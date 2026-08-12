import { useEffect, useMemo, useState } from 'react';
import { api, type Provider } from '../api';
import { messageFor } from '../App';

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
      <h2>Providers</h2>
      <p className="sub">
        Everyone who has registered. Suspended and unverified accounts are
        included — they are usually the ones you are looking for.
      </p>

      <div className="card">
        <div className="row">
          <input
            placeholder="Narrow by name or phone"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && load()}
          />
          <button className="action primary" onClick={() => load()}>
            Search
          </button>
          {query && (
            <button className="action" onClick={() => { setQuery(''); void load(''); }}>
              Clear
            </button>
          )}
        </div>
      </div>

      <div className="filters">
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
      {rows === null && <p className="empty">Loading the roster…</p>}
      {rows !== null && visible.length === 0 && <p className="empty">Nobody here.</p>}

      {visible.map((row) => (
        <div className="card" key={row.id}>
          <div className="row">
            <div>
              <div className="name">{row.displayName}</div>
              <div className="meta">
                {row.isSuspended && <span className="tag bad">suspended</span>}
                <span className={`tag ${row.kycStatus === 'verified' ? 'good' : 'warn'}`}>
                  {row.kycStatus}
                </span>
                {row.activeJob ? (
                  <span className="tag busy">
                    on a job · {row.activeJob.reference} ({row.activeJob.status.replace('_', ' ')})
                  </span>
                ) : row.isOnline ? (
                  <span className="tag good">online, free</span>
                ) : (
                  <span className="tag">offline</span>
                )}
                {row.upcomingCount > 0 && (
                  <span className="tag">{row.upcomingCount} booked ahead</span>
                )}
                <span className="tag">{row.countryCode}</span>
                <br />
                {row.phone} · {row.rating.toFixed(1)} stars · {row.completedJobs} jobs done
                {row.categories.length > 0 && (
                  <>
                    <br />
                    {row.categories.join(', ')}
                  </>
                )}
              </div>
            </div>

            {canSuspend && (
              <div className="actions">
                <button
                  className={`action ${row.isSuspended ? '' : 'danger'}`}
                  disabled={busy === row.id}
                  onClick={() => toggle(row)}
                >
                  {row.isSuspended ? 'Reinstate' : 'Suspend'}
                </button>
              </div>
            )}
          </div>
        </div>
      ))}

      {!canSuspend && rows && rows.length > 0 && (
        <p className="empty">
          Suspending requires the admin role. Support accounts can review
          identity and licences.
        </p>
      )}
    </>
  );
}
