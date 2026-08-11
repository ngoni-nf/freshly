# Freshly — instructions for GitHub Copilot

On-demand beauty and grooming marketplace. South Africa live first, Zimbabwe
pre-configured. NestJS + PostgreSQL/PostGIS + Redis, two Flutter apps, one
shared Dart package.

`CLAUDE.md` in the repository root is the fuller version of this document and
records *why* each decision was made. Read it before any non-trivial change.

## Invariants — breaking one of these is a bug, not a refactor

- **Money is an integer count of minor units, everywhere.** `money_minor` in
  SQL, `int` in TypeScript, `Money{minor, currency}` in Dart. No floats, no
  `DECIMAL` arithmetic in application code. Rounding happens only in `applyBps`
  and `splitWithRemainder` in `apps/api/src/common/money/money.ts`.
- **The ledger nets to zero, and has exactly one writer.** Every movement goes
  through `LedgerService.write`, which calls `fn_assert_ledger_balanced` in the
  same transaction. Do not insert into `ledger_entries` anywhere else. If the
  assertion fires, the change is wrong, not the assertion.
- **The booking state machine lives in the database.** `fn_booking_status_guard`
  raises on an illegal transition. Change the truth table if a transition is
  genuinely valid; never work around the trigger.
- **The quote is server-authoritative.** The client renders `PriceQuote`
  verbatim and never recomputes a total.
- **Capture is gated on the client's PIN.** A provider can never self-declare
  `in_progress`.
- **An unverified provider cannot be paid or go online**, and an unlicensed one
  cannot list an invasive service — enforced by `trg_service_credential_guard`
  in the database, not only in application code.
- **Providers see the suburb, not the street, until they accept**
  (`maskAddress` in `dispatch.service.ts`).
- **GPS breadcrumbs live in Redis under a TTL and never reach Postgres.** POPIA
  and the Zimbabwe DPA both require personal data be kept no longer than it
  serves a purpose.
- **Market rules are data, not code.** Commission, VAT, travel tariffs and
  vendor choice are rows in `countries`. Do not add `if (country === 'ZA')` to
  the booking or payout path.
- **Anything that moves money is idempotent** and takes an `Idempotency-Key`.

## Verifying a change

```bash
npm run test -w @freshly/api          # 70 unit tests
npx tsc --noEmit -p apps/api/tsconfig.json
npm run build

cd apps/mobile_client && flutter analyze && flutter test
cd apps/mobile_partner && flutter analyze
```

Against a running API and database:

```bash
npm run db:reset
npm run api:dev
npm run smoke                     # book -> pay -> PIN -> capture -> ledger balances
bash scripts/smoke-payouts.sh     # wallet, cash-out, KYC gate, SOS
node scripts/check-credential-gate.cjs   # the licence gate, enforced by trigger
```

CI runs the unit tests, typecheck, migrations, the credential gate, and
`flutter analyze` on both apps. It must be green before a merge.

**You will not have database credentials.** `.env` is gitignored and holds a
live Supabase password. Rely on the unit tests and CI rather than trying to
reach a database, and never commit a connection string, key or token.

## Conventions

- Comments explain **why**, not what. If a line needs a comment to say what it
  does, rewrite the line.
- Errors carry a stable machine-readable `code`; clients switch on the code,
  never the message. Messages are user-facing and will be localised.
- No emoji in code, comments or commit messages.
- Dart: run `dart format .`. `require_trailing_commas` is deliberately absent —
  the tall-style formatter decides commas itself.
- Never commit `.env`, keystores, `google-services.json` or service accounts.

## Environment facts that will otherwise waste your time

- **JDK 21 is required.** Gradle 8.11.1 rejects JDK 25 with a bare `25.0.2`
  error, and Android Studio's bundled JBR on the original dev machine is
  damaged. AGP 8.9.1 and Kotlin 2.2.20 are floors, not preferences.
- **`DEV_LOCATION` is needed to test discovery on an emulator.** Every service
  area is geofenced and the emulator reports Mountain View:
  `--dart-define=DEV_LOCATION=-26.1076,28.0473`.
- **Supabase**: use the session-mode pooler on port 5432. The direct host is
  IPv6-only, and the transaction pooler on 6543 rejects the DDL the migrations
  issue.
- `public.spatial_ref_sys` will always fail Supabase's RLS lint. It belongs to
  PostGIS, is owned by `supabase_admin`, and holds the public EPSG registry.
  Suppress that finding; migration 011 covers every table we own.
- Re-running the smoke scripts trips the OTP throttle. It surfaces as
  `sign-in returned no token`, which is the limiter working.

## Not built yet

Admin portal (`apps/admin`), salon staff management, FCM push and Crashlytics,
the KYC document upload UI (the storage endpoints exist and are tested; nothing
in the apps calls them yet).

Nothing is deployed. `docs/DEPLOYMENT.md` has the runbook; the Dockerfile,
`fly.toml` and `deploy.yml` are written but have never been executed.
