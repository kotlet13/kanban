# Opomnik za ustvarjalca opomnika in zadolžene — 5. november 2026

Po potrjenem popravku starega prostora na iPhonu je uporabnik naročil naslednji
korak: ročni opomnik pri opravilu, dodeljenem drugemu računu, naj prejmeta
nastavljalec opomnika in zadolžena oseba. Implementacija je lokalna; trenutni
produkcijski strežnik in nameščeni aplikaciji te nove funkcije še nimajo.

## Vedenje

Pri novem opomniku za opravilo na podprtem strežniku urejevalnik privzeto
izbere **»Ti in zadolženi ob času opomnika«**. Možna je tudi izbira **»Samo ti«**.
Oba načina časa (konkreten datum/ura in glede na rok) uporabljata isto pravilo
prejemnikov. Opomniki dogodkov in financ ostajajo osebni.

Prejemnike ob zapadlosti sestavljajo nastavljalec ter takrat zadolženi iz
trenutnih podpisanih metapodatkov opravila. Isti račun je v naboru samo enkrat;
nedodeljeno opravilo še vedno opomni nastavljalca. Vsak prejemnik mora imeti
trenutni dostop in obdrži svoje nastavitve posameznih dostavnih kanalov.

Urejanje starega osebnega opomnika ohrani osebno izbiro, dokler je uporabnik
izrecno ne spremeni. Stare čakajoče zahteve in podpisani opomniki se ne
razširijo ob nadgradnji. Opomnik še naprej ureja ali prekliče njegov lastnik;
zadolženi prejme obvestilo, ne novega dovoljenja za urejanje tuje nastavitve.

## Pogodba in varovala

- Nova zmožnost je `features.taskReminderRecipients`. Starejši strežnik
  ponudi osebni opomnik. Izguba zmožnosti ne prepiše že čakajoče nove namere.
- Neobvezno polje `recipientPolicy: schedulerAndTaskAssignees` se ob
  shranitvi zapiše v isti transakciji z lokalnim opomnikom in vrsto ukazov,
  nato v nespremenljivo podpisano zahtevo. Odsotno polje pomeni osebno
  vedenje. Prosti seznam poljubnih prejemnikov ni podprt.
- Odgovor se primerja s politiko v prvotni podpisani zahtevi; strežniški
  odgovor ne sme dodati ali odstraniti prejemnikov iz prikazane namere.
- Razširjena dostava zahteva obstoječo pravico urejanja konkretnega
  opravila. Poznejša izguba te pravice zadrži dostavo drugim; veljaven osebni
  opomnik nastavljalca ostane dovoljen.
- Strežnik ohrani eno lastniško vrstico opomnika. Nova politika se bere iz
  že shranjene podpisane zahteve, brez migracije sheme. Stari identifikatorji
  dogodkov ostajajo enaki; novi povezani dogodki uporabljajo omejen ključ
  `r2a:<reminder UUID>:<revision>` za ponovno preverjanje pred dostavo.
- Zaključek opravila, preklic, nova revizija opomnika, izguba dostopa ali
  sprememba zadolženega se ponovno preverijo pred push/e-pošto in odprtjem.
  Spremembe zadolženega in arhiviranje projekta sprožijo obstoječi mehanizem
  ponovne uskladitve že prenesenih obvestil. Novo skupno preklicevanje se
  uskladi z dostavnim delavcem prek istega zaklepa prostora.

## Povezana napaka prikaza

Prejemnik nima lastniške vrstice tujega opomnika. Njegov samodejni lokalni
opomnik ob roku opravila je zato lahko še v prihodnosti. Stara projekcija je
zaradi tega skrila že dostavljeni ročni opomnik. Dostavljeni opomnik drugega
uporabnika je zdaj neodvisen od prihodnjega roka in lastnih osebnih nastavitev
istega opravila. Nastavljalec je v novem inbox dogodku naveden kot avtor.

Izrecni dremež na napravi še naprej odloži prikaz. Za razlikovanje od
samodejnega roka ima izpeljani `ReminderPlan` prehodno zastavico `isSnoozed`,
ki jo nastavi samo uspešno preverjeni obstoječi SQL dremež. Ta zastavica ni
nova strežniška ali trajna shema.

Ločen samodejni lokalni opomnik ob roku ostaja ločen tok. Preprečevanje
podvajanja tu pomeni isti strežniški opomnik/revizijo istemu računu, ne
zagotovila, da se ne more časovno ujemati z neodvisnim lokalnim opomnikom.

