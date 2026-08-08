# Datenbank-Schema

Status: **Live in Supabase.** Migration `supabase/migrations/20260808120000_initial_schema.sql`
wurde erfolgreich ausgeführt (RLS aktiv, Doppelbuchungsschutz verifiziert).

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
  aktiv boolean not null default true,
  created_at timestamptz not null default now()
);
```

`aktiv` statt Löschen: eine deaktivierte Behandlung bleibt für bestehende Termine referenzierbar.

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

## RLS-Policies (Zusammenfassung)

| Tabelle | Öffentlich (`anon`) | Kundin (`authenticated`) | Admin |
|---|---|---|---|
| `profiles` | – | SELECT/UPDATE nur eigene Zeile (`auth.uid() = id`) | SELECT alle |
| `dienstleistungen` | SELECT nur `aktiv = true` | SELECT nur `aktiv = true` | SELECT alle, INSERT/UPDATE/DELETE |
| `oeffnungszeiten` | SELECT alle | SELECT alle | UPDATE (kein INSERT/DELETE, Zeilen sind fix per Seed) |
| `sperrzeiten` | SELECT alle | SELECT alle | INSERT/UPDATE/DELETE |
| `termine` | – | SELECT/INSERT nur eigene (`kundin_id = auth.uid()`) | SELECT/INSERT/UPDATE alle (jede Kundin, jede Zeit) |

`dienstleistungen`, `oeffnungszeiten` und `sperrzeiten` sind bewusst auch ohne Login lesbar
(z.B. für eine öffentliche Übersichtsseite) — es sind keine personenbezogenen Daten. Buchen
selbst bleibt an ein Kundinnen-Konto gebunden.

Details und Begründungen: siehe `docs/decisions.md`.

## Offen / noch zu klären

- `dienstleistungen` hat noch kein Preis-Feld, das Figma-Mockup zeigt aber überall Preise
  (z.B. "CHF 90") — Migration nötig, sobald die Dienstleistungsseite gebaut wird.
- Buchungen nur für registrierte Kundinnen (`kundin_id` ist Pflicht, kein Gast-Feld) — auch wenn die Admin den Termin selbst einträgt, muss vorher ein Kundinnen-Konto existieren.
- Trigger, der beim Buchen prüft, ob der gewählte Slot innerhalb der festen Öffnungszeiten liegt und nicht mit einer `sperrzeiten`-Zeile kollidiert — wird beim Bau der Buchungslogik ergänzt, nicht Teil des Basisschemas.
- Kundinnen können eigene Termine nur stornieren (Status ändern), nicht Zeit/Dienstleistung nachträglich ändern — wird über einen Trigger bei der Buchungs-UI umgesetzt. Die Admin ist davon ausgenommen und darf jeden Termin frei bearbeiten.
