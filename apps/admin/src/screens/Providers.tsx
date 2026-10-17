import { useEffect, useMemo, useState } from 'react';
import { api, type Provider } from '../api';
import { messageFor } from '../App';
import { Icon, Monogram, Star } from '../ui';

type Filter = 'all' | 'online' | 'offline' | 'working' | 'idle' | 'unverified' | 'suspended';

const FILTERS: Array<{ key: Filter; label: string }> = [
  { key: 'all', label: 'Everyone' },
  { key: 'online', label: 'Online' },
  { key: 'offline', label: 'Offline' },
  { key: 'working', label: 'On a job' },
  { key: 'idle', label: 'Free now' },
  { key: 'unverified', label: 'Not verified' },
  { key: 'suspended', label: 'Suspended' },
];

/**
 * The roster.
 *
 * Loads everybody on open rather than waiting for a search. The first question
 * an operator has is "who have we got and what are they doing", and a blank
 * screen until you guess a name answers a different one.
 *
 * Online and busy are shown separately on purpose: someone online with no job
 * is spare capacity, someone mid-job is not, and treating them the same is how
 * you conclude you have cover when you do not.
 */
export function Providers({ canSuspend }: { canSuspend: boolean }) {
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<Provider[] | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function load(q = query) {
    setError(null);
    try {
      setRows(await api.searchProviders(q));
    } catch (err) {
      setError(messageFor(err));
    }
  }

  useEffect(() => {
    void load('');
    // Presence changes minute to minute; a stale roster is worse than none.
    const timer = setInterval(() => void load(), 30_000);
    return () => clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function toggle(row: Provider) {
    const next = !row.isSuspended;
    const reason = window.prompt(
      next
        ? `Why is ${row.displayName} being suspended? They will be taken offline immediately.`
        : `Why is ${row.displayName} being reinstated?`,
    );
    if (!reason) return;

    setBusy(row.id);
    try {
      await api.setSuspension(row.id, next, reason);
      setRows((current) =>
        (current ?? []).map((r) =>
          r.id === row.id ? { ...r, isSuspended: next, isOnline: next ? false : r.isOnline } : r,
        ),
      );
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  const counts = useMemo(() => {
    const all = rows ?? [];
    return {
      all: all.length,
      online: all.filter((r) => r.isOnline).length,
      offline: all.filter((r) => !r.isOnline).length,
      working: all.filter((r) => r.activeJob).length,
      idle: all.filter((r) => r.isOnline && !r.activeJob).length,
      unverified: all.filter((r) => r.kycStatus !== 'verified').length,
      suspended: all.filter((r) => r.isSuspended).length,
    } as Record<Filter, number>;
  }, [rows]);

  const visible = useMemo(() => {
    const all = rows ?? [];
    switch (filter) {
      case 'online': return all.filter((r) => r.isOnline);
      case 'offline': return all.filter((r) => !r.isOnline);
      case 'working': return all.filter((r) => r.activeJob);
      case 'idle': return all.filter((r) => r.isOnline && !r.activeJob);
      case 'unverified': return all.filter((r) => r.kycStatus !== 'verified');
      case 'suspended': return all.filter((r) => r.isSuspended);
      default: return all;
    }
  }, [rows, filter]);

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Providers</h2>
          <p className="sub">
            Everyone who has registered. Suspended and unverified accounts are
            included — they are usually the ones you are looking for.
          </p>
        </div>
      </header>

      <div className="input-group" style={{ marginBottom: 16 }}>
        <div className="input-with-icon">
          <Icon name="search" size={16} />
          <input
            placeholder="Narrow by name or phone"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && load()}
            style={{ background: 'var(--surface)', borderColor: 'var(--line)' }}
          />
        </div>
        <button className="action dark" onClick={() => load()}>
          Search
        </button>
        {query && (
          <button className="action" onClick={() => { setQuery(''); void load(''); }}>
            Clear
          </button>
        )}
      </div>

      <div className="filters" style={{ marginBottom: 20 }}>
        {FILTERS.map((f) => (
          <button
            key={f.key}
            className={`chip ${filter === f.key ? 'on' : ''}`}
            onClick={() => setFilter(f.key)}
          >
            {f.label} <span className="count">{counts[f.key] ?? 0}</span>
          </button>
        ))}
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty loading">Loading the roster…</p>}
      {rows !== null && visible.length === 0 && <p className="empty">Nobody here.</p>}

      {visible.length > 0 && (
        <div className="card flush">
          <table className="table">
            <thead>
              <tr>
                <th style={{ minWidth: 250 }}>Provider</th>
                <th>Right now</th>
                <th>Verification</th>
                <th>Services</th>
                <th className="num">Rating</th>
                <th className="num">Jobs</th>
                {canSuspend && <th />}
              </tr>
            </thead>
            <tbody>
              {visible.map((row) => (
                <tr key={row.id} className={row.isSuspended ? 'attention' : undefined}>
                  <td>
                    <div className="person">
                      <Monogram
                        name={row.displayName}
                        presence={row.activeJob ? 'busy' : row.isOnline ? 'on' : 'off'}
                      />
                      <div>
                        <div className="person-name">{row.displayName}</div>
                        <div className="person-sub">{row.phone} · {row.countryCode}</div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div className="pills">
                      {row.activeJob ? (
                        <span className="pill info">
                          <span className="dot" />
                          on a job · {row.activeJob.reference} ({row.activeJob.status.replace('_', ' ')})
                        </span>
                      ) : row.isOnline ? (
                        <span className="pill success"><span className="dot" />online, free</span>
                      ) : (
                        <span className="pill">offline</span>
                      )}
                      {row.upcomingCount > 0 && (
                        <span className="pill">{row.upcomingCount} booked ahead</span>
                      )}
                    </div>
                  </td>
                  <td>
                    <div className="pills">
                      {row.isSuspended && <span className="pill danger"><span className="dot" />suspended</span>}
                      <span className={`pill ${row.kycStatus === 'verified' ? 'success' : 'warning'}`}>
                        {row.kycStatus.replace(/_/g, ' ')}
                      </span>
                    </div>
                  </td>
                  <td className="muted" style={{ textTransform: 'capitalize', maxWidth: 200 }}>
                    {row.categories.length > 0 ? row.categories.join(', ') : '—'}
                  </td>
                  <td className="num">
                    {row.rating === 0 && row.completedJobs === 0 ? (
                      <span className="pill">New</span>
                    ) : (
                      <span className="rating"><Star /> {row.rating.toFixed(1)}</span>
                    )}
                  </td>
                  <td className="num" style={{ fontWeight: 700 }}>{row.completedJobs}</td>
                  {canSuspend && (
                    <td className="num">
                      <button
                        className={`action ${row.isSuspended ? '' : 'danger'}`}
                        disabled={busy === row.id}
                        onClick={() => toggle(row)}
                      >
                        {row.isSuspended ? 'Reinstate' : 'Suspend'}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!canSuspend && rows && rows.length > 0 && (
        <p className="empty plain">
          Suspending requires the admin role. Support accounts can review
          identity and licences.
        </p>
      )}
    </>
  );
}
