# Freshly — working notes for Claude Code

On-demand beauty and grooming marketplace. South Africa live first, Zimbabwe
pre-configured. Clients book barbers, stylists and nail techs to their door or
at a shop; providers run their diary and get paid from the same app.

## Layout

```
apps/api              NestJS + PostgreSQL/PostGIS + Redis. Owns all business logic.
apps/mobile_client    Flutter. Customer app.       africa.freshly.client
apps/mobile_partner   Flutter. Provider app.       africa.freshly.partner
packages/freshly_core Dart. Models, API client, realtime, design system. Shared.
packages/contracts    TypeScript types shared with the (unbuilt) admin portal.
infra/db              Migrations, seeds, migrate.mjs.
scripts/              doctor.mjs, smoke.sh, bootstrap-mobile.sh, setup-local-db.sql
```

## Invariants — do not break these without a deliberate decision

**Money is integer minor units, everywhere.** `money_minor` in SQL, `int` in
TypeScript, `Money{minor, currency}` in Dart. No floats, no `DECIMAL`
arithmetic in application code. The marketplace splits one payment three ways
in two currencies; a cent of drift per booking becomes an unreconcilable
ledger within a month. `applyBps` and `splitWithRemainder` in
`apps/api/src/common/money/money.ts` are the only places rounding happens, and
`splitWithRemainder` guarantees the parts sum back to the whole.

**The quote is server-authoritative.** The client renders `PriceQuote` verbatim
and never recomputes a total. If the app and the backend could disagree about
a travel fee, the customer would be charged something other than what they
agreed to — a chargeback and a trust failure at once.

**The booking state machine lives in the database.** `fn_booking_status_guard`
in migration 006 raises on any illegal transition. The application also guards
it, but the trigger is what stops a background job, an admin script or a future
service from corrupting a booking. Never work around it; change the truth table
if a new transition is genuinely valid.

**The ledger must net to zero.** Every movement writes balanced entries through
`LedgerService.write`, which calls `fn_assert_ledger_balanced` in the same
transaction. It is the only place in the system that inserts `ledger_entries`
— escrow and payouts both go through it, because the "nets to zero" property
only holds if there is exactly one writer enforcing it. Reconciliation is one
`GROUP BY`. If a change makes that assertion fire, the change is wrong, not the
assertion.

**A payout reserves before it sends, and reverses if it fails.** Disbursement
is confirmed by webhook hours later, not by the HTTP response. So
`PayoutsService` locks the wallet and writes the ledger group in one
transaction, calls the rail outside it, and writes a mirror-image reversing
group if the money never left. Never hold a wallet row lock across a call to a
bank. Never delete ledger entries to undo something.

**An unverified provider cannot be paid and cannot go online.** `PayoutPolicy`
refuses a cash-out unless `kyc_status = 'verified'`, and losing verification
sets `is_online = false` in the same transaction as the status change. Any KYC
result the vendor mapping does not recognise becomes `in_review`, never
`verified` — the failure that matters is an unvetted person reaching a
customer's door, not a delayed approval.

**Capture is gated on the client's PIN.** The customer holds a four-digit code;
the provider types it; only then does escrow capture. "The job is done" is
asserted by the person who paid, not the person being paid. A provider can
never self-declare `in_progress` — `advanceStatus` refuses it explicitly.

**Providers see the suburb, not the street, until they accept.** `maskAddress`
in `dispatch.service.ts`. No reason to hand a client's address to eight people
who did not take the job.

**GPS breadcrumbs live in Redis under a TTL and never reach Postgres.** POPIA
and the Zimbabwe Data Protection Act both require personal information be kept
only as long as it serves a purpose. A trip breadcrumb has none once the job
ends, so it expires on its own rather than becoming a deletion job somebody has
to remember to run. Postgres holds only a coarse last-known point for dispatch
radius maths.

**Market rules are data, not code.** Commission, VAT, travel tariffs, dispatch
timings and which payment or KYC vendor to call are rows in `countries`.
Turning Zimbabwe on is an UPDATE plus a payment adapter. Do not add
`if (country === 'ZA')` to the booking or payout path.

## Current state

Working and verified: 62 unit tests green, `tsc` clean, both Flutter apps
analyze clean and build and run on an Android 16 emulator. Pricing reconciles
across a swept range of prices and distances; payout gross always splits into
exactly fee plus net across the same kind of sweep.

Modules: `payouts` (wallet, cash-out, accounts, settlement webhooks), `kyc`
(submission, manual review, signed callbacks), `safety` (SOS and emergency
contacts — both apps were already calling these and getting 404s).

Adapters follow the `PaynowGateway` precedent: the mock is fully functional so
the whole flow works locally, and the real vendor adapters are structurally
complete — auth, idempotency, signature verification, status mapping — but
refuse to run until their outstanding contract detail is confirmed. Enabling
one is deleting a guard, not writing an integration. A plausible-looking
guessed payload that pays the wrong account is worse than a refusal to start.

Not built yet: admin portal (`apps/admin`), salon staff management, Firebase
FCM and Crashlytics wiring in the apps, document/selfie upload for KYC (the
submission takes S3 keys; nothing produces them yet).

Blocked on a human: `DATABASE_URL`, so nothing has been run against a real
database yet — every claim above is from tests, typecheck and the emulator.

## Running it

```bash
npm install
npm run doctor          # Node, deps, Flutter, container runtime, PostGIS, Redis, migrations
npm run db:reset        # migrations + markets + Johannesburg demo data
npm run api:dev
npm run smoke           # sign in -> book -> pay -> PIN -> capture -> ledger balances
bash scripts/smoke-payouts.sh   # wallet, cash-out, KYC gate, SOS
```

