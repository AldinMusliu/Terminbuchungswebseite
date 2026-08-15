# Datenbank-Schema

Status: **Live in Supabase.** Migration `supabase/migrations/20260808120000_initial_schema.sql`
wurde erfolgreich ausgeführt (RLS aktiv, Doppelbuchungsschutz verifiziert).

Nachträgliche Migrationen:
- `20260814100000_dienstleistungen_preis.sql` — Preis-Feld `preis_rappen` ergänzt
- `20260814100100_dienstleistungen_preis_pflicht.sql` — setzt `preis_rappen` auf Pflichtfeld
  (erst ausführen, wenn alle Zeilen einen Preis haben)
- `20260814110000_freie_slots.sql` — Funktion `freie_slots()` für die Verfügbarkeitsberechnung
- `20260814120000_grants_fix.sql` — Tabellen-Rechte für `anon`/`authenticated` explizit gesetzt
- `20260815100000_dienstleistungen_preis_ab.sql` — Feld `preis_ab` für Startpreise ("ab CHF 75.00")
- `20260815100100_dienstleistungen_katalog.sql` — echter Katalog (42 Behandlungen), ersetzt die Testeinträge

## Übersicht

```
auth.users (Supabase-intern, Rolle liegt in app_metadata.role)
     │ 1:1
     ▼
profiles                          dienstleistungen
  id (PK, = auth.users.id)          id (PK)
  full_name                         name
  phone                             kategorie (kosmetik | laser | tattoo_entfernung)
  created_at                        dauer_minuten
     │                              preis_rappen
     │                              aktiv
     │ 1:n                          created_at
     │                                 │ 1:n
     ▼                                 ▼
termine ◄─────────────────────────────┘
  id (PK)
  kundin_id        -> profiles.id
  dienstleistung_id -> dienstleistungen.id
  start_zeit, end_zeit
  status (bestaetigt | storniert)
  created_at

sperrzeiten (unabhängig, admin-gepflegt)
  id (PK)
  start_zeit, end_zeit
  grund
  created_at

oeffnungszeiten (7 Zeilen, admin-editierbar)
  wochentag (PK, 0=So..6=Sa)
  geoeffnet
  start_zeit, end_zeit
```

**Öffnungszeiten (eigene Tabelle, admin-editierbar):**
`oeffnungszeiten` enthält genau 7 Zeilen (eine pro Wochentag), initial mit
Di–Sa geöffnet 09:00–20:30, So/Mo geschlossen. Deine Mutter kann jede Zeile über die
Admin-Oberfläche anpassen (Uhrzeiten ändern, Tag öffnen/schliessen) — kein Code-Deploy nötig.
Buchbar ist automatisch alles innerhalb der eingetragenen Öffnungszeiten des jeweiligen
Wochentags, außer es liegt eine `sperrzeiten`-Zeile oder ein bestehender `termine`-Eintrag
darüber (Prinzip wie Google Calendar: Standard offen, gezielt blockieren statt gezielt freigeben).

## Tabellen

### `profiles`
Kontaktdaten der Kundin. 1:1 mit `auth.users`, damit Name/Telefon nicht bei jeder Buchung neu eingetippt werden müssen.

```sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  created_at timestamptz not null default now()
);
```

### `dienstleistungen`
Behandlungen mit individuell einstellbarer Dauer.

```sql
create table public.dienstleistungen (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kategorie text not null check (kategorie in ('kosmetik','laser','tattoo_entfernung')),
  dauer_minuten integer not null check (dauer_minuten > 0),
  preis_rappen integer not null check (preis_rappen >= 0),
  preis_ab boolean not null default false,
  aktiv boolean not null default true,
  created_at timestamptz not null default now()
);
```

`aktiv` statt Löschen: eine deaktivierte Behandlung bleibt für bestehende Termine referenzierbar.

`preis_rappen` speichert den Preis als ganze Rappen (`9000` = CHF 90.00), nicht als
Kommazahl — Ganzzahlen können keine Rundungsfehler bekommen. Formatiert wird erst
in der UI (`preis_rappen / 100`). Preis ist Pflichtfeld: jede Behandlung, auch eine
deaktivierte, braucht einen Preis.

