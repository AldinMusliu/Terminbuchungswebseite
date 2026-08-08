import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabaseClient';
import { AuthContext } from './authHooks';

// Legt beim ersten Login die passende profiles-Zeile an, falls sie noch
// fehlt. Das faengt auch den Fall ab, dass Supabase eine E-Mail-
// Bestaetigung verlangt: dann existiert beim signUp() noch keine Session,
// die profiles_insert_own-Policy greift erst beim ersten echten Login.
async function ensureProfile(user) {
  const { data: existing } = await supabase
    .from('profiles')
    .select('id')
    .eq('id', user.id)
    .maybeSingle();

  if (existing) return;

  await supabase.from('profiles').insert({
    id: user.id,
    full_name: user.user_metadata?.full_name ?? '',
    phone: user.user_metadata?.phone ?? null,
  });
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    supabase.auth.getSession().then(({ data: { session: initialSession } }) => {
      if (cancelled) return;
      setSession(initialSession);
      setLoading(false);
      if (initialSession?.user) ensureProfile(initialSession.user);
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
