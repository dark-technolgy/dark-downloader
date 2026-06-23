#!/usr/bin/env bash
# إصدار للنشر على الموقع من لينكس أو macOS (APK + لينكس).
# ويندوز: استخدم build_release_for_website.ps1 على ويندوز.
#
# الاستخدام:  bash scripts/build_release_for_website.sh
#              SKIP_FETCH=1 bash scripts/build_release_for_website.sh
#              SPLIT_APK=1 bash scripts/build_release_for_website.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${SKIP_FETCH:-}" != "1" ]]; then
  bash scripts/fetch_ffmpeg_bundles.sh
fi

if [[ ! -f "$ROOT/bundled_ffmpeg/linux/ffmpeg" ]]; then
  echo "مطلوب: bundled_ffmpeg/linux/ffmpeg" >&2
  exit 1
fi

if [[ "${SPLIT_APK:-}" == "1" ]]; then
  echo ">>> flutter build apk --release --split-per-abi"
  flutter build apk --release --split-per-abi
else
  echo ">>> flutter build apk --release"
  flutter build apk --release
fi

OUT=""
if [[ "$(uname -s)" == "Linux" ]]; then
  echo ">>> flutter build linux --release"
  flutter build linux --release
  OUT="$ROOT/build/linux/x64/release/bundle"
  FF="$OUT/ffmpeg/ffmpeg"
  if [[ -f "$FF" ]]; then
    echo "OK: FFmpeg مع حزمة لينكس: $FF"
  else
    echo "تحذير: لم يُعثر على $FF — راجع linux/CMakeLists.txt" >&2
  fi
else
  echo "تخطي بناء لينكس (شغّل هذا السكربت على جهاز Linux أو في CI)."
fi

echo ""
echo "=== جاهز للرفع ==="
echo "  APK: build/app/outputs/flutter-apk/"
if [[ -n "$OUT" ]]; then
  echo "  لينكس: $OUT (انسخ مجلد bundle كاملاً)"
fi
