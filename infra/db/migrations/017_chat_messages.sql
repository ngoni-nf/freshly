-- ---------------------------------------------------------------------------
-- 017: In-app messaging for active bookings.
--
-- Enables communication between client and provider during the booking
-- lifecycle (accepted -> arrived -> in_progress) without revealing private
-- phone numbers.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS chat_messages (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id   UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  author_id    UUID NOT NULL REFERENCES users(id),
  body         TEXT NOT NULL,
  is_read      BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_booking ON chat_messages(booking_id, created_at);

-- RLS ensures participants can only see messages for their own bookings.
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY policy_chat_messages_participant ON chat_messages
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM bookings b
      LEFT JOIN providers p ON p.id = b.provider_id
      WHERE b.id = chat_messages.booking_id
        AND (b.client_id = auth.uid() OR p.user_id = auth.uid())
    )
  );
