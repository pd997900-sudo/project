-- ====================================================================
-- ROADWATCH SAFE AUTH ROLE MIGRATION & PRIVACY-STRICT SECURITY SCRIPT
-- Safe to run in Supabase SQL Editor (https://app.supabase.com)
--
-- Target Accounts:
-- 1. dindupuji04@gmail.com (UUID: 88deb318-8c4b-48fd-8915-52fbc04ed6dd) -> role: 'reporter'
-- 2. dpuji0408@gmail.com  (UUID: 63543ee0-b295-46dd-8493-5b946edead4e) -> role: 'community'
-- ====================================================================

-- 1. Ensure public.user_profiles schema
CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Safely add role column if it does not exist yet (without default fallback)
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS role TEXT;

-- 2. Least-privilege schema and table grants (Restricted to authenticated users only - No public/anonymous access)
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;
REVOKE ALL ON TABLE public.user_profiles FROM anon;

-- 3. Enable RLS and define strict security policies
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Drop any previous anonymous access policy to guarantee zero public disclosure
DROP POLICY IF EXISTS "Allow anon read user_profiles" ON public.user_profiles;

DROP POLICY IF EXISTS "Allow authenticated read user_profiles" ON public.user_profiles;
CREATE POLICY "Allow authenticated read user_profiles"
ON public.user_profiles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow individual insert user_profiles" ON public.user_profiles;
CREATE POLICY "Allow individual insert user_profiles"
ON public.user_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow individual update user_profiles" ON public.user_profiles;
CREATE POLICY "Allow individual update user_profiles"
ON public.user_profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 4. Update auth.users.raw_user_meta_data using exact UUIDs (Preserves all other metadata)
-- Reporter Account: 88deb318-8c4b-48fd-8915-52fbc04ed6dd (dindupuji04@gmail.com)
UPDATE auth.users
SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'reporter')
WHERE id = '88deb318-8c4b-48fd-8915-52fbc04ed6dd';

-- Community Account: 63543ee0-b295-46dd-8493-5b946edead4e (dpuji0408@gmail.com)
UPDATE auth.users
SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'community')
WHERE id = '63543ee0-b295-46dd-8493-5b946edead4e';

-- 5. Synchronize public.user_profiles table records
INSERT INTO public.user_profiles (user_id, full_name, role, updated_at)
VALUES ('88deb318-8c4b-48fd-8915-52fbc04ed6dd', 'pujitha', 'reporter', NOW())
ON CONFLICT (user_id) DO UPDATE SET role = 'reporter', updated_at = NOW();

INSERT INTO public.user_profiles (user_id, full_name, role, updated_at)
VALUES ('63543ee0-b295-46dd-8493-5b946edead4e', 'lakshmi', 'community', NOW())
ON CONFLICT (user_id) DO UPDATE SET role = 'community', updated_at = NOW();

-- 6. Trigger to populate/update public.user_profiles without silent role defaults
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    extracted_name TEXT;
    extracted_role TEXT;
BEGIN
    extracted_name := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), '')
    );
    extracted_role := NULLIF(TRIM(NEW.raw_user_meta_data->>'role'), '');

    IF extracted_name IS NOT NULL AND extracted_name <> '' THEN
        INSERT INTO public.user_profiles (user_id, full_name, role, updated_at)
        VALUES (NEW.id, extracted_name, extracted_role, NOW())
        ON CONFLICT (user_id) DO UPDATE 
        SET full_name = EXCLUDED.full_name,
            role = COALESCE(EXCLUDED.role, public.user_profiles.role),
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- 7. Security Definer RPC check_email_registered (Restricted to authenticated users)
CREATE OR REPLACE FUNCTION public.check_email_registered(search_email text)
RETURNS TABLE(is_registered boolean, user_role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    found_id uuid;
    found_role text;
BEGIN
    SELECT id, NULLIF(TRIM(raw_user_meta_data->>'role'), '') INTO found_id, found_role
    FROM auth.users
    WHERE LOWER(email) = LOWER(TRIM(search_email))
    LIMIT 1;

    IF found_id IS NOT NULL THEN
        IF found_role IS NULL THEN
            SELECT NULLIF(TRIM(role), '') INTO found_role FROM public.user_profiles WHERE user_id = found_id;
        END IF;
        
        -- Returns actual found role without silent default fallback
        RETURN QUERY SELECT true, LOWER(found_role);
        RETURN;
    END IF;

    RETURN QUERY SELECT false, NULL::text;
END;
$$;

REVOKE ALL ON FUNCTION public.check_email_registered(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_email_registered(text) TO authenticated;

-- 8. RPC Function get_voter_display_names (Restricted to authenticated users)
CREATE OR REPLACE FUNCTION public.get_voter_display_names(voter_ids text[])
RETURNS TABLE(voter_id text, display_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vid AS voter_id,
        COALESCE(
            NULLIF(TRIM(up.full_name), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'full_name'), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'name'), ''),
            NULLIF(TRIM(u.raw_user_meta_data->>'display_name'), ''),
            'Name not available'
        ) AS display_name
    FROM unnest(voter_ids) AS vid
    LEFT JOIN public.user_profiles up ON up.user_id::text = vid
    LEFT JOIN auth.users u ON u.id::text = vid;
END;
$$;

REVOKE ALL ON FUNCTION public.get_voter_display_names(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_voter_display_names(text[]) TO authenticated;

-- 9. Verification Query
SELECT 
    u.id AS user_id, 
    u.email, 
    u.raw_user_meta_data->>'role' AS auth_metadata_role, 
    up.role AS user_profiles_role, 
    up.full_name AS profile_name
FROM auth.users u
LEFT JOIN public.user_profiles up ON u.id = up.user_id
WHERE u.id IN ('88deb318-8c4b-48fd-8915-52fbc04ed6dd', '63543ee0-b295-46dd-8493-5b946edead4e');
