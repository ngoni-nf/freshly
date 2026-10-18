import { useState } from 'react';
import { api, token, type Me } from '../api';
import { messageFor } from '../App';
import { googleIdToken } from '../firebase';

/**
 * Operators sign in the same way everyone else does — phone and OTP. There is
 * no separate admin password to leak, and an operator losing their role in the
 * database loses this console at the same moment.
 */
export function SignIn({ onSignedIn }: { onSignedIn: (me: Me) => void }) {
  const [phone, setPhone] = useState('');
  // Zimbabwe launches first, so its operators are the ones signing in.
  const [country, setCountry] = useState('ZW');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send() {
    setBusy(true);
    setError(null);
    try {
      await api.requestOtp(phone, country);
      setSent(true);
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(false);
    }
  }

  async function verify() {
    setBusy(true);
    setError(null);
    try {
      const result = await api.verifyOtp(phone, country, code);
      token.set(result.accessToken);
      // Ask the server who this is rather than trusting the sign-in payload,
      // so the roles shown are the roles the API will actually enforce.
      onSignedIn(await api.me());
    } catch (err) {
      setError(messageFor(err));
    } finally {
      setBusy(false);
    }
  }

  async function google() {
    setBusy(true);
    setError(null);
    try {
      const idToken = await googleIdToken();
      const result = await api.signInWithFirebase(idToken, country);
      token.set(result.accessToken);
      onSignedIn(await api.me());
    } catch (err) {
      // A closed popup is not an error worth shouting about.
      const code = (err as { code?: string }).code;
      if (code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request') {
        return;
      }
      setError(messageFor(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="signin-shell">
      <aside className="signin-hero">
        <div className="brand">
          <div className="brand-mark">F</div>
          <span className="brand-word">Freshly</span>
          <span className="brand-tag">Ops</span>
        </div>
        <h1>
          Keep every visit <em>safe</em> and every payout honest.
        </h1>
        <p>
          The operations console for identity review, practitioner licences,
          disputes and emergency alerts across Harare and Johannesburg.
        </p>
        <div className="hero-points">
          <span>Identity review</span>
          <span>Emergency alerts</span>
          <span>Dispute mediation</span>
          <span>Provider roster</span>
        </div>
      </aside>

      <main className="signin-panel">
        <div className="signin">
          <h2>Sign in</h2>
          <p className="sub">Operations staff only. Your role is checked on every request.</p>

          {!sent ? (
            <>
              <button className="action primary lg block" disabled={busy} onClick={google}>
                {busy ? 'Signing in…' : 'Sign in with Google'}
              </button>
              <div className="divider">or with a mobile number</div>
              <div className="field">
                <label htmlFor="country">Country</label>
                <select id="country" value={country} onChange={(e) => setCountry(e.target.value)}>
                  <option value="ZW">Zimbabwe (+263)</option>
                  <option value="ZA">South Africa (+27)</option>
                </select>
              </div>
              <div className="field">
                <label htmlFor="phone">Mobile number</label>
                <input
                  id="phone"
                  inputMode="numeric"
                  placeholder={country === 'ZA' ? '82 123 4567' : '77 123 4567'}
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && phone && send()}
                />
              </div>
              <button className="action dark lg block" disabled={!phone || busy} onClick={send}>
                {busy ? 'Sending…' : 'Send code'}
              </button>
            </>
          ) : (
            <>
              <div className="field">
                <label htmlFor="code">6-digit code sent to {phone}</label>
                <input
                  id="code"
                  inputMode="numeric"
                  maxLength={6}
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && code.length === 6 && verify()}
                  autoFocus
                  style={{ fontSize: 20, letterSpacing: '0.4em', fontWeight: 700 }}
                />
              </div>
              <div className="btn-row">
                <button className="action lg" onClick={() => setSent(false)} disabled={busy}>
                  Back
                </button>
                <button className="action primary lg" disabled={code.length !== 6 || busy} onClick={verify}>
                  {busy ? 'Checking…' : 'Sign in'}
                </button>
              </div>
            </>
          )}

          {error && <p className="error" style={{ marginTop: 16 }}>{error}</p>}

          <p className="fine">
            This session ends when you close the tab. Opening an identity
            document is recorded against your account.
          </p>
        </div>
      </main>
    </div>
  );
}
