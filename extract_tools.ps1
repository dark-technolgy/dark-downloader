$ErrorActionPreference = 'Stop'

$ZipPath = "$env:TEMP\cmdline-tools.zip"
$SdkPath = "C:\Users\Dark\AppData\Local\Android\sdk"
$CmdLineToolsPath = "$SdkPath\cmdline-tools"
$LatestPath = "$CmdLineToolsPath\latest"

Write-Host "Extracting..."
$ExtractTemp = "$env:TEMP\cmdline-tools-extract"
if (Test-Path $ExtractTemp) { Remove-Item -Recurse -Force $ExtractTemp }
New-Item -ItemType Directory -Force -Path $ExtractTemp | Out-Null

Expand-Archive -Path $ZipPath -DestinationPath $ExtractTemp -Force

if (Test-Path $LatestPath) { Remove-Item -Recurse -Force $LatestPath }
New-Item -ItemType Directory -Force -Path $LatestPath | Out-Null

Write-Host "Moving files..."
Copy-Item -Path "$ExtractTemp\cmdline-tools\*" -Destination $LatestPath -Recurse -Force

Write-Host "Accepting licenses..."
cmd.exe /c "echo y | `"$LatestPath\bin\sdkmanager.bat`" --licenses"

Write-Host "Installing NDK to fix flutter NDK issue..."
cmd.exe /c "echo y | `"$LatestPath\bin\sdkmanager.bat`" `"ndk;25.1.8937393`""

Write-Host "Done."
