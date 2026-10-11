# Izguba testnega strežnika — Android in Mac

**11. oktober 2026 · začetna objava/prenos potrjena, celotni A–F še čakajo.**
Lokalna priprava je končana: svež Kanboard 1.2.54/FamilyHub 0.11.2 paket ima
SHA256 `9c6d62d6a2e8670b2604b5849569688d2695c6c72319132e644b627660df0ae6`,
2185 datotek, CRC/inventar, 77 PHP lint in 10 paketnih testov PASS. Dodatni
`config.php` zapre zahteve s 503 pred migracijami. Paket ne vsebuje uporabniških
baz/priponk/skrivnosti; vključeni SQL sta nespremenjeni upstream shemi.
Pred začetkom je DNS za test2 vrnil NXDOMAIN. Na računu `tripar13` je nato ustvarjena
ločena domena z rootom `/home/tripar13/jivie-test2.triparna.si`; AutoSSL ima veljaven
certifikat do 9. januarja 2027. Uporabnik je sam oddal namestitev z novim geslom;
Softaculous je potrdil uspešno namestitev Kanboard 1.2.54 z novo bazo
`tripar13_jivietest2`. FamilyHub **0.11.2/schema15** je nato nameščen in dejansko preverjen;
celotni preizkus še sledi. Dokazi so v
ignorirani `build/qa/server-loss-test-20261011/`, ZIP v `build/releases/test2-server-20261011/`.

Preizkus uporablja samo novo `https://jivie-test2.triparna.si`, sintetične podatke,
Android **1.4.0 (18)** in dejansko odprto Mac gradnjo, katere različico in izvor
zabeležimo pred začetkom. Namen je preveriti ohranitev prenesenih podatkov,
lokalno delo in obnovo po izgubi strežnika. Ugotovljene napake in njihovi ločeni popravki so navedeni spodaj.

## Dejanska priprava gostovanja — 11. oktober

- Namestitev uporablja uporabnikov sveži Softaculous **Kanboard 1.2.54** in strogi
  **83-datotečni FamilyHub 0.11.2** ZIP; zgornji skupni zaprti ZIP ni bil razpakiran
  preko Softaculous jedra ali njegovih nastavitev baze.
- Plugin ZIP SHA256 `8108791ef3c5dd39f295395b1a5c5164ba58c2f21bc5c36722b0fe7244d857b4`;
  varovani CLI helper SHA256 `986828ba0a400fea963594224fcccc71c8cd66728b118743fa7885089b7ae008`.
  SHA/CRC/inventar in PHP razčlenitev so preverjeni tudi na gostovanju **PHP 8.4.26**.
- Pred vklopom je javna pot dejansko vračala **503**, vtičnik pa je bil migriran z
  Native API izključenim. CLI `--verify` nato potrdi **0.11.2/schema15**, nova
  identiteta `f48b41ae-c6bb-4f2d-ae13-0aa7fa255993`, **0 Native računov/sej**, ohranjene
  izvirne core datoteke in vrstice ter 83 ujemajočih datotek vtičnika.
- Aktivni config je `/home/tripar13/private/jivie-test2/config.php` (0600), podatki
  `/home/tripar13/private/jivie-test2/data` (0700). Javni config je le vključitev
  zasebnega; izvirni config, `.htaccess` in podatki so ohranjeni za povrnitev.
- HTTPS capabilities neodvisno potrdi isto novo identiteto, Native API in možnost
  prvega računa; **SMTP/FCM/stara projektna povabila so izključeni**. Native prijava
  v skrbniški račun ni bila izvedena; prvi račun čaka na skrbniško spletno kodo.
- cPanel HTTPS stikalo je pokazalo On, vendar HTTP še ni preusmerjal. Dodano
  namensko pravilo samo za test2 zdaj dejansko vrne **301 → HTTPS**. Izvirna
  `.htaccess` je ohranjena zasebno. Zahteve `config.php`, `config.default.php`,
  `data/` in `data/.htaccess` brez prijave vrnejo **302 na prijavo z 0 bajti**;
  to ni opaženi 403 in samo po sebi ne dokazuje odziva po prijavi. Aktivni config
  in podatki so zunaj vseh pregledanih document rootov.
- Edini test2 cron je novi Softaculous core cron `45 14 * * *`; FamilyHub delavci
  niso kopirani ali dodani. Pošta/push nista del tega preizkusa. Capabilities
  obstoječega test1 so pred in po namestitvi povsem enake, vključno s serverId.
