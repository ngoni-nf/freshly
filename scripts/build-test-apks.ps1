# ---------------------------------------------------------------------------
# Builds both Android apps for testing on a real phone, pointed at the live
# staging API, and copies them to Documents\Freshly-APKs.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-test-apks.ps1
#
# Built here rather than in CI on purpose. Phone sign-in on Android only works
# when the APK's signing certificate is registered in Firebase, and the one
# registered for the client app is this machine's debug key. A CI runner signs
# with a different key, and sign-in would fail on every tester's phone.
#
# Release mode, debug-signed (build.gradle.kts falls back to the debug key when
# no KEYSTORE_PATH is set): fast and small like a store build, installable by
# sideloading. Not for the Play Store.
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

$Api = 'https://freshly-api.fly.dev'
$Root = Split-Path -Parent $PSScriptRoot
$Out = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Freshly-APKs'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'flutter is not on PATH. Open the terminal you normally run flutter from.'
}

# Each app needs its own Firebase config, which is never committed. Without it
# the build stops at :app:processReleaseGoogleServices with a message about
# the Gradle plugin rather than about the missing file.
$missing = @()
foreach ($app in 'mobile_client', 'mobile_partner') {
  $json = Join-Path $Root "apps\$app\android\app\google-services.json"
  if (-not (Test-Path $json)) { $missing += $json }
}
if ($missing.Count -gt 0) {
  Write-Host ''
  Write-Host 'Missing Firebase config:' -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  $_" }
  Write-Host ''
  Write-Host 'Download each from Firebase console > Project settings > Your apps >'
  Write-Host '(Freshly / Freshly Partner) > google-services.json, and save it at the path above.'
  exit 1
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

foreach ($pair in @(@('mobile_client', 'freshly-client.apk'), @('mobile_partner', 'freshly-partner.apk'))) {
  $app = $pair[0]; $name = $pair[1]
  Write-Host ''
  Write-Host "== $app" -ForegroundColor Cyan
  Push-Location (Join-Path $Root "apps\$app")
  try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed for $app" }
    flutter build apk --release `
      "--dart-define=API_BASE_URL=$Api" `
      "--dart-define=REALTIME_URL=$Api" `
      '--dart-define=FLAVOR=staging'
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed for $app" }
    Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' (Join-Path $Out $name) -Force
  } finally {
    Pop-Location
  }
}

# The fingerprint Firebase must have for phone sign-in to work in these builds.
# If it does not match what is listed under each app in Firebase > Project
# settings, add it there (Add fingerprint), or sign-in fails on the phone.
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if ((Test-Path $keystore) -and (Get-Command keytool -ErrorAction SilentlyContinue)) {
  Write-Host ''
  Write-Host 'Signing fingerprint (must be registered for BOTH apps in Firebase):' -ForegroundColor Yellow
  keytool -list -v -keystore $keystore -alias androiddebugkey -storepass android -keypass android |
    Select-String 'SHA1:'
}

Write-Host ''
Write-Host "Done. Copy these to the phone and open them to install:" -ForegroundColor Green
Get-ChildItem $Out -Filter *.apk | ForEach-Object { Write-Host "  $($_.FullName)  ($([math]::Round($_.Length / 1MB, 1)) MB)" }
