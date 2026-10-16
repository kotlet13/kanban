# FamilyHub 0.15.0 / shema19 — preverjeni postopek nadgradnje

16. oktober 2026. Uporabnik je izrecno naročil nadgradnjo produkcije
`jivie.triparna.si`, preglednega test1 in pripravo javne izdaje Android.
Ta dokument opisuje ločeni novi postopek **0.14.1/shema18 → 0.15.0/shema19**.
Stari pomagači za prehod17→18 in popravek0.14.1 ostanejo nespremenjeni.
Test2 ni del tega postopka; Apple ostaja odložen.

**Produkcija in pregledni test1 sta dejansko nadgrajena na0.15.0/shemo19 in
ponovno odprta.** Za vsako gostovanje so ločeno potrjeni sveži zajem, polna
kopija, prava izolirana obnova, stage/apply/verify/release in vrnitev njegovega
originalnega crona. Test2 ostaja nespremenjen in zunaj obsega.

## Dejanska nadgradnja produkcije — 16. oktober 2026

Produkcijski postopek je uporabil svojo zapečateno mapo
`/home/tripar13/private/jivie-production/upgrade-0.15.0-20261016-104825`.
Priprava je potrdila staro0.14.1/shemo18, pravi
`ad56910f-ca2e-41ee-af0d-3f18081497cf`, vse101stare izvorne datoteke,
konfiguracije/ključe, GD, ZipArchive in izvirni cron. VzdrževanjeHTTP503 in
ustavitev petih ciljnih delavcev sta bila potrjena približno ob11:06UTC.

Po dejanskem65-sekundnem praznjenju je nova kopija nastala ob**11:07:44UTC**:
`/home/tripar13/private/jivie-production/backups/documents19-preupgrade-20261016-110744-5d0f381c/Documents19-private-backup.zip`.
Arhiv ima **287.147bajtov,118vnosov,93tabel in423zgodovinskih vrstic**,
dveDATA datoteki in dva imenika. Vključuje vsakCREATE/vrstico, konfiguracije,
ključe, izvirniHTTPS in celotni originalni cron ter vseh101starih izvorov.
Produkcijski SHA256:

`76002f71ae061de3b145a4d63efb522b8ebb4ce96cc0e1973668dd224f6f3a8d`.

Točni produkcijski arhiv je bil dejansko obnovljen v **ločeni sveži
MariaDB10.11.19**, z `network=none`, brez vrat in hostbindov, samo z anonimnim
MySQLvolumnom. Vsaka vrstica, vsakCREATE/stolpec/tip,DATA in prazni imeniki,
config/ključni/HTTPS/cron hashi in vseh101starih izvorov so preverjeni.
Obnovljena baza potrdi isto produkcijsko identiteto/shemo18, **triračune in
štirinaprave**. SQLSHA256:

`ff5883a8e6f57ed67682ec330f7a96ce2119500474024e053c8d5dbf266af129`.

Dejanski zasebni dokaz je
`~/.local/share/jivie/backups/documents19-production-20261016-r1/restore-proof.json`.
Obnova ni zagnala aplikacije/PHP ali dostavnih delavcev ter ni uporabila žive
baze ali test1kopije. Običajni brskalnikovSave arhiva je dokončno uspel brez
spremembe varnostnih nastavitev. Pri prejšnjem pomožnem poskusu nastali
zasebni `backup-transfer.json` ni bil uporabljen za prenos ali kot dokaz
obnove; skrivnosti niso bile izpisane.

Po vrnitvi produkcijskega dokaza v njegovWORK so **stage,apply,verify inrelease
PASS**. Nameščen je isti končni107-file paket5c14… iz spodnjega razdelka.
Nastalo je samo pet preverjenih praznih dokumentnih tabel: **93→98tabel**,
brez dodajanja stolpcev starim tabelam. Samo FamilyHub metadata preide18→19.
Vsak zgodovinskiCREATE in vse druge zgodovinske vrednosti ostanejo ohranjeni,
vključno z423izhodiščnimi vrsticami, računi, gesli, napravami, surovimi
nastavitvami, čakalnimi vrstami,DATA/pravicami,config/ključi, jedrom in drugimi
vtičniki.

