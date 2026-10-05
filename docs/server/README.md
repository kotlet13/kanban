# Lokalno okolje in strežniški temelj

To je izvedena razvojna osnova, ne namestitev v produkcijo. Lasten vtičnik `FamilyHub` 0.5.0 razširi Kanboard 1.2.54 brez sprememb jedra. Native API dodaja prijavo, TOTP, naprave, povabljeno registracijo, dodelitve/dogodke, trajni inbox, opomnike in finančni modul z ločenimi pravicami; ločeno ostaja stari razvojni JSON-RPC dokaz projektnih povabil. Tri Docker okolja imajo ločene vsebnike, omrežja in poimenovane nosilce. Objavljena spletna vrata so vezana izključno na `127.0.0.1`. Drugih obstoječih Docker storitev ne upravljajo.

## Zagon in preverjanje

Ukaze izvedi iz korena repozitorija:

```sh
docker compose -f server/compose.yaml up -d
curl --fail http://127.0.0.1:18380/healthcheck.php
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/integration.php
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/native-integration.php
```

[Kanboard na lokalnem računalniku](http://127.0.0.1:18380) uporablja SQLite. Uradna slika `kanboard/kanboard:v1.2.54` je pripeta na SHA256 `8df6c4339134b6c196da9a262daa42ab8ce395f528a48d4a3dd7038c296f34c1`. Preverjena slika vsebuje PHP 8.4.24; to je konkretna razvojna podrazličica in ne dokaz podrazličice PHP na gostovanju.

Izolirana dodatna matrika MySQL:

```sh
docker compose -f server/compose.mysql.yaml up -d
docker compose -f server/compose.mysql.yaml exec -T kanboard php /familyhub-tests/integration.php
docker compose -f server/compose.mysql.yaml exec -T kanboard php /familyhub-tests/native-integration.php
```

Drugo okolje objavi Kanboard na `127.0.0.1:18381`; baza nima objavljenih vrat. Uradna slika `mysql:8.4` je pripeta na SHA256 `6ea90827b1100f8f2ae306a539f86d2c264a26ed435a2a9f75551dd5c3aeb242`. Prikazane poverilnice v `compose.mysql.yaml` veljajo izključno za zavržljivo lokalno bazo. Binarni dnevnik je izključen za test začasnega sprožilca, ki simulira napako zapisa. Takšna nastavitev ni predlog za produkcijo. Backup je potrdil MySQL PDO gonilnik in glavo različice 10.11.19; test MySQL 8.4.11 sam ne dokazuje enakosti pogona.

Matrika MariaDB 10.11.19 uporablja uradno sliko s SHA256 `7db29378d4fdab73f8123bbc2b48905c90d1a4b00cf848b028f1e81e623257f2`, brez objavljenih vrat baze. Kanboard je na `127.0.0.1:18382`:

```sh
docker compose -f server/compose.mariadb.yaml up -d --wait
docker compose -f server/compose.mariadb.yaml exec -T kanboard php /familyhub-tests/native-integration.php
docker compose -f server/compose.mariadb.yaml exec -T kanboard php /familyhub-tests/integration.php
```

Testi ustvarjajo naključna sintetična imena, gesla in projekte ter poročajo samo imena preverjanj, brez poverilnic ali povabilnih žetonov. Native test zahteva `FAMILYHUB_DEVELOPMENT_MODE === true`; ponavljanje ohrani podatke in QA račune, resetira le lastne sintetične IP rate bucket ključe. Podatki ostanejo samo v nosilcu ustreznega okolja; ponavljanje testov doda nove sintetične zapise. Na sveži Kanboard bazi ostane standardni začetni račun `admin`/`admin`; uporaben je le za ta lokalni prikaz. Native QA uporablja običajne `app-user`, ne skrbnika. Na javnem strežniku standardni začetni račun ni sprejemljiva nastavitev.

Za zasebno lokalno QA datoteko (nikoli je ne izpiši ali dodaj v Git):

```sh
mkdir -p build/qa/sharing
chmod 700 build/qa/sharing
umask 077
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/native-seed.php > build/qa/sharing/shared-fixture.json
```

Seed ustvari novega sintetičnega lastnika in TOTP uporabnika ter ime še neregistriranega prejemnika. TOTP skrivnost in gesla so testni podatki, samo v zaščiteni datoteki. Dejanski UI preizkus ustvari gospodinjstvo in povabilo v aplikaciji; seed ne ponareja opravljenega toka.

Za ustavitev brez izgube lokalne testne baze:

```sh
docker compose -f server/compose.yaml down
docker compose -f server/compose.mysql.yaml down
docker compose -f server/compose.mariadb.yaml down
```

Dodatek `--volumes` odstrani izključno nosilce izbranega Compose projekta in s tem njegove sintetične podatke; uporabi ga le, ko želiš zavreči to okolje. Ne uporabljaj splošnega `docker system prune`.

## Paket vtičnika

```sh
python3 server/scripts/package-plugin.py
```

Nastaneta `server/dist/FamilyHub-0.5.0.zip` in datoteka SHA256. Paket vsebuje samo mapo `FamilyHub`: PHP izvorno kodo, migracije in kratka navodila. Ne vsebuje podatkov, testov, razvojnih nastavitev ali gesel. Sestava ZIP je deterministična. Paket je pripravljen za kasnejši prenos z upravljalnikom datotek v cPanel, vendar še ni nameščen v produkcijo in produkcijske nastavitve/pravice niso preizkušene.

Povabila so v razvojnih konfiguracijah izrecno vključena, v samem vtičniku pa **privzeto izključena**. Razlog: obstoječe finance so v Kanboardovih projektnih metapodatkih. Dodajanje projektnega člana lahko odpre tudi te metapodatke, zato vtičnik ne trdi, da ločeno varuje finance. Pred vključitvijo na resničnih podatkih potrebujemo ločeno finančno shrambo in preverjene pravice. Podrobnosti pogodbe so v [api-contract.md](api-contract.md).

Native API je neodvisno **privzeto izključen** (`FAMILYHUB_ENABLE_NATIVE_API`). Njegovi household/project obsegi uporabljajo lastna članstva in tabele; zato ne odprejo starih projektov ali financ. Generic record contract1 podpira project/task/shoppingList/shoppingItem; contract2 doda datume, dodelitve, avtorstvo in event. Finance uporabljajo ločene finance.* metode, tabele in cursor. Celotna pogodba, točne omejitve, napake in CORS/TLS nastavitve so v [native-api-contract.md](native-api-contract.md). Razvojna HTTP izjema in CORS 18770/18771 nikoli ne sodita v produkcijski paket.

## Migracije in povrnitev

Schema 1 vsebuje stari `familyhub_project_invitations`. Schema 2/3 dodata native instance/accounts/scopes/members/records/operations/devices/invitations/rate_limits/totp_state. Schema4–7 dodajo sodelovanje/inbox/reminders/finance/delivery ter dopolnitve med razvojem. Schema9 doda owner-only personal scope, enrollment, preverjeno email identiteto, hash enkratnih kod in šifrirano account-mail queue. Schema8 additivno doda šifrirane registracije FCM naprav in reference-only push queue; podatkov in čakajočih operacij ne briše. Kanboardova evidenca `plugin_schema_versions` zabeleži različico9. Ne spreminja starih podatkovnih modulov in ne seli finančnih metapodatkov. Registracija izrecno povabljenega novega računa uporabi core UserModel in običajno vlogo. Ni migracije PostgreSQL; povabila in native API se za ta gonilnik ne vključijo. Zgodnja razvojna schema 2 brez identity binding se dopolni brez brisanja; stare neveljavne naprave/članstva se ne nadgradijo v nove pravice.

Pred kakršnokoli kasnejšo namestitvijo ugotovi dejanski gonilnik in različico baze, omogočene PHP razširitve ter dostopne poti za kopiranje. Varnostno kopiraj celotno bazo, priponke in nastavitve. Na ločeni kopiji izvedi uvoz, naloži vtičnik, preveri število/pravice obstoječih projektov ter preizkusi obnovo prvotne kopije. Pri MySQL DDL ni zagotovljeno transakcijsko vračanje celotne migracije; kopija je obvezna tudi za ta dodaten korak.

Odstranitev mape vtičnika ustavi njegove API metode, ne izbriše tabel in ne prekliče že sprejetih projektnih članstev. Za povrnitev podatkovnih sprememb uporabi predhodno preverjeno celotno kopijo. Podatkov ne briši ali spreminjaj ročno kot nadomestilo za preverjeno obnovo.

## Dejansko preverjeno in nadaljnji obseg

4. oktobra 2026 je stari HTTP JSON-RPC sklop uspešno opravil 81 preverjanj na SQLite, MySQL 8.4.11 in MariaDB 10.11.19, s PHP 8.4.24. Preverja dovoljene in zavrnjene dostope, osebno identiteto proti globalnemu API ključu, 2FA, preklic, potek, idempotenco, neposredne in skupinske vloge, ponovitev po preklicu članstva, napako zapisa ter vzporedni sprejem/preklic. Svež ločen vsebnik z vsebino dejansko sestavljenega ZIP, brez razvojne konfiguracije, opravi osem preverjanj: izključena stara povabila, native prijavo in sinhronizacijo ter zavrnitev ponarejenega forwarded HTTPS. PHP lint je uspešen za celoten vtičnik in teste. ZIP vsebuje samo izvorni vtičnik; preverjeni so CRC, enakost izvornih bajtov in enak SHA256 po ponovni sestavi.

Native HTTP sklop dejansko preverja lastnika brez admin pravic, obstoječo prijavo, povabljeno registracijo z rollbackom, naprave, TOTP/replay/zaklep, hash žetonov, lastne obsege in viewer/foreign/revoked ACL, konflikte dveh ljudi, izgubljen odgovor/idempotenco, tombstone, starše, paginacijo, čakanje na scope commit ter accept/revoke in remove/push race. Končni sklop je uspešno opravil **93/93 preverjanj na SQLite, MySQL 8.4.11 in MariaDB 10.11.19**; SQLite je neodvisno ponovil glavni agent. Vključuje tudi dejanski project/task CRUD, nespremenljiv createdAt, veljavne datume, UTF-8 bajtne omejitve, omejeno velikost strani z Unicode vsebino in potek naprave.

Finančna domena lahko v prihodnje podpira izrecno deljenje v gospodinjstvu ali ustrezno zasnovanem projektu; zahteva lastne pravice in pogodbo. FamilyHub 0.3 že omogoča ločen skupni finančni modul po izrecnem vklopu; generic sync ne vrača finančnih podatkov. Zaseben lokalni račun ni samodejno deljen.

Odprto ostaja: preizkus namestitve na cPanel, dejanska platformna varna hramba, upravljanje 2FA iz aplikacije, zunanji auth ponudniki, življenjski cikel/kvote trajnih zapisov, cross-scope/valutni prenosi ter naprednejša finančna pravila. Native podatki se ne urejajo v core Kanboard spletnem vmesniku; ta obseg ne obljublja take sinhronizacije. Dejanski SMTP provider/TLS poverilnice, APNs/FCM in oddaljeni SSH so nepreverjeni. Povabila in naprave preverijo čas ob zahtevi; osnovna sinhronizacija ne potrebuje e-pošte ali stalnega procesa. Server opomniki in izbirna SMTP dostava uporabljajo bounded cron.

## Primarni viri

- [Uradna izvorna koda Kanboard 1.2.54](https://github.com/kanboard/kanboard/tree/v1.2.54).
- [Nalagalnik in migracije vtičnikov](https://github.com/kanboard/kanboard/blob/v1.2.54/app/Core/Plugin/Loader.php).
- [Avtentikacija API, zaklepanje in pravilo za 2FA](https://github.com/kanboard/kanboard/blob/v1.2.54/app/Api/Middleware/AuthenticationMiddleware.php).
- [Neposredne in skupinske projektne vloge](https://github.com/kanboard/kanboard/blob/v1.2.54/app/Model/ProjectUserRoleModel.php).

Vmesniki so bili preverjeni v izvorni kodi izdaje in v dejansko zagnani uradni sliki. Datoteke v `/tmp` so bile raziskovalne kopije in niso del dostave.


## Sodelovanje, inbox in finance — nova etapa

Exact pogodba je v [collaboration-api-contract.md](collaboration-api-contract.md), vključno z record2 kompatibilnostjo, account inbox visibility resetom in finance accessRevision reset/backfill. Ob spremembi pravic odjemalec takoj skrije staro vsebino; lokalnih nesprejetih namer ne zavrže. Finančni account holder, payer/recipient in canonical author so različne vloge. Prenosi med member-owned in skupnim računom istega skupnega obsega/valute ne štejejo kot income/expense. Osebni cross-scope ali valutni prenosi še niso podprti.

Za vsako Compose matriko zaženi še:

```sh
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/collaboration-integration.php
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/finance-integration.php
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/smtp-integration.php
```

Zamenjaj compose.yaml z compose.mysql.yaml oziroma compose.mariadb.yaml za drugo bazo. SMTP test sam ustvari omejen loopback PHP zajemnik v istem vsebniku, sprejema samo sintetične .invalid naslove in ga odstrani; ne potrebuje nove Docker slike in ne pošilja zunaj. Proces za zajemnik je samo testna infrastruktura, produkcijski adapter ne izvaja subprocess. Evidenca te etape je v ignorirani `build/qa/family-upgrade/`.

Končna matrika 4. oktobra 2026: **37/37 collaboration, 40/40 finance in 15/15 SMTP preverjanj na vsaki od treh baz** (SQLite, MySQL 8.4.11, MariaDB 10.11.19). Na vsaki sta ponovno uspešna tudi native 93 in legacy 81. Collaboration pokriva paginiran inbox nad 100 dogodki, sočasne read/novi-event variante, dodelitve, avtorstvo, opomnike ter preklic članstva. Finance pokriva izolacijo od generic sync, transferje, avtorstvo, audit, izgubljeni ACK, sočasni revision/grant race in reset/backfill po ponovni dodelitvi pravic. SMTP preverja dejanski lokalni zajem, neodvisna inApp/email kanala, ponovne poskuse in preklic ter zavrnitev TLS downgrade; zunanje dostave ne potrjuje.

Prejšnji paket `FamilyHub-0.3.0.zip` (4. oktober) je imel 29 izvornih datotek, SHA256 `95e3ce93f62ab00e758a97f31944428404ef7d1fb6223217bcfd9d51c4f231b5`; takrat razširjeni ZIP je opravil vseh 6 default-policy preverjanj brez razvojnih nastavitev.

Opomniki in izbirna e-pošta v kasnejši preverjeni cPanel namestitvi:

```sh
php /path/to/kanboard/plugins/FamilyHub/cli/reminders.php --limit=100
php /path/to/kanboard/plugins/FamilyHub/cli/delivery.php --limit=20
```

Prva pot in razpoložljivi PHP CLI na gostovanju zahtevata preverjanje; to nista izvedena produkcijska ukaza. Delivery potrebuje izrecno lastno FAMILYHUB_SMTP_* konfiguracijo. `mail()` in globalni BCC se ne uporabljata. Pred transportom preveri trenutne pravice in preference; telo je generično brez task/finance podatkov. Stable Message-ID ne zagotovi exactly-once SMTP. Privzeto email=false, capability smtp=false brez konfiguracije, externalPush=false brez konfiguracije; izbirni FCM adapter0.4 omogoči kanal samo ob veljavni konfiguraciji. Neodvisna nastavitev email=true lahko deluje ob inApp=false. [Uradna dokumentacija Swift](https://swiftmailer.symfony.com/docs/sending.html) potrjuje send recipient count; nameščena pripeta knjižnica je preverjena tudi za TLS fallback. Swift ni več vzdrževan: gre za obstoječo Kanboard odvisnost, ne novo nameščeno knjižnico.

Native bearer controller zavrže neuporabljeno spletno sejo (`session_abort`), zato Kanboardov deferred session SELECT/write ob koncu ne tekmuje z native SQLite transakcijami in ne doda fatal izpisa po JSON odgovoru. Core spletni/JSONRPC tokovi niso spremenjeni.


## Izolirani HTTP preizkusi odjemalca

`server/compose.http-tests.yaml` uporablja dva ločena SQLite nosilca in loopback 18381/18382, brez sprememb živega razvojnega okolja 18380. Ta vrata so sicer uporabljena v MySQL/MariaDB matriki: okolij ne zaganjaj sočasno na istih vratih. Za sočasno preverjanje uporabi izrecni Compose port override za matriko. Poverilnice seed vedno preusmeri v zasebno datoteko:

```sh
docker compose -f server/compose.http-tests.yaml up -d --wait
umask 077
docker compose -f server/compose.http-tests.yaml exec -T sharing php /familyhub-tests/native-seed.php --server=http://127.0.0.1:18381 > build/qa/family-upgrade/isolated-sharing.json
docker compose -f server/compose.http-tests.yaml exec -T upgrade php /familyhub-tests/native-seed.php --server=http://127.0.0.1:18382 > build/qa/family-upgrade/isolated-upgrade.json
```

Dva odjemalčeva HTTP sklopa uporabita vsak svojo datoteko/strežnik. Ponovljeni testi registracije še vedno štejejo v varnostno omejitev 10/IP/600s; ni testnega bypassa ali brisanja rate tabel. Za povsem neodvisen nov zagon uporabi nov Compose project (`-p`) in njegove sveže sintetične nosilce, ko so vrata prosta; starih podatkov ne odstranjuj. Ustavitev z `down` ohrani nosilce.

Sklop `scope-rate-integration.php` je opravil **10/10 preverjanj na vseh treh bazah**. Uporablja naključne sintetične IP ključe/račune in dejanske trajne števce brez resetov: 600 branj uspe, 601. je zavrnjeno, drug račun za istim NAT ostane dovoljen, menjava IP ne obide uporabniške omejitve, 121. sprememba ostane zavrnjena, 2401. neavtenticirana zahteva istega IP je zavrnjena. Native 93, collaboration 37, finance 40 in SMTP 15 so po spremembi ponovno uspešni na vsaki bazi. Nova politika ne spreminja omejitev prijave, registracije ali sprememb; legitimno branje pri gospodinjskem pollingu loči od prejšnje skupne scope omejitve 120/IP/min.


## Izbirni FCM — priprava 5. oktobra 2026

Adapter0.4 uporablja Firebase samo za dostavo generičnih opozoril; podatki, auth in kanoničen inbox ostanejo v FamilyHub. Native API in FCM sta v ZIP privzeto izključena. [Pogodba push](push-api-contract.md) vsebuje vse konstante, device CAS/generation, reference-only payload, skupine, ACL in offline preflight. Primer konfiguracije je [server/examples/fcm-config.php.example](../../server/examples/fcm-config.php.example); zasebni JSON in ločen32-byte ključ sta zunaj javnih map. PUBLIC_ROOT je obvezen tudi za CLI; dodatne virtualne gostitelje preveri skrbnik. Preflight ne dokazuje Google IAM/APNs ali dejanske dostave.

```sh
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/push-integration.php
python3 server/scripts/test-push-http.py
php /path/to/kanboard/plugins/FamilyHub/cli/push-preflight.php
php /path/to/kanboard/plugins/FamilyHub/cli/push.php --limit=20
```

Zadnja dva ukaza sta predloga za kasnejšo cPanel namestitev, ne izvedeni produkcijski dejanji. Cron ima40s dispatch budget, rezervira20s za OAuth+send, vsak HTTP timeout10s, no redirect in TLS verify. DB lock waits5s lahko podaljšajo celotni walltime; SQLite med send drži write transaction in lahko začasno blokira urejanje. Jobs potečejo po24h, največ5 poskusov, lease120s in bounded retry. Rotacija/odjava/preklic/geslo/2FA/policy/prefs se ponovno preverijo; že sprejete push dostave ni mogoče odpoklicati in ambiguous ACK lahko podvoji OS opozorilo. Ni realnih Firebase credentialov, projektov ali zunanjih prejemnikov v testih.

Končna evidenca te priprave je v ignorirani `build/qa/firebase-preparation/`. Preverjevalni dnevniki ne izpisujejo žetonov ali uporabniških payloadov. Ločene zasebne `isolated-*.json` fixture datoteke vsebujejo sintetična gesla/TOTP skrivnosti, imajo dovoljenja0600, so izključene iz Gita in niso za objavo. Sintetična push integracija vključuje več naprav, lost-ACK CAS, cross-account token binding, rotacijo in revoke race, šifriranje/AAD, generic payload, push-only skupine, finančni ACL, potek/lease/retry, OAuth401 refresh ter permanentne/malformed provider odgovore. Konfigurirani HTTP smoke ima12 preverjanj v zavržljivem official vsebniku brez omrežja. Običajni localhost18380 ostane FCMoff.

Finalna matrika 0.4.0: **76 push + 93 native + 37 collaboration + 40 finance + 15 SMTP + 10 scope-rate + 81 legacy = 352 preverjanj na vsaki od treh baz** (SQLite, MySQL 8.4.11, MariaDB 10.11.19). Konfigurirani HTTP smoke: **12/12**. Nadomestni provider in dejanski dvoprocesni registration/delivery race preverita generacije; nobena zahteva ni šla v Google.

Paket **FamilyHub-0.4.0.zip** vsebuje **39 izvornih datotek**, SHA256 **`569d365aa58ab719eaaf328c04515537ceeddd954c869060ab5ce2e09e518778`**. Dvakratna sestava ima isti SHA256; CRC in vsak ZIP vnos sta preverjena proti izvornim bajtom. Dejanski razširjeni ZIP brez konfiguracije opravi **8/8 default-policy** preverjanj; celoten vtičnik in PHP testi imajo uspešen lint.

## Osebni prostor, prvi vstop in obnova računa — 0.5.0

[Pogodba računa](account-api-contract.md) določa izvedene metode in združljivost. Osebni prostor nastane samo z izrecnim personal.ensure; strežnik ima en trajen owner-only prostor na račun. Povabila, dodatni člani in finančne pravice drugim so prepovedani, tudi ob podtaknjenem članstvu. Stari scopes.list brez includePersonal=true tega prostora ne vidi. Zasebne finance ostanejo v ločenem finance API; projekt se ne izbriše pred potrjenim odklopom finančnih povezav. Osebni prenos mora pred vključitvijo preveriti celotne lokalne vrednosti, brez krajšanja.

Prvi novi račun omogoči upravljavec v Kanboard Settings → FamilyHub Bootstrap. GET ničesar ne izda; HTTPS admin POST zahteva CSRF in trajen issuanceId proti refresh replay. Enkratna koda velja 15 min in je prikazana samo v odgovoru na izdajo. Po prvem FamilyHub računu se bootstrap zapre; obstoječi Kanboard uporabniki se normalno prijavijo. CLI je alternativa, ne pogoj spletnega setupa. Njegov izhod preusmeri v zasebno datoteko, ne v dnevnik ali cron email:

```sh
umask 077
php /path/to/kanboard/plugins/FamilyHub/cli/enrollment.php --admin-user-id=1 > /home/ACCOUNT/private/familyhub-enrollment.json
```

ID mora biti dejanski aktivni skrbnik. To je primer za kasnejšo namestitev; noben tak ukaz ni bil izveden v produkciji.

Preverjanje e-pošte in reset gesla zahtevata [ločeno SMTP/key konfiguracijo](../../server/examples/account-mail-config.php.example). Naključni 32-byte ključ ustvari v zaščiteni datoteki zunaj vseh public_html/webroot map; konfiguracija ga prebere, nikoli se ne izpiše v dnevnike:

```sh
umask 077
php -r 'file_put_contents("/home/ACCOUNT/private/familyhub-account-mail.key", base 64_encode(random_bytes(32)));'
php /path/to/kanboard/plugins/FamilyHub/cli/account-mail.php --limit=20
```

Drugi ukaz je primer minutnega cPanel cron opravila. Uporabi dejansko pot PHP CLI in preveri dovoljenja na gostovanju. Brez SMTP ali ključa sta emailVerification/passwordReset izključena; ne trdimo, da je ponudnik konfiguriran. UI dostopnost preverjanja naslova določa capability emailVerification, status.resetAvailable pa pomeni že verificiran naslov za reset. Sprememba naslova zahteva geslo in svež TOTP. Reset ostane brez samodejne prijave, ohrani TOTP in prekliče vse naprave/push generacije. Varnostna e-pošta ima enega prejemnika, ignorira globalni BCC in inbox preference; kode so v telesu sporočila, ne URL.

Account-mail queue je šifrirana AES-256-GCM z ločenim ključem, token records hranijo samo hash. Worker ima 60 s dispatch budget, rezervira 50 s za bounded SMTP; čakanje na DB locks lahko podaljša walltime. Med pošiljanjem drži user/job transaction, pri SQLite write lock. Lease 120 s, največ 5 poskusov, rok določa veljavnost kode; pred dostavo ponovno preveri identiteto, geslo/2FA in revizijo naslova. Ambiguous ACK lahko podvoji isto e-pošto. Ključ ohrani s celotno zaščiteno strežniško kopijo; rotacija onemogoči že shranjeno pending ciphertext. Sinhronizacija ni kopija; šifriran client backup ne vsebuje celotne strežniške baze ali priponk.

Dodatna sintetična sklopa za vsako od treh Compose baz:

```sh
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/personal-integration.php
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/account-integration.php
```

Finalna matrika 0.5: **48 account + 36 personal + 76 push + 93 native + 37 collaboration + 40 finance + 15 SMTP + 10 scope-rate + 81 legacy =436 preverjanj na vsaki bazi**. Account uporablja resničen lokalni SMTP zajem, šifriranje/AAD, TOTP/replay, stare reset/verify kode, vse-device revocation, rate limits, lease/retry in dejanski dvoprocesni reset race. Dvoprocesni personal.ensure na vseh treh bazah vrne isti prostor. Personal preveri stare scopes.list, podtaknjena članstva, private/shared meje, celotno Unicode vsebino ter finance unlink/project delete.

Admin HTTP sklop na svežem SQLite ima **12/12** dejanskih preverjanj: GET ne izdaja, CSRF/nonadmin zavrnitev, admin POST, refresh replay, dvoprocesna enrollment poraba in HTTP zavrnitev brez razvojne izjeme. Fresh fixture se ustvari izključno na 18383/18384, nikoli ne ponastavi 18380:

```sh
python 3 server/scripts/start-account-http-fixture.py --project kanban-familyhub-account-review --port 18383 --output build/qa/personal-sync-recovery/account-review.json
```

Za ponovitev potrebuješ nov project/volume in novo zasebno fixture datoteko, ker enrollment uspe samo enkrat. SMTP zajemnik velja 900 s; namenjen je samo loopback .invalid naslovom. Admin smoke potrebuje ločeno fresh smoke fixture na 18384 in sprejme --fixture argument (glej --help). Evidence v build/qa/personal-sync-recovery imajo 0600; fixture vsebuje sintetična gesla/kode in ni za objavo. Logi ne vsebujejo teh vrednosti. V produkciji še niso preverjeni SMTP ponudnik/TLS, cPanel namestitev/cron ali email dostava.

Paket **FamilyHub-0.5.0.zip** vsebuje **53 izvornih datotek**, SHA256 **`8dafe 588ec 930d 3189d 60e 79be 727cf 15d 5d 29fbbbdf 259937f 578575c 389066`**. Dve sestavi sta bajtno enaki; CRC in vsi ZIP vnosi so preverjeni proti izvoru. Razširjeni dejanski ZIP brez konfiguracije opravi **11/11 default-policy** preverjanj. Konfigurirani FCM HTTP smoke ostaja **12/12**, brez omrežja ali realnih Google zahtev. PHP lint vseh **68** datotek vtičnika/testov je uspešen. MySQL/MariaDB in admin smoke vsebniki so po preverjanju ustavljeni brez odstranitve nosilcev; SQLite 18380 in ločeni 18383 QA sta ohranjena.

Po zaključku 0.5 sta na svežih ločenih SQLite HTTP okoljih uspešna tudi **2/2 prejšnja Flutter HTTP regresijska testa** (collaboration_http_integration_test in family_upgrade_http_test), z aktualnim client schema4: dve identiteti, diskovni restart, konflikti/kopiranje/preklic ter dodelitve, inbox race/paginacija, finance ACL/restart/spori in push-group routing. Dokaz je v build/qa/personal-sync-recovery/client-shared-regression-http.log (0600). Okolji18381/18382 sta po testu ustavljeni brez odstranitve nosilcev;18380 in novi account QA18383 ostaneta ločena. Ponovitev registracij potrebuje svež fixture, ne ponastavitve običajnega razvojnega strežnika.
