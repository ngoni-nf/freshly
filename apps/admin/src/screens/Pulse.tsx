import { useEffect, useState } from 'react';
import { api, type PulseStats } from '../api';
import { messageFor } from '../App';
import { Icon, formatMoney } from '../ui';

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
  if (!stats) return <div className="empty loading">Loading marketplace pulse…</div>;

  // Of everyone online, how many are free to take the next job.
  const idleShare =
    stats.onlineProviders > 0 ? (stats.idleProviders / stats.onlineProviders) * 100 : 0;

  return (
    <div className="pulse">
      <header className="page-head">
        <div>
          <h2>Marketplace Pulse</h2>
          <p className="sub">Today across every live market. Refreshes every thirty seconds.</p>
        </div>
        <div className="page-actions">
          <button className="action-minor" onClick={refresh}>
            <Icon name="refresh" size={16} />
            Refresh
          </button>
        </div>
      </header>

      <div className="stat-grid">
        <div className="card stat hero">
          <div className="stat-top">
            <div className="label">GMV Today</div>
            <span className="stat-icon"><Icon name="cash" size={16} /></span>
          </div>
          {stats.gmvToday.length === 0 ? (
            <div className="value none">No completed bookings yet today</div>
          ) : (
            <div className={`gmv ${stats.gmvToday.length > 1 ? 'many' : ''}`}>
              {stats.gmvToday.map((g) => (
                <div className="value" key={g.currency}>
                  {formatMoney(g)}
                </div>
              ))}
            </div>
          )}
          <p className="meta">
            {stats.gmvToday.length > 1
              ? 'Gross value of today\'s bookings, per currency'
              : 'Gross value of today\'s bookings'}
          </p>
        </div>
        <div className="card stat">
          <div className="stat-top">
            <div className="label">Bookings Today</div>
            <span className="stat-icon"><Icon name="calendar" size={16} /></span>
          </div>
          <div className="value">{stats.bookingsToday}</div>
          <p className="meta">Instant and scheduled</p>
        </div>
        <div className="card stat">
          <div className="stat-top">
            <div className="label">Completion Rate</div>
            <span className="stat-icon"><Icon name="check" size={16} /></span>
          </div>
          <div className="value">{stats.completionRate.toFixed(1)}%</div>
          <div className="meter">
            <span style={{ width: `${Math.min(100, Math.max(0, stats.completionRate))}%` }} />
          </div>
        </div>
        <div className="card stat">
          <div className="stat-top">
            <div className="label">Online Providers</div>
            <span className="stat-icon"><Icon name="users" size={16} /></span>
          </div>
          <div className="value">{stats.onlineProviders}</div>
          <div className="meter">
            <span style={{ width: `${idleShare}%` }} />
          </div>
          <p className="meta">{stats.idleProviders} available now</p>
        </div>
        <div className="card stat">
          <div className="stat-top">
            <div className="label">Demand Index</div>
            <span className="stat-icon"><Icon name="bolt" size={16} /></span>
          </div>
          <div className="value">{stats.demandIndex.toFixed(1)}</div>
          <p className="meta">Active jobs vs online supply</p>
        </div>
      </div>

      <section>
        <h3 className="section-title">Market Performance</h3>
        <p className="sub" style={{ marginBottom: 16 }}>
          Real-time health of the South Africa and Zimbabwe regions.
        </p>
        {/* Placeholder for future charts/maps */}
        <div className="card placeholder-panel">
          <span className="stat-icon"><Icon name="globe" size={20} /></span>
          <div className="empty-title">Market distribution map coming soon</div>
          <p className="meta">Live jobs and online supply by suburb will appear here.</p>
        </div>
      </section>
    </div>
  );
}
