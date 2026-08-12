import { ForbiddenException, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { NotFoundError } from '../../common/errors/domain.errors';
import { PushService } from '../notifications/push.service';

type Side = 'client' | 'provider';

/**
 * Complaints, and answering them.
 *
 * `support_tickets` has existed since the first schema and nothing ever read
 * or wrote it, which meant a customer whose provider did not arrive had
 * nowhere to go but a review. This is the smallest thing that is actually a
 * support system: raise, read, reply, close, with the reply reaching the
 * person on their phone rather than sitting in a table nobody opens.
 *
 * Client and provider complaints are separate queues. They are answered by
 * different people and mean different things — "he never arrived" and "she
 * refused to pay" are not the same work — and the side is recorded at creation
 * rather than derived later, because somebody who is both would otherwise land
 * in whichever branch was written first.
 */
@Injectable()
export class SupportService {
  constructor(
    private readonly db: DatabaseService,
    private readonly push: PushService,
  ) {}

  async raise(
    userId: string,
    input: { subject: string; body: string; bookingId?: string; raisedBy?: Side },
  ) {
    // A ticket about a booking must be about one of the user's own bookings.
    // Without this, a complaint is a way to ask whether a booking id exists.
    if (input.bookingId) {
      const owned = await this.db.queryOne<{ id: string }>(
        `SELECT b.id FROM bookings b
           LEFT JOIN providers p ON p.id = b.provider_id
          WHERE b.id = $1 AND (b.client_id = $2 OR p.user_id = $2)`,
        [input.bookingId, userId],
      );
      if (!owned) throw new NotFoundError('Booking', input.bookingId);
    }

    const row = await this.db.queryOne<{ id: string; created_at: Date }>(
      `INSERT INTO support_tickets (user_id, booking_id, subject, body, raised_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, created_at`,
      [userId, input.bookingId ?? null, input.subject, input.body, input.raisedBy ?? 'client'],
    );

    return { id: row!.id, status: 'open', createdAt: row!.created_at.toISOString() };
  }

  /** The tickets a person raised, with the whole thread. */
  async mine(userId: string) {
    const tickets = await this.db.query<Record<string, any>>(
      `SELECT id, subject, body, status, created_at, closed_at, last_staff_reply_at
         FROM support_tickets WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
      [userId],
    );
    return Promise.all(tickets.map((t) => this.withThread(t)));
  }

  /**
   * The operator queue for one side.
   *
   * Open first and oldest first inside that: the ticket that has been waiting
   * longest without an answer is the one that turns into a chargeback.
   */
  async queue(side: Side, status: 'open' | 'closed' | 'all' = 'open') {
    const tickets = await this.db.query<Record<string, any>>(
      `SELECT t.id, t.subject, t.body, t.status, t.created_at, t.closed_at,
              t.last_staff_reply_at, t.booking_id,
              u.full_name, u.phone_e164,
              b.reference AS booking_reference
         FROM support_tickets t
         JOIN users u ON u.id = t.user_id
         LEFT JOIN bookings b ON b.id = t.booking_id
        WHERE t.raised_by = $1
          AND ($2 = 'all' OR t.status = $2)
        ORDER BY (t.status = 'open') DESC, t.last_staff_reply_at NULLS FIRST, t.created_at ASC
        LIMIT 100`,
      [side, status],
    );

    return Promise.all(
      tickets.map(async (t) => ({
        ...(await this.withThread(t)),
        raisedByName: t.full_name,
        raisedByPhone: t.phone_e164,
        bookingReference: t.booking_reference ?? null,
        bookingId: t.booking_id ?? null,
      })),
    );
  }

  private async withThread(t: Record<string, any>) {
    const messages = await this.db.query<Record<string, any>>(
      `SELECT id, author_id, is_staff, body, created_at
         FROM support_ticket_messages WHERE ticket_id = $1 ORDER BY created_at ASC`,
      [t.id],
    );

    return {
      id: t.id,
      subject: t.subject,
      body: t.body,
      status: t.status,
      createdAt: t.created_at.toISOString(),
      closedAt: t.closed_at?.toISOString() ?? null,
      lastStaffReplyAt: t.last_staff_reply_at?.toISOString() ?? null,
      messages: messages.map((m) => ({
        id: m.id,
        isStaff: m.is_staff,
        body: m.body,
        createdAt: m.created_at.toISOString(),
      })),
    };
  }

  /**
   * An operator answers.
   *
   * The reply is pushed to the person's phone. A support system whose answers
   * live only in the console is one where the complainant never learns they
   * were answered, and complains again.
   */
  async reply(ticketId: string, staffUserId: string, body: string) {
    const ticket = await this.db.queryOne<{ user_id: string; subject: string; status: string }>(
      'SELECT user_id, subject, status FROM support_tickets WHERE id = $1',
      [ticketId],
    );
    if (!ticket) throw new NotFoundError('Ticket', ticketId);

    await this.db.transaction(async (tx) => {
      await tx.query(
        `INSERT INTO support_ticket_messages (ticket_id, author_id, is_staff, body)
         VALUES ($1, $2, true, $3)`,
        [ticketId, staffUserId, body],
      );
      await tx.query(
        `UPDATE support_tickets
            SET last_staff_reply_at = now(),
                status = CASE WHEN status = 'closed' THEN 'open' ELSE status END
          WHERE id = $1`,
        [ticketId],
      );
    });

    void this.push.sendToUser(ticket.user_id, {
      title: 'Freshly support replied',
      body: body.length > 120 ? `${body.slice(0, 117)}...` : body,
      data: { type: 'support.reply', ticketId },
      channelId: 'freshly_bookings',
    });

    return { ok: true };
  }

  /** The complainant adds to their own thread. */
  async addMessage(ticketId: string, userId: string, body: string) {
    const ticket = await this.db.queryOne<{ user_id: string }>(
      'SELECT user_id FROM support_tickets WHERE id = $1',
      [ticketId],
    );
    if (!ticket) throw new NotFoundError('Ticket', ticketId);
    if (ticket.user_id !== userId) {
      throw new ForbiddenException({ code: 'not_your_ticket', message: 'Not permitted' });
    }

    await this.db.query(
      `INSERT INTO support_ticket_messages (ticket_id, author_id, is_staff, body)
       VALUES ($1, $2, false, $3)`,
      [ticketId, userId, body],
    );
    // Reopens on a reply: a closed ticket someone is still writing into is not
    // closed, whatever the column says.
    await this.db.query(
      `UPDATE support_tickets SET status = 'open', closed_at = NULL WHERE id = $1`,
      [ticketId],
    );
    return { ok: true };
  }

  async close(ticketId: string, staffUserId: string, resolution: string) {
    const ticket = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM support_tickets WHERE id = $1',
      [ticketId],
    );
    if (!ticket) throw new NotFoundError('Ticket', ticketId);

    // The resolution is written into the thread rather than only onto the
    // ticket, so the person can read why it was closed.
    await this.reply(ticketId, staffUserId, resolution);
    await this.db.query(
      `UPDATE support_tickets SET status = 'closed', closed_at = now() WHERE id = $1`,
      [ticketId],
    );
    return { ok: true };
  }
}