`preis_ab` kennzeichnet Startpreise. Bei `true` zeigt die UI `ab CHF 75.00` statt
`CHF 75.00` — betrifft die Wimpernverlängerungen, deren Endpreis vom Aufwand abhängt.
Bei `preis_rappen = 0` zeigt die UI `Kostenlos` (die drei Beratungsgespräche).

Der Katalog ist in `20260815100100_dienstleistungen_katalog.sql` als Daten-Migration
abgelegt, damit er versioniert ist und nicht nur im Table Editor lebt. Die Dauern
darin sind Schätzwerte und noch **nicht vom Betrieb bestätigt** — Stand und
Rückfragen in `docs/dienstleistungen-dauern.md`.

### `sperrzeiten`
Zeiträume innerhalb der festen Öffnungszeiten, die die Admin gezielt blockiert
(Pause, Urlaub, privater Termin) — alles andere ist automatisch buchbar.

```sql
create table public.sperrzeiten (
  id uuid primary key default gen_random_uuid(),
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  grund text,
  created_at timestamptz not null default now(),
  check (end_zeit > start_zeit)
);
```

### `oeffnungszeiten`
Öffnungszeiten pro Wochentag, admin-editierbar. Genau 7 Zeilen, einmalig per Seed-Daten
angelegt — keine INSERT/DELETE-Policy nötig, nur UPDATE.

```sql
create table public.oeffnungszeiten (
  wochentag smallint primary key check (wochentag between 0 and 6), -- 0=So .. 6=Sa
  geoeffnet boolean not null default false,
  start_zeit time,
  end_zeit time,
  check (
    geoeffnet = false
    or (start_zeit is not null and end_zeit is not null and end_zeit > start_zeit)
  )
);

insert into public.oeffnungszeiten (wochentag, geoeffnet, start_zeit, end_zeit) values
  (0, false, null, null),        -- Sonntag: zu
  (1, false, null, null),        -- Montag: zu
  (2, true, '09:00', '20:30'),   -- Dienstag
  (3, true, '09:00', '20:30'),   -- Mittwoch
  (4, true, '09:00', '20:30'),   -- Donnerstag
  (5, true, '09:00', '20:30'),   -- Freitag
  (6, true, '09:00', '20:30');   -- Samstag
```

### `termine`
Die eigentliche Buchung.

```sql
create table public.termine (
  id uuid primary key default gen_random_uuid(),
  kundin_id uuid not null references public.profiles(id) on delete cascade,
  dienstleistung_id uuid not null references public.dienstleistungen(id),
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  status text not null default 'bestaetigt' check (status in ('bestaetigt','storniert')),
  created_at timestamptz not null default now(),
  check (end_zeit > start_zeit)
);

create index on public.termine (kundin_id);
create index on public.termine (dienstleistung_id);
create index on public.termine (start_zeit);
```

**Doppelbuchungsschutz auf DB-Ebene** (nicht nur Frontend-Check):

```sql
create extension if not exists btree_gist;

alter table public.termine
  add constraint termine_keine_ueberschneidung
  exclude using gist (tstzrange(start_zeit, end_zeit) with &&)
  where (status = 'bestaetigt');
```

## Funktionen

### `freie_slots(p_datum date, p_dienstleistung_id uuid) → setof timestamptz`

Liefert die freien Startzeiten für eine Dienstleistung an einem Tag.

```js
const { data } = await supabase.rpc('freie_slots', {
  p_datum: '2026-09-02',
  p_dienstleistung_id: '…',
});
// → ['2026-09-02T07:00:00+00:00', '2026-09-02T07:15:00+00:00', …]
```

Berücksichtigt in dieser Reihenfolge: Öffnungszeiten des Wochentags (geschlossen → leeres
Ergebnis), 15-Minuten-Raster für Startzeiten, volle `dauer_minuten` muss vor Ladenschluss
reinpassen, keine Überlappung mit bestätigten `termine`, keine Überlappung mit `sperrzeiten`,
nichts in der Vergangenheit.

**Zeitzone:** `oeffnungszeiten` speichert reine Uhrzeiten ohne Zone. Die Funktion setzt sie
per `at time zone 'Europe/Zurich'` auf das Datum und erhält damit echte `timestamptz`-Werte.
Sommer-/Winterzeit läuft automatisch mit — 09:00 Zürich ist im Sommer 07:00 UTC und im
Winter 08:00 UTC, ohne dass irgendwo ein Offset hartcodiert ist.

