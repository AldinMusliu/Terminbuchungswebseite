# Architektur-Entscheidungen

## Rollen (Kundin/Admin) im `app_metadata`, nicht in einer Tabellenspalte

**Entscheidung:** Die Rolle wird nicht als Spalte in `profiles` gespeichert, sondern im `app_metadata`
des Supabase-Auth-Users (`auth.users.raw_app_meta_data`).

**Warum:** `app_metadata` kann ausschließlich mit dem geheimen `service_role`-Key geändert werden —
niemals über die normale Frontend-Verbindung (anon/publishable Key). Eine Rollen-Spalte in einer
normalen Tabelle wäre dagegen potenziell durch eine fehlerhafte RLS-Policy oder einen Bug
selbst editierbar (Privilege Escalation: Kundin setzt sich selbst auf "admin"). Bei nur einer
Admin-Person (Mutter) ist der einmalige manuelle Schritt im Supabase-Dashboard kein Mehraufwand.

**Wie geprüft:** In RLS-Policies über `(auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'`.
Bewusst **nicht** `user_metadata`, da dieses vom Nutzer selbst über die Auth-API änderbar ist.

## Registrierungspflicht vor Buchung

**Entscheidung:** Kein anonymes Buchungsformular — Login ist Voraussetzung fürs Buchen.

**Warum:** Reduziert Spam/Missbrauch und macht RLS-Policies robust, da jede Buchung an eine
echte `auth.uid()` gebunden ist (`kundin_id = auth.uid()` statt Freitext-Kontaktdaten prüfen zu müssen).

## Doppelbuchungsschutz per DB-Constraint (Exclusion Constraint)

**Entscheidung:** Überschneidende Termine werden über einen `EXCLUDE USING gist`-Constraint auf
`termine` verhindert, nicht nur durch eine Prüfung im Frontend/Backend-Code.

**Warum:** Ein Frontend-Check kann durch Race Conditions umgangen werden (zwei Buchungen fast
gleichzeitig). Der Datenbank-Constraint lehnt eine kollidierende Buchung unabhängig vom Zeitpunkt
zuverlässig ab — die einzige Stelle, an der das garantiert werden kann.

## Öffnungszeiten als eigene Tabelle (`oeffnungszeiten`), nicht im Code

**Entscheidung:** Öffnungszeiten pro Wochentag liegen in einer eigenen Tabelle
(`oeffnungszeiten`, eine Zeile pro Wochentag), nicht als Konstante im Code.

**Warum:** Deine Mutter soll Öffnungszeiten selbst über die Admin-Oberfläche anpassen können
(früher öffnen, einen Tag dazunehmen), ohne dass dafür Code geändert und neu deployt werden
muss — das war von Anfang an eine bewusste Anforderung (keine hartcodierten Zeiten).

**Warum eine Zeile pro Wochentag statt einer einzelnen "Singleton"-Konfigurationszeile:**
Eine Singleton-Tabelle (eine Zeile, viele Spalten wie `mo_start`, `di_start`, ...) wäre nötig,
wenn es sich um *eine* globale Einstellung handeln würde. Hier gibt es aber 7 unabhängige
Werte (pro Wochentag geöffnet ja/nein + Start/Ende) — als 7 Zeilen mit `wochentag` als
Primärschlüssel ist das normalisiert, jede Zeile einzeln update-bar, und es braucht keinen
Singleton-Constraint-Trick (z.B. `check (id = 1)`), weil `wochentag` selbst schon eindeutig ist.
INSERT/DELETE sind für niemanden freigegeben, da die 7 Zeilen einmalig per Seed-Daten entstehen
und nie neue Wochentage dazukommen — nur `UPDATE` ist relevant.

## Sperrzeiten statt Verfügbarkeiten (Opt-out statt Opt-in)

**Entscheidung:** Innerhalb der in `oeffnungszeiten` hinterlegten Zeiten ist standardmäßig
alles buchbar. Die Admin pflegt eine separate `sperrzeiten`-Tabelle, in der sie gezielt
einzelne Zeiträume blockiert (Pause, Urlaub, privater Termin) — analog zu Google Calendar, wo
man freie Zeit nicht extra freigibt, sondern nur Ausnahmen einträgt.