- Pred gostovanim posegom je lokalni izolirani PHP 8.4.24/MariaDB 10.11.19 preizkus
  potrdil vseh sedem faz, zaporo običajnega CLI bootstrap in povrnitev datotek.
  Povrnitev ni bila izvedena na gostovanju; nobena baza ali datoteka ni izbrisana.
- Uporabnik se je dejansko prijavil kot `jivie_test2_admin`; spletni About potrdi
  **PHP 8.4.26/litespeed** in **MariaDB 10.11.19**. Odprta je FamilyHub enrollment
  stran; enkratna koda še ni izdana, aplikacijski račun še ni ustvarjen.
- Pred menjavo računa je odprta podpisana Mac **1.3.2 (17)** iz
  `build/qa/jivie-retention-mac-20261011/SignedProducts/Debug/Jivie.app`; po naložitvi
  potrdi račun takndev, obstoječi test1 in izbor Vsi. Začetni prehodni lokalni prikaz
  pred naložitvijo ni dokaz izgube prijave. Mac dialog šifrirane kopije je pripravljen
  za uporabnikovo geslo. Android različica in dejansko odprti kopiji obeh naprav
  še čakata; račun na tej točki še ni zamenjan.

## Predogled ničel — 11. oktober

Uporabnik je poročal o pretežno praznem predogledu na Macu in ničlah na Androidu.
To še ni dokaz praznega izvoza: `BackupPreview.personalCounts` zajame samo privzeti
lokalni osebni snapshot in vrtove; `tables.records`, `finance_records`, druge
`localSpaces` in linked-payment sidecar so v šifriranem dokumentu ločeni. UI jih v
teh številkah ne pokaže. `scopeCount` vključuje tudi zasebni sync scope, ne samo
skupnih prostorov; `pendingCount` izpušča linked-payment intents. Relevantna logika
je med 1.3.2 (17) in 1.4.0 (18) enaka. Pred javno izdajo je potreben jasnejši
predogled vsebine in regresija »osebno 0, prenesena vsebina >0«; to ni že izveden
popravek in samo pregled kode ne potrjuje vsebine uporabnikove kopije.

Macov UI še pokaže obstoječi skupni projekt ter Doma in projektni obseg. Uporabnik
je kopijo že shranil na Desktop; ohranjena dodatna zasebna kopija ima **43.704
bajtov**, veljavno ovojnico1/PBKDF2-600000/AES-256-GCM, šifriran payload **32.608
bajtov** in SHA256 `c83998bbd3ed1346909890b441d5582811910202e25f1eb96e901d3b6c81fdbe`.
Izvirnik ostane ohranjen. Šifrirane datoteke in geslo niso v Git/QA; zapisani so le
metapodatki. Shranjena datoteka je nato z uporabnikovim geslom dejansko
odprta in strogo preverjena v aplikaciji: račun takndev/test1, osebni števci0,
**2 strežniška obsega in 0 prikazanih neusklajenih operacij**, brez opozorila o
nepopolnih obsegih. Predogled je zaprt brez potrditve obnove. To potrdi
avtenticirano dešifriranje in obliko kopije, ne fizične obnove posameznih skupnih
zapisov. Androidovo kopijo
je potrdil uporabnik, njena datoteka in različica aplikacije še nista neodvisno
preverjeni.

**39 ciljnih Flutter testov PASS** za portable backup, lokalno samostojno obnovo,
lokalne prostore, povezana plačila in backup UI: zajem/obnova opravila z novim
lokalnim ID in ohranjenim šifriranim izvirnikom, finance brez podvojitve,
finančna zavrnitev/nepopolnost, lokalni vrtovi in payment/refund/cash roundtrip.
Obstoječi UI test uporablja fake osebne števce; ne pokrije sedanjega zavajajočega
prikaza ničel. Ti testi niso fizični rezultati A–F.

## Prvi testni račun — potrjeno

Po dejanskem pregledu shranjene Macove kopije je Mac po standardni poti odjavljen
iz takndev/test1; skupni pogled se skrije, osebni zapisi ostanejo. Račun test1,
jegovo članstvo, baza in datoteke niso izbrisani. Običajna odjava prekliče samo
Macovo staro sejo; trditev o nespremenjenih starih capabilities zgoraj se nanaša
na pripravo gostovanja, ne na odsotnost običajnega napravnega prometa.

