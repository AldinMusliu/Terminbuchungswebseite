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

## Soft-Delete bei Dienstleistungen (`aktiv`-Flag statt Löschen)

**Entscheidung:** Dienstleistungen werden über `aktiv = false` deaktiviert statt gelöscht.

**Warum:** `termine.dienstleistung_id` referenziert die Dienstleistung per Fremdschlüssel.
Ein echtes Löschen würde entweder fehlschlagen (Fremdschlüssel-Konflikt) oder die Historie
alter Buchungen zerstören.
