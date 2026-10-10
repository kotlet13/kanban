# Testna nadgradnja deljenja — priprava 10. oktobra 2026

Ta dokument opisuje lokalno pripravljen in preverjen pripomoček. Ne dokazuje
aktivacije gostovanja. Dovoljen cilj je samo `jivie-test.triparna.si`, obstoječa
baza `tripar13_jivietest`, FamilyHub 0.10.0/schema14 → 0.11.0/schema15.
Dokaze dejanske aktivacije vodi `CPANEL_SETUP.md`.

## Pregledani paketi

- `build/release/FamilyHub-0.11.0-sharing-source-final.zip`: 80 datotek, 73 PHP;
  SHA256 `d6f0b91c7fe539442ee6b0b84c017e14ee5fd23801aecc0a26f9b451f456288f`.
  Ustvarjen z `tools/plugin_release/package_source.py` in pregledanim seznamom
  dovoljenih datotek; brez konfiguracij, zgodovine Git ali uporabniških podatkov.
- `build/release/Jivie-sharing-upgrade-helpers.zip`: PHP pomočnik, shell ovoj in
  `manifest.json`; SHA256
  `c57d52150693d15792792f40abcb0947edcaddfa3553eda6afd357cee43ddac7`.
- Lokalni manifest je tudi `build/release/jivie-sharing-upgrade-manifest.json`.

Pomočnik ima pripeto kontrolno vsoto izvornega paketa. Preveri ZIP poti, navadne
vrste datotek, CRC, vsako datotečno kontrolno vsoto in dejansko PHP sintakso pred
odložitvijo vira. Star `config.php` in vse vključene zasebne konfiguracije samo
prebere ter preveri njihove hashe; ne zapisuje SMTP, FCM ali računov.

## Zaporedje na cPanelu

Ustvari novo zasebno mapo
`/home/tripar13/private/jivie-test/upgrade-0.11.0` z dovoljenji 0700.
Vanjo prenesi oba paketa in preveri njuni SHA256; razširi samo paket pomočnikov.
Datoteke naj imajo 0600. V isto mapo zajemi svež neprijavljen odgovor capabilities:

```sh
curl --fail --silent --show-error --header 'Content-Type: application/json' --data '{"v":1,"op":"capabilities","params":{}}' 'https://jivie-test.triparna.si/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub' > /home/tripar13/private/jivie-test/upgrade-0.11.0/before-capabilities.json
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh prepare
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh pause
```

