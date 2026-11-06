# Fizična priprava preizkusa opomnikov — 5. november 2026

## Obseg in trenutno stanje

Uporabnik je po lokalni diagnostiki dovolil nadaljevanje na iPhonu z njegovim
obstoječim računom, ločen nov testni račun na Macu in dve povabili. Namen je
preveriti absolutni opomnik z določenim datumom in časom ter odpiranje
konkretnega opravila po prejemu push obvestila. Relativni opomnik je ločena
lokalna ugotovitev, ne potrjen vzrok uporabnikove napake ob tapu.

**Native prejem in samodejno odpiranje pravega opravila po uporabnikovem
sistemskem »Odpri« sta PASS, z zamikom. Stara napaka metadata ostaja.** Mac
ima ustvarjen račun, potrjen e-poštni naslov in shranjeno obnovitveno datoteko;
povabilo je sprejeto in dostop do izbranega dešifriranega gospodinjstva je
potrjen. Po izrecni uporabnikovi potrditvi so pravila sodelovanja sprejeta in
eno opravilo z Maca ustvarjeno ter dodeljeno računu na iPhonu. Njegov prejem
in odpiranje v aplikaciji sta PASS; sistemskega push obvestila v prvem
opazovanem oknu ni bilo. Bralno je bila potrjena manjkajoča APNs konfiguracija
v istem Firebase projektu; pozneje je uporabnik izrecno dovolil ureditev
razvojnega Sandbox ključa. Prvi poskus shranjevanja absolutnega opomnika za
lastni račun je obstal pri ločenem sprejemu pravil na iPhonu. Po poznejši
uporabnikovi potrditvi je strežniški worker opomnik obdelal po prvotnem roku
in ustvaril eno due inbox obvestilo; njegov iOS push job je preklican.
Obvestilo opomnika je na iPhonu vidno in en tap v aplikaciji odpre pravo
opravilo: **in-app prejem in odpiranje absolutnega opomnika PASS**.
Pravočasna ali native dostava s tem nista potrjeni.
Po novi APNs nastavitvi je bil isti opomnik enkrat urejen na prihodnji termin.
Po enem ročnem syncu je strežniška razporeditev novega termina potrjena.
Worker ga je ob novem roku obdelal in ustvaril eno due obvestilo; novi iOS
push job je bil na prvem pregledu še v čakanju s številom poskusov 0.
Ob 20:21:42,444 UTC je nato opažen pravi sistemski opomnik. Uporabnik je
pritisnil sistemski **Odpri**; aplikacija se je odprla, prikaz konkretnega
opravila je nato brez dodatnega usmerjanja samodejno sledil okoli 20:24 UTC.
Ta dokument je končni zapis tega fizičnega scenarija in njegovih meja,
ne dokaz celotne uspešne sinhronizacije ali produktni popravek.

Predhodna lokalna faza in njene omejitve so opisane v
[REMINDER_SYNC_DIAGNOSTICS_2026_11_05.md](REMINDER_SYNC_DIAGNOSTICS_2026_11_05.md).
Tam navedeni ničelni posegi na telefonih veljajo za tisto fazo; tukaj so
zabeleženi pozneje izrecno dovoljeni fizični koraki. Nova objava v trgovinah
ali globalna namestitev strežniškega izdelka nista del tega nadaljevanja.

## iPhone: običajna nadgradnja iste namestitve

Na iPhonu je obstoječa aplikacija nadgrajena iz **1.11.3 (35)** na
**1.11.17 (49)** z isto identiteto aplikacije, podpisnim potrdilom in
vgrajenim provisioning profilom. To ni namestitev ločene QA aplikacije,
ponovna namestitev ali ponastavitev podatkov.

Prvi novi poskus gradnje se je končal neuspešno z izhodom 65 po 54,28 s;
drugi je uspel po 59,68 s. Uspešna gradnja ni bila ponovljena. Dejanski
artefakt ima preverjen strict/deep podpis, enake podpisane entitlements kot
35, nespremenjene odvisnostne ključavnice in Firebase konfiguracijo ter
**665 natančnih izvornih vhodov**. Runtime QA dodatkov ni. Edina podpisna
prilagoditev uporablja obstoječi razvojni podpis in razvojno APNs okolje;
to ni App Store distribucijski paket ali dokaz produkcijske APNs dostave.

Opravljena je ena nadgraditvena namestitev. Pred prvim zagonom nove različice
je primerjava hladnega stanja potrdila **vseh šest ohranjenih datotek brez
spremenjenega bajta**, brez novih datotek. Postopek tega preverjanja ni bral
ali pisal Keychaina. Takšna primerjava potrjuje ohranitev teh datotek do
zagona, ne nespremenljivosti vseh podatkov po poznejši običajni uporabi.

Dokazi: `build/qa/ios-production-upgrade-20261105/` vsebuje
`artifact-evidence.json`, izida obeh poskusov gradnje, izvorni manifest in
manifest datotek aplikacije. Zasebni dokaz `preservation-before-launch.json`
ostaja zunaj Gita v namenski mapi fizičnega preizkusa.

## Obstoječi račun, začetna napaka in povabilo

Omejeni bralni strežniški pregled obstoječega računa je imel dva neuspešna
diagnostična poskusa; **tretji poskus je uspel**. Potrdil je obstoj aktivnega
native računa. Vsi trije poskusi skupaj imajo **nič zapisov v bazo**. Rezultat
ni dokaz zgodovinskega izbrisa ali neizbrisa računa po e-poštnem naslovu;
takšna zgodovinska pripisljivost ni bila potrjena.

Po zagonu 49 je bila na iPhonu **že pred fizičnim push preizkusom** opažena
napaka sinhronizacije v fazi `metadata`, z razlogom
`crypto_reconciliation_required`. Zajem tedaj kaže nič potrjenih content in
finance strani oziroma uporabljenih zapisov. Ker je napaka obstajala pred
novim push dogodkom in tapom, je ne pripisujemo temu dogodku.

