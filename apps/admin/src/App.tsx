import { useCallback, useEffect, useState } from 'react';
import { ApiError, api, token, type Me } from './api';
import { SignIn } from './screens/SignIn';
import { KycQueue } from './screens/KycQueue';
import { CredentialQueue } from './screens/CredentialQueue';
import { Providers } from './screens/Providers';
import { Schedule } from './screens/Schedule';
import { Completed } from './screens/Completed';
import { Complaints } from './screens/Complaints';
import { Sos } from './screens/Sos';
import { Pulse } from './screens/Pulse';
import { Disputes } from './screens/Disputes';
import { Markets } from './screens/Markets';
import { PayoutAccounts } from './screens/PayoutAccounts';
import { BadgeCounts } from './api';
import { Icon, Monogram, type IconName } from './ui';

type Tab =
  | 'pulse'
  | 'sos'
  | 'schedule'
  | 'completed'
  | 'disputes'
  | 'clientComplaints'
  | 'providerComplaints'
  | 'providers'
  | 'kyc'
  | 'credentials'
  | 'payoutAccounts'
  | 'markets';

const TAB_META: Record<Tab, { label: string; group: string }> = {
  pulse: { label: 'Marketplace Pulse', group: 'Live' },
  sos: { label: 'Emergency alerts', group: 'Live' },
  schedule: { label: 'Schedule', group: 'Live' },
  completed: { label: 'Completed jobs', group: 'Live' },
  disputes: { label: 'Dispute resolution', group: 'Support' },
  clientComplaints: { label: 'Client complaints', group: 'Support' },
  providerComplaints: { label: 'Provider complaints', group: 'Support' },
  providers: { label: 'Providers', group: 'Trust' },
  kyc: { label: 'Identity review', group: 'Trust' },
  credentials: { label: 'Practitioner licences', group: 'Trust' },
  payoutAccounts: { label: 'Payout accounts', group: 'Trust' },
  markets: { label: 'Market settings', group: 'Admin' },
};

