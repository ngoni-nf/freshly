import { useCallback, useEffect, useState } from 'react';
import { api, type Credential } from '../api';
import { messageFor } from '../App';
import { Icon, Monogram } from '../ui';

const KIND_LABEL: Record<string, string> = {
  skin_penetration_permit: 'Skin penetration permit',
  aesthetics_practitioner: 'Aesthetics practitioner',
  laser_operator: 'Laser operator',
};

/**
 * Practitioner licences for invasive work.
 *
 * Deliberately has no "approve all" and no automated path. Verifying one of
 * these means looking the registration number up on the regulator's roll —
 * there is no adapter that can honestly do that, and approving without it is
 * how an unqualified person ends up holding a needle.
 */
export function CredentialQueue() {
  const [rows, setRows] = useState<Credential[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.credentialsPending().then(setRows).catch((err) => setError(messageFor(err)));
  }, []);

  useEffect(load, [load]);

  async function decide(row: Credential, decision: 'verified' | 'rejected') {
    const reason =
      decision === 'rejected'
        ? window.prompt(`Why is this licence being rejected? ${row.providerName} will see this.`)
        : window.prompt(
            `Confirm you have checked this registration with ${row.issuer ?? 'the issuer'}. ` +
              'Note the reference you checked:',
          );
    // Approving is gated on a note too. Rejecting a licence and approving one
    // both need to be answerable later; only approving is unrecoverable.
    if (!reason) return;

    setBusy(row.id);
    try {
      await api.reviewCredential(row.id, decision, reason);
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
          <h2>Practitioner licences</h2>
          <p className="sub">
            Required before a provider may list microblading, microneedling, laser
            or scalp micropigmentation. Rejecting one takes their gated services off
            the market immediately.
          </p>
        </div>
        {rows !== null && rows.length > 0 && (
          <span className="pill warning">{rows.length} waiting</span>
        )}
      </header>

      <div className="notice">
        <Icon name="shield" size={16} />
        <span>
          Check the registration number against the regulator before approving.
          Your decision is recorded against your account.
        </span>
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty loading">Loading…</p>}
      {rows?.length === 0 && (
        <div className="empty">
          <div className="empty-title">No licences waiting</div>
          Submitted permits and registrations appear here for checking.
        </div>
      )}

      {rows?.map((row) => {
        const expired = row.expiresOn !== null && new Date(row.expiresOn) < new Date();
        return (
          <article className="card" key={row.id}>
            <div className="row center">
              <Monogram name={row.providerName} large />
              <div className="grow">
                <div className="name">{row.providerName}</div>
                <div className="pills">
                  <span className="pill info" style={{ textTransform: 'capitalize' }}>{row.category}</span>
                  <span className="pill">{row.countryCode}</span>
                  {expired && <span className="pill danger"><span className="dot" />already expired</span>}
                </div>
              </div>
              <div className="actions">
                <button
                  className="action danger"
                  disabled={busy === row.id}
                  onClick={() => decide(row, 'rejected')}
                >
                  Reject
                </button>
                <button
                  className="action primary"
                  disabled={busy === row.id || expired}
                  onClick={() => decide(row, 'verified')}
                  title={expired ? 'This licence has already expired' : undefined}
                >
                  Approve
                </button>
              </div>
            </div>
            <div className="facts-row">
              <div className="fact">
                <div className="k">Licence</div>
                <div className="v">{KIND_LABEL[row.credentialKind] ?? row.credentialKind}</div>
              </div>
              <div className="fact">
                <div className="k">Issued by</div>
                <div className="v">{row.issuer ?? 'not stated'}</div>
              </div>
              <div className="fact">
                <div className="k">Reference ending</div>
                <div className="v mono">{row.referenceLast4 ?? '—'}</div>
              </div>
              <div className="fact">
                <div className="k">Expires</div>
                <div className="v" style={expired ? { color: 'var(--crimson-ink)' } : undefined}>
                  {row.expiresOn ?? 'not stated'}
                </div>
              </div>
              <div className="fact">
                <div className="k">Submitted</div>
                <div className="v">{new Date(row.submittedAt).toLocaleString()}</div>
              </div>
            </div>
          </article>
        );
      })}
    </>
  );
}