Približno ob**11:13UTC** je končni zasebni `release-checkpoint.json` potrdil
`phase=released`, `apiPaused=false`, `workerCronRestored=true` in vsa varovala
ohranitve. OriginalniHTTPS in natanko originalni cron sta vrnjena; SMTP/FCM
konfiguracije in ključi ostanejo isti. Stari izvor in vse zasebne kopije so
ohranjeni. V dnevniku pause je ostalo trdo zapisano besedilo »Five test1«;
**dejanski cilj ni bil test1**: zapečateniSITE/DB/serverId, izvoz in končni
checkpoint potrjujejo produkcijo. Zaradi te oznake nismo spreminjali helperjev
ali njihovih pinov med postopkom.

Sveži javni Native capabilities vrne **HTTP200/istiSID/enabled**, preglednice,
priloge, usernamepovabila/atomicresend/pogodbo3 ter vključenaSMTP inexternalPush.
Odgovor je shranjen v
[production-public-capabilities.json](../../build/qa/familyhub-0.15.0/production-public-capabilities.json).
Ob11:14:53UTC je dodatnih **10anonimnih bralnih kontrol PASS** v
[production-anonymous-negative-policy-checks.json](../../build/qa/familyhub-0.15.0/production-anonymous-negative-policy-checks.json):
pravila sodelovanja200 z isto identiteto/policy1/SLEN; scopes.list,
tables.list/get, attachments.list/get, invitations3.pending, sync6.pull in
moderation.policyStatus brez bearerja vrnejo401 `auth_required`; GETNativeAPI
vrne405. Noben račun, povabilo, dokument, soglasje ali vsebinska sprememba
ni bil zahtevan; običajni anonimni rate-limit števci se lahko povečajo.

Po ponovnem branju obeh dokazov ter ponovni primerjavi SHAobeh arhivov in
obnovljenihSQL sta bila odstranjena samo končana izolirana vsebnika
`jivie-documents19-restore-test1-20261016` in
`jivie-documents19-restore-production-20261016` z njunima anonimnima volumnoma.
**Oba arhiva, obnovljeni izvlečeniSQL/DATA/izvor in oba restoreproofa ostanejo
zasebno ohranjeni**. DrugiDocker vsebniki niso bili spreminjani.

Strežniška nadgradnja ne dokazuje nove namestitve ali fizičnega novegaUI na
telefonu niti nove dostave e-pošte/push. Javna izdaja aplikacije se potrjuje
v svojem izdajnem zapisu; Apple ostaja odložen.

## Dejanska nadgradnja test1 — 16. oktober 2026

Uporabljen je novi zasebniWORK
`/home/tripar13/private/jivie-test/upgrade-0.15.0-20261016-104824`,
zajet in zapečaten samo za test1. Po strogi potrditvi vzdrževanjaHTTP503 in
ustavitvi njegovih petih obstoječih delavcev sta **prva dva prezgodnja izvoza
pravilno obstala na `drain_65_seconds_required`**. Ti varovani ustavitvi nista
izvedliDDL ali zapisaliSQL vrstic. Tretji izvoz je uspel po dejanskem čakanju;
časovnega varovala nismo spreminjali ali zaobšli.

Sveži dejanski arhiv je nastal ob11:03:28UTC pod
`/home/tripar13/private/jivie-test/backups/documents19-preupgrade-20261016-110328-928eeadd/`.
Ima **295.451bajtov,125vnosov,93tabel in343zgodovinskih vrstic**. Zajema celotni
SQL, dveDATA datoteki in dva imenika, konfiguracije/ključe, izvirniHTTPS,
celotni originalni cron ter vseh101starih izvornih datotek. SHA256:

