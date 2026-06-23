#!/usr/bin/env bash
# يحمّل بناء BtbN ويملأ bundled_ffmpeg/windows و bundled_ffmpeg/linux
# الاستخدام: من جذر المستودع:  bash scripts/fetch_ffmpeg_bundles.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$ROOT/pubspec.yaml" ]]; then
  echo "شغّل من جذر المشروع." >&2
  exit 1
fi

WIN_OUT="$ROOT/bundled_ffmpeg/windows"
LIN_OUT="$ROOT/bundled_ffmpeg/linux"
mkdir -p "$WIN_OUT" "$LIN_OUT"

WIN_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
LIN_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "تنزيل ويندوز..."
curl -fsSL "$WIN_URL" -o "$TMP/win.zip"
unzip -q -o "$TMP/win.zip" -d "$TMP/win_exp"
BIN="$(find "$TMP/win_exp" -type d -name bin | head -n1)"
[[ -n "$BIN" ]] || { echo "bin not found (win)" >&2; exit 1; }
  find "$WIN_OUT" -mindepth 1 -delete 2>/dev/null || true
  cp -f "$BIN"/* "$WIN_OUT/"
[[ -f "$WIN_OUT/ffmpeg.exe" ]] || { echo "ffmpeg.exe missing" >&2; exit 1; }

echo "تنزيل لينكس..."
curl -fsSL "$LIN_URL" -o "$TMP/lin.tar.xz"
mkdir -p "$TMP/lin_exp"
tar -xJf "$TMP/lin.tar.xz" -C "$TMP/lin_exp"
BINL="$(find "$TMP/lin_exp" -type d -name bin | head -n1)"
[[ -n "$BINL" ]] || { echo "bin not found (linux)" >&2; exit 1; }
[[ -f "$BINL/ffmpeg" ]] || { echo "ffmpeg missing (linux)" >&2; exit 1; }
  find "$LIN_OUT" -mindepth 1 -delete 2>/dev/null || true
  cp -f "$BINL/ffmpeg" "$LIN_OUT/ffmpeg"
chmod +x "$LIN_OUT/ffmpeg"

echo "تم. ثم: flutter build windows --release  و/أو  flutter build linux --release"
