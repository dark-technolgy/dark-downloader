Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "1. GitHub Login" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
gh auth login --web

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "2. Cloudflare (Wrangler) Login" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
wrangler login

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "3. Supabase Login" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
supabase login

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "All logins completed! You can close this window now." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