V Macovem obrazcu »Prvi račun s kodo« je dejansko vpisano
`https://jivie-test2.triparna.si/`, sintetično uporabniško ime `slt_test` in prikazno
ime »Preizkus izgube strežnika«. Uporabnik sam izda kodo v prijavljenem spletnem
FamilyHub enrollment, jo prenese v obrazec in vnese/potrdi/odda novo geslo.
Koda, geslo in seje se ne beležijo v dokaze. Uporabnik je račun dejansko ustvaril;
Mac potrdi `slt_test` na test2. Neodvisni HTTPS capabilities potrdi isto novo
identiteto in zaprt prvi enrollment. Sinhronizacija obeh naprav in celotni A–F
še niso potrjeni.

## Prva fizična objava in popravek izbora

Na Macu je ustvarjeno lokalno **SLT gospodinjstvo**, opravilo
`SLT gospodinjstvo Mac`, dogodek `SLT dogodek Mac`, seznam `SLT nakupi Mac` z
artiklom `SLT artikel Mac` ter `SLT vrt Mac` z zapisom in eno gredo. Predogled
»Poveži in sinhroniziraj« pokaže **4 zapise in 1 vrt** ter izrecno pravi račun/test2.
Po potrditvi dejanski read-only pregled samo `tripar13_jivietest2` potrdi po en
live `task`, `event`, `shoppingList`, `shoppingItem` in `garden`: **5 skupaj**.
Prenos je uspel; podatki niso ponastavljeni ali ponovno ustvarjeni neposredno v bazi.

Fizična objava je razkrila **DropdownButton assertion**: izbrana lokalna vrednost
ostane `local:<ID>`, meni pa objavljeni vezani lokalni prostor odstrani iz postavk.
Selektor pokaže rdeči ErrorWidget in stari lokalni kontekst. Isti picker blob je v
1.3.2 (17) in main/1.4.0 (18); ne gre za poseben star Mac ostanek. Izvorni popravek
izbere točno pripadajoči scope istega računa, med vmesnim stanjem ohrani onemogočeno
izbrano postavko ter pred SQL zapisom preveri generacijo/identiteto/lokalni binding.
Uporabnikova izbira drugega lokalnega prostora/Vsi in menjava računa ustavita
zastareli prehod. Shema, API telesa, gostovanje in app različica ostanejo isti.

Pravi prvotni assertion je reproduciran v izoliranem negativnem widget preizkusu;
**74 začetnih ciljnih PASS / 1 opt-in preskočen**, vključno s sedmimi regresijami z
resničnima providerjema, SQLite, publication transportom ter kontrolo poznih SQL
zapisov. Širši prvi sklop je nato zaznal 4 napake v prvotnih povabilih: nova aktivna
odvisnost je po nepotrebnem odpirala lokalno platformno bazo/organizer. Končna
izvedba lokalni katalog bere samo, če je že aktiven, in ga ne aktivira iz
računskega toka. Prvotni testi povabil so nespremenjeni; nova osma regresija
potrdi, da lokalni/organizer/database providerji v account-only toku ostanejo
neustvarjeni. Končno **950 Flutter PASS / 13 opt-in preskočenih**, analiza brez
ugotovitev; funkcionalni **d627bbe** je na main/origin. Sveža podpisana Mac
**1.4.0 (18)** iz d627bbe je izdelana in dejansko odprta z ohranjeno prijavo slt_test.
295 zamrznjenih vhodov se ujema, podpis je strogo preverjen; certifikat/profil,
ključna veriga, odvisnosti in SDK so ohranjeni. Hladni zagon pokaže povezano
SLT gospodinjstvo brez napake. Nova dejanska objava lokalne SLT organizacija
z enim projektom in dvema opraviloma tudi uspešno preide v povezani izbor. Izdani Android (18) tega
novega popravka še nima; nove trgovinske izdaje s tem korakom ne trdimo.

Dodatno pojasnilo protokola: dejanski + Nov prostor ponudi gospodinjstvo/organizacijo.
Osebni del pripravljamo kot obstoječe **Osebno / Moje naprave** z ločenim izrecnim
predogledom, ne izmišljamo nedosegljivega dodatnega osebnega prostora v UI.

Uporabnik je nato na Androidu potrdil prijavo v test2 in prikaz opravila, dogodka,
nakupov ter vrta v SLT gospodinjstvo na **1.4.0**. Izdajni build18 je v Play aktiven,
številke nameščenega builda pa ni posebej navedel. To je dejanski uporabnikov
prenos na drugo napravo; dodatne organizacijske/osebne/finančne vsebine, ponovni
zagoni in izpad še niso potrjeni.

