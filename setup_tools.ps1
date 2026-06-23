$ErrorActionPreference = 'Stop'

$Url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$ZipPath = "$env:TEMP\cmdline-tools.zip"
$SdkPath = "C:\Users\Dark\AppData\Local\Android\sdk"
$CmdLineToolsPath = "$SdkPath\cmdline-tools"
$LatestPath = "$CmdLineToolsPath\latest"

Write-Host "Downloading cmdline-tools..."
Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing

$ExtractTemp = "$env:TEMP\cmdline-tools-extract"
if (Test-Path $ExtractTemp) { Remove-Item -Recurse -Force $ExtractTemp }
New-Item -ItemType Directory -Force -Path $ExtractTemp | Out-Null

Write-Host "Extracting..."
Expand-Archive -Path $ZipPath -DestinationPath $ExtractTemp -Force

if (Test-Path $LatestPath) { Remove-Item -Recurse -Force $LatestPath }
New-Item -ItemType Directory -Force -Path $LatestPath | Out-Null

Write-Host "Moving files..."
Copy-Item -Path "$ExtractTemp\cmdline-tools\*" -Destination $LatestPath -Recurse -Force

Write-Host "Accepting licenses..."
# Run the license acceptance script using cmd.exe to pipe "y"
cmd.exe /c "echo y | `"$LatestPath\bin\sdkmanager.bat`" --licenses"

Write-Host "Done."
