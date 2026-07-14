#Requires -Version 5.1
<#
  يحمّل بناء BtbN (GPL) ويملأ bundled_ffmpeg/windows و bundled_ffmpeg/linux
  لتضمينها مع إصدار ويندوز/لينكس (CMake ينسخها بجانب التنفيذي).

  الاستخدام (من جذر المستودع):
    pwsh scripts/fetch_ffmpeg_bundles.ps1

  يتطلب اتصالاً بالإنترنت مرة عند التحضير للنشر فقط — لا يحتاج المستخدم النهائي.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  throw 'شغّل السكربت من جذر المشروع (حيث pubspec.yaml).'
}

$winOut = Join-Path $root 'assets\bundled_ffmpeg\windows'
$linOut = Join-Path $root 'assets\bundled_ffmpeg\linux'
New-Item -ItemType Directory -Force -Path $winOut | Out-Null
New-Item -ItemType Directory -Force -Path $linOut | Out-Null

$winUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
$linUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "dd_ff_fetch_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  Write-Host 'تنزيل بناء ويندوز...'
  $winZip = Join-Path $tmp 'win.zip'
  Invoke-WebRequest -Uri $winUrl -OutFile $winZip -UseBasicParsing
  $winExt = Join-Path $tmp 'win_exp'
  Expand-Archive -LiteralPath $winZip -DestinationPath $winExt -Force
  $bin = Get-ChildItem -Path $winExt -Recurse -Directory -Filter 'bin' | Select-Object -First 1
  if (-not $bin) { throw 'لم يُعثر على مجلد bin في أرشيف ويندوز.' }
  Remove-Item "$winOut\*" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item -Path (Join-Path $bin.FullName '*') -Destination $winOut -Force
  if (-not (Test-Path (Join-Path $winOut 'ffmpeg.exe'))) {
    throw 'ffmpeg.exe غير موجود بعد النسخ.'
  }

  Write-Host 'تنزيل بناء لينكس...'
  $linTxz = Join-Path $tmp 'lin.tar.xz'
  Invoke-WebRequest -Uri $linUrl -OutFile $linTxz -UseBasicParsing
  $linExt = Join-Path $tmp 'lin_exp'
  New-Item -ItemType Directory -Force -Path $linExt | Out-Null
  & tar -xJf $linTxz -C $linExt
  if ($LASTEXITCODE -ne 0) { throw 'فشل tar -xJf لأرشيف لينكس.' }
  $binL = Get-ChildItem -Path $linExt -Recurse -Directory -Filter 'bin' | Select-Object -First 1
  if (-not $binL) { throw 'لم يُعثر على مجلد bin في أرشيف لينكس.' }
  $ff = Join-Path $binL.FullName 'ffmpeg'
  if (-not (Test-Path $ff)) { throw 'ملف ffmpeg غير موجود في bin لينكس.' }
  Remove-Item "$linOut\*" -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $ff -Destination (Join-Path $linOut 'ffmpeg') -Force

  $linFf = Join-Path $linOut 'ffmpeg'
  if (-not (Test-Path $linFf)) { throw 'ملف لينكس ffmpeg مفقود.' }
  $sz = (Get-Item $linFf).Length
  if ($sz -lt 500000) { throw "ملف لينكس ffmpeg صغير جداً ($sz بايت) — تحقق من الأرشيف." }

  Write-Host 'تم التحقق. التالي:'
  Write-Host '  pwsh scripts/build_release_for_website.ps1'
  Write-Host '  أو: flutter build windows --release / flutter build linux --release'
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