Na iPhonu je bilo nato sprejeto novo povabilo v uporabnikovo resnično
produkcijsko gospodinjstvo `test_gosp`, ustvarjeno za ta preizkus. To ni
sintetični lokalni fixture. Obstoječi račun in njegova namestitev sta
ohranjena. Sprejem sam po sebi ne potrjuje celotne sinhronizacije, dostave
opomnika ali uspešnega
odpiranja iz push obvestila. Mac je drugo povabilo sprejel, nato pa je bil po
spodaj opisanem preverjanju dostopa odprt dešifrirani prostor. Celotni
večnapravni tok sistemskega push opomnika še ni potrjen; poznejši in-app izid
opravila je naveden spodaj.

Uporabniški tok preverjanja obstoječe obnovitvene datoteke je v **enem
poskusu PASS** pokazal, da izbrana datoteka odklene ključe tega računa.
Opravljeno je bilo preverjanje datoteke, **ne obnova računa**, ponovna izdaja
ključev ali obnova namestitve/podatkov. Tega izida ne štejemo kot preizkus
celovite obnovljivosti naprave.

Na iPhonu je bilo sistemsko dovoljenje za obvestila že vključeno, napravni
vklop oddaljenih obvestil v aplikaciji pa je bil sprva izključen. Za dovoljeni
preizkus je bil vključen enkrat; aplikacija nato pokaže **»Naprava je
registrirana.«** Push nastavitev gospodinjstva `test_gosp` je bila že
vključena. Globalne ali prostorske nastavitve kategorij niso bile spreminjane.
Zasebni `iphone-push-registration.json` in posnetek ohranjata ta checkpoint.
To potrjuje registracijo naprave, ne dejanske APNs dostave ali odpiranja
opomnika. Poznejši bralni pregled APNs konfiguracije je opisan spodaj.

Za nadaljevanje je bil iPhone s sistemskim Home poslan v ozadje. V kategoriji
opravil so potrjeno že vključeni in-app, zvok in push, e-pošta pa je izključena;
nastavitve so ostale nespremenjene. Pri spodaj opisanem novem opravilu
sistemsko obvestilo ni bilo opaženo; in-app obvestilo je bilo pozneje odprto
po običajnem zagonu aplikacije.

Zasebni diagnostični rezultati so v
`/Users/anzenovsak/JivieTestAccounts/20261105/`, ločeno od repozitorija.
Poverilnice, naslovi, identifikatorji računov/naprav, žetoni, podpisane
zahteve in vsebina obnovitvenih datotek niso vključeni v ta zapis.

## Mac: ločena nova testna namestitev

Za drugi račun je izdelana nova izolirana **1.11.17 (49)**, z ločenim imenom
aplikacije, sandboxom, Keychain storitvijo in edino lastno Keychain skupino.
Obstoječe namizne aplikacije, njihovi računi in podatki niso uporabljeni kot
cilj te namestitve. URL handlerja sta odstranjena, da testna aplikacija ne
prevzame povezav drugih namestitev.

**Ena release gradnja PASS**, 94,887 s skupaj s pripravo odvisnosti; brez
ponavljanja starih funkcionalnih testov. Vseh **648 vhodov** v glavnem izvoru
in zamrznjeni kopiji je po gradnji enakih. Natančno šest overlay datotek
spreminja samo identiteto/ime, obstoječe podpisovanje, izolacijo Keychaina in
odstranitev URL handlerjev. Ni dodatnih testnih kavljev, posebnega CA ali
spremenjenega omrežnega transporterja.

Strict/deep podpis in dejanski sandbox sta preverjena. Obstoječi podpisni
profil iste ekipe velja do 10. oktobra 2027. Po eni ločeni namestitvi je
preverjenih 199 datotek; druge aplikacije niso bile spremenjene. Začetni
namestitveni zapis še ima nič zagonov, ker je nastal pred poznejšo dovoljeno
pripravo računa; to ni trditev o trenutnem številu zagonov.

Mac račun je registriran in njegov e-poštni naslov potrjen. Kombinirana
obnovitvena datoteka je shranjena zunaj Gita: **725 bajtov, dovoljenja 0600**;
zasebni `mac-file-export.json` ohranja dokaz izvoza. Vsebina datoteke ni
vključena v dokumentacijo. Povabilo je bilo sprejeto, UI pa je sprva pokazal
čakanje na pošiljateljevo podelitev ključev. Nadaljnji **Preveri
dostop / Check access** je prvič še pokazal čakanje, drugič pa podeljen dostop.
Na Macu je nato izbran in odprt dešifrirani `test_gosp`: **dostop PASS**.
To ni samodejno dokaz celotne sinhronizacije ali dostave opomnikov.

Uporabnik je na S25 sporočil, da je push za odobritev prispel z zamikom.
To je opažanje dostave odobritvenega obvestila, ne absolutnega opomnika.
Pošiljateljeva podelitev ključev je po drugem preverjanju dostopa potrjena.

Na Macu je pripravljen en obrazec opravila z naslovom
`TEST PUSH 05-11 Mac v iPhone`, zadolžen pa je samo obstoječi testni račun
na iPhonu. Ob prvem Save se je odprl pogoj sprejema pravil sodelovanja;
po poznejši izrecni uporabnikovi potrditvi so bila pravila sprejeta in
**opravilo enkrat ustvarjeno ob 19:32:26 UTC**. Mac je ob 20:32 po lokalnem
času pokazal usklajeno stanje brez čakajočih, konfliktnih ali blokiranih
sprememb. To potrjuje ta zapis in Macov prikaz, ne fizične dostave push.

Mac nima podprte sistemske FCM dostave; v tem preizkusu je drugi odjemalec
za račun, deljenje in inbox, iPhone pa predvideni prejemnik sistemskega push.

Dokazi: `build/qa/reminder-sync-20261105/mac49/` vsebuje `source-plan.json`,
`overlay.diff`, `artifact.json`, `build-result.json`, dnevnike in
`installation.json`. Zasebna kopija izvora in artefakt ostajata v namenski
mapi `JivieLocalTest`, brez kopiranja starih računov ali Keychain vsebine.

