-- ====================================================================
-- ROADWATCH SUPABASE MIGRATION: SECURE PROGRESS UPDATE DELETION RLS & STORAGE
-- ====================================================================
-- REVIEW BEFORE APPLYING. DO NOT RUN AUTOMATICALLY.
-- Run manually in the Supabase Dashboard -> SQL Editor (https://app.supabase.com)
--
-- Security Specifications:
-- 1. Strictly authenticated users only (TO authenticated). Zero anonymous access.
-- 2. Requires auth.uid() IS NOT NULL.
-- 3. Authorization: Caller must be the creator (community_user_id = auth.uid()::text)
--    OR an administrator via trusted JWT metadata:
--    ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin' OR (auth.jwt() ->> 'role') = 'admin').
-- 4. No references to nonexistent columns (e.g., user_profiles.role is NOT referenced).
-- 5. Completed complaints are strictly protected: deletion is blocked if the associated
--    complaint in public.reports is marked as 'completed'.
-- 6. Storage deletion in 'roadwatch-reports' bucket is strictly scoped to the user's own
--    progress photo path: '<auth.uid()>/progress_photos/%'. Non-progress photos, shared
--    complaint images, avatars, and other user folders cannot be deleted.
-- ====================================================================

-- 1. Ensure Row Level Security (RLS) is enabled on public.progress_updates
ALTER TABLE public.progress_updates ENABLE ROW LEVEL SECURITY;

-- 2. Revoke any DELETE permissions on public.progress_updates from anon
REVOKE DELETE ON TABLE public.progress_updates FROM anon;
GRANT DELETE ON TABLE public.progress_updates TO authenticated;

-- 3. Drop all previous DELETE policies on progress_updates
DROP POLICY IF EXISTS "Allow authorized users to delete progress_updates" ON public.progress_updates;
DROP POLICY IF EXISTS "Allow creator or admin to delete progress_updates" ON public.progress_updates;
DROP POLICY IF EXISTS "Allow public delete access on progress_updates" ON public.progress_updates;

-- 4. Create hardened DELETE RLS Policy on public.progress_updates
CREATE POLICY "Allow creator or admin to delete progress_updates"
    ON public.progress_updates
    FOR DELETE
    TO authenticated
    USING (
        auth.uid() IS NOT NULL
        AND (
            -- User is the creator who submitted this specific progress update
            community_user_id = auth.uid()::text
            -- OR User is an administrator according to trusted Supabase Auth JWT metadata
            OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
            OR (auth.jwt() ->> 'role') = 'admin'
        )
        -- Prevent deleting progress updates on completed complaints
        AND NOT EXISTS (
            SELECT 1 FROM public.reports r
            WHERE (
                r.complaint_id = progress_updates.complaint_id
                OR r.id::text = progress_updates.complaint_id
            )
            AND LOWER(COALESCE(r.status, '')) = 'completed'
        )
    );

-- 5. Create hardened Storage Object DELETE policy for roadwatch-reports bucket
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        DROP POLICY IF EXISTS "Allow creator or admin to delete progress photos" ON storage.objects;
        CREATE POLICY "Allow creator or admin to delete progress photos"
            ON storage.objects
            FOR DELETE
            TO authenticated
            USING (
                bucket_id = 'roadwatch-reports'
                AND auth.uid() IS NOT NULL
                AND (
                    -- Creator can ONLY delete objects inside their own progress_photos folder
                    name LIKE (auth.uid()::text || '/progress_photos/%')
                    -- Administrator can delete progress photos across folders if needed
                    OR (
                        (
                            (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
                            OR (auth.jwt() ->> 'role') = 'admin'
                        )
                        AND name LIKE '%/progress_photos/%'
                    )
                )
            );
    END IF;
END $$;

-- 6. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
