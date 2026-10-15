# FamilyHub 0.14.0 / schema18 — postopek in dejanska nadgradnja

15.oktober: produkcija/test1 sta pozneje prejela code-only0.14.1 popravek privzetega zvoka; schema18 ostane. Vse shranjene nastavitve so ohranjene. [Dokazi](../release/DEFAULT_SOUND_1_9_1.md#familyhub-in-živi-namestitvi).

**Produkcija `jivie.triparna.si` in pregledni test1 `jivie-test.triparna.si`
sta 15. oktobra 2026 dejansko nadgrajena na FamilyHub 0.14.0 / schema 18 in
ponovno odprta.** Na obeh sta izvirna crona obnovljena; podatki, ločeni
identiteti, konfiguracije, SMTP in FCM so ohranjeni. Vsako gostovanje je
uporabilo svoj sveži zajem, kopijo, resnično izolirano obnovo in zapečatene
vhodne hashe. **Test2 ostaja nespremenjen in zunaj tega obsega.**

## Potrjena produkcijska nadgradnja — 15. oktober 2026

Nadgradnja je uporabila novi zasebni delovni imenik:

`/home/tripar13/private/jivie-production/upgrade-0.14.0-20261015-032315`.

Sveži zajem ob **03:22:28 UTC** (05:22:28 CEST) je preveril dejansko
produkcijsko identiteto `ad56910f-ca2e-41ee-af0d-3f18081497cf`, staro schema 17,
konfiguracije, ključe, cron in stari izvor. Po varovanem ustavljanju petih
ciljnih delavcev, preverjenem HTTPS 503 ter dejanskem praznjenju procesov je
nastala **nova kopija ob 03:25:40 UTC** (05:25:40 CEST). To je ločen zajem po
predhodni prekinitvi; starega arhiva ali starega obnovitvenega dokaza nismo
uporabili kot podlago za migracijo.

Sveži ZIP ima **58.329 bajtov in 17 vnosov**, zajema vseh **92 tabel s 322
zgodovinskimi vrsticami**, dve datoteki DATA ter dva podatkovna imenika.
Vključuje tri Native račune in štiri registrirane naprave. Njegov SHA256 je:

`44eb4355a6f52303d14e345e9823f807a307b4bca4ec6a9d313add567e4e72ef`.

Ta točni arhiv je bil dejansko obnovljen v sveži **MariaDB 10.11.19**, z
`network=none`, brez objavljenih vrat in host bindov ter samo z anonimnim
MySQL volumnom. Preverjena je vsaka vrstica, CREATE definicija, tip stolpca,
podatkovna datoteka in prazen imenik ter konfiguracijski, HTTPS, cron in
SMTP/FCM ključni hash. Ista identiteta in schema 17 sta potrjeni tudi v
obnovljeni bazi. SQL SHA256 je
`931a8815edbef9ec1a7d4866393c41c5b34c046b4035e707e5d727f9a8fdaae1`.

Dejanski dokaz je zunaj Git:
`/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-production-20261015-fresh1/restore-proof.json`.
Dokaz je bil shranjen in ponovno prebran pred odstranitvijo obnovitvenega
vsebnika. Izvirni arhiv ostane ohranjen z istim hashem; pri obnovi aplikacija
in delavci niso bili zagnani, živa baza pa ni bila uporabljena.

Po vrnitvi tega dokaza v novi zasebni WORK so **stage, apply, verify in release
uspešno zaključeni**. Nameščenih je 101 preverjenih izvornih datotek iz
zapečatenega paketa 0.14.0 s SHA256
`e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743`.
Migracija doda samo štiri pregledane stolpce in novo prazno
`familyhub_scope_deletion_files`. Vsi stari stolpci, vrstice, definicije po
odstranitvi dovoljenih novih polj, gesla, računi, naprave in datoteke so
preverjeno ohranjeni. Samo FamilyHub schema metadata se spremeni 17 → 18.
Jedro, izvirni HTTPS, SMTP/FCM konfiguracije in ključi ter celotni cron ostanejo
nespremenjeni; stari izvor in zasebne kopije so ohranjeni.

Končni [produkcijski checkpoint](../../build/qa/upgrade-release-20261014/production-release-checkpoint.json)
izrecno potrdi `phase=released`, `apiPaused=false`, `workerCronRestored=true`
in vsa preverjanja ohranitve. Prisoten je tudi
[posnetek dejanske potrditve](../../build/qa/upgrade-release-20261014/production-release-confirmed.jpg).

Dejanski javni Native capabilities POST je po release vrnil **HTTP 200**, isto
identiteto in `enabled=true`. [Shranjeni odgovor](../../build/qa/upgrade-release-20261014/production-capabilities-014.json)
potrjuje lifecycle pogodbo 1, vrtni dokument 3, tablo Idejnika 2, relativne
opomnike 2, record6/sync6 ter push prikaz 2. Funkciji `smtp` in `externalPush`
ostaneta vključeni. To potrjuje dostopnost in zmožnosti novega strežnika;
ni nov dokaz fizične dostave obvestila, odjemalčeve namestitve ali trgovinske
objave. Pregledni test1 je bil nato nadgrajen v svojem ločenem postopku,
opisanem spodaj; test2 ni vključen.

## Potrjena nadgradnja preglednega test1 — 15. oktober 2026

Test1 je uporabil svoj novi zasebni WORK:

`/home/tripar13/private/jivie-test/upgrade-0.14.0-20261015-033029`.

Sveži zajem ob **03:29:58 UTC** (05:29:58 CEST) je potrdil identiteto
`95c11fe0-916c-48be-a3f6-999732846266`, staro schema 17 in njegove lastne
konfiguracije, ključe, izvor in cron. Po ustavitvi ciljnih delavcev,
preverjenem HTTPS 503 in dejanskem praznjenju procesov je nastala kopija ob
**03:32:37 UTC** (05:32:37 CEST).

Arhiv ima **74.766 bajtov in 24 vnosov**, vseh **92 tabel s 313 zgodovinskimi
vrsticami**, dve datoteki DATA ter dva podatkovna imenika. Ohranil je tri
Native račune in osem naprav. Njegov SHA256 je:

`823a868178cef34769654f2b00c3109b3d3640adb2ac49fd211e60be1eaa4744`.

Ta točni test1 arhiv je bil dejansko obnovljen v drugi sveži **MariaDB
10.11.19**, z `network=none`, brez objavljenih vrat in host bindov, samo z
anonimnim MySQL volumnom. Potrjeni so vsaka vrstica, CREATE definicija in tip
stolpca, datoteke, prazni imeniki, konfiguracije, HTTPS, cron ter dostavni
ključi. Obnovljena baza je ohranila isti serverId in schema 17; aplikacija in
delavci niso bili zagnani, živo gostovanje pri obnovi ni bilo uporabljeno.
SQL SHA256 je
`22eda445d062b2fe89cbc87bdf723b12595f0459710bc80336f5bb7da48c97b0`.

Dostopni dokaz je zunaj Git:
`/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-test1-20261015-fresh1/restore-proof.json`.
Shranjevanje in ponovno branje dokaza sta bila potrjena pred odstranitvijo
obnovitvenega vsebnika. Pri obnovi test1 nismo uporabili produkcijskega
arhiva ali produkcijskega dokaza; test1 kopija ostaja ohranjena z istim hashem.

Po vrnitvi test1 dokaza v njegov WORK so **stage, apply, verify in release
uspešno zaključeni**. Natanko štirje novi stolpci in ena nova prazna tabela
`familyhub_scope_deletion_files` razširijo schema 17 na 18. Nameščenih je
istih 101 preverjenih izvornih datotek paketa 0.14.0. Vsa zgodovinska vsebina,
definicije po odstranitvi dovoljenih dodatkov, računi, gesla, naprave in
podatkovne datoteke so ohranjeni. Jedro, HTTPS, SMTP/FCM nastavitve in ključi
ter celotni originalni cron ostanejo nespremenjeni.

[Test1 release checkpoint](../../build/qa/upgrade-release-20261014/test1-release-checkpoint.json)
potrdi `phase=released`, `apiPaused=false`, `workerCronRestored=true` in vsa
varovala ohranitve. [Posnetek dejanske potrditve](../../build/qa/upgrade-release-20261014/test1-release-confirmed.jpg)
je ločen od produkcijskega dokaza.

Javni Native capabilities POST je po release vrnil **HTTP 200**, isto test1
identiteto in `enabled=true`. [Shranjeni test1 odgovor](../../build/qa/upgrade-release-20261014/test1-capabilities-014.json)
potrdi lifecycle pogodbo 1, vrtni dokument 3, tablo Idejnika 2, relativne
opomnike 2, record6/sync6 in push prikaz 2. SMTP in externalPush sta še vedno
vključena. To je dokaz novega preglednega gostovanja, ne fizične namestitve,
nove dostave obvestila, vpisa preglednega gesla ali javne trgovinske oddaje.
Test2 je še naprej zunaj tega posega.

## Pregledani pomagači in postopek 17 → 18

Spodaj je postopek že izvedenih nadgradenj. Po uspešnem prehodu na schema 18
starih enkratnih pomagačev za schema 17 ne ponavljaj; prihodnje vzdrževalno
delo potrebuje kopijo in preverjanje dejanskega novega stanja.

Pomagači so v [server/scripts/upgrade-0.14.0](../../server/scripts/upgrade-0.14.0).
Ne uporabljajo starih konfiguracijskih hashov iz SMTP/FCM namestitve in ne
spreminjajo njenih varoval. `capture.php` prebere samo trenutno konfiguracijo,
identiteto in hashe; aplikacije ali dostavnih delavcev ne zažene. Zajame vse
vključene konfiguracije, zasebne datoteke na korenu ciljnega zasebnega imenika,
FCM service-account datoteko, semantični hash vseh FamilyHub konstant in celotni
cron. Skrivnosti ostanejo v datotekah, izpis vsebuje samo hashe in poti.

`seal.py` uporabi svež zajem (največ6ur), preverjeni končni0.14.0 ZIP in
96-datotečni gostovani0.13.0 izvorni manifest. PHP/LICENSE baseline preveri še
proti nespremenljivemu javnemu `v0.13.0` commit
`7571d1be1554255f6b702e6fe895af2b3b9ee81a`. Javni README in opis pogodbe izbrisa
sta bila namenoma drugače uredniško pripravljena; gostovani96manifest ohrani
njuna prvotna hasha. Novi ZIP mora vsebovati natanko eksplicitni aktualni
`tools/plugin_release/source_manifest.json` in osem eksplicitnih javnih pogodb (tudi novo scope-lifecycle pogodbo); ima samo regularne datoteke z veljavnimCRC, brez dodatnih datotek.
Vsak nov bajt mora biti enak zamrznjenemu izvornemu/javnemu dokumentu;
`Plugin.php` mora pokazati0.14.0. Zapečatena mapa vsebuje lastni
`deployment.php`, oba vira v manifestu in nespremenljiv paket. Vse zapečatene
vhodne datoteke so0600 in mapa0700 zunajGit; ciljna mapa je enkratna.

## Sveži vhodni podatki

Na prijavljenem cPanel terminalu namesti samo pregledani `capture.php` v zasebno
mapo. Vnaprej preveri, da ta in ciljne zasebne poti niso pod nobenim document
rootom. Ne kopiraj produkcijskegaSQL, konfiguracij ali ključev v repozitorij.
Za vsak strežnik ločeno:

```sh
umask 077
mkdir -m 700 /home/tripar13/private/CILJ/capture-0.14.0-FRESH
/bin/crontab -l > /home/tripar13/private/CILJ/capture-0.14.0-FRESH/cron.capture
/opt/alt/php84/usr/bin/php /home/tripar13/private/CILJ/capture.php production /home/tripar13/private/CILJ/capture-0.14.0-FRESH/cron.capture > /home/tripar13/private/CILJ/capture-0.14.0-FRESH/capture.json
```

`CILJ` je `jivie-production`; za pregledni strežnik je `jivie-test` in profil
`test1`; `FRESH` zamenjaj s svežim enkratnim identifikatorjem. Captureizhod
hrani v tej podmapi: output na korenuBASE bi krožno postal eden od vhodnih
config/key hashov in bi bil pravilno zavrnjen ob poznejšem preverjanju. Zajem mora dejansko potrditi MariaDB10.11.19, schema17, pravi serverId,
nativeAPI/self_hosted in izključena stara projektna povabila. Prenesi samo ta
zasebni zajem v svežo lokalno zasebno mapo zunajGit. Končni ZIP pripravi po
izdajnem preverjanju aktualnega izvora, nato:

```sh
python3 server/scripts/upgrade-0.14.0/seal.py /ZASEBNO/capture.json /ZASEBNO/FamilyHub-0.14.0-source.zip /ZASEBNO/sealed-production
```

Izpis pove točno `hostWork`, SHA paketa in SHA manifesta. Mapo prenesi v točno
navedeni novi `hostWork`;0700imeniki/0600datoteke. Ne spreminjaj njenih pinov.
Primeri spodaj uporabljajo `WORK` samo kot mesto za dejansko izpisano absolutno
pot, ne kot privzeto ali staro pot. `operate.sh` poženi prek `sh`.

## Kopija in resnična obnova pred DDL

```sh
sh WORK/operate.sh WORK prepare
sh WORK/operate.sh WORK pause
```

Prepare primerja konfiguracije/ključe/izvor/GD/schema in celotni originalni cron.
Ustvari pause kandidat za natanko pet obstoječih ciljnih delavcev: reminders,
delivery, account-mail, account-deletion-cleanup, push. Vse druge vrstice
ostanejo bajtno enake. Pause uporabi kandidat in preveri dejanskiTLS HTTP503.
Zapri urejevalne odjemalce. **Počakaj najmanj65dejanskih sekund.**
`operate.sh export` zahteva svež procesni drain, isti pausedcron in isto
vzdrževanje; z bralnimi zaklepi vsehInnoDB tabel zajame vsakCREATE/vsako vrstico,
celotnoDATA drevo s praznimi imeniki, root/private konfiguracije, ključe in
celotni originalni cron. Dva SQL in datotečna inventarja morata biti enaka.

```sh
sh WORK/operate.sh WORK export
```

Prenesi izpisani arhiv v novo lokalno0700mapo zunajGit, datoteka0600; preveri
izpisaniSHA. Ustvari **svežo** obnovitveno instanco brez omrežja, vrat ali host
bindov (samo anonimni MySQLvolume):

```sh
docker run -d --name jivie-restore-014-production --network none -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes mariadb:10.11.19
python3 server/scripts/upgrade-0.14.0/restore-verify.py /ZASEBNO/Lifecycle18-private-backup.zip --sha256 SHA --container jivie-restore-014-production --private-root /ZASEBNO
```

MariaDB mora biti pripravljena, popolnoma prazna in10.11.19. Preverjevalnik
primerja vsako vrstico, vsakCREATE/column/type, datoteko, prazen imenik,
konfiguracijo, credential/key incronhash. Ne zaženePHP/aplikacije ali delavcev
in ne uporablja žive baze. Dejanski `restore-proof.json` vrni vWORK kot0600;
nikoli ga ne napiši ročno. Arhiv mora biti star manj kot6ur.

## Stage, apply, preverjanje in release

```sh
sh WORK/operate.sh WORK stage ARCHIVE SHA
sh WORK/operate.sh WORK apply ARCHIVE SHA
sh WORK/operate.sh WORK verify ARCHIVE SHA
sh WORK/operate.sh WORK release SHA
```

Stage primerja vse žive vrstice/datoteke z resnično obnovljeno kopijo, kopira
stari96izvor zasebno in pripravi novi izvor. Apply zavrne ponavljanje, zastarele
vire/proof, spremembeSQL/datotek/cron/ključa ali prezgodnji drain. Zažene samo
`version_18`, brez bootstrap aplikacije. Preveri natanko:

- `familyhub_scopes.deleted_at`: NULL pri vseh zgodovinskih vrsticah;
- `familyhub_push_registrations.notification_format`:1 pri vseh starih napravah;
- `familyhub_reminders.schedule_mode='absolute'` in `offset_minutes=NULL`;
- eno novo prazno `familyhub_scope_deletion_files` s pregledanimi stolpci/ključem;
- istoSQL zgodovino v vseh starih stolpcih, stareCREATE definicije po odstranitvi
  natanko dovoljenih novih definicij, isti računi/gesla/seje/serverId/podatki;
- samo metadata `familyhub`17→18, druge metadata vrstice ostanejo enake;
- iste config/SMTP/FCM/constants/ključe, DATA, jedro in druge vtičnike.

Celotni stari vtičnik ostane zasebno; starih kopij ne prepiše. Release najprej
ponovi preverjanje ob še ustavljenih delavcih inHTTP503, nato atomarno vrne
izvirniHTTPS. **Šele nato** vrne natanko originalnicron in ločeno potrdi
zaključek. Tako delavec ne more spremeniti vrste med zadnjim primerjanjem in
odprtjemAPI. `http-release-checkpoint.json` potrjujeHTTPodprtje ob pausedcron;
`release-checkpoint.json` nastane šele po preverjeni obnovi originalnegacrona.
Spletni capabilities/preverjanje novega odjemalca opravimo ločeno po release.
Ni preverjene fizične naprave ali dostave samo zaradi uspeha teh pomagačev.

Ob napaki ohrani vzdrževanje, vse private izvirnike/state in podatke. Če je
HTTPžeodprt, vendar cronrestoration ni uspela, ohrani state
`released-http-workers-paused` in preglej točno napako; ne ponavljajDDL ali
slepo spreminjajcron. StareSQLkopije ne uvažaj neposredno na živo gostovanje.
Povrnitev poALTER zahteva pregledan obnovitveni postopek in ohranitev vseh
novih zapisov, ki bi nastali po odprtjuAPI.

## Lokalni dokazi

`python3 server/scripts/upgrade-0.14.0/fixture-test.py` uporablja napolnjeni
sintetični schema17 z računom, napravo/push registracijo, prostorom, čakajočim
opomnikom ter Unicode/decimal/binary podatki. Izvoz in obnova sta resnična;
samo fixture pripravi sintetično vzdrževanje in zamakne svoj čas po preverjanju,
da prezgodnji export odpove. Obnovitveni vsebnik ima vedno networknone/nobinds/
noports. Gostovani65sekundni pogoj ostane nespremenjen. Fixture ne kontaktira
nobenega živega gostovanja. Zasebni dokazi nastanejo zunajGit; v repozitoriju
so samo helperji/dokumentacija, nikoliSQL ali credentiali.

14. oktober: končni lokalni fixture **PASS**. Pred migracijo93tabel
(92baseline +1sintetična podatkovna tabela),45zgodovinskih vrstic,
1račun/1registrirana naprava; po migraciji ena nova prazna tabela in101novih
izvornih datotek. Vseh7 negativnih varovalPASS: manjkajočiGD, spremenjenSMTP
secret, prezgodnjiizvoz, napačen restoreproof, spremenjena zgodovinska vrstica,
prezgodnja potrditev obnovecrona in ponovno apply po release. Vseh6PHPhelperjev
z zapečatenimdeployment.php je lintPASS; Pythoncompile/shsyntax/diffcheckPASS.
Resnični zasebni dokaz:
`/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-fixtures/fixture-97ed90a5/fixture-evidence.json`.
Preverjen je tudi končni zamrznjeni izdajniZIP
`build/release/FamilyHub-0.14.0-upgrade-20261014.zip`,SHA
`e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743`:
seal sprejme natanko101izvornih datotek in njihove bajte. Zapečaten izhod tega
lokalnega preizkusa uporablja **sintetični zajem** in ni za živo namestitev.
Živo gostovanje potrebuje svoj novi dejanski capture/backup/restoreproof;
živi strežniki v tem koraku niso bili kontaktirani ali spremenjeni.


## Dejanski predhodni produkcijski korak — 15. oktober

Sveži produkcijski capture je potrdil isto identiteto
`ad56910f-ca2e-41ee-af0d-3f18081497cf`, schema17,96starih izvornih datotek
in9pinned zasebnih/config/ključnih datotek. Preverjeni zapečateni komplet
je pripravljen, pet ciljnih delavcev je bilo začasno ustavljenih, HTTPS503
preverjen. Dva prezgodnja izvoza je65-sekundno varovalo pravilno zavrnilo;
po dejanskem zamiku je dosledni izvoz zajel92tabel/319vrstic/2DATA datoteki
in17arhivskih vnosov. Arhiv58097bajtov ima SHA256
`8918015598615b82c3642c6bd9125633379f159daa42648eba69401a974911dc`.
Shramba kopije ostane zunaj document rootov in Git, z zasebnimi pravicami.

Brave je zavrnil prenos tega ZIP-a, nato se je Mac zaklenil. Dejanska
izolirana obnova v tistem poskusu zato **še ni bila izvedena**. Noben stage/DDL/code swap ni izveden.
Da produkcija ne ostane v vzdrževanju med čakanjem, je pregledani
`abort.php`/`abort.sh` potrdil odsotnost state/stage/migracij in schema18polj,
pravo identiteto/schema17, natančni old96/config/ključe in originale;
atomarno je vrnil HTTPS in po potrditviAPI izvirni cron.

Navadni Kanboard`/index.php` po obnovi pravilno vrne302, zato200preverjanje
v abort pomagaču uporablja javni Native capabilitiesPOST. Odgovor zahteva
strogoTLS/noFollow, v1/data.api=familyhub_native/version1, isti serverId in
enabled=true. NepreverjenHTML,302 ali napačna identiteta niso sprejeti.
Prvi abort je po obnoviHTTPS obstal pred cronom na tem strožjem preverjanju;
pregledana korekcija in nadaljevanje`--verify-http` sta nato omogočila
preverjeno vrnitev izvirnegacrona. `abort-checkpoint.json` dejansko potrdi
`aborted-before-ddl`,API200/workerCronRestoredtrue ob22:21:27UTC14.oktobra
(00:21:27CEST15.oktobra). Vse kopije/izvorni pomagači so ohranjeni.

Abort ima izolirani schema17preizkus s tremi negativnimi varovali; HTTPje
simuliran samo v fixtureju. Popravljeni APIprobe ima2pozitivni/7negativnih
kontrol in PHP8.4lintPASS. Dejanska gostovana pot je uporabila praviTLS.

Po odklepu Maca je bil tudi ta predhodni arhiv dejansko obnovljen v ločeni
izolirani MariaDB 10.11.19: vseh 92 tabel, 319 vrstic, dve datoteki in dva
imenika se ujemajo. Zgodovinski dokaz je
`/Users/anzenovsak/.local/share/jivie/backups/lifecycle18-production-20261015/restore-proof.json`;
sosednji `historical-restore-context.json` izrecno določa, da to ni aktualna
migracijska osnova.

Nadaljevanje je zato uporabilo novi zajem in kopijo po ponovni aktivnosti
produkcije, z novo obnovo in uspešnim stage/apply/verify/release, opisanim na
vrhu dokumenta. Zaključena abort mapa in njen arhiv ostaneta zgodovinska
dokaza; nobeden ni bil ponovno uporabljen za migracijo. Pregledni test1 in
test2 v tem predhodnem koraku nista bila spremenjena.