export function App() {
  const [me, setMe] = useState<Me | null>(null);
  const [checking, setChecking] = useState(true);
  const [tab, setTab] = useState<Tab>('pulse');
  const [search, setSearch] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [badges, setBadges] = useState<BadgeCounts>({
    kyc: 0,
    credentials: 0,
    sos: 0,
    payoutAccounts: 0,
    disputes: 0,
  });

  // Restore a session on reload. A stored token proves nothing about the
  // account's current state, so the server is asked rather than trusted.
  useEffect(() => {
    if (!token.get()) {
      setChecking(false);
      return;
    }
    api
      .me()
      .then(setMe)
      .catch(() => token.clear())
      .finally(() => setChecking(false));
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      if (search.length >= 2) {
        api.globalSearch(search).then(setSearchResults);
      } else {
        setSearchResults([]);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  useEffect(() => {
    const refreshBadges = () => api.badges().then(setBadges).catch(() => {});
    refreshBadges();
    const timer = setInterval(refreshBadges, 10000); // 10s
    return () => clearInterval(timer);
  }, []);

  const signOut = useCallback(() => {
    token.clear();
    setMe(null);
  }, []);

  if (checking) {
    return (
      <div className="centered">
        <p className="meta">Checking your session…</p>
      </div>
    );
  }
  if (!me) return <SignIn onSignedIn={setMe} />;

  // Belt and braces. The API refuses every one of these endpoints without the
  // role, but a client who cannot act should not be shown the buttons either.
  const canOperate = me.roles.includes('admin') || me.roles.includes('support');
  if (!canOperate) {
    return (
      <main className="centered">
        <div className="card">
          <div className="name">Not an operations account</div>
          <p className="meta" style={{ margin: '8px 0 20px' }}>
            {me.phone} is signed in but has no admin or support role, so there is
            nothing here for it.
          </p>
          <button className="action" onClick={signOut}>
            Sign out
          </button>
        </div>
      </main>
    );
  }

  const isAdmin = me.roles.includes('admin');

  const navItem = (
    key: Tab,
    icon: IconName,
    count = 0,
    tone: 'warn' | 'danger' = 'warn',
    extraClass = '',
  ) => (
    <button
      key={key}
      className={`nav-item ${extraClass}`}
      aria-current={tab === key}
      onClick={() => setTab(key)}
    >
      <Icon name={icon} />
      <span className="label">{TAB_META[key].label}</span>
      {count > 0 && <span className={`nav-count ${tone}`}>{count}</span>}
    </button>
  );

  return (
    <div className="shell">
      <nav className="sidebar">
        <div className="brand">
          <div className="brand-mark">F</div>
          <span className="brand-word">Freshly</span>
          <span className="brand-tag">Ops</span>
        </div>

        <div className="search-container">
          <span className="search-icon">
            <Icon name="search" size={16} />
          </span>
          <input
            type="search"
            placeholder="Search people, bookings"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {searchResults.length > 0 && (
            <div className="search-results">
              {searchResults.map((r) => (
                <div key={r.id} className="search-item" onClick={() => {
                    setSearch('');
                    // Navigate to appropriate tab/filter based on type
                    if (r.type === 'provider') setTab('providers');
                    if (r.type === 'booking') setTab('schedule');
                }}>
                  <div>
                    <div className="name" style={{ fontSize: 14 }}>{r.display_name}</div>
                    <div className="meta">{r.phone}</div>
                  </div>
                  <span className="pill">{r.type}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="nav-group">Live</div>
        {navItem('pulse', 'pulse')}
        {navItem('sos', 'siren', badges.sos, 'danger', 'sos-nav')}
        {navItem('schedule', 'calendar')}
        {navItem('completed', 'check')}

        <div className="nav-group">Support</div>
        {navItem('disputes', 'scale', badges.disputes)}
        {navItem('clientComplaints', 'message')}
        {navItem('providerComplaints', 'briefcase')}

        <div className="nav-group">Trust</div>
        {navItem('providers', 'users')}
        {navItem('kyc', 'idcard', badges.kyc)}
        {navItem('credentials', 'award', badges.credentials)}
        {navItem('payoutAccounts', 'wallet', badges.payoutAccounts)}

        {isAdmin && (
          <>
            <div className="nav-group">Admin</div>
            {navItem('markets', 'sliders')}
          </>
        )}

        <div className="spacer" />
        <div className="who-card">
          <Monogram name={me.fullName || me.phone} />
          <div className="who-text">
            <div className="who-name">{me.fullName || me.phone}</div>
            <div className="who-roles">{me.roles.join(', ')}</div>
          </div>
          <button className="icon-btn" onClick={signOut} title="Sign out" aria-label="Sign out">
            <Icon name="logout" />
          </button>
        </div>
      </nav>

      <div className="workspace">
        <header className="topbar">
          <div className="crumbs">
            <span>{TAB_META[tab].group}</span>
            <span className="sep">/</span>
            <strong>{TAB_META[tab].label}</strong>
          </div>
          <span className="live-dot" aria-hidden="true" />
          <span className="today">
            {new Date().toLocaleDateString(undefined, {
              weekday: 'short',
              day: 'numeric',
              month: 'short',
            })}
          </span>
        </header>

        <main className="page">
          {badges.sos > 0 && tab !== 'sos' && (
            <div className="sos-banner" role="alert">
              <span className="sos-beacon" aria-hidden="true" />
              <span className="sos-text">
                <strong>
                  {badges.sos} open emergency alert{badges.sos === 1 ? '' : 's'}.
                </strong>{' '}
                Someone has pressed SOS and is waiting for a response.
              </span>
              <button onClick={() => setTab('sos')}>Open alerts</button>
            </div>
          )}

          {tab === 'pulse' && <Pulse />}
          {tab === 'sos' && <Sos />}
          {tab === 'schedule' && <Schedule />}
          {tab === 'completed' && <Completed />}
          {tab === 'disputes' && <Disputes />}
          {tab === 'clientComplaints' && <Complaints side="clients" />}
          {tab === 'providerComplaints' && <Complaints side="providers" />}
          {tab === 'providers' && <Providers canSuspend={isAdmin} />}
          {tab === 'kyc' && <KycQueue />}
          {tab === 'credentials' && <CredentialQueue />}
          {tab === 'payoutAccounts' && <PayoutAccounts canReview={isAdmin} />}
          {tab === 'markets' && <Markets />}
        </main>
      </div>
    </div>
  );
}

/** Shared by every screen: turn a thrown error into something readable. */
export function messageFor(err: unknown): string {
  if (err instanceof ApiError) return err.message;
  return 'Could not reach the API. Is it running?';
}
