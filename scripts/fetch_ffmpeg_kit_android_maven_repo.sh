#!/usr/bin/env bash
# Fetches FFmpeg-Kit Android AAR into android/ffmpeg-kit-repo (Maven layout).
# Linux/macOS CI and local use. Windows: use fetch_ffmpeg_kit_android_maven_repo.ps1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/android/ffmpeg-kit-repo/com/arthenica/ffmpeg-kit-min-gpl/6.0-2"
AAR_PATH="${OUT_DIR}/ffmpeg-kit-min-gpl-6.0-2.aar"
POM_PATH="${OUT_DIR}/ffmpeg-kit-min-gpl-6.0-2.pom"
URL="https://github.com/NooruddinLakhani/ffmpeg-kit-full-gpl/releases/download/v1.0.0/ffmpeg-kit-full-gpl.aar"

mkdir -p "${OUT_DIR}"

if [[ ! -f "${POM_PATH}" ]]; then
  echo "error: missing POM at ${POM_PATH} (incomplete checkout)." >&2
  exit 1
fi

if [[ -f "${AAR_PATH}" ]] && [[ "$(stat -c%s "${AAR_PATH}" 2>/dev/null || stat -f%z "${AAR_PATH}" 2>/dev/null)" -gt 1048576 ]]; then
  echo "OK: AAR already present ($(du -h "${AAR_PATH}" | cut -f1))."
  exit 0
fi

rm -f "${AAR_PATH}"
echo "Downloading FFmpeg-Kit AAR..."
curl -fsSL -o "${AAR_PATH}" "${URL}"
echo "OK: ${AAR_PATH}"
