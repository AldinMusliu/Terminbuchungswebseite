import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabaseClient';
import { useAuth } from '../context/authHooks';
import './shared.css';
import './MeineTermine.css';

const zeitFormat = new Intl.DateTimeFormat('de-CH', {
  weekday: 'short',
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});

export default function MeineTermine({ onClose }) {
  const { signOut } = useAuth();
  const [termine, setTermine] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // RLS (termine_select_own) filtert bereits auf die eigenen Buchungen,
  // ein zusaetzlicher .eq() auf kundin_id ist hier nicht noetig.
  const ladeTermine = () =>
    supabase
      .from('termine')
      .select('id, start_zeit, status, dienstleistungen(name)')
      .order('start_zeit', { ascending: true });

  useEffect(() => {
    let cancelled = false;
    ladeTermine().then(({ data, error: ladeError }) => {
      if (cancelled) return;
      if (ladeError) setError(ladeError.message);
      else setTermine(data);
      setLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const stornieren = async (id) => {
    const { error: updateError } = await supabase
      .from('termine')
      .update({ status: 'storniert' })
      .eq('id', id);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    const { data, error: reloadError } = await ladeTermine();
    if (reloadError) setError(reloadError.message);
    else setTermine(data);
  };

  return (
    <div className="sheet-overlay" onClick={onClose}>
      <div className="sheet" onClick={(event) => event.stopPropagation()}>
        <div className="sheet-handle" />
        <h2>Meine Termine</h2>

        {error && <p className="form-error">{error}</p>}
        {loading && <p className="muted">Lade Termine…</p>}
        {!loading && termine.length === 0 && <p className="muted">Du hast noch keine Termine.</p>}

        {termine.length > 0 && (
          <ul className="termine-list">
            {termine.map((termin) => (
              <li key={termin.id} className="termine-item">
                <div>
                  <p className="termine-service">{termin.dienstleistungen?.name}</p>
                  <p className="termine-zeit">{zeitFormat.format(new Date(termin.start_zeit))}</p>
                </div>
                <div className="termine-actions">
                  <span className={`status status-${termin.status}`}>
                    {termin.status === 'bestaetigt' ? 'Bestätigt' : 'Storniert'}
                  </span>
                  {termin.status === 'bestaetigt' && (
                    <button type="button" className="btn-text" onClick={() => stornieren(termin.id)}>
                      Stornieren
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}

        <button type="button" className="btn-secondary" onClick={signOut}>
          Abmelden
        </button>
        <button type="button" className="btn-text" onClick={onClose}>
          Schliessen
        </button>
      </div>
    </div>
  );
}
