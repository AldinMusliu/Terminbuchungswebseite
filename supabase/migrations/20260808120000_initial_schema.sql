-- Initial Schema: Rajana Beauty Terminbuchung
-- Siehe docs/schema.md und docs/decisions.md fuer Begruendungen.

-- ============================================================
-- Extensions
-- ============================================================
create extension if not exists btree_gist;

-- ============================================================
-- Helper: Admin-Check ueber app_metadata (nicht user_metadata!)
-- app_metadata ist nur per service_role aenderbar, also nicht
-- durch Kundinnen selbst manipulierbar (siehe docs/decisions.md).
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

-- ============================================================
-- profiles: Kontaktdaten der Kundin, 1:1 mit auth.users
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using ( (select auth.uid()) = id );

create policy "profiles_select_admin"
  on public.profiles for select
  to authenticated
  using ( public.is_admin() );

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check ( (select auth.uid()) = id );

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using ( (select auth.uid()) = id )
  with check ( (select auth.uid()) = id );

-- ============================================================
-- dienstleistungen: Behandlungen mit anpassbarer Dauer
-- Oeffentlich sichtbar (auch ohne Login) fuer Landingpage/Uebersicht,
-- Buchen selbst bleibt an ein Konto gebunden (siehe termine).
-- ============================================================
create table public.dienstleistungen (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kategorie text not null check (kategorie in ('kosmetik', 'laser', 'tattoo_entfernung')),
  dauer_minuten integer not null check (dauer_minuten > 0),
  aktiv boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.dienstleistungen enable row level security;

create policy "dienstleistungen_select_aktiv"
  on public.dienstleistungen for select
  to anon, authenticated
  using ( aktiv = true );

create policy "dienstleistungen_admin_select_all"
  on public.dienstleistungen for select
  to authenticated
  using ( public.is_admin() );

create policy "dienstleistungen_admin_insert"
  on public.dienstleistungen for insert
  to authenticated
  with check ( public.is_admin() );

create policy "dienstleistungen_admin_update"
  on public.dienstleistungen for update
  to authenticated
  using ( public.is_admin() )
  with check ( public.is_admin() );

create policy "dienstleistungen_admin_delete"
  on public.dienstleistungen for delete
  to authenticated
  using ( public.is_admin() );

-- ============================================================
-- oeffnungszeiten: eine Zeile pro Wochentag, admin-editierbar
-- (0 = Sonntag ... 6 = Samstag). Oeffentlich sichtbar.
-- ============================================================
create table public.oeffnungszeiten (
  wochentag smallint primary key check (wochentag between 0 and 6),
  geoeffnet boolean not null default false,
  start_zeit time,
  end_zeit time,
  check (
    geoeffnet = false
    or (start_zeit is not null and end_zeit is not null and end_zeit > start_zeit)
  )
);

insert into public.oeffnungszeiten (wochentag, geoeffnet, start_zeit, end_zeit) values
  (0, false, null, null),
  (1, false, null, null),
  (2, true, '09:00', '20:30'),
  (3, true, '09:00', '20:30'),
  (4, true, '09:00', '20:30'),
  (5, true, '09:00', '20:30'),
  (6, true, '09:00', '20:30');

alter table public.oeffnungszeiten enable row level security;

create policy "oeffnungszeiten_select_all"
  on public.oeffnungszeiten for select
  to anon, authenticated
  using ( true );

create policy "oeffnungszeiten_admin_update"
  on public.oeffnungszeiten for update
  to authenticated
  using ( public.is_admin() )
  with check ( public.is_admin() );

-- ============================================================
-- sperrzeiten: admin-gepflegte Ausnahmen innerhalb der Oeffnungszeiten
-- Oeffentlich sichtbar, damit auch nicht eingeloggte Besucherinnen
-- sehen, wann tatsaechlich frei ist.
-- ============================================================
create table public.sperrzeiten (
  id uuid primary key default gen_random_uuid(),
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  grund text,
  created_at timestamptz not null default now(),
  check (end_zeit > start_zeit)
);

alter table public.sperrzeiten enable row level security;

create policy "sperrzeiten_select_all"
  on public.sperrzeiten for select
  to anon, authenticated
  using ( true );

create policy "sperrzeiten_admin_insert"
  on public.sperrzeiten for insert
  to authenticated
  with check ( public.is_admin() );

create policy "sperrzeiten_admin_update"
  on public.sperrzeiten for update
  to authenticated
  using ( public.is_admin() )
  with check ( public.is_admin() );

create policy "sperrzeiten_admin_delete"
  on public.sperrzeiten for delete
  to authenticated
  using ( public.is_admin() );

-- ============================================================
-- termine: die eigentliche Buchung
-- ============================================================
create table public.termine (
  id uuid primary key default gen_random_uuid(),
  kundin_id uuid not null references public.profiles(id) on delete cascade,
  dienstleistung_id uuid not null references public.dienstleistungen(id),
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  status text not null default 'bestaetigt' check (status in ('bestaetigt', 'storniert')),
  created_at timestamptz not null default now(),
  check (end_zeit > start_zeit)
);

create index on public.termine (kundin_id);
create index on public.termine (dienstleistung_id);
create index on public.termine (start_zeit);

-- Doppelbuchungsschutz auf DB-Ebene: keine zwei ueberlappenden
-- bestaetigten Termine, unabhaengig davon wer/wie gebucht hat.
alter table public.termine
  add constraint termine_keine_ueberschneidung
  exclude using gist (tstzrange(start_zeit, end_zeit) with &&)
  where (status = 'bestaetigt');

alter table public.termine enable row level security;

create policy "termine_select_own"
  on public.termine for select
  to authenticated
  using ( (select auth.uid()) = kundin_id );

create policy "termine_select_admin"
  on public.termine for select
  to authenticated
  using ( public.is_admin() );

create policy "termine_insert_own"
  on public.termine for insert
  to authenticated
  with check ( (select auth.uid()) = kundin_id );

create policy "termine_insert_admin"
  on public.termine for insert
  to authenticated
  with check ( public.is_admin() );

-- Kundinnen duerfen eigene Termine aktualisieren (fuers Stornieren).
-- Einschraenkung "nur Status, nicht Zeit/Dienstleistung aenderbar"
-- wird spaeter per Trigger ergaenzt (siehe docs/schema.md, "Offen").
create policy "termine_update_own"
  on public.termine for update
  to authenticated
  using ( (select auth.uid()) = kundin_id )
  with check ( (select auth.uid()) = kundin_id );

create policy "termine_update_admin"
  on public.termine for update
  to authenticated
  using ( public.is_admin() )
  with check ( public.is_admin() );
