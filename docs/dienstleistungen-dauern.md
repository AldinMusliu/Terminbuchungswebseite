# Behandlungsdauern — zum Gegenlesen

Im gelieferten `dienstleistungen.csv` war die Spalte `dauer_minuten` bei 40 von 42
Behandlungen leer. Nur „Wimpern Lifting ohne/mit Färben" hatte Werte (60 / 75).

`dauer_minuten` ist aber Pflichtfeld und die Grundlage der Slot-Berechnung
(`freie_slots`, siehe `docs/schema.md`). Die Werte unten sind deshalb **Schätzwerte
von mir**, keine Angaben aus dem Betrieb — sie stehen so in
`supabase/migrations/20260815100100_dienstleistungen_katalog.sql`.

**Bitte durchgehen und korrigieren.** Nur die Minuten müssen stimmen, Preise und
Namen kommen aus dem CSV.

## Was eine falsche Dauer bewirkt

- **Zu kurz** → Termine überschneiden sich in der Realität. Der Doppelbuchungsschutz
  in der DB merkt nichts, weil er nur die eingetragenen Zeiten kennt.
- **Zu lang** → der Kalender wirkt voller, als er ist. Es gehen buchbare Slots verloren.

Die Startzeiten laufen im 15-Minuten-Raster, die Dauer selbst darf krumm sein.
Es lohnt sich, die Zeit für Vor- und Nachbereitung mitzurechnen (Umziehen, Reinigen,
Nachgespräch), nicht nur die reine Behandlungszeit.

## Tattoo-Entfernung

| Behandlung | Preis | Vorschlag | Korrektur |
|---|---|---|---|
| Beratungsgespräch Tattooentfernen/PMU/Microblading | Kostenlos | 30 Min. | |
| Augenbrauen / PMU / Microblading | CHF 189.00 | 30 Min. | |
| Grösse XS (1 x 5cm) | CHF 180.00 | 30 Min. | |
| Grösse S (5 x 10cm) | CHF 260.00 | 30 Min. | |
| Grösse M (10x10) | CHF 420.00 | 45 Min. | |
| Grösse XL (15 x 15) | CHF 650.00 | 60 Min. | |

⚠️ **XS und S stehen beide auf 30 Minuten**, obwohl S doppelt so gross und CHF 80
teurer ist. Falls S länger dauert, hier korrigieren.

## Laser / dauerhafte Haarentfernung

| Behandlung | Preis | Vorschlag | Korrektur |
|---|---|---|---|
| Beratungsgespräch dauerhafte Haarentfernung | Kostenlos | 30 Min. | |
| Primelase 3 Zonen | CHF 119.00 | 45 Min. | |
| Primelase 5 Zonen | CHF 179.00 | 75 Min. | |
| Primelase Ganzkörper (Kopf-Fuss) | CHF 249.00 | 90 Min. | |
| 4 Zonen | CHF 149.00 | 60 Min. | |
| 2 Zonen | CHF 80.00 | 30 Min. | |
| Gesicht | CHF 49.00 | 30 Min. | |
| Kinn | CHF 25.00 | 15 Min. | |
| Oberlippe | CHF 25.00 | 15 Min. | |
| Achseln | CHF 45.00 | 15 Min. | |
| Oberarm | CHF 45.00 | 30 Min. | |
| Unterarm | CHF 45.00 | 30 Min. | |
| Arme komplett | CHF 79.00 | 45 Min. | |
| Oberschenkel | CHF 79.00 | 45 Min. | |
| Unterschenkel | CHF 79.00 | 45 Min. | |
| Beine komplett | CHF 89.00 | 60 Min. | |
| Bauch | CHF 45.00 | 30 Min. | |
| Intimzone | CHF 59.00 | 30 Min. | |
| Bikinizone | CHF 45.00 | 30 Min. | |
| Hände | CHF 29.00 | 15 Min. | |
| Rücken | CHF 69.00 | 45 Min. | |
| Brust | CHF 39.00 | 30 Min. | |
| Gesäss | CHF 49.00 | 30 Min. | |
| Füsse | CHF 29.00 | 15 Min. | |

⚠️ **15-Minuten-Termine sind knapp.** Bei Kinn, Oberlippe, Achseln, Hände und Füsse
ist die reine Laserzeit kurz, aber Empfang, Umziehen und Nachgespräch kommen dazu.
Falls realistisch 30 Minuten pro Kundin draufgehen, sollte das auch so drinstehen —
sonst steht der Kalender ständig unter Druck.

⚠️ **Die Zonen-Pakete passen preislich nicht zur Systematik:** „4 Zonen" kostet
CHF 149.00, „Primelase 5 Zonen" nur CHF 179.00, „Primelase 3 Zonen" CHF 119.00.
Sind „4 Zonen" und „2 Zonen" andere Geräte/Leistungen als die Primelase-Pakete?
Falls ja, gehört das evtl. in den Namen, damit Kundinnen es unterscheiden können.

## Kosmetik

| Behandlung | Preis | Vorschlag | Korrektur |
|---|---|---|---|
| 2D Lashes | ab CHF 75.00 | 120 Min. | |
| 3D Lashes | ab CHF 75.00 | 120 Min. | |
| 5D Lashes | ab CHF 79.00 | 135 Min. | |
| 7D Lashes | ab CHF 89.00 | 150 Min. | |
| Wimpern entfernen | CHF 20.00 | 30 Min. | |
| Wimpern Lifting ohne Färben | CHF 60.00 | **60 Min.** ✅ | aus CSV |
| Wimpern Lifting mit Färben | CHF 70.00 | **75 Min.** ✅ | aus CSV |
| Korean Lash Lift | CHF 80.00 | 75 Min. | |
| Augenbrauen Lifting | CHF 60.00 | 60 Min. | |
| Carbon Peeling | CHF 139.00 | 60 Min. | |
| Algen Peeling | CHF 249.00 | 90 Min. | |
| Beratungsgespräch Gesicht | Kostenlos | 30 Min. | |

⚠️ **Die Lashes sind die kritischsten Werte.** 120–150 Minuten blockieren den halben
Tag. Ausserdem: gelten die Zeiten für ein **Neuset** oder für ein **Auffüllen**? Das
sind normalerweise sehr unterschiedliche Termine. Falls beides angeboten wird,
sollten es getrennte Einträge sein (z.B. „3D Lashes Neuset" / „3D Lashes Auffüllen") —
sonst passt die Dauer immer nur für einen der beiden Fälle.

⚠️ **2D und 3D Lashes kosten beide ab CHF 75.00** und haben dieselbe Dauer. Falls das
stimmt, gut — sonst ist im CSV eine Zeile verrutscht.

## Weitere offene Punkte aus dem CSV

- **Die Spalte `notiz`** („ab-Preis", „Konsultation") hat kein Feld im Schema. Der
  „ab-Preis"-Teil ist jetzt über `preis_ab` abgebildet, „Konsultation" ist nirgends
  gespeichert. Falls Beratungen später anders behandelt werden sollen (z.B. keine
  Anzahlung, andere Stornofrist), bräuchte es ein eigenes Feld.
- **Kein Puffer zwischen Terminen.** Aufräumen und Umbauen ist aktuell nirgends
  eingeplant — entweder in die Dauer einrechnen oder später als eigenes Feld ergänzen
  (steht schon unter *Offen* in `docs/buchungsseite.md`).
