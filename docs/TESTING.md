# Testing Freshly

Three layers, in ascending order of how much they cost to run and how much
they tell you.

| Layer | Command | Needs | Runtime |
|---|---|---|---|
| Unit | `npm test` | nothing | ~3s |
| End-to-end | `npm run test:e2e` | Postgres + PostGIS, Redis | ~20s |
| Smoke | `npm run smoke` | a running API | ~30s |

## Unit tests

Pure logic, no infrastructure. These cover the arithmetic that decides what a
customer is charged and who gets paid — the pricing engine is swept across
roughly 750 price and distance combinations asserting that
`commission + provider payout + platform fee` equals the total exactly, every
time, with no cent unaccounted for.

```bash
npm test
```

Also covers the concierge's offline parser, including the case that a
substring match sent "retwist my dreads" to a braider instead of a loctician.

## End-to-end tests

Walks a real booking through the state machine against a real database:

```bash
npm run infra:up
npm run db:reset          # migrate + seed markets + demo data
RUN_E2E=1 npm run test:e2e
```

What it actually proves, none of which is verifiable by reading code:

- the escrow hold exists and `captured_minor` is still zero after checkout
- a wrong completion PIN returns 400 and does not release money
- the correct PIN, fetched by the owning client only, does
- after capture, the ledger for that booking nets to exactly zero
- Postgres itself refuses `completed -> en_route`
- one client cannot read another client's booking, and a provider cannot read
  a client's completion code

The suite skips unless `RUN_E2E=1`, so a laptop with nothing running still
gets a green `npm test`. It never silently passes — the skip is printed.

## Smoke test

The fastest way to convince yourself the whole thing works. Drives the full
path with `curl` against a running API and prints each step:

```bash
npm run infra:up && npm run db:reset
npm run api:dev           # in another terminal
npm run smoke
```

Sign in, search, quote, book, pay, dispatch, accept, PIN, complete, capture,
and a ledger balance check — with an idempotency replay in the middle to prove
a retried request cannot create a second booking or a second charge.

## Mobile

```bash
cd packages/freshly_core && flutter pub get && dart analyze --fatal-infos
cd apps/mobile_client   && flutter pub get && flutter test
```

## Continuous integration

`.github/workflows/ci.yml` runs three jobs on every push and pull request:

- **api** — migrations against a real PostGIS container, type check, unit
  tests, then the end-to-end suite with `RUN_E2E=1`
- **mobile** — `dart analyze --fatal-infos` on the shared core and the client
  app, widget tests, and an actual Android APK build
- **sql** — parses every migration and seed with `pglast`, so a syntax error
  cannot reach a deploy

## Demo credentials

`npm run db:seed` creates Johannesburg North supply, and `OTP_DEV_BYPASS=true`
makes the code `000000` for any number.

| Number | Who | Notes |
|---|---|---|
| `+27 82 111 2222` | Thandi Mokoena | Client |
| `+27 82 333 4444` | Sipho M. | Barber, online, inverter and battery clippers |
| `+27 82 555 6666` | Kabelo T. | Barber, online, no backup power |
| `+27 82 777 8888` | Lerato N. | Braids and locs, offline, generator |
| `+27 82 999 0000` | Glow Bar Rosebank | Salon, in-shop nails and brows |

Promo code `FRESH20` gives 20% off a first booking, capped at R50.

Kabelo is deliberately the one without backup power: set the grid to stage 4
and he should vanish from the feed while Sipho stays.

```sql
INSERT INTO grid_status (country_code, stage, source, effective_from)
VALUES ('ZA', 4, 'manual', now());
```
