# Buchungsseite (Kundenseite)

Fortschritts- und Entscheidungsprotokoll zum Buchungsflow. Ein Abschnitt pro
abgeschlossener Teilaufgabe: was gebaut wurde, warum so, was noch offen ist.

Grundlage: `checkliste-buchungsflow.md` (Rajana-Beauty-Ablage).
Schema: `docs/schema.md` · Architektur-Entscheidungen: `docs/decisions.md`

---

## 1 — Preis-Feld für Dienstleistungen

**Status:** Beide Migrationen in Supabase ausgeführt, Preise eingetragen.

### Was

| Datei | Zweck |
|---|---|
| `supabase/migrations/20260814100000_dienstleistungen_preis.sql` | legt Spalte `preis_rappen` auf `dienstleistungen` an (vorerst NULL erlaubt) |
| `supabase/migrations/20260814100100_dienstleistungen_preis_pflicht.sql` | setzt `preis_rappen` auf `not null` |
| `docs/schema.md` | Feld im Schema ergänzt, "kein Preis-Feld"-Punkt unter *Offen* gestrichen |

### Warum

**Preis als Rappen-Ganzzahl (`preis_rappen integer`), nicht als Kommazahl.**
`9000` bedeutet CHF 90.00. Ganzzahlen können keine Rundungsfehler bekommen —
bei Kommazahlen driften Beträge über Berechnungen hinweg ab. Formatiert wird
erst in der UI (`preis_rappen / 100`). Das ist auch der Standard bei
Zahlungsanbietern wie Stripe.

**Preis ist Pflichtfeld.** Jede Behandlung braucht einen Preis, damit die UI
keinen Sonderfall "Preis auf Anfrage" behandeln muss.

**Warum zwei Migrationen statt einer.** `not null` lässt sich nicht setzen,
solange Zeilen ohne Preis in der Tabelle stehen — Postgres bricht ab. Also:
erst Spalte anlegen (NULL erlaubt), Preise im Supabase Table Editor eintragen,
dann die zweite Migration nachziehen. Genau die Reihenfolge, die Schritt 1 und 2
der Checkliste vorgeben.

**Kein RLS-Handlungsbedarf.** `preis_rappen` ist eine neue Spalte auf einer
bestehenden Tabelle, keine neue Tabelle. Die vorhandenen Policies auf
`dienstleistungen` gelten unverändert weiter: öffentlich lesbar nur für
`aktiv = true`, schreiben nur Admin. Preise sind keine personenbezogenen Daten,
sie sollen öffentlich sichtbar sein.

### Offen

- Beide Migrationen sind **noch nicht ausgeführt**. Reihenfolge einhalten:
  Migration 1 → Preise im Table Editor eintragen → Migration 2.
- Preise müssen für **alle** Zeilen gesetzt werden, auch für `aktiv = false`
  (`not null` gilt tabellenweit, nicht nur für aktive Einträge).
- Die UI-Formatierung (`preis_rappen` → `"CHF 90.00"`) entsteht erst mit der
  `ServiceSelection`-Komponente in Teilaufgabe 3.

---

## 2 — Verfügbarkeits-Logik (`freie_slots`)

**Status:** In Supabase ausgeführt, alle 12 Testfälle bestanden (14.08.2026).

### Was

| Datei | Zweck |
|---|---|
| `supabase/migrations/20260814110000_freie_slots.sql` | Postgres-Funktion `freie_slots(datum, dienstleistung_id)` → freie Startzeiten |
| `supabase/tests/freie_slots_test.sql` | 12 Testfälle, laufen in einer Transaktion mit ROLLBACK, Ausgabe als **eine** PASS/FAIL-Tabelle |
| `docs/decisions.md` | zwei neue Entscheidungen: RPC statt Frontend, 15-Min-Raster |
| `docs/schema.md` | Funktion dokumentiert, Lücke "berechnet ≠ erzwungen" unter *Offen* präzisiert |

Die Funktion filtert der Reihe nach: Öffnungszeiten des Wochentags → 15-Minuten-Raster →
volle `dauer_minuten` muss vor Ladenschluss reinpassen → keine Überlappung mit bestätigten
`termine` → keine Überlappung mit `sperrzeiten` → nichts in der Vergangenheit.

### Warum

**Berechnung in der Datenbank, nicht im Frontend.** Das war keine Stilfrage, sondern
erzwungen: `termine_select_own` lässt eine Kundin nur ihre *eigenen* Termine sehen. Das
Frontend kann freie Slots damit gar nicht korrekt berechnen — es sei denn, man macht
`termine` für alle lesbar und gibt damit preis, wer wann einen Termin hat. Die Funktion
läuft als `security definer`, sieht dadurch alle Termine, gibt aber ausschliesslich
Zeitstempel zurück. Dazu `set search_path = ''`, das ist bei `security definer` Pflicht.

