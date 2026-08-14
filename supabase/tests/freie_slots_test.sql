-- ============================================================
-- Testfaelle fuer public.freie_slots()
--
-- SO BENUTZEN: komplett markieren und im Supabase SQL Editor ausfuehren.
-- Am Ende erscheint EINE Ergebnistabelle mit allen 12 Testfaellen.
-- (Der SQL Editor zeigt beim Ausfuehren eines Skripts nur das Ergebnis der
-- letzten Abfrage -- deshalb werden alle Teilergebnisse unterwegs in einer
-- temporaeren Tabelle gesammelt und ganz am Schluss zusammen ausgegeben.)
--
-- Das Skript laeuft in einer Transaktion, die mit ROLLBACK endet -- es bleibt
-- KEIN Testdatensatz zurueck. Auch die aufgeraeumten echten Termine und
-- Sperrzeiten sind nach dem Rollback wieder da.
--
-- VORAUSSETZUNG: Migrationen 20260814100000, 20260814100100 und
-- 20260814110000 sind ausgefuehrt, und es existiert mindestens ein
-- profiles-Eintrag (also mindestens eine registrierte Kundin).
--
-- ERWARTUNG: Spalte "status" zeigt in jeder Zeile PASS (die letzte Zeile ist
-- eine INFO-Zeile zur Sichtkontrolle, kein Test).
--
-- Testtage:
--   2026-09-02  Mittwoch, Sommerzeit (CEST = UTC+2), geoeffnet 09:00-20:30
--   2026-09-06  Sonntag, geschlossen
--   2026-12-02  Mittwoch, Winterzeit (CET = UTC+1)
-- ============================================================

begin;

-- ------------------------------------------------------------
-- Vorbedingung pruefen
-- ------------------------------------------------------------
do $$
begin
  if not exists (select 1 from public.profiles) then
    raise exception
      'Kein Eintrag in profiles vorhanden. Bitte zuerst einmal in der App registrieren.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Sammelstelle fuer die Testergebnisse
-- ok = null bedeutet: reine Info-Zeile, kein Test
-- ------------------------------------------------------------
create temp table testergebnisse (
  nr   integer,
  test text,
  ok   boolean,
  ist  text
) on commit drop;

-- ------------------------------------------------------------
-- Ausgangslage deterministisch machen
-- Oeffnungszeiten koennten von der Admin geaendert worden sein, und an den
-- Testtagen koennten echte Buchungen liegen -- beides wuerde die erwarteten
-- Zahlen verfaelschen. Wird durch den ROLLBACK am Ende zurueckgenommen.
-- ------------------------------------------------------------
update public.oeffnungszeiten
  set geoeffnet = true, start_zeit = '09:00', end_zeit = '20:30'
  where wochentag = 3;                      -- Mittwoch

update public.oeffnungszeiten
  set geoeffnet = false, start_zeit = null, end_zeit = null
  where wochentag = 0;                      -- Sonntag

delete from public.termine
  where start_zeit >= '2026-09-01' and start_zeit < '2027-01-01';

delete from public.sperrzeiten
  where start_zeit >= '2026-09-01' and start_zeit < '2027-01-01';

-- ------------------------------------------------------------
-- Test-Dienstleistungen
-- ------------------------------------------------------------
insert into public.dienstleistungen (id, name, kategorie, dauer_minuten, preis_rappen, aktiv) values
  ('aaaaaaaa-0000-0000-0000-000000000060', 'TEST 60 Minuten', 'kosmetik', 60,   9000, true),
  ('aaaaaaaa-0000-0000-0000-000000000050', 'TEST 50 Minuten', 'kosmetik', 50,   7500, true),
  ('aaaaaaaa-0000-0000-0000-000000000999', 'TEST inaktiv',    'kosmetik', 60,   9000, false),
  ('aaaaaaaa-0000-0000-0000-000000000800', 'TEST 13 Stunden', 'laser',    780, 50000, true);


-- ============================================================
-- BLOCK A -- leerer Tag (noch keine Termine, keine Sperrzeiten)
-- ============================================================

-- T1: Leerer Mittwoch, 60-Min-Behandlung.
-- 09:00 bis 20:30 = 11.5 h. Letzter moeglicher Start ist 19:30 (endet
-- punktgenau zu Ladenschluss). Von 09:00 bis 19:30 im 15-Min-Raster
-- sind das 43 Startzeiten.
insert into testergebnisse
select 1, 'leerer Tag, 60 Min -> 43 Slots',
       count(*) = 43,
       count(*)::text || ' Slots'
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060');