## Dejanska finančna osnova na Macu — 11. oktober

Vsi spodnji zapisi so ustvarjeni skozi aplikacijo na test2, brez SQL vstavljanja.
V **SLT gospodinjstvo** so knjiženi prihodek 50 EUR, odhodek 12 EUR ter notranji
prenos 25 EUR. Ledger pokaže **SLT glavni 138 EUR, SLT A 75 EUR, SLT B 25 EUR**,
skupaj **238 EUR**, prihodek **50 EUR**, odhodek **12 EUR**. Prenos ne ustvari novega
prihodka ali odhodka. Zgornje kartice mesečnega načrta kažejo začetna stanja
100/100/0, zato za kontrolo dejanskega stanja uporabimo spodnji ledger.
Dokaz: `build/qa/server-loss-test-20261011/mac-finance-baseline.png`.
Uporabnik na Androidu potrdi ista trenutna stanja in ustvari opravilo **`Slt android`**.
Mac nato dejansko pokaže isto novo opravilo ob svojem `SLT gospodinjstvo Mac`;
prenos osnovne vsebine/financ Mac → Android in novega taska Android → Mac je
potrjen. Uporabnik je opazil tudi zgornje kartice 100/0/100 EUR; to so začetna
stanja mesečnega načrta, spodnji ledger ostaja 75/25/138 EUR. Uporabnik nato potrdi tudi Androidovo popolno zaprtje/ponovni zagon ter
ohranjene gospodinjske podatke, vrt in zneske; organizacijo/projekt s stroškom
30 EUR in stanjem 70 EUR je pregledal ter potrdil »vse štima«.

Privzeto **Osebno** ima opravilo `SLT osebno Mac` in račun `SLT kartica` z začetnim
stanjem 0 EUR. Ločen predogled Moje naprave potrdi en task/en financialAccount,
potem je zasebna sinhronizacija izrecno vključena. Glava kaže Povezano; podnaslov
Osebno v pickerju še napačno pravi Lokalno/brez sinhronizacije. Ta manjša
neusklajenost prikaza še ni popravljena.

**SLT organizacija** ima svoj task in povezani **SLT projekt** s projektnim taskom.
Projektni ledger ima račun `SLT projektni` z začetnim stanjem 100 EUR ter en
knjižen strošek `SLT projekt strošek 30`: trenutno stanje **70 EUR**, odhodek
**30 EUR**. Organizacijski skupni pregled isti strošek pokaže enkrat.
Dejanje »Plačal sem osebno« in linked-payment razdelek se v trenutnem dejanskem
projektnem prikazu še ne pokažeta niti po uskladitvi. Vzrok preverjamo; osebno
plačilo/povračili nista ustvarjena in tega dela ne označujemo PASS.

Pred nadaljevanjem dejanski Macov status potrdi **Usklajeno** ter 0 čakajočih,
spornih in zadržanih sprememb; dokaz `mac-pre-outage-sync.png` v isti QA mapi.

Ločen test2-only CLI backup helper je naložen v zasebni install, SHA256
`a612a97d0a8a578502604f741bec3007d5a6da68fa28c85480ebb32c319c7053` in 0600
sta preverjena. Dejansko gostovano **read-only --check** potrdi pravo identiteto,
0.11.2/schema15, **1 račun, 2 napravi, 86 tabel in 2 zasebni datoteki**.
Marker ostane vključen. Lokalni sintetični export/restore druge izolirane mock baze
v MariaDB 10.11.19 brez omrežja je PASS (87 tabel/43 vrstic/4 datoteke/2 imenika,
vsi row/file/definition/config/marker hashi enaki); to ni obnovljena gostovana baza.
Gostovani izvoz in njegova dejanska izolirana obnova še nista izvedena.

Strežnik ostaja dosegljiv, marker ni odstranjen, nobena baza ni izbrisana.
Nova kopija test2, izpad in samostojna obnova še čakajo.

## Dva popravka, odkrita med pripravo

