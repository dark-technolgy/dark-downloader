# cmake/ytdlp_bootstrap.cmake
#
# Ensures the yt-dlp fallback binary is present under bundled_ytdlp/{windows,linux}/
# before the app is packaged. Used by windows/CMakeLists.txt and linux/CMakeLists.txt.
#
# yt-dlp is the resilience layer: when a site changes its player, yt-dlp is
# usually patched within days. Shipping (and auto-updating) it means users are
# never stuck when the native Rust extractor breaks.
#
# Requires internet access on the *first* build on a clean machine; on
# subsequent builds the binary is re-used unless the folder is wiped.

set(DARK_YTDLP_URL_WIN
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
  CACHE STRING "yt-dlp Windows binary (release channel)")

set(DARK_YTDLP_URL_LINUX
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
  CACHE STRING "yt-dlp Linux binary (release channel)")

function(dark_ensure_ytdlp_windows REPO_ROOT)
  set(_out "${REPO_ROOT}/bundled_ytdlp/windows")
  set(_bin "${_out}/yt-dlp.exe")
  if(EXISTS "${_bin}")
    message(STATUS "yt-dlp (Windows): already present in bundled_ytdlp/windows")
    return()
  endif()

  file(MAKE_DIRECTORY "${_out}")
  message(STATUS "yt-dlp (Windows): downloading to bundled_ytdlp/windows …")
  file(DOWNLOAD "${DARK_YTDLP_URL_WIN}" "${_bin}"
       SHOW_PROGRESS STATUS _st TLS_VERIFY ON)
  list(GET _st 0 _code)
  if(NOT _code EQUAL 0)
    message(WARNING "yt-dlp (Windows) download failed (${_st}); fallback will be unavailable in this build. Drop yt-dlp.exe into bundled_ytdlp/windows/ manually.")
    file(REMOVE "${_bin}")
    return()
  endif()

  # Sanity check — released yt-dlp.exe is ~10 MB. Anything under 1 MB is bogus.
  file(SIZE "${_bin}" _sz)
  if(_sz LESS 1000000)
    message(WARNING "yt-dlp (Windows) downloaded file is suspiciously small (${_sz} bytes); discarding.")
    file(REMOVE "${_bin}")
    return()
  endif()

  message(STATUS "yt-dlp (Windows): ready at ${_bin}")
endfunction()

function(dark_ensure_ytdlp_linux REPO_ROOT)
  set(_out "${REPO_ROOT}/bundled_ytdlp/linux")
  set(_bin "${_out}/yt-dlp")
  if(EXISTS "${_bin}")
    message(STATUS "yt-dlp (Linux): already present in bundled_ytdlp/linux")
    return()
  endif()

  file(MAKE_DIRECTORY "${_out}")
  message(STATUS "yt-dlp (Linux): downloading to bundled_ytdlp/linux …")
  file(DOWNLOAD "${DARK_YTDLP_URL_LINUX}" "${_bin}"
       SHOW_PROGRESS STATUS _st TLS_VERIFY ON)
  list(GET _st 0 _code)
  if(NOT _code EQUAL 0)
    message(WARNING "yt-dlp (Linux) download failed (${_st}); fallback will be unavailable in this build. Drop yt-dlp into bundled_ytdlp/linux/ manually.")
    file(REMOVE "${_bin}")
    return()
  endif()

  file(SIZE "${_bin}" _sz)
  if(_sz LESS 1000000)
    message(WARNING "yt-dlp (Linux) downloaded file is suspiciously small (${_sz} bytes); discarding.")
    file(REMOVE "${_bin}")
    return()
  endif()

  execute_process(COMMAND chmod +x "${_bin}" RESULT_VARIABLE _ch)
  if(NOT _ch EQUAL 0)
    message(WARNING "chmod +x on yt-dlp failed (may not be executable at runtime).")
  endif()

  message(STATUS "yt-dlp (Linux): ready at ${_bin}")
endfunction()
