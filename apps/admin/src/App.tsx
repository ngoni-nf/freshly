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
import { BadgeCounts } from './api';

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
  | 'markets';

export function App() {
  const [me, setMe] = useState<Me | null>(null);
  const [checking, setChecking] = useState(true);
  const [tab, setTab] = useState<Tab>('pulse');
  const [search, setSearch] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [badges, setBadges] = useState<BadgeCounts>({ kyc: 0, credentials: 0, sos: 0, disputes: 0 });

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

  if (checking) return <main className="empty">Checking your session…</main>;
  if (!me) return <SignIn onSignedIn={setMe} />;

  // Belt and braces. The API refuses every one of these endpoints without the
  // role, but a client who cannot act should not be shown the buttons either.
  const canOperate = me.roles.includes('admin') || me.roles.includes('support');
  if (!canOperate) {
    return (
      <main className="signin">
        <div className="card">
          <div className="name">Not an operations account</div>
          <p className="meta">
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

  return (
    <div className="shell">
      <nav>
        <h1>Freshly Ops</h1>
        <p className="who">
          {me.fullName || me.phone}
          <br />
          {me.roles.join(', ')}
        </p>

        <div className="search-container">
          <input
            type="search"
            placeholder="Search (Cmd+K)"
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
                    <div className="name">{r.display_name}</div>
                    <div className="meta">{r.phone}</div>
                  </div>
                  <div className="type">{r.type}</div>
                </div>
              ))}
            </div>
          )}
        </div>

        <button aria-current={tab === 'pulse'} onClick={() => setTab('pulse')}>
          Marketplace Pulse
        </button>
        <button
          className="danger-nav"
          aria-current={tab === 'sos'}
          onClick={() => setTab('sos')}
        >
          Emergency alerts {badges.sos > 0 && <span className="tag bad">{badges.sos}</span>}
        </button>
        <button aria-current={tab === 'schedule'} onClick={() => setTab('schedule')}>
          Schedule
        </button>
        <button aria-current={tab === 'completed'} onClick={() => setTab('completed')}>
          Completed jobs
        </button>
        <button aria-current={tab === 'disputes'} onClick={() => setTab('disputes')}>
          Dispute resolution {badges.disputes > 0 && <span className="tag warn">{badges.disputes}</span>}
        </button>
        <button
          aria-current={tab === 'clientComplaints'}
          onClick={() => setTab('clientComplaints')}
        >
          Client complaints
        </button>
        <button
          aria-current={tab === 'providerComplaints'}
          onClick={() => setTab('providerComplaints')}
        >
          Provider complaints
        </button>
        <button aria-current={tab === 'providers'} onClick={() => setTab('providers')}>
          Providers
        </button>
        <button aria-current={tab === 'kyc'} onClick={() => setTab('kyc')}>
          Identity review {badges.kyc > 0 && <span className="tag warn">{badges.kyc}</span>}
        </button>
        <button aria-current={tab === 'credentials'} onClick={() => setTab('credentials')}>
          Practitioner licences {badges.credentials > 0 && <span className="tag warn">{badges.credentials}</span>}
        </button>
        {isAdmin && (
          <button aria-current={tab === 'markets'} onClick={() => setTab('markets')}>
            Market settings
          </button>
        )}
        <div className="spacer" />
        <button onClick={signOut}>Sign out</button>
      </nav>

      <main>
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
        {tab === 'markets' && <Markets />}
      </main>
    </div>
  );
}

/** Shared by every screen: turn a thrown error into something readable. */
export function messageFor(err: unknown): string {
  if (err instanceof ApiError) return err.message;
  return 'Could not reach the API. Is it running?';
}
