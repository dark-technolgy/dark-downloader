# bundled_ytdlp — fallback extractor binaries

Drop `yt-dlp.exe` (Windows) or `yt-dlp` (Linux) here to ship an offline
fallback for the native Rust extractors. Files are picked up automatically
at first launch and copied to the application-support directory.

- Windows: `assets/bundled_ytdlp/windows/yt-dlp.exe`
- Linux:   `assets/bundled_ytdlp/linux/yt-dlp`

The runtime resolver (`lib/app/services/ytdlp_bootstrap.dart`) also honors:
1. A binary sitting next to the installed executable under
   `bundled_ytdlp/{windows,linux}/`, e.g. what `cmake/ytdlp_bootstrap.cmake`
   emits.
2. A previously-extracted copy under `<app-support>/dark_downloader/tools/ytdlp/`.
3. A system-wide `yt-dlp` on PATH.

If none are found the cascade quietly falls back to the native Rust extractors
only — the app keeps working.

**Android is intentionally skipped** because yt-dlp requires a Python
interpreter (Termux) and would balloon the APK. Android uses the native
extractors + rule packs exclusively.
