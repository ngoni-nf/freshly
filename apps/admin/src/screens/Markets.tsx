import { useEffect, useState } from 'react';
import { api, type MarketSettings } from '../api';
import { messageFor } from '../App';

export function Markets() {
  const [list, setList] = useState<MarketSettings[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = () => {
    api.markets().then(setList).catch((err) => setError(messageFor(err)));
  };

  useEffect(() => {
    refresh();
  }, []);

  const update = async (code: string, key: string, value: any) => {
      setBusy(true);
      try {
          await api.updateMarket(code, { [key]: value });
          refresh();
      } catch (err) {
          setError(messageFor(err));
      } finally {
          setBusy(false);
      }
  };

  if (error) return <div className="error">{error}</div>;

  return (
    <div className="markets">
      <header className="page-head">
        <div>
          <h2>Market Configuration</h2>
          <p className="sub">Adjust VAT, Commission, and Service Fees per country.</p>
        </div>
      </header>

      {list.map((m) => (
        <div key={m.code} className="card market-card">
          <div className="market-head">
            <div className="market-code">{m.code}</div>
            <div className="grow">
              <h3 style={{ fontSize: 18, fontWeight: 800 }}>{m.name}</h3>
              <div className="meta">Changes save when you leave a field.</div>
            </div>
            <span className={`pill ${m.is_live ? 'success' : ''}`}>
              {m.is_live && <span className="dot" />}
              {m.is_live ? 'LIVE' : 'OFFLINE'}
            </span>
          </div>

          <div className="market-fields">
            <div className="field">
              <label>Commission (BPS)</label>
              <input
                type="number"
                disabled={busy}
                defaultValue={m.commission_bps}
                onBlur={(e) => update(m.code, 'commission_bps', parseInt(e.target.value))}
              />
              <p className="meta">{m.commission_bps / 100}% of service value</p>
            </div>

            <div className="field">
              <label>Service Fee (Minor)</label>
              <input
                type="number"
                disabled={busy}
                defaultValue={m.service_fee_minor}
                onBlur={(e) => update(m.code, 'service_fee_minor', parseInt(e.target.value))}
              />
              <p className="meta">Fixed platform fee per booking</p>
            </div>

            <div className="field">
               <label>VAT Rate (BPS)</label>
               <input
                 type="number"
                 disabled={busy}
                 defaultValue={m.vat_bps}
                 onBlur={(e) => update(m.code, 'vat_bps', parseInt(e.target.value))}
               />
               <p className="meta">{m.vat_bps / 100}% tax rate</p>
            </div>

             <div className="field">
                <label>Status</label>
                <select
                  disabled={busy}
                  value={m.is_live ? 'true' : 'false'}
                  onChange={(e) => update(m.code, 'is_live', e.target.value === 'true')}
                >
                  <option value="true">Live</option>
                  <option value="false">Offline</option>
                </select>
             </div>
          </div>
        </div>
      ))}
    </div>
  );
}
