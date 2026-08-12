import { useEffect, useState } from 'react';
import { api, type SosAlert } from '../api';
import { messageFor } from '../App';

/**
 * The alert board.
 *
 * Everything on this screen exists to answer two questions in the fewest
 * seconds possible: where are they, and what is the number to ring. So the
 * coordinates are exact and the phone number is a link — the masking that
 * protects a client's address everywhere else in this product would be
 * actively harmful here.
 *
 * Polled every ten seconds. Everywhere else in the console a minute of
 * staleness costs nothing; here it is the whole point.
 */
export function Sos() {
  const [active, setActive] = useState<SosAlert[] | null>(null);
  const [history, setHistory] = useState<SosAlert[] | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      setActive(await api.sosActive());
    } catch (err) {
      setError(messageFor(err));
    }
  }

  useEffect(() => {
    void load();
    const timer = setInterval(() => void load(), 10_000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    if (showHistory && history === null) {
      api.sosHistory().then(setHistory).catch((err) => setError(messageFor(err)));
    }
  }, [showHistory, history]);

  async function acknowledge(alert: SosAlert) {
    setBusy(alert.id);
    try {
      await api.sosAcknowledge(alert.id);
      await load();
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  async function resolve(alert: SosAlert) {
    const notes = window.prompt(
      `Closing the alert from ${alert.personName}. What happened and what was done?`,
    );
    if (!notes) return;

    setBusy(alert.id);
    try {
      await api.sosResolve(alert.id, notes);
      setHistory(null);
      await load();
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  const card = (a: SosAlert, live: boolean) => (
    <div className={`card ${live ? 'alert' : ''}`} key={a.id}>
      <div className="row">
        <div>
          <div className="name">
            {a.personName} <span className="tag bad">{a.status}</span>
            <span className="tag">{a.actor}</span>
          </div>
          <div className="meta">
            <a href={`tel:${a.personPhone}`} className="phone">{a.personPhone}</a>
            {a.batteryPct !== null && <> · battery {a.batteryPct}%</>}
            {a.accuracyM !== null && <> · accurate to {a.accuracyM}m</>}
            <br />
            Raised {new Date(a.createdAt).toLocaleString()}
            {a.bookingReference && <> · {a.bookingReference}</>}
            {a.counterpartyName && <> · with {a.counterpartyName}</>}
            <br />
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${a.location.lat},${a.location.lng}`}
              target="_blank"
              rel="noreferrer"
            >
              {a.location.lat.toFixed(5)}, {a.location.lng.toFixed(5)} — open in Maps
            </a>
            {a.destinationAddress && <><br />{a.destinationAddress}</>}
            {a.resolutionNotes && <><br /><em>“{a.resolutionNotes}”</em></>}
          </div>
        </div>
        {live && (
          <div className="actions">
            {a.status !== 'acknowledged' && (
              <button className="action primary" disabled={busy === a.id} onClick={() => acknowledge(a)}>
                I have this
              </button>
            )}
            <button className="action danger" disabled={busy === a.id} onClick={() => resolve(a)}>
              Resolve
            </button>
          </div>
        )}
      </div>
    </div>
  );

  return (
    <>
      <h2>Emergency alerts</h2>
      <p className="sub">
        Anyone who has pressed SOS, where they are, and the number to ring.
        Refreshes every ten seconds.
      </p>

      {error && <p className="error">{error}</p>}

      {active === null && <p className="empty">Loading…</p>}
      {active?.length === 0 && (
        <p className="empty">No open alerts. This screen being empty is the goal.</p>
      )}
      {active?.map((a) => card(a, true))}

      <div className="card">
        <div className="row">
          <div className="meta">Alerts already dealt with</div>
          <div className="actions">
            <button className="chip" onClick={() => setShowHistory((v) => !v)}>
              {showHistory ? 'Hide' : 'Show'} history
            </button>
          </div>
        </div>
      </div>

      {showHistory && history?.map((a) => card(a, false))}
    </>
  );
}
