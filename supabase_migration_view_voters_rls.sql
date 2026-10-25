-- ============================================================
-- ROADWATCH SUPABASE MIGRATION: VIEW VOTERS RLS & PROFILES POLICIES
-- ============================================================
-- Run this SQL in the Supabase Dashboard -> SQL Editor

-- 1. Create profiles table if it does not exist
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT,
    full_name TEXT,
    display_name TEXT,
    username TEXT,
    email TEXT,
    role TEXT DEFAULT 'reporter',
    phone TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure optional name columns exist if profiles table already existed
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT;

-- 2. Ensure complaint_votes table exists
CREATE TABLE IF NOT EXISTS public.complaint_votes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    complaint_id TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vote TEXT NOT NULL CHECK (vote IN ('genuine', 'fake')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT complaint_votes_complaint_user_unique UNIQUE (complaint_id, user_id)
);

-- 3. Create indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_complaint_votes_complaint_id 
    ON public.complaint_votes(complaint_id);

CREATE INDEX IF NOT EXISTS idx_profiles_id 
    ON public.profiles(id);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_votes ENABLE ROW LEVEL SECURITY;

-- 5. Grant PostgreSQL Table Permissions
GRANT SELECT, INSERT, UPDATE ON public.profiles TO anon, authenticated;
GRANT ALL ON TABLE public.profiles TO postgres, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.complaint_votes TO anon, authenticated;
GRANT ALL ON TABLE public.complaint_votes TO postgres, service_role;

-- 6. RLS Policies for public.profiles
DROP POLICY IF EXISTS "Allow authenticated users to read profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow public read access on profiles" ON public.profiles;

CREATE POLICY "Allow public read access on profiles"
    ON public.profiles
    FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "Allow users to insert/update own profile" ON public.profiles;
CREATE POLICY "Allow users to insert/update own profile"
    ON public.profiles
    FOR ALL
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- 7. RLS Policy for public.complaint_votes: Allow read access for voter list display
DROP POLICY IF EXISTS "Allow public read access on complaint_votes" ON public.complaint_votes;
DROP POLICY IF EXISTS "Allow authorized users to read complaint_votes" ON public.complaint_votes;

CREATE POLICY "Allow authorized users to read complaint_votes"
    ON public.complaint_votes
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 8. Allow authenticated users to insert, update, and delete only their own vote
DROP POLICY IF EXISTS "Allow authenticated users to insert their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to insert their own vote"
    ON public.complaint_votes
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow authenticated users to update their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to update their own vote"
    ON public.complaint_votes
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow authenticated users to delete their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to delete their own vote"
    ON public.complaint_votes
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- 9. Auto-sync existing auth.users into public.profiles with their actual names from raw_user_meta_data
INSERT INTO public.profiles (id, name, full_name, display_name, email, role, updated_at)
SELECT 
    id,
    COALESCE(
        NULLIF(TRIM(raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(raw_user_meta_data->>'display_name'), ''),
        NULLIF(TRIM(raw_user_meta_data->>'username'), '')
    ) AS name,
    COALESCE(NULLIF(TRIM(raw_user_meta_data->>'full_name'), ''), NULLIF(TRIM(raw_user_meta_data->>'name'), '')) AS full_name,
    COALESCE(NULLIF(TRIM(raw_user_meta_data->>'display_name'), ''), NULLIF(TRIM(raw_user_meta_data->>'name'), '')) AS display_name,
    email,
    COALESCE(NULLIF(raw_user_meta_data->>'role', ''), 'reporter') AS role,
    now()
FROM auth.users
ON CONFLICT (id) DO UPDATE SET
    name = COALESCE(EXCLUDED.name, public.profiles.name),
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    display_name = COALESCE(EXCLUDED.display_name, public.profiles.display_name),
    email = EXCLUDED.email;

-- 10. Trigger to automatically sync newly created or updated auth.users into public.profiles
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, name, full_name, display_name, email, role, updated_at)
    VALUES (
        NEW.id,
        COALESCE(
            NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
            NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
            NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), ''),
            NULLIF(TRIM(NEW.raw_user_meta_data->>'username'), '')
        ),
        COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''), NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), '')),
        COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), ''), NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), '')),
        NEW.email,
        COALESCE(NULLIF(NEW.raw_user_meta_data->>'role', ''), 'reporter'),
        now()
    )
    ON CONFLICT (id) DO UPDATE SET
        name = COALESCE(EXCLUDED.name, public.profiles.name),
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        display_name = COALESCE(EXCLUDED.display_name, public.profiles.display_name),
        email = EXCLUDED.email,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- 11. RPC Function: get_voter_display_names(voter_ids text[])
-- Securely retrieves display names for voter user IDs from user_profiles, profiles and auth metadata without exposing sensitive fields
CREATE OR REPLACE FUNCTION public.get_voter_display_names(voter_ids text[])
RETURNS TABLE (
    voter_id text,
    display_name text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vid AS voter_id,
        COALESCE(
            NULLIF(TRIM(up.full_name), ''),
            NULLIF(TRIM(p.full_name), ''),
            NULLIF(TRIM(p.name), ''),
            NULLIF(TRIM(p.display_name), ''),
            NULLIF(TRIM(p.username), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'name'), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'display_name'), ''),
            'Name not available'
        ) AS display_name
    FROM unnest(voter_ids) AS vid
    LEFT JOIN public.user_profiles up ON up.user_id::text = vid
    LEFT JOIN public.profiles p ON p.id::text = vid
    LEFT JOIN auth.users u ON u.id::text = vid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_voter_display_names(text[]) TO anon, authenticated;

-- 12. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
