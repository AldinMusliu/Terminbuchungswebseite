import { useState } from 'react';
import { supabase } from '../lib/supabaseClient';
import './shared.css';
import './AuthSheet.css';

// Wird von der Elternkomponente per Mount/Unmount ein-/ausgeblendet
// (kein "open"-Prop), damit der Formularstatus bei jedem Oeffnen frisch ist.
//
// bookingContext (optional): { serviceName, whenText } fuer den Fall,
// dass die Kundin schon eine Behandlung + Uhrzeit ausgewaehlt hat,
// bevor sie sich einloggt (siehe Mockup "Fast geschafft").
export default function AuthSheet({ initialMode = 'login', bookingContext, onClose }) {
  const [mode, setMode] = useState(initialMode);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [info, setInfo] = useState(null);

  const resetMeldungen = () => {
    setError(null);
    setInfo(null);
  };

  const handleLogin = async (event) => {
    event.preventDefault();
    resetMeldungen();
    setLoading(true);
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);
    if (signInError) {
      setError(signInError.message);
      return;
    }
    onClose();
  };

  const handleRegister = async (event) => {
    event.preventDefault();
    resetMeldungen();
    if (password !== passwordConfirm) {
      setError('Die Passwörter stimmen nicht überein.');
      return;
    }
    setLoading(true);
    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: name } },
    });
    setLoading(false);
    if (signUpError) {
      setError(signUpError.message);
      return;
    }
    if (data.session) {
      onClose();
      return;
    }
    setInfo('Fast geschafft: Wir haben dir einen Bestätigungslink per E-Mail geschickt.');
  };

  const title = bookingContext
    ? mode === 'login'
      ? 'Fast geschafft'
      : 'Konto erstellen'
    : mode === 'login'
      ? 'Willkommen zurück'
      : 'Konto erstellen';

  const subtitle = bookingContext
    ? mode === 'login'
      ? `${bookingContext.serviceName} am ${bookingContext.whenText}. Melde dich an, um deinen Termin zu bestätigen.`
      : 'Erstelle ein Konto, um deine Termine ganz einfach zu verwalten.'
    : mode === 'login'
      ? 'Melde dich an, um deine Termine zu verwalten.'
      : 'Erstelle ein Konto, um deine Termine ganz einfach zu verwalten.';

  return (
    <div className="sheet-overlay" onClick={onClose}>
      <div className="sheet" onClick={(event) => event.stopPropagation()}>
        <div className="sheet-handle" />
        <div className="sheet-logo">R</div>
        <h2>{title}</h2>
        <p className="muted">{subtitle}</p>

        {error && <p className="form-error">{error}</p>}
        {info && <p className="form-info">{info}</p>}

        {mode === 'login' ? (
          <form className="auth-form" onSubmit={handleLogin}>
            <div className="field">
              <label htmlFor="login-email">E-Mail</label>
              <input
                id="login-email"
                type="email"
                required
                placeholder="name@beispiel.ch"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="login-password">Passwort</label>
              <input
                id="login-password"
                type="password"
                required
                placeholder="••••••••"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </div>
            <button type="submit" className="btn-primary" disabled={loading}>
              {loading ? 'Einen Moment…' : bookingContext ? 'Anmelden & buchen' : 'Anmelden'}
            </button>
            <button
              type="button"
              className="btn-text"
              onClick={() => {
                resetMeldungen();
                setMode('register');
              }}
            >
              Noch kein Konto? Jetzt registrieren
            </button>
          </form>
        ) : (
          <form className="auth-form" onSubmit={handleRegister}>
            <div className="field">
              <label htmlFor="register-name">Name</label>
              <input
                id="register-name"
                type="text"
                required
                placeholder="Vorname Nachname"
                value={name}
                onChange={(event) => setName(event.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="register-email">E-Mail</label>
              <input
                id="register-email"
                type="email"
                required
                placeholder="name@beispiel.ch"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="register-password">Passwort</label>
              <input
                id="register-password"
                type="password"
                required
                minLength={8}
                aria-describedby="register-password-hint"
                placeholder="••••••••"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
              <p id="register-password-hint" className="field-hint">
                Mindestens 8 Zeichen.
              </p>
            </div>
            <div className="field">
              <label htmlFor="register-password-confirm">Passwort bestätigen</label>
              <input
                id="register-password-confirm"
                type="password"
                required
                minLength={8}
                placeholder="••••••••"
                value={passwordConfirm}
                onChange={(event) => setPasswordConfirm(event.target.value)}
              />
            </div>
            <button type="submit" className="btn-primary" disabled={loading}>
              {loading ? 'Einen Moment…' : 'Konto erstellen'}
            </button>
            <button
              type="button"
              className="btn-text"
              onClick={() => {
                resetMeldungen();
                setMode('login');
              }}
            >
              Bereits registriert? Anmelden
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
