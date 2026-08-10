# Building Freshly for iOS and Android

Both mobile apps are Flutter. One Dart codebase per app compiles to a native
iOS binary and a native Android binary — there is no web view anywhere in the
booking, tracking or payment path.

| App | Directory | Bundle / package id | Audience |
|---|---|---|---|
| Freshly (client) | `apps/mobile_client` | `africa.freshly.client` | Customers booking services |
| Freshly Partner | `apps/mobile_partner` | `africa.freshly.partner` | Barbers, stylists, nail techs, salons |
| Shared core | `packages/freshly_core` | — | Models, API client, realtime, theme |

Minimum targets: **iOS 13** and **Android 6.0 (API 23)**. Both floors are set
by the installed device base in South Africa and Zimbabwe rather than by what
is convenient — a meaningful share of providers are on hardware several years
old, and they are the supply side of the marketplace.

## Prerequisites

```bash
flutter --version        # 3.22 or newer, Dart 3.4+
flutter doctor           # must be clean for the platforms you intend to build
```

For iOS you additionally need macOS, Xcode 15+, and CocoaPods.

## Running locally

Start the backend first:

```bash
npm run infra:up          # Postgres + PostGIS, Redis, MinIO
npm run db:reset          # migrate + seed
npm run api:dev
```

Then the client app. Note the API host differs by platform: the Android
emulator reaches your machine on `10.0.2.2`, the iOS simulator on `localhost`.

```bash
cd apps/mobile_client
flutter pub get

# Android emulator
flutter run -d emulator-5554 \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  --dart-define=REALTIME_URL=http://10.0.2.2:3000 \
  --dart-define=MAPS_API_KEY=$MAPS_API_KEY

# iOS simulator
flutter run -d "iPhone 15" \
  --dart-define=API_BASE_URL=http://localhost:3000 \
  --dart-define=REALTIME_URL=http://localhost:3000 \
  --dart-define=MAPS_API_KEY=$MAPS_API_KEY
```

With `OTP_DEV_BYPASS=true` in the API environment, any number signs in with
the code `000000`. That flag refuses to load in production.

## Release builds

```bash
# Android App Bundle for Play Console
flutter build appbundle --release \
  --dart-define=FLAVOR=production \
  --dart-define=API_BASE_URL=https://api.freshly.africa \
  --dart-define=REALTIME_URL=https://rt.freshly.africa \
  --dart-define=MAPS_API_KEY=$MAPS_API_KEY_ANDROID

# iOS archive for App Store Connect
flutter build ipa --release \
  --dart-define=FLAVOR=production \
  --dart-define=API_BASE_URL=https://api.freshly.africa \
  --dart-define=REALTIME_URL=https://rt.freshly.africa \
  --dart-define=MAPS_API_KEY=$MAPS_API_KEY_IOS \
  --export-options-plist=ios/ExportOptions.plist
```

Signing secrets are read from the environment (`KEYSTORE_PATH`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` for Android; Xcode automatic
signing or a Fastlane match repository for iOS). Nothing is committed.

## Store submission notes

**Apple.** Every permission we request has a specific usage string in
`ios/Runner/Info.plist` explaining the benefit to the user. Vague strings are
the most common rejection reason for apps in this category. Background location
is declared because the provider app streams position while a job is live;
Review will ask what it is for, and the answer is live trip tracking, which is
an accepted use.

**Google.** The provider app requests background location for the same reason
and therefore needs the Play Console background-location declaration plus a
short demo video of the tracking screen. Budget a week for that review.

**Both stores** will ask about the SOS feature. It dispatches to a private
armed-response provider and is not a substitute for emergency services — the
in-app copy says so, and the store listing should too.
