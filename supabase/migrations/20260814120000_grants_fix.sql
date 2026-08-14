-- Tabellen-Rechte fuer die beiden Frontend-Rollen explizit setzen
--
-- HINTERGRUND: Zugriff in Postgres hat ZWEI Schichten, die unabhaengig
-- voneinander greifen:
--   1. GRANT  -- darf die Rolle die Tabelle ueberhaupt anfassen?
--   2. RLS    -- welche ZEILEN darf sie dabei sehen/aendern?
-- Die Policies aus dem Initial-Schema regeln ausschliesslich Schicht 2.
-- Fehlt Schicht 1, kommt Postgres bei RLS gar nicht erst an und meldet
-- "permission denied for table ..." -- eine perfekt formulierte Policy
-- aendert daran nichts.
--
-- Diese Migration setzt Schicht 1 explizit, statt sich auf die
-- default privileges der Supabase-Instanz zu verlassen. Ein GRANT auf ein
-- bereits vorhandenes Recht ist ein No-op, die Migration ist also
-- gefahrlos auch dann ausfuehrbar, wenn die Rechte schon stimmen.
--
-- Die Rechte spiegeln exakt die RLS-Policy-Tabelle in docs/schema.md.
-- Bewusst KEIN "grant all": was keine Policy erlaubt, braucht auch kein
-- Tabellenrecht. Beispiel: es gibt keine DELETE-Policy auf termine, also
-- auch kein DELETE-Recht -- selbst ein Bug in einer kuenftigen Policy
-- koennte dann keine Termine loeschen.
--
-- WICHTIG zur Admin-Rolle: "Admin" ist KEINE eigene Datenbankrolle. Die
-- Admin meldet sich ganz normal an und ist damit ebenfalls die Rolle
-- "authenticated" -- ihre Sonderrechte kommen allein aus public.is_admin()
-- in den Policies. Deshalb braucht "authenticated" hier auch die
-- schreibenden Rechte auf dienstleistungen, oeffnungszeiten und
-- sperrzeiten: ohne sie koennte die Admin nichts pflegen, obwohl ihre
-- Policies es erlauben. Fuer normale Kundinnen bleibt das folgenlos,
-- sie scheitern an der RLS-Bedingung is_admin().

-- ============================================================
-- profiles -- eigene Kontaktdaten
-- Kein DELETE: Profile werden nicht geloescht, sie haengen per
-- "on delete cascade" am auth.users-Eintrag.
-- ============================================================
grant select, insert, update on public.profiles to authenticated;

-- ============================================================
-- dienstleistungen -- oeffentlich lesbar, Admin pflegt
-- ============================================================
grant select                          on public.dienstleistungen to anon;
grant select, insert, update, delete  on public.dienstleistungen to authenticated;

-- ============================================================
-- oeffnungszeiten -- oeffentlich lesbar, Admin aendert
-- Kein INSERT/DELETE: die 7 Wochentags-Zeilen entstehen einmalig per
-- Seed und es kommen nie neue dazu (siehe docs/decisions.md).
-- ============================================================
grant select          on public.oeffnungszeiten to anon;
grant select, update  on public.oeffnungszeiten to authenticated;

-- ============================================================
-- sperrzeiten -- oeffentlich lesbar, Admin pflegt
-- ============================================================
grant select                          on public.sperrzeiten to anon;
grant select, insert, update, delete  on public.sperrzeiten to authenticated;

-- ============================================================
-- termine -- nur fuer angemeldete Kundinnen
-- Kein Recht fuer anon: ohne Login gibt es keinen Zugriff auf Buchungen,
-- auch nicht lesend.
-- Kein DELETE: stornieren heisst status = 'storniert', nicht loeschen --
-- die Historie bleibt erhalten.
-- ============================================================
grant select, insert, update on public.termine to authenticated;

-- ============================================================
-- Keine Sequenz-Rechte noetig: alle Primaerschluessel sind uuid mit
-- gen_random_uuid() als Default, es gibt keine serial/identity-Spalten
-- und damit keine Sequenzen, die eigene Rechte braeuchten.
-- ============================================================
