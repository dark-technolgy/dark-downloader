$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$linOut = Join-Path $root 'assets\bundled_ffmpeg\linux'
New-Item -ItemType Directory -Force -Path $linOut | Out-Null

$linUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "dd_ff_fetch_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  Write-Host 'Downloading Linux FFmpeg...'
  $linTxz = Join-Path $tmp 'lin.tar.xz'
  Invoke-WebRequest -Uri $linUrl -OutFile $linTxz -UseBasicParsing
  $linExt = Join-Path $tmp 'lin_exp'
  New-Item -ItemType Directory -Force -Path $linExt | Out-Null
  
  Write-Host 'Extracting Linux FFmpeg...'
  & tar -xJf $linTxz -C $linExt
  if ($LASTEXITCODE -ne 0) { throw 'tar -xJf failed for linux archive.' }
  
  $binL = Get-ChildItem -Path $linExt -Recurse -Directory -Filter 'bin' | Select-Object -First 1
  if (-not $binL) { throw 'bin directory not found in linux archive.' }
  $ff = Join-Path $binL.FullName 'ffmpeg'
  if (-not (Test-Path $ff)) { throw 'ffmpeg binary not found in linux bin.' }
  
  Remove-Item "$linOut\*" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $ff -Destination (Join-Path $linOut 'ffmpeg') -Force
  Write-Host 'Done Linux FFmpeg!'
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
