import { useCallback, useEffect, useState } from 'react';
import { api, type PayoutMethod, type PendingPayoutAccount } from '../api';
import { messageFor } from '../App';
import { Icon, Monogram, formatMoney, timeAgo } from '../ui';

const METHOD_LABEL: Record<PayoutMethod, string> = {
  bank_transfer: 'Bank transfer',
  ecocash: 'EcoCash',
  onemoney: 'OneMoney',
  innbucks: 'InnBucks',
};

/**
 * Payout destinations waiting for a human.
 *
 * A mobile-money wallet on the provider's own verified number verifies itself.
 * Everything else lands here, because the only check that matters cannot be
 * automated: is the name on this account the person on the identity document?
 * A wrong answer pays a stranger, so the number itself is never shown and a
 * refusal has to carry a reason the provider can act on.
 */
export function PayoutAccounts({ canReview }: { canReview: boolean }) {
  const [rows, setRows] = useState<PendingPayoutAccount[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  /** The card whose reject form is open, and what has been typed into it. */
  const [rejecting, setRejecting] = useState<{ id: string; reason: string } | null>(null);
  const [cardError, setCardError] = useState<{ id: string; message: string } | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.payoutAccountsPending().then(setRows).catch((err) => setError(messageFor(err)));
  }, []);

  useEffect(load, [load]);

  async function submit(row: PendingPayoutAccount, decision: 'verified' | 'rejected', reason?: string) {
    setBusy(row.id);
    setCardError(null);
    try {
      await api.reviewPayoutAccount(row.id, decision, reason);
      setRows((current) => (current ?? []).filter((r) => r.id !== row.id));
      setRejecting(null);
    } catch (err) {
      setCardError({ id: row.id, message: messageFor(err) });
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <header className="page-head">
        <div>
          <h2>Payout accounts</h2>
          <p className="sub">
            Where providers have asked to be paid. Nobody can cash out until the
            account holder matches the person we verified.
          </p>
        </div>
        {rows !== null && rows.length > 0 && (
          <span className="pill warning">{rows.length} waiting</span>
        )}
      </header>

      <div className="notice">
        <Icon name="lock" size={16} />
        <span>
          The account number stays encrypted and is never shown. Compare the account
          holder's name with the name on their identity document, and the last four
          digits with what they tell you over the phone if anything looks off.
        </span>
      </div>

      {error && <p className="error">{error}</p>}
      {rows === null && <p className="empty loading">Loading…</p>}
      {rows?.length === 0 && (
        <div className="empty">
          <div className="empty-title">Nothing waiting</div>
          Bank accounts and wallets on other numbers appear here when a provider adds
          them. Wallets on a provider's own verified number verify themselves.
        </div>
      )}

      {rows?.map((row) => {
        const verified = row.provider.kycStatus === 'verified';
        const isRejecting = rejecting?.id === row.id;
        const reason = isRejecting ? rejecting.reason.trim() : '';
        const reasonOk = reason.length >= 3;
        return (
          <article className="card review-card" key={row.id}>
            <div className="review-head">
              <Monogram name={row.provider.displayName} large />
              <div className="grow">
                <div className="name" style={{ fontSize: 18 }}>{row.provider.displayName}</div>
                <div className="pills">
                  <span className={`pill ${verified ? 'success' : 'warning'}`}>
                    <span className="dot" />
                    {verified ? 'identity verified' : `identity ${row.provider.kycStatus.replace(/_/g, ' ')}`}
                  </span>
                  <span className="pill dark">{METHOD_LABEL[row.method] ?? row.method}</span>
                  <span className="pill">{row.currency}</span>
                </div>
              </div>
              <div className="meta" style={{ textAlign: 'right' }}>
                Waiting since
                <br />
                <strong style={{ color: 'var(--ink)' }} title={new Date(row.createdAt).toLocaleString()}>
                  {timeAgo(row.createdAt)}
                </strong>
              </div>
            </div>

            <div className="payout-facts">
              <div className="fact">
                <div className="k">Account holder</div>
                <div className="v" style={{ fontSize: 17 }}>{row.accountName || 'not given'}</div>
              </div>
              <div className="fact">
                <div className="k">{row.method === 'bank_transfer' ? 'Bank' : 'Wallet'}</div>
                <div className="v">{row.institutionName}</div>
              </div>
              <div className="fact">
                <div className="k">{row.method === 'bank_transfer' ? 'Account ending' : 'Number ending'}</div>
                <div className="v mono">•••• {row.last4}</div>
              </div>
              <div className="fact">
                <div className="k">Provider's phone</div>
                <div className="v mono">
                  <a href={`tel:${row.provider.phone}`}>{row.provider.phone}</a>
                </div>
              </div>
              <div className="fact">
                <div className="k">Available to cash out</div>
                <div className="v amount">
                  {formatMoney({ minor: row.availableMinor, currency: row.currency })}
                </div>
              </div>
            </div>

            {!verified && (
              <div className="payout-warning">
                <Icon name="info" size={16} />
                <span>
                  This provider's identity is not verified yet. Verifying the account
                  does no harm on its own, but a cash-out stays refused until their
                  identity review is approved.
                </span>
              </div>
            )}

            {cardError?.id === row.id && <p className="error" style={{ margin: '0 24px 16px' }}>{cardError.message}</p>}

            {canReview ? (
              isRejecting ? (
                <form
                  className="reject-form"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (reasonOk) void submit(row, 'rejected', reason);
                  }}
                >
                  <label htmlFor={`reason-${row.id}`}>
                    Why is this account being refused? {row.provider.displayName} will see this.
                  </label>
                  <input
                    id={`reason-${row.id}`}
                    autoFocus
                    value={rejecting.reason}
                    placeholder="e.g. Account holder name does not match your ID"
                    onChange={(e) => setRejecting({ id: row.id, reason: e.target.value })}
                  />
                  <div className="reject-form-actions">
                    <p className="meta">
                      {reasonOk
                        ? 'They will be asked to add a different account.'
                        : 'A reason needs at least three characters.'}
                    </p>
                    <div className="actions">
                      <button
                        type="button"
                        className="action"
                        disabled={busy === row.id}
                        onClick={() => setRejecting(null)}
                      >
                        Keep it
                      </button>
                      <button
                        type="submit"
                        className="action danger-solid"
                        disabled={busy === row.id || !reasonOk}
                      >
                        Reject account
                      </button>
                    </div>
                  </div>
                </form>
              ) : (
                <div className="decision-bar">
                  <p className="meta">
                    Verifying lets {row.provider.displayName} cash out to this{' '}
                    {row.method === 'bank_transfer' ? 'bank account' : 'wallet'}.
                    Rejecting sends your reason back to them.
                  </p>
                  <div className="actions">
                    <button
                      className="action danger lg"
                      disabled={busy === row.id}
                      onClick={() => {
                        setCardError(null);
                        setRejecting({ id: row.id, reason: '' });
                      }}
                    >
                      Reject
                    </button>
                    <button
                      className="action primary lg"
                      disabled={busy === row.id}
                      onClick={() => submit(row, 'verified')}
                    >
                      Verify account
                    </button>
                  </div>
                </div>
              )
            ) : (
              <div className="decision-bar">
                <p className="meta">
                  Verifying a payout account requires the admin role. Support accounts
                  can see the queue but not decide it.
                </p>
              </div>
            )}
          </article>
        );
      })}
    </>
  );
}
