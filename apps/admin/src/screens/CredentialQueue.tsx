import { useCallback, useEffect, useState } from 'react';
import { api, type Credential } from '../api';
import { messageFor } from '../App';

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
      <h2>Practitioner licences</h2>
      <p className="sub">
        Required before a provider may list microblading, microneedling, laser
        or scalp micropigmentation. Rejecting one takes their gated services off
        the market immediately.
      </p>

      <div className="notice">
        Check the registration number against the regulator before approving.
        Your decision is recorded against your account.
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty">Loading…</p>}
      {rows?.length === 0 && <p className="empty">No licences waiting.</p>}

      {rows?.map((row) => {
        const expired = row.expiresOn !== null && new Date(row.expiresOn) < new Date();
        return (
          <div className="card" key={row.id}>
            <div className="row">
              <div>
                <div className="name">{row.providerName}</div>
                <div className="meta">
                  <span className="tag">{row.category}</span>
                  <span className="tag">{row.countryCode}</span>
                  {expired && <span className="tag bad">already expired</span>}
                  <br />
                  {KIND_LABEL[row.credentialKind] ?? row.credentialKind}
                  {row.issuer && ` · issued by ${row.issuer}`}
                  <br />
                  Reference ending {row.referenceLast4 ?? '—'} · expires{' '}
                  {row.expiresOn ?? 'not stated'} · submitted{' '}
                  {new Date(row.submittedAt).toLocaleString()}
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
          </div>
        );
      })}
    </>
  );
}