`ed0feed36ab51aebb6d6adfe2d959c9d86ce51c8d970f5a9b574ba3875eb36c1`.

Točni arhiv je bil resnično obnovljen v sveži **MariaDB10.11.19**, z
`network=none`, brez vrat in hostbindov, samo z anonimnim MySQLvolumnom.
Primerjani so vsaka vrstica, vsakCREATE, stolpec/tip,DATA datoteke/prazni
imeniki, configuration/HTTPS/cron/key hashi in vseh101starih izvorov.
Obnovljena baza ima isto test1identiteto in shemo18, triNative račune in
desetnaprav. SQLSHA256:

`01076c7cc4ab6dae6062cea3d7a1d7836d6e2ec9bd9f0817df50363bbf63ca17`.

Zasebni dejanski dokaz je
`~/.local/share/jivie/backups/documents19-test1-20261016-r1/restore-proof.json`;
obnova ni zagnalaPHP/aplikacije/delavcev in ni uporabila žive baze. Arhiv in
dokaz ostaneta ohranjena zunajGit; produkcijska kopija ni bila uporabljena.

Po vrnitvi istega dokaza v istiWORK so **stage,apply,verify inrelease PASS**.
Nameščen je točni107-file končni paket5c14… iz spodnjega razdelka. Nastalo je
natanko pet praznih dokumentnih tabel, brez dodajanja stolpcev starim tabelam:
93→98tabel, metadata samo18→19. Vseh343zgodovinskih vrstic/vrednosti in stari
CREATE ostanejo ohranjeni, prav tako triračuni, desetnaprav, gesla, obstoječe
nastavitve,DATA/pravice,config/ključi, jedro in drugi vtičniki. Istočasno niso
bila ustvarjena resnična povabila, računi ali dokumenti za preizkus.

Končni checkpoint v zasebnem `apply-result.txt` izrecno potrdi `phase=released`,
`apiPaused=false`, `workerCronRestored=true` in vsa varovala ohranitve.
Test1serverId ostane `95c11fe0-916c-48be-a3f6-999732846266`. IzvirniHTTPS in
natanko originalni cron sta obnovljena; SMTP in FCM konfiguracija ostaneta isti.

Javni Native capabilities vrne **HTTP200/istiSID/enabled** in potrdi
`spreadsheets`, `attachments`, `usernameInvitations`, `invitationResend` ter
pogodbo povabil3. Odgovor je shranjen v
[test1-public-capabilities.json](../../build/qa/familyhub-0.15.0/test1-public-capabilities.json).
Dodatnih **10 anonimnih bralnih kontrol PASS** je v
[test1-anonymous-negative-policy-checks.json](../../build/qa/familyhub-0.15.0/test1-anonymous-negative-policy-checks.json):
javna pravila sodelovanja200 z isto identiteto/policy1 in obema jezikoma;
seznami prostorov, preglednic, prilog ter njihov prenos, prejeta povabila,
sinhronizacija in osebno stanje sprejema pravil brez bearerja vrnejo401
`auth_required`; neposredniGET doNativeAPI vrne405. Dostop do vsebine ali
osebnih podatkov ni bil pridobljen. Te zahteve ne pošljejo prijave, žetona,
soglasja, povabila ali vsebinske spremembe; običajni strežniški števci
omejitev anonimnih klicev se lahko povečajo.

To potrjuje nameščene pogodbe in anonimne zavrnitve, ne fizične namestitve
aplikacije, dejanske dostave obvestila/e-pošte ali uporabnikovega novegaUI.
Produkcijski postopek je potrjen v ločenem razdelku zgoraj; javna izdaja aplikacije ima svoj izdajni zapis.

## Paket, izhodišče in nespremenljive identitete

Končni paket [FamilyHub-0.15.0.zip](../../build/releases/FamilyHub-0.15.0.zip)
ima107 regularnih datotek, od tega94 PHP; CRC in vsak izvorni hash sta
preverjena. SHA256:

