# Testna nadgradnja hrambe prebranih obvestil — 11. oktober 2026

Lokalno pripravljen in preverjen pomočnik cilja samo **jivie-test.triparna.si**,
obstoječo bazo `tripar13_jivietest` in **FamilyHub 0.11.1/schema15 →
0.11.2/schema15**. Zamenja kodo brez DDL, migracije ali zapisovanja nastavitev.
Aktivacija ne zažene čiščenja. Po odprtju obstoječi cron opomnikov omejeno
odstranjuje obvestila, pri katerih je od prvega `read_at` minilo sedem dni;
`unread` prekliče rok. Podrobnosti pogodbe so v
[izvedbenem dnevniku](../INBOX_READ_STATE_AND_RETENTION.md).
Dejanska kopija, obnova in namestitev potrebujejo ločene dokaze.

## Zamrznjeni paketi

- `build/release/FamilyHub-0.11.2-retention-source.zip`: **83 datotek, 76 PHP**;
  SHA256 `8108791ef3c5dd39f295395b1a5c5164ba58c2f21bc5c36722b0fe7244d857b4`.
- `build/release/Jivie-inbox-retention-upgrade-helpers.zip`: PHP, shell ovoj,
  pregledovalnik in `manifest.json`; SHA256
  `13cb0790f2de102b399a7aa4c769fa875fd63b3f2563e147facb44942127684e`.
- Lokalni manifest: `build/release/jivie-inbox-retention-upgrade-manifest.json`.

Pomočnik ima pripet hash izvornega ZIP, preveri vse poti, vrste vnosov, CRC,
vse hashe ter dejanski PHP tokenizer. Točen izvor 0.11.1 in schema15 sta
obvezna. Stari pomočniki 0.11.0/0.11.1 so zgodovinski in niso spremenjeni.
Novi samostojni pomočnik ohrani njihove pregledane generične rutine, uporablja
novo mapo, nov paket in nova patch varovala. Produkcije ne cilja.

## Priprava in zaustavitev testnega okolja

Ustvari **novo** zasebno mapo `/home/tripar13/private/jivie-test/upgrade-0.11.2`
z dovoljenji 0700. Prenesi oba ZIP, primerjaj zgornja SHA256 in razširi samo
pomočnike v to mapo. Datoteke naj imajo 0600. Izvornega ZIP ne razširjaj ročno
v aktivno mapo vtičnika. Ne uporabljaj starega dokazila o obnovi.

```sh
curl --fail --silent --show-error --header 'Content-Type: application/json' --data '{"v":1,"op":"capabilities","params":{}}' 'https://jivie-test.triparna.si/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub' > /home/tripar13/private/jivie-test/upgrade-0.11.2/before-capabilities.json
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh prepare
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh pause
```

Priprava ohrani spletno aplikacijo. Zaustavitev ustavi samo pet testnih delavcev,
ohrani izvirni celotni cron ter preveri javni HTTPS 503. Po najmanj **65 sekundah**:

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh snapshot
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh bundle-backup
```

Zajem zahteva svež pregled brez aktivnih testnih PHP procesov, READ zaklepe vseh
InnoDB tabel in nespremenjeno kodo/konfiguracijo. Kopija vsebuje SQL, celotno
zasebno drevo, star vtičnik, konfiguracijo, originalni cron in `.htaccess`.
Sedanjo delovno mapo izključi iz zasebnega drevesa; stare kopije ohrani.

## Obvezna nova izolirana obnova

Prenesi novi `Jivie-private-upgrade-backup.zip` in `.sha256` v **novo** lokalno
zasebno mapo `/Users/anzenovsak/.local/share/jivie/backups/inbox-retention-20261011/`
(0700, datoteke 0600) ter primerjaj lokalni in strežniški hash. Obnovo izvedi
na potrjeni **MariaDB 10.11.19**, brez omrežja ali odprtih vrat:

```sh
docker run --name jivie-inbox-retention-restore-20261011 --network none -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 -d mariadb:10.11.19
docker exec jivie-inbox-retention-restore-20261011 healthcheck.sh --connect --innodb_initialized
python3 server/scripts/verify-cpanel-jivie-backup.py /Users/anzenovsak/.local/share/jivie/backups/inbox-retention-20261011/Jivie-private-upgrade-backup.zip --container jivie-inbox-retention-restore-20261011
```

Preverjalnik zahteva nov prazen cilj in preveri vse tabele/stolpce/vrstice,
serverId, račune/gesla/enrollment ter vsak hash zasebne datoteke. Aplikacije in
delavcev ne zažene. Vrni novi `restore-proof.json` v trenutno strežniško
`upgrade-0.11.2` mapo, neskrivni `restore-evidence.json` zabeleži med izdajne
dokaze. Ustavi samo novi vsebnik za to obnovo.

## Aktivacija, odprtje in povrnitev

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh activate
sh /home/tripar13/private/jivie-test/upgrade-0.11.2/upgrade-cpanel-jivie-inbox-retention.sh release
```

