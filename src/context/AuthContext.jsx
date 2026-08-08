import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabaseClient';
import { AuthContext } from './authHooks';

// Merkt sich pro Browser-Tab, fuer welche User-IDs das Profil schon
// sichergestellt wurde - erspart unnoetige Abfragen bei jedem Token-Refresh.
const sichergestellteProfile = new Set();

// Legt beim ersten Login die passende profiles-Zeile an, falls sie noch
// fehlt. Das faengt auch den Fall ab, dass Supabase eine E-Mail-
// Bestaetigung verlangt: dann existiert beim signUp() noch keine Session,
// die profiles_insert_own-Policy greift erst beim ersten echten Login.
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

  // 23505 = unique_violation: onAuthStateChange feuert beim Start sofort
  // mit der aktuellen Session (zusaetzlich zu getSession()), dadurch kann
  // ensureProfile parallel laufen - der zweite Insert kollidiert dann
  // harmlos mit dem ersten.
  if (insertError && insertError.code !== '23505') {
    console.error('Profil konnte nicht angelegt werden:', insertError.message);
    return;
  }

  sichergestellteProfile.add(user.id);
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    // Nur fuer den initialen Ladezustand - ensureProfile laeuft bewusst
    // ausschliesslich ueber onAuthStateChange (siehe unten), das beim
    // Registrieren sofort mit der aktuellen Session feuert (Event
    // INITIAL_SESSION). Zwei Aufrufstellen wuerden sich sonst ueberholen.
    supabase.auth.getSession().then(({ data: { session: initialSession } }) => {
      if (cancelled) return;
      setSession(initialSession);
      setLoading(false);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, newSession) => {
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