`5c14ca9a79d92cf1c5f71b681d8417f44f4bfb9b474443cdad4dbb3f589f51e7`.

Paket vsebuje izrecni pregledani manifest98 izvorov, osem javnih pogodb ter
`NOTICE.md`, bajtno enak nespremenljivemu javnemu0.14.1 commitu
`59119dc594f941cada5ede73435c1d9a2fda990c`. Preglednice, priloge in nova povabila
so v istem paketu. Javni FamilyHub je objavljen kot `dd5ae02`/`v0.15.0`;
usklajeni aplikacijski/strežniški izvor je `6c8a2fc` na `main`. Pravila dostopa in okvir funkcij opišeta
[preglednice in priloge](../TABLES_AND_ATTACHMENTS.md) ter
[prenova povabil](../INVITATION_AND_SHARING_IMPLEMENTATION.md).

Gostovano izhodišče ima101 datoteko, ne102 datotek javnega paketa0.14.1.
Pomagač preveri celotni prvotni0.14.0 paket s SHA
`e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743`,
njegov manifest in natanko tri pregledane spremembe privzetega zvoka:
`Plugin.php`, `Model/NativeNotificationPreferences.php` in
`Model/NativePushWorker.php`. Vse PHP datoteke in MIT licenca se morajo ujemati
še z nespremenljivim javnim0.14.1 commitom; gostovani README in pogodbe
ostanejo preverjeni proti gostovanemu izhodišču. Primerjava ni po imenih ali
približni različici: vseh101 hashov mora biti enakih svežemu zajemu.

| Profil | Gostovanje | Zasebni koren | Podatkovna baza | Isti serverId |
| --- | --- | --- | --- | --- |
| production | jivie.triparna.si | /home/tripar13/private/jivie-production | tripar13_jivieprod | ad56910f-ca2e-41ee-af0d-3f18081497cf |
| test1 | jivie-test.triparna.si | /home/tripar13/private/jivie-test | tripar13_jivietest | 95c11fe0-916c-48be-a3f6-999732846266 |

**Postopek spodaj je opis že izvedenega prehoda18→19. Na sedanjih gostovanjih
s shemo19 ga ne ponavljaj; naslednja nadgradnja potrebuje nov postopek in nove
trenutne kopije/pine.**

## Novi bralni zajem

[Pomagači](../../server/scripts/upgrade-0.15.0) ne uporabljajo aplikacijskega
bootstrap ali dostavnih delavcev. `capture.php` zahteva MariaDB10.11.19,
shemo18, pravo identiteto, staro različico0.14.1/101izvor, self-hosted NativeAPI,
izključena stara projektna povabila, ZipArchive in zasebne pravice DATA.
Pet novih dokumentnih tabel še ne sme obstajati.

Zajame hashe konfiguracije, vseh njenih vključitev in zasebnih korenskih
datotek, FCM ključa, semantičnega nabora FamilyHub konstant, HTTPS, celotnega
crona in celotnega starega izvora. Skrivne vrednosti ostanejo v datotekah;
izhod vsebuje poti, hashe, identiteto in števce. Skript in izhod sta v novi
podmapi zasebnega korena, nikoli med njegovimi korenskimi konfiguracijami:

```sh
umask 077
mkdir -m 700 /home/tripar13/private/CILJ/capture-0.15.0-FRESH
/bin/crontab -l > /home/tripar13/private/CILJ/capture-0.15.0-FRESH/cron.capture
/opt/alt/php84/usr/bin/php /home/tripar13/private/CILJ/capture-0.15.0-FRESH/capture.php PROFILE /home/tripar13/private/CILJ/capture-0.15.0-FRESH/cron.capture > /home/tripar13/private/CILJ/capture-0.15.0-FRESH/capture.json
```

`CILJ/PROFILE` sta `jivie-test/test1` ali `jivie-production/production`.
Za vsako gostovanje uporabimo svojo novo mapo in lasten zajem. Ne spreminjaj
korenskih prejšnjih pomočnikov ali njihovih statusnih datotek: če so v
zajetih konfiguracijskih pinjih, se mora njihov hash ohraniti.

