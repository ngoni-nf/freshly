# Going live — your checklist

Written for you, not for an agent. Everything here needs an account, a card, a
signature or a judgement call, which is why none of it is done.

Ordered so that nothing blocks on something later in the list.

---

## Before anything else: two decisions

**1. Which region.** Supabase is in `aws-1-eu-west-1` (Ireland) for a
South-Africa-first product. A request makes several database round trips, so
API and database must live together — `fly.toml` is set to Ireland to match.
If you want to be nearer your users, move *both*, and do it now while the only
real data is seed data. Moving later means a new Supabase project and a data
migration.

**2. Whether you are taking real money yet.** Everything below assumes yes. If
you only want a pilot with cash payment, you can skip the payment gateway and
KYC vendor sections — but production refuses to boot on mock adapters, so you
would need `NODE_ENV=staging` instead.

---

## Accounts and contracts you need

| What | Why | Rough cost |
|---|---|---|
| Fly.io (or Railway/Render) | Somewhere for the API to run | ~$5–15/mo |
| Upstash Redis | Dispatch locks, OTP throttle, PIN limiter | Free tier is enough to start |
| Payment gateway (Stitch or Peach) | Taking money. **Needs a registered company and FICA** | Per-transaction |
| Smile ID | Verifying provider identity against Home Affairs | Per-check |
| An SMS provider (Gupshup/Twilio) | OTP delivery. Nothing signs in without it | Per-message |
| Firebase | Push notifications and crash reporting | Free tier |
| Google Play Developer | Shipping the Android apps | $25 once |
| Apple Developer | Only if you want iOS | $99/yr |

**The long pole is the payment gateway.** Stitch and Peach both want a
registered company, proof of address, director IDs and FICA documents, and
underwriting takes days to weeks. Start that first — everything else can be
done in an afternoon.

---

## Step by step

### 1. Redis
Create an Upstash database in the same region as the API. Copy the `rediss://`
URL. Without it nobody can sign in, dispatch cannot lock, and PIN attempts
cannot be limited.

### 2. Storage buckets
In Supabase → Storage, create three:

| Bucket | Public |
|---|---|
| `kyc-documents` | **No** |
| `portfolio` | Yes |
| `avatars` | Yes |

`kyc-documents` must be private. The API hands out five-minute signed links; a
public bucket makes every ID document a permanent URL, which is a POPIA problem
rather than a preference.

Then Settings → API, copy the Project URL and the **service_role** key. That
key bypasses every access rule — it belongs in the API's secrets and nowhere
else, never in an app or a repository.

### 3. Generate the two secrets you cannot recover

```bash
openssl rand -base64 48   # JWT_SECRET
openssl rand -base64 32   # PII_ENCRYPTION_KEY
```

**Put `PII_ENCRYPTION_KEY` in a password manager before you use it.** It
encrypts ID numbers and bank account numbers. There is no reset: lose it and
that data is gone.

### 4. Deploy the API
Follow `docs/DEPLOYMENT.md`. Be ready to iterate — the Dockerfile has never
been built and `fly deploy` will be its first real test.

### 5. Point the apps at it and get them to testers
Rebuild with `--dart-define=API_BASE_URL=https://your-app.fly.dev`, then
Firebase App Distribution for both platforms. Play Console internal testing
needs the $25 registration; TestFlight needs the Apple account.

### 6. Turn the real adapters on, one at a time
`PAYMENTS_ZA_PROVIDER`, `PAYOUTS_ZA_PROVIDER`, `KYC_PROVIDER`, `COMMS_PROVIDER`.
Each real adapter refuses to run until its outstanding contract detail is
confirmed — enabling one is deleting a guard, not writing an integration.
Do them separately and run the smoke suites between each.

---

## Before you accept a single real booking

These are not optional, and none is a coding task.

- [ ] **Company registered, bank account open, FICA done.** The gateway will
      not onboard you otherwise, and you cannot receive money you cannot bank.
- [ ] **Legal review of the credential gate.** `service_category_rules` and
      `regulated_procedures` name HPCSA, SAHPRA and municipal by-laws with
      every category default set to `false`, so nothing is currently blocked on
      my guess. Someone with actual legal advice must set those flags before
      microblading, microneedling, laser or SMP open to real providers.
- [ ] **POPIA registration.** You are processing identity documents, bank
      details and location. Register an Information Officer with the
      Information Regulator.
- [ ] **Terms and a privacy notice that match what the app does.** The app
      already tells users it processes data "in line with POPIA" — that has to
      be true and documented.
- [ ] **Insurance.** Public liability at minimum. You are sending people into
      strangers' homes, and providers into strangers' homes.
- [ ] **Decide what happens when SOS fires.** Right now it records the alert,
      texts the user's emergency contacts, and honestly tells them to call
      10111 because no response provider is contracted. That is defensible for
      a pilot only if you have decided it deliberately.
- [ ] **A real support channel.** `support_tickets` exists in the schema and
      nothing writes to it. When a provider does not arrive, someone has to
      answer the phone.

---

## Known gaps you are launching with, unless you fix them

Ordered by how likely they are to hurt.

1. **No push notifications.** Dispatch offers arrive over a websocket, so a
   backgrounded app misses them. With a 60-second offer window the job silently
   goes to someone else. This is the one I would fix first.
2. **No document upload.** A provider cannot send an ID photo, so nobody can be
   verified without you doing it by hand.
3. **No catalogue browsing in the app.** The 92-service catalogue exists and is
   queryable; the apps do not use it yet.
4. **24 npm vulnerabilities, 4 high.** `multer` is reachable through your
   upload path. Upgrade before you are public.
5. **One API instance only.** `fly.toml` pins it deliberately: socket.io needs
   its Redis adapter before a second machine, or a client connected to one
   never receives an offer published from the other.
6. **No admin portal auth beyond role.** Any account with `admin` or `support`
   can review identity documents. Fine for a founder-run pilot, not for a team.
7. **Nails is still one category** covering both extensions and pedicures — the
   one place the taxonomy granularity is still inconsistent.

---

## What is actually solid

So you know where not to spend your worry:

- Money is integer minor units end to end, and the ledger balances by
  construction — a database assertion fires on any group that does not net to
  zero, and it is exercised on every smoke run.
- The booking state machine is enforced by a database trigger, not just
  application code.
- Escrow captures only after the client's PIN, now limited to five attempts.
- An unverified provider cannot go online or be paid; an unlicensed one cannot
  list an invasive service, enforced by a trigger that also catches someone
  filing microblading under a different category.
- Identity numbers and bank details are AES-256-GCM encrypted at rest.
- GPS breadcrumbs expire in Redis and never reach Postgres.
- 70 unit tests, three end-to-end suites against the real database, CI on every
  push.
