# Pomočnik za svežo produkcijsko namestitev

`server/scripts/deploy-cpanel-production.php` je ločen od testnih pomočnikov. Namenjen je izključno novi prazni namestitvi Kanboard 1.2.54 na `jivie.triparna.si`, z bazo `tripar13_jivieprod`. Ne prenaša uporabnikov ali podatkov s testne oziroma stare namestitve. Dovoljene so samo možnosti `--check`, `--prepare`, `--activate`; poti in kontrolne vsote niso zamenljive z argumenti.

Fiksne poti:

- javni koren: `/home/tripar13/jivie.triparna.si`;
- zasebni koren: `/home/tripar13/private/jivie-production`;
- vhodni paket in manifest: podmapa `install`, datoteki `FamilyHub-0.7.0-source.zip` in `manifest.json`;
- ZIP SHA256: `1f201bb6c44c269af081bf629236db815fae3bf5518e8a1913f4a2c6f0bd67ba`;
- manifest SHA256: `0e05619fbcbd33921c3c2a7a29d7b79ddc1f15785791f2ae77c5e076acf23bb1`.

Uporablja že preverjena lokalna vhoda `build/releases/FamilyHub-0.7.0-source.zip` in `build/qa/jivie-upgrade/cpanel-upload/manifest.json`. Paket ima 63 datotek, FamilyHub 0.7.0/schema11. Pomočnik preveri hash celotnega ZIP/manifest, dovoljene vnose, CRC, posamezne hashe in PHP sintakso. Ne prenaša ničesar z omrežja.

## Predpogoji in dokaz sveže baze

Najprej lastnik ustvari **novo** namestitev s svojim varnim skrbniškim geslom; privzeti `admin/admin` ni dovoljen. Pomočnik **ne poveže baze** in ne dokazuje njene praznosti samodejno. Potreben je ločen pregled nove baze z branjem (brez `common.php`, migracij ali Native prijave): nič projektov in opravil, samo začetni skrbnik, brez tabel FamilyHub in brez uvoženih uporabnikov. Preveriti je treba tudi, da zasebna mapa ni znotraj nobenega dokumentnega korena ter da HTTPS dejansko vrne 503.

Po tem preverjanju upravljavec zapiše zasebni `install/fresh-install-proof.json` (0600). To je **izjava upravljavca**, pripeta hashu izvirne konfiguracije; ni nadomestilo za preverjanje žive baze in ne dokazuje, da se baza pozneje ni spremenila. Dokazov ne izdeluj za odblokiranje namestitve brez dejanskega pregleda. Ob spremembi baze, gesla ali namestitve je potreben nov pregled pred pripravo; pred aktivacijo ponovno preveri, da baza ostaja sveža. Ne objavi spletnega vmesnika ali uvedi cronov med temi koraki.

Obvezna oblika izjave (spodnje `false` zamenjaj s `true` **šele po ustreznem preverjanju**, hash je hash dejanske datoteke `config.php`, brez tiskanja vsebine):

```json
{
  "format": "jivie-fresh-install-operator-attestation-v1",
  "site": "/home/tripar13/jivie.triparna.si",
  "database": "tripar13_jivieprod",
  "kanboardVersion": "1.2.54",
  "configSha256": "HASH_DEJANSKE_IZVIRNE_KONFIGURACIJE",
  "newSoftaculousInstallation": false,
  "noImportedAccountsOrData": false,
  "onlyInitialAdmin": false,
  "initialAdminPasswordChanged": false,
  "zeroProjects": false,
  "zeroTasks": false,
  "noFamilyHubTables": false,
  "privateRootOutsideAllDocumentRoots": false,
  "maintenanceHttps503Verified": false
}
```

Zasebne mape morajo že imeti dovoljenja 0700, zasebni vhodi 0600, lastnik mora biti isti kot pri `/home/tripar13`. Pomočnik teh predpogojev ne širi ali popravlja. Javna mapa `plugins` mora biti prazna. Izvirna `data` sme vsebovati samo prazni `files`/`cache` ter izvorne zaščitne datoteke `.htaccess`, `web.config`, `index.html`; priponke, dnevniki, SQLite ali drugi podatki zahtevajo pregled.

Javna `.htaccess` se mora začeti z naslednjimi vrsticami (obstoječa pravila ostanejo za njimi):

```apache
# JIVIE PRODUCTION MAINTENANCE
RewriteEngine On
RewriteRule ^ - [R=503,L]
```

## Izvedba in meje

Pomočnika naloži v zasebno `install`, s PHP 8.4 CLI in razširitvijo ZIP. Ukazi so zaporedni:

```sh
/opt/alt/php84/usr/bin/php /home/tripar13/private/jivie-production/install/deploy-cpanel-production.php --check
/opt/alt/php84/usr/bin/php /home/tripar13/private/jivie-production/install/deploy-cpanel-production.php --prepare
/opt/alt/php84/usr/bin/php -l /home/tripar13/private/jivie-production/install/familyhub-deploy/config.candidate.php
/opt/alt/php84/usr/bin/php -l /home/tripar13/private/jivie-production/familyhub-config.php
# Ponovno preveri svežo bazo ter vzdrževalno zaporo pred naslednjim ukazom.
/opt/alt/php84/usr/bin/php /home/tripar13/private/jivie-production/install/deploy-cpanel-production.php --activate
```