## Lokalna preverjanja

- 8 novih widget primerov: mobilna in namizna širina, nova privzeta izbira,
  izrecno osebni način, urejanje starih in novih opomnikov, stari strežnik,
  izbira glede na rok ter izguba zmožnosti med odprtim urejevalnikom — PASS.
- 5 novih projekcijskih/SQL dremež kontrol — PASS; en prizadeti obstoječi
  test dremeža prilagojen označeni izrecni odložitvi in preverjen enkrat.
- 11 novih odjemalčevih podatkovnih kontrol — PASS: modeli, ohranitev
  čakalne vrste, izguba zmožnosti, neustrezen ACK in lastniški preklic;
  pet primerov uporablja prave podpisane dokaze.
- 74 novih PHP kontrol — PASS: oba prejemnika, podvajanje, lastništvo,
  osebna združljivost, nastavitve, spremembe dodelitve, zaključek, preklic,
  izguba pravic, veljavna relativna consent pot, vezava povezave in projekt.
- Ciljna analiza 20 Dart vhodov: 0 napak in 0 opozoril, 2 stari informativni
  pripombi v kontrolerju zunaj spremembe. `flutter gen-l10n` izveden.

Prvi skupni root tek je imel napako manjkajočega importa v novem
projekcijskem testu; vseh 8 UI primerov je v istem izhodu posamično uspelo in
se niso ponovili. Samo projekcija je po popravku uspela v drugem teku.
Odjemalčev prvi podatkovni tek je imel napačno tipizirane testne capabilities;
drugi je razkril manjkajoči izrecni sintetični metadata router v fixture.
Pet primerov je uspelo prvič, eden drugič, štirje tretjič. Produktnih varoval
zaradi teh napak nismo spremenili. PHP prvi tek je obstal pri strogi primerjavi
vrstnega reda testnega polja pred prvo kontrolo; po popravku 50 PASS, nato
ločeno 17 novih dodatnih kontrol in 7 novih kontrol zaklepa pri preklicu. Uspešnih primerov nismo ponavljali.

Enote uporabljajo prave modele, SQL, podpisovanje in produkcijska varovala;
nekateri transportni in sprejemni robovi so sintetični. Celotni lokalni HTTP
preizkus z dvema ohranjenima računoma je opisan po zaključku spodaj.

Dokazi: `build/qa/task-reminder-recipients-20261105/` in
`build/qa/reminder-recipients-http-20261105/`. Zasebne kopije, ključi in seje
so ignorirani in niso del repozitorijskih dokumentov.

## Meje

Predhodno odkrita začetna manjkajoča consent generacija pri nekaterih novih
relativnih opomnikih ostaja ločena napaka; to delo ne spreminja podpisane
zgodovine zaradi njenega obhoda. Naravni HTTP scenarij uporablja uporabnikov
konkretni datum in uro. Obstoječa veljavna relativna pot ima novo lokalno PHP
kontrolo.

Google Play, App Store, produkcijski strežnik in fizična nova dostava te
funkcije niso spremenjeni ali potrjeni s temi lokalnimi rezultati. iPhone je
bil na uporabnikovo zahtevo zaklenjen prek Device Hub → Controls → Lock;
poznejši posnetek je potrdil črn zaslon. Pri tem je nameščeni prejšnji popravek
starega prostora še vedno prikazoval uspešno sinhronizacijo.


## Končni pregled in HTTP meja

Neodvisni pregled je našel še ozko neskladje med trenutnim podpisanim PUT
in starejšim `putAuthorization` pri branju seznama. Dodana je primerjava
njune politike prejemnikov; nov negativni test z dvema dejansko veljavnima
podpisoma različnih politik je **PASS1**. Prejšnjih 10 uspešnih podatkovnih
primerov se ni ponovilo. Končna analiza tega vira in testa je brez pripomb.
Drugi pregled je potrdil strežnik in projekcijo brez odprte blokade v kodi;
sočasni preklic uporablja nov zaklep prostora in ponovno preveri lastnika
ter revizijo. Sedem novih kontrol preverja ta vrstni red in escape poti.
To niso dokazi dejanske vzporednosti na MariaDB.