Sveža bralna zajema16.oktobra ob10:37/10:38UTC sta shranjena zunajGit:

- `~/.local/share/jivie/backups/documents19-production-20261016-r1/capture.json`,
  SHA `96c65ca7ea8500bc2934989faecb7ad92aeb74651a94f80a8505f9ec1aa347e9`;
- `~/.local/share/jivie/backups/documents19-test1-20261016-r1/capture.json`,
  SHA `4c7b00b70fa65badc7efbc2016d7301cc1b5e779e986dcabe761854462f0af35`.

Oba potrdita shemo18, pravilni različni identiteti,101izvor, ZipArchive in
dve zasebni datoteki/dva imenika. To je zajem trenutnih pinov, **ni še kopija
baze ali dokaz obnove**.

## Zapečatenje in prenos

Lokalni `seal.py` zahteva zajem, mlajši od6ur, in preveri vse zgornje pine.
Končni ZIP primerja z vsakim aktualnim pregledanim izvorom/javno pogodbo,
izrecnim seznamom in nespremenljivim NOTICE. Zavrne symlink, dodatni vnos,
podvojeno ime, napačenCRC, različico ali spremenjen izvor. Izhod je nova
0700mapa zunajGit, vse datoteke0600:

```sh
python3 server/scripts/upgrade-0.15.0/seal.py /ZASEBNO/capture.json build/releases/FamilyHub-0.15.0.zip /ZASEBNO/sealed
```

Izpis določi natančni novi `hostWork`; ne izmišljaj poti in ne uporabi starega
WORK. Za zajema zgoraj sta zapečateni lokalni mapi `sealed-r2` ob zajemih, končni
hostWork test1 pa
`/home/tripar13/private/jivie-test/upgrade-0.15.0-20261016-104824`,
produkcijski
`/home/tripar13/private/jivie-production/upgrade-0.15.0-20261016-104825`.
Predhodni mapi `sealed` in njen prvi paket sta nadomeščena; ne uporabita se za namestitev.
Oba končna source-manifestSHA sta
`25c3acc08b8a9f18de7e16d87f53d3801cadab4578a45f7c65baee043906eea6`.

Prenesejo se samo regularne datoteke te zapečatene mape: `deployment.php`,
`source-manifests.json`, končni javniZIP, `capture.json`, `document-tables.php`,
`backup.php`, `upgrade.php`, `maintenance.php`, oba datotečna varovala,
`operate.sh`, `abort.php` in `abort.sh`. Novi WORK je0700 zunaj vseh document
rootov; datoteke0600 in uporabnik/lastnik isti kot gostovanje. Pred izvajanjem
primerjaj vsak preneseni hash z lokalnim. Nobene produkcijske konfiguracije,
ključa,SQL ali DATA ni v tem distribucijskem svežnju.

## Ustavitev, polna kopija in resnična obnova

Najprej izvedi test1, nato preizkus njegove nove pogodbe in šele nato ločeno
produkcijo. Vsak profil ima svoj WORK, svoj arhiv in svoj restoreproof.
V spodnjih ukazih `WORK` pomeni izključno absolutno pot iz `seal.py`.

```sh
sh WORK/operate.sh WORK prepare
sh WORK/operate.sh WORK pause
```

Prepare ponovno primerja stari101izvor, konfiguracije/ključe, identiteto,
shemo18, končniZIP/hash/CRC/PHP, GD, ZipArchive in celotni izvirni cron.
Ustvari kandidat, ki začasno ustavi natanko pet obstoječih ciljnih delavcev:
reminders, delivery, account-mail, account-deletion-cleanup in push. Vse
ostale vrstice ostanejo bajtno enake. Pause namesti ta kandidat ter strogo
preveri javni HTTPS503 brez sledenja preusmeritvam.

