// supabase/functions/get-extractor-rules/index.ts
//
// Serves the latest extractor rule pack to Dark Downloader clients.
//
// Priority (first non-empty wins):
//   1. `extractor_rules` table row with the highest `pack_version` — allows
//      hot-shipping new rules from the dashboard without redeploying.
//   2. The `default_rules` embedded below — matches the shape shipped in
//      `assets/bootstrap/extractor_rules.json` so a client always gets *some*
//      pack even on a brand-new project.
//
// Response shape (`RulesRegistry` on the Rust side):
//   {
//     "last_updated": <unix seconds>,
//     "rules": [ { "platform": "...", "version": 1,
//                  "url_patterns": ["..."], "steps": [...] }, ... ]
//   }
//
// Deploy:  supabase functions deploy get-extractor-rules
// Invoke:  GET https://<project>.functions.supabase.co/get-extractor-rules
//
// This endpoint is public (no auth required) so cold installs work
// immediately. It never returns user data.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DEFAULT_RULES = {
  last_updated: 0,
  rules: [
    {
      platform: "generic-mp4",
      version: 1,
      priority: -100,
      url_patterns: [".*"],
      user_agent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      steps: [
        { op: "fetch", url: "{{url}}", as: "html" },
        {
          op: "regex_extract",
          input: "html",
          pattern: "<title>([^<]+)</title>",
          as: "title",
        },
        { op: "set_title", value: "{{title}}" },
        {
          op: "regex_find_all",
          input: "html",
          pattern: "(https?://[^\"'>\\s]+\\.mp4(?:\\?[^\"'>\\s]*)?)",
          as: "mp4_urls",
        },
        {
          op: "build_stream",
          url: "{{mp4_urls[0]}}",
          quality: "HD",
          container: "mp4",
        },
      ],
    },
    {
      platform: "generic-hls",
      version: 1,
      priority: -101,
      url_patterns: [".*"],
      steps: [
        { op: "fetch", url: "{{url}}", as: "html" },
        {
          op: "regex_extract",
          input: "html",
          pattern: "<title>([^<]+)</title>",
          as: "title",
        },
        { op: "set_title", value: "{{title}}" },
        {
          op: "regex_find_all",
          input: "html",
          pattern: "(https?://[^\"'>\\s]+\\.m3u8(?:\\?[^\"'>\\s]*)?)",
          as: "hls_urls",
        },
        {
          op: "build_stream",
          url: "{{hls_urls[0]}}",
          quality: "Auto HLS",
          container: "mp4",
        },
      ],
    },
  ],
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Cache-Control": "public, max-age=900",
  "Content-Type": "application/json",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (supabaseUrl && serviceKey) {
      const client = createClient(supabaseUrl, serviceKey);
      const { data, error } = await client
        .from("extractor_rules")
        .select("payload")
        .order("pack_version", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!error && data && data.payload) {
        return new Response(JSON.stringify(data.payload), {
          status: 200,
          headers: CORS,
        });
      }
    }
  } catch (e) {
    console.error("get-extractor-rules: database lookup failed:", e);
  }

  // Fallback: embedded defaults.
  const body = {
    ...DEFAULT_RULES,
    last_updated: Math.floor(Date.now() / 1000),
  };
  return new Response(JSON.stringify(body), { status: 200, headers: CORS });
});
