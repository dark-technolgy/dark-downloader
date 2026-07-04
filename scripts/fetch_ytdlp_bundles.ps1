$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  throw 'Run the script from the project root.'
}

$winOut = Join-Path $root 'assets\bundled_ytdlp\windows'
$linOut = Join-Path $root 'assets\bundled_ytdlp\linux'
New-Item -ItemType Directory -Force -Path $winOut | Out-Null
New-Item -ItemType Directory -Force -Path $linOut | Out-Null

$winUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
$linUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp'

Write-Host 'Downloading yt-dlp for Windows...'
Invoke-WebRequest -Uri $winUrl -OutFile (Join-Path $winOut 'yt-dlp.exe') -UseBasicParsing

Write-Host 'Downloading yt-dlp for Linux...'
Invoke-WebRequest -Uri $linUrl -OutFile (Join-Path $linOut 'yt-dlp') -UseBasicParsing

Write-Host 'Done!'
