import { useState } from 'react';
import ServiceSelection from './ServiceSelection';
import './BuchungsFlow.css';

// Container fuer den mehrstufigen Buchungsflow. Haelt die Auswahl der
// einzelnen Schritte an einer Stelle, damit die Schritt-Komponenten selbst
// zustandslos bleiben.
// Schritt 1: Behandlung  (fertig)
// Schritt 2: Datum/Uhrzeit  (folgt)
// Schritt 3: Bestaetigen    (folgt)
export default function BuchungsFlow() {
  const [dienstleistung, setDienstleistung] = useState(null);

  return (
    <div className="buchung">
      <ServiceSelection
        selectedId={dienstleistung?.id ?? null}
        onSelect={setDienstleistung}
      />

      {dienstleistung && (
        <div className="buchung-leiste">
          <div className="buchung-auswahl">
            <p className="buchung-auswahl-label">Gewählt</p>
            <p className="buchung-auswahl-name">{dienstleistung.name}</p>
          </div>
          <button type="button" className="btn-primary buchung-weiter" disabled>
            Weiter
          </button>
        </div>
      )}
    </div>
  );
}
