-- Optional storage backing the `get-extractor-rules` Edge Function.
--
-- The client-side Rust engine (`api::remote_rules`) can execute pure-data
-- rule packs (regex + fetch + build_stream) without a new app release. This
-- table lets admins hot-ship a new pack from the Supabase dashboard: bump
-- `pack_version`, insert the JSON payload, and the Edge Function will start
-- serving it on the next client sync.
--
-- The payload shape must match `RulesRegistry` in Rust:
--   {
--     "last_updated": <unix seconds>,
--     "rules": [ { "platform": "...", "version": 1,
--                  "url_patterns": ["..."], "steps": [...] }, ... ]
--   }

CREATE TABLE IF NOT EXISTS public.extractor_rules (
    id              BIGSERIAL PRIMARY KEY,
    pack_version    INTEGER      NOT NULL,
    payload         JSONB        NOT NULL,
    published_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    notes           TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_extractor_rules_version
    ON public.extractor_rules (pack_version DESC);

ALTER TABLE public.extractor_rules ENABLE ROW LEVEL SECURITY;

-- Public read (anyone with the anon key can pull the latest pack; the pack
-- itself is not sensitive — it contains extraction recipes, not user data).
DROP POLICY IF EXISTS "extractor_rules_public_read" ON public.extractor_rules;
CREATE POLICY "extractor_rules_public_read"
    ON public.extractor_rules
    FOR SELECT
    USING (true);

-- Writes go through the service role only.
DROP POLICY IF EXISTS "extractor_rules_service_write" ON public.extractor_rules;
CREATE POLICY "extractor_rules_service_write"
    ON public.extractor_rules
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.extractor_rules IS
    'Hot-shippable extractor rule packs consumed by the Dark Downloader Rust engine.';
