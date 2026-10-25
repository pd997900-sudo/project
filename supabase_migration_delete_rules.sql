-- ============================================================
-- ROADWATCH SUPABASE MIGRATION: SECURE COMPLAINT DELETION RLS & POLICIES
-- ============================================================
-- Run this SQL in the Supabase Dashboard -> SQL Editor

-- 1. Ensure Row Level Security (RLS) is enabled on public.reports
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- 2. Drop any legacy or overly permissive delete policies on reports
DROP POLICY IF EXISTS "Allow authenticated users to delete unverified reports" ON public.reports;
DROP POLICY IF EXISTS "Allow public delete access on reports" ON public.reports;
DROP POLICY IF EXISTS "Allow authenticated users to delete reports" ON public.reports;
DROP POLICY IF EXISTS "Restrict delete on verified reports" ON public.reports;

-- 3. Create RLS Policy for DELETE on public.reports
-- Only allow deleting reports that are NOT verified by the community and NOT completed
CREATE POLICY "Allow authenticated users to delete unverified reports"
    ON public.reports
    FOR DELETE
    TO anon, authenticated
    USING (
        LOWER(COALESCE(status, 'submitted')) NOT IN ('verified', 'accepted', 'work started', 'repair in progress', 'near completion', 'completed')
        AND COALESCE(progress_percentage, 0) = 0
    );

-- 4. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
