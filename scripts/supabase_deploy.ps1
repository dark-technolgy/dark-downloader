#Requires -Version 5.1
<#
.SYNOPSIS
  Links this repo to Supabase, pushes migrations, deploys Edge Functions.

.DESCRIPTION
  Requires SUPABASE_ACCESS_TOKEN (Dashboard → Account → Access Tokens).
  Deploys FIB functions only: fib-create-payment, fib-webhook (Stripe functions not deployed here).
  Optional: SUPABASE_DB_PASSWORD (Database password) if `db push` needs it.
  Optional: SUPABASE_PROJECT_REF (default: parsed from SUPABASE_URL or rptcqqohdnpciyohnekx).

  Run from repo root or any path:
    powershell -ExecutionPolicy Bypass -File scripts/supabase_deploy.ps1

  Paste the REAL token from the dashboard (long hex after sbp_). Do not use the literal text sbp_...
#>
param(
  [string] $ProjectRef = $env:SUPABASE_PROJECT_REF
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

function Assert-NpxSuccess {
  param([int] $StepExitCode)
  if ($StepExitCode -ne 0) {
    Write-Host "Stopped: previous command failed (exit $StepExitCode)." -ForegroundColor Red
    exit $StepExitCode
  }
}

if (-not $env:SUPABASE_ACCESS_TOKEN -or $env:SUPABASE_ACCESS_TOKEN.Trim().Length -eq 0) {
  Write-Host "Missing SUPABASE_ACCESS_TOKEN." -ForegroundColor Red
  Write-Host "Create one at https://supabase.com/dashboard/account/tokens" -ForegroundColor Yellow
  Write-Host "Then: `$env:SUPABASE_ACCESS_TOKEN = '<paste full token here>'" -ForegroundColor Yellow
  exit 1
}

$tok = $env:SUPABASE_ACCESS_TOKEN.Trim()
# Reject obvious placeholders; real PAT looks like sbp_<many hex chars>
if ($tok -match "\.\.\." -or $tok -eq "sbp_..." -or $tok -notmatch "^sbp_[A-Za-z0-9_-]{20,}$") {
  Write-Host "SUPABASE_ACCESS_TOKEN looks invalid or is still a placeholder." -ForegroundColor Red
  Write-Host "Open Account → Access Tokens, generate a token, and paste the entire value (starts with sbp_, long hex)." -ForegroundColor Yellow
  Write-Host "Do not type the characters sbp_... literally." -ForegroundColor Yellow
  exit 1
}

if (-not $ProjectRef -or $ProjectRef.Trim().Length -eq 0) {
  $u = $env:SUPABASE_URL
  if ($u -match "https://([a-z0-9]+)\.supabase\.co") {
    $ProjectRef = $Matches[1]
  } else {
    $ProjectRef = "rptcqqohdnpciyohnekx"
  }
}

Write-Host "Using project ref: $ProjectRef" -ForegroundColor Cyan

$linkArgs = @("supabase", "link", "--project-ref", $ProjectRef, "--yes")
if ($env:SUPABASE_DB_PASSWORD) {
  $linkArgs += @("-p", $env:SUPABASE_DB_PASSWORD)
}
& npx --yes @linkArgs
Assert-NpxSuccess $LASTEXITCODE

$dbArgs = @("supabase", "db", "push", "--yes")
if ($env:SUPABASE_DB_PASSWORD) {
  $dbArgs += @("-p", $env:SUPABASE_DB_PASSWORD)
}
& npx --yes @dbArgs
Assert-NpxSuccess $LASTEXITCODE

# التطبيق يستخدم FIB فقط؛ دوال Stripe تبقى في المستودع اختيارياً ولا تُنشر افتراضياً.
$functions = @(
  @{ Name = "fib-create-payment"; NoVerifyJwt = $false },
  @{ Name = "fib-webhook"; NoVerifyJwt = $true }
)

foreach ($fn in $functions) {
  $dArgs = @(
    "supabase", "functions", "deploy", $fn.Name,
    "--project-ref", $ProjectRef,
    "--use-api"
  )
  if ($fn.NoVerifyJwt) {
    $dArgs += "--no-verify-jwt"
  }
  Write-Host "Deploying $($fn.Name)..." -ForegroundColor Cyan
  & npx --yes @dArgs
  Assert-NpxSuccess $LASTEXITCODE
}

$envFile = Join-Path $RepoRoot ".env"
if (Test-Path $envFile) {
  Write-Host "Setting Edge Function secrets from .env..." -ForegroundColor Cyan
  & npx --yes supabase secrets set --project-ref $ProjectRef --env-file $envFile
  Assert-NpxSuccess $LASTEXITCODE
} else {
  Write-Host "No .env found - skip secrets. Create .env from .env.example and run:" -ForegroundColor Yellow
  Write-Host "  npx supabase secrets set --project-ref $ProjectRef --env-file .env" -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green
