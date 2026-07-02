#Requires -Version 5.1
<#
    build_installer.ps1
    -------------------
    Builds Dark Downloader for Windows (Release) and packages it as a real
    installer using Inno Setup 6.

    Output:
        build\windows\x64\runner\Release\Dark-Downloader-Setup-v<version>.exe

    The installer:
        - Requires no code-signing certificate  (no 0x800B010A error)
        - Requires no admin rights by default (installs per-user)
        - Creates a Desktop shortcut automatically
        - Creates a Start Menu entry
        - Registers a proper Uninstall entry in Programs & Features

    Prerequisites:
        - Inno Setup 6 installed. If ISCC.exe is not found the script will
          try to install it silently via winget: JRSoftware.InnoSetup.

    Usage:
        pwsh scripts/build_installer.ps1
        pwsh scripts/build_installer.ps1 -SkipFlutterBuild
        pwsh scripts/build_installer.ps1 -Version 1.1.36
#>
param(
    [switch]$SkipFlutterBuild,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Set-Location $repoRoot

# --- 1. Resolve version from pubspec.yaml -----------------------------------
if (-not $Version) {
    $pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
    if ($pubspec -match '(?m)^version:\s*([\d\.]+)') {
        $Version = $Matches[1]
    } else {
        $Version = '0.0.0'
    }
}
Write-Host ">>> Version: $Version" -ForegroundColor Cyan

# --- 2. Locate (or install) Inno Setup compiler -----------------------------
function Get-InnoCompiler {
    $cmd = Get-Command 'iscc.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles           'Inno Setup 6\ISCC.exe')
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$iscc = Get-InnoCompiler
if (-not $iscc) {
    Write-Host ">>> Inno Setup 6 not found — attempting silent install via winget..." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw @"
Inno Setup 6 is required but not installed and winget is unavailable.
Install it manually from https://jrsoftware.org/isdl.php then re-run this script.
"@
    }
    winget install --id JRSoftware.InnoSetup --silent --accept-source-agreements --accept-package-agreements
    $iscc = Get-InnoCompiler
    if (-not $iscc) {
        throw "Inno Setup install did not produce ISCC.exe. Install manually and re-run."
    }
}
Write-Host ">>> Inno Setup compiler: $iscc" -ForegroundColor DarkGray

# --- 3. Ensure bundled FFmpeg exists ----------------------------------------
$winFf = Join-Path $repoRoot 'bundled_ffmpeg\windows\ffmpeg.exe'
if (-not (Test-Path $winFf)) {
    Write-Host ">>> bundled_ffmpeg missing — fetching..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'fetch_ffmpeg_bundles.ps1')
    if (-not (Test-Path $winFf)) {
        throw "Failed to obtain $winFf"
    }
}

# --- 4. Build Windows release -----------------------------------------------
if (-not $SkipFlutterBuild) {
    Write-Host ">>> flutter build windows --release" -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
}

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$mainExe    = Join-Path $releaseDir 'dark_downloader.exe'
if (-not (Test-Path $mainExe)) {
    throw "dark_downloader.exe not found in $releaseDir — did the build succeed?"
}

# --- 5. Clean stale artifacts so they don't get bundled into the installer --
Get-ChildItem -Path $releaseDir -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.(msix|cer|zip)$' -or $_.Name -like 'Dark-Downloader-Setup-*.exe' -or $_.Name -eq 'RUN.bat' -or $_.Name -eq 'README.txt' } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

# --- 6. Compile installer with Inno Setup -----------------------------------
$issFile = Join-Path $repoRoot 'installer\dark_downloader.iss'
if (-not (Test-Path $issFile)) { throw "Missing $issFile" }

Write-Host ">>> Compiling installer ($iscc)..." -ForegroundColor Cyan
& $iscc `
    "/DAppVersion=$Version" `
    "/DSourceDir=$releaseDir" `
    "/DOutputDir=$releaseDir" `
    $issFile
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed ($LASTEXITCODE)" }

$setupExe = Join-Path $releaseDir "Dark-Downloader-Setup-v$Version.exe"
if (-not (Test-Path $setupExe)) { throw "Setup executable not produced at $setupExe" }

$size = [math]::Round((Get-Item $setupExe).Length / 1MB, 1)
Write-Host ""
Write-Host "=== INSTALLER READY ===" -ForegroundColor Green
Write-Host "  File : $setupExe"
Write-Host "  Size : $size MB"
Write-Host ""
Write-Host "Users double-click the file to install:"
Write-Host "  * No admin rights required (per-user install by default)."
Write-Host "  * No certificate, no MSIX, no 0x800B010A error."
Write-Host "  * Desktop shortcut is created automatically."
