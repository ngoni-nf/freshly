# Freshly — start here

The project is on this machine at:

    C:\Users\Support\OneDrive - AOY-Interface\Desktop\freshly

It is already a git repository with full history, and `apps/mobile_client`
opens in Android Studio as a recognised Flutter project.

## What is left, and why

Everything up to this point is done. One step remains that requires typing
into a terminal, which is blocked for automated control on Windows — so it
needs sixty seconds from you.

`Pub get` inside Android Studio does nothing, which almost always means the
Flutter SDK path is not registered in this IDE installation. Confirm and fix
it from a terminal, which also sidesteps the IDE entirely.

## 1. Confirm Flutter is installed

Open **Git Bash** or **PowerShell** and run:

    flutter --version

If that fails, Flutter is not on PATH. Either add it, or find it with:

    where.exe flutter

## 2. Fetch packages and generate the platform plumbing

    cd "$HOME/OneDrive - AOY-Interface/Desktop/freshly"
    bash scripts/bootstrap-mobile.sh

That runs `flutter pub get` for the shared core and the client app, then
`flutter create` to fill in the Gradle wrapper and Xcode project. It will not
overwrite the AndroidManifest.xml, Info.plist, build.gradle.kts or launcher
icons already in the repo.

## 3. Start the backend

    npm install           # do this first — nothing else works without it
    npm run doctor        # checks Node, Docker/Podman, PostGIS, Redis, Flutter
    npm run infra:up      # Postgres + PostGIS, Redis, MinIO
    npm run db:reset      # migrations + markets + Johannesburg demo data
    npm run api:dev

`npm run doctor` is worth running whenever something is odd. It reports each
prerequisite separately with the command that fixes it, rather than letting
you find them one stack trace at a time.

### You do not have Docker — use your local PostgreSQL

`npm run doctor` confirmed the server is already running (it answered with an
authentication error, which means it is up and listening). It just has no
`freshly` role yet.

1. Install PostGIS if it is not there. **Application Stack Builder** ships with
   your PostgreSQL install: run it, pick your server, then
   *Spatial Extensions -> PostGIS*. Every discovery query is spatial, so this
   is not optional.

2. Create the role, database and extension in one step:

        npm run db:bootstrap

   That runs `psql -U postgres -f scripts/setup-local-db.sql` and will prompt
   for your `postgres` password. It is safe to re-run.

3. Redis, for dispatch and live tracking. You have WSL:

        wsl -e sudo apt-get update
        wsl -e sudo apt-get install -y redis-server
        wsl -e sudo service redis-server start

4. Then:

        npm run doctor        # should be all green
        npm run db:reset      # migrations + markets + demo data
        npm run api:dev

### Alternative: if you do install Docker

`infra:up` uses `docker compose`. Podman works too — alias it, or run the
services yourself. You already have PostgreSQL installed, so the local route
is:

1. Add PostGIS via **Application Stack Builder** (it ships with the PostgreSQL
   installer): Spatial Extensions -> PostGIS. Nothing spatial works without it,
   and every discovery query is spatial.
2. Create the role and database:

        psql -U postgres -c "CREATE USER freshly WITH PASSWORD 'freshly' SUPERUSER;"
        psql -U postgres -c "CREATE DATABASE freshly OWNER freshly;"

3. Redis: the simplest option on Windows is WSL, which you have —
   `wsl -e sudo apt install redis-server && wsl -e redis-server --daemonize yes`

Then `npm run doctor` should come back clean.

Verify it end to end without touching the app:

    npm run smoke

That drives sign-in, search, quote, booking, payment hold, dispatch, PIN
verification, capture and a ledger balance check, printing each step.

## 4. Run the app

Your emulator (Medium Phone API 36.1) is already configured.

    cd apps/mobile_client
    flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
                --dart-define=REALTIME_URL=http://10.0.2.2:3000

`10.0.2.2` is how the Android emulator reaches this machine's localhost.

Sign in with **+27 82 111 2222**, code **000000**.

You should see Sipho, Kabelo, Lerato and Glow Bar in the feed.

