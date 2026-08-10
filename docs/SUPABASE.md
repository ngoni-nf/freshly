# Running Freshly on Supabase

Supabase is Postgres, so every migration, the booking state-machine trigger,
the PostGIS discovery query and the double-entry ledger all run unchanged.
The only thing that changes is `DATABASE_URL`.

## 1. Create the project

Organisation `ngoni-nf's Org`, project name `freshly`, region
**Central EU (Frankfurt)**.

Two settings are deliberate:

**Region.** Supabase has no African region — the full list is the Americas,
Europe, Asia-Pacific and São Paulo. Frankfurt is the closest realistic option
for Johannesburg at roughly 150–180 ms round trip. That is fine for a pilot,
but it is real: every API call from a client's phone crosses to Europe and
back. If Freshly reaches the volume where that matters, the answer is compute
in AWS `af-south-1` (Cape Town) with Postgres alongside it, not a different
Supabase region.

**Enable Data API: off.** That switch publishes a PostgREST API over the
`public` schema. Our tables have no row-level security policies, and the anon
key ships inside both mobile apps — so leaving it on would put `bookings`,
`users` and `ledger_entries` within reach of anyone who decompiled the APK.
The apps talk to the NestJS API, which enforces authorisation properly. If you
ever do want the Data API, enable RLS on every table first.

**Database password.** Set your own and store it in a password manager. It
appears in `DATABASE_URL` and is never committed — `.env` is git-ignored.

## 2. Enable PostGIS

Dashboard → Database → Extensions → search `postgis` → enable. Or from the SQL
editor:

```sql
create extension if not exists postgis;
```

Nothing in discovery works without it: `fn_search_providers` is a single
spatial query and the migrations create `GEOGRAPHY` columns.

## 3. Point the app at it

Project settings → Database → Connection string → **URI**.

```bash
# .env
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@db.PROJECT_REF.supabase.co:5432/postgres
DATABASE_SSL=true
```

Use the **direct** connection on port 5432, not the pooler on 6543. Migrations
issue DDL and `CREATE EXTENSION`, which a transaction-mode pooler rejects.

Once you deploy the API somewhere with many short-lived connections, add the
pooler for runtime only and leave migrations on the direct URL:

```bash
DATABASE_POOL_URL=postgresql://postgres.PROJECT_REF:PASSWORD@aws-0-eu-central-1.pooler.supabase.com:6543/postgres
```

The API prefers `DATABASE_POOL_URL` when set; `migrate.mjs` always uses
`DATABASE_URL`.

## 4. Migrate and seed

```bash
npm run doctor        # confirms reachability and PostGIS
npm run db:reset      # migrations, markets, Johannesburg demo data
npm run smoke         # full booking through to a balanced ledger
```

`db:reset` drops and recreates the `public` schema. On a shared project that
would take your other tables with it — on a dedicated `freshly` project it is
exactly what you want. Use `npm run db:migrate` if you ever need to apply
migrations without dropping anything.

## What Supabase is not doing here

Only Postgres. Not Supabase Auth — the API issues its own JWTs, and phone
sign-in goes through Firebase. Not Supabase Storage, Realtime or Edge
Functions; the NestJS API owns dispatch, escrow and the websocket.

That is deliberate. Postgres is portable — the same migrations run on RDS,
Cloud SQL or a machine in Cape Town. The more of the product that leans on one
vendor's proprietary surface, the harder it is to move when latency, pricing or
data-residency rules make moving necessary. Data residency is a live question
here: POPIA does not forbid processing personal information outside South
Africa, but section 72 sets conditions, and holding Johannesburg customers'
data in Frankfurt is a decision to make deliberately rather than by default.