## Opravilo, in-app izid in strežniški izid absolutnega opomnika

Med 20:32 in 20:36 po lokalnem času (19:32–19:36 UTC) v centru obvestil na
iPhonu ni bilo opaženo novo sistemsko obvestilo o dodeljenem opravilu.
Nov omejeni bralni pregled vrste je **R1 PASS ob 19:36:05 UTC**: strežnik je
ob 19:32:27 UTC ustvaril eno inbox obvestilo `crypto2.task.assigned`.
Povezani push job je `cancelled`, z enim poskusom. Ujemajoča se iOS
registracija je aktivna; job ni bil pretečen ali zadržan v lease, čas
uspešnega pošiljanja pa je prazen. Napaka ponudnika ni trajno shranjena,
zato konkretni razlog preklica ostaja **neznan**. To ni dokaz uspešne FCM/APNs
dostave in fizični tap tega sistemskega obvestila ni bil izveden.

Nov bralni pregled dostavnih varoval je **R1 PASS ob 19:43:18 UTC**:
pregledana trenutna varovala so izpolnjena, zgodovinski job pa ostaja
`cancelled`. Napake ponudnika ni mogoče obnoviti iz trajne evidence.
Pošiljanje ni bilo ponovljeno, job ni bil ponovno aktiviran in varovala niso
bila obita.

Bralni pregled Firebase konzole je za **isti projekt in bundle ID kot v
nameščeni 49** potrdil: ni razvojnega APNs auth ključa, ni produkcijskega
APNs auth ključa in ni nobenega razvojnega ali produkcijskega APNs
certifikata. FCM HTTP v1 je vključen. Ujemanje je neodvisno preverjeno s
konfiguracijo zamrznjenega izvora, generiranimi definicijami in AOT artefaktom
nameščene aplikacije. To je **potrjena konfiguracijska vrzel za iOS dostavo**;
ni ohranjena koda napake ponudnika, ki bi dokazala konkreten razlog preklica
prejšnjega joba. Firebase nastavitve niso bile spremenjene, ključ ali
certifikat ni bil ustvarjen ali naložen. Ta iOS ugotovitev ne dokazuje vzroka
prvotne uporabnikove Android napake po tapu. Zasebna dokaza sta
`firebase-apns-observation.json` in pripadajoči posnetek.

Po običajnem ponovnem odprtju aplikacije je iPhone v inboxu prikazal
**»Dodeljeno ti je 1 opravilo«**. Odprto je bilo pravo opravilo: **in-app
prejem in odpiranje PASS**. Tega ne štejemo kot odpiranje iz native push
obvestila. Novo opravilo in prejšnja napaka `metadata` sta ločeni opažanji;
podlaga prvotne napake ostaja nepotrjena.

Ob **19:40:24 UTC** je bil izveden prvi poskus shranjevanja absolutnega
opomnika za lastni račun z ročno določenim časom **20:45 lokalno oziroma
19:45 UTC**. Naknadno je bilo ugotovljeno, da je ta poskus na iPhonu
zadržal pogoj sprejema pravil sodelovanja za njegov račun. Prejšnji zapis o
»shranjenem opomniku« zato ni bil dokaz strežniške razporeditve.

Uporabnik je ločen sprejem pravil na iPhonu izrecno dovolil;
**sprejeta so bila ob 19:48:22 UTC**, ko je prvotni termin 19:45 UTC že
potekel. Začela se je samodejna sinhronizacija. Težava s pravili v UI ni več
prikazana, ostaja pa prejšnja napaka `metadata` starega prostora.

Ločen bralni strežniški pregled po sprejemu pravil je bil izveden enkrat:
**R1 PASS ob 19:52:24 UTC, nič zapisov v bazo**. Potrjuje natanko en
absolutni opomnik za lastni račun, z revizijo 1, revizijo tarče 1 in
prvotnim terminom 19:45 UTC. Strežniški status opomnika je `delivered`.
Natanko eno due inbox obvestilo je nastalo **ob 19:49:01 UTC**, z vključenim
in-app kanalom, še neprebrano, z revizijo 1 in revizijo tarče 1.

Naravni worker ga je torej obdelal po sprejemu pravil ob 19:48:22 UTC in
**po prvotnem roku**, brez ponovnega ustvarjanja ali spreminjanja termina.
Status `delivered` tu potrjuje strežniško obdelavo in nastanek inbox
obvestila, ne pravočasnega sistemskega prejema na telefonu.

Natanko en ujemajoči se iOS push job je `cancelled`, z enim poskusom,
aktivno registracijo in ujemajočo se revizijo registracije. Ni pretečen,
čas uspešnega pošiljanja je prazen. Odgovor ponudnika ni ohranjen; ni bilo
nove zahteve ponudniku, ponovnega aktiviranja joba ali prerazporeditve
opomnika. **Native prejem in tap ostajata NEPASS**.

Na iPhonu je stabilni sync dialog ob 20:51 po lokalnem času še prikazoval
samo predhodno napako `metadata` starega prostora; težave s pravili ni več.
Končni seznam obvestil nato vsebuje **»Čas je za opomnik«**, oznako **»Zame«**,
prostor `test_gosp` in čas **20:49**, poleg dodelitve ob 20:32. En tap tega
in-app opomnika odpre isto pravo opravilo `TEST PUSH 05-11 Mac v iPhone`;
ujemajo se naslov, opombe, zadolženi račun in avtor. **In-app prejem in
odpiranje tarče PASS**. To ni native push ali tap sistemskega obvestila,
niti pravočasna dostava za prvotni termin 20:45. S tem je bil zaključen ta
checkpoint; poznejši izrecno odobren korak je opisan spodaj.

