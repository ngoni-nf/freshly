import { useCallback, useEffect, useState } from 'react';
import { api, type DocumentLinks, type KycSubmission } from '../api';
import { messageFor } from '../App';

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
      <h2>Identity review</h2>
      <p className="sub">
        Providers waiting to be verified. Nobody can accept a booking until this
        is approved.
      </p>

      <div className="notice">
        Opening a document is recorded against your account in the audit log.
        Links expire in five minutes.
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty">Loading…</p>}
      {rows?.length === 0 && <p className="empty">Nothing waiting. </p>}

      {rows?.map((row) => (
        <div className="card" key={row.id}>
          <div className="row">
            <div>
              <div className="name">{row.providerName}</div>
              <div className="meta">
                <span className={`tag ${row.status === 'in_review' ? 'warn' : ''}`}>
                  {row.status === 'in_review' ? 'needs a human' : 'awaiting vendor'}
                </span>
                <span className="tag">{row.countryCode}</span>
                <span className="tag">{row.documentType.replace(/_/g, ' ')}</span>
                <br />
                Legal name {row.legalName || 'not given'} · document ending{' '}
                {row.idNumberLast4 ?? '—'} · submitted{' '}
                {new Date(row.submittedAt).toLocaleString()}
                {row.faceMatchScore !== null && (
                  <>
                    <br />
                    Face match {(row.faceMatchScore * 100).toFixed(0)}%
                    {row.livenessScore !== null &&
                      ` · liveness ${(row.livenessScore * 100).toFixed(0)}%`}
                  </>
                )}
              </div>

              {docs[row.id] && (
                <div className="docs">
                  {Object.entries(docs[row.id]).map(([label, link]) => (
                    <a key={label} href={link.url} target="_blank" rel="noreferrer">
                      Open {label}
                    </a>
                  ))}
                </div>
              )}
            </div>

            <div className="actions">
              {row.hasDocuments && !docs[row.id] && (
                <button className="action" disabled={busy === row.id} onClick={() => view(row.id)}>
                  View documents
                </button>
              )}
              <button
                className="action danger"
                disabled={busy === row.id}
                onClick={() => decide(row, 'rejected')}
              >
                Reject
              </button>
              <button
                className="action primary"
                disabled={busy === row.id}
                onClick={() => decide(row, 'verified')}
              >
                Approve
              </button>
            </div>
          </div>
        </div>
      ))}
    </>
  );
}