**Prvo osebno plačilo novega projekta.** Prazna nova evidenca plačil še nima
`linkedPaymentsRequired`; prejšnji sync jo je zato izpustil. UI pa pravilno zahteva
resničen svež sidecar, preden ponudi prvo osebno plačilo. Popravek v
`collaboration_finance_sync.dart` ob oglaševani zmožnosti prenese pravi začetni
finance3 posnetek tudi za zapisovalni vir organizacije/projekta. Ne postavlja
umetnega fresh. Gospodinjstvo, viewer in strežnik brez zmožnosti ne dobijo novih
bootstrap zahtev. API/strežnik/shema ostanejo isti.
**21 ciljnih PASS**, od tega 9 novih resničnih repository/provider/UI regresij:
prvo plačilo lokalni in zasebno sinhronizirani kartici, napačen scope, omrežje,
zavrnitve, odjava ter sprememba finančnih pravic med odgovorom. Prvotna HEAD koda
negativno potrdi odsotni gumb. `build/qa/linked-payment-bootstrap/` ima dokaze.
Fizično plačilo s tem popravkom še sledi; trenutna odprta Mac gradnja je d627bbe.

**Pregleden predogled kopije.** Iz istega že validiranega dokumenta izračuna
ločene osebne, druge lokalne, prenesene in ohranjene izhodiščne zapise, finance
ter evidence plačil. Privzeti osebni snapshot in po objavi ohranjeni lokalni
posnetki niso sešteti kot dodatni aktivni prostori. Zasebni/skupni obsegi so
ločeni; nedokončani linked-payment intents so vključeni v čakajoče delo.
Opozorilo o omejeni samostojni aktivaciji prenosov/povezanih financ ostane jasno.
Format4/schema8, izvoz in trajni preview JSON ključi so nespremenjeni.
**45 različnih ciljnih PASS**, od tega 6 novih dejanskih SQLite/repository,
crypto encode/decode in SL/EN widget regresij. Ciljna in celotna analiza sta brez
ugotovitev. **Celotni sklop 965 PASS / 13 opt-in preskočenih**, analiza brez ugotovitev;
podpisana nova Mac gradnja še sledi; Androidova
trgovinska izdaja 18 teh novih popravkov še nima.

## Pred začetkom

- Zabeležimo HTTPS izvor, dejanski `serverId`, različico FamilyHub/schema,
  račun in izbrane prostore na obeh napravah. Različice gostovanja ne sklepamo iz kode.
- Test2 ima svojo mapo, bazo, uporabnika baze in zasebno konfiguracijo; ne uporablja
  baze, podatkov, `serverId`, SMTP/FCM ključev ali delavcev obstoječega testnega strežnika.
  Za ta preizkus pošta in push nista potrebna. Račun pripravimo po podprti prijavni poti.
- Pred menjavo prijave izdelamo in dejansko odpremo šifrirano kopijo sedanjih
  podatkov vsake naprave. Izvirne prijave/prostore zabeležimo za vrnitev.
  Aplikacije ne odstranjujemo in njene shrambe ne ponastavljamo.
- Kopije in strežniški rollback hranimo zasebno zunaj javne spletne mape in Gita.
  Gesel, sej, finančnih payloadov in konfiguracij ne vključujemo v dokazni dnevnik.
- Dogovorjen izpad je najprej reverzibilen samo za test2. Pred posegom zabeležimo
  točno tarčo, preverjeno kopijo in način vrnitve. Noben globalni prune/purge ni potreben.

## Sintetična vsebina

Na telefonu in Macu se prijavimo v **isti novi testni račun**. Ustvarimo povezane
osebni del **Osebno / Moje naprave**, prostora `SLT gospodinjstvo`,
`SLT organizacija` in organizacijski projekt `SLT projekt`. Zasebno sinhronizacijo in objavo lokalnih podatkov potrdimo
izrecno. V vsakem prostoru dodamo po eno opravilo; v gospodinjstvu še nakupovalni
seznam, dogodek in vrt. Opravilo na telefonu in drugo na Macu označimo z različnim
besedilom, da je razviden izvor spremembe.

