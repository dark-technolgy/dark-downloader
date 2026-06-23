#Requires -Version 5.1
<#
  إصدار جاهز للنشر على موقعكم (بدون متاجر).

  الاستخدام من جذر المشروع:
    pwsh scripts/build_release_for_website.ps1
    pwsh scripts/build_release_for_website.ps1 -SkipFetch          # ثنائيات جاهزة مسبقاً
    pwsh scripts/build_release_for_website.ps1 -SplitApk         # APK منفصلة لكل ABI (أصغر حجماً)
    pwsh scripts/build_release_for_website.ps1 -SkipApk -SkipWindows

  بناء لينكس: استخدم scripts/build_release_for_website.sh على جهاز لينكس.
  بناء iOS: على macOS: flutter build ipa --release (بعد إعداد التوقيع).
#>
param(
    [switch]$SkipFetch,
    [switch]$SkipApk,
    [switch]$SkipWindows,
    [switch]$SplitApk
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not $SkipFetch) {
    & (Join-Path $PSScriptRoot 'fetch_ffmpeg_bundles.ps1')
}

$winFf = Join-Path $root 'bundled_ffmpeg\windows\ffmpeg.exe'
if (-not (Test-Path $winFf)) {
    throw "مطلوب: $winFf — شغّل السكربت بدون -SkipFetch أو نفّذ fetch_ffmpeg_bundles.ps1"
}

if (-not $SkipApk) {
    if ($SplitApk) {
        Write-Host '>>> flutter build apk --release --split-per-abi'
        flutter build apk --release --split-per-abi
    }
    else {
        Write-Host '>>> flutter build apk --release'
        flutter build apk --release
    }
}

if (-not $SkipWindows) {
    Write-Host '>>> flutter build windows --release'
    flutter build windows --release

    $outDir = Join-Path $root 'build\windows\x64\runner\Release'
    $bundledFf = Join-Path $outDir 'ffmpeg\ffmpeg.exe'
    if (Test-Path $bundledFf) {
        Write-Host "OK: وُجد FFmpeg مع الإصدار: $bundledFf"
    }
    else {
        Write-Warning "تحذير: لم يُعثر على $bundledFf — راجع windows/CMakeLists.txt ومجلد bundled_ffmpeg\windows"
    }
}

Write-Host ''
Write-Host '=== جاهز للرفع على الموقع ==='
if (-not $SkipApk) {
    if ($SplitApk) {
        Write-Host '  APK (منفصلة): build\app\outputs\flutter-apk\app-*-release.apk'
    }
    else {
        Write-Host '  APK: build\app\outputs\flutter-apk\app-release.apk'
    }
}
if (-not $SkipWindows) {
    Write-Host '  ويندوز: انسخ مجلد build\windows\x64\runner\Release\ كاملاً (يجب أن يحتوي ffmpeg\ و data\ و *.dll)'
}
