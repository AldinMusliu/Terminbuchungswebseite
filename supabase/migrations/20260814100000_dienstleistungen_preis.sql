-- Preis-Feld fuer dienstleistungen (Schritt 1 von 2)
--
-- Das Figma-Mockup zeigt ueberall Preise (z.B. "CHF 90"), das Feld fehlte bisher.
--
-- Warum Rappen (integer) statt CHF-Kommazahl:
-- Ganzzahlige Rappen koennen keine Rundungsfehler bekommen. Formatiert wird
-- erst in der UI: preis_rappen / 100 -> "CHF 90.00".
--
-- Warum hier noch NULL erlaubt:
-- Der Preis soll am Ende Pflichtfeld sein. Ein "not null" waere aber
-- fehlgeschlagen, solange bereits Dienstleistungen ohne Preis in der Tabelle
-- stehen. Deshalb: erst Spalte anlegen, Preise im Table Editor nachtragen,
-- danach Migration 20260814100100 ausfuehren -> setzt not null.

alter table public.dienstleistungen
  add column preis_rappen integer
  check (preis_rappen is null or preis_rappen >= 0);

comment on column public.dienstleistungen.preis_rappen is
  'Preis in Rappen (9000 = CHF 90.00).';
