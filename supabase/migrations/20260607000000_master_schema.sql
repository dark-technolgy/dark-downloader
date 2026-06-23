-- ============================================================================
-- DARK DOWNLOADER — MASTER SCHEMA (VERSION 2.0)
-- Consolidated, Hardened, and Optimized for Dark Downloader
-- Purpose: Complete single-file schema for future maintenance.
-- ============================================================================

-- 1. EXTENSIONS
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 2. CORE: PROFILES (With Device Tracking Columns)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  email text unique,
  name text,
  language text default 'ar',
  
  -- Device & Tracking Data
  platform text,
  device_model text,
  locale_info text,
  timezone text,
  country_code text,
  country_name text,
  city text,
  isp text,

  -- Subscription & Stats
  subscription_tier text default 'free' check (subscription_tier in ('free', 'premium', 'pro')),
  subscription_status text default 'inactive' check (subscription_status in (
    'inactive', 'active', 'trialing', 'past_due', 'canceled', 'cancelled', 'expired'
  )),
  subscription_expires_at timestamp with time zone,
  total_downloads bigint default 0 not null,
  
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

-- Fix for existing tables: Add missing columns if they were skipped due to "if not exists"
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='platform') THEN
        ALTER TABLE public.profiles ADD COLUMN platform text;
        ALTER TABLE public.profiles ADD COLUMN device_model text;
        ALTER TABLE public.profiles ADD COLUMN locale_info text;
        ALTER TABLE public.profiles ADD COLUMN timezone text;
        ALTER TABLE public.profiles ADD COLUMN country_code text;
        ALTER TABLE public.profiles ADD COLUMN country_name text;
        ALTER TABLE public.profiles ADD COLUMN city text;
        ALTER TABLE public.profiles ADD COLUMN isp text;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='subscription_status') THEN
        ALTER TABLE public.profiles ADD COLUMN subscription_status text default 'inactive';
        ALTER TABLE public.profiles ADD COLUMN subscription_tier text default 'free';
        ALTER TABLE public.profiles ADD COLUMN subscription_expires_at timestamp with time zone;
    END IF;
END $$;

-- 3. CLOUD SYNC: DOWNLOADS, HISTORY, BOOKMARKS, AD-WHITELIST
create table if not exists public.downloads (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  file_name text not null,
  file_url text not null,
  file_size bigint,
  downloaded_at timestamp with time zone default now(),
  unique(user_id, file_url)
);

create table if not exists public.browser_history (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  url text not null,
  title text,
  visited_at timestamp with time zone default now(),
  unique(user_id, url)
);

create table if not exists public.bookmarks (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  url text not null,
  title text not null,
  category text default 'All',
  created_at timestamp with time zone default now(),
  unique(user_id, url)
);

create table if not exists public.adblock_whitelist (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  host text not null,
  created_at timestamp with time zone default now(),
  unique(user_id, host)
);

-- 4. PAYMENTS & AUDIT
create table if not exists public.fib_pending_payments (
  id uuid default gen_random_uuid() primary key,
  payment_id text not null unique,
  user_id uuid references auth.users(id) on delete cascade not null,
  tier text not null,
  amount_iqd numeric not null,
  status text default 'PENDING',
  created_at timestamptz default now()
);

create table if not exists public.audit_logs (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  metadata jsonb,
  created_at timestamp with time zone default now()
);

-- 5. APP MANAGEMENT: REMOTE CONFIG
create table if not exists public.remote_config (
  id int primary key default 1 check (id = 1),
  maintenance_mode boolean default false,
  maintenance_message text,
  min_version text default '1.0.0',
  latest_version text default '1.0.0',
  download_url text,
  release_notes text,
  updated_at timestamptz default now()
);

-- Insert default config
insert into public.remote_config (id, maintenance_mode, latest_version)
values (1, false, '1.0.0')
on conflict (id) do nothing;

-- 6. SECURITY: RLS
alter table public.profiles enable row level security;
alter table public.downloads enable row level security;
alter table public.browser_history enable row level security;
alter table public.bookmarks enable row level security;
alter table public.adblock_whitelist enable row level security;
alter table public.fib_pending_payments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.remote_config enable row level security;

-- POLICIES (Idempotent creation)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Self Access' AND tablename = 'profiles') THEN
        create policy "Self Access" on public.profiles for all using (auth.uid() = id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'User Downloads' AND tablename = 'downloads') THEN
        create policy "User Downloads" on public.downloads for all using (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'User History' AND tablename = 'browser_history') THEN
        create policy "User History" on public.browser_history for all using (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'User Bookmarks' AND tablename = 'bookmarks') THEN
        create policy "User Bookmarks" on public.bookmarks for all using (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'User Whitelist' AND tablename = 'adblock_whitelist') THEN
        create policy "User Whitelist" on public.adblock_whitelist for all using (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'User Payments' AND tablename = 'fib_pending_payments') THEN
        create policy "User Payments" on public.fib_pending_payments for select using (auth.uid() = user_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public Config' AND tablename = 'remote_config') THEN
        create policy "Public Config" on public.remote_config for select using (true);
    END IF;
END
$$;

-- 7. PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_profiles_subscription_status ON public.profiles(subscription_status);
CREATE INDEX IF NOT EXISTS idx_downloads_user_date ON public.downloads(user_id, downloaded_at DESC);
CREATE INDEX IF NOT EXISTS idx_browser_history_user_date ON public.browser_history(user_id, visited_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_category ON public.bookmarks(user_id, category);
CREATE INDEX IF NOT EXISTS idx_fib_payments_user_status ON public.fib_pending_payments(user_id, status);

-- 8. TRIGGERS & FUNCTIONS
-- Cleanup old triggers to avoid duplicates
DROP TRIGGER IF EXISTS on_auth_user_login ON auth.users;

-- Smart profile handler (Extracts metadata directly to columns)
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

-- Ensure execute permissions
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;

-- Ensure the trigger is active on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 9. STORAGE BUCKETS (If you use storage for avatars/files)
-- Idempotent check before policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'avatars') THEN
        DROP POLICY IF EXISTS "Public avatars are viewable by everyone" ON storage.objects;
        CREATE POLICY "Public avatars are viewable by everyone"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'avatars');
    END IF;
END $$;

-- 10. REALTIME CONFIGURATION
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'profiles'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'downloads'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.downloads;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'fib_pending_payments'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.fib_pending_payments;
    END IF;
END $$;
