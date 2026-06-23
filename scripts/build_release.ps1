# Build Release Script for Dark Downloader
# This script bundles FFmpeg, and builds the flutter app with obfuscation.

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Dark Downloader - Release Build Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1: Bundle FFmpeg
Write-Host "1. Bundling FFmpeg natively into the project..." -ForegroundColor Yellow
dart run scripts/bundle_ffmpeg.dart

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to bundle FFmpeg. Aborting." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Step 2: Build Flutter Windows with Obfuscation
Write-Host "2. Building Flutter Windows Release with Obfuscation..." -ForegroundColor Yellow
flutter build windows --release --obfuscate --split-debug-info=build/app/outputs/symbols

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to build Windows release. Aborting." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Build Completed Successfully!" -ForegroundColor Green
Write-Host "  Exe is located at: build/windows/x64/runner/Release/dark_downloader.exe" -ForegroundColor Green
Write-Host "  Debug symbols saved to: build/app/outputs/symbols" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