**15-Minuten-Raster.** Nur für Startzeiten — das Ende richtet sich nach `dauer_minuten` und
darf krumm fallen. Da `dauer_minuten` frei wählbar ist, würde ein 30-Minuten-Raster
regelmässig unbuchbare Lücken zwischen verschieden langen Behandlungen hinterlassen.

**Zeitzone.** `oeffnungszeiten` speichert reine Uhrzeiten. Die Funktion setzt sie per
`at time zone 'Europe/Zurich'` aufs Datum. Sommer-/Winterzeit läuft dadurch automatisch mit,
nirgends steckt ein fester Offset. Zwei Testfälle prüfen genau das (September = UTC+2,
Dezember = UTC+1) — das ist der Fehler, der laut Checkliste am leichtesten übersehen wird.

**Anschlusstermine bleiben erlaubt.** Zeitbereiche sind `[start, ende)`, ein Termin bis 13:00
blockiert den Slot 13:00 nicht. Dieselbe Logik nutzt der Doppelbuchungs-Constraint, damit
können Anzeige und Constraint nicht auseinanderlaufen.

### Testlauf 14.08.2026 — alle 12 bestanden

Bestätigt unter anderem: 43 Slots am leeren Tag, Ränder exakt 09:00/19:30, Sommer- und
Winterzeit korrekt (07:00 bzw. 08:00 UTC), 29 Slots nach Termin und Sperrzeit.

Aufschlussreich war die Slot-Liste: die Lücken sind **11:15–12:45** und **14:15–15:45**, nicht
etwa nur 12:00–13:00 und 15:00–16:00. Eine 60-Minuten-Behandlung ab 11:15 würde in den Termin
um 12:00 hineinlaufen, fällt also ebenfalls weg. Die Lücke ist immer
*Hindernisdauer + Behandlungsdauer − 15 Min* breit. Für die UI heisst das: bei langen
Behandlungen wirken einzelne Sperrzeiten deutlich grösser, als sie im Kalender aussehen — das
ist korrekt, wird aber Rückfragen provozieren.

### Offen

- **Die Funktion berechnet, erzwingt aber nichts.** Ein direkter INSERT in `termine` kann
  weiterhin ausserhalb der Öffnungszeiten oder über einer Sperrzeit landen — RLS prüft nur
  `kundin_id`, der Exclusion-Constraint nur Überlappung mit anderen Terminen. Dafür fehlt ein
  Trigger auf `termine`. **Empfehlung: als eigene kleine Aufgabe vor der UI erledigen**,
  sonst ist die Slot-Auswahl nur Bequemlichkeit statt Absicherung.
- Kein Puffer zwischen Terminen (Aufräumen, Umbauen). Falls gewünscht, gehört das als
  Feld an `dienstleistungen` oder als globale Einstellung — bisher nirgends vorgesehen.
- Keine Mindest-Vorlaufzeit. Aktuell wäre ein Termin in 5 Minuten buchbar, solange er in der
  Zukunft liegt.
- Der JS-Aufruf (`supabase.rpc('freie_slots', …)`) entsteht mit der Datums-/Zeitauswahl in
  Teilaufgabe 4.

---

## 3 — UI: Dienstleistungsauswahl

**Status:** Gebaut, `npm run lint` und `npm run build` laufen sauber. Im Browser noch
nicht durchgeklickt.

### Was

| Datei | Zweck |
|---|---|
| `src/components/ServiceSelection.jsx` | lädt aktive Dienstleistungen, gruppiert nach Kategorie, Karten mit Name/Dauer/Preis |
| `src/components/ServiceSelection.css` | Kartenraster, einspaltig mobil, ab 640px zweispaltig |
| `src/components/BuchungsFlow.jsx` | Container für den mehrstufigen Flow, hält die Auswahl |
| `src/components/BuchungsFlow.css` | fixierte Auswahl-Leiste am unteren Rand |
| `src/App.jsx`, `src/App.css` | Platzhalter im `<main>` durch den Flow ersetzt |

### Warum

**Auswahl-State liegt im `BuchungsFlow`, nicht in `ServiceSelection`.** Ab Teilaufgabe 4
kommen Datum und Uhrzeit dazu, ab 5 der Bestätigungsschritt — die brauchen alle dieselbe
Dienstleistung (für `freie_slots` die `id`, für die Zusammenfassung Name und Preis).
`ServiceSelection` bekommt darum nur `selectedId` und `onSelect` und bleibt zustandslos.
`onSelect` gibt das **ganze** Objekt zurück, nicht bloss die `id`, damit die späteren
Schritte Dauer und Preis nicht erneut aus der DB holen müssen.

**Kategorie-Beschriftungen stehen im Frontend.** Die DB kennt nur die technischen Werte
aus dem check-Constraint (`kosmetik`, `laser`, `tattoo_entfernung`). Die Konstante
`KATEGORIEN` legt gleichzeitig die Anzeigereihenfolge fest — eine Sortierung nach
`kategorie` in SQL wäre alphabetisch und damit willkürlich. Kategorien ohne aktive
Einträge fallen automatisch raus.

