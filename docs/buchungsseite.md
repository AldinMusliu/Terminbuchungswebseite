# Buchungsseite (Kundenseite)

Fortschritts- und Entscheidungsprotokoll zum Buchungsflow. Ein Abschnitt pro
abgeschlossener Teilaufgabe: was gebaut wurde, warum so, was noch offen ist.

Grundlage: `checkliste-buchungsflow.md` (Rajana-Beauty-Ablage).
Schema: `docs/schema.md` · Architektur-Entscheidungen: `docs/decisions.md`

---

## 1 — Preis-Feld für Dienstleistungen

**Status:** Migrationen geschrieben, noch nicht in Supabase ausgeführt.

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