| Primer | Zapis in kontrola pred izpadom |
| --- | --- |
| Običajne finance | EUR račun z začetnim stanjem 100 EUR, prihodek 50 EUR in strošek 12 EUR: 138 EUR, če račun nima drugih premikov. |
| Notranji prenos | Ločena EUR računa, 100/0 EUR; prenos 25 EUR: 75/25 EUR, skupaj 100 EUR, brez novega prihodka/stroška. |
| Povezano plačilo | Ločen projektni strošek 30 EUR, osebno plačilo −30 EUR; povračili 10 in 20 EUR: terjatev 30 → 20 → 0, osebni premiki −30/+10/+20 EUR. Projekt ima en strošek 30 EUR; povračili nista nov strošek/prihodek. |
| Čakajoče delo | Po izpadu ustvarimo `SLT Android offline` in `SLT Mac offline`, spremenimo po eno že preneseno opravilo in pripravimo en navaden finančni zapis, kjer ga UI dopušča. Zabeležimo stanje vrste pred/po ponovnem zagonu. |
| Neuspešna finančna zahteva | Če UI podpira pripravo zahteve brez omrežja, uporabimo **ločen** projektni strošek 7 EUR. Zahteva ostane čakajoča; napake ne razglasimo za potrjeno plačilo. Trajno zavrnjeno zahtevo, če jo dejansko dobimo, zabeležimo posebej in je ne prištevamo potrjenim premikom. |

Če katera možnost v dejanski gradnji ni dosegljiva, jo označimo **ČAKA/OMEJITEV**;
ne ustvarjamo nadomestnih finančnih vrstic ali novih računov neposredno v bazi.
Skupne priponke niso zaključena pot: URL ni prenesena datoteka. Njihove ohranitve
ne potrdimo brez dejanske lokalne datoteke in preverljivega zajema v kopiji.

## A — Ustvarjanje, prenos in ponovni zagon

1. Na obeh napravah osvežimo vse štiri prostore ter posebej finance in povezana plačila.
   Preverimo naslove, zneske in oba delna povračila; v `Vsi` ni podvojenih zapisov.
2. Zapremo in ponovno odpremo obe aplikaciji. Vsebina in povezave ostanejo enake.
   Uspešen oblak mora imeti dejansko dokončan postopek brez čakajočega ali blokiranega dela.
3. Zabeležimo izhodiščne števce po prostorih in številu finančnih zapisov/premikov.
   Identifikatorje in podrobne zneske hranimo le v zasebnih dokazih.

## B — Resnična šifrirana kopija na obeh platformah

1. V uporabniškem toku Kopije izvozimo **dejansko datoteko `.vsakdan`** na vsaki
   napravi; vidno sporočilo o izvozu samo po sebi ni dokaz shranjene datoteke.
2. Izbrano shranjeno datoteko na isti platformi odpremo za predogled s pravilnim
   geslom, pregledamo izvor, števce, čakajoče delo in opozorila nepopolnosti, nato prekličemo obnovo.
3. Zabeležimo velikost in SHA256 vsake datoteke ter jo ohranimo nespremenjeno.
   Kopiji naprav se lahko razlikujeta; obe morata zajeti njuno dejansko preneseno stanje.
   Odjemalska kopija ni celotna kopija strežnika in ne vsebuje sej ali dostavnih skrivnosti.

## C — Reverzibilna nedosegljivost samo test2

1. Po uspešnem B preverimo strežniško kopijo in rollback, nato izključimo samo
   aplikacijsko pot test2 ter njene morebitne delavce. Bazo in datoteke ohranimo.
2. Potrdimo, da test2 ni dosegljiv z obeh naprav, medtem ko obstoječi testni
   strežnik in produkcija ostaneta dosegljiva in nespremenjena.
3. Izpad ne predstavlja preklica članstva, izbrisa računa ali revokacije naprave.
   Trajna odstranitev cPanel namestitve je ločen korak po rezultatih in konkretni
   potrditvi uporabnika; ta protokol je ne izvaja.

## D — Delo brez strežnika, potek seje, zagon in izvoz

1. Preberemo vse prenesene prostore in finance, tudi osebne podatke/povezave plačil.
   Preverimo zadnje znano stanje; neuspešna osvežitev ne sme ustvariti novega zelenega uspeha.
2. Izvedemo vrstice »Čakajoče delo« in »Neuspešna finančna zahteva«, poskusimo
   osvežitev ter zapremo/odpremo aplikaciji. Vsebina in vrsta se ohranita.
   Nedosegljivost ne sme izbrisati ali zakleniti upravičeno prenesenih zapisov.
3. Ponovno izvozimo datoteki na obeh napravah in ju odpremo za predogled.
   Novi offline zapisi in čakajoče delo morajo biti zajeti. Zabeležimo novi SHA256.