**Anschlusstermine:** Zeitbereiche sind `[start, ende)`. Ein Termin bis 13:00 blockiert den
Slot 13:00 also nicht — direkt anschliessen ist erlaubt. Das ist dieselbe Logik, die auch
der Doppelbuchungs-Constraint auf `termine` verwendet, beide bleiben damit konsistent.

`security definer`, weil `termine_select_own` sonst fremde Termine verbergen würde und die
Berechnung falsch wäre. Zurückgegeben werden ausschliesslich Zeitstempel, keine Termindaten.
Begründung siehe `docs/decisions.md`.

Testfälle: `supabase/tests/freie_slots_test.sql` (läuft in einer Transaktion mit ROLLBACK,
hinterlässt keine Daten).

## RLS-Policies (Zusammenfassung)

| Tabelle | Öffentlich (`anon`) | Kundin (`authenticated`) | Admin |
|---|---|---|---|
| `profiles` | – | SELECT/UPDATE nur eigene Zeile (`auth.uid() = id`) | SELECT alle |
| `dienstleistungen` | SELECT nur `aktiv = true` | SELECT nur `aktiv = true` | SELECT alle, INSERT/UPDATE/DELETE |
| `oeffnungszeiten` | SELECT alle | SELECT alle | UPDATE (kein INSERT/DELETE, Zeilen sind fix per Seed) |
| `sperrzeiten` | SELECT alle | SELECT alle | INSERT/UPDATE/DELETE |
| `termine` | – | SELECT/INSERT nur eigene (`kundin_id = auth.uid()`) | SELECT/INSERT/UPDATE alle (jede Kundin, jede Zeit) |

Diese Tabelle beschreibt nur die **RLS-Schicht** (welche Zeilen). Damit eine Rolle die Tabelle
überhaupt anfassen darf, braucht es zusätzlich ein `GRANT` — gesetzt in
`20260814120000_grants_fix.sql`. Fehlt das, scheitert die Abfrage mit
`permission denied for table …`, bevor RLS überhaupt ausgewertet wird. Bei jeder neuen Tabelle
gehören beide Schichten in dieselbe Migration; Details in `docs/decisions.md`.

Umgekehrt gilt: **`permission denied` heisst nicht zwangsläufig, dass Rechte fehlen** — es kann
auch bedeuten, dass die Anfrage mit der falschen Rolle ankommt (z.B. als `anon`, weil der
Auth-Token nicht mitgeschickt wurde). Ein realer Fall dazu steht in `docs/troubleshooting.md`.

`dienstleistungen`, `oeffnungszeiten` und `sperrzeiten` sind bewusst auch ohne Login lesbar
(z.B. für eine öffentliche Übersichtsseite) — es sind keine personenbezogenen Daten. Buchen
selbst bleibt an ein Kundinnen-Konto gebunden.

Details und Begründungen: siehe `docs/decisions.md`.

## Offen / noch zu klären

- Buchungen nur für registrierte Kundinnen (`kundin_id` ist Pflicht, kein Gast-Feld) — auch wenn die Admin den Termin selbst einträgt, muss vorher ein Kundinnen-Konto existieren.
- **Offene Lücke: `freie_slots()` berechnet, erzwingt aber nichts.** Die Funktion sagt, was
  frei ist — sie hindert niemanden daran, per direktem INSERT einen Termin ausserhalb der
  Öffnungszeiten oder über einer Sperrzeit anzulegen. Die RLS-Policy `termine_insert_own`
  prüft nur `kundin_id = auth.uid()`, der Exclusion-Constraint nur Überlappung mit anderen
  Terminen. Ein Trigger auf `termine`, der dieselben Regeln beim INSERT/UPDATE durchsetzt,
  fehlt noch. Solange er fehlt, ist die Slot-Auswahl in der UI eine Bequemlichkeit, keine
  Absicherung.
- Kundinnen können eigene Termine nur stornieren (Status ändern), nicht Zeit/Dienstleistung nachträglich ändern — wird über einen Trigger bei der Buchungs-UI umgesetzt. Die Admin ist davon ausgenommen und darf jeden Termin frei bearbeiten.
