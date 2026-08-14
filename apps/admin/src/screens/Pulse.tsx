import { useEffect, useState } from 'react';
import { api, type PulseStats } from '../api';
import { messageFor } from '../App';

export function Pulse() {
  const [stats, setStats] = useState<PulseStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = () => {
    api.pulse().then(setStats).catch((err) => setError(messageFor(err)));
  };

  useEffect(() => {
    refresh();
    const timer = setInterval(refresh, 30000); // refresh every 30s
    return () => clearInterval(timer);
  }, []);

  if (error) return <div className="error">{error}</div>;
  if (!stats) return <div className="empty">Loading marketplace pulse…</div>;

  return (
    <div className="pulse">
      <header>
        <h2>Marketplace Pulse</h2>
        <button className="action-minor" onClick={refresh}>Refresh</button>
      </header>

      <div className="grid">
        <div className="card stat">
          <div className="label">GMV Today</div>
          <div className="value">R {(stats.gmvTodayMinor / 100).toLocaleString()}</div>
        </div>
        <div className="card stat">
          <div className="label">Bookings Today</div>
          <div className="value">{stats.bookingsToday}</div>
        </div>
        <div className="card stat">
          <div className="label">Completion Rate</div>
          <div className="value">{stats.completionRate.toFixed(1)}%</div>
        </div>
        <div className="card stat">
          <div className="label">Online Providers</div>
          <div className="value">{stats.onlineProviders}</div>
          <p className="meta">{stats.idleProviders} available now</p>
        </div>
        <div className="card stat">
          <div className="label">Demand Index</div>
          <div className="value">{stats.demandIndex.toFixed(1)}</div>
          <p className="meta">Active jobs vs online supply</p>
        </div>
      </div>

      <section>
        <h3>Market Performance</h3>
        <p className="meta">Real-time health of the South Africa and Zimbabwe regions.</p>
        {/* Placeholder for future charts/maps */}
        <div className="card empty-state" style={{ height: '200px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <p className="meta">Market distribution map coming soon</p>
        </div>
      </section>
    </div>
  );
}
