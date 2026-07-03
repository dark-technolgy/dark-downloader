-- ============================================================================
-- DARK DOWNLOADER — REMOVE MONETIZATION
-- Purpose: Drop every subscription / payment / license artifact.
--          The app is now 100% free — no tiers, no payments, no donations.
-- ============================================================================

-- 1. Drop old policy first (depends on the table)
DROP POLICY IF EXISTS "User Payments" ON public.fib_pending_payments;

-- 2. Drop payment table
DROP INDEX IF EXISTS public.idx_fib_payments_user_status;
DROP TABLE IF EXISTS public.fib_pending_payments CASCADE;

-- 3. Drop subscription columns from profiles
DROP INDEX IF EXISTS public.idx_profiles_subscription_status;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'profiles'
                 AND column_name = 'subscription_tier') THEN
        ALTER TABLE public.profiles DROP COLUMN subscription_tier;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'profiles'
                 AND column_name = 'subscription_status') THEN
        ALTER TABLE public.profiles DROP COLUMN subscription_status;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'profiles'
                 AND column_name = 'subscription_expires_at') THEN
        ALTER TABLE public.profiles DROP COLUMN subscription_expires_at;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'profiles'
                 AND column_name = 'trial_started_at') THEN
        ALTER TABLE public.profiles DROP COLUMN trial_started_at;
    END IF;
END $$;

-- 4. Drop any leftover monetization helper functions
DROP FUNCTION IF EXISTS public.start_trial_if_null();
DROP FUNCTION IF EXISTS public.activate_subscription(uuid, text, timestamptz);
DROP FUNCTION IF EXISTS public.expire_subscription(uuid);
