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
  const [country, setCountry] = useState('ZA');
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
    <div className="signin">
      <div className="card">
        <h2>Freshly Ops</h2>
        <p className="sub">Identity review, licences and provider status.</p>

        {!sent ? (
          <>
            <button className="action primary" disabled={busy} onClick={google}>
              {busy ? 'Signing in…' : 'Sign in with Google'}
            </button>
            <p className="sub" style={{ textAlign: 'center', margin: '14px 0' }}>
              or with a mobile number
            </p>
            <div className="field">
              <label htmlFor="country">Country</label>
              <select id="country" value={country} onChange={(e) => setCountry(e.target.value)}>
                <option value="ZA">South Africa (+27)</option>
                <option value="ZW">Zimbabwe (+263)</option>
              </select>
            </div>
            <div className="field">
              <label htmlFor="phone">Mobile number</label>
              <input
                id="phone"
                inputMode="numeric"
                placeholder="82 123 4567"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && phone && send()}
              />
            </div>
            <button className="action primary" disabled={!phone || busy} onClick={send}>
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
              />
            </div>
            <button className="action primary" disabled={code.length !== 6 || busy} onClick={verify}>
              {busy ? 'Checking…' : 'Sign in'}
            </button>{' '}
            <button className="action" onClick={() => setSent(false)} disabled={busy}>
              Back
            </button>
          </>
        )}

        {error && <p className="error">{error}</p>}
      </div>
    </div>
  );
}