To watch the load-shedding filter work, set the grid to stage 4 and refresh —
Kabelo has no backup power and should disappear while Sipho stays:

    psql "postgres://freshly:freshly@localhost:5432/freshly" -c \
      "INSERT INTO grid_status (country_code, stage, source, effective_from)
       VALUES ('ZA', 4, 'manual', now());"

## 5. Push to GitHub

First clear two stale git lock files. They exist because the sandbox that
wrote this folder can create files here but not delete them, so an interrupted
commit left its locks behind:

    cd "$HOME/OneDrive - AOY-Interface/Desktop/freshly"
    rm -f .git/index.lock .git/HEAD.lock
    git add -A
    git commit -m "feat: partner app, Android scaffolding, CI for both apps"

The first commit is already in history; that second one picks up the partner
app and everything after it. Create an empty repo on GitHub named
`freshly`, then:

    git remote add origin https://github.com/ngoni-nf/freshly.git
    git push -u origin main

Use a personal access token when prompted for a password — GitHub stopped
accepting account passwords for git in 2021. Settings → Developer settings →
Personal access tokens → Fine-grained, with Contents: read and write.

**Change your GitHub password first.** It was pasted into a chat log earlier
in this session and should be treated as compromised.

CI runs automatically on push: API tests against a real PostGIS container,
`dart analyze` plus an Android build, and a parse check on every migration.

## Known fixes already applied

**`intl` version conflict.** Your Flutter SDK (`C:\flutter`) bundles a
`flutter_localizations` that pins `intl` to exactly 0.20.2. The pubspecs asked
for `^0.19.0`, which excludes it, so resolution failed before it started. All
three pubspecs now ask for `^0.20.2`. No code change was needed — the
`DateFormat` and `NumberFormat` calls are identical across those versions.

While fixing that I also removed dependencies nothing imports:

- `freezed`, `json_serializable` and `build_runner` from the shared core.
  Nothing in this project is code-generated — the models are hand-written
  `fromJson` factories — and those three pin the analyzer, which is the usual
  reason a package stops resolving after a Dart upgrade.
- `geolocator` from the shared core. A shared package should not force a
  platform plugin on every consumer; the apps that need position declare it.
- `google_maps_flutter`, `permission_handler` and `cached_network_image` from
  the partner app, which imports none of them.

Every remaining dependency is imported by real code. An unused native plugin
still runs its Gradle and CocoaPods work on every build and can fail on its
own, so it earns its place or it goes.

## What to send back

Whatever `flutter run` prints, errors included. First-run Gradle failures are
routine and readable.

---

## What exists right now

| Piece | State |
|---|---|
| `apps/api` | 59 TypeScript files. Boots, 28 routes, 42 unit tests green. |
| `apps/mobile_client` | Full client journey. Opens in Android Studio as a Flutter project. |
| `apps/mobile_partner` | Full provider loop: offers, job flow, PIN, wallet, availability. |
| `packages/freshly_core` | Money, models, API client, realtime, design system. Shared by both apps. |
| `infra/db` | 7 migrations, PostGIS, state-machine trigger, demo seed. |
| `.github/workflows` | API against real PostGIS, both apps analysed and built, SQL parsed. |

Not built yet: admin portal, payout and KYC provider adapters, salon staff
management. None of them block running or testing the two apps.

## Two things that need a decision from you, not code

**Zimbabwe escrow.** Paynow collects immediately and cannot hold an
authorisation, so the escrow guarantee there has to come from a platform trust
account rather than the processor. That needs an RBZ-compliant arrangement
before Zimbabwe opens. It is on the critical path for market two and it is a
commercial and legal task.

**Firebase.** Android Studio is connected to Firebase on this machine, but the
apps do not depend on it yet — I removed `firebase_core` and
`firebase_messaging` because Gradle fails without a `google-services.json`, and
a first build that dies on a missing config file teaches you nothing. When you
want push notifications: download `google-services.json` into
`apps/*/android/app/`, add the `com.google.gms.google-services` plugin back to
`android/app/build.gradle.kts`, and re-add the two packages to `pubspec.yaml`.
I have not logged into your Firebase account and would not — entering someone
else's credentials is not something I do.
