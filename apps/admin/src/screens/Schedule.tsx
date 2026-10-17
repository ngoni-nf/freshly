import { useEffect, useMemo, useState } from 'react';
import { api, type ScheduledBooking } from '../api';
import { messageFor } from '../App';
import { formatMoney } from '../ui';

/**
 * The diary.
 *
 * Everything in flight or booked ahead, grouped by the day it happens. Ops
 * needs this for one reason above all: a scheduled job nobody has accepted is
 * something to fix the week before, not the morning of. Those are pulled to
 * the top of their day and marked, because they are the only rows here that
 * need somebody to act.
 *
 * Instant bookings have no scheduled time and are shown under Now — they are
 * either happening or waiting for a provider as you read.
 */
export function Schedule() {
  const [rows, setRows] = useState<ScheduledBooking[] | null>(null);
  const [days, setDays] = useState(14);
  const [error, setError] = useState<string | null>(null);

  async function load(d = days) {
    setError(null);
    try {
      setRows(await api.upcoming(d));
    } catch (err) {
      setError(messageFor(err));
    }
  }

  useEffect(() => {
    void load(days);
    const timer = setInterval(() => void load(days), 30_000);
    return () => clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [days]);

  const groups = useMemo(() => {
    const byDay = new Map<string, ScheduledBooking[]>();
    for (const b of rows ?? []) {
      const key = b.scheduledStart
        ? new Date(b.scheduledStart).toDateString()
        : 'Now';
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key)!.push(b);
    }
    // Unassigned first within each day: they are the rows that need somebody.
    for (const list of byDay.values()) {
      list.sort((a, b) => Number(Boolean(a.providerName)) - Number(Boolean(b.providerName)));
    }
    return [...byDay.entries()];
  }, [rows]);

  const unassigned = (rows ?? []).filter((b) => !b.providerName).length;

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Schedule</h2>
          <p className="sub">
            Everything happening now or booked ahead. A job with no provider is the
            one to deal with first.
          </p>
        </div>
      </header>

      <div className="toolbar">
        <div className="summary">
          {rows === null ? 'Loading…' : (
            <strong>{`${rows.length} booking${rows.length === 1 ? '' : 's'}`}</strong>
          )}
          {unassigned > 0 && (
            <span className="pill danger"><span className="dot" />{unassigned} with nobody assigned</span>
          )}
        </div>
        <div className="filters">
          {[7, 14, 30].map((d) => (
            <button
              key={d}
              className={`chip ${days === d ? 'on' : ''}`}
              onClick={() => setDays(d)}
            >
              {d} days
            </button>
          ))}
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {rows !== null && rows.length === 0 && (
        <p className="empty">Nothing booked. A quiet diary is not always good news.</p>
      )}

      {groups.map(([day, list]) => (
        <section key={day}>
          <h3 className={`day ${day === 'Now' ? 'now' : ''}`}>
            {day === 'Now' && <span className="live-dot" aria-hidden="true" />}
            {day === 'Now' ? 'Happening now' : day}
            <span className="count">{list.length}</span>
          </h3>
          <div className="card flush">
            <table className="table">
              <thead>
                <tr>
                  <th style={{ width: 110 }}>Time</th>
                  <th>Booking</th>
                  <th>Provider</th>
                  <th>Status</th>
                  <th className="num">Total</th>
                </tr>
              </thead>
              <tbody>
                {list.map((b) => (
                  <tr key={b.id} className={!b.providerName ? 'attention' : undefined}>
                    <td className="time-cell">
                      {b.scheduledStart
                        ? new Date(b.scheduledStart).toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                          })
                        : 'Now'}
                    </td>
                    <td>
                      <div style={{ fontWeight: 700 }}>
                        {b.services.length ? b.services.join(' · ') : b.reference}
                      </div>
                      <div className="muted" style={{ marginTop: 2 }}>
                        {b.reference} · {b.clientName}
                      </div>
                      <div className="muted">{b.destinationAddress}</div>
                    </td>
                    <td>
                      {b.providerName ? (
                        <span style={{ fontWeight: 600 }}>{b.providerName}</span>
                      ) : (
                        <span className="pill danger"><span className="dot" />unassigned</span>
                      )}
                      {!b.providerName && (
                        <div className="muted" style={{ marginTop: 4 }}>waiting for a provider</div>
                      )}
                    </td>
                    <td>
                      <div className="pills">
                        <span className="pill info" style={{ textTransform: 'capitalize' }}>
                          {b.status.replace('_', ' ')}
                        </span>
                        <span className="pill" style={{ textTransform: 'capitalize' }}>{b.bookingType}</span>
                      </div>
                    </td>
                    <td className="num amount">{formatMoney(b.total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ))}
    </>
  );
}
