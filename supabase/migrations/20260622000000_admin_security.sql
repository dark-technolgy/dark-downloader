-- ============================================================================
-- KEENX ADMIN SECURITY MIGRATION
-- Purpose: Add admin role management and secure the apps table + storage.
-- Run this AFTER the master_schema.sql migration.
-- ============================================================================

-- ──────────────────────────────────────────────────────────
-- 1. ADMIN USERS TABLE
-- Maps Supabase auth users to admin roles.
-- Only users in this table can access KeenX Admin panel.
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'editor' CHECK (role IN ('super_admin', 'admin', 'editor')),
  display_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Enable RLS
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Only authenticated admins can read their own record (used by login check)
CREATE POLICY "Admins can read own record"
  ON public.admin_users
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- No public insert/update/delete — managed via Supabase Dashboard or SQL only
-- This prevents any client from elevating privileges

-- ──────────────────────────────────────────────────────────
-- 2. SECURE THE APPS TABLE
-- Read: anyone (anon + authenticated) — website needs public read
-- Write: only authenticated admin users
-- ──────────────────────────────────────────────────────────

-- Only secure the apps table if it exists (it is an optional website feature).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'apps'
  ) THEN
    -- Ensure RLS is enabled on apps (may already be, but idempotent)
    EXECUTE 'ALTER TABLE public.apps ENABLE ROW LEVEL SECURITY';

    -- Drop any existing permissive policies
    EXECUTE 'DROP POLICY IF EXISTS "Public App Read" ON public.apps';
    EXECUTE 'DROP POLICY IF EXISTS "Admin App Write" ON public.apps';
    EXECUTE 'DROP POLICY IF EXISTS "Apps are publicly readable" ON public.apps';
    EXECUTE 'DROP POLICY IF EXISTS "Apps are admin writable" ON public.apps';

    -- Anyone can READ apps (the website needs this)
    EXECUTE 'CREATE POLICY "Apps are publicly readable"
      ON public.apps
      AS PERMISSIVE
      FOR SELECT
      TO anon, authenticated
      USING (true)';

    -- Only admin_users can INSERT, UPDATE, DELETE apps
    EXECUTE 'CREATE POLICY "Apps are admin writable"
      ON public.apps
      AS PERMISSIVE
      FOR ALL
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.admin_users
          WHERE admin_users.user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.admin_users
          WHERE admin_users.user_id = auth.uid()
        )
      )';
  END IF;
END $$;

-- ──────────────────────────────────────────────────────────
-- 3. SECURE STORAGE BUCKET: apps_releases
-- Read: anyone (public download links)
-- Write: only authenticated admin users
-- ──────────────────────────────────────────────────────────

-- Create the bucket if it doesn't exist (no-op if exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('apps_releases', 'apps_releases', true)
ON CONFLICT (id) DO NOTHING;

-- Drop existing storage policies to avoid conflicts
DROP POLICY IF EXISTS "Anyone can download releases" ON storage.objects;
DROP POLICY IF EXISTS "Admins can upload releases" ON storage.objects;
DROP POLICY IF EXISTS "Admins can update releases" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete releases" ON storage.objects;

-- Public READ for downloads
CREATE POLICY "Anyone can download releases"
  ON storage.objects
  AS PERMISSIVE
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'apps_releases');

-- Admin-only UPLOAD
CREATE POLICY "Admins can upload releases"
  ON storage.objects
  AS PERMISSIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'apps_releases'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.user_id = auth.uid()
    )
  );

-- Admin-only UPDATE (for upsert)
CREATE POLICY "Admins can update releases"
  ON storage.objects
  AS PERMISSIVE
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'apps_releases'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.user_id = auth.uid()
    )
  );

-- Admin-only DELETE
CREATE POLICY "Admins can delete releases"
  ON storage.objects
  AS PERMISSIVE
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'apps_releases'
    AND EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.user_id = auth.uid()
    )
  );

-- ──────────────────────────────────────────────────────────
-- 4. AUDIT LOG: Track admin actions
-- ──────────────────────────────────────────────────────────

-- Allow admins to insert audit logs
DROP POLICY IF EXISTS "Admins can insert audit logs" ON public.audit_logs;
CREATE POLICY "Admins can insert audit logs"
  ON public.audit_logs
  AS PERMISSIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.user_id = auth.uid()
    )
  );

-- Admins can read all audit logs
DROP POLICY IF EXISTS "Admins can read audit logs" ON public.audit_logs;
CREATE POLICY "Admins can read audit logs"
  ON public.audit_logs
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE admin_users.user_id = auth.uid()
    )
  );

-- ──────────────────────────────────────────────────────────
-- 5. INDEX for admin lookups
-- ──────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON public.admin_users(user_id);

-- ============================================================================
-- POST-MIGRATION SETUP (Manual Steps):
--
-- After running this migration, you MUST manually add your admin user:
--
--   INSERT INTO public.admin_users (user_id, role, display_name)
--   VALUES (
--     'YOUR_SUPABASE_AUTH_USER_UUID',
--     'super_admin',
--     'Your Name'
--   );
--
-- You can find your user UUID in:
--   Supabase Dashboard → Authentication → Users
-- ============================================================================