Zapri urejevalne odjemalce in počakaj **najmanj65dejanskih sekund**.
Naslednji ukaz zahteva nov procesni pregled, isto vzdrževanje in isti pausedcron:

```sh
sh WORK/operate.sh WORK export
```

Bralni zaklepi vseh tabelInnoDB omejijo zapisovalce med kopiranjem. Arhiv
zajame vsakCREATE, vsak stolpec/tip, vsako vrstico vseh tabel, celotno DATA
s praznimi imeniki, konfiguracije/ključe, izvirniHTTPS, celotni izvirni cron
ter vseh101starih izvornih datotek. SQL vrednosti so binarno ohranjene.
Dva inventarja baze/datotek in izvorna/kopirana drevesa morajo biti enaki.
Napačne zasebne pravice, symlinki, spremenjen ključ, aktivni proces ali
prezgodnji izvoz ustavijo postopek.

Prenesi **točni izpisani** `Documents19-private-backup.zip` v novo0700lokalno
mapo zunajGit, datoteka0600; SHA se mora ujemati z izpisom gostovanja.
Ustvari svež obnovitveni vsebnik in vanj uvozi samo ta arhiv:

```sh
docker run -d --name jivie-documents19-restore-test1 --network none -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=yes mariadb:10.11.19
python3 server/scripts/upgrade-0.15.0/restore-verify.py /ZASEBNO/Documents19-private-backup.zip --sha256 SHA --container jivie-documents19-restore-test1 --private-root /ZASEBNO
```

Baza mora biti pripravljena in prazna. Preverjevalnik zavrne drugo sliko ali
različico, omrežje, vrata, host bind, imenovan volume ali dodatne mounte.
Dovoljen je samo anonimni MySQLvolume. Primerja vsako vrstico inCREATE,
stolpce/tip,DATA in prazne imenike, konfiguracijske/ključne/HTTPS/cron hashe ter
vseh101starih izvorov. PHP/aplikacija/delavci se pri obnovi ne zaženejo;
živa baza ni uporabljena. Dokaz vsebuje isto identiteto, shemo18 in števce.

`restore-proof.json` nastane dejansko iz preverjanja; nikoli ga ne piši ročno.
Vrni ga kot0600visti WORK, ponovno primerjaj hash in ga ohrani ob arhivu.
Tudi kopija mora biti mlajša od6ur. Vsebnik odstrani šele, ko je dokaz shranjen
in ponovno prebran; arhiv,SQL/datoteke in dokaz ostanejo zasebno ohranjeni.

## Stage, pet dodajalnih tabel in release

```sh
sh WORK/operate.sh WORK stage ARCHIVE SHA
sh WORK/operate.sh WORK apply ARCHIVE SHA
sh WORK/operate.sh WORK verify ARCHIVE SHA
sh WORK/operate.sh WORK release SHA
```

Stage zahteva dejanski obnovitveni dokaz in primerja sveže živo stanje s
kopijo. Celotni stari vtičnik kopira zasebno; novi izvor pripravi brez
objavljanja. Apply pred DDL znova preveri vse pine, staro vsebino, dokaz in
procesni drain. Zažene samo pregledani `version_19` iz zamrznjenega paketa,
brez bootstrap. Nastane natanko pet praznih tabel:

- `familyhub_tables`;
- `familyhub_attachments`;
- `familyhub_attachment_chunks`;
- `familyhub_document_requests`;
- `familyhub_document_cleanup`.

Njihovi stolpci, tipi, vrstni red primarnih ključev in celotniSHOWCREATEhashi
morajo biti enaki neodvisno pridobljenim referencam MariaDB10.11.19 v
`document-tables.php`; hash referenc je dodatno zapečaten. Ne sme nastati
noben dodaten stolpec stare tabele, indeks ali tabela. Vsi stariCREATEhashi
in vsaka zgodovinska vrednost morajo ostati isti, vključno z uporabniki,
gesli, napravami, neobdelanimi nastavitvami in šifriranimi vrstami. Edina
sprememba stare vrstice je natanko metadata `familyhub`18→19; ostale plugin
metadata vrstice ostanejo enake.

