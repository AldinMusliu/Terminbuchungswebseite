import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabaseClient';
import './shared.css';
import './ServiceSelection.css';

// Reihenfolge und Beschriftung der Kategorien. Die DB kennt nur die technischen
// Werte (check-Constraint auf dienstleistungen.kategorie), die Anzeige gehoert
// ins Frontend. Kategorien ohne aktive Eintraege werden uebersprungen.
const KATEGORIEN = [
  { key: 'kosmetik', label: 'Kosmetik' },
  { key: 'laser', label: 'Laser' },
  { key: 'tattoo_entfernung', label: 'Tattoo-Entfernung' },
];

const preisFormat = new Intl.NumberFormat('de-CH', {
  style: 'currency',
  currency: 'CHF',
});

// preis_rappen ist eine Ganzzahl in Rappen (9000 = CHF 90.00),
// erst hier wird daraus ein Franken-Betrag.
// Zwei Sonderfaelle: 0 sind die kostenlosen Beratungen, preis_ab kennzeichnet
// Startpreise (Wimpernverlaengerung), deren Endpreis vom Aufwand abhaengt.
const formatPreis = (preisRappen, preisAb) => {
  if (preisRappen === 0) return 'Kostenlos';
  const betrag = preisFormat.format(preisRappen / 100);
  return preisAb ? `ab ${betrag}` : betrag;
};

const formatDauer = (minuten) => {
  const stunden = Math.floor(minuten / 60);
  const rest = minuten % 60;
  if (stunden === 0) return `${rest} Min.`;
  if (rest === 0) return `${stunden} Std.`;
  return `${stunden} Std. ${rest} Min.`;
};

export default function ServiceSelection({ selectedId, onSelect }) {
  const [dienstleistungen, setDienstleistungen] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    // Die RLS-Policy gibt anon/authenticated ohnehin nur aktiv = true frei;
    // der explizite Filter schadet nicht und gilt auch fuer die Admin-Rolle,
    // die alle Zeilen sehen darf.
    supabase
      .from('dienstleistungen')
      .select('id, name, kategorie, dauer_minuten, preis_rappen, preis_ab')
      .eq('aktiv', true)
      .order('name', { ascending: true })
      .then(({ data, error: ladeError }) => {
        if (cancelled) return;
        if (ladeError) setError(ladeError.message);
        else setDienstleistungen(data);
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const gruppen = useMemo(
    () =>
      KATEGORIEN.map(({ key, label }) => ({
        key,
        label,
        eintraege: dienstleistungen.filter((d) => d.kategorie === key),
      })).filter((gruppe) => gruppe.eintraege.length > 0),
    [dienstleistungen],
  );

  return (
    <section className="service-selection">
      <h2>Behandlung wählen</h2>

      {error && <p className="form-error">{error}</p>}
      {loading && <p className="muted">Lade Behandlungen…</p>}
      {!loading && !error && gruppen.length === 0 && (
        <p className="muted">Zurzeit sind keine Behandlungen buchbar.</p>
      )}

      {gruppen.map((gruppe) => (
        <div key={gruppe.key} className="service-gruppe">
          <h3 className="service-gruppe-titel">{gruppe.label}</h3>
          <ul className="service-liste">
            {gruppe.eintraege.map((dienstleistung) => (
              <li key={dienstleistung.id}>
                <button
                  type="button"
                  className={`service-karte${
                    dienstleistung.id === selectedId ? ' service-karte-aktiv' : ''
                  }`}
                  aria-pressed={dienstleistung.id === selectedId}
                  onClick={() => onSelect(dienstleistung)}
                >
                  <span className="service-name">{dienstleistung.name}</span>
                  <span className="service-meta">
                    <span className="service-dauer">
                      {formatDauer(dienstleistung.dauer_minuten)}
                    </span>
                    <span className="service-preis">
                      {formatPreis(dienstleistung.preis_rappen, dienstleistung.preis_ab)}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </section>
  );
}
