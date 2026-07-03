# yt-dlp binaries live under `windows/` and `linux/`. They are populated by:
#
# 1. `cmake/ytdlp_bootstrap.cmake` (invoked from `windows/CMakeLists.txt` and
#    `linux/CMakeLists.txt`) — downloads the latest yt-dlp release on the
#    first clean build.
# 2. Manual placement — drop the binaries in the right subfolder if you're
#    working offline or want to pin a specific version.
# 3. The runtime `YtdlpBootstrap` service also copies binaries from the
#    Flutter asset bundle (`assets/bundled_ytdlp/**`) into
#    `<application-support>/dark_downloader/tools/ytdlp/` on first launch.
#
# The Rust extractor cascade calls `yt-dlp` only if the native extractor
# fails. The app therefore keeps working with or without this folder present.