**Warum:** Ursprünglich war ein Opt-in-Modell geplant (Admin gibt jedes Zeitfenster einzeln
frei). In der Praxis arbeitet die Admin aber wie mit einem normalen Kalender: an nahezu jedem
Öffnungstag ist gebucht werden, Ausnahmen sind die Minderheit. Opt-out spart ihr täglich
wiederkehrende Pflege und bildet den echten Arbeitsablauf besser ab. Ein Wechsel auf
wiederkehrende Regeln (z.B. "jeden Montag Pause 12–13 Uhr") ist später möglich, ohne das
Grundschema zu brechen.

## Admin hat Vollzugriff auf `termine`, Kundin nur eingeschränkt

**Entscheidung:** Die Admin darf jeden Termin für jede registrierte Kundin anlegen, verschieben
und bearbeiten (SELECT/INSERT/UPDATE ohne Einschränkung auf `kundin_id`). Kundinnen dürfen
weiterhin nur eigene Termine sehen, anlegen und stornieren.

**Warum:** Deine Mutter soll Termine wie in einem gewohnten Kalender direkt selbst eintragen
und bei Bedarf frei verschieben können (z.B. nach einem Telefonanruf), nicht nur eigene
Buchungen bestätigen. Der Doppelbuchungsschutz (Exclusion Constraint) gilt unabhängig von der
Rolle für jeden INSERT/UPDATE — die Admin kann also auch versehentlich keine Kollision anlegen.
Buchungen bleiben trotzdem an registrierte Kundinnen-Konten gebunden (kein Gast-Freitextfeld),
damit RLS und Datenmodell konsistent bleiben.

## Tabellen-Rechte (GRANT) werden explizit gesetzt, nicht vererbt

**Entscheidung:** Jede Tabelle bekommt in der Migration explizite `GRANT`-Statements für
`anon` und `authenticated`, statt sich auf die *default privileges* der Supabase-Instanz zu
verlassen. Umgesetzt in `supabase/migrations/20260814120000_grants_fix.sql`.

> **Zur Entstehung:** Diese Migration entstand aus der Vermutung, fehlende GRANTs seien
> die Ursache eines `permission denied for table termine`. Das war eine Fehldiagnose — die
> Rechte waren bereits korrekt gesetzt, der Fehler kam vom Test-Browser (siehe
> `docs/troubleshooting.md`). Die Migration ist damit faktisch ein No-op. Sie bleibt
> trotzdem, weil explizite Rechte der vererbten Automatik vorzuziehen sind: sie stehen
> versioniert neben den Policies und sind bei einem Neuaufsetzen der Datenbank reproduzierbar.
> Der Dateiname `grants_fix` ist im Nachhinein irreführend.

**Warum:** Zugriff in Postgres hat **zwei unabhängige Schichten**, und RLS ist nur die zweite:

| Schicht | Frage | Geregelt durch |
|---|---|---|
| 1. GRANT | Darf die Rolle die Tabelle überhaupt anfassen? | `grant … on … to …` |
| 2. RLS | Welche *Zeilen* darf sie dabei sehen/ändern? | `create policy …` |

Fehlt Schicht 1, kommt Postgres bei RLS gar nicht erst an: die Abfrage scheitert mit
`permission denied for table …`, egal wie korrekt die Policy formuliert ist. Das ist eine
verwirrende Fehlerquelle, weil man den Fehler instinktiv bei der Policy sucht — dort ist er
aber nie. Umgekehrt gilt: ein GRANT allein öffnet nichts, solange RLS aktiv ist und keine
Policy passt. Beide Schichten müssen stimmen.

**Merksatz für neue Tabellen:** RLS aktivieren, Policies schreiben, **und** die GRANTs setzen.
Alle drei gehören in dieselbe Migration.

**Wie man den echten Zustand prüft:** `information_schema.role_table_grants` ist dafür
irreführend — die View zeigt nur Zeilen, bei denen die abfragende Rolle selbst Grantor oder
Grantee ist. Rechte für `anon`/`authenticated` fehlen dort oft in der Anzeige, obwohl sie
existieren. Verlässlich ist `has_table_privilege()`:

