$ErrorActionPreference = 'Stop'
$SdkPath = "C:\Users\Dark Technology\AppData\Local\Android\Sdk"
$CmdLineToolsPath = "$SdkPath\cmdline-tools"
$LatestPath = "$CmdLineToolsPath\latest"
$Url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
$ZipPath = "$env:TEMP\cmdline-tools.zip"

if (-not (Test-Path $ZipPath)) {
    Write-Host "Downloading cmdline-tools..."
    Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing
}

$ExtractTemp = "$env:TEMP\cmdline-tools-extract"
if (Test-Path $ExtractTemp) { Remove-Item -Recurse -Force $ExtractTemp }
New-Item -ItemType Directory -Force -Path $ExtractTemp | Out-Null

Write-Host "Extracting..."
Expand-Archive -Path $ZipPath -DestinationPath $ExtractTemp -Force

if (Test-Path $LatestPath) { Remove-Item -Recurse -Force $LatestPath }
New-Item -ItemType Directory -Force -Path $LatestPath | Out-Null

Write-Host "Moving files..."
# The zip contains a folder 'cmdline-tools'. Inside it there are bin, lib, source.properties, notice.txt
Copy-Item -Path "$ExtractTemp\cmdline-tools\*" -Destination $LatestPath -Recurse -Force

Write-Host "Accepting licenses..."
cmd.exe /c "echo y | `"$LatestPath\bin\sdkmanager.bat`" --sdk_root=`"$SdkPath`" --licenses"

Write-Host "Done."
