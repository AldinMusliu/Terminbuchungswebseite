-- Verfuegbarkeits-Logik: freie Startzeiten fuer eine Dienstleistung an einem Tag
--
-- Aufruf aus dem Frontend:
--   supabase.rpc('freie_slots', { p_datum: '2026-09-02', p_dienstleistung_id: '...' })
--   -> [ '2026-09-02T07:00:00Z', '2026-09-02T07:15:00Z', ... ]  (timestamptz, UTC)
--
-- WARUM security definer:
-- Die RLS-Policy termine_select_own laesst eine Kundin nur ihre EIGENEN Termine
-- sehen. Wer freie Slots berechnen will, muss aber ALLE bestaetigten Termine
-- kennen. Im Frontend ginge das nur, wenn man termine fuer alle lesbar macht --
-- das wuerde preisgeben, wer wann gebucht hat. Deshalb rechnet die Datenbank:
-- security definer umgeht RLS kontrolliert, gibt aber ausschliesslich
-- Start-Zeitstempel zurueck, nie Namen, IDs oder sonstige Termindaten.
-- set search_path = '' verhindert, dass ueber einen manipulierten search_path
-- eigener Code mit den Rechten des Function-Owners ausgefuehrt wird -- bei
-- security definer Pflicht, nicht optional.

create or replace function public.freie_slots(
  p_datum date,
  p_dienstleistung_id uuid
)
returns setof timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with dienstleistung as (
    -- Nur aktive Dienstleistungen sind buchbar. Findet sich keine Zeile,
    -- bleibt das Ergebnis leer (cross join unten liefert dann nichts).
    select d.dauer_minuten
    from public.dienstleistungen d
    where d.id = p_dienstleistung_id
      and d.aktiv = true
  ),
  oeffnung as (
    -- Oeffnungszeiten sind reine Uhrzeiten (time) ohne Datum/Zone.
    -- p_datum + start_zeit ergibt einen timestamp OHNE Zone, danach
    -- interpretiert "at time zone 'Europe/Zurich'" ihn als Zuercher
    -- Wandzeit und macht daraus einen echten timestamptz.
    -- 09:00 in Zuerich ist damit im Sommer 07:00 UTC und im Winter
    -- 08:00 UTC -- die Umstellung passiert automatisch, ohne dass
    -- irgendwo ein Offset hartcodiert ist.
    select
      (p_datum + o.start_zeit) at time zone 'Europe/Zurich' as tag_start,
      (p_datum + o.end_zeit)   at time zone 'Europe/Zurich' as tag_ende
    from public.oeffnungszeiten o
    where o.wochentag = extract(dow from p_datum)::smallint
      and o.geoeffnet = true
  ),
  kandidaten as (
    -- 15-Minuten-Raster: das Raster bestimmt nur, WANN ein Termin starten
    -- kann. Das Ende richtet sich nach der tatsaechlichen dauer_minuten und
    -- muss selbst nicht aufs Raster fallen (50-Min-Behandlung um 09:00
    -- endet 09:50, naechster moeglicher Start ist 10:00).
    --
    -- generate_series endet bei tag_ende - dauer: der letzte Kandidat ist
    -- der, der gerade noch komplett vor Ladenschluss fertig wird. Ist die
    -- Behandlung laenger als der ganze Oeffnungstag, kommt nichts zurueck.
    select
      s.slot_start,
      s.slot_start + make_interval(mins => d.dauer_minuten) as slot_ende
    from oeffnung f
    cross join dienstleistung d
    cross join lateral generate_series(
      f.tag_start,
      f.tag_ende - make_interval(mins => d.dauer_minuten),
      interval '15 minutes'
    ) as s(slot_start)
  )
  select k.slot_start
  from kandidaten k
  where
    -- Vergangenes ist nicht buchbar. Betrifft vor allem "heute":
    -- am Nachmittag sollen die Vormittags-Slots verschwunden sein.
    k.slot_start > now()

    -- Kein Ueberlappen mit bestehenden Buchungen. && ist der
    -- Ueberlappungs-Operator auf Zeitbereichen und deckt alle Faelle ab
    -- (Slot startet mitten im Termin, Termin startet mitten im Slot,
    -- einer umschliesst den anderen). Zeitbereiche in Postgres sind
    -- [start, ende) -- ein Termin 09:00-10:00 blockiert den Slot 10:00
    -- also NICHT, direkt anschliessen ist erlaubt.
    and not exists (
      select 1
      from public.termine t
      where t.status = 'bestaetigt'
        and tstzrange(t.start_zeit, t.end_zeit)
            && tstzrange(k.slot_start, k.slot_ende)
    )

    -- Kein Ueberlappen mit einer Sperrzeit (Pause, Urlaub, privater Termin).
    and not exists (
      select 1
      from public.sperrzeiten sp
      where tstzrange(sp.start_zeit, sp.end_zeit)
            && tstzrange(k.slot_start, k.slot_ende)
    )
  order by k.slot_start;
$$;

comment on function public.freie_slots(date, uuid) is
  'Freie Startzeiten fuer eine Dienstleistung an einem Tag. 15-Min-Raster, '
  'beruecksichtigt Oeffnungszeiten, Sperrzeiten und bestehende Termine. '
  'security definer, damit fremde Termine geprueft werden koennen ohne sie preiszugeben.';

-- Ausfuehrungsrecht bewusst setzen statt sich auf das Standard-PUBLIC-Recht
-- zu verlassen: nur die beiden Frontend-Rollen duerfen die Funktion aufrufen.
-- Auch ohne Login abrufbar, damit eine oeffentliche Terminuebersicht moeglich
-- bleibt -- freie Zeiten sind keine personenbezogenen Daten.
revoke execute on function public.freie_slots(date, uuid) from public;
grant execute on function public.freie_slots(date, uuid) to anon, authenticated;