Zasebni dokazi so `physical-task-test.json`,
`diagnostics/iphone-task-push-result.json` in pripadajoči posnetki v namenski
mapi fizičnega preizkusa. Izid po pravilih ohranjajo
`diagnostics/iphone-reminder-after-policy-r1-top.png`,
`diagnostics/iphone-reminder-after-policy-r1-bottom.png` in
`iphone-sync-after-policy.png`. Bralni izid po pravilih je z označenim
izvorom prepisan tudi v `diagnostics/iphone-reminder-after-policy-result.json`,
celotni absolutni scenarij pa vodi `physical-absolute-test.json`; prvotni
dokazi ostanejo ohranjeni. Končni in-app izid ohranjata
`iphone-absolute-inapp-inbox.png` in `iphone-absolute-inapp-open.png`.
Bralni pregled vrste ni spremenil podatkov ali konfiguracije. Produktna koda
in strežniška namestitev nista bili spremenjeni.

## Poznejša dovoljena APNs nastavitev in nov termin istega opomnika

Uporabnik je nato izrecno odobril ureditev APNs in čas naslednjega fizičnega
preizkusa. Ustvarjen je **en Sandbox, Topic Specific ključ**, omejen samo na
`si.triparna.jivie`; Apple seznam potrjuje en topic in Sandbox okolje.
Firebase **Development** slot je potrdil naloženi pravi ključ in ekipo.
Produkcijski slot ni bil uporabljen in ostaja nenastavljen za produkcijsko
Apple oziroma TestFlight dostavo. To je konfiguracijski korak, ne dokaz
fizične dostave.

Ključ je bil prenesen samo enkrat in prestavljen v zasebno mapo
`/Users/anzenovsak/JivieProductionSafety/20261105-apns/`: mapa ima dovoljenja
0700, ključna datoteka 0600. Vsebina, ime datoteke ter identifikatorji ključa
in ekipe niso del repozitorija. Zaradi tega koraka ni bilo produktne
spremembe, nove gradnje ali namestitve strežniškega izdelka.

Isti opomnik s prejšnjim strežniškim statusom `delivered` je bil v običajnem UI
**enkrat urejen ob
20:12:51 UTC**, na nov termin **20:20 UTC oziroma 21:20 lokalno**. To je nov
odobren fizični scenarij po spremembi APNs konfiguracije, ne ponovitev
uspešnega starega in-app preizkusa ali ponovno aktiviranje starega push joba.
Novega opomnika ni bilo ustvarjenega.

Prvi omejeni bralni pregled pred terminom je ob **20:13:19 UTC** vrnil
`ok=true`, vendar **nič opomnikov z natančnim novim terminom**. Strežniška
potrditev spremembe tedaj še ni bila ugotovljena: funkcionalno merilo R1 ni
bilo izpolnjeno, sam bralni probe pa ni odpovedal. Sprožen je bil en ročni
sync.

Drugi pregled pred terminom je **ob 20:15:24 UTC potrdil dejansko
razporeditev — R2 PASS**: natanko en isti opomnik ima stanje `pending`,
revizijo **2**, revizijo tarče **1** in novi termin **20:20 UTC**. Pred
terminom še ni due inbox obvestila ali novega push joba, kar je pričakovano.
Iz uspeha po ročnem syncu ne sklepamo o razlogu prejšnje zakasnitve.
Tretji pregled pred terminom ni načrtovan.

iPhone je bil z enim pritiskom Home okoli **20:15 UTC** poslan v ozadje.
Takrat se je čakalo naravni termin 21:20 po lokalnem času; native prejem in
tap še nista bila potrjena. Pred novim push dogodkom še vedno obstaja prejšnja napaka
`metadata` starega prostora. Stari preklicani jobi niso bili spremenjeni.

Ločen bralni pregled po terminu je **R1 ob 20:20:43 UTC** potrdil isti
absolutni opomnik, revizijo 2, revizijo tarče 1, termin 20:20 UTC in stanje
**`delivered`**. Natanko eno due inbox obvestilo za to revizijo je nastalo
**ob 20:20:03 UTC**, z vključenim in-app kanalom, še neprebrano. Natanko en
ujemajoči se iOS push job je **`pending`, s številom poskusov 0**. Registracija
je aktivna in se ujema; čas uspešnega pošiljanja je prazen, job ni pretečen.
To je čakanje na push worker, **ne dokaz napake ponudnika**. Center obvestil
je bil ob 20:20 UTC še prazen; native tap ni bil izveden. V tem trenutku se
je čakalo naravni worker, brez ponovnega pošiljanja ali aktiviranja joba.

**Ob 20:21:42,444 UTC je bil potrjen pravi native prejem — PASS.** V centru
obvestil oziroma ob aplikaciji v ozadju je iOS prikazal obvestilo Jivie
**»Opomnik«** z besedilom **»Odprite Jivie za ogled šifrirane vsebine.«**
Prejšnji prazen center ob 20:20 UTC je bil opažen, ko je push job še čakal
z nič poskusi; ni bil dokaz neuspeha ponudnika.

Poskusi avtomatiziranega odpiranja vrstice v centru obvestil so vrstico samo
premaknili in niso potrjeno odprli tarče. **Uporabnik je nato izrecno
sporočil, da je sam pritisnil »Odpri«.** To je dejanski native Open v tem
scenariju. Aplikacija se je odprla na **Utrip** z indikatorjem sinhronizacije.
Ob **20:23:26 UTC** je bil še vedno prikazan Utrip s spinnerjem; konkretno
opravilo tedaj še ni bilo potrjeno odprto in ta vmesni checkpoint ni bil
označen kot tap-routing PASS.

Končni bralni pregled dostave **ob 20:23:37 UTC** je potrdil isti opomnik,
revizijo 2, v stanju `delivered`; due inbox je nastal ob 20:20:03 UTC in je
bil v tem posnetku še neprebran. Ujemajoči se iOS job je **`sent`, z enim
poskusom in časom pošiljanja 20:21:02 UTC**. Registracija je aktivna in se
ujema, job ni pretečen. To je **en naravni dostavni poskus**, brez ročnega
ponovnega pošiljanja. Dokaz je `diagnostics/iphone-apns-fresh-delivery-result.png`.
Ročni prepis z izrecnim izvorom posnetka ohranja
`diagnostics/iphone-apns-fresh-delivery-result.json`; zaključeni zasebni
scenarij vodi `physical-apns-fresh-test.json`.

