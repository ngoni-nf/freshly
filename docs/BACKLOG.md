# Backlog and agent handoff

For GitHub Copilot, Gemini in Android Studio, or any agent picking this up.
Read `.github/copilot-instructions.md` first — it has the invariants that must
not be broken. `CLAUDE.md` has the reasoning behind them.

Each item below is written to be pasted straight into a GitHub issue.

---

## QA pass of 17 October 2026

Found by walking the product as a new Harare barber and a new customer,
against a local API with the real migrations and seeds. All three launch
blockers and the smaller findings are fixed on `fix/launch-blockers`
(`test/provider-onboarding.e2e-spec.ts` walks the whole journey). Kept here
as the record of what was wrong, and for the two items that are decisions
rather than bugs.

### Fixed

- A provider could not sign up: nothing created a `providers` row. Now
  `POST /auth/become-provider` plus the "Set up your business" screen.
- A provider could never cash out: nothing verified a payout account. A
  mobile-money wallet on the provider's own number is verified at
  creation; the rest go to the ops console's payout queue.
- "Pick a time" never worked: nothing wrote working hours. Defaults at
  sign-up, editable in the availability screen, `PUT
  /providers/me/availability/rules`.
- A refused "Complete" locked its idempotency key forever (PR #4).
- The quote sent the commission and provider payout to customers (PR #4).
- The outbox relay sent every booking event as a status, so "started"
  showed as Draft in the apps.
- `review.reveal_window_hours` was never read; an hourly job publishes
  overdue reviews now.
- Minimum cash-out was one global 5000 (US$50 in Harare); it is per
  market, US$20 and R50.
- KYC accepted a submission with no documents.
- Admin badges queried `sos_alerts`, which does not exist, so the SOS
  banner could never show; market edits took column names from the body
  straight into SQL; GMV added rand and dollars together.
- ESLint had no config and never ran; it runs in CI now.
- "Suggest an extra service" pushed a route that did not exist; the
  add-on screen and `POST /bookings/:id/addons` exist now.

### Decisions still open

- **Who confirms completion.** Today the client's code starts the job and
  the provider's "complete" captures the money (after
  `escrow.capture_delay_minutes`, default 0). The original plan had the
  client's code release the money. Both are workable; pick one before
  real money. If the client should confirm, add a second code or an
  in-app "confirm" with a timeout, and move capture behind it.
- **Capture delay.** `escrow.capture_delay_minutes` is wired now (it was
  seeded and never read): above zero, a completed booking is captured by
  `CaptureDueJob` once the window passes with no open dispute. It is 0 for
  the pilot. With real money, set it to something (an hour?) so a client
  has a window to dispute before the provider is paid.

## Where things are

| Surface | Path | State |
|---|---|---|
| Customer app | `apps/mobile_client` | Built, runs |
| Provider app | `apps/mobile_partner` | Built, runs |
| Admin / ops portal | `apps/admin` | Built, deployed as the Cloudflare Worker `freshly` |

`command_screen.dart` in the partner app is a *provider's* dashboard — going
online, today's jobs, earnings. It is not the ops console; that is
`apps/admin`.

### Where the API connections live

Everything crossing a network boundary is in one of these places:

| Connection | File |
|---|---|
| Apps → API base URL | `apps/*/lib/app/env.dart` (`API_BASE_URL`, default `http://10.0.2.2:3000`) |
| **Every HTTP call the apps make** | `packages/freshly_core/lib/src/network/api_client.dart` |
| Apps → websocket | `packages/freshly_core/lib/src/realtime/realtime_client.dart` (`REALTIME_URL`) |
| API → Postgres | `apps/api/src/common/database/database.service.ts` (`DATABASE_URL`) |
| API → Redis | `apps/api/src/common/redis/redis.module.ts` (`REDIS_URL`) |
| API → payment rails | `apps/api/src/modules/payments/gateways/` |
| API → payout rails | `apps/api/src/modules/payouts/providers/` |
| API → identity vendor | `apps/api/src/modules/kyc/providers/` |
| API → emergency response | `apps/api/src/modules/safety/providers/` |
| API → file storage | `apps/api/src/modules/storage/storage.service.ts` |
| Vendors → API (inbound) | `POST /payouts/webhooks/:provider`, `POST /kyc/callbacks/:provider` |

There is exactly one HTTP client in the apps. Add endpoints to `FreshlyApi`,
never call `Dio` from a screen.

---

## What is still open, in order

Everything that used to sit under "blocking a real launch" is built: the ops
console, push and Crashlytics, document upload, the deploy, provider sign-up,
cash-out, working hours, extras, support, reviews, invoices and salon staff.
What follows needs an account, a contract or a decision rather than code.

### 1. Real money (needs contracts)
`PaymentsModule` runs on `MockGateway`. `StitchPayoutProvider`,
`PaystackGateway` and `SmileIdKycProvider` are structurally complete — auth,
idempotency, signature verification, status mapping — but refuse to run until
their payload contract is confirmed against the live account. Enabling one is
deleting a guard, not writing an integration. Production refuses to boot on
mock adapters.

Zimbabwe is the harder half: `PaynowGateway` fails loudly on purpose. Paynow
has no authorise-then-capture, so escrow there needs a platform-held trust
account and an RBZ-compliant arrangement. Commercial and legal work.

### 2. Masked calling (needs a vendor)
The chat is number-masked; calls are not. Both apps offer "Message" only
until a voice vendor with number masking is contracted. Do not add a `tel:`
link to the other party's real number.

### 3. Legal review of the credential gate
`service_category_rules` and `regulated_procedures` name HPCSA, SAHPRA and
municipal by-laws with every category default set to `false`, so nothing is
blocked on a guess. Someone with actual legal advice should set those flags
before the aesthetics categories open to real providers.

### 4. Remaining vulnerable dependencies
The non-breaking fixes are applied. What is left needs a major upgrade or does
not reach a server: `@nestjs/swagger` (docs endpoint only, off in
production), `firebase` in the admin bundle (Firestore is not used), and
`gaxios`/`uuid` under `firebase-admin` (waiting on upstream). Do **not** run
`npm audit fix --force` blind: it bumps Nest majors. Gate any upgrade on the
unit tests, `test:e2e` and both smoke suites.

### 5. iOS
PR #2 aligns the bundle identifiers. Building and TestFlight need an Apple
Developer account and either a Mac or a macOS CI runner; Firebase needs the
iOS apps and an APNs key.

### 6. Product decisions recorded above
Who confirms completion, and the capture delay. See "Decisions still open".

### 7. Quality
- The nails category merges extensions with natural nails and pedicure; the
  catalogue groups them (3A/3B) but the client's category grid does not.
- No TypeScript coverage of the dispatch race; it is exercised only by the
  shell smoke tests against a live database.
- Android Studio's bundled JDK on the dev machine is broken; Temurin 21 is
  used instead.

---

## Verifying anything

```bash
npm run test -w @freshly/api
npx tsc --noEmit -p apps/api/tsconfig.json
cd apps/mobile_client && flutter analyze && flutter test
cd apps/mobile_partner && flutter analyze
```

With a database and the API running:

```bash
npm run db:reset && npm run api:dev
npm run smoke
bash scripts/smoke-payouts.sh
node scripts/check-credential-gate.cjs
```

CI runs all of the above except the shell suites. It must be green to merge.
