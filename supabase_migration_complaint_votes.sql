-- ============================================================
-- ROADWATCH SUPABASE MIGRATION: PERSISTENT COMPLAINT VOTES TABLE
-- ============================================================
-- Run this SQL in the Supabase Dashboard -> SQL Editor

-- 1. Create table complaint_votes
CREATE TABLE IF NOT EXISTS public.complaint_votes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    complaint_id TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vote TEXT NOT NULL CHECK (vote IN ('genuine', 'fake')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT complaint_votes_complaint_user_unique UNIQUE (complaint_id, user_id)
);

-- Safe cleanup of any legacy duplicate vote rows (preserves the latest legitimate vote per user per complaint):
DELETE FROM public.complaint_votes a
USING public.complaint_votes b
WHERE a.complaint_id = b.complaint_id 
  AND a.user_id = b.user_id 
  AND a.created_at < b.created_at;

-- 2. Create index for fast lookup of votes by complaint_id
CREATE INDEX IF NOT EXISTS idx_complaint_votes_complaint_id 
    ON public.complaint_votes(complaint_id);

-- 3. Grant PostgreSQL Table Permissions to anon and authenticated roles (Resolves "permission denied for table complaint_votes")
GRANT SELECT, INSERT, UPDATE, DELETE ON public.complaint_votes TO anon, authenticated;
GRANT ALL ON TABLE public.complaint_votes TO postgres, service_role;

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.complaint_votes ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policy: Allow reading votes to display totals and user status
DROP POLICY IF EXISTS "Allow public read access on complaint_votes" ON public.complaint_votes;
CREATE POLICY "Allow public read access on complaint_votes"
    ON public.complaint_votes
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 6. RLS Policy: Allow authenticated users to insert only their own vote
DROP POLICY IF EXISTS "Allow authenticated users to insert their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to insert their own vote"
    ON public.complaint_votes
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 7. RLS Policy: Allow authenticated users to update only their own vote
DROP POLICY IF EXISTS "Allow authenticated users to update their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to update their own vote"
    ON public.complaint_votes
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 8. RLS Policy: Allow authenticated users to delete their own vote
DROP POLICY IF EXISTS "Allow authenticated users to delete their own vote" ON public.complaint_votes;
CREATE POLICY "Allow authenticated users to delete their own vote"
    ON public.complaint_votes
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);