-- T2: Raender -- erster Slot exakt zur Oeffnung, letzter so, dass er
-- punktgenau zu Ladenschluss endet. Der Grenzfall aus der Checkliste.
insert into testergebnisse
select 2, 'Grenzen: erster 09:00, letzter 19:30',
       min(s) at time zone 'Europe/Zurich' = timestamp '2026-09-02 09:00'
       and max(s) at time zone 'Europe/Zurich' = timestamp '2026-09-02 19:30',
       to_char(min(s) at time zone 'Europe/Zurich', 'HH24:MI')
         || ' / ' || to_char(max(s) at time zone 'Europe/Zurich', 'HH24:MI')
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s;

-- T3: Zeitzone Sommer -- 09:00 Zuercher Wandzeit muss 07:00 UTC sein
-- (CEST = UTC+2). Der klassische Fehler waere ein hartcodierter Offset.
insert into testergebnisse
select 3, 'Sommerzeit: 09:00 Zuerich = 07:00 UTC',
       min(s) = timestamptz '2026-09-02 07:00+00',
       to_char(min(s) at time zone 'UTC', 'HH24:MI') || ' UTC'
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s;

-- T4: Zeitzone Winter -- derselbe Wochentag im Dezember, 09:00 Zuerich ist
-- jetzt 08:00 UTC (CET = UTC+1). Beweist, dass die Umstellung automatisch
-- mitlaeuft. MUSS vor der Ganztags-Sperre in Block C laufen.
insert into testergebnisse
select 4, 'Winterzeit: 09:00 Zuerich = 08:00 UTC',
       min(s) = timestamptz '2026-12-02 08:00+00',
       to_char(min(s) at time zone 'UTC', 'HH24:MI') || ' UTC'