Po uporabnikovem sistemskem **»Odpri«** je aplikacija po čakanju na Utripu
**samodejno odprla točno pravo opravilo** `TEST PUSH 05-11 Mac v iPhone`.
Prvi potrjeni prikaz je bil opažen okoli **20:24 UTC**, posnetek je shranjen
ob **20:24:15,411 UTC**. Ujemajo se naslov, opombe, zadolženi račun in avtor.
Med uporabnikovim Open in tem prikazom agent ni izvedel nobenega dodatnega
in-app usmerjanja. **Native prejem in odpiranje konkretne tarče PASS, z
zamikom**; native Open je izvedel uporabnik, samodejno usmerjanje aplikacija.
Dokaz je `iphone-apns-native-open-exact-task.png`.

Šele po tem potrjenem prikazu je agent zaprl opravilo in odprl oblaček za
pregled stanja. Prikazana je še vedno **ista predhodna metadata napaka starega
prostora `testno gospodinjstvo`**. Varni JSON ob 20:24:29 UTC kaže
`stage=metadata` in `reason=crypto_reconciliation_required`, brez nove faze
`unknown`. Dialog vključuje nov samodejni poskus z začetkom ob 20:24:27 UTC
in tedaj začetnimi števci strani 0; to ni njegov končni izid ali dokaz
celotne zelene sinhronizacije. Dokaza sta `iphone-apns-sync-after-native-open.png`
in `iphone-apns-sync-details-after-native-open.png`. Nadaljnjih UI dejanj ni bilo.

Zasebni checkpoint vodi `physical-apns-fresh-test.json`, podatki o ključu
ostajajo samo v zasebni mapi ProductionSafety. Na strežniku so tekli običajni
aplikacijski tokovi in workerji; diagnostični pregledi so bili bralni in
podatkov niso spreminjali. Novi dokazili sta `diagnostics/iphone-apns-fresh-predue-r2.png`
in `iphone-apns-sync-before-push.png`, stanje po terminu pa ohranja
`diagnostics/iphone-apns-fresh-postdue-r1.png`.
Native prejem ohranja `iphone-apns-native-receipt-r2.png`, stanje po
uporabnikovem Open pa `iphone-apns-after-native-open.png`.
**Ta native scenarij je zaključen s potrjenim prejemom in pravo tarčo.
APNs Sandbox nastavitev velja za trenutno razvojno 49; produkcijska Apple
dostava in prvotni vzrok Android napake s tem nista potrjena.**

## Zaključen scenarij in preostale meje

- Potrjeni strežniški in in-app scenariji se ne ponavljajo; prvotno opravilo
  in opomnik ostaneta ista. Zaključenega native scenarija se ne ponavlja.
- Native prejem in prava tarča po uporabnikovem Open sta PASS z zamikom;
  to ni dokaz celotne uspešne uskladitve ali produkcijske Apple/TestFlight
  konfiguracije. Ta ostaja nenastavljena.
- Ugotoviti konkretno podlago že opažene iPhone napake v fazi `metadata`;
  manjkajoči dokaz ostane blokada, brez obhoda varoval ali lažnega ACK.
- Prvotni uporabnikov Android vzrok ostaja nepotrjen. iOS nastavitev in
  ta uspešen native scenarij ga ne pojasnita.
- Ločiti trenutno osebno pravilo prejemnikov od uporabnikove želje
  »ustvarjalec opomnika in zadolžena oseba«. Nova politika še ni izvedena.

Produktna koda, funkcionalni testi, gradnje in izdaje v zaključnem APNs
scenariju niso bili spreminjani ali ponavljani. Časi, hash dokazi in podrobni
dnevniki ostajajo v pripadajočih lokalnih evidencah; nepotrjene meje niso PASS.

## Nadaljevanje: stari prostor na iPhonu — diagnoza brez popravka

Uporabnik je posebej naročil raziskavo stare napake sinhronizacije. Bralna
primerjava je potrdila, da gre za lokalno ohranjen, na strežniku že izbrisan
prostor. Najmočnejša razlaga zavrnjene potrditve izbrisa je nepodprta pot od
lokalno znane glave članstva 2 do glave 3, na katero je vezan dokaz izbrisa.
Ta mehanizem je reproduciran z resničnim produkcijskim varovalom v lokalnem
testu; dejanski skriti exception in Keychain pin iPhona nista zajeta.

### Dejanski podatki naprave in strežnika

- Obstoječa obnovitvena datoteka z datumom 31. oktober, 725 B, je bila prek
  Files/AirDrop prenesena na isti uporabnikov Mac in premaknjena v zasebno
  mapo zunaj Git, `0600`. Original na telefonu je ostal ohranjen. Račun ni
  bil obnovljen, ključi niso bili ustvarjeni ali zamenjani.
- Bralni pregled kopij uporablja produkcijski `RecoveryBundleCodec` in
  `LocalVaultCipher`, že zgrajeno pripeto knjižnico sqlite3mc ter zasebni
  host adapter sqlite3 2.9.4 brez spremembe odvisnosti repozitorija.
  Ujemanje vault ID, AEAD probe, `OpenMode.readOnly`, `query_only`,
  `quick_check=ok` ter nespremenjeni vhodni hashi so potrjeni. Aktualna
  kopija je bila zajeta med delovanjem in ni atomski posnetek; predhodna
  hladna kopija je bila zajeta ob ustavljenem procesu pred nadgradnjo 35→49.
- Točno isti račun/prostor ima v obeh kopijah `scope_reconciliation=missing`,
  ne `crypto_pending`. Lokalno ni označen kot izbrisan ali preklican; ima
  glavi 1/2, preverjen `scopeMetadata` revizije 1 in zaključena prenosa obeh
  domen. Navadne vrste sprememb in osnutki izbrisa tega prostora so prazni.
  Te lastnosti so med kopijama enake. To dokazuje obstoj oznake pred današnjo
  nadgradnjo in pred push preizkusom, ne njenega prvega časa nastanka.