Aktivacija zahteva popolno ujemanje svežega dokaza obnove, SQL in zasebnih
hashov. Pred/po zamenjavi ter pred odprtjem primerja vse vrstice, celotne
stolpce/indekse in vse `plugin_schema_versions` vrstice. Ne kliče migracije ali
obvestilnega čiščenja. `release` bajtno vrne originalni cron in `.htaccess`.

Pred zamenjavo uporabi `abort-before-activation`. Po zamenjavi, še pod
vzdrževanjem, `rollback-code` vrne samo prvotno 0.11.1 kodo ob nespremenjeni
bazi, zasebnih datotekah, konfiguraciji in zaustavljenem cronu. Nato
`abort-before-activation` obnovi originalni cron in odpre stran. Po `release`
ali poznejših zapisih se povrnitev ustavi. `capture-recovery` ohrani trenutno
stanje za izrecno popravilo; pomočnik ne vrača starega SQL čez nove podatke.

## Pregled po odprtju — samo branje

Paket že vsebuje `verify-cpanel-jivie-inbox-retention.php`:

```sh
/bin/crontab -l | /opt/alt/php84/usr/bin/php /home/tripar13/private/jivie-test/upgrade-0.11.2/verify-cpanel-jivie-inbox-retention.php
```

Pregledovalnik ne piše datotek, ne kliče `common.php` in ne zaganja delavcev.
Preveri aktivni manifest, 0.11.2/schema15, identitete/gesla/enrollment,
konfiguracijo, originalni cron in `.htaccess` ter varovani posnetek ob
aktivaciji. Dejanske čiste preference in cutoff/unread funkcije preveri brez
vpisov. V poročilu navede sedemdnevno pogodbo ter loči ohranitev ob aktivaciji
od dovoljenih poznejših zapisov.

Počakaj na redni cron vseh petih delavcev: `updatedAfterRelease=true`,
`expectedStatusShape=true`, `validJson=true`, `mode=600`, svež čas. Opomniki
morajo poleg starih števcev vrniti tudi nenegativen celoštevilski
`readNotificationsDeleted`. Pregled tega števca ne zažene čiščenja; vrednost 0
ne dokazuje fizične dostave push. Javna različica, prijava in fizični Android
preizkus imajo ločena potrdila.

## Lokalna preverjanja

- `server/tests/upgrade-inbox-retention-helper-test.php`: **34 PASS**,
  filesystem/ZIP/izolirani dokaz obnove, `familyhub-fcm-setup-test`, brez omrežja.
- `server/tests/upgrade-inbox-retention-helper-db-test.php`: **22 PASS**,
  začasni unikatni bazi na lokalni MariaDB 10.11.19, dejanska SQL obnova,
  definicije/gesla/politike in varovanje povrnitve kode.
- `tools/plugin_release/test_package_source.py`: **10 PASS**.
- PHP lint novih pomočnikov/pregledovalnika/testov in `sh -n`: PASS.

To potrjuje lokalne pomočnike in paket. Ne potrjuje žive namestitve, obnove
dejanske kopije ali delovanja uporabnikove naprave.
