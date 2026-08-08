# Login & Registrierung

Status: **umgesetzt** (erster Frontend-Baustein). Basierend auf dem Figma-Mockup
"Slotora — Rajana Beauty".

## Überblick

Login und Registrierung sind **keine eigenen Seiten/Routen**, sondern ein
Bottom-Sheet-Modal, das sich über die Buchungsseite legt — genau wie im
Mockup vorgezeichnet. Das Modal hat zwei Zustände (Login / Registrieren) und
passt seinen Text an, je nachdem ob die Kundin schon eine Behandlung +
Uhrzeit ausgewählt hat ("Fast geschafft…") oder einfach nur oben rechts auf
"Login" klickt ("Willkommen zurück").

Betroffene Dateien:

```
src/context/AuthContext.jsx   Provider-Komponente + Session-Logik
src/context/authHooks.js      Context-Objekt + useAuth()-Hook
src/components/AuthSheet.jsx  Login-/Registrierungs-Formular (Bottom-Sheet)
src/components/Header.jsx     Logo + Login-Button/Profil-Avatar
src/components/MeineTermine.jsx  Liste eigener Buchungen, inkl. Stornieren
src/components/shared.css     Gemeinsame Modal-/Formular-Styles
```

## Warum kein Router für Login/Registrierung?

Im Mockup liegen beide Screens als abgedunkeltes Overlay über der
Buchungsseite, nicht als eigene URL. Eine eigene Route (`/login`) hätte hier
nur unnötige Komplexität gebracht — stattdessen steuert `App.jsx` einfach,
ob `<AuthSheet />` gemountet ist oder nicht:

```jsx
{authOpen && <AuthSheet initialMode={authMode} onClose={() => setAuthOpen(false)} />}
```

**Wichtig:** `AuthSheet` bekommt kein `open`-Prop, sondern wird komplett
aus- und eingehängt (`{authOpen && ...}`). Dadurch ist der Formularstatus
(eingetippte E-Mail, Fehlermeldung, Login/Register-Modus) bei jedem Öffnen
automatisch frisch — ohne dass wir das manuell per `useEffect` zurücksetzen
müssen. Die erste Version hatte genau das per Effekt gemacht, was ESLint
zu Recht bemängelt hat ("setState synchron im Effekt"), weil es unnötig
kompliziert war für etwas, das Mount/Unmount von Haus aus lösen.

## AuthContext: Session halten + Profil automatisch anlegen

`AuthContext.jsx` hält die aktuelle Supabase-Session und stellt sie per
React Context allen Komponenten zur Verfügung:

```jsx
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    // ensureProfile wird bewusst NICHT hier aufgerufen, sondern nur unten in
    // onAuthStateChange - siehe Bugfix-Hinweis weiter unten.
    supabase.auth.getSession().then(({ data: { session: initialSession } }) => {
      if (cancelled) return;
      setSession(initialSession);
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      if (newSession?.user) ensureProfile(newSession.user);
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, []);

  const value = {
    session,
    user: session?.user ?? null,
    loading,
    signOut: () => supabase.auth.signOut(),
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

- `getSession()` liest beim ersten Laden, ob noch eine gültige Session im
  Browser gespeichert ist (Supabase legt die im `localStorage` ab).
- `onAuthStateChange` reagiert live auf Login/Logout/Token-Refresh.
- `cancelled`-Flag verhindert, dass nach dem Unmount noch `setState`
  aufgerufen wird (React würde sonst eine Warnung werfen).

**Profil automatisch anlegen:** Beim Signup gibt es unter Umständen noch
keine Session (falls Supabase eine E-Mail-Bestätigung verlangt) — die
`profiles_insert_own`-Policy braucht aber eine eingeloggte Nutzerin. Deshalb
prüft `ensureProfile` bei *jeder* Session (egal ob nach Signup oder
normalem Login), ob schon eine `profiles`-Zeile existiert, und legt sie
sonst nach:

```jsx
const sichergestellteProfile = new Set();

