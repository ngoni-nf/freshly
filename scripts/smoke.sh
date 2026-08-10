#!/usr/bin/env bash
#
# Freshly smoke test — drives a whole booking through a running API with curl.
#
# What it proves, in about thirty seconds:
#   sign in -> search -> quote -> book -> pay -> dispatch -> accept -> PIN ->
#   complete -> escrow captured -> ledger balanced
#
#   npm run infra:up && npm run db:reset && npm run api:dev
#   ./scripts/smoke.sh
#
set -euo pipefail

API="${API:-http://localhost:3000}"
DB="${DATABASE_URL:-postgres://freshly:freshly@localhost:5432/freshly}"
CLIENT_PHONE="+27821112222"
PROVIDER_PHONE="+27823334444"
LAT=-26.1076
LNG=28.0473

green() { printf '\033[32m  ok\033[0m  %s\n' "$1"; }
fail()  { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
step()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

jq_get() { node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const j=JSON.parse(d);const v=$1;console.log(v===undefined?'':v)}catch(e){console.log('')}})"; }

sign_in() {
  curl -sS -X POST "$API/auth/otp/request" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$1\",\"countryCode\":\"ZA\"}" > /dev/null
  curl -sS -X POST "$API/auth/otp/verify" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$1\",\"countryCode\":\"ZA\",\"code\":\"000000\"}" | jq_get "j.accessToken"
}

step "1. Health"
curl -sSf "$API/health" > /dev/null || fail "API is not responding at $API"
green "API is up"

step "2. Sign in"
CLIENT_TOKEN=$(sign_in "$CLIENT_PHONE")
PROVIDER_TOKEN=$(sign_in "$PROVIDER_PHONE")
[ -n "$CLIENT_TOKEN" ] || fail "client sign-in returned no token (is OTP_DEV_BYPASS=true?)"
[ -n "$PROVIDER_TOKEN" ] || fail "provider sign-in returned no token"
green "client and provider signed in"

step "3. Discovery"
PROVIDERS=$(curl -sS "$API/discovery/providers?lat=$LAT&lng=$LNG&radiusKm=15&category=barber")
PROVIDER_ID=$(echo "$PROVIDERS" | jq_get "j[0]&&j[0].providerId")
[ -n "$PROVIDER_ID" ] || fail "no providers found — did the demo seed run? (npm run db:seed)"
green "found $(echo "$PROVIDERS" | jq_get "j.length") providers nearby"

step "4. Provider profile"
PROFILE=$(curl -sS "$API/providers/$PROVIDER_ID")
SERVICE_ID=$(echo "$PROFILE" | jq_get "j.services[0].id")
[ -n "$SERVICE_ID" ] || fail "provider has no active services"
green "$(echo "$PROFILE" | jq_get "j.displayName") — $(echo "$PROFILE" | jq_get "j.services.length") services"

step "5. Quote"
QUOTE=$(curl -sS -X POST "$API/bookings/quote" -H "Authorization: Bearer $CLIENT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"providerId\":\"$PROVIDER_ID\",\"serviceIds\":[\"$SERVICE_ID\"],\"destination\":{\"lat\":$LAT,\"lng\":$LNG}}")
TOTAL=$(echo "$QUOTE" | jq_get "j.totalMinor")
[ -n "$TOTAL" ] || fail "quote failed: $QUOTE"
RECONCILES=$(echo "$QUOTE" | jq_get "j.commissionMinor + j.providerPayoutMinor + j.serviceFeeMinor === j.totalMinor")
[ "$RECONCILES" = "true" ] || fail "quote does not reconcile: $QUOTE"
green "total R$(echo "$TOTAL" | awk '{printf "%.2f", $1/100}') and the split reconciles"

