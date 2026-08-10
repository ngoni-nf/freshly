-- ============================================================================
-- 007  Completion PIN storage
--
-- The PIN has two jobs that a single hash cannot serve:
--   - the provider submits a candidate, which we verify  -> needs a hash
--   - the client must be shown their own code on demand  -> needs to be
--     recoverable
--
-- So it is stored twice: a peppered SHA-256 for constant-time verification,
-- and an AES-256-GCM ciphertext that only the API process can open. The
-- database alone never yields a usable code.
-- ============================================================================

ALTER TABLE bookings ADD COLUMN completion_pin_enc BYTEA;

COMMENT ON COLUMN bookings.completion_pin_hash IS
  'Peppered SHA-256 of the 4-digit completion code, used for verification only.';
COMMENT ON COLUMN bookings.completion_pin_enc IS
  'AES-256-GCM ciphertext of the same code so the owning client can retrieve it.';
