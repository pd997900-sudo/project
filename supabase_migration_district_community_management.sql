-- ====================================================================
-- ROADWATCH SUPABASE MIGRATION: DISTRICT-WISE COMMUNITY MANAGEMENT SYSTEM
-- Fully safe, idempotent, backward-compatible migration for:
-- 1. India-Level Admin
-- 2. District-Wise Community Users (Assigned State & District)
-- 3. Local Repair Teams (Assigned to Districts & Complaints)
-- 4. Location-Based Complaint Assignment (State, District, Locality)
-- ====================================================================

-- 1. Ensure columns on public.user_profiles
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS state TEXT DEFAULT 'Tamil Nadu';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS district TEXT DEFAULT 'Kanchipuram';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS repair_team_id UUID;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS phone TEXT;

-- Index for district lookup
CREATE INDEX IF NOT EXISTS idx_user_profiles_district ON public.user_profiles(state, district);
CREATE INDEX IF NOT EXISTS idx_user_profiles_role ON public.user_profiles(role);

-- 2. Create public.repair_teams table
CREATE TABLE IF NOT EXISTS public.repair_teams (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'Tamil Nadu',
    district TEXT NOT NULL DEFAULT 'Kanchipuram',
    specialization TEXT DEFAULT 'Pothole Patching & Asphalt Repair',
    lead_name TEXT,
    contact_phone TEXT,
    contact_email TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indices for repair_teams
CREATE INDEX IF NOT EXISTS idx_repair_teams_district ON public.repair_teams(state, district);
CREATE INDEX IF NOT EXISTS idx_repair_teams_active ON public.repair_teams(is_active);

-- Seed initial repair teams across districts if none exist
INSERT INTO public.repair_teams (id, name, state, district, specialization, lead_name, contact_phone, contact_email)
VALUES 
    ('a0000001-0000-0000-0000-000000000001', 'Kanchipuram Rapid Pothole Squad', 'Tamil Nadu', 'Kanchipuram', 'Pothole Patching & Asphalt Repair', 'R. Murugan', '+91 98401 22345', 'kanchi.repair@roadwatch.org'),
    ('a0000002-0000-0000-0000-000000000002', 'Sriperumbudur Highway Maintenance Unit', 'Tamil Nadu', 'Kanchipuram', 'Heavy Road & Highway Repairs', 'K. Saravanan', '+91 98402 33456', 'sriperumbudur.highway@roadwatch.org'),
    ('a0000003-0000-0000-0000-000000000003', 'Chennai Central Quick-Fix Road Crew', 'Tamil Nadu', 'Chennai', 'Urban Pothole & Surface Leveling', 'S. Arumugam', '+91 98403 44567', 'chennai.roadfix@roadwatch.org'),
    ('a0000004-0000-0000-0000-000000000004', 'Tiruvallur Road & Drainage Brigade', 'Tamil Nadu', 'Tiruvallur', 'Drainage, Potholes & Shoulder Works', 'V. Natarajan', '+91 98404 55678', 'tiruvallur.repair@roadwatch.org'),
    ('a0000005-0000-0000-0000-000000000005', 'Bengaluru Urban Asphalt Response Team', 'Karnataka', 'Bengaluru Urban', 'Asphalt Patching & Water-logged Roads', 'M. Venkatesh', '+91 98801 66789', 'bengaluru.asphalt@roadwatch.org'),
    ('a0000006-0000-0000-0000-000000000006', 'Mumbai Metro Pothole Action Squad', 'Maharashtra', 'Mumbai City', 'Monsoon Pothole Repair & Cold Mix', 'P. Shinde', '+91 98201 77890', 'mumbai.pothole@roadwatch.org')
ON CONFLICT (id) DO NOTHING;

-- 3. Ensure columns on public.reports for location & repair-team assignment
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS state TEXT DEFAULT 'Tamil Nadu';
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS district TEXT DEFAULT 'Kanchipuram';
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS repair_team_id UUID;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS repair_team_name TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS assigned_to_repair_team_at TIMESTAMPTZ;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS assigned_by_user_id TEXT;

-- Indices on reports for high-performance district and team queries
CREATE INDEX IF NOT EXISTS idx_reports_state_district ON public.reports(state, district);
CREATE INDEX IF NOT EXISTS idx_reports_repair_team ON public.reports(repair_team_id);

-- 4. Backfill existing reports with intelligent district detection
UPDATE public.reports
SET state = 'Tamil Nadu',
    district = 'Kanchipuram',
    city = 'Sriperumbudur'
WHERE (district IS NULL OR district = '')
  AND (
      address ILIKE '%mevalurkuppam%'
      OR address ILIKE '%sriperumbudur%'
      OR address ILIKE '%saveetha%'
      OR address ILIKE '%kanchipuram%'
      OR address ILIKE '%kancheepuram%'
      OR (latitude >= 12.80 AND latitude <= 13.20 AND longitude >= 79.70 AND longitude <= 80.15)
  );

UPDATE public.reports
SET state = 'Tamil Nadu',
    district = 'Chennai',
    city = 'Chennai'
WHERE (district IS NULL OR district = '')
  AND (
      address ILIKE '%chennai%'
      OR address ILIKE '%guindy%'
      OR address ILIKE '%t nagar%'
      OR address ILIKE '%velachery%'
      OR (latitude >= 12.95 AND latitude <= 13.25 AND longitude >= 80.15 AND longitude <= 80.35)
  );

UPDATE public.reports
SET state = 'Tamil Nadu',
    district = 'Tiruvallur',
    city = 'Tiruvallur'
WHERE (district IS NULL OR district = '')
  AND (
      address ILIKE '%tiruvallur%'
      OR address ILIKE '%avadi%'
      OR address ILIKE '%poonamallee%'
  );

-- Default any remaining unassigned reports safely
UPDATE public.reports
SET state = COALESCE(state, 'Tamil Nadu'),
    district = COALESCE(district, 'Kanchipuram')
WHERE district IS NULL OR district = '';

-- Backfill Community users with Kanchipuram default if unassigned
UPDATE public.user_profiles
SET state = 'Tamil Nadu',
    district = 'Kanchipuram'
WHERE role = 'community' AND (district IS NULL OR district = '');

-- 5. Updated handle_new_user_profile trigger with state & district preservation
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    extracted_name TEXT;
    extracted_role TEXT;
    extracted_state TEXT;
    extracted_district TEXT;
    extracted_phone TEXT;
    extracted_repair_team_id UUID;
BEGIN
    extracted_name := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), '')
    );
    extracted_role := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'role'), ''), 'reporter');
    extracted_state := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'state'), ''), 'Tamil Nadu');
    extracted_district := COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data->>'district'), ''), 'Kanchipuram');
    extracted_phone := NULLIF(TRIM(COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone')), '');
    
    BEGIN
        extracted_repair_team_id := (NEW.raw_user_meta_data->>'repair_team_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
        extracted_repair_team_id := NULL;
    END;

    IF extracted_name IS NOT NULL AND extracted_name <> '' THEN
        INSERT INTO public.user_profiles (
            user_id, full_name, role, state, district, phone, email, repair_team_id, updated_at
        )
        VALUES (
            NEW.id,
            extracted_name,
            extracted_role,
            extracted_state,
            extracted_district,
            extracted_phone,
            NEW.email,
            extracted_repair_team_id,
            NOW()
        )
        ON CONFLICT (user_id) DO UPDATE 
        SET full_name = EXCLUDED.full_name,
            role = COALESCE(EXCLUDED.role, public.user_profiles.role),
            state = COALESCE(public.user_profiles.state, EXCLUDED.state),
            district = COALESCE(public.user_profiles.district, EXCLUDED.district),
            phone = COALESCE(EXCLUDED.phone, public.user_profiles.phone),
            email = COALESCE(EXCLUDED.email, public.user_profiles.email),
            repair_team_id = COALESCE(EXCLUDED.repair_team_id, public.user_profiles.repair_team_id),
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- 6. Permissions and Row Level Security
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.repair_teams TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reports TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;

ALTER TABLE public.repair_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Policies for repair_teams
DROP POLICY IF EXISTS "Allow read repair_teams" ON public.repair_teams;
CREATE POLICY "Allow read repair_teams"
ON public.repair_teams FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "Allow insert repair_teams" ON public.repair_teams;
CREATE POLICY "Allow insert repair_teams"
ON public.repair_teams FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Allow update repair_teams" ON public.repair_teams;
CREATE POLICY "Allow update repair_teams"
ON public.repair_teams FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- Ensure public.reports RLS allows updates across admin, district community, and repair teams
DROP POLICY IF EXISTS "Allow update on reports" ON public.reports;
CREATE POLICY "Allow update on reports"
ON public.reports FOR UPDATE
TO anon, authenticated
USING (true)
WITH CHECK (true);

-- Allow authenticated users and admins to update user_profiles (for district assignment and activation)
DROP POLICY IF EXISTS "Allow update user_profiles" ON public.user_profiles;
CREATE POLICY "Allow update user_profiles"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- 7. Security Definer RPC: Assign district to Community User
CREATE OR REPLACE FUNCTION public.assign_community_user_district(
    target_user_id UUID,
    new_state TEXT,
    new_district TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.user_profiles
    SET state = new_state,
        district = new_district,
        updated_at = NOW()
    WHERE user_id = target_user_id;

    -- Also update auth metadata if permissible
    UPDATE auth.users
    SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || 
        jsonb_build_object('state', new_state, 'district', new_district)
    WHERE id = target_user_id;

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_community_user_district(UUID, TEXT, TEXT) TO authenticated, anon;

-- 8. Security Definer RPC: Set user active/inactive status
CREATE OR REPLACE FUNCTION public.set_user_active_status(
    target_user_id UUID,
    active_status BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.user_profiles
    SET is_active = active_status,
        updated_at = NOW()
    WHERE user_id = target_user_id;

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_user_active_status(UUID, BOOLEAN) TO authenticated, anon;

-- 9. Security Definer RPC: Assign complaint to Repair Team
CREATE OR REPLACE FUNCTION public.assign_complaint_to_repair_team(
    target_complaint_id TEXT,
    target_team_id UUID,
    team_name TEXT,
    assigned_by TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.reports
    SET repair_team_id = target_team_id,
        repair_team_name = team_name,
        assigned_by_user_id = assigned_by,
        assigned_to_repair_team_at = NOW(),
        status = CASE 
            WHEN LOWER(status) = 'submitted' THEN 'Accepted'
            WHEN LOWER(status) = 'under verification' THEN 'Accepted'
            WHEN LOWER(status) = 'verified' THEN 'Accepted'
            ELSE status
        END,
        updated_at = NOW()
    WHERE id::text = target_complaint_id 
       OR complaint_id = target_complaint_id;

    RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_complaint_to_repair_team(TEXT, UUID, TEXT, TEXT) TO authenticated, anon;

-- Notify schema reload
NOTIFY pgrst, 'reload schema';

