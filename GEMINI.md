# Freshly — instructions for Gemini in Android Studio

You are most useful here on the **Flutter side**. The backend is complete and
verified; the apps are where the gaps are.

Read `.github/copilot-instructions.md` for the invariants that must not be
broken, and `CLAUDE.md` for why each exists. `docs/BACKLOG.md` is the full
issue list.

## The shape of things

```
apps/mobile_client    Customer app.  africa.freshly.client
apps/mobile_partner   Provider app.  africa.freshly.partner
apps/admin            Ops console (React, not Flutter — leave it alone)
packages/freshly_core Models, API client, realtime, design system. SHARED.
```

**Every HTTP call lives in `packages/freshly_core/lib/src/network/api_client.dart`.**
Add a method there and call it from a screen. Never construct a `Dio` in a
widget — the client handles auth, token refresh and the error shape, and a
screen that bypasses it will silently break session restore.

The API base URL comes from `apps/*/lib/app/env.dart`, supplied at build time:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
            --dart-define=REALTIME_URL=http://10.0.2.2:3000 \
            --dart-define=DEV_LOCATION=-26.1076,28.0473
```

`DEV_LOCATION` is not optional on an emulator. Every service area is geofenced,
the emulator claims to be in Mountain View, and `adb emu geo fix` reports OK
while changing nothing. Without it discovery correctly says "Freshly is not
live in this area yet" and you will chase a bug that is not there.

**JDK 21 is required.** Gradle 8.11.1 rejects JDK 25 with a bare `25.0.2`
error that explains nothing, and Android Studio's bundled JBR on this machine
is damaged — `jbr/lib` has only `fonts` and `modules`. Temurin 21 is installed
and Flutter is pointed at it via `flutter config --jdk-dir`.

## What to build, highest value first

### 1. Browse the catalogue — speciality, then service

This is the biggest gap and the backend for it is done and tested.

`GET /catalog/categories` returns the 15 specializations with counts.
`GET /catalog/services?category=braiding` returns the canonical menu — 92
services seeded from the provider taxonomy, each with a typical duration and
two flags: `requiresPower` and `requiresLicence`.

Today the client dashboard shows category tiles in a horizontal strip, so most
of the 15 are off-screen, and there is no way to browse *services* at all — a
customer cannot look for "Knotless braids" and see who offers it.

Build: a full-screen speciality grid, then a service list under it, then the
providers offering that service. Add `catalogServices()` and
`catalogCategories()` to `FreshlyApi`; `ServiceCategory` in `models.dart`
already has labels and icons for all 15.

### 2. Provider menu building

`GET /catalog/me/menu` and `POST /catalog/me/menu` exist. A provider picks a
template and sets their price; name, category and licence status come from the
catalogue, not from them.

The partner app has no screen for this at all — services only exist because
they were seeded. Note that adding an invasive service without a verified
licence is refused by a database trigger with a readable message; surface it
rather than swallowing it.

### 3. Scheduled versus instant on the provider dashboard

`command_screen.dart` lists today's jobs without distinguishing a booking
happening now from one scheduled for Thursday. `Booking.scheduledStart` is
already on the model and `bookingType` is `instant` or `scheduled`. Group them.

### 4. KYC document upload

`POST /storage/uploads` returns a short-lived signed URL, the size limit and
the accepted content types. `POST /kyc/submissions` then takes the returned
key. Neither app calls the first one, so a provider cannot actually send an ID
document — the verification screen collects a number and nothing else.

Enforce the limits the API returns rather than hardcoding them.

### 5. FCM push

Dispatch offers arrive over a websocket, so a backgrounded app misses them
entirely. With a 60-second offer window that means the job silently goes to
someone else. `FIREBASE_ENABLED` and the config are ready; each app needs its
own `google-services.json`, which must **never** be committed.

## How to check your work

```bash
cd apps/mobile_client && flutter analyze && flutter test
cd apps/mobile_partner && flutter analyze
```

Both are currently clean — keep them that way. `dart format .` before
committing; `require_trailing_commas` is deliberately absent because the
tall-style formatter decides commas itself.

To run against a live backend you need Postgres, Redis and the API. See
`START_HERE.md`. Redis lives in WSL on this machine and dies when its session
ends:

```bash
wsl -d Ubuntu -u root -- /bin/sh -c "service redis-server start; exec sleep infinity"
```

Demo sign-ins, code `000000` while `OTP_DEV_BYPASS=true`:
client `+27 82 111 2222`, provider `+27 82 333 4444`, ops `+27 82 000 0001`.

## Things that will mislead you

- Re-running the smoke scripts trips the OTP throttle. It appears as
  `sign-in returned no token`, which is the rate limiter working correctly.
- The emulator's IME shows a "Try out your stylus" sheet on first launch that
  swallows keystrokes. Dismiss it before automating any input.
- `nest --watch` does not restart on `.env` changes. Restart the API by hand
  after editing it, or you will test against stale configuration.

## What not to change

The money, ledger, escrow, dispatch and credential-gate rules are enforced in
the database and covered by tests. If a change makes `fn_assert_ledger_balanced`
or the booking status trigger fire, the change is wrong. Ask before touching
anything under `apps/api/src/modules/payments`, `payouts`, or the migrations.