**`.eq('aktiv', true)` trotz RLS.** Die Policy gibt `anon`/`authenticated` ohnehin nur
aktive Zeilen frei. Der Filter kostet nichts und greift zusätzlich für die Admin-Rolle,
die alle Zeilen sehen darf — sonst tauchten deaktivierte Behandlungen in der Kundinnen-
Ansicht auf, sobald die Admin eingeloggt ist.

**Preis-Formatierung erst hier.** `preis_rappen / 100` durch
`Intl.NumberFormat('de-CH', { currency: 'CHF' })` → `CHF 90.00`. Das ist die in
Teilaufgabe 1 angekündigte UI-Seite der Rappen-Ganzzahl.

**Karten sind `<button>`, keine `<div>`.** Damit funktionieren Tastatur und Screenreader
ohne Zusatzarbeit; `aria-pressed` macht die Auswahl ansagbar. Der aktive Zustand ist
nicht nur farbig, sondern auch am dickeren Rand erkennbar.

### Testhinweise

`npm run dev`, dann:

- Karten erscheinen nach Kategorie gruppiert, Preise als `CHF 90.00`, Dauer als
  `45 Min.` bzw. `1 Std. 30 Min.`
- Karte antippen → Rand wird akzentfarben, Leiste unten zeigt den Namen
- Andere Karte antippen → Auswahl wechselt, es bleibt genau eine aktiv
- Mit Tab durchsteppen, mit Enter/Leertaste auswählen
- Schmales Fenster (Handy-Breite): eine Spalte, Leiste verdeckt die letzte Karte nicht
- Eine Behandlung in Supabase auf `aktiv = false` setzen, neu laden → verschwindet;
  letzter Eintrag einer Kategorie → ganze Gruppe verschwindet

### Nachtrag — echter Katalog importiert

Nach dem Bau der Komponente kam der echte Behandlungskatalog als CSV (42 Einträge).
Vier Punkte passten nicht ins bestehende Schema:

| Datei | Zweck |
|---|---|
| `supabase/migrations/20260815100000_dienstleistungen_preis_ab.sql` | Feld `preis_ab` für Startpreise |
| `supabase/migrations/20260815100100_dienstleistungen_katalog.sql` | 42 Behandlungen, ersetzt die Testeinträge |
| `docs/dienstleistungen-dauern.md` | Dauer-Vorschläge zum Gegenlesen + offene Rückfragen |

**Dauer fehlte bei 40 von 42 Zeilen.** `dauer_minuten` ist Pflichtfeld und die
Grundlage von `freie_slots` — ohne Dauer kein Termin. Die Werte in der Migration sind
branchenübliche Schätzwerte, **nicht vom Betrieb bestätigt**. Bis das gegengelesen ist,
stimmt die Slot-Berechnung rechnerisch, aber nicht zwingend mit der Realität überein.

**`preis_ab` statt Fixpreis für die Lashes.** Vier Einträge sind im CSV als „ab-Preis"
markiert. Ein Fixpreis auf der Karte wäre gegenüber Kundinnen schlicht falsch. Die drei
Beratungen sind mit `preis_rappen = 0` erfasst und werden als „Kostenlos" angezeigt —
`preis_ab` bleibt dort `false`, „ab CHF 0.00" wäre sinnlos.

**Namen mit echten Umlauten.** Das CSV war ASCII („Groesse", „Ruecken"), die Namen
stehen aber auf der Kundinnen-Seite. Schweizer Schreibweise, `ss` statt `ß`.

**Katalog als Daten-Migration, nicht per Table Editor.** Damit ist der Katalog
versioniert und auf einer frischen Datenbank reproduzierbar.

### Offen

- **Die Dauern sind ungeprüft.** `docs/dienstleistungen-dauern.md` durchgehen, bevor
  die Buchung scharf geht. Enthält ausserdem drei inhaltliche Rückfragen (Lashes
  Neuset vs. Auffüllen, Zonen-Pakete, 15-Minuten-Termine).
- Die Spalte `notiz` aus dem CSV ist nicht importiert — „ab-Preis" ist über `preis_ab`
  abgebildet, „Konsultation" hat kein Feld.
- **Der "Weiter"-Button ist bewusst deaktiviert** — Ziel ist Teilaufgabe 4.
- Das Figma-Mockup lag mir nicht vor; die Karten folgen den bestehenden Tokens aus
  `index.css` und der Optik von `MeineTermine`. Feinschliff gegen Figma steht in Phase 7.
- Kein Zurücksetzen der Auswahl, wenn eine Behandlung während der Sitzung deaktiviert
  wird. Unkritisch, weil der INSERT in Teilaufgabe 5 ohnehin gegen die DB läuft.
- Die Liste wird einmal beim Mount geladen, ohne Neuladen im Hintergrund. Für einen
  Katalog, der sich selten ändert, ausreichend.
