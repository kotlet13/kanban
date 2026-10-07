# Jivie in FamilyHub na cPanelu

Vodič za samostojno gostovanje, pripravljen 7. oktobra 2026 iz kode **FamilyHub 0.6.0 / schema10** za **Kanboard 1.2.54**. Po uporabnikovem dovoljenju je na novi ločeni testni poddomeni izvedena sveža namestitev; dejanske dokaze vodi razdelek 11. Stari Kanboard ostane nespremenjen. Jivie osebni način deluje brez strežnika; ta postopek omogoči izbirno sinhronizacijo, sodelovanje in strežniške storitve.

Pregled gostovanja in prejšnja kopija kažeta PHP 8.4 (glava izvoza: 8.4.25), `DB_DRIVER=mysql` in podatkovni strežnik 10.11.19. Lokalna matrika vključuje MariaDB 10.11.19. Aktualno različico, poti in dovoljenja je treba preveriti na mestu namestitve; stare ugotovitve niso pregled trenutnega stanja. PHP `mail()` in izvajanje sistemskih procesov sta bila izključena. Vtičnik uporablja SMTP oziroma PHP cURL, ne teh funkcij.

## 1. Zapiši dejanske poti in pripravi ločeno preizkusno okolje

V cPanel **Domains** preveri document root posamezne domene/poddomene; v **File Manager** najdi obstoječi Kanboard `index.php`, `config.php`, `app/common.php`, `plugins` in dejansko podatkovno mapo. `data/files` je bila potrjena v stari kopiji, namestitev pa lahko pot spreminja. V **MultiPHP Manager** preveri različico za konkretno domeno. Ne sklepaj, da sta spletni PHP in CLI ista.

