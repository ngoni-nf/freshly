import { useState } from 'react';
import { api, type Provider } from '../api';
import { messageFor } from '../App';

/**
 * Provider search and suspension.
 *
 * Suspending is the emergency lever — a complaint, a safety incident, a
 * fraudulent account — so it takes the provider offline in the same
 * transaction and requires a reason that lands in the audit log.
 */
export function Providers({ canSuspend }: { canSuspend: boolean }) {
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<Provider[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  async function search() {
    setError(null);
    try {
      setRows(await api.searchProviders(query));
    } catch (err) {
      setError(messageFor(err));
    }
  }

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
        (current ?? []).map((r) => (r.id === row.id ? { ...r, isSuspended: next, isOnline: next ? false : r.isOnline } : r)),
      );
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <h2>Providers</h2>
      <p className="sub">
        Search by name or phone. Suspended and unverified accounts are included
        — they are usually the ones you are looking for.
      </p>

      <div className="card">
        <div className="row">
          <input
            placeholder="Name or phone number"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && search()}
          />
          <button className="action primary" onClick={search}>
            Search
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty">Search to begin.</p>}
      {rows?.length === 0 && <p className="empty">Nobody matched.</p>}

      {rows?.map((row) => (
        <div className="card" key={row.id}>
          <div className="row">
            <div>
              <div className="name">{row.displayName}</div>
              <div className="meta">
                {row.isSuspended && <span className="tag bad">suspended</span>}
                <span className={`tag ${row.kycStatus === 'verified' ? 'good' : 'warn'}`}>
                  {row.kycStatus}
                </span>
                {row.isOnline && <span className="tag good">online</span>}
                <span className="tag">{row.countryCode}</span>
                <br />
                {row.phone} · {row.rating.toFixed(1)} stars · {row.completedJobs} jobs done
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
