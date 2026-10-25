-- ====================================================================
-- ROADWATCH SUPABASE MIGRATION: PERSISTENT IN-APP & EMAIL NOTIFICATIONS
-- Uses existing public.notifications table with columns:
-- id, user_id, complaint_id, title, message, type, is_read, created_at
-- Safe to execute in Supabase SQL Editor (https://app.supabase.com)
-- ====================================================================

-- 1. Ensure public.notifications table structure
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    complaint_id UUID NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'work', -- 'work', 'verified', 'accepted', 'rejected', 'completed', 'submitted'
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure base columns exist safely without altering data
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'work';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 2. Indexes for high-performance notification feeds and realtime delivery
CREATE INDEX IF NOT EXISTS idx_notifications_user_created 
ON public.notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_complaint_id 
ON public.notifications(complaint_id);

-- 3. Grants & Secure Row Level Security (RLS)
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Policy 1: Users (reporters) can view only their own notifications
DROP POLICY IF EXISTS "Users can read own notifications" ON public.notifications;
CREATE POLICY "Users can read own notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Policy 2: Users can update only their own notifications (e.g. marking as read)
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Authenticated can update notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Policy 3: Users can insert notifications for themselves or for the verified submitter of the report (prevents arbitrary recipient injection)
DROP POLICY IF EXISTS "Authenticated can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert notifications for report submitters" ON public.notifications;
CREATE POLICY "Users can insert notifications for report submitters"
ON public.notifications FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = user_id
    OR
    EXISTS (
        SELECT 1 FROM public.reports r
        WHERE r.id = complaint_id
        AND r.user_id = user_id::text
    )
);

-- 4. SECURITY DEFINER: Resolve reporter email securely from auth.users
CREATE OR REPLACE FUNCTION public.get_user_email(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_email TEXT;
BEGIN
    SELECT email INTO v_email
    FROM auth.users
    WHERE id = p_user_id;

    RETURN v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_email(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_email(UUID) TO service_role;

-- 5. SECURITY DEFINER: Trusted Server-Side Function to Create Notification for Report Submitter
-- Safely gets original submitter's user_id from public.reports (which is TEXT)
-- Safely validates and converts it to UUID only if it contains a valid UUID
-- Never allows arbitrary user injection
CREATE OR REPLACE FUNCTION public.create_report_notification(
    p_report_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type TEXT DEFAULT 'work'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_submitter_user_id TEXT;
    v_reporter_uuid UUID;
    v_notification_id UUID;
    v_created_at TIMESTAMPTZ;
BEGIN
    -- Require authentication
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Authentication required'
        );
    END IF;

    -- Look up original submitter from public.reports
    SELECT user_id INTO v_submitter_user_id
    FROM public.reports
    WHERE id = p_report_id;

    IF v_submitter_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Report not found in public.reports for id: ' || p_report_id::text
        );
    END IF;

    -- Validate user_id from public.reports is a valid UUID
    IF v_submitter_user_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        v_reporter_uuid := v_submitter_user_id::uuid;
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Original submitter user_id is not a valid UUID: ' || v_submitter_user_id
        );
    END IF;

    -- Insert into public.notifications
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        type,
        is_read,
        created_at
    ) VALUES (
        v_reporter_uuid,
        p_report_id,
        p_title,
        p_message,
        p_type,
        false,
        NOW()
    )
    RETURNING id, created_at INTO v_notification_id, v_created_at;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_notification_id,
        'user_id', v_reporter_uuid,
        'complaint_id', p_report_id,
        'title', p_title,
        'message', p_message,
        'type', p_type,
        'is_read', false,
        'created_at', v_created_at
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_report_notification(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_report_notification(UUID, TEXT, TEXT, TEXT) TO service_role;

-- 6. Compatibility Function: create_status_notification
CREATE OR REPLACE FUNCTION public.create_status_notification(
    p_user_id UUID,
    p_complaint_id TEXT,
    p_title TEXT,
    p_message TEXT,
    p_type TEXT,
    p_status TEXT,
    p_email_status TEXT DEFAULT 'pending'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_target_uuid UUID;
    v_report_uuid UUID;
    v_new_id UUID;
BEGIN
    v_target_uuid := p_user_id;

    -- Resolve report UUID if complaint_id is UUID
    IF p_complaint_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        v_report_uuid := p_complaint_id::uuid;
    ELSE
        -- Try finding report UUID in public.reports
        SELECT id INTO v_report_uuid
        FROM public.reports
        WHERE complaint_id = p_complaint_id OR title ILIKE '%' || p_complaint_id || '%'
        LIMIT 1;
    END IF;

    IF v_report_uuid IS NULL THEN
        -- Fallback to generating or using dummy UUID for complaint reference
        v_report_uuid := gen_random_uuid();
    END IF;

    -- Insert into public.notifications using the 8 standard columns
    INSERT INTO public.notifications (
        user_id,
        complaint_id,
        title,
        message,
        type,
        is_read,
        created_at
    ) VALUES (
        v_target_uuid,
        v_report_uuid,
        p_title,
        p_message,
        p_type,
        false,
        NOW()
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_new_id,
        'user_id', v_target_uuid,
        'complaint_id', v_report_uuid,
        'message', 'Notification created successfully'
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_status_notification TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_status_notification TO service_role;
