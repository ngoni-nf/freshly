import { useEffect, useMemo, useState } from 'react';
import { api, type CompletedJob } from '../api';
import { messageFor } from '../App';

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
      <h2>Completed jobs</h2>
      <p className="sub">
        Who attended, what was done, and whether the client was happy. Anything
        rated three or below is pulled to the top.
      </p>

      <div className="card">
        <div className="row">
          <div className="meta">
            {rows === null ? 'Loading…' : `${rows.length} job${rows.length === 1 ? '' : 's'}`}
            {unhappy > 0 && <> · <span className="tag bad">{unhappy} unhappy</span></>}
            {unreviewed > 0 && <> · <span className="tag">{unreviewed} not reviewed</span></>}
          </div>
          <div className="actions">
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
      </div>

      {error && <p className="error">{error}</p>}
      {rows !== null && visible.length === 0 && (
        <p className="empty">Nothing here for this period.</p>
      )}

      {visible.map((job) => {
        const poor = job.review !== null && job.review.rating <= 3;
        return (
          <div className="card" key={job.id}>
            <div className="row">
              <div>
                <div className="name">
                  {job.services.length ? job.services.join(' · ') : job.reference}
                </div>
                <div className="meta">
                  {job.review ? (
                    <span className={`tag ${poor ? 'bad' : 'good'}`}>
                      {'★'.repeat(job.review.rating)}
                      {'☆'.repeat(5 - job.review.rating)} {job.review.rating}/5
                    </span>
                  ) : (
                    <span className="tag warn">no review left</span>
                  )}
                  <span className="tag">{job.reference}</span>
                  <br />
                  <strong>{job.providerName ?? 'unassigned'}</strong>
                  {job.providerRating !== null && (
                    <> ({job.providerRating.toFixed(1)} avg over {job.providerRatingCount})</>
                  )}
                  {' attended '}
                  <strong>{job.clientName}</strong>
                  {job.completedAt && (
                    <> on {new Date(job.completedAt).toLocaleString()}</>
                  )}
                  <br />
                  {job.destinationAddress}
                  {job.review?.tags.length ? (
                    <>
                      <br />
                      {job.review.tags.map((t) => (
                        <span className="tag" key={t}>{t}</span>
                      ))}
                    </>
                  ) : null}
                  {job.review?.comment && (
                    <>
                      <br />
                      <em>“{job.review.comment}”</em>
                    </>
                  )}
                </div>
              </div>
              <div className="actions">
                <div className="amount">
                  {(job.total.minor / 100).toLocaleString(undefined, {
                    style: 'currency',
                    currency: job.total.currency,
                  })}
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </>
  );
}