- Ločena ozka poizvedba je našla dve vključeni opazovanji prostora v lastni
  zgodovini, pri generacijah 3/4; obe kažeta glavo 2. Kandidatov ni, kazalec
  lastne zgodovine je 9. Sam SQL pregled ni podpisni replay aplikacije.
- Prva produkcijska poizvedba, samo `START TRANSACTION READ ONLY` in
  `ROLLBACK`, je potrdila izbris istega prostora, odsotnost aktivnega
  članstva in legacy revocation vrstice ter obstoj retained witness.
  Račun iPhona je med dovoljenimi nekdanjimi člani. Dokazi header/leaf/event
  in membership head so prisotni; izbris je izvedel drug račun.
- Druga, ločena bralna poizvedba je potrdila čas izbrisa
  **2026-11-03 04:04:48 UTC**. Dokaz uporablja **glavo 3**, katere neposredni
  predhodnik je **točno lokalna glava 2**. Strežnik ohranja celotno verigo
  3→2→1, osnovni lifecycle dokaz in potrebne reference imenika. Nobeno
  lokalno vključeno opazovanje ne kaže glave 3. To so dejstva in kontrolne
  primerjave SQL; ti poizvedbi nista HTTP ali podpisni preizkus celotnega
  strežniškega odgovora.

### Pot v kodi in lokalni dokaz

`collaboration_sync_actions.dart:1218` zajame `metadata /
crypto_reconciliation_required`, kadar lokalni aktivni prostor manjka v
preverjenem rezultatu, ne da bi bil potrjen njegov izbris/preklic. Zato
ohrani lokalno kopijo z oznako `missing`. To je dejanska veja, ki jo kaže
kopija iPhona.

`CryptoBusinessSession.scopes()` za izpuščene prostore že zahteva retained
deletion status. `SessionCryptoAccess.withVerifiedDeletedScope()` pa pred
preverjanjem dokazov zahteva **točno enako** glavo v varnem lokalnem pinu ali
preverjenih opazovanjih. Veljaven naslednik znane glave sam po sebi ni
sprejet; funkcija ne prenese in preveri manjkajoče verige. Zavrne ga z
`crypto_scope_deletion_history_pending`, ki ga router zadrži, zato zunanji
prikaz ostane splošni `crypto_reconciliation_required`.

Nov test
`test/organizer/data/e2ee/scope_deleted_unseen_head_diagnostic_20261105_test.dart`
je **PASS1**, en sam ciljni tek. Neodvisno preveri resnično podpisano
propozicijo in aktivacijo naslednika 3 glede na glavo 2, nato kliče pravo
produkcijsko varovalo s sintetičnim varnim pinom 2. Rezultat je točen
`crypto_scope_deletion_history_pending`, nič klicev potrditvenega callbacka
in nespremenjen pin. Podpisi, reducer in SQL so resnični; pridobivanje
lastnega imenika/opazovanj uporablja omejen sintetični transport. To ni
native ponovitev ali dokaz dejanskega Keychain pina tega iPhona.
Analiza samo novega testa: **0 težav**; `git diff --check` uspešen. Stari
uspešni testi niso bili ponovljeni.

### Meje neposredne diagnostike naprave

Poskus ozkega branja enega neskrivnega `scope2` pina v že nameščenem
razvojnem app49 prek LLDB ni dal uporabnega rezultata. R1 je obstal pri
prevajanju izraza pred poizvedbo in proces je bil potrjeno odklopljen.
R2 je imel napačno tih zajem, ki je skril tudi rezultate; izid morebitnega
branja je neznan. R3 je uporabil zastarel PID, čeprav je predhodni seznam
že pokazal novega; to je napaka diagnostične izvedbe, poizvedba se ni
izvedla. Četrtega poskusa ni bilo. Sprememba PID ni dokaz vzroka ponovnega
zagona. Noben izraz ni vseboval zapisa ali brisanja Keychain; noben skrivni
ključ ali surova vsebina pina ni bila izpisana. Zato **ne trdimo zajetega
native `crypto_scope_deletion_history_pending` ali uspešnega Keychain branja**.

Po koncu je običajni Jivie odziven, prijavljen in prikazuje `test_gosp`.
To ni nova potrditev celotne zelene sinhronizacije. Diagnostična nadomestna
gradnja ni bila izdelana ali nameščena. Produktna koda, strežniška vsebina,
ključi in izdaje niso spremenjeni; ni resetiranja ali novega izbrisa.

Zasebne evidence v `/Users/anzenovsak/JivieTestAccounts/20261105/`:
`iphone-old-space-observation`, `iphone-existing-file-copy.json`,
`old-space-offline-probe/{current-private-report,cold-private-report,
chronology-comparison,current-observation-private-report}.json`,
`diagnostics/iphone-old-scope-{metadata,retained-ancestry}-r1.{php,png}`,
njihova prepisana rezultata z navedenim izvorom in zasebni dnevniki LLDB.
Dokazi in identifikatorji niso v Git. Naslednja produktna smer je strogo
preverjanje podpisane nasledstvene verige za retained izbris, brez
samodejnega zaupanja izpuščenemu prostoru, preskoka varoval ali ponovitve
izbrisa. Ta popravek še ni izveden. Prvotni Android tap vzrok ostaja ločen
in nepotrjen.

## Poznejši lokalni popravek: retained izbris z nevidenim naslednikom

Uporabnik je po zgornji diagnostiki izrecno dovolil lokalni popravek
odjemalca in njegovo fizično preverjanje. Prejšnji sklep »popravek še ni
izveden« opisuje checkpoint pred tem dovoljenjem. **Popravek je zdaj izveden
in lokalno preverjen; rezultat novega fizičnega iPhone preizkusa je še
PENDING.** Ni nove strežniške namestitve, commita, izdaje ali potrditve, da je
s tem odpravljen prvotni Android tap primer.

