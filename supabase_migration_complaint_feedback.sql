-- ====================================================================
-- ROADWATCH SUPABASE MIGRATION: DEDICATED COMPLAINT FEEDBACK TABLE
-- ====================================================================
-- Target Supabase Project: rblhbjmenbghvacljjwv
-- Execute ONCE in Supabase Dashboard -> SQL Editor:
-- https://supabase.com/dashboard/project/rblhbjmenbghvacljjwv/sql
-- ====================================================================
-- Confirmed Database Schema Facts:
-- 1. public.reports.id is UUID
-- 2. public.reports.user_id is TEXT
-- 3. public.reports does NOT have a title column
-- 4. public.complaint_feedback allows each authenticated reporter
--    to submit rating & comment per completed complaint
-- ====================================================================

-- 1. Create dedicated public.complaint_feedback table
CREATE TABLE IF NOT EXISTS public.complaint_feedback (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    feedback_id TEXT,
    complaint_id UUID NOT NULL REFERENCES public.reports(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reporter_name TEXT,
    rating DOUBLE PRECISION NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
    comments TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT complaint_feedback_complaint_reporter_unique UNIQUE (complaint_id, reporter_id)
);

-- 2. Ensure all columns exist (in case a partial table existed)
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS feedback_id TEXT;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS complaint_id UUID;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS reporter_id UUID;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS reporter_name TEXT;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS rating DOUBLE PRECISION;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS comments TEXT;
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.complaint_feedback ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 3. Idempotently enforce constraints (rating 1-5, unique (complaint_id, reporter_id), FKs)
DO $$
BEGIN
    -- Check constraint for rating (1.0 to 5.0 stars)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.complaint_feedback'::regclass 
          AND contype = 'c'
          AND pg_get_constraintdef(oid) LIKE '%rating%'
    ) THEN
        ALTER TABLE public.complaint_feedback 
        ADD CONSTRAINT complaint_feedback_rating_check 
        CHECK (rating >= 1.0 AND rating <= 5.0);
    END IF;

    -- Drop legacy single-column unique constraint if present
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.complaint_feedback'::regclass 
          AND contype = 'u'
          AND conname = 'complaint_feedback_complaint_id_key'
    ) THEN
        ALTER TABLE public.complaint_feedback 
        DROP CONSTRAINT complaint_feedback_complaint_id_key;
    END IF;

    -- Composite unique constraint: Exactly one feedback per (complaint_id, reporter_id)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.complaint_feedback'::regclass 
          AND contype = 'u'
          AND conname = 'complaint_feedback_complaint_reporter_unique'
    ) THEN
        ALTER TABLE public.complaint_feedback 
        ADD CONSTRAINT complaint_feedback_complaint_reporter_unique 
        UNIQUE (complaint_id, reporter_id);
    END IF;

    -- Foreign key to public.reports(id) with CASCADE on delete
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.complaint_feedback'::regclass 
          AND contype = 'f'
          AND confrelid = 'public.reports'::regclass
    ) THEN
        ALTER TABLE public.complaint_feedback 
        ADD CONSTRAINT complaint_feedback_complaint_id_fkey 
        FOREIGN KEY (complaint_id) REFERENCES public.reports(id) ON DELETE CASCADE;
    END IF;

    -- Foreign key to auth.users(id) with CASCADE on delete
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.complaint_feedback'::regclass 
          AND contype = 'f'
          AND confrelid = 'auth.users'::regclass
    ) THEN
        ALTER TABLE public.complaint_feedback 
        ADD CONSTRAINT complaint_feedback_reporter_id_fkey 
        FOREIGN KEY (reporter_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- 4. Create performance indexes
CREATE INDEX IF NOT EXISTS idx_complaint_feedback_complaint_id 
    ON public.complaint_feedback(complaint_id);

CREATE INDEX IF NOT EXISTS idx_complaint_feedback_reporter_id 
    ON public.complaint_feedback(reporter_id);

CREATE INDEX IF NOT EXISTS idx_complaint_feedback_complaint_reporter 
    ON public.complaint_feedback(complaint_id, reporter_id);

-- 5. Restrict Table Grants (Least-privilege: zero anonymous access)
REVOKE ALL ON TABLE public.complaint_feedback FROM anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.complaint_feedback TO authenticated;
GRANT ALL ON TABLE public.complaint_feedback TO postgres, service_role;

-- 6. Enable Row Level Security (RLS)
ALTER TABLE public.complaint_feedback ENABLE ROW LEVEL SECURITY;

-- 7. Strict Authenticated RLS Policies

-- Policy 1: Authenticated users can read feedback
DROP POLICY IF EXISTS "Allow authenticated read on complaint_feedback" ON public.complaint_feedback;
DROP POLICY IF EXISTS "Allow public read access on complaint_feedback" ON public.complaint_feedback;
CREATE POLICY "Allow authenticated read on complaint_feedback"
    ON public.complaint_feedback
    FOR SELECT
    TO authenticated
    USING (auth.uid() IS NOT NULL);

-- Policy 2: Any authenticated reporter can submit feedback for an existing complaint with reporter_id = auth.uid()
DROP POLICY IF EXISTS "Allow authenticated reporters to insert feedback" ON public.complaint_feedback;
DROP POLICY IF EXISTS "Allow users to insert complaint_feedback" ON public.complaint_feedback;
DROP POLICY IF EXISTS "Allow authenticated users to insert own feedback" ON public.complaint_feedback;
CREATE POLICY "Allow authenticated reporters to insert feedback"
    ON public.complaint_feedback
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND reporter_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.reports r
            WHERE r.id = complaint_feedback.complaint_id
        )
    );

-- Policy 3: Authenticated reporters may update their own feedback
DROP POLICY IF EXISTS "Allow authenticated reporters to update own feedback" ON public.complaint_feedback;
DROP POLICY IF EXISTS "Allow users to update complaint_feedback" ON public.complaint_feedback;
DROP POLICY IF EXISTS "Allow authenticated users to update own feedback" ON public.complaint_feedback;
CREATE POLICY "Allow authenticated reporters to update own feedback"
    ON public.complaint_feedback
    FOR UPDATE
    TO authenticated
    USING (
        auth.uid() IS NOT NULL
        AND reporter_id = auth.uid()
    )
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND reporter_id = auth.uid()
    );

-- 8. Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';

