-- Preis-Feld fuer dienstleistungen (Schritt 2 von 2)
--
-- ERST AUSFUEHREN, wenn fuer ALLE Zeilen in dienstleistungen ein Preis
-- eingetragen ist (auch fuer die mit aktiv = false -- not null gilt fuer
-- die ganze Tabelle, nicht nur fuer die aktiven Eintraege).
--
-- Pruefen, ob noch was fehlt:
--   select id, name, aktiv from public.dienstleistungen where preis_rappen is null;
-- Kommt eine leere Liste zurueck, laeuft diese Migration durch.

alter table public.dienstleistungen
  alter column preis_rappen set not null;

-- Der alte Check erlaubte NULL (war noetig, solange die Spalte leer sein durfte).
-- Jetzt reicht die reine >= 0 Pruefung.
alter table public.dienstleistungen
  drop constraint dienstleistungen_preis_rappen_check;

alter table public.dienstleistungen
  add constraint dienstleistungen_preis_rappen_check
  check (preis_rappen >= 0);

comment on column public.dienstleistungen.preis_rappen is
  'Preis in Rappen (9000 = CHF 90.00). Pflichtfeld.';