Redis lives in the `Ubuntu` WSL distro on this machine and needs a session
holding it open, or it disappears a minute after the last WSL command:

```bash
wsl -d Ubuntu -u root -- /bin/sh -c "service redis-server start; exec sleep infinity"
```

```bash
cd apps/mobile_client
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
            --dart-define=REALTIME_URL=http://10.0.2.2:3000 \
            --dart-define=DEV_LOCATION=-26.1076,28.0473
```

`DEV_LOCATION` is required to get past discovery on an emulator. Every service
area is geofenced, the emulator reports Mountain View, and `adb emu geo fix`
answers OK while changing nothing on recent system images — so without it the
app correctly says "Freshly is not live in this area yet" and there is nothing
to test. It is read only under `kDebugMode`.

`10.0.2.2` is how the Android emulator reaches the host. Demo sign-ins:
client `+27 82 111 2222`, provider (Sipho) `+27 82 333 4444`, code `000000`
while `OTP_DEV_BYPASS=true`.

## Things that have already bitten us

- `flutter create` derives its Kotlin package from `--org` plus
  `--project-name`, giving `africa.freshly.freshly_client`. Our namespace is
  `africa.freshly.client`. Delete the generated `MainActivity`, do not rename
  the namespace.
- Flutter 3.32 moved `ThemeData`'s `*Theme` slots to `*ThemeData` types, and
  deprecated `RadioListTile.groupValue`/`onChanged` in favour of `RadioGroup`.
- go_router's `context.go` returns `void`; only `context.push` returns a
  Future. Do not wrap `go` in `unawaited`.
- `flutter_localizations` pins `intl` exactly. Any caret range that excludes
  the SDK's pinned version fails resolution before it starts.
- `compileSdk` must be 36 for the current plugin set. `targetSdk` stays 35
  deliberately — moving it opts into Android 16 behaviour changes that deserve
  their own pass.
- `require_trailing_commas` is deliberately absent from the lint rules. Dart
  3.10's tall-style formatter decides commas itself. Run `dart format .`.
- AGP must be at least 8.9.1 and Kotlin at least 2.2.20. `androidx.core` 1.17
  and `androidx.browser` 1.9 refuse to build under older AGP, and Kotlin 2.1
  hits an internal compiler error on `google_maps_flutter_android` under JDK
  21. Both are floors, not preferences. Gradle wrapper is 8.11.1 to match.
- Supabase's direct database host (`db.<ref>.supabase.co`) resolves **AAAA
  only**. On a machine without IPv6 it is simply unreachable, and the failure
  looks like a wrong password. Use the **session-mode pooler on port 5432**,
  which is IPv4 and, unlike transaction mode on 6543, supports the DDL and
  `CREATE EXTENSION` the migrations issue.
- Redis runs in the `Ubuntu` WSL distro on this machine. WSL terminates a
  distro once its last session exits — `vmIdleTimeout=-1` in `.wslconfig` does
  not prevent it on WSL 2.6 — so Redis disappears a minute after you stop
  using it and the API then fails at sign-in with `ECONNREFUSED` long after
  everything last worked. Something must hold the distro open:

  ```bash
  wsl -d Ubuntu -u root -- /bin/sh -c "service redis-server start; exec sleep infinity"
  ```

  Redis is bound to `0.0.0.0` with `protected-mode no` inside the distro,
  because binding to loopback alone was not reachable through WSL's localhost
  relay. WSL2's NAT keeps it off the LAN; do not copy that config to a server.
- Memurai (the native Windows Redis) will not install here: its MSI custom
  actions fail with `SFXCA: Failed to create temp directory. Error code 5`
  even elevated, which is Controlled Folder Access or AV, not permissions.
  WSL was the way through.
- Running the smoke scripts several times in a row trips the OTP throttle, and
  it surfaces as `sign-in returned no token` rather than anything about rate
  limiting. That is the limiter working. Clear it with:

  ```bash
  wsl -d Ubuntu -u root -- bash -lc "redis-cli --scan --pattern 'ctr:*' | xargs -r redis-cli del"
  ```
- Supabase's linter flags every `public` table without RLS. Migration 011
  enables deny-all RLS on all 48 tables we own and revokes `anon` and
  `authenticated` outright. It is defence in depth, not the primary control:
  nothing uses PostgREST, and those roles hold no USAGE on `public` anyway.
  `public.spatial_ref_sys` will keep failing that lint forever — it belongs to
  the PostGIS extension, is owned by `supabase_admin` so we cannot alter it,
  and contains the public EPSG registry. Suppress that one finding rather than
  taking ownership of an extension's tables.

## Zimbabwe is not just a second row

Paynow — EcoCash, OneMoney, InnBucks — has no authorise-then-capture
primitive. A mobile-money push either collects or it does not. The escrow
guarantee there has to come from a platform-held trust account, with release as
an internal ledger movement. That needs an RBZ-compliant arrangement before
Zimbabwe opens, and it is a commercial and legal task, not a coding one. See
`PaynowGateway`, which fails loudly rather than pretending.

## Conventions

- Comments explain *why*, not what. If a line needs a comment to say what it
  does, rewrite the line.
- Errors carry a stable machine-readable `code`; clients switch on the code,
  never the message. Messages are user-facing and will be localised.
- Anything that moves money is idempotent and takes an `Idempotency-Key`.
- Never commit `.env`, keystores, `google-services.json` or service accounts.
- No emoji in code or commit messages.

## Docs

`START_HERE.md` setup, `docs/TESTING.md` the three test layers,
`docs/SUPABASE.md` hosted database, `docs/BUILD.md` iOS and Android builds.
