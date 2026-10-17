import { useCallback, useEffect, useState } from 'react';
import { api, type DocumentLinks, type KycSubmission } from '../api';
import { messageFor } from '../App';
import { Icon, Monogram } from '../ui';

/**
 * The identity review queue.
 *
 * This is the decision that gates whether a stranger may be dispatched to a
 * customer's home, so the screen is built to make an operator look before
 * approving: the documents are one click away, the vendor's own scores are
 * shown, and rejecting requires a reason that goes back to the provider.
 */
export function KycQueue() {
  const [rows, setRows] = useState<KycSubmission[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [docs, setDocs] = useState<Record<string, DocumentLinks>>({});
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.kycPending().then(setRows).catch((err) => setError(messageFor(err)));
  }, []);

  useEffect(load, [load]);

  async function view(id: string) {
    setBusy(id);
    try {
      const links = await api.kycDocuments(id);
      setDocs((d) => ({ ...d, [id]: links }));
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  async function decide(row: KycSubmission, decision: 'verified' | 'rejected') {
    const reason =
      decision === 'rejected'
        ? window.prompt(`Why is ${row.providerName} being rejected? They will see this.`)
        : undefined;
    // A rejection with no reason is not a decision anyone can act on.
    if (decision === 'rejected' && !reason) return;

    setBusy(row.id);
    try {
      await api.reviewKyc(row.id, decision, reason ?? undefined);
      setRows((current) => (current ?? []).filter((r) => r.id !== row.id));
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Identity review</h2>
          <p className="sub">
            Providers waiting to be verified. Nobody can accept a booking until this
            is approved.
          </p>
        </div>
        {rows !== null && rows.length > 0 && (
          <span className="pill warning">{rows.length} waiting</span>
        )}
      </header>

      <div className="notice">
        <Icon name="lock" size={16} />
        <span>
          Opening a document is recorded against your account in the audit log.
          Links expire in five minutes.
        </span>
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty loading">Loading…</p>}
      {rows?.length === 0 && (
        <div className="empty">
          <div className="empty-title">Nothing waiting</div>
          New submissions appear here as providers finish onboarding.
        </div>
      )}

      {rows?.map((row) => (
        <article className="card review-card" key={row.id}>
          <div className="review-head">
            <Monogram name={row.providerName} large />
            <div className="grow">
              <div className="name" style={{ fontSize: 18 }}>{row.providerName}</div>
              <div className="pills">
                <span className={`pill ${row.status === 'in_review' ? 'warning' : 'info'}`}>
                  <span className="dot" />
                  {row.status === 'in_review' ? 'needs a human' : 'awaiting vendor'}
                </span>
                <span className="pill">{row.countryCode}</span>
                <span className="pill" style={{ textTransform: 'capitalize' }}>
                  {row.documentType.replace(/_/g, ' ')}
                </span>
              </div>
            </div>
            <div className="meta" style={{ textAlign: 'right' }}>
              Submitted
              <br />
              <strong style={{ color: 'var(--ink)' }}>
                {new Date(row.submittedAt).toLocaleString()}
              </strong>
            </div>
          </div>

          <div className="review-body">
            <div className="facts">
              <div className="fact">
                <div className="k">Legal name</div>
                <div className="v">{row.legalName || 'not given'}</div>
              </div>
              <div className="fact">
                <div className="k">Document ending</div>
                <div className="v mono">{row.idNumberLast4 ?? '—'}</div>
              </div>
              {row.faceMatchScore !== null && (
                <div className="fact">
                  <div className="k">Face match</div>
                  <div className="score">
                    <div className="meter">
                      <span style={{ width: `${row.faceMatchScore * 100}%` }} />
                    </div>
                    <span className="pct">{(row.faceMatchScore * 100).toFixed(0)}%</span>
                  </div>
                </div>
              )}
              {row.faceMatchScore !== null && row.livenessScore !== null && (
                <div className="fact">
                  <div className="k">Liveness</div>
                  <div className="score">
                    <div className="meter">
                      <span style={{ width: `${row.livenessScore * 100}%` }} />
                    </div>
                    <span className="pct">{(row.livenessScore * 100).toFixed(0)}%</span>
                  </div>
                </div>
              )}
            </div>

            <div className="doc-area">
              {docs[row.id] ? (
                <div className="doc-grid">
                  {Object.entries(docs[row.id]).map(([label, link]) => (
                    <DocTile key={label} label={label} url={link.url} />
                  ))}
                </div>
              ) : (
                <div className="doc-locked">
                  <span className="stat-icon"><Icon name="idcard" size={22} /></span>
                  {row.hasDocuments ? (
                    <>
                      <div>
                        <div className="empty-title">Look before you decide</div>
                        Compare the document with the selfie before approving.
                      </div>
                      <button className="action dark" disabled={busy === row.id} onClick={() => view(row.id)}>
                        View documents
                      </button>
                    </>
                  ) : (
                    <div>
                      <div className="empty-title">No documents uploaded</div>
                      This submission has no images attached.
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          <div className="decision-bar">
            <p className="meta">
              Approving lets {row.providerName} accept bookings and go to clients' homes.
              Rejecting sends your reason back to them.
            </p>
            <div className="actions">
              <button
                className="action danger lg"
                disabled={busy === row.id}
                onClick={() => decide(row, 'rejected')}
              >
                Reject
              </button>
              <button
                className="action primary lg"
                disabled={busy === row.id}
                onClick={() => decide(row, 'verified')}
              >
                Approve identity
              </button>
            </div>
          </div>
        </article>
      ))}
    </>
  );
}

/**
 * A signed link may be a PDF or something the browser cannot draw, so a
 * failed image falls back to a plain link rather than a broken picture.
 */
function DocTile({ label, url }: { label: string; url: string }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className="doc-tile">
      <a className="doc-frame" href={url} target="_blank" rel="noreferrer">
        {failed ? (
          <span className="doc-fallback">
            <Icon name="external" size={22} />
            Preview unavailable. Open {label}
          </span>
        ) : (
          <img src={url} alt={label} referrerPolicy="no-referrer" onError={() => setFailed(true)} />
        )}
      </a>
      <div className="doc-caption">
        <span className="doc-label">{label.replace(/_/g, ' ')}</span>
        <a href={url} target="_blank" rel="noreferrer">
          Open {label}
        </a>
      </div>
    </div>
  );
}