V spodnjih primerih `/home/ACCOUNT/public_html/kanboard`, `/home/ACCOUNT/private` in `/opt/cpanel/ea-php84/root/usr/bin/php` pomenijo **predloge**, ne potrjenih poti. `ACCOUNT` zamenjaj z dejanskim računom, pot Kanboarda pa s svojim korenom. EasyApache in CloudLinux imata različni CLI poti; uporabi [cPanel navodila za PHP CLI](https://support.cpanel.net/hc/en-us/articles/360050224413-How-to-run-PHP-commands-as-a-cPanel-user-via-Terminal).

Najprej ustvari staging poddomeno z veljavnim HTTPS, svojo mapo, ločeno bazo in ločenim DB uporabnikom. Za uporabniški preizkus uporabi svež Kanboard 1.2.54 in sintetične račune. Zamenjaj začetno skrbniško geslo pred javnim dostopom. Omeji dostop do staginga; celotnega Kanboard korena ne ponujaj kot statičen prenos.

Obnovo produkcijske kopije preverjaj ločeno, zasebno in brez odhodne dostave. Obnovljena baza vsebuje resnične e-poštne vrste, naprave in morebitna čistilna opravila: **na njej ne zaženi cronov** in je ne poveži z napravami ali produkcijskim SMTP/FCM. Kopije staginga ne smejo uporabljati produkcijske baze ali priponk. Obnovljeni `serverId` prav tako ne pomeni nove strežniške identitete.

## 2. Sveža kopija in načrt povrnitve

Pred nameščanjem izključi pisanje za dogovorjeno kratko vzdrževalno okno in ustavi obstoječe dostavne crone te namestitve. Zajemi skladno kopijo:

- celotne Kanboard baze prek cPanel Backup/phpMyAdmin, vključno z vsemi `familyhub_*` tabelami pri nadgradnji;
- celotne podatkovne mape, priponk in avatarjev;
- konfiguracije, trenutnega vtičnika ter ločenih zasebnih šifrirnih ključev, če obstajajo.

Prenesi kopijo v zaščiten lokalni arhiv zunaj Git in vseh javnih map. Preveri obnovo v ločeni bazi, število zapisov in odpiranje izbranih priponk. SQL in datoteke morajo pripadati istemu zajemu. [Prejšnji arhiv](../../README.md) ne nadomesti sveže kopije pred novo migracijo.

Dogovori povrnitev celotne skladne baze, datotek in konfiguracije, če staging preverjanje ali namestitev odpove. Odstranitev mape `FamilyHub` samo izključi API; **ne povrne migracij**. Po dejanskem uporabniškem izbrisu stare kopije ne obnovi tiho, saj bi obnovila izbrisani račun. Novih zapisov po nadgradnji ne izgubi s slepo obnovo stare kopije.

## 3. PHP in omrežje

Kanboard 1.2.54 zahteva PHP **8.1+** ter `SimpleXML`, `dom`, `xml`, `gd`, `mbstring`, `hash`, `openssl`, `json`, `ctype`, `filter`, `session`; za to MariaDB/MySQL namestitev še `PDO` in `pdo_mysql`. To so zahteve [izvornega composer.json izdaje 1.2.54](https://github.com/kanboard/kanboard/blob/v1.2.54/composer.json), ne ohlapne zahteve starejše izdaje. FamilyHub uporablja `mb_check_encoding`, PDO transakcije in OpenSSL AES-256-GCM; izbirni FCM dodatno zahteva **cURL** in OpenSSL RSA podpisovanje. Preveri CA trust store, čas strežnika in DNS.

V cPanel Terminal lahko po potrditvi poti opraviš preverjanje **brez izpisa konfiguracije ali skrivnosti**:

```sh
/opt/cpanel/ea-php84/root/usr/bin/php -v
/opt/cpanel/ea-php84/root/usr/bin/php -r 'foreach (["SimpleXML","dom","xml","gd","mbstring","hash","openssl","json","ctype","filter","session","PDO","pdo_mysql"] as $e) { echo $e, ": ", extension_loaded($e) ? "OK" : "MISSING", PHP_EOL; }'
/opt/cpanel/ea-php84/root/usr/bin/php -r 'echo "AES-256-GCM: ", in_array("aes-256-gcm", openssl_get_cipher_methods(), true) ? "OK" : "MISSING", PHP_EOL; echo "cURL: ", extension_loaded("curl") ? "OK" : "MISSING", PHP_EOL;'
```

Spletne razširitve preveri prek zasebnih nastavitev/diagnostike gostovanja. Javne datoteke `phpinfo()` ne puščaj na strežniku. Če razširitve ali CLI niso na voljo, jih uredi s ponudnikom pred namestitvijo. Strežniški cron teče neposredno s PHP CLI; oddaljeni SSH, Docker, Composer in stalni proces niso potrebni. Spletni terminal je priročen za prvi ročni preizkus, ne pogoj za vsak prihodnji zagon.

Za SMTP mora gostovanje dovoljevati odhodno povezavo na ponudnikova vrata z preverjenim TLS. FCM potrebuje odhodni HTTPS do `oauth2.googleapis.com` in `fcm.googleapis.com`. To na produkciji še ni dokazano. Ne vključuj razvojnih izjem za HTTP ali nezaščiten SMTP.

## 4. Naloži samo vtičnik 0.6.0

Lokalno pripravljena javna dostava je pregledani 61-datotečni `build/releases/FamilyHub-0.6.0-source.zip` s spremljajočim SHA256. Edina aktualna pot ponovne sestave je `python3 tools/plugin_release/package_source.py --output build/releases/FamilyHub-source-reviewed.zip` po pregledu manifesta; obstoječih paketov ne prepisuje. [Navodila paketorja](../../tools/plugin_release/README.md) opišejo izrecni seznam datotek in zavrnitve. Stari široki rekurzivni paketor ni uporabljen za to predajo. Preveri ustrezno kontrolno vsoto in vsebino ZIP pred uporabo. To ni statična stran `jivie-website.zip`.

V staging **File Manager** prenesi ZIP, ga razširi v `plugins` in preveri natanko `plugins/FamilyHub/Plugin.php`. Izogni se podvojeni mapi `plugins/FamilyHub/FamilyHub`. Pri nadgradnji zamenjaj pregledano mapo vtičnika skladno z načrtom povrnitve. ZIP, SQL, kopij in konfiguracij ne pusti v javni mapi. Ne nalagaj `dev-config.php`, Docker datotek, fixture ali testov.

Kanboard ob nalaganju vtičnika uporabi njegove migracije; uporabnik baze zato potrebuje pravice za ta poseg. Preglej različico v nastavitvah vtičnikov in napake zasebno. Preveri 0.6.0 in nastanek schema10 tudi pri nadgradnji; sam obstoj mape tega ne dokazuje. Jedro Kanboarda ostane nespremenjeno. [Namestitvena pogodba](../../server/plugins/FamilyHub/README.md) opiše privzeto izključene funkcije.

## 5. Vključi Native API za samostojno gostovanje

Obstoječega `config.php` in njegovih nastavitev baze ne nadomesti. Dodaj samo pregledane nove konstante; posamezne konstante definiraj enkrat. Zasebne nastavitve lahko zahteva z `require` iz zaščitene datoteke zunaj vseh spletnih korenov. Ne spreminjaj SQL poverilnic kot stranskega učinka vključitve vtičnika.

```php
define('FAMILYHUB_ENABLE_NATIVE_API', true);
define('FAMILYHUB_ACCOUNT_MODE', 'self_hosted');
define('FAMILYHUB_ENABLE_PROJECT_INVITATIONS', false);
define('FAMILYHUB_ENABLE_FCM', false);
define('FAMILYHUB_TRUSTED_PROXY_IPS', []);
define('FAMILYHUB_CORS_ORIGINS', []);
```

`self_hosted` omogoča pogodbo izbrisa računa; `managed` je ne omogoči. Stara projektna povabila ostanejo izključena, posebej za stare projekte s finančnimi metapodatki. Native prostori niso stari Kanboard projekti.

Neposredni cPanel HTTPS uporablja PHP `HTTPS`. Če TLS zaključuje proxy, v `FAMILYHUB_TRUSTED_PROXY_IPS` vpiši samo preverjene dejanske proxy IP-je; ne zaupaj vsem forwarded glavam. Mobilni odjemalec ne potrebuje CORS. Za spletni odjemalec dodaj samo njegov točen HTTPS izvor (brez poti, wildcarda ali poverilnic), na primer `['https://app.example.invalid']` po zamenjavi z resničnim izvorom. Statična predstavitvena stran sama ni spletni sinhronizacijski odjemalec.

Ne vključi `FAMILYHUB_DEVELOPMENT_MODE`, `FAMILYHUB_DEVELOPMENT_ENVIRONMENT` ali `FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT` na javni namestitvi. Žetonov in gesel ne vpisuj v URL, cron ali odjemalčev privilegirani JSON-RPC račun.

Na staging naslov pošlji neoverjeni POST `capabilities` (to preverjanje ne pošilja skrivnosti):

```sh
curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  --data '{"v":1,"op":"capabilities","params":{}}' \
  'https://STAGING_HOST/KANBOARD_PATH/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub'
```

Ne dodajaj `-L` ali `-k`: nepričakovano preusmeritev in napako TLS popravi. Pričakuj `api=familyhub_native`, `version=1`, `enabled=true`, trajni `serverId` in `features.accountDeletion=true`. Brez SMTP/FCM ostaneta ustrezni zmožnosti izključeni. [Native pogodba](native-api-contract.md) določa preostali odgovor.

Obstoječi lokalni Kanboard uporabnik se prijavi z lastnim geslom/TOTP. Prvi novi FamilyHub račun lahko upravljavec pripravi v **Settings → FamilyHub Bootstrap**: HTTPS, skrbniški POST in CSRF, enkratna koda 15 minut. Po prvem Native računu se bootstrap zapre. CLI `enrollment.php` je alternativa; njegov izhod vsebuje kodo, zato ga nikoli ne pošlji v cron e-pošto ali običajen dnevnik. Javna odprta registracija in zunanji prijavni ponudniki niso podprti.

## 6. Izbirni SMTP in obnovitvene kode

Od ponudnika pridobi gostitelja, vrata, šifriranje in dovoljeni naslov pošiljatelja. V zasebno konfiguracijo dodaj dejanske vrednosti po [predlogi](../../server/examples/account-mail-config.php.example):

```php
define('FAMILYHUB_SMTP_HOST', 'smtp.example.invalid');
define('FAMILYHUB_SMTP_PORT', 465);
define('FAMILYHUB_SMTP_ENCRYPTION', 'ssl');
define('FAMILYHUB_SMTP_FROM', 'sender@example.invalid');
define('FAMILYHUB_SMTP_USERNAME', 'REPLACE_ON_SERVER');
define('FAMILYHUB_SMTP_PASSWORD', 'REPLACE_ON_SERVER');
define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', trim(file_get_contents('/home/ACCOUNT/private/familyhub-account-mail.key')));
```

Ponudnik lahko zahteva 587 in `'tls'` (STARTTLS) namesto 465/`'ssl'`; TLS je preverjen, brez tihega prehoda na plaintext. SMTP poverilnice, `familyhub-account-mail.key` in vse kopije postavi **zunaj vseh document rootov**, tudi korenov dodatnih domen in samega Kanboarda. Predvidi zasebno mapo 0700, datoteke 0600 ter dejansko berljivost spletnega in CLI PHP uporabnika; dovoljenj ne širi na 0777. Ključ je naključnih 32 bajtov, zapisan base64, ločen od FCM ključa. Ustvari ga po izbiri prave poti z zasebnim postopkom brez izpisa vrednosti in brez prepisovanja obstoječega ključa; ta vodič ključev ne ustvarja.

Ključ hrani s šifrirano varnostno kopijo; menjava onemogoči dešifriranje stare čakajoče vrste. Obnovitvene kode imajo ločeno šifrirano vrsto `account-mail.php`, običajna obvestila `delivery.php`. Globalni Kanboard BCC in `mail()` se ne uporabita. E-pošta obvestil je privzeto izključena; varnostna pošta za račun ni odvisna od te preference. Capability `smtp=true` pomeni lokalno veljavno obliko konfiguracije, **ne uspešne dostave** ali pravilnih poverilnic. Preverjanje e-pošte/reset sta brez ločenega ključa izključena; reset potrebuje verificiran naslov.

Na staging uporabi samo sintetičen račun in izrecno določen testni naslov. Preveri actual prejem, TLS, porabo/potek kode, TOTP in preklic starih naprav po resetu. Ne pošiljaj vrste iz obnovljene produkcijske baze. Ob dvoumnem SMTP ACK je možna ponovljena e-pošta. Obstoječa Kanboard Swift knjižnica ni več vzdrževana; prihodnja nadgradnja potrebuje pregled združljivosti.

## 7. cPanel Cron Jobs

Vsako vrstico dodaj kot svoje opravilo v **Cron Jobs**. Za minutni interval nastavi Minute, Hour, Day, Month, Weekday na `*`; v Command vnesi ukaz **brez** začetnega `* * * * *`. Uporabi potrjeni absolutni PHP CLI in Kanboard poti. Prvi zagon preveri ročno na stagingu. [cPanel](https://docs.cpanel.net/cpanel/advanced/cron-jobs/) opozarja na prekrivanje izvajanj; account-mail ima proračun 60 s, push 40 s, DB čakanje pa lahko trajanje podaljša.

```sh
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/reminders.php --limit=100
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/delivery.php --limit=20
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/account-mail.php --limit=20
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/account-deletion-cleanup.php
```

`reminders` ustvari obvestila za aktualne strežniške opomnike. `delivery` dodaj samo ob konfiguriranem SMTP; `account-mail` samo ob SMTP in ločenem account ključu. Čistilni cron zaključi datoteke že potrjenih self-hosted izbrisov; **ne sproža novih uporabniških izbrisov**. Pregleduj števce in exit status. Njegov `pending` zahteva zasebni pregled datotečne shrambe/dovoljenj, ne brisanja vrste.

Izpis so omejeni števci/splošne napake, vendar morebitne PHP zagonske napake lahko razkrijejo poti. Cron e-pošto izključi za ta opravila; če želiš dnevnik, ga postavi v zasebno mapo z omejenimi dovoljenji in hrambo. Po preverjanju lahko ukazu dodaš `>/dev/null 2>&1`, vendar potem neuspeh nadzoruj ločeno. Ne dodajaj gesel, enrollment ali reset kod v ukaz ali dnevnik. Preveri dejanski interval in zakasnitev; cron ni zagotovilo takojšnje dostave. Leases/ponovitve omejijo podvajanje dela, ne zagotavljajo exactly-once prikaza sporočil.

Za zmanjšanje prekrivanja je možen potrjeni `flock -n` z zasebno datoteko zaklepa za vsak worker; njegova prisotnost in absolutna pot na tem gostovanju še nista potrjeni. Če workerji trajajo dlje od minute, najprej preveri gostovanje/interval, ne odstranjuj zaščit v vtičniku. Obstoječega core Kanboard crona ne nadomesti z novimi ukazi.

## 8. FCM je ločen, izbirni korak

Za javno mobilno kandidatko mora Firebase registracija uporabljati **`si.triparna.jivie`** za Android in iOS. Strežnik, Android ter iOS morajo uporabljati **isti Firebase projekt**; naključen drugi projekt lastnega strežnika ne more pošiljati v to nespremenjeno kandidatko. Lastnikom samostojnih strežnikov ne deli zasebnega ključa osrednjega projekta. Splošen push posrednik še ni izveden; ne obljubljaj poljubnih self-hosted push povezav. Glej [konfiguracijo obvestil](../NOTIFICATION_SETUP.md).

Ko ima upravljavec dejansko dovoljen projekt, omejeno storitveno identiteto za FCM HTTP v1, omogočen API, preverjen APNs in ustrezno mobilno konfiguracijo, uporabi [FCM predlogo](../../server/examples/fcm-config.php.example):

```php
define('FAMILYHUB_ENABLE_FCM', true);
define('FAMILYHUB_PUBLIC_ROOT', '/home/ACCOUNT/public_html');
define('FAMILYHUB_FCM_PROJECT_ID', 'YOUR_FIREBASE_PROJECT_ID');
define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE', '/home/ACCOUNT/private/firebase-service-account.json');
define('FAMILYHUB_PUSH_KEY_BASE64', trim(file_get_contents('/home/ACCOUNT/private/familyhub-push.key')));
```

To nadomesti prejšnji `FAMILYHUB_ENABLE_FCM=false`, ne doda druge definicije. `FAMILYHUB_PUBLIC_ROOT` mora obstajati in kazati dejanski javni koren; dodatne javne korene preveri posebej. JSON in ločeni naključni 32-bajtni ključ morata biti zunaj **vseh** javnih korenov in Kanboarda. Service-account JSON in APNs `.p8` nista klientovi datoteki. Mobilni javni konfiguracijski datoteki ne vsebujeta teh zasebnih ključev.

```sh
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/push-preflight.php
/opt/cpanel/ea-php84/root/usr/bin/php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/push.php --limit=20
```

Preflight je **brez omrežja**, `providerVerified=false`; ne dokazuje Google IAM, APNs, resnične dostave ali prikaza. Drugi ukaz je izbirno minutno cron opravilo po fizičnem preizkusu. Opozorila so generične reference na shranjeno obvestilo; ob odpiranju aplikacija ponovno preveri račun/prostor/pravice. Že sprejetega opozorila ni mogoče odpoklicati, dvoumen ACK lahko podvoji prikaz. Lokalni telefonski opomniki delujejo ločeno od FCM in strežniškega crona.

## 9. Preverjanje pred produkcijo in omejitve

Na stagingu preveri prijavo s TOTP, povabilo/registracijo, dve napravi, sočasne spremembe/konflikt, offline zapis in ponovno povezavo, odvzem članstva ter ločeno finančno pravico. Prijava v Jivie sama ne vključi prenosa osebnih podatkov; soglasje je izrecno. Kanboard splet ne ureja novih Native tabel.

Za izbris uporabi samo sintetičen račun in svež pregled, ločene izbire za naslednika/ohranitev struktur ter ponovno overitev. Preveri dejansko odstranitev `users`, stari bearer/web login, izid po izgubljenem odgovoru in datotečni `cleanupPending`. Spletna pot za uporabnika istega strežnika je:

```text
https://YOUR_HOST/KANBOARD_PATH/index.php?controller=AccountDeletionController&action=index&plugin=FamilyHub
```

Javna Jivie stran usmeri na ta naslov; gesla zbira samo uporabnikov strežnik. [Pogodba izbrisa](account-deletion-contract.md) izrecno opozarja: že avtorizirana stara Kanboard spletna create zahteva lahko po izbrisu ustvari dangling legacy zapis. Jedro nima Native ponovnega preverjanja identitete po čakanju. Tudi urejanja izbrisanega člana v ohranjenih tujih zapisih ostanejo; tretji vtičniki, arhivi, kopije in poslana pošta niso zajeti. Produkcijskega izbrisa zato ne predstavljaj kot popoln izbris vseh UGC ali potrditev skladnosti trgovin.

Šele po uspešnem stagingu, obnovi kopije, dejanskem cron/TLS preizkusu in ločenem dogovoru za produkcijo ponovi postopek na živem strežniku v dogovorjenem oknu. Zabeleži datum, nameščeni checksum, različice, migracijo, capabilities in izvedene preizkuse brez skrivnosti. Ta vodič in pripravljeni ZIP sama po sebi ne pomenita namestitve ali dovoljenja za brisanje produkcijskih računov.

## 10. Sveža testna poddomena — dejanski napredek 7. oktobra 2026

Uporabnik je izrecno dovolil poseg v cPanel za **novo ločeno testno poddomeno in svež Kanboard**, brez prenosa starih podatkov. Glavni agent je neposredno preveril:

- ustvarjena domena **`jivie-test.triparna.si`**, document root **`/home/tripar13/jivie-test.triparna.si`**;
- prikazani obstoječi wildcard certifikat pokriva ta naslov, poteče **18. novembra 2026**; `www.jivie-test.triparna.si` še ni pokrit, AutoSSL je v teku. Uporabi naslov brez `www`; prikaz v SSL Status sam ni celoten preizkus javne povezave TLS;
- uporabnik je **dejansko namestil Softaculous Kanboard 1.2.54**, zasebno določil skrbniško geslo in se prijavil; nova baza je `tripar13_jivietest`, gonilnik `mysql`, samodejne nadgradnje so izključene;
- preverjeni spletni sistem poroča PHP **8.4.26 / LiteSpeed** in bazo **10.11.19-MariaDB-cll-lve-log**. Application URL je `https://jivie-test.triparna.si/`, časovni pas `Europe/Ljubljana`, datum `d.m.Y`. Namestitev FamilyHub, capabilities in cron dokazi so spodaj v razdelku 11.

Stare aplikacije, baze, datoteke in računi s tem postopkom niso bili preneseni ali izbrisani. Za Softaculous namestitev uporabi že pregledani 61-datotečni FamilyHub ZIP iz razdelka 4. Lokalni **rezervni** paket `build/releases/cpanel-fresh/kanboard-1.2.54-FamilyHub-0.6.0-fresh-fallback.zip` se ne nalaga čez uspešno Softaculous namestitev.

### Dodatek konfiguracije in zasebna podatkovna mapa

[Dodatek konfiguracije za svež Softaculous](../../server/examples/cpanel-familyhub-config.php.example) vsebuje samo `DATA_DIR` in FamilyHub nastavitve; **ni zamenjava celotnega `config.php`**. Izvedeni zasebni cilj je `/home/tripar13/private/jivie-test/data`, zunaj pregledanih document rootov. Spodaj ostaja splošni postopek; konkretna izvedba z varovanim v3 skriptom je dokumentirana v razdelku 11.

Po uspešno potrjeni sveži namestitvi, pred prvo uporabniško uporabo:

1. Omeji dostop do te poddomene med nastavitvami; dokončaj začetno skrbniško geslo brez javno uporabnega `admin/admin`. Ohrani zaščiteno kopijo novega `config.php`; ne izpisuj nastavitev baze.
2. Preveri vse document roote računa. Ustvari nov zasebni nadrejeni imenik zunaj njih, primer `/home/tripar13/private/jivie-test`, z dovoljenji, primernimi dejanskemu PHP uporabniku (običajno 0700). Preveri tudi `open_basedir`; sam obstoj imenika ne dokazuje dostopa spletnega PHP.
3. S File Manager **Copy** kopiraj samo `data` te **sveže** namestitve v novi zasebni nadrejeni imenik. Končni cilj mora biti natanko `.../jivie-test/data`, ne `.../data/data`. Ohranijo se skrite zaščitne datoteke in morebitna vsebina sveže namestitve. Starih podatkov drugega Kanboarda ne kopiraj. Pred preklopom preveri kopijo in PHP zapisovanje v ciljno mapo; `files` in `cache` morata biti dosegljiva ter zapisljiva. Ne uporabljaj 0777.
4. V obstoječi novi `config.php` ohrani vse dejanske `DB_*` nastavitve. Dodaj `DATA_DIR` ali popravi njegovo **eno obstoječo definicijo**, nato FamilyHub konstante iz predloge. Ne prilepi drugega `<?php` v odprto PHP datoteko in ne kopiraj generične rezervne DB predloge preko Softaculous konfiguracije. Core `FILES_DIR`, `CACHE_DIR`, `LOG_FILE`, `DB_FILENAME` privzeto izhajajo iz `DATA_DIR`; če jih Softaculous konfiguracija že definira, zasebno preglej in uskladi dejanske poti, brez spremembe baze.
5. V prvi fazi brez SMTP preveri PHP sintakso, HTTPS prijavo in `capabilities`; pričakuj Native `enabled=true`, `accountDeletion=true`, `smtp=false`, `emailVerification=false`, `passwordReset=false`, `externalPush=false`. V tej prvi fazi SMTP/FCM ključi še niso ustvarjeni ali prebrani. Kasnejši dejanski vklop SMTP na testni poddomeni vodi razdelek 11. Odsotnost `FAMILYHUB_SMTP_*` nastavitve izključi dostavo vtičnika; ne obstaja poseben `FAMILYHUB_ENABLE_SMTP` switch.
6. Preveri neposreden HTTP dostop do javnega `data/`: mora biti zavrnjen. Ohranjen izvorni `data/.htaccess` uporablja Apache `Require all denied`; varna rešitev je tudi uspešen zasebni `DATA_DIR`. Če deny ne deluje, omejitve strežnika odpravi pred uporabo. Kopije konfiguracije/SQL/ZIP nikoli ne hrani v javnem document rootu.
7. Izvorne podatkovne mape ne odstrani pred potrjenim zasebnim preklopom in kopijo. Pri napaki povrni konfiguracijo te nove namestitve; ne posegaj v stare baze. Cron `reminders.php` in `account-deletion-cleanup.php` uvedi šele po dejanskem preverjanju. SMTP/push workerjev ob izključenih kanalih ne dodajaj.

### Lokalni izvori rezervnega paketa

Uradni [GitHub release v1.2.54](https://github.com/kanboard/kanboard/releases/tag/v1.2.54) nima ločenih binarnih prilog; prenesen je uradni ZIP označene izdaje prek GitHub API, commit **`9ce6a5edc5b646ef15780cb445bc6d2c39d9898f`**. Arhiv že vsebuje `vendor/autoload.php` in vključene odvisnosti; Composer na gostovanju ni potreben. Lokalne vsote dokazujejo zajete bajte, ne dodatnega podpisa ali neodvisne objavljene vendor kontrolne vsote:

| Lokalni paket | SHA256 | Preverjeno |
| --- | --- | --- |
| `build/releases/cpanel-fresh/kanboard-v1.2.54-upstream.zip` | `7ff2e9f0c7f1003338c072e6af890f5abfba505c9f40dcc560f0d45c3b3761a7` | GitHub HTTPS izvor, CRC, vgrajeni tag/commit, potrebni bootstrap in odvisnosti |
| `build/releases/FamilyHub-0.6.0-source.zip` | `433d45fbb8c7aa350e92beab812a7b9e7ffc1ed07bdae5d003fa1fce4e9624c0` | Vseh 61 dovoljenih vnosov, CRC, enakost s pregledanimi izvori, brez dodatnih datotek |
| `build/releases/cpanel-fresh/kanboard-1.2.54-FamilyHub-0.6.0-fresh-fallback.zip` | `c33d72a893b0c19c3bdbc812c97dd012000527f037b2a8274290ca099e6fa4e0` | 2157 datotek / 4403720 bajtov, CRC in bajtna enakost vsakega vnosa; `index.php` v korenu, vtičnik `plugins/FamilyHub/Plugin.php` |

Rezervni paket ohrani core/vendored kode in licence; izloči samo `CONTRIBUTING.md`, `ChangeLog` in tri Docker Compose primere. Ne vsebuje živega `config.php`, baz, skrivnosti ali starih podatkov. [Rezervna predloga](../../server/examples/cpanel-fresh-config.php.example) potrebuje pregledane zasebne poti in zasebno novo DB konfiguracijo, zato ni avtomatična namestitev. Izvor/inventar z SHA256 vsake datoteke sta v `build/releases/cpanel-fresh/kanboard-upstream-origin.json` in `fresh-fallback-manifest.json`. Noben lokalni prenos ali sestava ZIP v tem odseku ni dokaz strežniške namestitve.


## 11. Izvedena namestitev in dejanski strežniški preizkusi

Glavni agent je 7. oktobra 2026 po uporabnikovem dovoljenju izvedel in preveril **novo testno namestitev**, brez poseganja v stari Kanboard:

| Področje | Dejanski dokaz |
| --- | --- |
| PHP CLI | `/opt/alt/php84/usr/bin/php`, **PHP 8.4.26**; `pdo_mysql`, `mbstring`, `openssl`, `curl`, `gd`, `dom`, `SimpleXML`, `zip` in tokenizer potrjeni; CLI `open_basedir` je prazen. |
| Namestitev vtičnika | FamilyHub **0.6.0** prikazan v Kanboard spletnem UI; dejanska tabela `plugin_schema_versions` potrdi shemo **10**. Uporabljen pregledani 61-datotečni ZIP s SHA256 iz razdelka 10. |
| Varovano nameščanje | Izveden v3 `deploy-cpanel-fresh-v3.php`, SHA256 `cabc88cd7e350037ecbbd574c2074b9c6be2033f4f83c49a2b23de98980fe266`; preverjanje, zasebna priprava, PHP lint in aktivacija. Izvor je [deploy-cpanel-fresh.php](../../server/scripts/deploy-cpanel-fresh.php). |
| Podatkovna mapa | `DATA_DIR=/home/tripar13/private/jivie-test/data`. Sveža Softaculous namestitev še ni imela `files` in `cache`; oba imenika sta bila ustvarjena zasebno z **0700**; DATA_DIR/FILES_DIR/CACHE_DIR so nato preverjeno zapisljivi. Izvorni javni `data` ostane ohranjen; stare vsebine druge namestitve niso prenesene. |
| Native HTTPS | `enabled=true`, `accountDeletion=true`, `privateSync=true`, `emailVerification=true`, `passwordReset=true`, `smtp=true`; `externalPush=false`, `legacyProjectSharing=false`. `serverId=95c11fe0-916c-48be-a3f6-999732846266`. To je dokaz zmožnosti/konfiguracije, ne fizičnih uporabniških tokov. |
| HTTP/TLS | HTTP preusmeri **301** na HTTPS. Neposredna dostopa do `data/` in `data/.htaccess` vrneta **302** na prijavo brez vrnjenih bajtov teh datotek. To **ni opaženi odgovor 403** in ne dokazuje, kakšen bi bil odgovor po morebitni odstranitvi prijavne zaščite. Aktivni podatki so v zasebnem `DATA_DIR`. |

### SMTP: priprava, avtentikacija in meje dokaza

Uporabnik je ustvaril predal **`jivie-test@triparna.si`** in obstoječe geslo vnesel zasebno v `/home/tripar13/private/jivie-test/smtp-password.txt` z dovoljenji **0600**. Geslo ni v izvoru, ZIP, ukazu ali dokumentaciji. cPanel Connect Devices je potrdil **`mail.triparna.si:465` / SSL**, z zahtevano avtentikacijo.

Preizkušeni helper je ohranjen nespremenjen kot [setup-cpanel-smtp.php](../../server/scripts/setup-cpanel-smtp.php), SHA256 **`84c4da136bce3f73791954f30198e23b19b74f49c2ec140cb84b64108471eac5`**. Strežniški `--prepare`, oba PHP lint pregleda in `--activate` so uspešni. `--prepare` ustvari ločen naključni 32-bajtni base64 ključ `account-mail.key` in zasebne kandidate; SMTP se vključi šele z ločeno aktivacijo. Helper preverja samo metapodatke datoteke z geslom, ničesar ne pošilja in ne vključuje Kanboardovega bootstrap/migracijskega postopka. Njegovo začetno varovalo zavrne prazno datoteko brez ustvarjanja ključa.

Dejanski `NativeVerifiedSmtp` **start/stop** je uspešen z avtentikacijo, preverjenim TLS in preverjanjem imena/certifikata ponudnika. **Nobeno sporočilo še ni bilo poslano.** To potrjuje transportno povezavo in poverilnico, ne sprejema sporočila, njegovega prejemanja ali končnega account-mail/reset toka. Tak preizkus potrebuje izrecno določenega prejemnika in testni račun. FCM ostane izključen; priprava SMTP ne potrjuje APNs/FCM dostave.

Po dodani SMTP konfiguraciji začetni deployment helper pri ponovnem `--check` pričakovano zavrne **`feature_config_changed`**, ker se preverjena osnovna datoteka zdaj namenoma razlikuje za SMTP `require`. Prvotnega helperja ne uporabljaj za obnovo osnovne konfiguracije in ne rahljaj njegovega SHA/konfiguracijskega varovala. Nadaljnjo konfiguracijo preglej kot ločeno spremembo; zasebne varnostne kopije ohrani.

### Ročni workerji in dejanski cron

Vsi štirje ročni CLI zagoni so uspešni s praznimi vrstami in ničelnimi števci: **reminders**, **account-deletion-cleanup**, **account-mail** in **delivery**. To ne ustvari uporabniškega izbrisa ali e-pošte.

V cPanel so dodana opravila:

| Worker | Interval | Dejanski dosedanji dokaz |
| --- | --- | --- |
| `reminders.php --limit=100` | Vsako minuto | Prvi periodični zagon **22:25 +02:00** je zapisal ničelne števce. |
| `account-mail.php --limit=20` | Vsako minuto | Prvi periodični zagon **22:25 +02:00** je zapisal ničelne števce. |
| `delivery.php --limit=20` | Vsako minuto | Prvi periodični zagon **22:25 +02:00** je zapisal ničelne števce. |
| `account-deletion-cleanup.php` | Vsakih pet minut (`*/5`) | Ročni in prvi opaženi periodični zagon **22:30:01 +02:00** uspešna, `complete=0`, `pending=0`. |

Vsako opravilo uporablja potrjeni `/opt/alt/php84/usr/bin/php`, `umask 077` in prepisuje svoj zasebni `*-status.json`, zato ne ustvarja neomejenega dnevnika ali cron e-pošte. Statusne datoteke vsebujejo omejene števce, brez gesel, ključev ali vsebine uporabniških zapisov. Obstoječi dnevni Softaculous cron je ohranjen. Opazovanje prazne vrste potrjuje časovno izvajanje, ne obdelave dejanskega opomnika, datotečnega pending izbrisa ali dostave sporočila.

Lokalni izolirani preizkus **nespremenjenega v3** z dejanskim PHP tokenizerjem je preveril dejanski izraz `__DIR__.DIRECTORY_SEPARATOR.'data'`, relativne `LOG_FILE`/`CACHE_DIR`/`FILES_DIR`, ignoriranje komentiranih primerov, ohranitev DB nastavitev in idempotentno pripravo/aktivacijo. SMTP helper je neodvisno preveril prazno datoteko, zasebne kandidate, izključen SMTP po pripravi, 32-bajtni ključ in ponovljivo aktivacijo, brez oddaje sporočila. Ti sintetični dokazi se ne štejejo za fizični mobilni ali realni e-poštni tok. Končne uporabniške omejitve iz razdelka 9 ostanejo veljavne.

Dodatno preverjeni zavrnitvi Native API: `scopes.list` brez seje vrne **401 auth_required**, nezaupanja vreden Origin vrne **403 origin_not_allowed**. Dokazilo je `build/qa/garden-release/cpanel-native-api-evidence.json`.

Končni pregled ob **22:30:01 +02:00** potrdi vse štiri periodične statuse z ničelnimi števci in dovoljenji 0600. Dokaz: `build/qa/garden-release/cpanel-cron-executed.png`. Aktivna migracija je **10**, vse tri zasebne podatkovne poti pa so zapisljive.
