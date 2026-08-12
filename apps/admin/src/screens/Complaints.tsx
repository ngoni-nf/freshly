import { useEffect, useState } from 'react';
import { api, type Ticket } from '../api';
import { messageFor } from '../App';

/**
 * Complaints, and answering them.
 *
 * One component, two queues. Client and provider complaints are handled by
 * different people and mean different things — "he never arrived" and "she
 * refused to pay" are not the same work — so they are separate screens rather
 * than one list with a filter somebody forgets to set.
 *
 * Sorted by who has waited longest without a reply, because that is the one
 * that turns into a chargeback or a lost provider.
 */
export function Complaints({ side }: { side: 'clients' | 'providers' }) {
  const [rows, setRows] = useState<Ticket[] | null>(null);
  const [status, setStatus] = useState<'open' | 'closed' | 'all'>('open');
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load(s = status) {
    setError(null);
    try {
      setRows(await api.tickets(side, s));
    } catch (err) {
      setError(messageFor(err));
    }
  }

  useEffect(() => {
    void load(status);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [side, status]);

  async function send(ticket: Ticket, close: boolean) {
    const body = (drafts[ticket.id] ?? '').trim();
    if (!body) return;

    setBusy(ticket.id);
    try {
      if (close) await api.closeTicket(ticket.id, body);
      else await api.replyToTicket(ticket.id, body);
      setDrafts((d) => ({ ...d, [ticket.id]: '' }));
      await load();
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  const waiting = (rows ?? []).filter((t) => t.status === 'open' && !t.lastStaffReplyAt).length;

  return (
    <>
      <h2>{side === 'clients' ? 'Client complaints' : 'Provider complaints'}</h2>
      <p className="sub">
        {side === 'clients'
          ? 'Raised by customers. Replies are pushed to their phone.'
          : 'Raised by professionals — pay, access, difficult clients.'}
      </p>

      <div className="card">
        <div className="row">
          <div className="meta">
            {rows === null ? 'Loading…' : `${rows.length} ticket${rows.length === 1 ? '' : 's'}`}
            {waiting > 0 && <> · <span className="tag bad">{waiting} never answered</span></>}
          </div>
          <div className="actions">
            {(['open', 'closed', 'all'] as const).map((s) => (
              <button key={s} className={`chip ${status === s ? 'on' : ''}`} onClick={() => setStatus(s)}>
                {s}
              </button>
            ))}
          </div>
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {rows !== null && rows.length === 0 && <p className="empty">Nothing here. Good.</p>}

      {rows?.map((t) => (
        <div className="card" key={t.id}>
          <div className="name">{t.subject}</div>
          <div className="meta">
            <span className={`tag ${t.status === 'open' ? 'warn' : 'good'}`}>{t.status}</span>
            {!t.lastStaffReplyAt && t.status === 'open' && (
              <span className="tag bad">never answered</span>
            )}
            {t.bookingReference && <span className="tag">{t.bookingReference}</span>}
            <br />
            {t.raisedByName} · {t.raisedByPhone} ·{' '}
            {new Date(t.createdAt).toLocaleString()}
          </div>

          <p className="body">{t.body}</p>

          {t.messages.map((m) => (
            <div key={m.id} className={`bubble ${m.isStaff ? 'staff' : ''}`}>
              <div className="who">
                {m.isStaff ? 'Freshly' : t.raisedByName} ·{' '}
                {new Date(m.createdAt).toLocaleString()}
              </div>
              {m.body}
            </div>
          ))}

          <div className="row">
            <input
              placeholder={t.status === 'closed' ? 'Reopen with a reply…' : 'Write a reply…'}
              value={drafts[t.id] ?? ''}
              onChange={(e) => setDrafts((d) => ({ ...d, [t.id]: e.target.value }))}
              onKeyDown={(e) => e.key === 'Enter' && send(t, false)}
            />
            <div className="actions">
              <button
                className="action primary"
                disabled={busy === t.id || !(drafts[t.id] ?? '').trim()}
                onClick={() => send(t, false)}
              >
                Reply
              </button>
              {t.status === 'open' && (
                <button
                  className="action"
                  disabled={busy === t.id || !(drafts[t.id] ?? '').trim()}
                  onClick={() => send(t, true)}
                  title="Sends this as the resolution and closes the ticket"
                >
                  Reply and close
                </button>
              )}
            </div>
          </div>
        </div>
      ))}
    </>
  );
}