Produktna sprememba je omejena na
`lib/organizer/data/e2ee/session_crypto_access.dart`.
`withVerifiedDeletedScope()` lahko preveri ohranjeno glavo 3 kot podpisanega
naslednika neodvisno znane glave 2. Pred sprejemom preveri celotno verigo do
genesis, popolno vezavo prostora in vseh predhodnikov ter obstoječe
podpise predlogov, aktivacij, lifecycle in imenikov. Veriga mora vsebovati
**tako varen lokalni scope floor kot vsa preverjena vključena opazovanja iz
lastne podpisane zgodovine**, kadar so prisotna. Sama SQL vrstica ali
nepotrjen kandidat ne ustvarita sidrišča.

To je zgodovinski dokaz za potrditev izbrisa. Ne odpre običajne trenutne
avtoritete prostora, ne promovira scope floora in ne pridobiva ali zapisuje
novih ključev. Ohranjene zahteve, računski ključi in seje se ne ponastavljajo;
nov ukaz izbrisa se ne pošlje. Callback še vedno preveri header, leaf,
membership head in vključitev dogodka izbrisa v podpisani imenik njegovega
avtorja. Napačen pozni dogodek ne povzroči potrditve izbrisa.

### Izolacija in omejitve

- Kandidat se kanonično globoko kopira pred prvim `await`; nadaljnje
  preverjanje uporablja isto kopijo in zajeti hash.
- Preverjanje ima zasebni kontekst, vezan na isti `SessionCryptoAccess` in
  prostor. Zgodovinske glave, imeniki, descriptorji in opazovanja ostanejo v
  njegovih začasnih mapah, ki se ob uspehu ali napaki počistijo. Običajne
  mape in trajne SQL vrstice glav/imenikov se s to potjo ne promovirajo.
- V kontekstu sta dovoljeni samo ustrezni retained `deletionHead` in
  `deletionDirectory` branji. Običajni `currentHead`, zapisovalna avtoriteta
  in pridobitev ključev ostanejo zavrnjeni. Drug primerek dostopa in
  asinhrono delo po izteku konteksta ne moreta uporabiti njegovega dovoljenja.
- Veriga je omejena na **64 glav in skupaj 2 MiB**. Retained kontekst ima
  največ **256 zahtev in skupaj 8 MiB odgovorov**. Presežene omejitve ali
  manjkajoči dokazi ostanejo pending; ni skrajšanega sprejema nepopolne verige.
- Surova varna pina prostora in lastnega imenika, račun, naprava in veljavnost
  seje se ponovno preverjajo med branjem ter po celotnem callbacku. Zadnja
  primerjava poteka pod obstoječim skupnim zaklepom sidrišč, brez omrežja v
  zaklepu. Sočasna sprememba pina ni prepisana.
- Podpisan javni origin lahko obnovi descriptor v tem začasnem kontekstu.
  Prej preverjen legacy descriptor se sme uporabiti le ob ujemajočem
  lifecycle baseline; manjkajoči legacy descriptor ostane pending. Ta pot
  ne odpira običajnega migracijskega transporta ali novega key bootstrapa.

### Novi lokalni dokazi

**28 različnih novih testov PASS, vsak v svojem prvem ciljnem teku:**

| Novi sklop | Rezultat | Kaj dejansko preveri |
| --- | --- | --- |
| Podpisani naslednik in dodatne kontrole | 1 + 22 PASS | Pravi predlogi/aktivacije, varna sidrišča in vključena opazovanja; ponaredki, fork, rollback, drug prostor/strežnik, manjkajoča zgodovina, omejitve in tekmovanja pinov/seje. |
| Celotni retained status skozi `CryptoBusinessSession.scopes()` | 2 PASS | Veljaven dokaz vrne deleted/revoked; napačen pozni dogodek ostane nepotrjen. Zaščitene SQL vrstice in varni pini ostanejo isti. |
| Življenjska doba zasebnega konteksta | 3 PASS | Drug primerek dostopa, asinhroni pobeg po zaključku in običajni `currentHead` znotraj konteksta so zavrnjeni brez dodatnih omrežnih klicev, trajnih sprememb ali zapisov v varno shrambo. |

Prvotni diagnostični PASS zavrnitve na stari izvedbi ostaja ločen
zgodovinski izid; ni prištet tem 28. Prvi uspešni pozitivni test je bil pri
naslednjem ukazu izrecno izključen; 22 dodatnih kontrol ga ni ponovilo.
Uspešnih integracijskih ali kontekstnih testov nismo ponavljali.

Testi uporabljajo resnični Sodium, podpisni reducer, codec, produkcijska
varovala in SQLite, pridobivanje odgovorov ter OS varna shramba pa sta
sintetična. To niso novi HTTP, native Keychain, iPhone ali produkcijski
strežniški preizkusi. Neodvisni pregled končnega diffa ni našel blokirajoče
napake ali obhoda avtorizacije in dopušča **lokalno iPhone testno gradnjo**;
to ni dovoljenje za trgovinsko izdajo ali dokaz native uspeha.

Ciljna analiza je imela **0 napak in 0 opozoril**; ostajajo obstoječi
produktni informativni zapisi. Ena nova testna pripomba o zavitih oklepajih
je odpravljena; končna analiza tega testnega vira je brez pripomb. Oblikovanje in `git diff --check`
sta preverjena. Starih uspešnih funkcionalnih zbirk nismo ponavljali.

Evidence: `build/qa/deleted-scope-descendant-20261105/test-results.json` je
izrecno označen kot povzetek orodnih prepisov, ne kot samostojen surovi
dnevnik. Ločeni dejanski dnevnik 22 dodatnih kontrol je
`build/qa/scope-deleted-descendant-20261105/remaining-r1.log`, njegov točni
ukaz/izid pa `remaining-r1.json`. Integracijski in trije kontekstni izidi so
potrjeni v koordinacijskih orodnih izhodih. Zasebni produkcijski podatki,
identifikatorji in podpisani dokazi niso preneseni v ta dokument.


### Fizični iPhone: ista seja po lokalnem popravku

