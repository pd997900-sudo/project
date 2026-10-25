-- ============================================================
-- ROADWATCH SUPABASE MIGRATION: PROGRESS UPDATES & REPORTS SCHEMA
-- ============================================================
-- Run this SQL in the Supabase Dashboard -> SQL Editor

-- 1. Create progress_updates table if it does not exist
CREATE TABLE IF NOT EXISTS public.progress_updates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    update_id TEXT,
    complaint_id TEXT NOT NULL,
    community_user_id TEXT,
    community_user_name TEXT,
    progress_note TEXT,
    image_url TEXT,
    work_percentage DOUBLE PRECISION DEFAULT 0.0,
    status TEXT DEFAULT 'In Progress',
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    address TEXT,
    captured_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE public.progress_updates ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.progress_updates ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.progress_updates ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.progress_updates ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ;

-- 2. Ensure all required columns exist on public.reports table
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS progress_percentage DOUBLE PRECISION DEFAULT 0.0;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS updates JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS after_image_url TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS completion_notes TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS community_user_id TEXT;
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS community_user_name TEXT;

-- 3. Create index for fast lookup by complaint_id
CREATE INDEX IF NOT EXISTS idx_progress_updates_complaint_id 
    ON public.progress_updates(complaint_id);

CREATE INDEX IF NOT EXISTS idx_reports_complaint_id 
    ON public.reports(complaint_id);

-- 4. Grant PostgreSQL Table Permissions to anon and authenticated roles
GRANT SELECT, INSERT, UPDATE, DELETE ON public.progress_updates TO anon, authenticated;
GRANT ALL ON TABLE public.progress_updates TO postgres, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.reports TO anon, authenticated;
GRANT ALL ON TABLE public.reports TO postgres, service_role;

-- 5. Enable Row Level Security (RLS)
ALTER TABLE public.progress_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies for progress_updates
DROP POLICY IF EXISTS "Allow public read access on progress_updates" ON public.progress_updates;
CREATE POLICY "Allow public read access on progress_updates"
    ON public.progress_updates
    FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "Allow authenticated users to insert progress_updates" ON public.progress_updates;
CREATE POLICY "Allow authenticated users to insert progress_updates"
    ON public.progress_updates
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to update progress_updates" ON public.progress_updates;
CREATE POLICY "Allow authenticated users to update progress_updates"
    ON public.progress_updates
    FOR UPDATE
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 7. RLS Policies for reports
DROP POLICY IF EXISTS "Allow public read access on reports" ON public.reports;
CREATE POLICY "Allow public read access on reports"
    ON public.reports
    FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "Allow authenticated users to insert reports" ON public.reports;
CREATE POLICY "Allow authenticated users to insert reports"
    ON public.reports
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to update reports" ON public.reports;
CREATE POLICY "Allow authenticated users to update reports"
    ON public.reports
    FOR UPDATE
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

-- 8. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

