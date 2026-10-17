import { useEffect, useState } from 'react';
import { api, type DisputedBooking, type ChatMessage } from '../api';
import { messageFor } from '../App';
import { formatMoney } from '../ui';

export function Disputes() {
  const [list, setList] = useState<DisputedBooking[]>([]);
  const [selected, setSelected] = useState<DisputedBooking | null>(null);
  const [chat, setChat] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = () => {
    api.disputed().then(setList).catch((err) => setError(messageFor(err)));
  };

  useEffect(() => {
    refresh();
  }, []);

  const openDetail = async (b: DisputedBooking) => {
    setSelected(b);
    setChat([]);
    try {
        const history = await api.chatHistory(b.id);
        setChat(history);
    } catch (err) {
        console.error('Could not load chat history', err);
    }
  };

  const resolve = async (decision: 'refund_client' | 'release_to_pro') => {
    if (!selected || !window.confirm(`Are you sure you want to resolve this dispute by ${decision === 'refund_client' ? 'refunding the client' : 'releasing funds to the pro'}?`)) return;
    setBusy(true);
    try {
      await api.resolveDispute(selected.id, decision);
      setSelected(null);
      refresh();
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(false);
    }
  };

  if (error) return <div className="error">{error}</div>;

  return (
    <div className="disputes">
      <header className="page-head">
        <div>
          <h2>Dispute Resolution</h2>
          <p className="sub">Bookings flagged for mediation. Review evidence and settle funds.</p>
        </div>
        {list.length > 0 && <span className="pill warning">{list.length} open</span>}
      </header>

      <div className="split">
        <div className="queue">
          {list.length === 0 ? (
            <div className="empty">
              <div className="empty-title">No active disputes</div>
              Flagged bookings land here with their chat history.
            </div>
          ) : (
            list.map((b) => (
              <button
                key={b.id}
                className={`queue-item ${selected?.id === b.id ? 'active' : ''}`}
                onClick={() => openDetail(b)}
              >
                <div className="row center">
                  <span className="pill mono dark">{b.reference}</span>
                  <span className="amount">{formatMoney(b.total)}</span>
                </div>
                <div style={{ marginTop: 10, fontWeight: 600 }}>
                  {b.clientName} <span className="meta">vs</span> {b.providerName}
                </div>
                <p className="meta" style={{ marginTop: 2 }}>
                  Flagged {new Date(b.createdAt).toLocaleDateString()}
                </p>
              </button>
            ))
          )}
        </div>

        <div className="detail">
          {selected ? (
            <div className="card detail-card flush">
              <div style={{ padding: 24 }}>
              <div className="row center">
                <div>
                  <div className="meta">Disputed booking</div>
                  <h3 style={{ fontSize: 22, fontWeight: 800 }}>{selected.reference}</h3>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="meta">Booking total</div>
                  <div className="amount" style={{ fontSize: 22 }}>{formatMoney(selected.total)}</div>
                </div>
              </div>

              <div className="parties">
                <div className="party">
                  <div className="k">Client</div>
                  <div className="v">{selected.clientName}</div>
                </div>
                <span className="versus">VS</span>
                <div className="party">
                  <div className="k">Provider</div>
                  <div className="v">{selected.providerName}</div>
                </div>
              </div>

              <h4 className="section-title" style={{ marginTop: 0, fontSize: 14 }}>Evidence: Chat History</h4>
              <div className="chat-log">
                {chat.length === 0 ? (
                  <p className="meta">No messages exchanged</p>
                ) : (
                  chat.map((m) => (
                    <div key={m.id} className="bubble" style={{ background: 'var(--surface)' }}>
                       <div className="who">{m.authorId === selected.id ? 'System' : 'Participant'}</div>
                       {m.body}
                    </div>
                  ))
                )}
              </div>
              </div>

              <div className="decision-bar">
                <p className="meta">Settling decides who receives this booking's money. Read the evidence first.</p>
                <div className="actions">
                  <button className="action danger lg" disabled={busy} onClick={() => resolve('refund_client')}>Refund Client</button>
                  <button className="action primary lg" disabled={busy} onClick={() => resolve('release_to_pro')}>Release to Pro</button>
                </div>
              </div>
            </div>
          ) : (
            <div className="empty" style={{ paddingTop: 100, paddingBottom: 100 }}>
              <div className="empty-title">Nothing selected</div>
              Select a dispute from the list to review evidence
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
