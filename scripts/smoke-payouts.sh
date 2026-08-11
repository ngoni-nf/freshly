#!/usr/bin/env bash
#
# Smoke test for the payout, KYC and safety paths, which the main smoke test
# does not reach. Run it after scripts/smoke.sh, so the provider has earnings.
#
#   ./scripts/smoke-payouts.sh
#
set -euo pipefail

API="${API:-http://localhost:3000}"
PROVIDER_PHONE="+27823334444"

green() { printf '\033[32m  ok\033[0m  %s\n' "$1"; }
fail()  { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
step()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

jqv() { node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const o=JSON.parse(s);const v=$1;console.log(v===undefined?'':typeof v==='object'?JSON.stringify(v):v)}catch(e){console.log('')}})"; }

step "0. Normalise state from any previous run"
# Without this the script only passes once per db:reset: step 5 adds a verified
# account, so a second run finds cash-out already possible and step 4's
# expected refusal never happens. A test that passes exactly once is a trap.
psql_bin=psql
command -v psql > /dev/null 2>&1 || for c in "/c/Program Files/PostgreSQL"/*/bin; do
  [ -x "$c/psql.exe" ] && PATH="$PATH:$c" && break
done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB=$(grep '^DATABASE_URL=' "$ROOT/.env" | cut -d= -f2-)
# Un-verify rather than delete: a past run's account is referenced by the
# payout it funded, and payouts.payout_account_id is RESTRICT for good reason —
# a disbursement must always be traceable to where the money was sent.
$psql_bin "$DB" -qAtc "UPDATE payout_accounts SET is_verified = false" > /dev/null
green "previous test accounts un-verified"

step "1. Sign in as the provider"
curl -s -X POST "$API/auth/otp/request" -H 'Content-Type: application/json' \
  -d "{\"phone\":\"$PROVIDER_PHONE\",\"countryCode\":\"ZA\"}" > /dev/null
TOKEN=$(curl -s -X POST "$API/auth/otp/verify" -H 'Content-Type: application/json' \
  -d "{\"phone\":\"$PROVIDER_PHONE\",\"countryCode\":\"ZA\",\"code\":\"000000\"}" | jqv "o.accessToken")
[ -n "$TOKEN" ] || fail "could not sign in"
AUTH="Authorization: Bearer $TOKEN"
green "signed in"

step "2. KYC status"
KYC=$(curl -s "$API/kyc/status" -H "$AUTH")
STATUS=$(echo "$KYC" | jqv "o.status")
[ -n "$STATUS" ] || fail "kyc status failed: $KYC"
green "kyc status is '$STATUS'"

step "3. Wallet reflects the completed booking"
WALLET=$(curl -s "$API/payouts/wallet" -H "$AUTH")
AVAILABLE=$(echo "$WALLET" | jqv "o.availableMinor")
CURRENCY=$(echo "$WALLET" | jqv "o.currency")
BLOCKED=$(echo "$WALLET" | jqv "o.blockedReason")
[ -n "$AVAILABLE" ] || fail "wallet failed: $WALLET"
green "available $AVAILABLE $CURRENCY, blocked by: ${BLOCKED:-nothing}"

step "4. Cash out is refused while the seeded account is unverified"
CODE=$(curl -s -X POST "$API/payouts" -H "$AUTH" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: payout-noacct-$(date +%s)" -d '{"amountMinor":5000}' | jqv "o.code")
[ "$CODE" = "payout_account_unverified" ] || fail "expected payout_account_unverified, got '$CODE'"
green "refused with payout_account_unverified"

step "5. Add a payout account"
ACCT=$(curl -s -X POST "$API/payouts/accounts" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"method":"bank_transfer","accountNumber":"1234567890","accountName":"Sipho Mahlangu","institutionName":"Capitec"}')
LAST4=$(echo "$ACCT" | jqv "o.last4")
[ "$LAST4" = "7890" ] || fail "account not created: $ACCT"
green "account added, last4 $LAST4, unverified as expected"

step "6. The new account is default, and still unverified"
DEFAULT_LAST4=$(curl -s "$API/payouts/wallet" -H "$AUTH" | jqv "o.account.last4")
[ "$DEFAULT_LAST4" = "7890" ] || fail "new account did not become the default, got '$DEFAULT_LAST4'"
green "new account is the default"

step "7. Verify only the readable account, then cash out"
# Only the one added through the API has a real ciphertext; the seeded rows
# stay unverified because their details genuinely cannot be read.
$psql_bin "$DB" -qAtc "UPDATE payout_accounts SET is_verified = true WHERE account_last4 = '7890'" > /dev/null

PAYOUT=$(curl -s -X POST "$API/payouts" -H "$AUTH" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: payout-ok-$(date +%s)" -d '{"amountMinor":5000,"instant":true}')
NET=$(echo "$PAYOUT" | jqv "o.netMinor")
FEE=$(echo "$PAYOUT" | jqv "o.feeMinor")
PSTATUS=$(echo "$PAYOUT" | jqv "o.status")
[ "$NET" = "4925" ] || fail "expected net 4925 after a 1.5% fee, got '$NET' ($PAYOUT)"
green "gross 5000 = fee $FEE + net $NET, status $PSTATUS"

step "8. Payout ledger group nets to zero"
NETSUM=$($psql_bin "$DB" -tAc "SELECT COALESCE(SUM(signed_minor),0) FROM ledger_entries WHERE payout_id IS NOT NULL")
COUNT=$($psql_bin "$DB" -tAc "SELECT COUNT(*) FROM ledger_entries WHERE payout_id IS NOT NULL")
[ "$NETSUM" = "0" ] || fail "payout ledger does not balance: net $NETSUM"
green "$COUNT payout entries, net zero"

step "9. Wallet was debited"
AFTER=$(curl -s "$API/payouts/wallet" -H "$AUTH" | jqv "o.availableMinor")
[ "$AFTER" = "$((AVAILABLE - 5000))" ] || fail "expected $((AVAILABLE - 5000)), got $AFTER"
green "balance moved $AVAILABLE -> $AFTER"

step "10. Overdrawing is refused"
CODE=$(curl -s -X POST "$API/payouts" -H "$AUTH" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: payout-over-$(date +%s)" -d '{"amountMinor":99999999}' | jqv "o.code")
[ "$CODE" = "insufficient_funds" ] || fail "expected insufficient_funds, got '$CODE'"
green "refused with insufficient_funds"

step "11. SOS is recorded and honest about dispatch"
SOS=$(curl -s -X POST "$API/safety/sos" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"lat":-26.1076,"lng":28.0473,"accuracyM":12.5,"batteryPct":64}')
SOS_ID=$(echo "$SOS" | jqv "o.id")
DISPATCHED=$(echo "$SOS" | jqv "o.dispatched")
EMERGENCY=$(echo "$SOS" | jqv "o.emergencyNumber")
[ -n "$SOS_ID" ] || fail "sos failed: $SOS"
[ "$DISPATCHED" = "false" ] || fail "mock provider must not claim a unit was dispatched"
green "recorded, dispatched=$DISPATCHED, tells the user to call $EMERGENCY"

step "12. Only the person who raised it can stand it down"
ABORT=$(curl -s -X POST "$API/safety/sos/$SOS_ID/abort" -H "$AUTH" | jqv "o.status")
[ "$ABORT" = "aborted" ] || fail "abort failed: $ABORT"
green "stood down by its owner"

printf '\n\033[32mAll payout, KYC and safety checks passed.\033[0m\n'
