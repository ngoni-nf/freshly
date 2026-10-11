# Backlog and agent handoff

For GitHub Copilot, Gemini in Android Studio, or any agent picking this up.
Read `.github/copilot-instructions.md` first — it has the invariants that must
not be broken. `CLAUDE.md` has the reasoning behind them.

Each item below is written to be pasted straight into a GitHub issue.

---

## Where things are

**There are three apps in the plan and only two exist.**

| Surface | Path | State |
|---|---|---|
| Customer app | `apps/mobile_client` | Built, runs |
| Provider app | `apps/mobile_partner` | Built, runs |
| **Admin / ops portal** | `apps/admin` | **Does not exist** |

`command_screen.dart` in the partner app is a *provider's* dashboard — going
online, today's jobs, earnings. It is not the ops console. The admin side has
working API endpoints that nothing calls: KYC review, credential review,
dispute handling, provider suspension. See issue #1.

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

Done and removed from this list: dispatch filters by category, checkout and
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

### 6. socket.io Redis adapter before a second instance
`fly.toml` pins one machine deliberately. Two instances without the adapter
means a client connected to machine B never receives an offer published from
machine A — silent, and only under load.

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
