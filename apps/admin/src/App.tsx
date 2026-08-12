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

type Tab =
  | 'sos'
  | 'schedule'
  | 'completed'
  | 'clientComplaints'
  | 'providerComplaints'
  | 'providers'
  | 'kyc'
  | 'credentials';

export function App() {
  const [me, setMe] = useState<Me | null>(null);
  const [checking, setChecking] = useState(true);
  // The diary opens first: what is happening today is the question an operator
  // has before any queue.
  const [tab, setTab] = useState<Tab>('schedule');

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
        <button
          className="danger-nav"
          aria-current={tab === 'sos'}
          onClick={() => setTab('sos')}
        >
          Emergency alerts
        </button>
        <button aria-current={tab === 'schedule'} onClick={() => setTab('schedule')}>
          Schedule
        </button>
        <button aria-current={tab === 'completed'} onClick={() => setTab('completed')}>
          Completed jobs
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
          Identity review
        </button>
        <button aria-current={tab === 'credentials'} onClick={() => setTab('credentials')}>
          Practitioner licences
        </button>
        <div className="spacer" />
        <button onClick={signOut}>Sign out</button>
      </nav>

      <main>
        {tab === 'sos' && <Sos />}
        {tab === 'schedule' && <Schedule />}
        {tab === 'completed' && <Completed />}
        {tab === 'clientComplaints' && <Complaints side="clients" />}
        {tab === 'providerComplaints' && <Complaints side="providers" />}
        {tab === 'providers' && <Providers canSuspend={isAdmin} />}
        {tab === 'kyc' && <KycQueue />}
        {tab === 'credentials' && <CredentialQueue />}
      </main>
    </div>
  );
}

/** Shared by every screen: turn a thrown error into something readable. */
export function messageFor(err: unknown): string {
  if (err instanceof ApiError) return err.message;
  return 'Could not reach the API. Is it running?';
}
