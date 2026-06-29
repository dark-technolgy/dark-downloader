# Fetches FFmpeg-Kit Android AAR into android/ffmpeg-kit-repo (Maven layout).
# Required because com.arthenica binaries are no longer on Maven Central.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'android\ffmpeg-kit-repo\com\arthenica\ffmpeg-kit-full-gpl\6.0-2'
$aarPath = Join-Path $outDir 'ffmpeg-kit-full-gpl-6.0-2.aar'
$url = 'https://github.com/NooruddinLakhani/ffmpeg-kit-full-gpl/releases/download/v1.0.0/ffmpeg-kit-full-gpl.aar'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

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

# Create POM for full-gpl
$pomPath = Join-Path $outDir 'ffmpeg-kit-full-gpl-6.0-2.pom'
$pomContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.arthenica</groupId>
  <artifactId>ffmpeg-kit-full-gpl</artifactId>
  <version>6.0-2</version>
  <packaging>aar</packaging>
  <description>FFmpeg Kit for Android. Full GPL variant.</description>
</project>
"@
Set-Content -Path $pomPath -Value $pomContent
