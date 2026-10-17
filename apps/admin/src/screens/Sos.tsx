import { useEffect, useState } from 'react';
import { api, type SosAlert } from '../api';
import { messageFor } from '../App';
import { Icon } from '../ui';

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
    <article className={`sos-card ${live ? '' : 'past'}`} key={a.id}>
      <div className="sos-head">
        {live && <span className="sos-beacon" aria-hidden="true" />}
        <div className="grow">
          <div className="who">{a.personName}</div>
          <div className="since">
            Raised {new Date(a.createdAt).toLocaleString()}
            {a.bookingReference && <> · {a.bookingReference}</>}
            {a.counterpartyName && <> · with {a.counterpartyName}</>}
          </div>
        </div>
        <span className="pill">{a.status}</span>
        <span className="pill" style={{ textTransform: 'capitalize' }}>{a.actor}</span>
      </div>

      <div className="sos-body">
        <div className="sos-cell">
          <div className="k">Ring them</div>
          <a href={`tel:${a.personPhone}`} className="sos-phone">{a.personPhone}</a>
          <div className="meta" style={{ marginTop: 4 }}>
            {a.batteryPct !== null ? <>Battery {a.batteryPct}%</> : 'Battery unknown'}
          </div>
        </div>
        <div className="sos-cell">
          <div className="k">Where they are</div>
          <div className="sos-coords">
            {a.location.lat.toFixed(5)}, {a.location.lng.toFixed(5)}
          </div>
          <div className="meta" style={{ marginTop: 4 }}>
            {a.accuracyM !== null && <>Accurate to {a.accuracyM}m · </>}
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${a.location.lat},${a.location.lng}`}
              target="_blank"
              rel="noreferrer"
            >
              open in Maps
            </a>
          </div>
        </div>
        <div className="sos-cell">
          <div className="k">Booking address</div>
          <div style={{ fontWeight: 600 }}>{a.destinationAddress ?? 'No booking address'}</div>
          {a.vehicleDescription && (
            <div className="meta" style={{ marginTop: 4 }}>Vehicle: {a.vehicleDescription}</div>
          )}
        </div>
      </div>

      {(live || a.resolutionNotes) && (
        <div className="sos-foot">
          <div className="meta">
            {a.resolutionNotes ? (
              <em>“{a.resolutionNotes}”</em>
            ) : a.status === 'acknowledged' ? (
              'Someone on the team has this alert.'
            ) : (
              'Nobody has picked this up yet.'
            )}
          </div>
          {live && (
            <div className="actions">
              {a.status !== 'acknowledged' && (
                <button className="action danger-solid lg" disabled={busy === a.id} onClick={() => acknowledge(a)}>
                  I have this
                </button>
              )}
              <button className="action lg" disabled={busy === a.id} onClick={() => resolve(a)}>
                Resolve
              </button>
            </div>
          )}
        </div>
      )}
    </article>
  );

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Emergency alerts</h2>
          <p className="sub">
            Anyone who has pressed SOS, where they are, and the number to ring.
            Refreshes every ten seconds.
          </p>
        </div>
        {active !== null && active.length > 0 && (
          <span className="pill solid-danger">{active.length} open</span>
        )}
      </header>

      {error && <p className="error">{error}</p>}

      {active === null && <p className="empty loading">Loading…</p>}
      {active?.length === 0 && (
        <div className="sos-clear">
          <span className="stat-icon"><Icon name="shield" size={22} /></span>
          <div>
            <div className="empty-title">No open alerts</div>
            <p className="meta">This screen being empty is the goal.</p>
          </div>
        </div>
      )}
      {active?.map((a) => card(a, true))}

      <div className="toolbar" style={{ marginTop: 32 }}>
        <h3 className="section-title" style={{ margin: 0 }}>Alerts already dealt with</h3>
        <button className={`chip ${showHistory ? 'on' : ''}`} onClick={() => setShowHistory((v) => !v)}>
          {showHistory ? 'Hide' : 'Show'} history
        </button>
      </div>

      {showHistory && history?.map((a) => card(a, false))}
    </>
  );
}