async function ensureProfile(user) {
  if (sichergestellteProfile.has(user.id)) return;

  const { data: existing, error: selectError } = await supabase
    .from('profiles')
    .select('id')
    .eq('id', user.id)
    .maybeSingle();

  if (selectError) {
    console.error('Profil konnte nicht geprueft werden:', selectError.message);
    return;
  }

  if (existing) {
    sichergestellteProfile.add(user.id);
    return;
  }

  const { error: insertError } = await supabase.from('profiles').insert({
    id: user.id,
    full_name: user.user_metadata?.full_name ?? '',
    phone: user.user_metadata?.phone ?? null,
  });

  if (insertError && insertError.code !== '23505') {
    console.error('Profil konnte nicht angelegt werden:', insertError.message);
    return;
  }

  sichergestellteProfile.add(user.id);
}
```

**Bugfix (Code Review durch zweiten AI-Helfer):** Die erste Version hat weder
den Insert-Fehler ausgewertet, noch verhindert, dass `ensureProfile`
mehrfach parallel laeuft. Grund: `onAuthStateChange` feuert beim
Registrieren sofort mit der aktuellen Session (Event `INITIAL_SESSION`) —
zusaetzlich zur separaten `getSession()`-Abfrage beim Start. Bei einer
bestehenden Session liefen dadurch zwei `ensureProfile`-Aufrufe parallel,
beide lasen "Profil existiert nicht" und versuchten zu inserten; der
zweite Insert kollidierte mit dem Primary-Key-Constraint und scheiterte
still, weil der Fehler nicht ausgewertet wurde. Fix: `ensureProfile` wird
jetzt nur noch aus `onAuthStateChange` aufgerufen (nicht mehr zusaetzlich
aus `getSession()`), der Insert-Fehler wird ausgewertet (ein
`unique_violation`/`23505` ist dabei erwartet und kein echter Fehler), und
ein Set merkt sich pro Tab bereits sichergestellte Profile.

Der Name kommt aus `user.user_metadata.full_name` — der wird beim Signup
mitgeschickt (siehe unten) und ist reiner Anzeige-Text, **keine**
Berechtigungsentscheidung. Für Rollen (Kundin/Admin) verwenden wir bewusst
`app_metadata` statt `user_metadata`, siehe `docs/decisions.md`.

### Warum zwei Dateien (`AuthContext.jsx` + `authHooks.js`)?

`AuthContext.jsx` exportiert nur die `AuthProvider`-Komponente,
`authHooks.js` nur das `AuthContext`-Objekt und den `useAuth()`-Hook:

```js
// authHooks.js
export const AuthContext = createContext(undefined);

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuth muss innerhalb von <AuthProvider> verwendet werden');
  }
  return ctx;
}
```

Grund: Vites Fast-Refresh funktioniert nur zuverlässig, wenn eine `.jsx`-
Datei **ausschliesslich** Komponenten exportiert. Ein Hook + eine Komponente
im selben File hätte bei jeder Änderung einen vollen Seiten-Reload
ausgelöst statt eines schnellen Hot-Reloads.

## AuthSheet: ein Formular, zwei Modi

`AuthSheet` zeigt je nach `mode`-State entweder das Login- oder das
Registrierungsformular. Der Titel/Untertitel hängt zusätzlich vom optionalen
`bookingContext`-Prop ab (wird gesetzt, sobald es eine echte Buchungsseite
gibt):

```jsx
const title = bookingContext
  ? mode === 'login' ? 'Fast geschafft' : 'Konto erstellen'
  : mode === 'login' ? 'Willkommen zurueck' : 'Konto erstellen';