Celotni HTTP scenarij **NI PASS**. Uporabljena je nova izolirana kopija
ohranjene namestitve z dvema obstoječima računoma; originalni preklicani
owner device ni uporabljen, temveč že obstoječi veljavni recovered-owner in
drugi račun. Prijava, registracija, deljenje in FILE obnova se niso ponovili.
Exact originalni lokalni URL je ohranjen zaradi vezave particije; znana
ovojnica varne shrambe je prilagojena samo za branje istega materiala.

| Poskus priprave | Izid | Dosežena meja |
| --- | --- | --- |
| 1 | FAIL_SETUP | V novem ogrodju manjka inicializiran Flutter messenger; 0 API zahtev. |
| 2 | FAIL_SETUP | Flutter testni binding prestreže HTTP in vrne sintetični 400; 0 zahtev do PHP. |
| 3 | FAIL_SETUP | Docker internal omrežje ni vzpostavilo zahtevanih objavljenih vrat; povezava odpove pred API odgovorom. |

Po izrecnem pravilu največ treh poskusov iz `AGENTS.md` je preizkus ustavljen.
Ni bilo četrtega teka, ponastavitve ali novega računa/fixture za obhod meje.
Zapisane zahteve za objavo vrat v Docker konfiguraciji ne pomenijo dejansko
povezanih vrat; njegov `NetworkSettings.Ports` je bil prazen. Prejšnje delujoče
lokalno okolje je uporabljalo bridge. Ta okoljska razlika je diagnoza za
nadaljevanje, ne že izveden popravek ali potrjena HTTP povezava.

**BLOCKED/NEIZVEDENO:** ustvaritev novega opravila in opomnika skozi ta HTTP
scenarij, naravna zapadlost, zajem provider ovojev, odprtje obeh push referenc
in projekcija po pravi HTTP poti. Posledično ni potrjena nova fizična
dostava iPhone/Android ali odsotnost sync napake po takem kliku. Strežniški
unit/komponentni worker testi so ločen dokaz in tega ne nadomestijo.

Namenski lokalni vsebnik je ustavljen in ohranjen. Vse tri datoteke dnevnikov
in števec, SQL kopiji, ključi ter FILE ostanejo shranjeni. Vsi izvorni hashi,
obe kopirani obnovitveni datoteki in kopirana varna shramba so nespremenjeni.
0 scenarijskih API zahtev je doseglo PHP; Dockerjeva privzeta lokalna
healthcheck GET branja so ločena in niso scenarijski HTTP preizkus.

Končni rezultat priprave je `build/qa/task-reminder-recipients-20261105/implementation-result.json`
in `build/qa/reminder-recipients-http-20261105/http-outcome.json`. Za pregled
je pripravljen `server-source-review.zip` z natanko dvema PHP datotekama ter
manifestom hash vrednosti. Paket ni nameščen. App različica, shema in
odvisnosti niso zvišane. Potreben je zaključek ohranjenega HTTP scenarija
pred živo nadgradnjo in novim fizičnim preverjanjem.

## 6. november – ista lokalna namestitev in tri dodatne izvedbe

Uporabnik je odobril tri nove teste. Lokalna namestitev uporablja kopiji
starejših sintetičnih računov. Produkcijski prostor `test_gosp` je bil
uporabljen posebej za opazovanje ročnega preverjanja na iPhonu.

| Izvedba | Izid |
| --- | --- |
| R4, priprava | Docker je na `127.0.0.1:57881` pravilno objavil vrata. Prvi anonimni klic je uspel. Prvi overjeni klic je zaustavila razlika med zapisom lokalnega naslova brez končne poševnice in normaliziranim naslovom. |
| R5, priprava na isti kopiji | Testni adapter je uporabil kanonični omrežni naslov in ohranil izvorno lokalno particijo obeh računov. Običajni podpisani pregled je preveril oba obstoječa zapisa in obnovil zaščito istega prostora za ista člana. Opravilo je nastalo. Od skupno 634 zahtev obeh odjemalcev v približno 15,4 s je zadnja dobila odgovor HTTP 429. Opomnik v tej izvedbi še ni bil ustvarjen. |
| R6, nadaljevanje od obstoječega opravila | Oba odjemalca sta preverila isto opravilo. Strežnik je sprejel en absolutni opomnik. Ob naravnem roku je worker ustvaril dve obvestili, vsako za svoj račun. Zajeti sta bili dve sporočili za potisno obvestilo, po eno na račun. |