Po preverjanju se atomarno zamenja vtičnik, original ostane zasebno ohranjen.
Verify znova potrdi natančne stare podatke in definicije,DATA/pravice,
jedro/druge vtičnike,config/ključe,HTTP503 in isti pausedcron. Release
najprej ponovi preverjanje, nato vrne izvirniHTTPS, **šele zatem** natančni
izvirni cron. Ločena checkpointa ločujeta `released-http-workers-paused`
od `released`; končni vsebuje `apiPaused=false` in `workerCronRestored=true`.
Ponovljeni apply, spremenjen izvor ali ponovno uporabljen abortWORK so zavrnjeni.

Priloge ne potrebujejo dodatnega crona: isti pregledani `cli/reminders.php`
po nadgradnji izvaja še omejeno čiščenje prilog. Zasebna dokumentna shramba
nastane ob uporabi z0700imeniki/0600datotekami pod obstoječim DATA. Obnova
originalnega crona ohrani njegove obstoječe flock/omejevalnike,SMTP in FCM.
Po odprtju se delavci lahko normalno premaknejo v vrstah ali ustvarijo svoj
podimenik; preverjanje bajtne ohranitve je zato opravljeno pred odprtjem.

Po release ločeno preveri javni Native capabilitiesHTTP200/istiSID/enabled,
različico in zaslone pravil zasebnosti, dokumentne zmožnosti, username/resend pogodbo in
namenski testni račun. Ne uporabljaj produkcijskih uporabnikov za sintetično
pošiljanje; fizična dostava ali delovanje na napravi ne sledi zgolj iz checkpointa.

## Varovana prekinitev pred DDL

Če še ni stage/state/DDL/code-swap, uporabi samo nov pregledani abort:

```sh
sh WORK/abort.sh WORK
```

Abort zahteva shemo18, odsotnost vseh petih dokumentnih tabel, natanko stari101
izvor,iste config/ključe, izvirnikeHTTPS/crona in vzdrževanje. Najprej atomarno
vrne HTTPS ter preveri pravi Native capabilitiesHTTP200/istiSID/enabled.
Delavci ostanejo ustavljeni do potrditve tega odgovora; šele potem se vrne
izvirni cron in ustvari `aborted-before-ddl` checkpoint. Vse kopije in izvor
ostanejo ohranjeni, nobena SQL vrstica se ne zapiše.

Če je bilHTTPS že vrnjen, vendar je strogi200probe odpovedal, ne zaganjaj
abort od začetka. Po pregledu vzroka lahko nadaljuješ `abort.php --verify-http`,
ponoviš bralni `upgrade.php --check`, potrdiš isti pausedcron, obnoviš točni
originalcron in izvedeš `abort.php --confirm-cron`. Svež procesni/cron pregled
ostane potreben. Končana abortmapa se nikoli ne uporabi za novo migracijo:
nov zajem, nova kopija, nova prava obnova in nov WORK.

Po začetku stage/DDL abort namenoma zavrne. Ohrani vzdrževanje in vse zasebne
izvirnike/state. MariaDBDDL ni transakcijski rollback; stare kopije se ne
uvaža neposredno na živo gostovanje. Morebitna povrnitev po DDL potrebuje
pregledani načrt z ohranitvijo vseh novih zapisov po odprtjuAPI.

## Lokalno preverjanje

`fixture-test.py` uporablja samo sintetični Kanboard/FamilyHub0.14.1/schema18,
račun, napravo/push registracijo, prostor, opomnik ter Unicode/decimal/binary
podatke. Vseh94starih tabel vključuje93izhodiščnih in eno sintetično kontrolno
tabelo;45zgodovinskih vrstic. Preizkus uporabi točni končni107-fileZIP zgoraj,
ne na novo sestavljene približne kopije. Izvoz in obnovitev v drugi sveži
MariaDB10.11.19 sta resnična, brez omrežja/vrat/hostbindov na obnovitvi.

