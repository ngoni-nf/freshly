# Backlog and agent handoff

For GitHub Copilot, Gemini in Android Studio, or any agent picking this up.
Read `.github/copilot-instructions.md` first — it has the invariants that must
not be broken. `CLAUDE.md` has the reasoning behind them.

Each item below is written to be pasted straight into a GitHub issue.

---

## Launch blockers found in the QA pass of 17 October 2026

Found by walking the product as a new Harare barber and a new customer,
against a local API with the real migrations and seeds. Each one was
reproduced with curl; none is a guess.

### 1. A provider cannot sign up

Sign in to the provider app with a new number and the account is created
with `roles = ['client']`. Nothing in the API or the app ever adds the
`provider` role or inserts a `providers` row, so verification, going
online and the wallet all answer `insufficient_role`. Today a barber can
only be onboarded by someone running SQL. Needs: a "become a provider"
step (POST /providers/me or a flag on sign-in from the partner app) that
creates the row with `kyc_status = 'pending'`, plus the business details
screen writing display name, categories, base location and travel radius.

### 2. A provider can never cash out

`POST /payouts/accounts` creates an account with `is_verified = false`,
and nothing in the API or the admin console ever sets it to true. The
only thing that does is `scripts/smoke-payouts.sh`, with SQL. Every real
cash-out is refused with `payout_account_unverified`. Needs: a
verification step (an admin action in the console at minimum; a
penny-drop or vendor name check later).

### 3. "Pick a time" never works for a real provider

`fn_provider_is_available` requires a row in `availability_rules` for the
weekday. Only the demo seed inserts those; there is no API call and no
screen for a provider to set working hours. So every scheduled booking
for a real provider fails with `slot_unavailable`. Only "As soon as
possible" works. Needs: working-hours editing in the availability screen
and `PUT /providers/me/availability/rules`.

### Smaller findings from the same pass

- Minimum cash-out is one global setting (`payout.min_amount_minor` =
  5000). That is R50 in South Africa and $50 in Zimbabwe, five skin fades
  for a Harare barber. Make it per market.
- `review.reveal_window_hours` (14 days) is seeded but unused: a review
  is published only once both sides have reviewed, so if a provider never
  rates the client, the client's review never appears.
- KYC submission accepts no documents at all (`documentFrontKey`,
  `selfieKey` optional). The app always sends them; the API should insist.
- `/docs` (Swagger) is public on the live API. Fine for staging, off for
  production.
- `npm run lint -w @freshly/api` has never run: there is no ESLint config
  and CI does not call it.
- The outbox relay can log a failed `UPDATE` once in a few e2e runs, when
  the test closes the pool while it is draining. Harmless in production
  (the event is retried), noisy in CI.
- Fixed in the same pass (PR #4): a refused "Complete" locked its
  idempotency key forever, and the quote endpoint sent the commission and
  provider payout to customers.

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

## Priority 1 — blocking a real launch

### 1. Build the admin portal (`apps/admin`)
Nothing can review a KYC submission, approve a practitioner credential, resolve
a dispute or suspend a provider. The endpoints exist and are tested; there is
no interface. Without it, onboarding a provider requires SQL.

Endpoints already available: `POST /kyc/submissions/:id/review`,
`GET /credentials/pending`, `POST /credentials/:id/review`.

Acceptance: an operator can list pending KYC and credentials, view the
submitted documents via signed URLs, approve or reject with a reason, and see
the decision recorded in `audit_log` against their user id.

### 2. Wire FCM push and Crashlytics
Bookings work; the notification telling a provider an offer has arrived does
not. Dispatch offers currently rely on an open websocket, so a backgrounded app
misses them entirely — which for a 60-second offer window means the job goes to
someone else.

`FIREBASE_ENABLED`, `FIREBASE_PROJECT_ID` and the service account are already
in the config schema. Needs `google-services.json` per app — **never commit it**.

### 3. KYC document upload in the app
`POST /kyc/submissions` accepts S3 keys and `POST /storage/uploads` issues
signed upload URLs. Neither app calls the latter, so a provider cannot actually
send an ID document. Same gap for `credential_document`.

Acceptance: provider picks or captures an image, app requests a signed URL,
uploads directly to storage, submits the returned key. Enforce the size and
content-type limits the API returns rather than hardcoding them.

### 4. Deploy (needs accounts — see `docs/DEPLOYMENT.md`)
The Dockerfile, `fly.toml` and deploy workflow are written and have never been
executed. Expect to iterate on the first run.

---

## Priority 2 — correctness and safety

Done and removed from this list: the socket.io Redis adapter, dispatch
filters by category, checkout and
PIN entry have their own rate limits, and `expiresIn` is read from the signed
token.

### 5. Remaining vulnerable dependencies
The non-breaking fixes are applied (18 production advisories down to 8, the
critical `proxy-addr` IP-spoofing one included). What is left needs a major
upgrade or does not reach a server:

- `@nestjs/swagger` 12 for `js-yaml`. Docs endpoint only.
- `firebase` in the admin portal for `@firebase/firestore` and `@grpc/grpc-js`.
  The portal is a browser bundle that does not use Firestore; audit's
  suggested "fix" is a downgrade to firebase 9 and should not be taken.
- `gaxios` / `uuid` under `firebase-admin`, waiting on an upstream release.

Do **not** run `npm audit fix --force` blind: it bumps Nest majors. Gate any
upgrade on unit tests, `test:e2e` and both smoke suites.

### 10. Enable a real payment gateway
`PaymentsModule` runs on `MockGateway`. `StitchPayoutProvider` and
`SmileIdKycProvider` are structurally complete — auth, idempotency, signature
verification, status mapping — but refuse to run until their payload contract
is confirmed against the live account. Enabling one is deleting a guard, not
writing an integration. Production refuses to boot on mock adapters.

### 11. Zimbabwe
`PaynowGateway` fails loudly on purpose: Paynow has no authorise-then-capture,
so escrow there needs a platform-held trust account and an RBZ-compliant
arrangement. Commercial and legal work, not code.

### 12. Salon staff management
`salon_staff` and `business_mode = 'salon_staff'` exist in the schema; nothing
manages them.

### 13. Legal review of the credential gate
`service_category_rules` and `regulated_procedures` name HPCSA, SAHPRA and
municipal by-laws with every category default set to `false`, so nothing is
blocked on a guess. Someone with actual legal advice should set those flags
before these categories open to real providers.

---

## Priority 4 — quality

### 14. Split the nails category
The taxonomy still merges acrylic/gel extensions (3A) with natural nails and
pedicure (3B), the one place granularity is still inconsistent after migration
008.

### 15. Widen test coverage
70 API unit tests cover money, pricing, payout policy, KYC mapping and AI
intent. There is no coverage of the escrow capture path, the dispatch race, or
the booking state machine in TypeScript — those are only exercised by the shell
smoke tests, which need a live database.

### 16. Repair Android Studio's bundled JDK
`jbr/lib` on the dev machine contains only `fonts` and `modules`; `jvm.cfg` and
the rest are missing, so it is not a usable JDK. Temurin 21 is installed and
Flutter points at it. Worth repairing so the bundled toolchain works again.

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
