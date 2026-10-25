-- ============================================================
-- ROADWATCH SUPABASE MIGRATION: 2 KM LOCATION-BASED VOTING RESTRICTION
-- ============================================================
-- Run this SQL script in the Supabase Dashboard -> SQL Editor
--
-- This migration implements a trusted server-side location-validation
-- RPC function that calculates the distance between the voter's GPS
-- location and the complaint's saved coordinates using the Haversine
-- formula. It strictly enforces the 2 km (2000 m) voting radius and
-- the one-vote-per-user-per-complaint rule.

-- 1. Ensure public.complaint_votes table exists with unique constraint
CREATE TABLE IF NOT EXISTS public.complaint_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    complaint_id TEXT NOT NULL,
    user_id UUID NOT NULL,
    vote TEXT NOT NULL CHECK (vote IN ('genuine', 'fake')),
    created_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT complaint_votes_unique_user_complaint UNIQUE (complaint_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_complaint_votes_complaint_id ON public.complaint_votes (complaint_id);
CREATE INDEX IF NOT EXISTS idx_complaint_votes_user_id ON public.complaint_votes (user_id);

ALTER TABLE public.complaint_votes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'complaint_votes' AND policyname = 'Allow all to read votes'
    ) THEN
        CREATE POLICY "Allow all to read votes"
            ON public.complaint_votes FOR SELECT
            TO authenticated, anon
            USING (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'complaint_votes' AND policyname = 'Allow authenticated users to insert their vote'
    ) THEN
        CREATE POLICY "Allow authenticated users to insert their vote"
            ON public.complaint_votes FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- 2. Trusted RPC Function: submit_vote_with_location
-- Validates caller authentication, vote type, user GPS coordinates,
-- calculates Haversine distance server-side, enforces 2 km restriction,
-- prevents duplicate voting, and inserts the vote atomically.
CREATE OR REPLACE FUNCTION public.submit_vote_with_location(
    p_complaint_id TEXT,
    p_vote TEXT,
    p_user_lat DOUBLE PRECISION,
    p_user_lng DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_report_lat DOUBLE PRECISION;
    v_report_lng DOUBLE PRECISION;
    v_report_status TEXT;
    v_progress_pct DOUBLE PRECISION;
    v_distance_meters DOUBLE PRECISION;
    v_clean_vote TEXT;
    v_existing_vote TEXT;
    c_p DOUBLE PRECISION := 0.017453292519943295; -- pi / 180
    v_a DOUBLE PRECISION;
BEGIN
    -- 1. Check authenticated user
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Authentication required to vote.'
        );
    END IF;

    -- 2. Validate vote option
    v_clean_vote := lower(trim(p_vote));
    IF v_clean_vote NOT IN ('genuine', 'fake') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invalid vote option. Must be genuine or fake.'
        );
    END IF;

    -- 3. Validate user GPS coordinates
    IF p_user_lat IS NULL OR p_user_lng IS NULL OR
       p_user_lat < -90.0 OR p_user_lat > 90.0 OR
       p_user_lng < -180.0 OR p_user_lng > 180.0 OR
       (p_user_lat = 0.0 AND p_user_lng = 0.0) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Valid current GPS location is required to vote.'
        );
    END IF;

    -- 4. Lookup complaint report coordinates and status from public.reports
    SELECT latitude, longitude, status, progress_percentage
    INTO v_report_lat, v_report_lng, v_report_status, v_progress_pct
    FROM public.reports
    WHERE id::text = trim(p_complaint_id)
       OR complaint_id = trim(p_complaint_id)
    LIMIT 1;

    IF v_report_lat IS NULL OR v_report_lng IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Complaint not found or complaint coordinates unavailable.'
        );
    END IF;

    -- 4b. Enforce closed voting on rejected complaints
    IF lower(trim(COALESCE(v_report_status, ''))) IN ('rejected', 'fake') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'This complaint was rejected as fake by the community. Voting is closed.',
            'voting_closed', true
        );
    END IF;

    -- 4c. Enforce closed voting once work has started or later
    IF lower(trim(COALESCE(v_report_status, ''))) IN ('work started', 'repair in progress', 'near completion', 'completed', 'repaired', 'resolved', 'closed')
       OR COALESCE(v_progress_pct, 0.0) >= 40.0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Voting closed — work has started.',
            'voting_closed', true
        );
    END IF;

    -- 5. Calculate Haversine distance in meters on the server
    v_a := 0.5 - cos((v_report_lat - p_user_lat) * c_p) / 2.0 +
           cos(p_user_lat * c_p) * cos(v_report_lat * c_p) *
           (1.0 - cos((v_report_lng - p_user_lng) * c_p)) / 2.0;
    v_distance_meters := 12742000.0 * asin(sqrt(v_a));

    -- 6. Enforce 2 km (2000 metres) voting restriction securely on server
    IF v_distance_meters > 2000.0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Voting is available only within 2 km of the reported issue.',
            'distance_meters', round(v_distance_meters::numeric, 1)
        );
    END IF;

    -- 7. Enforce one-vote-per-user-per-complaint rule
    SELECT vote INTO v_existing_vote
    FROM public.complaint_votes
    WHERE complaint_id = trim(p_complaint_id)
      AND user_id = v_user_id;

    IF v_existing_vote IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'You have already voted on this complaint.',
            'already_voted', true
        );
    END IF;

    -- 8. Record the vote in public.complaint_votes
    INSERT INTO public.complaint_votes (complaint_id, user_id, vote, created_at)
    VALUES (trim(p_complaint_id), v_user_id, v_clean_vote, now());

    -- 9. Optionally update aggregated vote counts in public.reports if columns exist
    BEGIN
        UPDATE public.reports
        SET 
            real_votes = (SELECT count(*) FROM public.complaint_votes WHERE complaint_id = trim(p_complaint_id) AND lower(vote) = 'genuine'),
            fake_votes = (SELECT count(*) FROM public.complaint_votes WHERE complaint_id = trim(p_complaint_id) AND lower(vote) = 'fake'),
            updated_at = now()
        WHERE id::text = trim(p_complaint_id)
           OR complaint_id = trim(p_complaint_id);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Vote recorded successfully.',
        'distance_meters', round(v_distance_meters::numeric, 1),
        'vote', v_clean_vote
    );
END;
$$;

-- 3. Grant execution permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.submit_vote_with_location(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, anon;
