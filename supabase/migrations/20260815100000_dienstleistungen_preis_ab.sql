-- Kennzeichnet Behandlungen, deren Preis ein Startpreis ist ("ab CHF 75.00").
-- Betrifft die Wimpernverlaengerungen: der Endpreis haengt vom Aufwand ab.
--
-- Kein RLS-Handlungsbedarf: neue Spalte auf einer bestehenden Tabelle, keine
-- neue Tabelle. Die Policies auf dienstleistungen gelten unveraendert weiter
-- (oeffentlich lesbar nur fuer aktiv = true, schreiben nur Admin). Preise sind
-- keine personenbezogenen Daten.

alter table public.dienstleistungen
  add column preis_ab boolean not null default false;

comment on column public.dienstleistungen.preis_ab is
  'true = preis_rappen ist ein Startpreis, die UI zeigt "ab CHF x". '
  'false = Fixpreis. Bei preis_rappen = 0 zeigt die UI "Kostenlos".';
