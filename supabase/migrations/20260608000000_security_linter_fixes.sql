-- ============================================================================
-- DARK DOWNLOADER — SECURITY LINTER FIXES
-- Resolves warnings:
-- 1. function_search_path_mutable
-- 2. anon_security_definer_function_executable
-- 3. authenticated_security_definer_function_executable
-- 4. auth_allow_anonymous_sign_ins
-- ============================================================================

-- 1 & 2 & 3. Fix handle_new_user() security issues
-- Ensuring search_path is set to public (already there, but explicitly recreating to be safe)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id, email, name, language, 
    platform, device_model, locale_info, timezone, country_code, country_name, city, isp
  )
  VALUES (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'language', 'ar'),
    new.raw_user_meta_data->>'platform',
    new.raw_user_meta_data->>'device_model',
    new.raw_user_meta_data->>'locale_info',
    new.raw_user_meta_data->>'timezone',
    new.raw_user_meta_data->>'country_code',
    new.raw_user_meta_data->>'country_name',
    new.raw_user_meta_data->>'city',
    new.raw_user_meta_data->>'isp'
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    platform = EXCLUDED.platform,
    device_model = EXCLUDED.device_model,
    country_code = EXCLUDED.country_code,
    country_name = EXCLUDED.country_name,
    city = EXCLUDED.city;
  RETURN new;
END;
$$;

-- Revoke execute permissions to prevent public/anon/authenticated from calling it directly
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM authenticated;

-- 4. Fix auth_allow_anonymous_sign_ins for all RLS policies
-- We will alter existing policies to be explicitly for 'authenticated'
-- If the policy name doesn't match, we drop old ones and create standard ones.

-- Clean up any old policies that the linter found
DROP POLICY IF EXISTS "User Data" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Self Access" ON public.profiles;

DROP POLICY IF EXISTS "User Browser" ON public.browser_history;
DROP POLICY IF EXISTS "User History" ON public.browser_history;

DROP POLICY IF EXISTS "Users manage own downloads" ON public.downloads;
DROP POLICY IF EXISTS "User Downloads" ON public.downloads;

DROP POLICY IF EXISTS "User Bookmarks" ON public.bookmarks;

DROP POLICY IF EXISTS "Public App Config" ON public.remote_config;
DROP POLICY IF EXISTS "Public Config" ON public.remote_config;

-- Recreate standard policies explicitly FOR authenticated users
CREATE POLICY "Self Access" ON public.profiles AS PERMISSIVE FOR ALL TO authenticated USING (auth.uid() = id);
CREATE POLICY "User History" ON public.browser_history AS PERMISSIVE FOR ALL TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "User Downloads" ON public.downloads AS PERMISSIVE FOR ALL TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "User Bookmarks" ON public.bookmarks AS PERMISSIVE FOR ALL TO authenticated USING (auth.uid() = user_id);

-- Configs should be accessible by anon and authenticated
CREATE POLICY "Public Config" ON public.remote_config AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