```sh
python3 server/scripts/upgrade-0.15.0/fixture-test.py
python3 server/scripts/upgrade-0.15.0/fixture-test.py --abort-only
```

Polni fixture preveri pripravo,izvoz,pravoobnovo,stage,apply,verify,HTTP-release
in natančno obnovo crona. Enajst negativnih varoval vključuje nedostopen
ZipArchive, javno DATA datoteko, manjkajočiGD, spremenjen SMTPsecret,
prezgodnji izvoz, napačen restoreproof, spremenjeno zgodovinsko vrstico,
neprazno/spreminjeno novo dokumentno tabelo, prezgodnjo potrditev crona in
ponovni apply po release.

Abort fixture preveri prekinitev in šest negativnih varoval: delna shema19,
stage, napačna javna identiteta, prezgodnja potrditev crona, ponovljen končani
abort in poskus migracije z abortWORK. Samo v tem sintetičnem preizkusu je
HTTP nadomeščen z lokalnim kontroliranim odgovorom; gostovani pomočniki imajo
pravi strogiTLS. Samo fixture po negativnem časovnem preizkusu premakne svoj
maintenance čas; gostovanih65dejanskih sekund ni mogoče preskočiti.

Zasebni dokazi in morebitni SQL/konfiguracije so izključno pod
`~/.local/share/jivie/backups/documents19-fixtures/`, ne vGit ali documentrootu.
PHP lint vseh pomagačev, Python compile, shellsyntax in preverjanje
nespremenljivosti starih pomagačev so del končnega pregleda.


Končno preverjanje uporablja paket5c14… z107vnosi in nespremenjenimi94PHP:

- Polni fixture **PASS**:94starih tabel/45vrstic →99tabel s petimi praznimi
  dodatki; stage/apply/verify/release, prava izolirana obnova in vseh11negativnih
  varoval. Zasebni dokaz:
  `~/.local/share/jivie/backups/documents19-fixtures/fixture-3cea90fc/fixture-evidence.json`.
- Abort fixture **PASS**, vseh6negativnih varoval. Zasebni dokaz:
  `~/.local/share/jivie/backups/documents19-fixtures/fixture-7c7f819d/fixture-abort-evidence.json`.
- Vseh8PHPpomagačev lintPASS,3Pythoncompile in2shellsyntaxPASS;
  `git diff` potrdi nespremenjene stare0.14.0/0.14.1pomagače.
- Dokumentacijsko popravljeni končni paket5c14… nadomesti predhodni e1d6…;
  zgodovinaCHANGELOG je ohranjena. Žive mape `sealed-r2` vsebujejo samo končni
  paket in zgornji končni manifest. Prejšnjih zapečatenih map ne uporabi.

Za prenos sta poleg polnega svežnja pripravljena manjša zasebna
`sealed-r2-helpers-only.tar.gz` z12pomagači/pini. Javnega paketa ne vsebujeta;
po ekstrakciji v isti noviWORK se prenese točni javniZIP:

```sh
curl --fail --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/kotlet13/kanban_family_hub/v0.15.0/dist/FamilyHub-0.15.0.zip --output WORK/FamilyHub-0.15.0-source.zip
chmod 600 WORK/FamilyHub-0.15.0-source.zip
sha256sum WORK/FamilyHub-0.15.0-source.zip
```

SHA mora biti natanko5c14… iz začetka dokumenta. Vsak od vseh13končnih vnosov
se mora ujemati s per-file `sealed-r2-transfer-manifest.json` ob lokalnem
svežnju. Javna pot ni nadomestilo za hashpin; drugačna vsebina se zavrne pred
pripravo aliDDL. Test1helpers-onlySHA je
`f1c6ebe0bc003483c7e277a0daa602a387b3445b789b5b59d5d8eef9223357a9`,
produkcijski
`4d7d2ccb4174a0560fa8f1397bbd54af4895d9fef3199d3b7235c378135f045e`.