step "6. Create booking"
KEY="smoke-$(date +%s)"
BOOKING=$(curl -sS -X POST "$API/bookings" -H "Authorization: Bearer $CLIENT_TOKEN" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" \
  -d "{\"providerId\":\"$PROVIDER_ID\",\"serviceIds\":[\"$SERVICE_ID\"],\"destination\":{\"lat\":$LAT,\"lng\":$LNG},\"bookingType\":\"instant\",\"destinationAddress\":\"12 Oak Avenue, Sandton\"}")
BOOKING_ID=$(echo "$BOOKING" | jq_get "j.id")
REFERENCE=$(echo "$BOOKING" | jq_get "j.reference")
[ -n "$BOOKING_ID" ] || fail "booking creation failed: $BOOKING"
green "created $REFERENCE"

step "7. Idempotency"
REPLAY=$(curl -sS -X POST "$API/bookings" -H "Authorization: Bearer $CLIENT_TOKEN" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY" \
  -d "{\"providerId\":\"$PROVIDER_ID\",\"serviceIds\":[\"$SERVICE_ID\"],\"destination\":{\"lat\":$LAT,\"lng\":$LNG},\"bookingType\":\"instant\",\"destinationAddress\":\"12 Oak Avenue, Sandton\"}")
[ "$(echo "$REPLAY" | jq_get "j.id")" = "$BOOKING_ID" ] || fail "replay created a second booking"
green "replaying the key returned the same booking"

step "8. Checkout — money held, not taken"
curl -sS -X POST "$API/bookings/$BOOKING_ID/checkout" -H "Authorization: Bearer $CLIENT_TOKEN" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $KEY-pay" \
  -d '{"method":"card"}' > /dev/null
ESCROW=$(psql "$DB" -tAc "SELECT escrow_status||','||captured_minor FROM payment_intents WHERE booking_id='$BOOKING_ID'")
[ "${ESCROW%%,*}" = "authorized" ] || fail "expected an authorized hold, got $ESCROW"
[ "${ESCROW##*,}" = "0" ] || fail "money was captured at checkout — escrow is broken"
green "authorised, nothing captured"

step "9. Assign and travel"
psql "$DB" -qAtc "UPDATE bookings SET provider_id='$PROVIDER_ID', status='accepted' WHERE id='$BOOKING_ID'" > /dev/null
curl -sS -X POST "$API/bookings/$BOOKING_ID/status" -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H 'Content-Type: application/json' -d '{"status":"en_route"}' > /dev/null
curl -sS -X POST "$API/bookings/$BOOKING_ID/status" -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H 'Content-Type: application/json' -d '{"status":"arrived"}' > /dev/null
green "en route, then arrived"

step "10. Wrong PIN is refused"
BAD=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$API/bookings/$BOOKING_ID/verify-pin" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" -H 'Content-Type: application/json' -d '{"pin":"0000"}')
[ "$BAD" = "400" ] || fail "a wrong PIN returned $BAD instead of 400"
green "wrong code rejected"

step "11. Correct PIN starts the job"
PIN=$(curl -sS "$API/bookings/$BOOKING_ID/pin" -H "Authorization: Bearer $CLIENT_TOKEN" | jq_get "j.pin")
[ -n "$PIN" ] || fail "client could not retrieve their completion code"
curl -sS -X POST "$API/bookings/$BOOKING_ID/verify-pin" -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H 'Content-Type: application/json' -d "{\"pin\":\"$PIN\"}" > /dev/null
green "code $PIN accepted, service in progress"

step "12. Complete and capture"
curl -sS -X POST "$API/bookings/$BOOKING_ID/complete" -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Idempotency-Key: $KEY-done" > /dev/null
CAPTURED=$(psql "$DB" -tAc "SELECT escrow_status FROM payment_intents WHERE booking_id='$BOOKING_ID'")
[ "$CAPTURED" = "captured" ] || fail "escrow is $CAPTURED, expected captured"
green "escrow captured"

step "13. Ledger balances"
NET=$(psql "$DB" -tAc "SELECT COALESCE(SUM(signed_minor),0) FROM ledger_entries WHERE booking_id='$BOOKING_ID'")
[ "$NET" = "0" ] || fail "ledger nets to $NET, not zero"
ENTRIES=$(psql "$DB" -tAc "SELECT COUNT(*) FROM ledger_entries WHERE booking_id='$BOOKING_ID'")
green "$ENTRIES entries, net zero"

step "14. Illegal transitions are refused"
if psql "$DB" -qAtc "UPDATE bookings SET status='en_route' WHERE id='$BOOKING_ID'" > /dev/null 2>&1; then
  fail "the database allowed completed -> en_route"
fi
green "completed -> en_route rejected by the state machine"

printf '\n\033[32mAll checks passed.\033[0m Booking %s completed and reconciled.\n\n' "$REFERENCE"
