-- ====================================================================
-- ROADWATCH SUPABASE MIGRATION: USER PROFILES & ROLE ISOLATION
-- Safe to run multiple times in Supabase SQL Editor (https://app.supabase.com)
-- ====================================================================

-- 1. Create public.user_profiles table (with user_id and role)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT DEFAULT 'reporter',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure role column exists if table already existed without it
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'reporter';

-- 2. Enable Row Level Security (RLS) on public.user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Policy 1: Allow any authenticated user to SELECT from user_profiles
DROP POLICY IF EXISTS "Allow authenticated read user_profiles" ON public.user_profiles;
CREATE POLICY "Allow authenticated read user_profiles"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (true);

-- Policy 2: Allow authenticated users to INSERT only their own profile row
DROP POLICY IF EXISTS "Allow individual insert user_profiles" ON public.user_profiles;
CREATE POLICY "Allow individual insert user_profiles"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Policy 3: Allow authenticated users to UPDATE only their own profile row
DROP POLICY IF EXISTS "Allow individual update user_profiles" ON public.user_profiles;
CREATE POLICY "Allow individual update user_profiles"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. Enable RLS on complaint_votes table (if present)
ALTER TABLE IF EXISTS public.complaint_votes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'complaint_votes') THEN
        DROP POLICY IF EXISTS "Allow authenticated read complaint_votes" ON public.complaint_votes;
        CREATE POLICY "Allow authenticated read complaint_votes"
        ON public.complaint_votes
        FOR SELECT
        TO authenticated
        USING (true);

        DROP POLICY IF EXISTS "Allow individual insert complaint_votes" ON public.complaint_votes;
        CREATE POLICY "Allow individual insert complaint_votes"
        ON public.complaint_votes
        FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 4. Backfill public.user_profiles with full_name and role from auth.users.raw_user_meta_data
INSERT INTO public.user_profiles (user_id, full_name, role)
SELECT 
    id AS user_id,
    COALESCE(
        NULLIF(TRIM(raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(raw_user_meta_data->>'display_name'), '')
    ) AS full_name,
    COALESCE(
        NULLIF(TRIM(raw_user_meta_data->>'role'), ''),
        'reporter'
    ) AS role
FROM auth.users
WHERE 
    id IS NOT NULL 
    AND (
        (raw_user_meta_data->>'full_name' IS NOT NULL AND TRIM(raw_user_meta_data->>'full_name') <> '')
        OR (raw_user_meta_data->>'name' IS NOT NULL AND TRIM(raw_user_meta_data->>'name') <> '')
        OR (raw_user_meta_data->>'display_name' IS NOT NULL AND TRIM(raw_user_meta_data->>'display_name') <> '')
    )
ON CONFLICT (user_id) DO UPDATE 
SET full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    updated_at = NOW();

-- 5. Trigger to automatically populate/update public.user_profiles when a user registers or updates metadata
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
DECLARE
    extracted_name TEXT;
    extracted_role TEXT;
BEGIN
    extracted_name := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), '')
    );
    extracted_role := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'role'), ''),
        'reporter'
    );

    IF extracted_name IS NOT NULL AND extracted_name <> '' THEN
        INSERT INTO public.user_profiles (user_id, full_name, role)
        VALUES (NEW.id, extracted_name, extracted_role)
        ON CONFLICT (user_id) DO UPDATE 
        SET full_name = EXCLUDED.full_name,
            role = EXCLUDED.role,
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- 6. RPC Function to check if an email is registered in auth.users or profiles (Security Definer)
CREATE OR REPLACE FUNCTION public.check_email_registered(search_email text)
RETURNS TABLE(is_registered boolean, user_role text) AS $$
DECLARE
    found_id uuid;
    found_role text;
BEGIN
    -- 1. Check auth.users directly
    SELECT id, COALESCE(raw_user_meta_data->>'role', '') INTO found_id, found_role
    FROM auth.users
    WHERE LOWER(email) = LOWER(search_email)
    LIMIT 1;

    IF found_id IS NOT NULL THEN
        IF found_role IS NULL OR found_role = '' THEN
            SELECT role INTO found_role FROM public.user_profiles WHERE user_id = found_id;
        END IF;
        IF found_role IS NULL OR found_role = '' THEN
            SELECT role INTO found_role FROM public.profiles WHERE id = found_id;
        END IF;
        
        RETURN QUERY SELECT true, LOWER(COALESCE(NULLIF(found_role, ''), 'reporter'));
        RETURN;
    END IF;

    -- 2. Check profiles table by email
    SELECT role INTO found_role
    FROM public.profiles
    WHERE LOWER(email) = LOWER(search_email)
    LIMIT 1;

    IF found_role IS NOT NULL THEN
        RETURN QUERY SELECT true, LOWER(found_role);
        RETURN;
    END IF;

    RETURN QUERY SELECT false, ''::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.check_email_registered(text) TO anon, authenticated;

-- 7. RPC Function for secure batch voter display name lookup
CREATE OR REPLACE FUNCTION public.get_voter_display_names(voter_ids text[])
RETURNS TABLE(voter_id text, display_name text) AS $$
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

-- 8. Identification & Verification Query
-- Run this query in Supabase SQL Editor to verify synchronized profiles and role statuses:
-- SELECT 
--     u.id AS auth_user_id, 
--     u.email, 
--     u.created_at, 
--     u.raw_user_meta_data->>'role' AS metadata_role,
--     up.full_name AS synchronized_full_name,
--     up.role AS synchronized_role,
--     CASE 
--         WHEN up.full_name IS NOT NULL THEN 'Synchronized' 
--         ELSE 'Missing Name in Metadata' 
--     END AS sync_status
-- FROM auth.users u 
-- LEFT JOIN public.user_profiles up ON u.id = up.user_id;