V R6 je preizkus nato padel pri svoji prvi pretvorbi sporočila za
odpiranje. Androidovo sporočilo različice 2 vsebuje devet polj. Test je
vseh devet poslal metodi `RemotePushReference.parse`, ki pričakuje štiri.
Dejanska Firebase pot v aplikaciji najprej izbere štiri referenčna polja
s `SystemPushMessage.referenceData`. Izjema je nastala v testu **pred**
`openRemotePushReference`. Odprtje opravila in stanje sinhronizacije po njem
sta za oba računa še nepreverjena. Zajeti sporočili, inbox vnosa in že
dostavljeni opomnik so ohranjeni za ciljno nadaljevanje.

Zunanjih zahtev za pošiljanje v Firebase je bilo nič. Obe dejanski napravi
in nova Android gradnja za ta opomnik še potrebujejo fizični preizkus.
Ločena meritev gumba na produkcijskem iPhonu je v
[zapisniku iPhona](REMINDER_PHYSICAL_SETUP_2026_11_05.md).

### Ločeni preizkus odpiranja dveh dostavljenih obvestil

Po dodatni izrecni odobritvi je bil izveden **en** preizkus samo za
odpiranje (R7). Test je z dejansko funkcijo `SystemPushMessage.tryParse`
iz vsakega ohranjenega sporočila za Android pridobil referenco ter zanjo
poklical običajno pot `openRemotePushReference`. Vsak račun je uporabil
svojo sejo in referenco svojega inbox vnosa.

| Račun | Rezultat odpiranja in preverjanja | Čas celotnega koraka v lokalnem preizkusu |
| --- | --- | ---: |
| Nastavljalec | Pravo opravilo in njegov inbox vnos, `available`, vidno obvestilo, brez sync napak ali čakajočega dela | 3,61 s |
| Zadolženi | Isto opravilo in njegov lastni inbox vnos, `available`, vidno obvestilo, brez sync napak ali čakajočega dela | 2,78 s |

Za ta klik ni bilo novega opomnika, opravila, pošiljanja ali zagona
dostavnega workerja. Ob odpiranju je rok opravila že potekel. Pokritost
prikaza pred prihodnjim rokom v tem HTTP preizkusu zato ostaja odprta.
Zabeležen je rezultat lokalne aplikacijske poti s prestreženimi potisnimi
sporočili. Pred javno izdajo ostaja preizkus pravega sistemskega prejema in
dotika na Androidu s kandidatno gradnjo in podprto različico strežnika.

Dokazi so v `build/qa/reminder-recipients-http-20261105/`, vključno z
`open_both_push_references-renewal-20261106-r7.log`. Zgodovinski
`http-outcome.json` še vedno opisuje prvotno ustavitev po tretjem poskusu.

## 7. november – produkcijski strežniški popravek nameščen

Po izrecnem naročilu uporabnika je bila ob 21:02:51 UTC (22:02:51 lokalno)
izvedena ena namestitev dveh PHP datotek iz commita `9c265b6` na
`jivie.triparna.si`. Prejšnji hashi obeh datotek in konfiguracije so se
ujemali s pričakovanimi. Preneseni ZIP SHA-256:
`5ee56bbedd982c1963af456e19c7fc5f2d8b9445ca8f2e36e26ea5e710bd54f9`.
Strežniški helper je potrdil PHP 8.4 lint, varnostno kopijo, zamenjavi in
končna hasha; NativeService s capability je zamenjan zadnji.
Kopija je v `/home/tripar13/private/jivie-production/reminder-recipients-20261107/before`.
Ni migracije sheme, neposrednega dostopa do baze ali spremembe konfiguracije,
poverilnic, ključev oziroma cron nastavitev.

Javni HTTPS capabilities po namestitvi: HTTP 200, ista identiteta strežnika,
`features.taskReminderRecipients=true`; edina sprememba v features je ta
nova zmožnost. To potrjuje namestitev in oglaševanje funkcije, ne fizične
push dostave. Pravi prejem in klik na Androidu z 1.11.18 (50) ostajata za
preizkus. Ločena težava relativnih opomnikov ostaja odprta.
Dokazi: `build/qa/reminder-server-deploy-20261107/verified-outcome.json`,
manifest ter capabilities-before/after.json. Uspešnih lokalnih testov nismo
ponavljali, novih opomnikov ali pošiljanj nismo ustvarili.
