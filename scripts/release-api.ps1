# ---------------------------------------------------------------------------
# Ships the API from this machine while GitHub Actions is locked.
#
#   powershell -ExecutionPolicy Bypass -File scripts\release-api.ps1
#
# Does what .github/workflows/deploy.yml does on a green CI run, in the same
# order: migrate the hosted database first, so a bad migration fails before a
# container is behind it; then deploy; then check /health answers.
#
# It never reads secrets from the repository. The hosted database URL is
# asked for once (the session-mode pooler on port 5432, see docs/SUPABASE.md)
# and kept only for this run. Fly settings that the API needs and that were
# missing on the app are set here; the Supabase service role key is pasted by
# you, so it is never on a command line in your shell history.
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$App = 'freshly-api'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

foreach ($tool in 'flyctl', 'node') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "$tool is not on PATH."
  }
}

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') {
  Write-Host "You are on '$branch', not main. Releases ship main." -ForegroundColor Yellow
  $go = Read-Host 'Deploy this branch anyway? (y/N)'
  if ($go -ne 'y') { exit 1 }
}
if (git status --porcelain) {
  throw 'The working tree has uncommitted changes. Commit or stash them first.'
}

# 1. Migrate the hosted database.
$dbUrl = Read-Host 'Hosted DATABASE_URL (pooler, port 5432; input is hidden)' -AsSecureString
$plainDb = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbUrl))
if (-not $plainDb.StartsWith('postgres')) { throw 'That does not look like a Postgres URL.' }

Write-Host ''
Write-Host '== Migrating the hosted database' -ForegroundColor Cyan
$env:DATABASE_URL = $plainDb
$env:DATABASE_SSL = 'true'
node infra/db/migrate.mjs up
if ($LASTEXITCODE -ne 0) { throw 'Migration failed; nothing was deployed.' }
Remove-Item Env:DATABASE_URL

# 2. Settings the live app was missing. --stage so one restart applies them
#    together with the deploy below.
Write-Host ''
Write-Host '== Fly settings' -ForegroundColor Cyan
$current = flyctl secrets list -a $App | Out-String
$pending = @()
if ($current -notmatch 'PUSH_ENABLED') { $pending += 'PUSH_ENABLED=true' }
if ($current -notmatch 'SUPABASE_URL') { $pending += 'SUPABASE_URL=https://kgsspuueiqrwsxogrwbf.supabase.co' }
if ($current -notmatch 'SUPABASE_SERVICE_ROLE_KEY') {
  $key = Read-Host 'SUPABASE_SERVICE_ROLE_KEY (Supabase > Project settings > API; input is hidden)' -AsSecureString
  $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($key))
  if ($plainKey.Length -lt 40) { throw 'That key looks too short.' }
  $pending += "SUPABASE_SERVICE_ROLE_KEY=$plainKey"
}
if ($pending.Count -gt 0) {
  Write-Host "  staging $($pending.Count) setting(s)"
  flyctl secrets set -a $App --stage @pending
  if ($LASTEXITCODE -ne 0) { throw 'Could not set Fly secrets.' }
} else {
  Write-Host '  nothing missing'
}

# 3. Deploy.
Write-Host ''
Write-Host '== Deploying' -ForegroundColor Cyan
flyctl deploy -a $App --remote-only --wait-timeout 300
if ($LASTEXITCODE -ne 0) { throw 'Deploy failed.' }

# 4. Prove it answers, and that it is the new code: the places search now
#    honours the country, so a Johannesburg suburb must not come back for ZW.
Write-Host ''
Write-Host '== Checking' -ForegroundColor Cyan
$health = Invoke-RestMethod "https://$App.fly.dev/health"
if ($health.status -ne 'ok') { throw "Health check returned $($health.status)" }
$places = Invoke-RestMethod "https://$App.fly.dev/markets/places?q=rosebank&countryCode=ZW"
if ($places.Count -gt 0) { throw 'The live API still ignores countryCode: the old code is running.' }
Write-Host 'Live and on the new code.' -ForegroundColor Green
