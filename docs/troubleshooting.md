# Troubleshooting-Protokoll

Fehlerbilder, die schon einmal Zeit gekostet haben — inklusive der Sackgassen.
Die falschen Fährten stehen bewusst mit drin: sie sind der eigentliche Wert, weil
dasselbe Symptom sonst beim nächsten Mal wieder in dieselbe Richtung führt.

---

## `permission denied for table termine` nach dem Login

**Datum:** 14.08.2026 · **Fix:** kein Code-Fix nötig

### Symptom

Nach erfolgreichem Login zeigte `MeineTermine` den Fehler
`permission denied for table termine`. Zusätzlich blieb `public.profiles` leer,
obwohl der Login durchlief — `ensureProfile` legte also keine Zeile an.

### Erste Vermutung (falsch): fehlende GRANT-Rechte

Naheliegend, weil `permission denied` in Postgres genau auf die GRANT-Schicht
zeigt und nicht auf RLS. Eine Prüfung über `information_schema.role_table_grants`
schien das zu bestätigen: für `authenticated` erschienen dort nur
`TRIGGER`/`REFERENCES`/`TRUNCATE`, kein SELECT/INSERT/UPDATE.

**Diese View ist für die Frage aber ungeeignet.** Sie zeigt nur Zeilen, bei denen
die abfragende Rolle selbst Grantor oder Grantee ist, und unterschlägt dadurch
Rechte anderer Grantees. Verlässlich ist `has_table_privilege()`:

```sql
select t.table_name,
       has_table_privilege('authenticated', 'public.'||t.table_name, 'select') as sel,
       has_table_privilege('authenticated', 'public.'||t.table_name, 'insert') as ins,
       has_table_privilege('authenticated', 'public.'||t.table_name, 'update') as upd,
       has_table_privilege('anon',          'public.'||t.table_name, 'select') as anon_sel
from information_schema.tables t
where t.table_schema = 'public' and t.table_type = 'BASE TABLE';
```

Ergebnis: **alle Rechte waren korrekt gesetzt.** Die GRANT-Theorie war ein
Fehlalarm.

### Tatsächliche Ursache: der Test-Browser

Getestet wurde im **in VS Code eingebauten Browser-Tab (Simple Browser)**. Nach
Wechsel auf einen normalen Browser (Edge) funktionierten Login und
Profilerstellung sofort einwandfrei, der Fehler trat dort nicht auf.

Naheliegende Erklärung: der eingebaute Browser behandelt Session-/Token-Speicherung
anders, wodurch der Supabase-Auth-Token nicht mitgeschickt wurde und Anfragen
effektiv als `anon` statt `authenticated` liefen. `anon` hat auf `termine` bewusst
keinerlei Zugriff (private Daten) — daher exakt dieses `permission denied`.

**Wichtig:** Der genaue Mechanismus ist *nicht* im Detail verifiziert. Belegt ist
nur, dass der Browser-Wechsel das Problem zuverlässig behebt.

### Warum das Symptom so gut zur falschen Fährte passte

`permission denied for table termine` ist die *korrekte* und erwartete Antwort für
eine `anon`-Anfrage auf `termine`. Die Datenbank hat sich also richtig verhalten —
falsch war nur die Annahme, die Anfrage käme von einer angemeldeten Kundin. Genau
deshalb führte die Fehlersuche in die Datenbank statt in den Client.

### Lehre

- Bei Auth-/Session-Fehlern **zuerst prüfen, in welchem Browser-Kontext getestet
  wird.** Der VS-Code-interne Browser eignet sich nicht zuverlässig zum Testen von
  Login-Flows.
- `permission denied` heisst nicht automatisch "Rechte fehlen" — es kann auch
  heissen "die Anfrage kam mit der falschen Rolle an". Vor dem Ändern von Rechten
  klären, **als wer** die Anfrage überhaupt ankommt.
- Für Rechteprüfungen `has_table_privilege()` verwenden, nicht
  `information_schema.role_table_grants`.

### Bleibendes Artefakt

`supabase/migrations/20260814120000_grants_fix.sql` ist im Zuge dieser falschen
Vermutung entstanden. Die Migration bleibt im Repo: sie ist ein No-op, da die
Rechte bereits existierten, schadet also nicht — und sie setzt die GRANTs nun
explizit statt sie von den Supabase-Default-Privileges zu erben, was für künftige
Tabellen ohnehin die sauberere Praxis ist. Der Dateiname `grants_fix` ist im
Nachhinein irreführend; umbenannt wird er trotzdem nicht, weil ausgeführte
Migrationen nicht nachträglich verändert werden.
