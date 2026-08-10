#!/usr/bin/env bash
#
# One-time scaffolding for the mobile apps.
#
# The repository holds hand-written Dart, the manifest, the Podfile and the
# Gradle config, but not the generated platform plumbing — Gradle wrapper,
# Xcode project, launcher icons, resource files. Those are large, machine
# specific and regenerable, so `flutter create` fills them in rather than
# living in version control.
#
# It is safe to re-run: flutter create will not overwrite files that already
# exist, so the custom AndroidManifest.xml, Info.plist and build.gradle.kts
# in this repo survive.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v flutter >/dev/null || { echo "flutter is not on PATH"; exit 1; }
flutter --version

echo
echo "==> shared core"
cd "$ROOT/packages/freshly_core"
flutter pub get

echo
echo "==> client app scaffolding"
cd "$ROOT/apps/mobile_client"
flutter create --platforms=android,ios --org africa.freshly --project-name freshly_client .
flutter pub get

echo
echo "==> analyzing"
dart analyze || true

cat <<'NEXT'

Done. To run on an emulator or device:

  cd apps/mobile_client
  flutter devices
  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
              --dart-define=REALTIME_URL=http://10.0.2.2:3000

  Android emulator reaches the host on 10.0.2.2
  iOS simulator and physical devices use your machine's LAN IP

Sign in with +27 82 111 2222 and code 000000 (OTP_DEV_BYPASS=true).
NEXT
