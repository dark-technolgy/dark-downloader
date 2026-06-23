# Fetches FFmpeg-Kit Android AAR into android/ffmpeg-kit-repo (Maven layout).
# Required because com.arthenica binaries are no longer on Maven Central.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'android\ffmpeg-kit-repo\com\arthenica\ffmpeg-kit-min-gpl\6.0-2'
$aarPath = Join-Path $outDir 'ffmpeg-kit-min-gpl-6.0-2.aar'
$url = 'https://github.com/NooruddinLakhani/ffmpeg-kit-full-gpl/releases/download/v1.0.0/ffmpeg-kit-full-gpl.aar'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pom = Join-Path $outDir 'ffmpeg-kit-min-gpl-6.0-2.pom'
if (-not (Test-Path $pom)) {
  throw "Missing POM at $pom (incomplete checkout)."
}

if (Test-Path $aarPath) {
  $len = (Get-Item $aarPath).Length
  if ($len -gt 1MB) {
    $mb = [math]::Round($len / 1MB, 1)
    Write-Host "OK: AAR already present ($mb MB)."
    exit 0
  }
  Remove-Item $aarPath -Force
}

Write-Host 'Downloading FFmpeg-Kit AAR...'
Invoke-WebRequest -Uri $url -OutFile $aarPath -UseBasicParsing
Write-Host "OK: $aarPath"
