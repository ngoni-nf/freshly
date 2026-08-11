# Deployment

Everything that could be prepared without your credentials is committed. What
remains needs an account, a card, or a login, and is marked **[you]**.

Read the region note before you create anything.

---

## The region decision, first

The Supabase project is in **`aws-1-eu-west-1` (Ireland)**, for a
South-Africa-first product.

That is survivable but worth understanding. A single API request makes several
database round trips. If the API runs in Johannesburg and the database stays in
Ireland, you pay the ~150 ms crossing **per query**, so a request doing six
queries costs close to a second before any work happens. Co-locating the API
with the database costs a South African user ~160 ms once, on the HTTP call.

So `fly.toml` is set to `dub` (Ireland), matching the database.

Your options:

1. **Leave it.** Ireland for both. Simplest, and the latency is acceptable for
   booking flows. This is the committed default.
2. **Move both closer.** Create a Supabase project in a region nearer South
   Africa, migrate the schema and data, then change `primary_region` in
   `fly.toml` to match. Best latency, and cheapest to do *now* while the only
   real data is demo seed data.

Do not split them.

---

## 1. Source control **[you]**

There is no git remote yet. Two commits sit on `feat/payouts-kyc-safety`.

```bash
gh repo create freshly --private --source=. --remote=origin --push
```

If you do not have the GitHub CLI, create an empty private repo in the browser,
then:

```bash
git remote add origin https://github.com/YOUR_USER/freshly.git
git push -u origin feat/payouts-kyc-safety
```

Merge to `main` when you are happy — CI runs on pull requests and on `main`.

**Never commit `.env`.** It is gitignored and contains your database password.

---

## 2. Redis **[you]**

The API needs Redis for dispatch locks, OTP throttling and GPS breadcrumbs.
The WSL instance on the development machine is not reachable from a host.

Use **Upstash** (free tier is enough to start) or Fly's own Redis. Take the
connection string; it becomes `REDIS_URL`.

Pick a region matching the API, for the same reason as the database.

---

## 3. Storage buckets **[you]**

Three buckets, created once in the Supabase dashboard under Storage:

| Bucket | Public | Holds |
|---|---|---|
| `kyc-documents` | **No** | ID documents, selfies, practitioner certificates |
| `portfolio` | Yes | Provider work photos, after moderation |
| `avatars` | Yes | Profile pictures |

`kyc-documents` must be private. The API brokers every read with a signed URL
that expires in five minutes; a public bucket would make every identity
document a permanent link. That is a POPIA problem, not a preference.

Then, from Settings → API, copy the **Project URL** and the **service_role**
key into `.env`:

```
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
```

The service role key bypasses RLS entirely. It belongs in the API process and
in no app, no browser, and no repository. Without it the API mocks uploads:
the flow works end to end, nothing is stored.

---

## 4. Deploy the API **[you]**

```bash
# Install flyctl, then:
fly auth login
fly launch --no-deploy      # accept the existing fly.toml
```

Set the secrets. These are the ones the API refuses to boot without:

```bash
fly secrets set \
  DATABASE_URL='postgresql://postgres.REF:PASSWORD@aws-1-eu-west-1.pooler.supabase.com:5432/postgres' \
  REDIS_URL='rediss://...' \
  JWT_SECRET='<64 random characters>' \
  PII_ENCRYPTION_KEY='<openssl rand -base64 32>' \
  SUPABASE_URL='https://REF.supabase.co' \
  SUPABASE_SERVICE_ROLE_KEY='...'
```

Generate the two secrets rather than inventing them:

```bash
openssl rand -base64 48   # JWT_SECRET
openssl rand -base64 32   # PII_ENCRYPTION_KEY, must decode to exactly 32 bytes
```

`PII_ENCRYPTION_KEY` encrypts ID numbers and bank account numbers. **If you
lose it, that data is unrecoverable** — there is no reset. Store it in a
password manager before you paste it.

Then:

```bash
fly deploy
```

Production refuses to start on mock adapters or a bypassed OTP. That is
deliberate — see `loadConfiguration` in `apps/api/src/common/config`. You will
need real `PAYMENTS_ZA_PROVIDER`, `PAYOUTS_ZA_PROVIDER` and `KYC_PROVIDER`
values, and their credentials, before `NODE_ENV=production` will boot.

---

## 5. Continuous deployment **[you]**

`.github/workflows/deploy.yml` runs migrations and deploys on every green CI
run against `main`. It needs three repository secrets, under
Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `FLY_API_TOKEN` | `fly tokens create deploy` |
| `DATABASE_URL` | the same session-pooler URL |
| `API_BASE_URL` | `https://your-app.fly.dev`, for the post-deploy health check |

Migrations run as a separate step *before* the deploy, so a bad migration fails
without a half-deployed container behind it.

---

## 6. Point the apps at it

Once the API has a public URL, rebuild the apps against it:

```bash
cd apps/mobile_client
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-app.fly.dev \
  --dart-define=REALTIME_URL=https://your-app.fly.dev
```

Do **not** pass `DEV_LOCATION` to a release build. It is read only under
`kDebugMode`, but leaving it out keeps the intent obvious.

---

## 7. Getting the apps to testers **[you]**

Before store release, easiest first:

- **Firebase App Distribution** — both platforms, testers by email, no store
  review. Needs a Firebase project, which you will want anyway for FCM.
- **Play Console internal testing** — up to 100 testers, near-instant, but
  needs the $25 one-off Play developer registration.
- **TestFlight** — iOS, needs an Apple Developer account at $99/yr.

Still unwired either way: FCM push and Crashlytics. Bookings will work; the
push notification telling a provider an offer arrived will not.

---

## Order of operations

1. Decide the region.
2. Create the GitHub repo, push.
3. Upstash Redis, copy the URL.
4. Supabase buckets, copy the URL and service key.
5. `fly launch`, set secrets, `fly deploy`.
6. Add the three GitHub secrets so CD works from then on.
7. Rebuild the apps against the public URL and distribute.

---

## What is not verified

Written carefully, but not run here, because none of it can be without your
accounts:

- The `Dockerfile` has never been built — there is no container runtime on the
  development machine. The build steps mirror the `npm run build` that passes
  locally, but the first `fly deploy` is its first real test.
- `fly.toml` and `deploy.yml` have never executed.
- `SupabaseStorageAdapter` has never spoken to live Storage. Its endpoints
  follow Supabase's documented Storage REST API, and the mock adapter is what
  every local run and test has exercised.

Expect to iterate on the first deploy. Nothing above depends on the parts that
*are* verified — schema, ledger, escrow, dispatch and the credential gate all
have passing end-to-end coverage against the real database.
