Write-Host "================================================" -ForegroundColor Cyan
Write-Host " Uploading Email Templates to Supabase Cloud" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Opening the Supabase Access Tokens page in your browser..."
Write-Host "Please click 'Generate new token', name it, and copy the long token."
Start-Sleep -Seconds 3
Start-Process "https://supabase.com/dashboard/account/tokens"
Write-Host ""
$token = Read-Host "Paste the token here (it starts with sbp_) and press Enter"
$token = $token.Trim()
if ($token -match "^sbp_") {
    $env:SUPABASE_ACCESS_TOKEN = $token
    Write-Host "Uploading templates..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File .\scripts\apply_auth_email_templates.ps1
    Write-Host ""
    Write-Host "تم الرفع بنجاح! (Uploaded Successfully!)" -ForegroundColor Green
} else {
    Write-Host "Invalid token. It must start with sbp_" -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to close this window..."