```

**Login:**

```jsx
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
```

**Registrierung** — inkl. Client-seitigem Abgleich der beiden
Passwort-Felder und Behandlung des Falls "E-Mail-Bestätigung nötig":

```jsx
const handleRegister = async (event) => {
  event.preventDefault();
  resetMeldungen();
  if (password !== passwordConfirm) {
    setError('Die Passwoerter stimmen nicht ueberein.');
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
  setInfo('Fast geschafft: Wir haben dir einen Bestaetigungslink per E-Mail geschickt.');
};
```

`options.data.full_name` landet in `user_metadata` und wird von
`ensureProfile` beim ersten Login ausgelesen. Ob `data.session` nach dem
Signup gesetzt ist, hängt von der Supabase-Einstellung "Confirm email" ab —
mit Bestätigungspflicht ist sie `null`, ohne wird die Nutzerin direkt
eingeloggt.

## Header: Login-Button wird zum Profil-Avatar

```jsx
{user ? (
  <button type="button" className="avatar-btn" onClick={onAccountClick} aria-label="Meine Termine">
    {initiale}
  </button>
) : (
  <button type="button" className="btn-login" onClick={onLoginClick}>
    Login
  </button>
)}
```

Der Avatar zeigt den ersten Buchstaben von Name oder E-Mail. Klick öffnet
`MeineTermine`.

## MeineTermine: eigene Buchungen, direkt über RLS gefiltert

```jsx
const ladeTermine = () =>
  supabase
    .from('termine')
    .select('id, start_zeit, status, dienstleistungen(name)')
    .order('start_zeit', { ascending: true });
```

Kein `.eq('kundin_id', user.id)` nötig — die RLS-Policy `termine_select_own`
aus der Datenbank sorgt bereits dafür, dass Postgres nur Zeilen der
eingeloggten Kundin zurückgibt. Stornieren nutzt genauso die
`termine_update_own`-Policy:

```jsx
const stornieren = async (id) => {
  const { error: updateError } = await supabase
    .from('termine')
    .update({ status: 'storniert' })
    .eq('id', id);
  ...
};
```

Der Datenabruf läuft bewusst über `.then()` statt über eine `async`-
Funktion, die direkt im Effekt aufgerufen wird — sonst meldet ESLint
("react-hooks/set-state-in-effect"), dass `setState` synchron im Effekt
läuft, weil eine `async`-Funktion bis zum ersten `await` synchron
ausgeführt wird.

## Design-Tokens (aus Figma übernommen)

| Token | Wert | Verwendung |
|---|---|---|
| `--color-accent` | `#c9956c` | Buttons, Logo-Badge |
| `--color-text` | `#1c1917` | Haupttext |
| `--color-text-muted` | `#6b6560` | Labels, Untertitel |
| `--color-surface` | `#fbf8f6` | Input-Hintergrund |
| `--color-border` | `#ede6e0` | Rahmen |
| `--font-heading` | Fraunces | Überschriften |
| `--font-body` | Inter | Fliesstext, Buttons |

Definiert in `src/index.css`, Schriften über Google Fonts in `index.html`
eingebunden.

## Bug gefixt: Gross-/Kleinschreibung bei Dateinamen (Windows)

Direkt nach dem ersten Test zeigte die Seite nur einen weissen Screen.
Ursache: `src/context/AuthContext.jsx` und `src/context/authContext.js`
existierten gleichzeitig — auf dem case-**insensitiven** Windows-Dateisystem
sind das aus Sicht des Betriebssystems nahezu identische Namen. Vite hat
beim Import `from './context/AuthContext'` (ohne Dateiendung) die falsche
Datei aufgelöst (`authContext.js` statt `AuthContext.jsx`), die aber gar
keinen `AuthProvider`-Export hatte → React konnte nichts rendern, ganz ohne
Fehlermeldung im Terminal.

**Fix:** die reine Hook-Datei wurde eindeutig zu `authHooks.js` umbenannt,
damit sich kein Dateiname mehr nur durch Gross-/Kleinschreibung
unterscheidet.

## Behobene Bugs (Code Review durch zweiten AI-Helfer)

- **Race Condition in `ensureProfile`**: kein Insert-Fehler ausgewertet und
  potenziell doppelter, paralleler Aufruf beim Start — siehe Abschnitt
  weiter oben.

## Offene Punkte

- `dienstleistungen` hat noch kein Preis-Feld, das Mockup zeigt aber überall
  Preise (z.B. "CHF 90") — Migration nötig, sobald die Dienstleistungsseite
  gebaut wird.
- `bookingContext`-Prop von `AuthSheet` wird aktuell noch nirgends befüllt,
  da es noch keine echte Buchungsseite gibt — folgt im nächsten Baustein.
- Login/Registrierung wurden noch nicht end-to-end mit echten
  Supabase-Zugangsdaten im Browser durchgeklickt (nur Server-Response und
  ESLint geprüft) — das sollte vor dem nächsten Schritt noch nachgeholt
  werden.
