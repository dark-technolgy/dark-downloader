# Sets environment for Flutter Windows + rust_lib_dark_downloader (aws-lc-sys via CMake).
# Usage:  . .\scripts\env_windows_rust_build.ps1
# Then:   flutter build windows --release --obfuscate --split-debug-info=build/obfuscate_symbols

$cmake = "${env:ProgramFiles}\CMake\bin"
if (Test-Path $cmake) {
  $env:PATH = "$cmake;$env:PATH"
}

# Prefer CMake builder + prebuilt NASM objects (no NASM.exe required on PATH).
$env:AWS_LC_SYS_CMAKE_BUILDER = "1"
$env:AWS_LC_SYS_PREBUILT_NASM = "1"

Write-Host "PATH prepended: $cmake (if exists)"
Write-Host "AWS_LC_SYS_CMAKE_BUILDER=$env:AWS_LC_SYS_CMAKE_BUILDER"
Write-Host "AWS_LC_SYS_PREBUILT_NASM=$env:AWS_LC_SYS_PREBUILT_NASM"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
  Write-Warning "cmake not found. Install: winget install -e --id Kitware.CMake"
}
