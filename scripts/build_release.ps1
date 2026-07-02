# ─────────────────────────────────────────────────────────────
#  Dark Downloader — Windows Release Build
#  Produces a real installer .exe (no MSIX, no certificate).
# ─────────────────────────────────────────────────────────────

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Dark Downloader - Release Build Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1 — bundle FFmpeg into the project (once, cached)
Write-Host "1. Bundling FFmpeg natively into the project..." -ForegroundColor Yellow
dart run scripts/bundle_ffmpeg.dart
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to bundle FFmpeg. Aborting." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Step 2 — build Windows release (obfuscated) + package as .exe installer
Write-Host "2. Building Windows release + installer..." -ForegroundColor Yellow
flutter build windows --release --obfuscate --split-debug-info=build/app/outputs/symbols
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to build Windows release. Aborting." -ForegroundColor Red
    exit $LASTEXITCODE
}

pwsh (Join-Path $PSScriptRoot 'build_installer.ps1') -SkipFlutterBuild
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to build installer. Aborting." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Build Completed Successfully!" -ForegroundColor Green
Write-Host "  Installer: build/windows/x64/runner/Release/Dark-Downloader-Setup-v*.exe" -ForegroundColor Green
Write-Host "  Debug symbols: build/app/outputs/symbols" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
