import { useEffect, useState } from 'react';
import { api, type DisputedBooking, type ChatMessage } from '../api';
import { messageFor } from '../App';

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
      <header>
        <h2>Dispute Resolution</h2>
        <p className="meta">Bookings flagged for mediation. Review evidence and settle funds.</p>
      </header>

      <div className="split-view" style={{ display: 'grid', gridTemplateColumns: '350px 1fr', gap: '24px' }}>
        <div className="queue">
          {list.length === 0 ? (
            <div className="empty">No active disputes</div>
          ) : (
            list.map((b) => (
              <div key={b.id} className={`card clickable ${selected?.id === b.id ? 'active' : ''}`} onClick={() => openDetail(b)}>
                <div className="row">
                  <div className="name">{b.reference}</div>
                  <div className="amount">R {(b.total.minor / 100).toFixed(2)}</div>
                </div>
                <p className="meta">{b.clientName} vs {b.providerName}</p>
                <p className="meta" style={{ fontSize: '11px' }}>Flagged {new Date(b.createdAt).toLocaleDateString()}</p>
              </div>
            ))
          )}
        </div>

        <div className="detail">
          {selected ? (
            <div className="card">
              <h3>{selected.reference} Detail</h3>
              <div className="row" style={{ marginBottom: '24px' }}>
                <div>
                   <p className="meta">Client: <strong>{selected.clientName}</strong></p>
                   <p className="meta">Provider: <strong>{selected.providerName}</strong></p>
                </div>
                <div className="actions">
                  <button className="action danger" disabled={busy} onClick={() => resolve('refund_client')}>Refund Client</button>
                  <button className="action primary" disabled={busy} onClick={() => resolve('release_to_pro')}>Release to Pro</button>
                </div>
              </div>

              <h4>Evidence: Chat History</h4>
              <div className="chat-log" style={{ background: '#f6f8fa', padding: '16px', borderRadius: '8px', maxHeight: '400px', overflowY: 'auto' }}>
                {chat.length === 0 ? (
                  <p className="meta">No messages exchanged</p>
                ) : (
                  chat.map((m) => (
                    <div key={m.id} className="bubble">
                       <div className="who">{m.authorId === selected.id ? 'System' : 'Participant'}</div>
                       {m.body}
                    </div>
                  ))
                )}
              </div>
            </div>
          ) : (
            <div className="empty" style={{ textAlign: 'center', paddingTop: '100px' }}>
              <p className="meta">Select a dispute from the list to review evidence</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
