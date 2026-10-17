import { useEffect, useMemo, useState } from 'react';
import { api, type CompletedJob } from '../api';
import { messageFor } from '../App';
import { formatMoney } from '../ui';

/**
 * Work done, and what the client thought of it.
 *
 * The rating is the reason this screen exists. An average tells you a provider
 * is fine; it does not tell you which visit went wrong, and by the time an
 * average moves the customer has already left. So unhappy jobs sort to the top
 * and are marked — the point is to catch one while somebody can still ring the
 * client back.
 *
 * Jobs with no review are shown rather than hidden. Silence after a visit is
 * itself information.
 */
export function Completed() {
  const [rows, setRows] = useState<CompletedJob[] | null>(null);
  const [days, setDays] = useState(30);
  const [unhappyOnly, setUnhappyOnly] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load(d = days) {
    setError(null);
    try {
      setRows(await api.completed(d));
    } catch (err) {
      setError(messageFor(err));
    }
  }

  useEffect(() => {
    void load(days);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [days]);

  const visible = useMemo(
    () => (rows ?? []).filter((j) => !unhappyOnly || (j.review && j.review.rating <= 3)),
    [rows, unhappyOnly],
  );

  const unhappy = (rows ?? []).filter((j) => j.review && j.review.rating <= 3).length;
  const unreviewed = (rows ?? []).filter((j) => !j.review).length;

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Completed jobs</h2>
          <p className="sub">
            Who attended, what was done, and whether the client was happy. Anything
            rated three or below is pulled to the top.
          </p>
        </div>
      </header>

      <div className="toolbar">
        <div className="summary">
          {rows === null ? 'Loading…' : (
            <strong>{`${rows.length} job${rows.length === 1 ? '' : 's'}`}</strong>
          )}
          {unhappy > 0 && <span className="pill danger"><span className="dot" />{unhappy} unhappy</span>}
          {unreviewed > 0 && <span className="pill">{unreviewed} not reviewed</span>}
        </div>
        <div className="filters">
          <button
            className={`chip ${unhappyOnly ? 'on' : ''}`}
            onClick={() => setUnhappyOnly((v) => !v)}
          >
            Only unhappy
          </button>
          {[7, 30, 90].map((d) => (
            <button key={d} className={`chip ${days === d ? 'on' : ''}`} onClick={() => setDays(d)}>
              {d} days
            </button>
          ))}
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {rows !== null && visible.length === 0 && (
        <p className="empty">Nothing here for this period.</p>
      )}

      {visible.map((job) => {
        const poor = job.review !== null && job.review.rating <= 3;
        return (
          <article
            className="card"
            key={job.id}
            style={poor ? { boxShadow: 'inset 4px 0 0 var(--crimson)' } : undefined}
          >
            <div className="row">
              <div className="grow">
                <div className="row center" style={{ justifyContent: 'flex-start', gap: 10 }}>
                  <div className="name">
                    {job.services.length ? job.services.join(' · ') : job.reference}
                  </div>
                  <span className="pill mono">{job.reference}</span>
                </div>
                <div className="meta" style={{ marginTop: 6 }}>
                  <strong style={{ color: 'var(--ink)' }}>{job.providerName ?? 'unassigned'}</strong>
                  {job.providerRating !== null && (
                    <> ({job.providerRating.toFixed(1)} avg over {job.providerRatingCount})</>
                  )}
                  {' attended '}
                  <strong style={{ color: 'var(--ink)' }}>{job.clientName}</strong>
                  {job.completedAt && (
                    <> on {new Date(job.completedAt).toLocaleString()}</>
                  )}
                  <br />
                  {job.destinationAddress}
                </div>
                {job.review?.tags.length ? (
                  <div className="pills">
                    {job.review.tags.map((t) => (
                      <span className="pill" key={t}>{t}</span>
                    ))}
                  </div>
                ) : null}
                {job.review?.comment && (
                  <div className="quote">“{job.review.comment}”</div>
                )}
              </div>
              <div style={{ textAlign: 'right', display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'flex-end' }}>
                <div className="amount">{formatMoney(job.total)}</div>
                {job.review ? (
                  <span className={`pill ${poor ? 'danger' : 'success'}`}>
                    <span className="stars" style={poor ? { color: 'var(--crimson)' } : undefined}>
                      {'★'.repeat(job.review.rating)}
                      {'☆'.repeat(5 - job.review.rating)}
                    </span>
                    {job.review.rating}/5
                  </span>
                ) : (
                  <span className="pill warning">no review left</span>
                )}
              </div>
            </div>
          </article>
        );
      })}
    </>
  );
}
