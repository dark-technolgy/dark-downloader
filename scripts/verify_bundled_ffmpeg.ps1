# يتحقق من وجود ثنائيات FFmpeg قبل flutter build.
# الاستخدام من جذر المشروع:
#   pwsh scripts/verify_bundled_ffmpeg.ps1
#   pwsh scripts/verify_bundled_ffmpeg.ps1 -WindowsOnly
param(
    [switch]$WindowsOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$w = Join-Path $root 'bundled_ffmpeg\windows\ffmpeg.exe'
$l = Join-Path $root 'bundled_ffmpeg\linux\ffmpeg'

if (-not (Test-Path $w)) {
    throw "ناقص: $w — شغّل fetch_ffmpeg_bundles.ps1"
}
if (-not $WindowsOnly) {
    if (-not (Test-Path $l)) {
        throw "ناقص: $l — شغّل fetch_ffmpeg_bundles.ps1 أو استخدم -WindowsOnly إن كنت تبني ويندوز فقط"
    }
}

Write-Host 'OK: bundled_ffmpeg جاهز لـ CMake.'