from public.freie_slots('2026-12-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s;

-- T5: Geschlossener Tag (Sonntag) -> gar keine Slots.
insert into testergebnisse
select 5, 'geschlossener Tag -> 0 Slots',
       count(*) = 0,
       count(*)::text || ' Slots'
from public.freie_slots('2026-09-06', 'aaaaaaaa-0000-0000-0000-000000000060');

-- T6: Inaktive Dienstleistung ist nicht buchbar.
insert into testergebnisse
select 6, 'inaktive Dienstleistung -> 0 Slots',
       count(*) = 0,
       count(*)::text || ' Slots'
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000999');

-- T7: Behandlung laenger als der Oeffnungstag (13 h bei 11.5 h offen)
-- -> kein Slot passt rein, statt eines Fehlers.
insert into testergebnisse
select 7, 'Dauer > Oeffnungstag -> 0 Slots',
       count(*) = 0,
       count(*)::text || ' Slots'
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000800');

-- T8: Krumme Dauer im 15-Min-Raster -- 50-Min-Behandlung. Startzeiten
-- bleiben im Raster, das Ende faellt krumm (09:00 -> 09:50). Rechnerisch
-- waere 19:40 der letzte moegliche Start, der liegt aber nicht im Raster,
-- also ist 19:30 der letzte.
insert into testergebnisse
select 8, '50-Min-Dauer: letzter Start 19:30',
       max(s) at time zone 'Europe/Zurich' = timestamp '2026-09-02 19:30',
       to_char(max(s) at time zone 'Europe/Zurich', 'HH24:MI')
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000050') as s;


-- ============================================================
-- BLOCK B -- Tag mit Buchung und Sperrzeit
-- ============================================================

-- Bestehender Termin 12:00-13:00 Zuercher Zeit
insert into public.termine (kundin_id, dienstleistung_id, start_zeit, end_zeit, status)
values (
  (select id from public.profiles limit 1),
  'aaaaaaaa-0000-0000-0000-000000000060',
  (timestamp '2026-09-02 12:00') at time zone 'Europe/Zurich',
  (timestamp '2026-09-02 13:00') at time zone 'Europe/Zurich',
  'bestaetigt'
);

-- Sperrzeit 15:00-16:00 Zuercher Zeit (Pause mitten im Tag)
insert into public.sperrzeiten (start_zeit, end_zeit, grund)
values (
  (timestamp '2026-09-02 15:00') at time zone 'Europe/Zurich',
  (timestamp '2026-09-02 16:00') at time zone 'Europe/Zurich',
  'TEST Pause'
);

-- T9: Teilweise gebuchter Tag. Ein 60-Min-Slot kollidiert mit dem Termin
-- 12:00-13:00, wenn er nach 11:00 startet und vor 13:00 beginnt:
-- 11:15, 11:30, 11:45, 12:00, 12:15, 12:30, 12:45 = 7 Slots.
-- Die Sperrzeit 15:00-16:00 nimmt nach derselben Rechnung 7 weitere weg.
-- 43 - 7 - 7 = 29.
insert into testergebnisse
select 9, 'Termin + Sperrzeit -> 43-7-7 = 29',
       count(*) = 29,
       count(*)::text || ' Slots'
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060');

-- T10: Direkt anschliessend buchen muss erlaubt bleiben. Zeitbereiche sind
-- [start, ende) -- ein Termin bis 13:00 blockiert 13:00 selbst nicht, und
-- ein Slot der punktgenau um 12:00 endet (Start 11:00) auch nicht.
-- Dieselbe Logik nutzt der Doppelbuchungs-Constraint auf termine.
insert into testergebnisse
select 10, 'Anschluss: 11:00 und 13:00 noch frei',
       bool_or(z = timestamp '2026-09-02 11:00')
       and bool_or(z = timestamp '2026-09-02 13:00'),
       '11:00 frei=' || bool_or(z = timestamp '2026-09-02 11:00')::text
         || ', 13:00 frei=' || bool_or(z = timestamp '2026-09-02 13:00')::text
from (
  select s at time zone 'Europe/Zurich' as z
  from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s
) x;

-- T11: Belegte Zeiten sind wirklich weg, nicht nur seltener.
insert into testergebnisse
select 11, '12:00 (Termin) und 15:00 (Sperre) weg',
       not bool_or(z = timestamp '2026-09-02 12:00')
       and not bool_or(z = timestamp '2026-09-02 15:00'),
       '12:00 weg=' || (not bool_or(z = timestamp '2026-09-02 12:00'))::text
         || ', 15:00 weg=' || (not bool_or(z = timestamp '2026-09-02 15:00'))::text
from (
  select s at time zone 'Europe/Zurich' as z
  from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s
) x;


-- ============================================================
-- BLOCK C -- komplett ausgebuchter Tag
-- ============================================================

-- Sperrzeit ueber die kompletten Oeffnungszeiten des 02.12.2026
insert into public.sperrzeiten (start_zeit, end_zeit, grund)
values (
  (timestamp '2026-12-02 09:00') at time zone 'Europe/Zurich',
  (timestamp '2026-12-02 20:30') at time zone 'Europe/Zurich',
  'TEST ganztags'
);

-- T12: Ganztags gesperrt -> nichts bleibt uebrig.
insert into testergebnisse
select 12, 'ausgebuchter Tag -> 0 Slots',
       count(*) = 0,
       count(*)::text || ' Slots'
from public.freie_slots('2026-12-02', 'aaaaaaaa-0000-0000-0000-000000000060');


-- ------------------------------------------------------------
-- Sichtkontrolle als Info-Zeile (ok = null -> Status INFO).
-- Bewusst als Zeile in derselben Tabelle statt als eigene Abfrage --
-- sonst wuerde sie die Ergebnistabelle im SQL Editor wieder verdecken.
-- ------------------------------------------------------------
-- Erwartete Luecken: 11:15-12:45 und 14:15-15:45. Sie beginnen 45 Minuten VOR
-- dem Hindernis, weil eine 60-Min-Behandlung ab 11:15 in den Termin um 12:00
-- hineinlaufen wuerde. Die Luecke ist also immer Hindernisdauer + Behandlungs-
-- dauer - 15 Min breit, nicht nur so lang wie das Hindernis selbst.
insert into testergebnisse
select 13, 'INFO freie Zeiten am 02.09. (Luecken 11:15-12:45 und 14:15-15:45)',
       null,
       string_agg(to_char(s at time zone 'Europe/Zurich', 'HH24:MI'), ' ' order by s)
from public.freie_slots('2026-09-02', 'aaaaaaaa-0000-0000-0000-000000000060') as s;


-- ============================================================
-- ERGEBNIS -- letzte Abfrage im Skript, deshalb die, die angezeigt wird
-- ============================================================
-- Der Ausgabe-Alias heisst bewusst NICHT "nr": ein "order by nr" wuerde sich
-- in Postgres zuerst auf den Ausgabe-Alias beziehen und damit den Text
-- sortieren (T1, T10, T11, T2, ...) statt die Zahl.
select
  'T' || nr as fall,
  test,
  case when ok is null then 'INFO'
       when ok        then 'PASS'
       else                'FAIL'
  end as status,
  ist
from testergebnisse
order by nr;

rollback;