4. **Potek seje preverimo ločeno.** Izvorni `SESSION_SECONDS` je 2.592.000 (30 dni),
   zato kratek izpad tega ne dokazuje. Uporabimo naravno poteklo test2 sejo ali
   vnaprej dogovorjeno izolirano pripravo kratke test2 seje. Ure telefona/Maca ne
   prestavljamo; `device_revoked` ni nadomestilo za expiry. Če pogoja ni, ostane **ČAKA**.
   Po dejanskem poteku ponovimo branje, urejanje opravila, zagon in šifriran izvoz.

## E — Samostojna obnova brez starega strežnika

1. Kopijo iz D prenesemo v **ločeno prazno namestitev/profil** z enako preverjeno
   gradnjo, brez prijave in brez dostopa do starega URL. Na Macu je lahko ločen OS
   uporabnik; na Androidu ločen razpoložljiv profil/naprava. Obstoječega profila ne brišemo.
   Če izoliranega cilja ni, tega koraka ne potrdimo na že napolnjeni shrambi.
2. Kopijo odklenemo, pregledamo obnovo in izberemo združevanje v prazni cilj.
   Pod »Obnovljeno skupno delo« uporabimo **Nadaljuj lokalno**, pregledamo omejitve
   in izrecno potrdimo ustvarjanje novih lokalnih prostorov.
3. Preverimo nove lokalne ID-je in preslikane povezave opravil/projektov, nove
   lokalne prostore, branje/urejanje brez računa ter ponovni zagon in nov izvoz.
   Podatkovna kontrola ID-jev sme biti read-only in mora uporabljati izključno testni profil.
4. Izvirna datoteka ima isti SHA256; ohranjen obnovitveni paket mora še vsebovati
   izvorne ID-je, operacije in arhivske finančne podatke. Pretvorjenih ID-jev ne
   zapisujemo nazaj v izvirni arhiv. Ponovitev iste potrditve ne ustvari novih dvojnikov.
5. **Prenosi med računi in strežniško vezana povezana plačila se v trenutni
   samostojni pretvorbi ne aktivirajo.** Ostanejo v šifriranem arhivu; prikaz mora
   povedati »Finančni pregled še ni popoln …«. Nov lokalni balans zato ni dokaz
   popolne finančne obnove. Prenesena projekcija iz D in nova pretvorba iz E sta ločena rezultata.

## F — Vrnitev in nova povezava

1. Za rollback vrnemo **isto test2 namestitev z istim `serverId`**. Na prvotnih
   napravah preverimo sveže pravice in dovoljen nadaljnji sync: oba offline naslova
   prispeta enkrat; finančni zapis in ponovljene zahteve ne podvojijo premikov.
2. Povezava lokalne obnovljene kopije na nov strežnik je ločen izrecen predogled
   objave. Nove identitete ne smejo dobiti starih sej ali samodejno poslanih starih operacij.
3. Če pozneje preverimo prazno novo namestitev na **istem test2 URL z drugim
   `serverId`**, najprej ohranimo rollback stare. Zaznana menjava identitete mora
   ustaviti overjeni promet pod staro identiteto in ohraniti lokalno vsebino.
   Ponovno uporabljeno uporabniško ime/številčni ID samo po sebi ni isti račun.

## Zapis rezultatov in merilo zaključka

Za vsak korak zabeležimo datum, platformo/gradnjo, **PASS / FAIL / ČAKA**, kratek
dejanski izid in zasebno pot do dokaza. Trenutno so A–F **ČAKA**. Navedbe zgoraj
so pričakovanja in znane meje, ne rezultati novega fizičnega preizkusa.

Predhodni [dokazi prostorov](../SPACES_UPGRADE_IMPLEMENTATION.md) poročajo o
lokalnih avtomatiziranih preizkusih ohranitve po expiry, novih lokalnih ID-jev,
nespremenjenega arhiva ter dejanskem izoliranem Dart/HTTP preverjanju plačila
30 EUR z dvema povračiloma in ponovnim odprtjem SQLite. Ti ne nadomeščajo A–F.
Aktualni tok določa tudi [pogodba povezanih plačil](linked-payments-api-contract.md).

Ob izgubi zapisov, dvojnih finančnih premikih ali samodejnem prometu pod drugo
identiteto preizkus ustavimo, ohranimo obe lokalni shrambi in kopije ter vrnemo
test2 po rollbacku. Trajna odstranitev ni merilo uspeha: uspeh zahteva preverjeno
ohranitev, dejanski izvoz/obnovo in jasno navedene neopravljene kontrole ter finančne meje.