Izolirana gradnja je zamrznila **665 produktnih vhodov**; edina razlika
proti prvotni nameščeni iOS49 je `session_crypto_access.dart`. Različica
ostaja **1.11.17 (49)**. Offline dependencies/config-only in en Xcode archive
so uspeli; archive je trajal **57,59 s**. Gradnja ima običajno produkcijsko
kodo brez QA runtime prekrivanja ter isti razvojni APNs, bundle, podpisni
certifikat, provisioning profile, entitlements, Firebase in dependency locke.

Prvi verifier je obstal na napačni sintaksi izbirnega argumenta
`codesign --extract-certificates`; ločen diagnostični klic je potrdil isti
helper problem. Po popravku v `--extract-certificates=...` je verifier v
drugem polnem teku uspel na **istem artefaktu**, brez ponovne gradnje ali
produktnih sprememb. Strogo preverjanje podpisa in vseh vhodov je uspešno.
Artefakt ima 148 datotek, 41.849.215 bajtov; AOT SHA256
`0edf4eeab93bec7712c501a1d14ff75002e68c62bf7d37cc87d87628def8d786`.

Pred namestitvijo je bil PID navadne Jivie pridobljen iz svežega seznama
in vezan na točno pot njenega bundle; nato je bila aplikacija ustavljena
in odsotnost procesa potrjena. Zasebna hladna kopija Documents in Preferences
vsebuje 6 datotek. Izvedena je bila **ena in-place namestitev**; vseh 6
datotek je bilo pred prvim zagonom byte-exact enakih kopiji. Keychain ni
izvožen ali spremenjen; ni bilo odjave, reinstalla, obnove, resetiranja ali
novih ključev. Ločena aplikacija Jivie Test ostane nedotaknjena.

Navadna Jivie se je odprla v isti seji in `test_gosp`. Že samodejna
sinhronizacija po zagonu je uspela. Device Hub posnetek orodnega izhoda
prikazuje **Usklajeno**, zadnjo uspešno uskladitev **5. 11. 2026 ob 22:32
lokalno**, čakajoče/sporne/zadržane spremembe **0/0/0** in nobene prejšnje
metadata napake. Ročni »Uskladi zdaj« ni bil pritisnjen. Obstoječi banner za
pregled zaščite in obvestilo o povabilu sta ločena od uspešnega sync statusa.
Ta posnetek je v orodnem prepisu; ne trdimo ločene shranjene slikovne datoteke.

Po uspehu je bila pridobljena nova zasebna živa kopija Documents/Preferences
za bralno preverjanje. Ta kopija ni razglašena za atomski posnetek. Fizični
UI uspeh je potrjen; zaključena offline primerjava je opisana spodaj.
Ni novega push testa, strežniškega deploya, trgovinske izdaje ali commita.
Gradnja in manifesti so v `build/qa/ios-retained-deletion-fix-20261105`;
zasebne kopije ostajajo zunaj Git repozitorija.


### Zaključena bralna primerjava po popravku

En nov offline primerjalni tek **PASS1** je na kopijah s pravim šifriranim
SQLite in obstoječim FILE potrdil:

- isti račun in isti vault, oba AEAD preveritvena zapisa veljavna; bajti
  `state.json`, obnovitvenega FILE in vseh izvornih vhodov so ohranjeni;
- stari prostor je prešel iz `deleted=false/revoked=false` v
  **`deleted=true/revoked=true`**, z običajno terminalno lokalno blokado;
- njegov `scope_reconciliation` je prešel iz **`missing` v odsoten**;
- SQL glavi ostajata **1 in 2**, z enakimi vrsticami in authorization bajti;
  nova zgodovinska glava3 ni bila promovirana v trajno običajno avtoriteto;
- metapodatki starih scope ključev in bajti starih records so nespremenjeni;
- novi `test_gosp` ostaja isti aktiven prostor brez revocation/deletion/blokade,
  z istim enim zapisom in nespremenjenimi bajti njegove vsebine.

Primerjalnik odpira le zasebne dodatne kopije v `OpenMode.readOnly` in
`PRAGMA query_only=ON`; preveri `quick_check`, avtentičnost vault probe in
končne hash vrednosti vhodov. Izpis vsebuje le omejene zastavice/števila,
izvorni zasebni identifikatorji se ne objavijo. Zamrznjeni helper in rezultat
sta zunaj repozitorija v `iphone-retained-fix-observation`. To je nov
preizkus dejanskega stanja po popravku, ne ponovitev starih uspešnih probeov.

**Dejanski iPhone izid starega prostora je zdaj PASS.** UI in lokalni
terminalni zapis se ujemata. Native Keychain pin ni bil prebran ali
primerjan; bralni kopiji nista razglašeni za atomski zajem. Prvotna
Android napaka po tapu na push ostaja ločeno vprašanje, prav tako še
neimplementirani opomnik za ustvarjalca in zadolženega. Ni Play/App Store
izdaje, strežniške namestitve ali commita/pusha.

### 6. november – ročni »Uskladi zdaj« na iPhonu

Na običajni Jivie z odprtim produkcijskim testnim prostorom `test_gosp`
je Device Hub pred pritiskom pokazal »Usklajeno«, uspešno preverjanje ob
22:12 ter nič čakajočih, spornih ali zadržanih sprememb. En pritisk je bil
poslan ob 22:13:07,022 po lokalnem času. Prvi posnetek, zajet do 579 ms
po začetku klika, je že pokazal uspešno preverjanje ob 22:13, »Usklajeno«
in vse tri števce na nič. Tudi posnetka pri 997 in 1.404 ms sta pokazala
isto stanje. Zadnja uskladitev podatkov je bila še vedno zabeležena prejšnji
večer.

Gre za opazovanje uporabniškega vmesnika na odprti aplikaciji. Čas
vključuje Device Hub, prikaz v aplikaciji pa je natančen na minuto.
Posamezni HTTP klici in morebitno časovno prekrivanje s samodejnim
preverjanjem niso bili izmerjeni. Večsekundnega čakanja v tem poskusu nismo
videli. Po meritvi je bil iPhone zaklenjen in zaslon je ugasnil.
