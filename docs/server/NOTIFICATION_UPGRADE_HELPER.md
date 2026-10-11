# Testna nadgradnja obvestil — 11. oktober 2026

Lokalno pripravljen pomočnik za **jivie-test.triparna.si**, obstoječo bazo
`tripar13_jivietest`, **FamilyHub 0.11.0/schema15 → 0.11.1/schema15**.
To je zamenjava kode brez DDL ali zapisovanja nastavitev. Dejanske kopije, obnove
in aktivacije imajo ločene dokaze v `CPANEL_SETUP.md`.

## Pregledani paketi

- `build/release/FamilyHub-0.11.1-notifications-source.zip`: **81 datotek, 74 PHP**;
  SHA256 `630b22150b4ed090110b39804cdbf64672bcdbb8cf5964cf2a66c1db3e96befe`.
- `build/release/Jivie-notifications-upgrade-helpers.zip`: PHP, shell ovoj in
  `manifest.json`; SHA256
  `b5f7bf7bdf0bea8d16620b83d1f31d4e7a2f3ec224218ab1a948a6a980e39a78`.
- Lokalni manifest: `build/release/jivie-notifications-upgrade-manifest.json`.

ZIP vsebuje pregledane vire in javne pogodbe, brez konfiguracije, Git zgodovine
ali uporabniških podatkov. Pomočnik ima pripet hash paketa, preveri poti, vrste
vnosov, CRC, vse datotečne hashe in dejanski PHP tokenizer pred odložitvijo kode.
Privzete push/inApp nastavitve se računajo ob odsotnem zapisu; obstoječih
izrecnih nastavitev se ne spreminja. Napravnih registracij, dovoljenj ali starih
obvestil nadgradnja ne ustvari.

## Zaporedje na testnem cPanelu

Ustvari **novo** zasebno mapo
`/home/tripar13/private/jivie-test/upgrade-0.11.1` (0700), prenesi oba paketa,
primerjaj oba SHA256 in razširi samo pomočnike. Datoteke naj imajo 0600.
Prejšnjega migracijskega pomočnika iz 0.11.0 ne uporabljaj za ta korak.

```sh
curl --fail --silent --show-error --header 'Content-Type: application/json' --data '{"v":1,"op":"capabilities","params":{}}' 'https://jivie-test.triparna.si/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub' > /home/tripar13/private/jivie-test/upgrade-0.11.1/before-capabilities.json
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh prepare
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh pause
```

`prepare` preveri točno izvorno 0.11.0 in schema15, pripravi kodo ter kandidat
crona; aplikacije ne spremeni. `pause` ustavi samo pet testnih delavcev, ohrani
celoten originalni cron in preveri javni HTTPS 503. Po najmanj **65 sekundah**:

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh snapshot
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh bundle-backup
```

Zajem zahteva svež pregled brez aktivnih testnih PHP procesov, READ zaklepe vseh
InnoDB tabel ter nespremenjeno kodo/konfiguracijo. Kopija vsebuje SQL, celotno
zasebno drevo (vključno s prejšnjimi kopijami, brez trenutne delovne mape), stari
vtičnik, konfiguracijo, originalni cron in `.htaccess`.

## Obvezna sveža izolirana obnova

Prenesi **nov** `Jivie-private-upgrade-backup.zip` in `.sha256` v novo mapo
`/Users/anzenovsak/.local/share/jivie/backups/notifications-20261011/` (0700,
datoteke 0600). Primerjaj lokalni/oddaljeni hash. Stari dokaz obnove ni veljaven.
Ustvari nov vsebnik, brez omrežja in vrat:

```sh
docker run --name jivie-notifications-restore-20261011 --network none -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 -d mariadb:10.11.19
```

Po uspešnem `healthcheck.sh --connect --innodb_initialized`:

```sh
python3 server/scripts/verify-cpanel-jivie-backup.py /Users/anzenovsak/.local/share/jivie/backups/notifications-20261011/Jivie-private-upgrade-backup.zip --container jivie-notifications-restore-20261011
```

Preverjalnik zahteva nov prazen cilj. Preveri vse tabele, stolpce in vrstice,
identiteto, račune/gesla/enrollment ter vsak hash zasebne datoteke; ne zaganja
aplikacije ali delavcev. Vrni `restore-proof.json` v trenutno strežniško delovno
mapo, neskrivni `restore-evidence.json` zabeleži v dokaze. Ustavi samo ta vsebnik.

## Aktivacija in povrnitev

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh activate
sh /home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.sh release
```

