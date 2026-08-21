-- ---------------------------------------------------------------------------
-- Social sign-in (Google, Email) with deferred phone linking.
--
-- Until now every user was born with a verified phone: OTP, then Firebase phone
-- auth, both proved possession before a row existed. Google and Email give an
-- identity with no phone, and this marketplace cannot dispatch a provider to a
-- home, send a booking SMS, or run the escrow PIN handshake without one.
--
-- So the number becomes nullable — a social user exists but cannot yet book —
-- and firebase_uid keys that phone-less account to its Firebase identity. The
-- app walks them through phone verification (the same Firebase phone flow)
-- before the first booking, and link-phone fills the column in. The booking
-- path guards on phone_e164 being present, so a null here is a "link your
-- phone" prompt, never a dispatched job without a contactable client.
--
-- UNIQUE stays: Postgres allows many NULLs under a unique constraint, so
-- phone-less accounts coexist while every real number is still one account.
-- ---------------------------------------------------------------------------

ALTER TABLE users ALTER COLUMN phone_e164 DROP NOT NULL;

ALTER TABLE users ADD COLUMN firebase_uid VARCHAR(128) UNIQUE;

-- Social sign-in looks a user up by this on every return visit, so it wants an
-- index; partial, because the phone-first accounts that predate this leave it
-- null and there is no reason to index those.
CREATE INDEX idx_users_firebase_uid ON users (firebase_uid)
  WHERE firebase_uid IS NOT NULL;
