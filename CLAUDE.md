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
`EscrowService.writeEntries`, which calls `fn_assert_ledger_balanced` in the
same transaction. Reconciliation is one `GROUP BY`. If a change makes that
assertion fire, the change is wrong, not the assertion.

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

Working and verified: API boots, 28 routes, 42 unit tests green, `tsc` clean.
Pricing reconciles across a swept range of prices and distances. Both Flutter
apps compile against Flutter 3.38 / Dart 3.10.

Not built yet: admin portal (`apps/admin`), payout and KYC provider adapters,
salon staff management, Firebase FCM and Crashlytics wiring in the apps.

Blocked on a human: the Supabase database password, hence `DATABASE_URL` in
`.env` is still a placeholder.

## Running it

```bash
npm install
npm run doctor          # Node, deps, Flutter, container runtime, PostGIS, Redis, migrations
npm run db:reset        # migrations + markets + Johannesburg demo data
npm run api:dev
npm run smoke           # sign in -> book -> pay -> PIN -> capture -> ledger balances
```

```bash
cd apps/mobile_client
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
            --dart-define=REALTIME_URL=http://10.0.2.2:3000
```

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
