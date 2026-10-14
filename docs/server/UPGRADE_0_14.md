# FamilyHub 0.14.0 / schema18: pripravljena varovana nadgradnja

To je lokalno pripravljen izdajni postopek. **Ta dokument ne potrjuje nadgradnje
nobenega živega gostovanja.** Produkcija `jivie.triparna.si` in pregledni
`jivie-test.triparna.si` imata ločena identitetna profila; vsak zahteva svojo
svežo kopijo, resnično izolirano obnovo in zapečatene vhodne hashe. Test2 ni
vključen: njegov polni profil mora biti posebej pregledan pred uporabo.

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