`--check` samo bere. `--prepare` ohrani živo konfiguracijo/vtičnike, kopira svežo `data` v zasebno mapo, preveri celoten inventar in shrani izvirni `config.php` v zasebno varnostno kopijo. Kandidat ohrani poverilnice baze, nastavi zasebno `DATA_DIR`, `DEBUG=false`, `PLUGIN_INSTALLER=false` in ločeno konfiguracijo FamilyHub. Sprejme samo pregledne vrhnje literalne `define` stavke; dinamična konfiguracija, vključitve ali nepoznane nastavitve se zavrnejo.

`--activate` preveri nespremenjene konfiguracije, inventarje, paket, izjavo in zaporo. Namesti vtičnik in zasebno konfiguracijo; javni `config.php` postane samo vključitev zasebne datoteke. Izvirni podatki in varnostna kopija ostanejo ohranjeni. Zasebni podatki/konfiguracije so 0700/0600, vtičnik 0700/0644. Native API je v načinu `self_hosted`, stara projektna povabila in FCM so izključeni, proxy/CORS seznama prazna; SMTP in ključi niso dodani.

Vzdrževalna zapora ostane aktivna. Pomočnik ne ustvari računov, ključev, cronov, pošte ali sej, ne zaganja Kanboarda in ne izvaja migracij. Migracije, dejanske zmožnosti prek HTTPS, SMTP, prijava in končna odprava vzdrževalne zapore potrebujejo ločene dokaze. Ponovitve uspešne priprave/aktivacije ne prepisujejo artefaktov; odstopanja ali delno končana priprava se ustavijo za pregled. Po prekinitvi med preimenovanji stanje preveri ročno; pomočnik ne ugiba in ne briše podatkov za ponovni poskus. Ponovljivost velja za dokončani stanji `prepared` in `activated`, ne za nedokončano transakcijo nad datotekami.

## Ročna obnova po prekinitvi

Ob zavrnitvi `partial_prepare_or_unowned_destination_requires_review` ali `partial_or_unowned_activation_requires_review` pusti vzdrževanje aktivno. Najprej zasebno zavaruj celoten inventar in stanje, brez tiskanja konfiguracij. Ne preimenuj ali odstranjuj datotek, ki nimajo dokazljivega izvora iz tega zagona. Pred nadaljevanjem primerjaj hashe z `state.json`, preverjenim ZIP in izvirno kopijo; celovitost baze preveri ločeno.

Možne meje prekinitve:

| Stanje | Datoteke za pregled | Ročni postopek po dokazu izvora |
| --- | --- | --- |
| Priprava brez `state.json` | `familyhub-deploy`, zasebna `data`, `familyhub-config.php`; javna konfiguracija naj ostane izvirna | Ohrani delne artefakte v novi zasebni mapi za pregled; ne briši jih in ne ponaredi uspešnega stanja. Svežo pripravo ponovi šele ob prostih ciljnih poteh in ponovno preverjenih predpogojih. |
| Prvi `rename` aktivacije | Kandidat je postal zasebni `config.php`, vtičnik je še v `familyhub-deploy/FamilyHub`, javna konfiguracija izvirna | Po preverjanju kandidatovega hasha ga vrni na `familyhub-deploy/config.candidate.php`; nato mora `--check` spet potrditi `prepared`. |
| Drugi `rename` aktivacije | Zasebni `config.php` in javni `plugins/FamilyHub` obstajata, javna konfiguracija je še izvirna | Po preverjanju celotnega vtičnika ga vrni v zasebno staging mapo, kandidat pa na `config.candidate.php`; zahteva se uspešen `--check`. |
| Javni preklop uspe, zapis stanja ne | Javna konfiguracija je preverjeni kratek `require`, zasebni kandidat in vtičnik sta nameščena, `state.json` še kaže `prepared` | Najprej preveri vse tri končne hashe, izvirno kopijo, zaščito podatkov in zaporo. Upravljavec lahko nato zaključi samo oznako faze v zasebnem stanju ter zahteva uspešen `--check`, ali vrne oba premaknjena artefakta in z atomarno zamenjavo povrne javno izvirno kopijo. Obnovljeni javni kratek `require` ostane kandidat v staging mapi. Nobene kopije ne zavrzi. |

Ti postopki zahtevajo pregled dejanskega stanja; niso ukazi za samodejno povrnitev. Če so se konfiguracija, podatki ali baza medtem spremenili, ohrani vse kopije in ustavi namestitev do razrešitve. Preverjanja končnega delovanja in dovoljenje za odstranitev vzdrževanja ostanejo ločena.

## Lokalno preverjanje

Izolirani test `server/tests/cpanel-production-deploy.php` uporablja naključne začasne mape in prirejene kopije pomočnika, ki ne vsebujejo poti `/home/tripar13`; nima cilja za živo gostovanje. Pri preverjanju 9. oktobra 2026 je **194 kontrol PASS** v vsebniku `familyhub-fcm-setup-test:latest` z `--network none` in repozitorijem samo za branje. Preverjeni so priprava/aktivacija/ponovljivost, zasebna dovoljenja, ohranitev poverilnic in podatkov, odsotnost poverilnic v izpisu/javni novi konfiguraciji, zavrnitve nepravilnih dokazov, paketa, vzdrževanja, svežosti, simbolnih povezav, poznih sprememb ter delnih stanj pred zapisom `state.json` in po vsakem od treh aktivacijskih preimenovanj. To preverja pomočnik s sintetičnimi datotekami; ne potrjuje produkcijske namestitve ali žive baze.
