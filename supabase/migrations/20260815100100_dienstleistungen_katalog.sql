-- Echter Behandlungskatalog (42 Eintraege) aus dienstleistungen.csv.
-- Ersetzt die von Hand angelegten Testeintraege.
--
-- ACHTUNG Reihenfolge: erst 20260815100000_dienstleistungen_preis_ab.sql.
--
-- Das DELETE scheitert, sobald ein Eintrag von einem Termin referenziert wird
-- (Fremdschluessel termine.dienstleistung_id, ohne on delete). Das ist Absicht:
-- die Migration laeuft in einer Transaktion, bricht sauber ab und aendert nichts.
-- Dann entweder die Testtermine loeschen oder auf aktiv = false umstellen statt
-- zu loeschen.
--
-- Preise als ganze Rappen (18900 = CHF 189.00).
-- preis_ab = true nur bei den Wimpernverlaengerungen; die drei Beratungen sind
-- kostenlos (preis_rappen = 0), dort waere "ab CHF 0.00" sinnlos.
--
-- Die Dauern stammen NICHT aus dem CSV (dort war die Spalte bis auf zwei Zeilen
-- leer), sondern sind branchenuebliche Schaetzwerte zum Gegenlesen.
-- Uebersicht: docs/dienstleistungen-dauern.md

delete from public.dienstleistungen;

insert into public.dienstleistungen (name, kategorie, dauer_minuten, preis_rappen, preis_ab) values
  -- Tattoo-Entfernung
  ('Beratungsgespräch Tattooentfernen/PMU/Microblading', 'tattoo_entfernung',  30,      0, false),
  ('Augenbrauen / PMU / Microblading',                   'tattoo_entfernung',  30,  18900, false),
  ('Grösse XS (1 x 5cm)',                                'tattoo_entfernung',  30,  18000, false),
  ('Grösse S (5 x 10cm)',                                'tattoo_entfernung',  30,  26000, false),
  ('Grösse M (10x10)',                                   'tattoo_entfernung',  45,  42000, false),
  ('Grösse XL (15 x 15)',                                'tattoo_entfernung',  60,  65000, false),

  -- Laser / dauerhafte Haarentfernung
  ('Beratungsgespräch dauerhafte Haarentfernung',        'laser',              30,      0, false),
  ('Primelase 3 Zonen',                                  'laser',              45,  11900, false),
  ('Primelase 5 Zonen',                                  'laser',              75,  17900, false),
  ('Primelase Ganzkörper (Kopf-Fuss)',                   'laser',              90,  24900, false),
  ('4 Zonen',                                            'laser',              60,  14900, false),
  ('2 Zonen',                                            'laser',              30,   8000, false),
  ('Gesicht',                                            'laser',              30,   4900, false),
  ('Kinn',                                               'laser',              15,   2500, false),
  ('Oberlippe',                                          'laser',              15,   2500, false),
  ('Achseln',                                            'laser',              15,   4500, false),
  ('Oberarm',                                            'laser',              30,   4500, false),
  ('Unterarm',                                           'laser',              30,   4500, false),
  ('Arme komplett',                                      'laser',              45,   7900, false),
  ('Oberschenkel',                                       'laser',              45,   7900, false),
  ('Unterschenkel',                                      'laser',              45,   7900, false),
  ('Beine komplett',                                     'laser',              60,   8900, false),
  ('Bauch',                                              'laser',              30,   4500, false),
  ('Intimzone',                                          'laser',              30,   5900, false),
  ('Bikinizone',                                         'laser',              30,   4500, false),
  ('Hände',                                              'laser',              15,   2900, false),
  ('Rücken',                                             'laser',              45,   6900, false),
  ('Brust',                                              'laser',              30,   3900, false),
  ('Gesäss',                                             'laser',              30,   4900, false),
  ('Füsse',                                              'laser',              15,   2900, false),

  -- Kosmetik
  ('2D Lashes',                                          'kosmetik',          120,   7500, true),
  ('3D Lashes',                                          'kosmetik',          120,   7500, true),
  ('5D Lashes',                                          'kosmetik',          135,   7900, true),
  ('7D Lashes',                                          'kosmetik',          150,   8900, true),
  ('Wimpern entfernen',                                  'kosmetik',           30,   2000, false),
  ('Wimpern Lifting ohne Färben',                        'kosmetik',           60,   6000, false),
  ('Wimpern Lifting mit Färben',                         'kosmetik',           75,   7000, false),
  ('Korean Lash Lift',                                   'kosmetik',           75,   8000, false),
  ('Augenbrauen Lifting',                                'kosmetik',           60,   6000, false),
  ('Carbon Peeling',                                     'kosmetik',           60,  13900, false),
  ('Algen Peeling',                                      'kosmetik',           90,  24900, false),
  ('Beratungsgespräch Gesicht',                          'kosmetik',           30,      0, false);