`prepare` ne spremeni aplikacije. Shrani celoten originalni cron in pripravi
kandidat, ki ustavi samo pet točno določenih testnih delavcev. `pause` preveri
bajtno nespremenjeni originalni cron ter javni HTTPS 503. Po najmanj 65 sekundah:

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh snapshot
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh bundle-backup
```

Zajem zahteva svež pregled brez aktivnih testnih PHP procesov, celobazne READ
zaklepe vseh InnoDB tabel in nespremenjeno konfiguracijo. Zasebni arhiv vključuje
SQL, vse datoteke zasebne osnove (tudi stare kopije, brez trenutne delovne mape),
prejšnji vtičnik, konfiguracijo, originalni cron in `.htaccess`.

## Obvezna dejanska obnova pred aktivacijo

Prenesi **nov** `Jivie-private-upgrade-backup.zip` in njegovo `.sha256` v novo
zasebno lokalno mapo pod `~/.local/share/jivie/backups/` (mapa 0700, datoteke 0600).
Primerjaj SHA256 lokalne in oddaljene kopije. Ne uporabi starega dokaza obnove.
Ustvari nov vsebnik z drugo oznako, brez omrežja in brez objavljenih vrat:

```sh
docker run --name jivie-sharing-restore-20261010 --network none -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 -d mariadb:10.11.19
```

Po uspešnem `healthcheck.sh --connect --innodb_initialized`:

```sh
python3 server/scripts/verify-cpanel-jivie-backup.py /Users/anzenovsak/.local/share/jivie/backups/sharing-20261010/Jivie-private-upgrade-backup.zip --container jivie-sharing-restore-20261010
```

Preverjevalnik zahteva nov, prazen cilj obnove. Preveri vse tabele/stolpce/vrstice,
identiteto, račune, gesla, enrollment in vsak hash zasebnega drevesa. Aplikacije
ali poštnih delavcev ne zaganja. `restore-proof.json` vrni v trenutno zasebno
strežniško delovno mapo. `restore-evidence.json` vsebuje neskrivno število tabel,
vrstic/datotek in hashe; zabeleži ga v dokaze gostovanja. Vsebnik po preverjanju
ustavi, ne ustavljaj drugih razvojnih vsebnikov.

## Aktivacija in ponovna vključitev

```sh
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh activate
sh /home/tripar13/private/jivie-test/upgrade-0.11.0/upgrade-cpanel-jivie-sharing.sh release
```

Aktivacija zahteva ujemanje SQL in zasebnih hashov novega dokaza obnove, identitete
in celotnega obnovljenega posnetka. Pred aktivacijo morajo vsi stari podatki,
konfiguracija, cron in zasebne datoteke še ustrezati kopiji.

Migracija doda nullable `parent_scope_id`, ki dobi samo obstoječi `organization_id`,
nullable `access_scope`, `invitation_contract=1` in prazno
`familyhub_record_relocations`. Stare politike 1/2 se **ne razširijo**; njihov
izrecni prehod s predogledom je ločen uporabniški postopek. Uporabniška registracija,
e-pošta ali novo članstvo niso del nadgradnje. Pomočnik po migraciji in pred
odprtjem primerja hashe vseh starih stolpcev vseh tabel, posebej identiteto,
račune, gesla in enrollment, ter točno nove stolpce/indekse/prazno tabelo.

`release` najprej preveri stanje pod vzdrževanjem, nato bajtno povrne originalni
cron in `.htaccess`. Zunanji HTTPS pregled mora nato potrditi 0.11.0/schema15,
isti serverId in nove pogodbe deljenja; brez prijave preveri zavrnitve novih
zaščitenih metod. Preveri tudi nadaljnje statuse vseh petih delavcev in obstoječo
uporabniško prijavo posebej. Lokalna priprava sama tega ne potrjuje.

Pred aktivacijo je možen `abort-before-activation`. Po začetku DDL se ne izvajajo
samodejni SQL restore/drop/reset: `capture-recovery` ohrani novo stanje pod
vzdrževanjem za izrecno nadaljnje popravilo. Stare kopije ne vračaj čez poznejše
zapise ali izbrise računov.

## Lokalna preverjanja

- `server/tests/upgrade-sharing-helper-test.php`: **32 PASS**, sintetičen zasebni
  filesystem/ZIP/dokaz obnove, brez konfiguracije ali baze gostovanja; izolirani
  image `familyhub-fcm-setup-test` ima dejanski PHP tokenizer in `network=none`.
- `server/tests/upgrade-sharing-helper-db-test.php`: **28 PASS** na dejanski
  lokalni MariaDB 10.11.19 v ločenih začasnih bazah. Obnova SQL, vse stare vsebine,
  politike 1/2, stara username in e-poštna povabila ter novi privzeti stolpci so
  preverjeni; ponovljena migracija je stabilna. Preverjena je zavrnitev spremembe
  politik/pogodbe, neizrecnega parenta, samodejne relokacije, dodatnega stolpca ali
  tabele, manjkajočih indeksov, kasnejšega crona in povrnitve po migraciji.
- `tools/plugin_release/test_package_source.py`: **10 PASS**.
- PHP lint pomočnika in testa ter `sh -n` ovoja: PASS.

Ti rezultati so lokalni dokazi pomočnika; sveža dejanska kopija, izolirana obnova
te kopije in aktivacija gostovanja so ločeni koraki.