```sql
select t.table_name,
       has_table_privilege('authenticated', 'public.'||t.table_name, 'select') as sel,
       has_table_privilege('anon',          'public.'||t.table_name, 'select') as anon_sel
from information_schema.tables t
where t.table_schema = 'public' and t.table_type = 'BASE TABLE';
```

**Kein `grant all`:** Vergeben wird nur, was auch eine Policy erlaubt — `termine` bekommt z.B.
kein DELETE, weil Stornieren ein Status-Update ist und die Historie erhalten bleiben soll. So
könnte selbst ein Fehler in einer künftigen Policy keine Termine löschen: das Tabellenrecht
fehlt schlicht.

**Zur Admin-Rolle:** "Admin" ist keine eigene Datenbankrolle. Die Admin meldet sich normal an
und ist damit ebenfalls `authenticated`; ihre Sonderrechte kommen allein aus `is_admin()` in
den Policies. Deshalb braucht `authenticated` auch die schreibenden Rechte auf
`dienstleistungen`, `oeffnungszeiten` und `sperrzeiten` — für normale Kundinnen bleibt das
folgenlos, sie scheitern an der RLS-Bedingung.

## Verfügbarkeits-Berechnung als Datenbank-Funktion, nicht im Frontend

**Entscheidung:** Freie Termin-Slots werden von der Postgres-Funktion
`public.freie_slots(datum, dienstleistung_id)` berechnet und per RPC aufgerufen,
nicht im JavaScript des Frontends.

**Warum:** Die RLS-Policy `termine_select_own` lässt eine Kundin ausschliesslich ihre
**eigenen** Termine sehen. Freie Slots zu berechnen setzt aber voraus, alle bestätigten
Termine zu kennen. Im Frontend wäre das nur möglich, indem man `termine` für alle lesbar
macht — womit offengelegt wäre, wer wann einen Termin hat. Die Berechnung in der Datenbank
löst beides: sie sieht alle Termine, gibt aber ausschliesslich freie Startzeiten zurück,
nie Namen, IDs oder sonstige Termindaten. Zusätzlich gibt es damit nur eine einzige Quelle
der Wahrheit statt einer Logik, die in Kundenansicht und Adminansicht getrennt gepflegt
werden müsste.

**Wie abgesichert:** `security definer` (umgeht RLS kontrolliert) zusammen mit
`set search_path = ''` — ohne das könnte ein manipulierter `search_path` eigenen Code mit
den Rechten des Function-Owners ausführen. Ausführungsrecht ist explizit auf `anon` und
`authenticated` gesetzt statt auf dem Postgres-Standard `PUBLIC` zu bleiben.

**Bewusst in Kauf genommen:** Aus den freien Zeiten lässt sich ablesen, *dass* eine Zeit
belegt ist — nicht aber von wem oder womit. Das ist jedem Buchungssystem inhärent: eine
Terminauswahl, die nicht verrät was frei ist, wäre keine.

## 15-Minuten-Raster für Termin-Startzeiten

**Entscheidung:** Termine können alle 15 Minuten starten. Das Raster gilt nur für die
**Startzeit** — das Ende ergibt sich aus `dauer_minuten` und darf krumm fallen.

**Warum:** `dauer_minuten` ist pro Dienstleistung frei wählbar, es gibt bewusst kein festes
30/60-Schema. Bei einem 30-Minuten-Raster entstünden zwischen unterschiedlich langen
Behandlungen regelmässig Lücken, die zu kurz zum Buchen und damit verschenkt sind. 15 Minuten
verschneiden deutlich weniger Zeit. Der Preis dafür sind mehr Buttons in der Slot-Auswahl —
ein reines UI-Thema, das sich in der Darstellung lösen lässt, während verlorene Arbeitszeit
sich nicht zurückholen lässt.

## Soft-Delete bei Dienstleistungen (`aktiv`-Flag statt Löschen)

**Entscheidung:** Dienstleistungen werden über `aktiv = false` deaktiviert statt gelöscht.

**Warum:** `termine.dienstleistung_id` referenziert die Dienstleistung per Fremdschlüssel.
Ein echtes Löschen würde entweder fehlschlagen (Fremdschlüssel-Konflikt) oder die Historie
alter Buchungen zerstören.
