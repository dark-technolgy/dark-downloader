#Requires -Version 5.1
<#
.SYNOPSIS
  Pushes branded auth email templates to a hosted Supabase project via Management API.

.DESCRIPTION
  Reads HTML from supabase/templates/ and sets mailer_subjects_* / mailer_templates_*_content.
  Requires SUPABASE_ACCESS_TOKEN. Project ref defaults to rptcqqohdnpciyohnekx.

.EXAMPLE
  $env:SUPABASE_ACCESS_TOKEN = "sbp_..."
  powershell -ExecutionPolicy Bypass -File .\scripts\apply_auth_email_templates.ps1
#>
param(
  [string]$ProjectRef = "rptcqqohdnpciyohnekx"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$templatesDir = Join-Path $root "supabase\templates"

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Error "Set SUPABASE_ACCESS_TOKEN (Dashboard → Account → Access Tokens)."
}

function Read-Template([string]$name) {
  $path = Join-Path $templatesDir $name
  if (-not (Test-Path $path)) { throw "Missing template: $path" }
  return (Get-Content -Path $path -Raw -Encoding UTF8)
}

$body = @{
  mailer_subjects_confirmation = "أكد حسابك في دارك | Confirm your Dark account"
  mailer_templates_confirmation_content = (Read-Template "confirmation.html")
  mailer_subjects_recovery = "إعادة تعيين كلمة المرور — دارك | Reset your Dark password"
  mailer_templates_recovery_content = (Read-Template "recovery.html")
  mailer_subjects_magic_link = "رابط الدخول — دارك | Sign in to Dark"
  mailer_templates_magic_link_content = (Read-Template "magic_link.html")
  mailer_subjects_email_change = "تأكيد البريد الجديد — دارك | Confirm your new email"
  mailer_templates_email_change_content = (Read-Template "email_change.html")
}

$json = $body | ConvertTo-Json -Depth 5 -Compress
$uri = "https://api.supabase.com/v1/projects/$ProjectRef/config/auth"
$headers = @{
  Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN"
  "Content-Type" = "application/json"
}

Write-Host "Updating auth email templates on project $ProjectRef ..."
Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $json | Out-Null
Write-Host "Done. Configure SMTP in Dashboard (Sender name: دارك — Dark Technology)."