Aktivacija zahteva ujemanje novega dokaza obnove ter nespremenjen SQL/zasebne
hashe. Pred in po zamenjavi ter pred odprtjem primerja **celotni posnetek vseh
vrstic**, vse definicije stolpcev in indeksov ter vse vrstice
`plugin_schema_versions` (vključno s FamilyHub). Ne kliče migracije in ne piše v
bazo. Konfiguracija in identitete ostanejo enake. `release` bajtno vrne originalni
cron in `.htaccess`. Javna različica 0.11.1/schema15, isti serverId, prijava in
stanje delavcev potrebujejo dejanski zunanji pregled; lokalni testi tega ne
potrjujejo.

Pred zamenjavo je na voljo `abort-before-activation`. Po zamenjavi, **še pod
vzdrževanjem**, `rollback-code` vrne samo originalno 0.11.0 kodo. Zahteva
nespremenjeno bazo, shemo, zasebne datoteke, oba drevesa kode, konfiguracijo in
zaustavljeni cron. Nato `abort-before-activation` vrne originalni cron in odpre
stran. Po `release` ali poznejših zapisih se pomočnik za povrnitev ustavi; ne
vrača starega SQL čez nove podatke. `capture-recovery` ohrani trenutno stanje za
izrecno popravilo.

## Lokalna preverjanja

- `server/tests/upgrade-notifications-helper-test.php`: **34 PASS**, sintetičen
  filesystem/ZIP/dokaz obnove, image `familyhub-fcm-setup-test`, `network=none`.
- `server/tests/upgrade-notifications-helper-db-test.php`: **22 PASS**, ločeni
  začasni bazi v lokalni MariaDB 10.11.19; dejanska SQL obnova, natančne definicije,
  varovanje gesel/politik/tabel/stolpcev/indeksov ter povrnitev kode.
- `tools/plugin_release/test_package_source.py`: **10 PASS**.
- PHP lint pomočnika/testov ter `sh -n`: PASS.

Pomočnik namenoma ohrani samostojne zamrznjene generične rutine pregledanega
sharing pomočnika. Njegove zgodovinske fiksne poti, pripet ZIP in migracija
ostanejo nespremenjeni; novi pomočnik uvaja samo patch varovala in novo ciljno
mapo/paket.

## Pregled po odprtju (samo branje)

`server/scripts/verify-cpanel-jivie-notifications.php` prenesi kot
`verify-hosted.php` v trenutno zasebno delovno mapo. Pomočnik ne piše datotek,
ne kliče `common.php` in ne zaganja delavcev. Za svež dokaz crona:

```sh
/bin/crontab -l | /opt/alt/php84/usr/bin/php /home/tripar13/private/jivie-test/upgrade-0.11.1/verify-hosted.php
```

JSON preveri izvorni manifest, 0.11.1/schema15, konfiguracijo, originalni cron,
`.htaccess`, identiteto/gesla/enrollment, vse definicije stolpcev/indeksov in
zapisani nespremenjeni posnetek ob aktivaciji. Naloži samo osnovne razrede ter
čisto dejansko `NativeNotificationPreferences::resolve`; potrdi vseh šest
kategorij in privzete vrednosti. Vse obstoječe shranjene nastavitve prebere brez
razkritja vsebine in preveri prednost izrecnih vrednosti, tudi izklopov.
Poroča ujemanje trenutnih preference vrstic s kopijo; poznejše dovoljene zapise
loči od dokazila o ohranitvi ob aktivaciji.

Za pet delavcev izpiše samo čas, dovoljenja, svežost/posodobitev po odprtju,
obliko JSON in dovoljene številčne števce. Počakaj na redni cron, dokler imajo
vsi `updatedAfterRelease=true`, `expectedStatusShape=true`, `validJson=true`,
`mode=600` in svež čas; pregled sam delavcev ne zažene. Prazni števci ne dokazujejo
fizične dostave obvestila.
