# Mobilna testna priprava — 24. oktober 2026

## 25. oktober — dejanski Mac preizkus pravic, r13

Po izrecnem naročilu »Ok, stestiri mac verzije« sta bili isti Mac Sync A/B
posodobljeni na r13 iz zamrznjenih 627 produktnih vhodov. En build in ena
namestitev za vsako, iste identitete, Keychain nastavitve in lokalni CA;
podatki niso bili ponastavljeni. Prejšnja r12 paketa sta ohranjena. Sol6.1/high
je pripravil okolje in neodvisno pregledal QA dodatke; glavni agent je izvedel
GUI. Telefoni, mobilni strežnik 18801 in produkcija niso bili uporabljeni.

Novi ciljni preizkus v obstoječem prostoru **QA Table Access 25**, pravila
avtorstva v1: A ustvari **QA-AUTHORITY-25-1** in ga dodeli B. B ga prejme z
avtomatsko sinhronizacijo, odpre urejevalnik in napiše sintetični neshranjeni
osnutek. A nato odstrani dodelitev in enkrat shrani. Po avtomatskem prejemu
spremembe pri B:

- odprti obrazec in prejšnje besedilo ostaneta;
- dodatno lokalno tipkanje še deluje;
- prikaže se opozorilo o nedostopnem skupnem shranjevanju; gumb Shrani je siv;
- po arhiviranju sintetičnega osnutka v diagnostični dokaz in izrecnem Prekliči
  novo odprtje iste vrstice pokaže predogled brez možnosti »Edit task«.

To je **native GUI PASS** za spremembo dovoljenja prek dodelitve opravila.
Ne gre za odvzem članstva v prostoru ali za novo preverjanje tabelnega osnutka.
Prvotni avtomatizirani viewer fixture STOP3 ostane zgodovinski rezultat; ta
uporabniško naročeni native preizkus ni njegov četrti zagon. Lokalni task
osnutek ni dobil nove trajne hrambe: testno besedilo je agent pred zaprtjem
izrecno shranil v dokaz, ne aplikacija sama.

Stara **QA-TABLE-ACCESS-25-1** je bila samo dvakrat odprta za novo meritev
ponovne uporabe pravic, brez urejanja ali shranjevanja. Vidna sta revizija3 in
A1 **DRUGI-25**; dostop ostane. Starih testov ustvarjanja, povabila, sprejema
in shranjevanja preglednice nismo ponavljali.

Odprta manjša UX ugotovitev: ob izgubi dovoljenja se hkrati izpiše pravilno
opozorilo »Sharing is unavailable…« in splošno obvestilo »…will be compared
when you save«, čeprav je Shrani onemogočen. Besedilo drugega obvestila je
potrebno prilagoditi lokalnemu načinu; podatkov ali pravic to ni spremenilo.
V tem testnem koraku produktne kode nismo spreminjali.

Meritev: **322 fizičnih HTTP zahtevkov**, vsi200, vrh111 v drsečih60s,
nič429 in nič zajetih native napak; zaključka A/B error=null/unresolved=false.
Prvo označeno okno odpiranja preglednice ima35, drugo19 zahtevkov. V obeh je
**0 authority.snapshot, 0 scope.headGet, 0 directory.status HTTP**; native
hramba potrdi zadetke preverjenih glav in statusov. Sveža branja vsebine,
inventory, lifecycle, directory.read, capabilities in table.lease ostanejo.
Strežniški časi imajo sekundno natančnost, zato pripis zahtevkov na mejnih
sekundah ni podsekundno natančen. Okni sta različne dolžine in vključujeta
navigacijo/ozadje: to ni čist
benchmark posameznega odprtja niti podlaga za odstotek proti prejšnjim669.

Kontrolni strežniški posnetek: istih5prostorov/7članstev/5kriptografskih glav,
enak hash pred/po. Stara preglednica ostane rev3/seq5. Novo opravilo ima
reviziji1 in2 ter dve uspešni batch zahtevi (ustvarjanje in odstranitev
dodelitve); B osnutka ni pošiljal. `store.evict` ni števec odvzetih dostopov:
ponovni sprejem dokaza najprej odstrani star vnos hrambe in ga nadomesti.

Zajem 17:12:00–17:18:08 UTC, obe aplikaciji normalno zaprti ob koncu. Izvoz
je sprva uporabljal prejšnjo macOS mapo; cilj je bil popravljen pred poslovnimi
koraki. To ni napaka aplikativne sinhronizacije. Dokazi so v
`build/qa/mac-authority-reuse-20261025/` (paketi, zajem, native dogodki,
`recipient-draft-after.png`, `recipient-draft-full.txt`, `recipient-viewer.png`,
`table-second.png`). Noben ročni sync, ponovna prijava, povabilo, grant,
rotacija ključev ali sprememba članstva ni bila izvedena. Celotna byte-pariteta
zaščitenih lokalnih baz ostaja neprebrana zaradi TCC; te omejitve nismo obšli.

Zaključek: neodvisni pregled dokazov je potrdil zgornje meje PASS.
`final-native-result.json` vsebuje končne meritve in omejitve. Odstranjenih je
bilo 2.291.202.120 bajtov obnovljivih gradbenih datotek; nameščena paketa,
povratna r12 paketa, izvori, podatki in dokazila so ohranjeni.

## 25. oktober — pravice prek koordinatorja (nadaljnja optimizacija)

Uporabnik je potrdil ponovno uporabo zadnje preverjene avtoritete med
preverjanji `account.changes`. Sprememba pravic ne sme zavreči odprtega osnutka;
strežnik kljub temu preveri dovoljenje ob dejanskem zapisu. Zavrnjen prenos ni
uspešno shranjevanje v skupni prostor. Lokalni osnutek mora ostati ohranjen.

Zasnova: pomnilniška hramba natančnih dokaznih odgovorov znotraj iste prijave,
običajno preverjanje podpisov in lokalnih varnostnih sidrišč pri vsakem porabniku,
razveljavitev ob spremembi dostopa/ključev ter sveža meja pred pošiljanjem.
Podatkovne strani, zaloge zapisov, receipts in potrditve popolnosti niso del te
hrambe. Navadna sprememba vsebine ne zahteva ponovnega pridobivanja vseh pravic.
Pozni odgovor preverjanja ne sme ponovno omogočiti že razveljavljenega stanja.

Strežniški izvorni pregled: `NativeAccountChanges` že vključuje glavo in epoho,
vloge, finančna dovoljenja, stanje identitet ter življenjski cikel prostora in
starša. Aktivacija pravil avtorstva poveča `metadata_revision`, ki je v oznaki
sprememb dostopa. Za to optimizacijo ni ugotovljena potreba po novi shemi ali
spremembi strežniškega protokola.

Merilo je zmanjšanje dejanskih zahtevkov za primerljiva branja. Prejšnjih
669 zahtevkov brez napake 429 ni dokaz zadostne učinkovitosti. Dokazi tega
koraka so v `build/qa/authority-change-driven-20261025/`.

### Lokalna meritev in meje dokaza

Nov omejen HTTP preizkus je uspel v prvem poskusu: isti hladni kopiji testne
baze, dva prostora, trije zaporedni porabniki z ločenimi `SessionCryptoAccess`.
Obe strani preverita šest celotnih podpisanih glav in opisnikov, z enakimi
glavami in vlogami. Klici transporta: **21 → 6**; po porabnikih **7/7/7 →
6/0/0**. Klici capabilities **6 → 1**, authority.snapshot **6 → 2**,
directory.read **9 → 3**. To je 71 % manj klicev v tem konkretnem preizkusu,
ne dokaz enakega zmanjšanja celotne sinhronizacije ali hitrosti telefona.
Optimizirana veja izrecno omogoči krmilnik ponovne uporabe; njegova povezava
z `account.changes` je preverjena ločeno s testi koordinatorja.

Števec meri klice transporta; fizičnih ponovitev HTTP ni neodvisno preštel
strežniški dostopni dnevnik. Transportna varovalka je dovolila samo branja,
brez podpisanih ukazov. Ohranjen strežnik `jivie-fullsync-lab-20261021` na
127.0.0.1:59777 je po meritvi spet ustavljen. Izvirna testna baza in datoteka
ključev imata nespremenjena hasha; zapisovalo se je samo v dve majhni kopiji.
Stanje drugih vsebnikov se ni spremenilo; primerjava njihovih slik ostaja
nepotrjena zaradi različnih zapisov oznak in digestov, po treh diagnostičnih
primerjavah je bila ustavljena. Drugih vsebnikov nismo upravljali.

Koordinator: **15 novih uspešnih kontrol**. Jedro: **10 novih lokalnih kontrol
in 1 novi HTTP preizkus**. Pokriti so selektivna razveljavitev, pozni odgovori,
identiteta, napake, nespremenjene čakajoče zahteve, velikostne omejitve,
nespremenljivi dokazi in prisilno sveže meje. Prvi šibkejši test sočasnosti
ni štet kot dokaz zavrnitve starega odgovora; dodani močnejši kontroli uporabljata
resnična lokalna sidrišča oziroma podpisan imenik. Zgodovinskih uspešnih testov
in tabelnega scenarija ustvarjanje/sprejem/urejanje nismo ponavljali.

Neodvisni izvorni pregled je potrdil varovala. Zaključni popravek prikaza
sprejetih povabil bere trenutne prikazne metapodatke neposredno, mimo hrambe
pravic; dodatna ponovna primerjava lokalnega identitetnega sidrišča je bila
preverjena izvorno. Zaradi teh ozkih sprememb uspešne meritve nismo ponavljali.
Telefoni, mobilni strežnik 18801 in produkcija niso del tega koraka; novih
namestitev na Mac ali telefon v tem koraku ni.

Zaključna kontrola odkrije in odpravi še možnost, da že naložen petsekundni
odgovor po spremembi pravic dobi novo oznako veljavnosti. Kratka operacija,
transportni paket in finančno bralno dovoljenje zdaj nosijo isto generacijo
krmilnika. En dodaten preizkus je uspel prvič; starega HTTP preizkusa brez
vmesnih sprememb pravic zaradi te omejitve nismo ponavljali.

### Odprti osnutki ob spremembi pravic

Preglednica ima ločeno mejo identitete in pravic. Že odprt urejevalnik ob
odvzemu pravic ostane uporaben lokalno, vključno po vrnitvi iz ozadja. Osnutek
se shrani v prvotno lokalno shrambo; gumb za zaključek najprej počaka na ta
zapis. Skupno shranjevanje, preimenovanje, brisanje in priloge niso dovoljeni.
Menjava računa ali neveljavna seja skrije stare podatke. **6 novih UI kontrol
uspešnih**; dodatni test ozadja uspe v tretjem poskusu po dveh napakah priprave
testa (await nad void in nepravilno zaporedje Flutter lifecycle stanj).

Pri obstoječem opravilu, ki ga je uporabnik ob odprtju smel urejati, odvzem
pravic ohrani vnos v odprtem obrazcu. Shranjevanje, brisanje, časovnik in
omrežna priprava financ so blokirani. Obvestilo jasno pove, da je besedilo v
odprtem obrazcu: to ni nova trajna hramba opravilnih osnutkov. Začetni pogled
uporabnika brez pravice urejanja ostane samo za branje. Meja računa vključuje
tudi isto prijavno obdobje; preveri se pred pošiljanjem in po čakanju na
pravila sodelovanja. **7 ciljnih UI kontrol uspešnih**, od tega ena nadomesti
prejšnje, zdaj opuščeno pričakovanje samodejnega zapiranja ob odvzemu pravic.

**Nepotrjeno / STOP3:** UI preizkus začetnega pregledovalca opravila ni uspel
pripraviti predogleda, ker test ni predhodno naložil organizerProvider. Po treh
poskusih smo ga ustavili. Priprava testa je popravljena izvorno, brez četrtega
teka; izvorni pregled potrdi začetno preverjanje pravic, izvedbe UI ne štejemo
kot uspešne. To je omejitev testa, ne dokazana nova napaka aplikacije.

Skupaj: **39 uspešnih novih oziroma vsebinsko spremenjenih ciljnih kontrol**
(15 koordinator + 11 jedro/HTTP + 6 preglednica + 7 opravilo); ena UI kontrola
ostaja nepotrjena. To ni ponoven celoten preizkus aplikacije ali vseh mobilnih
modulov. Podatki, ključi, podpisi, receipts in obstoječa povabila ostanejo.

Uporabnik je dovolil posodobitev obeh ločenih Jivie Test in lokalnega mobilnega
strežnika. Android in iOS pripravita ločena Sol6.1/high agenta, root pregleda
paketa in namestitev. Uporabnik izvaja vse nadaljnje zaslonske teste.
Produkcijska Jivie iz Google Play in TestFlight ostaneta ločeni.

## Zamrznjeni izvor in izolacija

Oba paketa uporabljata `149ed06` z izrecnimi QA razlikami: identiteta in ime
Jivie Test, ista varna shramba, izključno lokalni HTTPS cilj in namenski javni
CA ter omejena diagnostika. Ponovno sta uporabljena obstoječa izvorna imenika;
ni nove polne kopije projekta. Stari diagnostični dokazi ostajajo ohranjeni.

- Android: `si.triparna.jivie.e2eetest.android20261018`.
- iPhone: `si.triparna.jivie.e2eetest.ios20261018`.
- Mobilni strežnik: `https://192.168.132.29:18801/`, ista identiteta gostovanja.
- Certifikat velja do 20. novembra 2026; vgrajeni obnovljeni javni CA ima
  SHA-256 `b9af2a77f19f4b541fd035858d4800408239b8d32d696f6075add608afe540f5`.
- Trgovinska aplikacija uporablja ločeni `si.triparna.jivie` in ni cilj
  nobenega ukaza za namestitev, ustavitev ali spreminjanje podatkov.

## Android

Ena gradnja in ena namestitev čez obstoječo Jivie Test, brez odstranitve ali
brisanja. APK SHA-256 `bbdcdbbb178b1c4a759f6379647ecdc5f8cd64f39d7e3883ba771f98f0d8746a`
(105.955.449 B). Isti podpis, UID in podatkovni imenik. Vse štiri šifrirane
datoteke trezorja (2.941.318 B) so pred in po namestitvi bajtno enake.
Zasebna kopija je ohranjena; Keystore ni izvožen. Produkcijski metapodatki
in APK so nespremenjeni. Sedem native knjižnic se ujema s prejšnjim QA paketom.
Aplikacija ostane zaprta; agent ni izvedel zagona, sinhronizacije ali UI testa.

Po preverjeni namestitvi je odstranjenih samo 16 regenerabilnih map te gradnje,
1.420.058.624 B zasedenega prostora; paket, izvori in dokazi so preverjeno ohranjeni.

## iPhone

Ena arhivska gradnja in ena dejanska namestitev čez isto Jivie Test. IPA
SHA-256 `070388ae30af29307765cedb7bfcc82432adac4fb39abb4d0b1bd80380891bfd`
(16.602.216 B), AOT `3503bf81…`. Isti podpisni profil, certifikat, Keychain
skupina in storage service; obe kriptografski native knjižnici sta brez
podpisa bajtno enaki prejšnjima. Zamrznjenih 616 izvornih vhodov ostane
nespremenjenih skozi gradnjo. Podpis paketa je preverjen.

Pred namestitvijo se je stara QA aplikacija ponovno zagnala; vzrok ni potrjen.
Varovalo je ustavilo postopek pred namestitvijo. Po normalnem zaprtju točnega
QA procesa je bila narejena nova kopija trenutnih podatkov, brez vračanja
starega stanja. Štiri šifrirane datoteke trezorja (4.157.830 B) so bajtno enake
pred in po dejanski namestitvi. Produkcijski metapodatki so enaki. iOS je
spremenil pot podatkovnega vsebnika; ne trdimo iste poti. Keychain ni bil
bran, ni bilo obvoda TCC, odstranitve ali ponastavitve. Aplikacija ostane zaprta.

Po namestitvi je odstranjenih pet regenerabilnih map te iOS gradnje,
1.189.871.616 B. Izvori, paketi, podpisane datoteke, dSYM in dokazi ostanejo
preverjeno enaki. Skupaj z Androidom je odstranjenih 2.609.930.240 B začasnih
gradbenih datotek.

## Lokalni mobilni strežnik

Isto gostovanje 18801 je posodobljeno: 17 spremenjenih/dodanih PHP datotek,
skupaj 186 datotek vtičnika, shema 20 → 21. Vseh 219 obstoječih podatkovnih
tabel in njihove DDL definicije so enake. Spremeni se le vrstica verzije sheme,
dodani sta dve prazni tabeli za v5 povabila. Zasebna hladna kopija vključuje
podatke, pošto, prejšnji izvor, konfiguracijo, TLS in skrivnosti. WAL kopije
so pred primerjavo konsolidirane na ločeni zasebni delovni kopiji.

Ohranjeni so trije pripravljalni izidi: prvi se ustavi pri preverjanju porta
ustavljenega Docker gatewaya, drugi pri odpiranju zasebne kopije SQLite z
WAL glavo brez stranskih datotek. Oba se zgodita pred spremembo izvorne kode
ali baze strežnika. Tretji izvede nadgradnjo in potrdi vse ciljne kontrole,
vključno z enim javnim HTTPS capabilities 200 istega serverId. Končno
primerjanje drugih vsebnikov zazna sočasno spremembo projekta aidiagramer,
zato ta splošna kontrola ni PASS. Nismo spreminjali ali vračali njegovih
vsebnikov. Bralni zaključni zapis loči uspešno pripravljeno mobilno gostovanje
od tega neuspešnega primerjanja; četrtega poskusa ni bilo.

Vse štiri izvirne mobilne storitve znova tečejo z istimi ID-ji in slikami.
Konfiguracija, TLS in ključi so enaki. Ni bilo avtenticiranega poslovnega RPC,
novega povabila ali ponovnega sprejema. Obstoječi lokalni poštni delavec je
vrnjen v prejšnje stanje po preverjanju odsotnosti čakajoče pošte.

Strežniški zajem samo HTTP metapodatkov je pripravljen, vendar še ni zagnan:
`tools/diagnostics/mobile_http_metadata_capture_20261024.py capture --user-manual-session-active --seconds 120`.
Omejen je na največ 180 sekund in 256 KiB ter obnovi prvotno konfiguracijo.
Ne zajema teles zahtevkov, glav ali poverilnic.

## Diagnostika in prvi ročni korak

Sveža QA diagnostika `jivie_qa_mobile_sync_20261024_v1` je v Application Support,
ne med uporabniškimi dokumenti. Zabeleži največ tri samodejne polne in tri
ročne polne sinhronizacije, največ 18 končnih datotek po 8 KiB. Zapis vsebuje
fazo, prvo ujeto izjemo, končni izid in do osem dovoljenih izvornih vrstic;
ne vsebuje ključev, vsebine, žetonov, računskih identifikatorjev ali surovih
sporočil izjem. Prva ujeta izjema je lahko obdelana; sama ni nujno vzrok
končne napake. Končni zapis uporablja samo rezultat istega cikla. Diagnostika
ne spreminja odločitev sinhronizacije. Nova ozka kontrola loggerja PASS1;
prejšnji uspešni poslovni testi niso bili ponovljeni.

Po končani namestitvi uporabnik najprej odpre samo Jivie Test na iPhonu.
Če se pokaže znano opozorilo obnove, izbere »Nadaljuj v lokalne podatke«.
Odpre isti skupni projekt in oblaček sinhronizacije ter sporoči stanje.
Pred pregledom svežega dnevnika ne ponavljamo povabila, sprejema, odobritve,
registracije ali obnovitvenega čarovnika.

Branje po uporabnikovem dejanju:

```sh
python3 build/qa/jivie-mobile-update-20261024/ios/read_diagnostics.py --after-user-test
python3 build/qa/jivie-mobile-update-20261024/android/read_diagnostics.py
```

Pripravljena diagnostika še ni dokaz uspešne native sinhronizacije. Sistemskih
push obvestil s tema QA identitetama trenutno ni mogoče preveriti: manjka QA
Firebase/APNs nastavitev, strežniški FCM je izključen. Preverjanje obvestil
znotraj aplikacije in foreground odobritve ostaja mogoče. Produkcijskih
push poverilnic nismo prenesli v testna paketa.

Dokazi in postopki so v `build/qa/jivie-mobile-update-20261024/`.


## Prvi uporabnikov zagon obeh telefonov

Uporabnik odpre obe Jivie Test. Android kaže »Zaščita povezanih podatkov«;
sveži trajni zapis potrdi dva samodejna polna cikla (08:07:14–28 UTC in
08:08:29–41 UTC), oba `completed=true`, `code=none`, `leaseClaimed=true`,
`workUnresolved=false`. To je PASS dejanske Androidove samodejne sinhronizacije,
ne potrditev zaključka vseh čarovnikov ali dvosmernega mobilnega prenosa.
Agent ni sprožil nobenega cikla. Dokaz: Androidov
`diagnostic-read-20261024T080904Z.json` v današnji QA mapi. Prvo branje je
odkrilo napako bralnega orodja: `adb exec-out` pri neobstoječi datoteki vrne
izhodišče 0 in besedilo napake; popravljeno na `adb shell -T`, ki ohrani
izhodno stanje. Aplikacija in njeni dnevniki niso bili spremenjeni.

Device Hub pokaže iPhonovo »Obnova celotne namestitve« z opozorilom o
neprepoznanih/ohranjenih starih datotekah ter gumboma »Poskusi znova« in
»Nadaljuj v lokalne podatke«. To je znana cleanup pot; gumb Continue samo
spremeni stanje prikaza, ne uvozi datoteke ali sproži novega šifriranja.
iOS bralnik ni mogel dobiti seznama nove diagnostične mape; ne trdimo
uspeha sinhronizacije ali zanesljivo potrjene odsotnosti datotek. Naslednje:
uporabnik pritisne samo Continue na iPhonu in sporoči naslednji zaslon.
Androida ni treba ponovno sinhronizirati.


### iPhone po Continue: native autosync PASS

Sveži dnevnik iOS `native-read/20261024T081203461838Z.json` potrdi prvi
samodejni polni cikel 08:11:46–56 UTC: `completed=true`, `code=none`,
`leaseClaimed=true`, `workUnresolved=false`. To potrjuje dejansko uspešno
sinhronizacijo na iPhonu po lokalno preverjenih popravkih. Ni novega
ročno sproženega synca s strani agenta.

Sveži Device Hub prikaz pokaže »Zaščita povezanih podatkov«, razlago, da za
razpoložljive prostore ni dodatnih korakov, gumb »Preveri in končaj« ter obe
kartici Mobile E2EE 20261018/MOBILE-PROJECT-1 v committed prikazu. Naslednji
nov uporabnikov korak je en pritisk »Preveri in končaj« na iPhonu. To preveri
in zabeleži dokončanje zaščite računa; dodatne priprave financ/ključev na
karticah ne ponavljamo. Izid tega koraka še ni znan.


### Uporabnikov zaključek zaščite na obeh telefonih

Uporabnik potrdi, da »Preveri in končaj« na iPhonu odpre Utrip in da enako
uspe na Androidu. To je uporabnikova potrditev zaključka čarovnika na obeh
napravah, skupaj s predhodno zajetima uspešnima native sinhronizacijama.
Agent ni ponovil preverjanja, pritiskal gumbov ali sprožil synca.

Naslednji nov test: na iPhonu v obstoječem MOBILE-PROJECT-1 odpreti isto
MOBILE-SHARED-1, k obstoječi opombi dodati novo vrstico `TEST-iPhone-24` in
enkrat shraniti. Originalne opombe ne prepisati. Nato preveriti novi zapis
na Androidu; povabila, odobritve in že uspešnega branja stare opombe ne
ponavljamo. Pisanje in prenos nove spremembe še nista izvedena/potrjena.


## Prvi prenos opombe: podatkovni model PASS, odprti urejevalnik zastarel

Uporabnik shrani opombo na iPhonu, obrazec se zapre. Na Samsungu v odprtem
urejevalniku novega besedila ne vidi. Diagnoza brez novih shranjevanj ali
ročnega synca:

- Isti strežniški task wire `7d3f72c9…`, child `254c3dae…`: B/iPhone podpisana
  zahteva `crypto2.records.batch` HTTP200 ob 08:16:27 UTC. Revizija zapisa
  1 → 2; avtor in naprava sta prvotni B. To samo po sebi ne razkrije vsebine.
- Androidova bralna VM diagnostika (getVM/getClassList/getInstances/getObject,
  brez eval/invoke) potrdi točen wire binding in novo 30-znakovno opombo v
  podatkovnem modelu. Vsebuje staro FROM-A in normalizirano testiphone24.
- Sveži iPhonov prikaz pokaže dejansko vneseno `Test iPhone 24`, ne dobesedne
  predlagane `TEST-iPhone-24`. Zato je prvi ozki literalni pregled vrnil
  false tudi za novi Androidov model; to ni bil dokaz manjkajočega prenosa.
- Odprti Androidov urejevalnik ima še stari 15-znakovni osnutek brez testnega
  besedila. Razlika model/odprti obrazec je neposredno potrjena. Zakaj in
  točno kdaj je obrazec zajel prejšnjo različico, še ni neposredno dokazano.
- Android zadnji polni cikel 08:22:39 UTC brez napake/nerešenega dela,
  pending/blocked/conflict/finance vrste 0. iPhone cloud je pred tem pokazal
  uspeh 10:18 lokalno in 0/0/0. Agent ni sprožil poslovne operacije.

Tri omejene VM diagnostične poskuse ohranimo: 1 manjkal naslov VM v omejenem
logu (pred povezavo), 2 prvi literalni pregled, 3 vezava in normalizirano
besedilo/model proti osnutku. Nobenega četrtega VM branja. Povezovalna vrata
so odstranjena. Dokazi: `android/first-edit-20261024/current-state-attempt3.json`
in `first-edit/server/readonly-task-receipts.json` v današnji QA mapi.

Naslednji korak uporabnika: Samsung zapre obrazec s Prekliči/brez shranjevanja
in ponovno odpre isto opravilo, nato potrdi prikaz `Test iPhone 24`. Ne
ponavljamo iPhonovega vnosa ali ročne sinhronizacije. Odprta UX ugotovitev:
urejevalnik ne pokaže jasno, da je v ozadju prispela novejša različica;
morebitni popravek mora ohraniti uporabnikove neshranjene spremembe.

Ločena ugotovitev odzivnosti: uporabnik ob ponovnem odprtju na iPhonu poroča
vsaj tri sekunde čakanja, preden se opravilo odpre. Zapisano kot opažanje,
ne časovna meritev; vzrok ni diagnosticiran. Brez ponavljanja odpiranj samo
za merjenje v tem koraku.


### Potrjen prikaz na Samsungu in nadaljevanje

Uporabnik na Samsungu zapre urejevalnik brez shranjevanja in ponovno odpre
isto opravilo. Zdaj vidi `Test iPhone 24`: prvi iPhone → Android prenos
spremembe je potrjen tudi v uporabniškem prikazu. Ponovitve vpisa ali ročne
sinhronizacije ni bilo. Potrjena težava je zastarel odprti osnutek ob novejšem
podatkovnem modelu; točen trenutek prihoda glede na odprtje ni izmerjen.

Zapisani izboljšavi za poznejši popravek: neurejan obrazec naj lahko prevzame
novejšo različico; pri neshranjenih spremembah naj opozori na novo različico
in ohrani uporabnikov vnos. Trisekundno odpiranje na iPhonu ostaja ločena,
še nediagnosticirana ugotovitev. Popravkov v tem koraku ne izvajamo.

Naslednji NOV test: Android → iPhone. Na Samsungu v istem opravilu k vsem
obstoječim opombam dodati vrstico `Test Samsung 24` in enkrat shraniti. Na
iPhonu najprej zapreti morebitni stari odprti obrazec s Prekliči, brez Save;
nato po Samsungovem shranjevanju ponovno odpreti isto opravilo in preveriti
obe testni vrstici. Brez ročne sinhronizacije ali novega povabila. Rezultat
te obratne smeri še ni znan; prejšnji iPhone → Android PASS se ne ponavlja.


### Obratni vnos: prehodno opozorilo, nato potrjeno pošiljanje

Uporabnik na Samsungu doda novo vrstico in shrani; obrazec se zapre, nato
poroča o sync napaki. Agent v Android Studiu vklopi samo zrcalni prikaz
priklopljenega S25, brez dotika aplikacije. Sveži prikaz ob 10:27 lokalno že
kaže »Usklajeno«, zadnji uspeh 10:27, zadnji poskus 10:26 in vrste 0/0/0.

En bralni VM posnetek novega obratnega scenarija ob 08:28:23 UTC potrdi
isti task wire binding, zadnji full completion seq19 ob 08:28:16 UTC brez
napake/nerešenega dela in vse vrste 0. Opomba v modelu je zdaj dolga 41
znakov (prej 30), čas spremembe 08:26:31 UTC; stara iPhone oznaka ostane.
Dobesedna predlagana Samsung oznaka se razlikuje od dejanskega vnosa;
sam negativni literalni test ni dokaz manjkajoče spremembe. Nobenega eval,
invoke, poslovnega klica ali drugega VM posnetka tega scenarija.

En omejen strežniški bralni posnetek potrdi lastnikov A zapis istega opravila:
`crypto2.records.batch` HTTP200 ob 08:26:32 UTC, expectedRevision2, trenutna
revizija 3/globalSequence9, ista A naprava. Sedem pregledanih A potrdil od
08:25 je HTTP200, brez zabeleženega konflikta ali finite kode napake.
To potrdi sprejem šifrirane spremembe, ne razkrije vsebine in še ne dokazuje
prikaza na iPhonu. Dokazi so v `android/reverse-edit-20261024/` in
`reverse-edit/server/` današnjega QA imenika.

Vzrok uporabnikovega prehodnega opozorila ostaja NEPOTRJEN. Ob opazovanju je
že izginilo; trenutni VM ne hrani prejšnje izjeme, omejena startup diagnostika
pa je že zapolnila prve tri cikle pred tem vnosom. Ne trdimo izgube povezave,
konflikta ali 429 brez dokaza. Za daljše ročne seje je treba pozneje izboljšati
omejeno hrambo novih napak po začetnih ciklih, brez ponavljanja tega vnosa.
Naslednje: uporabnik na iPhonu sveže odpre isto opravilo (stari obrazec naj
zapre brez Save) in potrdi obe novi vrstici. Brez ročnega synca/novega vnosa.


### Obratni prikaz PASS; mobilni testni tok ustavljen zaradi odzivnosti

Uporabnik potrdi, da po ponovnem odprtju MOBILE-SHARED-1 na iPhonu vidi oba
dodatka. Samsung → iPhone je s tem potrjen tudi v prikazu; oba prenosa sta
PASS in ju ne ponavljamo. Prejšnja prehodna sync napaka ostaja brez
zajetega vzroka, uspešen naknadni prenos je ne razloži.

Uporabnik obenem poroča o počasnem odpiranju opravila tudi na Samsungu in
približno 20 sekundah na iPhonu (prej najmanj 3 sekunde). To so uporabnikove
ocene, ne instrumentirane meritve. Odzivnost obeh naprav je odprta resna
napaka; pred novimi uporabniškimi scenariji ima prednost lokalna diagnoza
poti klik → prikaz obrazca. Telefonov ne upravljamo in odpiranj ne ponavljamo.

Prvi izvorni pregled: SharedCollaborationActions.task v
lib/organizer/presentation/shared/collaboration_actions.dart pred
showOrganizerEditor čaka refreshFinanceAccountChoices za podprojekt s
finančno podporo, tudi kadar opravilo nima stroška. Ta pot čaka finančno
politiko, seznam računov in refreshLocal. To je potrjena blokirajoča
odvisnost v kodi, NE še izmerjen vzrok vseh 20 sekund na napravi. Nadaljnja
diagnoza mora ločiti omrežje/kriptografsko preverjanje, lokalno branje in
čakanje na vrsto; odstranitev finančnih varoval ni dovoljena. Brez runtime
sprememb, builda, namestitve, novih HTTP/VM zajemov ali ponovitve PASS.

Dodatna izvorna ugotovitev: provider refreshFinanceAccountChoices uporablja
_edit (collaboration_provider.dart:605), ki po uspešnem branju pri isti
identiteti pokliče _requestAutomaticSync (vrstica345). Torej tudi odprtje
obrazca lahko zahteva avtomatski sync. Sam wrapper ga ne awaita in ne
serializira action; brez časovnih podatkov tega ne označujemo kot neposredni
vzrok 20 sekund. To je kandidat za odvečno delo ob zgolj ogledu opravila.


## Raziskava prepletanja osvežitev — 24. oktober 2026

Uporabnik je pred nadaljnjimi testi naročil skupni pregled finančnih in vseh
povezanih osvežitev. Trije GPT-6.1 Sol/high podagenti pregledajo UI,
razporejanje/lokalne projekcije in kriptografsko podatkovno pot; root
preveri glavne povezave, zgodovinske meritve in meje testov. Podlaga je
HEAD `a41cf99`; nameščeni QA paketi imajo runtime izvor `149ed06`.
Ta sklop je izvorna raziskava, ne nov preizkus hitrosti ali diagnoza
pretečene napake na napravi. Brez runtime sprememb, telefonskih dejanj,
HTTP, gradnje, namestitve ali ponavljanja uspešnih testov.

### Glavni sklep

Težava ni omejena na eno finančno funkcijo. Pomešani so prikaz lokalnega
stanja, preverjanje/obnova oddaljenih dokazov in zahteva za dostavo novih
sprememb. Bralna dejanja lahko sprožijo široko osvežitev ter nov sync;
objava lokalnega stanja sproži dodatna branja drugih modulov. Obstoječa
varovala omejujejo vzporedne sinhronizacije in retry, zato iz tega ne sledi
dokazana neskončna zanka. Obseg odvečnega dela in delež opaženih 20 sekund
ostajata za meritev. Finančna varnost ne zahteva, da prikaz že prenesene
nefinančne opombe čaka na osvežitev finančnega izbirnika.

### Zemljevid glavne verige

```text
Projekt → opravilo → CollaborationActions.task
  await refreshFinanceAccountChoices
    await finančna politika
    await kriptografsko preverjanje/priprava izbir računov
    await refreshLocal (vsi dostopni prostori, vse lokalne projekcije)
      objava collaboration state + personalChanged
        → dodatna branja organizatorja, prostorov, idej, vrta, plačil
    controller._edit → zahteva automatic sync (ne čaka njegovega konca)
  prikaz urejevalnika

Časovnik 3 s / zagon / resume / zaključek synca / _edit
  → refreshLocal + syncWork
  → če schedule.due: syncNow za račun
    → običajni zapisi, finance, inbox, konfiguracija, povezana plačila
    → refreshLocal → objave/poslušalci
```

To je graf možnih izvedbenih poti, ne časovni posnetek konkretnega dotika.
Na telefonih sta dokazana dvosmerni prenos in uporabnikovo opažanje zamika.

### Potrjene povezave in prioritete

| Prioriteta | Povezava v izvoru | Posledica in meja dokaza |
|---|---|---|
| 1 | `collaboration_actions.dart:399–436`: deljeni podprojekt pred dialogom awaita finance choices, še preden preveri linkedCost. | Tudi naslov/opomba brez stroška čakata na finančno pot. Dejanski čas posamezne stopnje ni zajet. |
| 1 | `collaboration_provider.dart:605–606` uporablja `_edit:345–350` za refreshFinanceAccountChoices. | Uspešna bralna osvežitev zahteva sync kot lokalna sprememba. Sync je asinhron; ni neposredno awaitan pred dialogom. |
| 1 | `collaboration_provider.dart:168–240`: timer vsake 3 s pred schedule.due izvede refreshLocal in syncWork. | Tudi kadar omrežni sync še ni na vrsti, se naloži lokalno stanje. 3 s NI interval vsakega HTTP synca. |
| 1 | `collaboration_repository.dart:397–730`: refreshLocal bere vse nepreklicane prostore ter vedno objavi state in personalChanged. | Tudi nespremenjeno stanje sproži nadaljnje delo; metoda nima skupnega združevanja vseh sočasnih klicateljev. |
| 2 | `shared_finance_workspace.dart:21–25,53–61`, `shared_finance_actions.dart:249`, `collaboration_actions.dart:405`. | Isti refresh sprožijo priklop projektnega finančnega zaslona in izrecno odpiranje obeh urejevalnikov. Family provider se ohrani med običajnimi rebuildi, ob dispose/remount pa se lahko ponovi. Dejanske podvojene HTTP zahteve ob dotiku niso izmerjene. |
| 2 | `collaboration_finance_account_choices.dart:87–97` proti `collaboration_finance_sync.dart:145–152`. | Ročni/UI refresh politike in izbir ni v skupnem withFinanceRead kontekstu, kot je finančni prehod polnega synca; prejšnje optimizacije ne pokrijejo samodejno te poti. |
| 2 | `crypto_business_router.dart:339–348` kliče CryptoFinanceAccountChoices.ensure. | Izbirnik ni samo lokalni SELECT: pot lahko preverja zgodovino, prenaša podatke in dokončuje podpisano pripravo. Ne smemo ga preprosto cacheirati brez vezi na pravice/revizije. |
| 2 | `crypto_sync_repository.dart:182–197`: Operacije crypto sync vrste (pull, staging, dostava in poravnava receipts) se serijsko izvajajo po partition. | Izbirnik lahko čaka za drugim delom istega računa, tudi drugega prostora. Potencialno čakanje, ne izmerjena blokada tega dotika. |
| 2 | `collaboration_sync_actions.dart:702–708`: full sync preverja finance in inbox ne glede na odprti zaslon. | Finančna napaka lahko označi celotni cikel kot neuspešen, čeprav je navadno opravilo že preneseno. To ni dokaz vzroka zadnjega prehodnega opozorila. |

Vse poti zgoraj so relativne glede na `lib/organizer/`: UI v
`presentation/shared` oziroma `presentation/finance`, provider v `state`,
repoji v `data`, crypto datoteke v `data/e2ee`.

### Nadaljnje lokalne osvežitve

- Organizator: SqliteOrganizerStorage posluša personalChanges;
  OrganizerRepository ob vsakem signalu doda reload na svojo zaporedno vrsto
  (`organizer_repository.dart:30–48,65`). Vrsta varuje vrstni red, ne združi
  več enakih zahtev za reload. Čakanje lahko prizadene tudi druga dela iste
  vrste; dolžina dejanske vrste ni zajeta.
- Lokalni prostori: `local_spaces_provider.dart:45–55` ob vsakem signalu
  sproži repo.read; ta prebere lokalne prostore in njihove projekcije.
- Plačila: `linked_payments_provider.dart:37–46` posluša celoten
  collaborationProvider in tok personalChanges. Ista osvežitev tako
  zagotovi dva vira invalidacije. Riverpod lahko del dogodkov združi, zato
  ne trdimo točno dveh SQL branj za vsak signal. Read je lokalni; ni sam po
  sebi nov omrežni sync. Finančni pregled organizacije opazuje tudi
  plačila vidnih podprojektov (`shared_finance_workspace.dart:76–94`).
- Ideje in vrt uporabljajo isti široki personalChanges. Skupne ideje
  poslušajo tudi collaboration changes. Povezava presega finančni modul;
  izvedba je odvisna od tega, kateri providerji/repozitoriji so ustvarjeni.
- Lokalni opomniki in izbirni push imajo lastna varovala/generacije.
  Njihovih listenerjev ne smemo šteti kot vedno izveden HTTP klic. QA push
  ni konfiguriran in njegove dejanske izvedbe v tem scenariju ne trdimo.

### Kaj že omejuje delo

Controllerjev busy prepreči prekrivanje njegovega lastnega refresh teka,
ne vseh repo refreshLocal klicev. syncNow ima _syncing/full-attempt ter
lease/identity varovala. Schedule po uspešnem praznem ciklu nastavi naslednji
rok na 60 s; ob neuspehu 15/30/60 s in spoštuje retryAt. Nov _edit lahko
zahteva prejšnji cikel. Zgolj signal personalChanged sam ne pomeni nove
poslovne spremembe ali novega synca. Zato ni podlage za trditev, da je
potrjena neomejena rekurzija.

Že izvedene optimizacije authority/capabilities in kratkih kriptografskih
bralnih kontekstov ostanejo veljavne znotraj svojih meja. Petsekundne meje,
invalidation ob mutaciji, menjavi računa, napaki ali spremembi dokaza so
varovala; ne predlagamo njihovega splošnega podaljševanja. Prejšnje meritve
HTTP na loopbacku niso merile tap-to-dialog, vseh UI listenerjev ali
telefonske hitrosti.

### Testna vrzel in manjkajoči dokaz

- Zgodovinski hitri tok iz `docs/NAVIGATION_AND_TASK_OPENING.md` še obstaja:
  showVisibleTaskTarget prikaže lokalni predogled, nato v ozadju preveri
  tarčo. Test `all_spaces_ui_test.dart:375–414` preverja prikaz po prvem
  izrisu z zakasnjenim/nedokončanim odgovorom. To ni test odpiranja
  projektnega urejevalnika; njegov Uredi lahko nato uporabi težjo pot.
- `shared_task_save_event_regression_test.dart:55` in
  `organization_finance_ui_test.dart:71` imata refreshFinanceAccountChoices
  nadomeščen s takojšnjim praznim Future. Dokazujeta svoja Save/UI merila,
  ne odzivnosti resnične finančne poti. Starih PASS ne razvrednotimo,
  vendar jih ne smemo šteti kot meritev hitrosti tega odpiranja.
- Privzeti HTTP timeout je 20 s (`collaboration_transport.dart:65`).
  Task-open napako finančne priprave ujame in nato lahko odpre dialog.
  Ujemanje z uporabnikovo oceno je kandidat za meritev, NE dokaz timeouta.
  Prav tako ni novega dokaza 429, napake dešifriranja ali izgube podatkov.
- Današnja QA diagnostika hrani le prve tri avtomatske cikle. Ti so bili
  izčrpani pred zadnjim opozorilom; za prihodnjo lokalno diagnostiko je
  potrebna omejena zgodovina novih napak in trajanj, ne le zagonski vzorci.

### Predlagan vrstni red naslednjega dela

1. Najprej merilni zapis enega odpiranja: čas do dialoga/prvega izrisa,
   policy, choices, čakanje v crypto vrsti, lokalna projekcija in sproženi
   sync. Števci naj ločijo SQL, HTTP, cache hit in listener reload; brez
   vsebin, ključev, naslovov ali tokenov. Lokalno ogrodje, največ tri
   poskuse na novo kontrolo; že uspešnih poslovnih tokov ne ponavljamo.
2. Ločiti bralni refresh od ukaza, ki ustvari odhodno delo. En koordinator
   naj združi zahteve iste identitete/obsega/domene. Branje, ki v crypto
   sloju res pripravi trajno delo, mora to sporočiti izrecno; ne ugibamo,
   da so vse metode z imenom refresh brez stranskih učinkov.
3. Že dovoljeno lokalno opravilo prikazati brez čakanja na finančni
   izbirnik. Finančni del se pripravlja ločeno; stroška ni mogoče veljavno
   urejati brez pravic, vezav in popolne projekcije. Znani preklic ali
   menjava računa morata zapreti/onemogočiti prikaz. Neshranjen osnutek
   mora ostati ohranjen ob novi različici.
4. Omejiti lokalno ponovno nalaganje na dejanske spremembe, obseg in
   domeno; združiti dogodke brez izgube zadnje invalidacije. Ločiti
   spremembo sync statusa od spremembe podatkov, da status ne sproži
   ponovnega branja vseh modulov. Ne odstranjevati vrst, ki varujejo
   atomarnost zapisov, podpisane zahteve ali task–cost pare.
5. Šele nato uskladiti preostale zaslonske/lifecycle osvežitve s skupnim
   koordinatorjem. Spremembo intervalov ali push obravnavati ločeno;
   Firebase ni potreben za odpravo blokiranja prikaza.

Nove ozke kontrole za bodočo izvedbo: lokalni task dialog ob nedokončanem
finance Future; read-refresh brez lažnega localEdit; dva hkratna ista
refresh klica z eno izvedbo; nespremenjena projekcija brez novih reloadov;
sprememba med refreshom se ne izgubi; zakasneli odgovor po menjavi računa
ali preklicu ne obnovi podatkov. To so predlagane kontrole, v tej raziskavi
nobena ni bila zagnana. Končni telefonski odziv ostane za uporabnikov
preizkus po lokalno preverjeni izvedbi.

### Inventar drugih zaslonskih vstopov

Poti v tej tabeli so relativne glede na `lib/organizer/presentation/`.
Inventar loči neposredne UI sprožilce od spodnjih skupnih osvežitev; ni
trditev, da vsak odprti zaslon izvede finance HTTP.

| Vstop | Pot in vrsta dela |
|---|---|
| Projekt → opravilo, planning summary, task list | `projects_page.dart:431,482,550` → actions.task → zgoraj opisani finance await za shared child projekt. |
| Osebe → njihovo opravilo | `shared/sharing_workspace.dart:532–538` → ista task pot. |
| Osebni Danes/koledar | `today_page.dart:72–76`, `calendar_page.dart:141–145` → OrganizerActions.task; lokalni ID-ji iz snapshot za local, sicer await deviceLocalRecordIds (`organizer_actions.dart:139–145`). Brez finance choices HTTP. |
| Vsi → predogled opravila | `all_spaces/all_spaces_rows.dart:584–592` → `inbox/visible_task_target_view.dart:49,138–145`; predogled najprej, preverjanje v ozadju. Drugi lokalni workspace lahko pred tem zahteva aktivacijo/reload. |
| Predogled → Uredi | `inbox/notification_target_view.dart:587–590` → actions.task; hitri predogled ne odpravi čakanja naslednjega urejevalnika. |
| Skupni Utrip/časovnica | `shared/sharing_workspace.dart:626–631,663–678` → showNotificationTarget → await openNotificationTarget pred prikazom (`inbox/notification_target_view.dart:52–56`). Druga pot od hitrega Vsi. |
| Inbox/zunanje obvestilo/finančna povezava do opravila | Ista preverjena notification pot; `finance/finance_source_link.dart:154–159` loči oddaljeno in lokalno tarčo. Svežo identiteto/pravice ob zunanjem vstopu ohraniti. |
| Globalno iskanje | `organizer_shell.dart:1908–1976`: aktivacija vira, lokalni editor oziroma remote fast preview. Aktivacija prostora lahko čaka lokalno branje. |
| Projekt/dogodek/nakupi | `shared/collaboration_actions.dart:314,695,116,154` in lokalni `organizer_actions.dart:78,287,323,340`: neposreden dialog, brez finančnega choices preflight. Shared content policy pri Save je ločeno varovalo. |
| Finančni vnos | `finance/shared_finance_actions.dart:243–255`: shared child čaka choices. Lokalni finance editor `organizer_actions.dart:371` čaka ownership ID-je. |
| Finance / Vsi Finance | Choices mount provider + lokalni PaymentSnapshot za scope in vidne podprojekte; `all_spaces/all_spaces_payments.dart:124–139`, `finance_page.dart:86–88`. |
| Mesečno finančno načrtovanje | `finance/finance_planning_panel.dart:325–349`: post-frame materialization aktivnih pravil za workspace/mesec, omejeno s pomnjenim ključem workspace/mesec v stanju widgeta; remount lahko ponovno preverja. To je pogojno domensko delo, ne vsak render. |
| Pravice financ | `finance/finance_permissions_dialog.dart:56,68–75`: members nato financeGrants. FinanceAccessGuard (`finance/finance_access_guard.dart:15–43`) sam bere cached stanje, ne izvaja HTTP osvežitve. |
| Člani/povabila | `shared/sharing_members.dart:124–139`, `sharing_pending_invitations.dart:94–110`, `received_invitation_notice.dart:39–57`: resume/return s current route, identity, busy in 5s omejitvijo; ne stalni polling. |
| Dokumenti/priloge | `shared/shared_documents.dart:44–48,87–96`: takojšen zaslon z loading, nato openDocuments; build ne odpira konteksta znova. `attachments/attachments_panel.dart:35–53,70–87`: list ob init/spremembi gatewaya z generation guardom. Brez finance choices povezave. |
| Tabele | `tables/spreadsheet_tables_page.dart:32–35,58–62,87`: list ob init in vrnitvi. Detail: load ob init/resume, pristine idle na 10s, lease renew med editing na 25s (`:220–264,301–302`); 1s access check v listu ni HTTP refresh. Ločena potencialna prekrivanja load ob timer/resume, še ne izmerjena. |

### Dodatne meje in tveganja za poznejši popravek

1. Task handler po čakanju osveži `state`, vendar uporabi stara zajeta
   `task` in `data` za osnutek/strošek (`collaboration_actions.dart:21–27,
   408,419–423,531–532`). Čakanje torej samo po sebi niti ne zagotovi
   svežega osnutka. Prav tako pred await ni UI busy/singleflight varovala
   pred več dotiki. Možnost več klicev je potrjena v kodi; dejanskega
   dvojnega odprtja na telefonih nismo opazili ali testirali.
2. refreshLocal ima epoch/closed varovala, nima pa skupne transakcije za
   celoten posnetek ali generacije, ki bi uredila objave dveh sočasnih
   refreshov istega računa. Mešan/zastarel prikaz je tveganje iz izvora,
   ne dokaz kršitve pravic; fetch/save še vedno izvajata lastna varovala.
3. Za organizacijsko finančno politiko lahko coverage preveri root content,
   root finance in zahtevane children (`crypto_business_router.dart:3319–
   3416`). Za project scope ta coverage prej vrne incomplete (`:3305–3307`),
   zato tega celotnega grafa ne pripisujemo začetnemu policy klicu našega
   MOBILE-PROJECT. Parent finance se lahko vključi pri pripravi manifesta.
4. Full sync lahko v finančnem prehodu ponovno preverja linked payments
   policy/negotiate (`collaboration_linked_payments.dart:14,57–68`);
   obstajajo cache meje, zato število klicev funkcij ni enako številu HTTP.
   Snapshot reuse odpove tudi nad namenskimi velikostnimi omejitvami
   (128 records/received, 8 checkpoints, 256 KiB), kar je varno obnašanje,
   ne razlog za odstranitev preverjanj.
5. Izvedena kriptografska vrsta varuje staged zahteve, receipts in claims.
   Zaradi počasnega prikaza je ne smemo razbiti na neodvisne vrste brez
   dokaza, da se ohranijo task–cost atomarnost, exact replay in konflikti.
   UI se lahko od te vrste razveže; to ne pomeni obhoda vrste pri pisanju.

### Ključne datoteke za naslednjo izvedbo

- [Odpiranje skupnega opravila](../lib/organizer/presentation/shared/collaboration_actions.dart)
- [Sprožilci in read/edit wrapper](../lib/organizer/state/collaboration_provider.dart)
- [Urnik synca](../lib/organizer/state/collaboration_sync_schedule.dart)
- [Celotna lokalna projekcija](../lib/organizer/data/collaboration_repository.dart)
- [Finančne izbire in varovala](../lib/organizer/data/collaboration_finance_account_choices.dart)
- [Finančni prehod polnega synca](../lib/organizer/data/collaboration_finance_sync.dart)
- [Kriptografsko usmerjanje](../lib/organizer/data/e2ee/crypto_business_router.dart)
- [Priprava/preverjanje izbir](../lib/organizer/data/e2ee/crypto_finance_account_choices.dart)
- [Serijska crypto vrsta](../lib/organizer/data/e2ee/crypto_sync_repository.dart)
- [Lokalne objave skupnih idej](../lib/organizer/data/collaboration_idea_actions.dart)
- [Plačila in dvojni vir invalidacije](../lib/organizer/state/linked_payments_provider.dart)

Raziskava ne razglasi celotne aplikacije za izmerjeno, ne določi vzroka
prehodne napake in ne dodaja novega poslovnega PASS. Pripravi preverjen
zemljevid za skupen popravek, namesto popravljanja posameznih zamikov
na telefonih enega za drugim.

Neodvisni zaključni pregled UI in crypto sinteze: vsebinsko potrjeno po
zožitvi trditve o serijski vrsti na crypto sync operacije in popravku poti
finance_page ter oznake zaslona Osebe. Root je preveril ključne await,
provider/schedule, lokalne emit in testne mock povezave. Relativne povezave
na ključne datoteke in git diff --check so preverjene; noben runtime test
ni bil izveden.


## Načrt prenove sinhronizacije celotne aplikacije — dogovor 24. oktobra

Status: uporabnik je 24. oktobra izrecno odobril lokalno izvedbo tega načrta.
Izvedba in novi testi so v `SYNC_REDESIGN_IMPLEMENTATION_2026_10_24.md`.
To še ni potrdilo zaključka ali produkcijske pripravljenosti. Telefoni in
produkcija ostajajo nedotaknjeni. Izvorna raziskava in njene omejitve so v
predhodnem razdelku; uporabnikovih 20 sekund še ni časovno izmerjenih.

### 1. Cilj in potrjena pravila

Cilj je odzivna aplikacija, ki dela iz lokalne šifrirane baze, varno ohrani
vnose, spremembe usklajuje v ozadju in uporabnika vključi ob resničnem
vsebinskem konfliktu. E2EE, šifrirana shramba in obstoječa obnova ostanejo.
Ni nove zahteve po ročnem preverjanju kartic ali zaščiti pred vsako možno
zlonamerno potezo gostitelja. Ohranimo dogovorjeno zaupanje pri deljenju;
ločimo lastnika prostora od skrbnika gostovanja.

Potrjene uporabnikove odločitve:

| Dejanje | Dovoljenje |
|---|---|
| Pregled vsebine | Člani z dostopom do konkretne vsebine; finančni dostop ostane ločen. |
| Urejanje zapisa | Lastnik prostora ali avtor zapisa. |
| Urejanje opravila | Poleg njiju uporabnik, ki mu je opravilo dodeljeno. |
| Označi nakupovalno postavko kot kupljeno/nekupljeno | Vsi člani z dostopom do seznama; to ni dovoljenje za spreminjanje naslova, količine ali brisanje. |
| Brisanje celote s tujimi zapisi | Samo lastnik prostora. Velja tudi za seznam/projekt in odvisne zapise. |
| Konflikt | Obe različici ostaneta; neodvisne spremembe se lahko združijo, nasprotujoče razreši upravičeni uporabnik. |

Lastnik prostora s tem ne dobi pravic nad zasebnimi prostori članov.
Dodeljena oseba brez računa ni dokaz pravice uporabnika; uporabimo povezavo
na pravi račun. Avtor ni zadnji urejevalnik ali naprava, ki je prenesla
zapis. Nova pravila ne smejo obstajati samo v skritih UI gumbih, temveč tudi
pri sprejemu sprememb. Trenutni splošni scope.canEdit ni njihova izvedba.

Urejanje opravila ne podeli finančnega dostopa. Če so polja stroška skrita
ali nedostopna, navadna sprememba opravila finančnega dela ne sme prepisati.
Urejanje in brisanje nista samodejno isto dovoljenje; dodatne podrobnosti
so označene v odprtih odločitvah na koncu.

### 2. Uporabniška pogodba: odpri, shrani, uskladi

**Odpri.** Že prenesena dovoljena vsebina se prikaže iz zadnjega veljavnega
lokalnega stanja. Omrežje, finančni izbirnik ali obdelava drugih prostorov
niso predpogoj za odprtje običajnega zapisa. Ob prvem prenosu ali manjkajoči
prilogi pokažemo resnično stanje nalaganja, ne praznega ali lažno popolnega
podatka. Znani preklic dostopa se upošteva takoj.

**Uredi.** Urejevalnik ima osnovno različico in uporabnikov osnutek. Če se
zapis v ozadju spremeni in uporabnik še ni urejal, se obrazec lahko osveži.
Če ima osnutek spremembe, se ohranijo in pojavi se kratko opozorilo o novi
različici. Brez tihega prepisovanja besedila ali odpiranja drugega dialoga
po več zaporednih dotikih.

**Shrani.** Lokalni zapis in namera za sinhronizacijo se shranita atomarno.
Po uspešni lokalni transakciji se obrazec zapre in kaže »Shranjeno na
napravi — čaka na uskladitev«. Napaka lokalnega shranjevanja obrazca ne
zapre in ne sme biti predstavljena kot uspeh. Lokalni UI ne čaka na druge
prostore ali omrežno potrditev.

**Pošlji.** Koordinator preveri aktualne pravice in pošlje trajno čakajoče
delo. Ponovitev iste zahteve nima drugega poslovnega učinka. Izgubljen
odgovor se rešuje z obstoječim dokazilom/receiptom, ne z ustvarjanjem novega
stroška ali drugega naključnega zapisa. Dokler je izid dvoumen, je viden
status čakanja; uporabnik ne dobi navodila »vnesi še enkrat«.

**Prejmi.** Nova vsebina se preveri, dešifrira in skupaj s kazalcem prenosa
trajno shrani, nato se obvestijo samo prizadeti prikazi. UI ne sme prikazati
nepreverjenega rezultata ali izgubiti spremembe ob prekinitvi med prenosom
in lokalnim zapisom.

**Zaključi.** »Usklajeno« pomeni potrjen rezultat konkretnega obsega. En
sporni zapis ali velika priloga ne blokira nepovezanih zapisov/prostorov.
Računski oblaček lahko pokaže, da ostaja delo, podrobnosti pa morajo povedati
kje in zakaj. Ločimo transportno napako, konflikt, odvzem pravic in
nedokončan prenos. Ne prikazujemo generične »seje je potekla« za vse napake.

### 3. En koordinator, ločene odgovornosti

Predlagana izvedbena pogodba:

- Branje lokalnega stanja nima skritega full synca in ne sproži objave
  »podatki so se spremenili«, kadar se ni spremenilo nič.
- Oddaljena osvežitev je izrecna zahteva za račun/obseg/domeno. Isti hkratni
  zahtevi se združita. Nova invalidacija med izvajanjem se ohrani za en
  naslednji potreben prehod, ne izgubi in ne ustvarja neomejene vrste.
- Poslovni ukaz ustvari trajno odhodno delo in zahteva dostavo. Bralni
  refresh ni samodejno localEdit. Če priprava kriptografskega izbirnika
  dejansko ustvari delo, mora to sporočiti izrecno.
- Lokalni prikaz, omrežni prenos, preverjanje dokazov in dostava priponk
  imajo razločljive statuse. Prednost ima odziv uporabniku; velika priloga
  ali širši finančni pregled ne zadržuje nepovezanega urejevalnika.
- Stanje sinhronizacije in stanje vsebine se objavljata ločeno. Sprememba
  oblačka ne povzroči ponovnega branja vrta, idej, vseh prostorov in financ.
- Lokalne projekcije se obnavljajo glede na dejansko spremenjen obseg in
  domeno. Branja se lahko združujejo; vrst za atomarne mutacije ne rušimo.
- Pravice, lifecycle in ključi se usklajujejo v skupnem preverjenem toku.
  Ne preverjamo istega računa neodvisno pri vsakem podprostoru/zaslonu,
  vendar ohranimo potrebno veljavnost posameznega podpisa in operacije.

Ne uvajamo istočasne neomejene obdelave vseh domen. Ohraniti je treba
odvisnosti ustvarjenega projekta, njegovega opravila, stroška in priponke.
Način delitve dela v koordinatorju mora upoštevati podpisane zahteve ter
obstoječo serijsko crypto vrsto; UI lahko preneha čakati nanjo, ne da bi
pisanje obšlo njena varovala.

### 4. Potrjeno: 30-sekundni pregled stanja in prenos samo sprememb

Uporabnik je potrdil en skupen koordinator, ki med aktivno uporabo vsakih
30 sekund preverja SAMO stanje sprememb računa. To nadomesti predlog
minutnega preverjanja in razpravo o push kot glavnem sprožilcu. Firebase
ostane za dejanska uporabniška push obvestila; sinhronizacija ni odvisna
od njihove dostave in ne uporablja Firebase kot potrebnega tihega signala.

Potek:

1. Strežnik ob uspešni spremembi atomarno zabeleži tudi napredek evidence
   sprememb, dostopne upravičenim računom. E2EE vsebina ostane šifrirana.
2. Koordinator z enim lahkim pregledom za račun vpraša, kaj se je spremenilo
   od njegovega zadnjega stanja. Ne kliče ločeno vseh zaslonov in podprostorov.
3. Odgovor »ni sprememb« zaključi pregled: brez prenosa vsebine, priprave
   finančnih izbir, celotnega refreshLocal ali ponovnega nalaganja modulov.
4. Če spremembe obstajajo, prenese samo potrebne spremenjene podatke po
   obsegih/domenah in njihovih odvisnostih. Nespremenjeni moduli ostanejo
   nedotaknjeni. Brisanja in spremembe dostopa so vključene v evidenco.
5. Prejete podatke preveri in trajno shrani, nato posodobi samo prizadete
   prikaze. Novost, prispela med prenosom, ostane za nadaljnji pregled.

Stanje uporablja zaporedje/kazalce, ne skupne zastavice »prebrano«. Vsaka
naprava vodi svoj napredek; uspešen prenos na telefon ne porabi spremembe
za drugo napravo istega uporabnika. Opazovanje oznake spremembe ni dokaz
njenega prevzema: napredek prenosa se potrdi šele po uspešnem preverjanju
in trajnem zapisu. Pri delnem neuspehu ohranimo čakajoče delo in ne
preskočimo neprenesenih sprememb. Obvestilo o dostopu samo po sebi ne
nadomesti preverjanja pravic in podpisov.

Lokalno shranjevanje sproži dostavo v ozadju takoj, ne čaka naslednjih
30 sekund. Pregled se zahteva tudi ob zagonu/vrnitvi v aplikacijo, obnovi
povezave, po potrebi ob odprtju zastarelega zaslona ter ob »Uskladi zdaj«.
Vsi sprožilci uporabljajo isti koordinator; hkratne zahteve se združijo,
počasno preverjanje ne ustvarja novega vzporednega teka ob vsakem ticku.
Odprtje zaslona vedno najprej prikaže veljavne lokalne podatke.

Poln prenos ostane za prvo prijavo, obnovo ali dokazano vrzel v evidenci,
ne za vsako navigacijo ali 30-sekundni pregled. Osvežitev financ ne nalaga
vseh drugih modulov; navadno opravilo ne čaka priprave financ. Ob napaki
je potreben backoff. 30 sekund velja za aktivno uporabo, ne pomeni jamstva
izvajanja v ozadju ali pri zaprti aplikaciji na Androidu/iOS. Posebna
5-minutna politika pravic s tem ni uvedena.

### 5. Konflikti in brisanje

Strežnik lahko primerja revizije, identitete operacij in preverljive
metapodatke. Ker vsebina ostaja E2EE, tri različice (osnovna, lokalna,
sprejeta skupna) vsebinsko primerja odjemalec. Morebitna združitev ustvari
novo namero proti trenutni reviziji; starih podpisanih zahtev ne prepisuje.

- Samo ena stran je spremenila polje: prevzamemo njeno spremembo.
- Obe sta naredili enako spremembo: brez konflikta in podvojitve.
- Neodvisni polji: združitev po pravilih modula, s kratkim preglednim
  obvestilom; brez potrditvenega dialoga za vsako običajno spremembo.
- Nasprotujoči si spremembi: prikaz avtorja in razlik ter »Obdrži skupno«,
  »Uporabi mojo«, »Uredi« ali »Odloči se pozneje«. Lokalni predlog ostane.
- Sočasni izbris in urejanje: ohranimo osnutek, ponudimo potrditev izbrisa
  ali ohranitev/obnovitev, samo če ima uporabnik za to pravice. Izbris
  prostora ali odvzem dostopa se ne obideta z obnovitvijo posameznega zapisa.
- Če se sprejeta različica spremeni med odločanjem, odločitev ponovno
  primerjamo z njo. Nobenega tihega overwrite novejših sprememb.

Konflikt razreši upravičeni uporabnik; ni treba, da odločitev potrjujejo vsi
člani. Sprejeta razrešitev se uskladi kot običajna sprememba. Pri povezanih
poljih ali atomarnih parih je odločitev skupna, pri nepovezanih zapisih pa
ne blokira drugih operacij.

### 6. Pravila posameznih modulov

| Modul | Enota in posebnosti |
|---|---|
| Opravila | Navaden zapis, možnost neodvisnega združevanja polj. Rok/status/dodelitev imajo jasne posledice za opomnike in dovoljenja. Urejanje besedila ne čaka na finance. |
| Projekti/prostori | Spremembe strukture in članstva so ločene od vsebine. Arhiv ali izbris ne sme biti razveljavljen z zakasnelim otroškim zapisom. Brisanje celote s tujimi zapisi samo lastnik. |
| Dogodki | Dogodek ima svojo revizijo; začetek/konec obravnavamo skupaj. Dodelitev na dogodek ne pomeni avtomatično dogovorjene izjeme za opravila. Ponavljajoči dogodki niso potrjena obstoječa funkcija te prenove. |
| Nakupi | Konflikt na postavki, ne celem seznamu. Checkbox lahko spremeni vsak član z dostopom, ne da bi s tem prepisal naslov/količino. Kaskadni izbris seznama s tujimi postavkami samo lastnik. |
| Finance | Znesek, valuta in račun imajo skupne omejitve; brez seštevanja konfliktnih predlogov ali podvojenih stroškov. Do razrešitve skupni saldo uporablja sprejeto različico, predlog ostane ločeno označen. Običajni lokalni čakajoči vnosi morajo biti razločljivi od potrjenih skupnih podatkov. |
| Opravilo in strošek | Navadna sprememba opravila ne spreminja nedostopnega stroška. Skupna sprememba obeh ostane atomarna; konflikt obeh se predstavi kot povezana celota. |
| Ponavljajoče finance | Eno pravilo/obdobje pomeni en logični pojav, tudi če ga ustvarjata dve napravi. Sprememba pravila ne podvoji ali tiho spreminja že potrjenih vnosov. Avtorstvo izhaja iz dogovorjene politike pravila. |
| Plačila/povračila/prenosi | Povezana dejstva ostanejo vezana na izvorni strošek in idempotentna. Že povezano dejstvo se ne spreminja z generičnim merge zneska; popravek mora ohraniti računovodski pomen obeh strani. |
| Idejnik | Obstoječi merge po elementih ohranimo in uskladimo s pravicami. Elementi, slike in njihove povezave ne smejo izginiti zaradi ločenega prenosa assetov. |
| Vrt | Trenutno cel vrt z območji/sezonami/zasaditvami sestavlja en zapis. Najprej varna razrešitev dveh različic; fino združevanje je ločena možnost, ne samoumeven del prve faze. |
| Tabele | Ohranimo trajni osnutek, revizijo in obstoječe zaklepanje. Prikaz ne čaka pridobitve pravice do urejanja. Združevanje po celicah/formulah ni del začetnega splošnega merge; potrebuje svoj dogovor. |
| Dokumenti/priloge | Metapodatki in dejanski bajti imajo ločen napredek. Prekinjen upload se nadaljuje, ne podvoji; datoteka ni označena kot razpoložljiva, dokler ni potrjeno zaključena. Brisanje/nov upload preverita veljavnost cilja. |
| Obvestila/opomniki | Prebrano in osebne nastavitve pripadajo uporabniku. Display refresh ne izbriše čakajočega ukaza. Sprememba roka uskladi opomnike brez ponovnega pošiljanja že dostavljenih opozoril. |
| Osebni lokalni podatki | Delujejo brez računa ali strežnika. Prenos v deljeni prostor je izrecen; ne spremeni identitete odprtega osnutka in ne deli zasebnih podatkov samodejno. |
| Kopije/obnova | Obnovitvena datoteka, identitete, ključi in ločevanje obnovljenega dela ostanejo. Obnova ne pomeni pravice za pošiljanje starega dela v sedaj nedostopen prostor. Kopija ni nadomestilo za sync in obratno. |

### 7. Varna nadgradnja obstoječih podatkov

Pred izvedbo nove permission pogodbe določimo združljivost starega klienta,
starega strežnika in nove sheme. Stare različice ne smejo še naprej veljavno
pisati po širših pravicah, ko prostor že uporablja nova pravila. Preklop se
izvede izrecno z verzionirano pogodbo, ne z ugibanjem UI.

Identitete, vsebina, ključi, povabila, cursorji, tombstoni, osnutki, konflikti,
čakajoče operacije in dokazila se ohranijo. Migracija je ponovljiva, z
varnostno kopijo in preverjanjem vsebine pred/po. Delne nadgradnje ne brišejo
ali ponastavljajo baze. Povratek na prejšnji paket je dovoljen le, če je
združljiv s stanjem; ni samoumeven po spremembi sheme/pogodbe.

Uporabimo OBSTOJEČE avtorstvo. Pregled izvora izdaje 1.10.0 (30), commit
6c8a2fc, in podlage 1.10.1 (31), 5fe4fdf, potrdi created_by/updated_by za
običajne in finančne deljene zapise, created_by za tabele ter owner_account_id
za priloge. Običajno urejanje ne spreminja prvotnega avtorja. Odjemalec
prejema createdByAccountId in updatedByAccountId; odsotnost polja v
posameznem UI modelu ne pomeni odsotnosti avtorstva v shrambi.

Prenova ohrani ta podatek in preveri njegov prenos skozi E2EE migracijo ter
novo projekcijo. Brez novega določanja avtorjev, uporabniškega čarovnika ali
splošne omejitve starih zapisov samo na lastnika prostora. To ni ločen odprt
produktni problem. Če preverjanje dejanskih podatkov odkrije konkreten
manjkajoč podatek, ga zabeležimo in obravnavamo posebej; ne izmišljamo
avtorja in ne uvajamo vnaprejšnjih omejitev za vse stare vnose.
Podrobno pravilo dodelitve se preverja proti že veljavnemu stanju; uporabnik
si ne more pridobiti pravice tako, da se dodeli v isti nepooblaščeni zahtevi.

Produkcija in obstoječe trgovinske aplikacije ostanejo zunaj izvedbe do
posebej dogovorjenega zaključnega preizkusa. Za stare berljive strežniške
kopije ostaja prejšnji dogovor 30 dni po dokazano uspešni obnovi nove
šifrirane kopije; ta načrt ne sproži brisanja ali prestavi začetka roka.

### 8. Vrstni red izvedbe in preverjanja

1. **Zaključek pogodbe.** Potrdimo spodnje odprte odločitve, ločimo pravice
   branja/urejanja/brisanja in združljivost klientov; obstoječe avtorstvo ohranimo.
   Rezultat: ena permission in sync pogodba za vse module.
2. **Ozka lokalna diagnostika.** Časovne faze odprtja, lokalnega zapisa,
   vrste, HTTP, crypto preverjanja in objav; omejena zgodovina napak tudi
   po zagonu. Brez zasebne vsebine. Rezultat: izmerjena podlaga namesto
   sklepanja iz skupnega trajanja.
3. **Ločitev prikaza od usklajevanja.** Lokalni prikaz, trajni save,
   en koordinator, ločitev branja in mutacije, združevanje zahtev in
   selektivna objava projekcij. Obstoječih varoval ne odstranjujemo.
4. **Pravice in skupni mehanizem konfliktov.** Preverljiva avtorstva in
   dodelitve, verzioniran sprejem sprememb, osnovna/lokalna/skupna verzija,
   skupen razumljiv UX. Najprej en celovit tok opravila, ne vsi moduli naenkrat.
5. **Moduli in odvisnosti.** Postopno nakupi/dogodki/projekti, finance in
   task–cost/ponavljanje/plačila, nato ideje/vrt/tabele/priloge in osebna
   obvestila. Ohranimo že dobre specializirane mehanizme, ne uvajamo enega
   prisilnega merge za vse tipe.
6. **Lokalni preizkus celote in nadgradnje.** Izolirane instance in isti
   namenski testni strežnik; izguba povezave/odgovora, restart, sočasna
   sprememba, izbris, odvzem in prehod stare baze. Vsak novi problem ima
   največ tri poskuse, nato zapis in nadaljevanje druge kontrole. Starih
   PASS brez razloga ne ponavljamo; zaradi spremenjene poti potrebne nove
   regresijske kontrole vnaprej jasno poimenujemo.
7. **Ročni mobilni preizkus.** Šele po lokalnih rezultatih isti ločeni
   Jivie Test, uporabnik klika. Preverimo odzivnost in platformne posebnosti;
   brez ponovnega preizkušanja celotne poslovne zgodovine ali novih računov.
8. **Ločena odobritev izdaje.** Poročilo uspešno/neuspešno/nepreverjeno,
   migracijska kopija in združljivost paketov/strežnika. Ta načrt sam ne
   pomeni odobritve produkcijske namestitve.

### 9. Merila dokončanosti

Obvezna vedenjska merila:

- Odprtje prenesenega običajnega zapisa ni odvisno od uspeha omrežja ali
  finančne priprave; napaka drugega prostora ne prepreči dela.
- Lokalni save preživi restart/izpad; ponovna dostava ne podvoji zapisa.
- Sprememba se prenese v drugo instanco, osnutek se ne prepiše neopazno.
- Pravice owner/author/task-assignee ter shopping-checkbox so uveljavljene
  pri sprejemu, tudi ob zakasnelem odgovoru in menjavi računa.
- Konflikt ohrani oba predloga, neodvisno delo se nadaljuje; izbris/preklic
  se ne obideta z merge ali ponovnim pošiljanjem.
- Nespremenjena vsebina ne sproža nalaganja vseh modulov; isti hkratni
  refresh se združi, sprememba med izvajanjem pa se ne izgubi.
- Aktivni koordinator na 30 sekund izvede samo pregled stanja sprememb;
  odgovor brez sprememb ne sproži vsebinskega prenosa ali refreshLocal.
  Sprememba enega modula ne prenese drugih nespremenjenih modulov. Napravi
  imata neodvisna kazalca; izgubljen push ne prepreči naslednjega pregleda.
- UI pravilno loči lokalno shranjeno, v prenosu, usklajeno, konflikt in
  blokirano. Skupni finančni seštevek ne vključuje dveh konfliktnih verzij.
- Prehod ohrani obstoječe podatke, ključe in čakajoče delo; stari klienti
  ne obidejo nove pogodbe.

Predlagana merljiva cilja za topli lokalni prikaz običajnega opravila in
običajni mali lokalni save: prikaz do približno 300 ms, potrditev save do
1 s na dogovorjenih referenčnih napravah/naboru. To nista trenutna rezultata
ali jamstvo za prvo odklepanje baze/velik dokument; proračuna in merilni
nabor še potrdimo. Lokalna simulacija ni nadomestilo za končno meritev na
S25/iPhone 11. Izboljšanja ne dokazujemo samo z manj HTTP zahtevki.

### 10. Odprte podrobnosti pred kodo

Te postavke so predlogi za odločitev, ne tiho potrjena pravila:

- Ali dodeljeni uporabnik sme tudi izbrisati/predodeliti opravilo oziroma
  spreminjati, kdo dobi pravico urejanja; dogovorjeno je urejanje opravila.
- Kdo ureja/briše prilogo: njen avtor, upravičeni urejevalnik cilja ali oba.
  Brisanje celote s tujimi zapisi ostaja rezervirano lastniku.
- Tehnična preslikava starih vlog mora ohraniti potrjeno izjemo: nakup lahko
  označi vsak član z dostopom do seznama. S tem ne spreminjamo drugih pravic
  viewer ali pravil ustvarjanja novih zapisov; ne uvajamo dodatne izjeme
  od uporabnikove odločitve.
- Končna merilna proračuna ter podrobnosti prikaza lokalnega predloga v
  financah, da lokalni in sprejeti skupni saldo nista zavajajoča.

To je enoten načrt za celotno aplikacijo; ne naročilo za hkratno prepisovanje
vseh modulov. Dokler traja dogovor, brez kode, migracij, gradenj ali testov.


## 25. oktober — obe ohranjeni Jivie Test posodobljeni; prvi uporabnikov zagon še sledi

Uporabnik naroči ločena GPT-6.1 Sol/high podagenta za Android in iOS; glavni
agent pregleda paketa, namestitvena varovala in diagnostiko, tretji podagent
pripravi isti lokalni mobilni strežnik 18801. Podlaga je commit `1694c42`.

- Android: ena gradnja in ena namestitev čez isto
  `si.triparna.jivie.e2eetest.android20261018`; isti podpis, UID in shramba.
  Štiri datoteke trezorja (3.338.630 B) in celoten pregledani profil brez
  predpomnilnika (20 datotek, 116.482.376 B) so po namestitvi byte-identični.
  Originalni Google Play APK in metapodatki ostanejo isti.
- iOS: dva arhiva, ena namestitev iste `.ios20261018`. Prvi arhiv ni bil
  nameščen; pregled je pred končno gradnjo zahteval zajem izvornih napak.
  Štiri datoteke trezorja (4.698.502 B) so byte-identične; isti podpisni
  profil, certifikat, Keychain service/group. Pot vsebnika se je ob namestitvi
  spremenila, kar ne pomeni nove identitete ali izbrisa podatkov.
- Strežnik: shema 21→23, 34 spremenjenih/dodanih datotek. Vseh 221 starih
  podatkovnih tabel ohrani stare vrednosti; novi števci so 0, tri nove tabele
  prazne. Isti server ID, TLS, ključi, konfiguracija in štirje vsebniki.
  Varnostna kopija ohranjena. En javni capabilities HTTP 200, nič poslovnih RPC.
- Diagnostika je samo v QA kopijah: koordinator, account.changes/probe razlogi,
  zaključki, 29 mest zajema izvorne napake ter markerji odpiranja opravila.
  Nova mapa je v predpomnilniku, največ 3×1 MiB in 6000 dogodkov na proces,
  brez vsebine zapisov/ključev/tokenov. Bralnika sta pripravljena; dejanski
  zapis novega dnevnika bo potrjen šele po uporabnikovem zagonu. iOS HTTP
  ovoj lahko account.changes označi other; koordinator ohrani točno operacijo.
  AOT stack lahko nima izvornih vrstic; prvi prestreženi error ni nujno vzrok.

Obe aplikaciji sta zaprti, agent launch/UI/manualSync/poslovni testi = 0.
Native APNs/FCM ni nastavljen. Starih PASS testov nismo ponavljali; produkcija
ni bila spremenjena. Naslednji korak: uporabnik odpre samo Samsung Jivie Test,
počaka približno 30 sekund in poroča zaslon; brez ročne sinhronizacije ali
urejanja. Nato preberemo nov dnevnik in nadaljujemo z iPhonom.

Dokazi in bralnika: `build/qa/jivie-mobile-update-20261025/`
(`root-results.json`, `android/installation-evidence.json`,
`android/profile-preservation-evidence.json`, `ios/installation-evidence.json`,
`server/upgrade-result.json`). Server capture je omejen na 180 s/256 KiB;
zažene se ob predaji uporabnikovega ročnega preizkusa. Namestitev ni dokaz
prvega uspešnega mobilnega synca ali produkcijske pripravljenosti.

Po preverjenih namestitvah odstranjenih 20 izrecno pregledanih obnovljivih
predpomnilnikov oziroma podvojenih gradbenih map (2.805.202.944 B). Končni
APK/IPA, iOS arhiv z dSYM, izvori, dokazi in varnostne kopije ostanejo;
hashi končnih paketov po čiščenju isti.

### 25. oktober — prvi Samsungov zagon: Utrip in sync zaključka PASS

Uporabnik poroča takojšen Utrip, brez ustavljanja v čarovniku; na kratko
se pokaže neidentificiran zaslon za potrditev in sam izgine. Njegova
identiteta/razlog iz dnevnika nista dokazljiva; UX opažanje ostaja zapisano.
En read-only bralnik, brez agentovih UI/sync dejanj: 2034 dogodkov med
07:50:25–07:51:51 UTC, 504 HTTP vsi200, brez429. Dva začetna zaključka
ob07:50:39 in07:51:21: code none/unresolved false/retry false. Prvi
uporabi predhodno shranjene capabilities (selectionLegacyServer), drugi
pridobi prvi account.changes cursor; potem07:51:51 samo account.changes
→unchanged. Ne gre za idlebenchmark ali dokaz odzivnosti urejevalnika.
Dvakrat prestrežena crypto_record_policy_existing_scope_upgrade_pending
(crypto_record_policy_baseline.dart206/144): izvor potrjuje namensko
odloženo prevzemanje novih pravil na obstoječih prostorih, catch jo
izrecno loči od sync napake. Nova pravila urejanja starega prostora zato
NISO potrjena; to je že dokumentirana odprta nadgradnja, ne izginuli podatki.
Strežniški180s zajem se je končal pred uporabnikovim zagonom (6vrstic,
config restored); ta sklep temelji na novem Androidovem dnevniku, ne njem.
Dokaz android/first-user-launch-summary.json in diagnostic-read-20261025T075213Z.json.
NEXT uporabnik odpre samo iPhone Jivie Test, počaka30s in poroča; brez
manualSync/Save/ponovnega Samsungzagona. Ob opozorilu se ustavi.

### 25. oktober — iPhone po uporabnikovem Continue: prvi sync PASS

Uporabnik odpre isto Jivie Test, na Obnova celotne namestitve klikne Nadaljuj
v lokalne podatke in počaka. Opozorilo ostaja UX ugotovitev; njegov izvor
v tem koraku ni znova izmerjen. En read-only zajem native-read/
20261025T075905154486Z.json:1572dogodkov07:57:28–07:58:47UTC,388HTTPvsi200,
0actual429. Completion1/2 code none/unresolved false/retry false.
4caught crypto_record_policy_owner_pending sta po2scope/2initialcycle,
sourcebaseline181/144; znano čakanje prehoda starih prostorov na novo
politiko, izrecno obravnavano brez syncfail. Cachedlegacycapability startup
inmissingcursor initialization, nato en account.changes→unchanged v66msHTTP.
Ni novega globalnega benchmarka. Agent UI/sync/save0; Android PASS ni ponovljen.
Naslednji nov mobilni preizkus: na iPhonu enkrat odpri MOBILE-PROJECT-1 /
MOBILE-SHARED-1, brez spremembe/shranjevanja, pusti odprto; primerjamo občutek
odzivnosti in sveže UI markerje, ne ponavljamo že potrjenega prenosa podatkov.
Dokaz ios/first-user-launch-summary.json v današnji mobile-update mapi.

### 25. oktober — iPhone odpiranje istega opravila: 42 ms, PASS

User odpre MOBILE-SHARED-1 in ga pusti odprtega brez spremembe; opisuje
praktično takojšen odziv. Novi markerji ob08:00:07UTC: taskEntered→
editorEntered18ms, editorEntered→editorWidgetFirstFrame24ms, skupaj42ms.
V tem intervalu0HTTP; nobena nova napaka. V okolici le običajni30s
account.changes→unchanged, brez vsebinskega synca. To je čas od vstopa
v handler do Flutter postframe, ne meritev fizičnega dotika/compositorja.
Prejšnjih~20s je uporabnikova ocena na starejši gradnji, brez trditve o
natančnem faktorju izboljšave. Read-only capture1, agentUI/sync/save0.
Dokazi ios/task-opening-summary.json in native-read/20261025T080046412525Z.json.
NEXT uporabnik naSamsungu enkrat odpre isto opravilo, brezedit/save;
iPhone ostane odprt. Androidova odzivnost nove verzije še ni izmerjena.

### 25. oktober — Samsung odzivnost PASS; neenoten predogled/urejanje

User odpre isto opravilo, opiše praktično takojšnje odpiranje, predogled
in potreben ločen Uredi opravilo, medtem ko je iPhone odprl editor neposredno.
Native seq2151–2153 predogled74ms, seq2247–2249 predogled45ms; nato
taskEntered→editorWidgetFirstFrame73ms (seq2354–2356). Zabeležen tudi
prejšnji nepovezan editor124ms brez taskEntered; ne pripisuj ga istemu tasku.
Novi zajem69HTTPall200/0newcaught, brezSave markerjev; ne trdi0HTTP za
celoten predogled, ker v ozadju preverja metadata. Source: all_spaces_rows
openAllSpacesRow vedno odpre preview, SharedActions.openTask pa editor
če canEditRecord; ni platformnega pogoja. Exact izvor navigacije/pravice
v trenutku prvega dotika niso logirane, zato ne trdi izgube pravic ali
vedno različnihOS. UX neenotnost zabeležena, brez spremembe kode.
Dokaz android/task-opening-summary.json +diagnostic-read-20261025T080327Z.json.
NEXT nov test prenovljenega changed-only synca in že odprtega čistega
osnutka: Samsung v že odprtem taskeditorju DODA TEST-SYNC-25 v opombo,
ohrani stari tekst in enkratSave. iPhoneisti editor ostane odprt/pristine.
Počakaj30s, report; nato preveri dnevnika in prihod spremembe brezreopen.

### 25. oktober — Samsung Save → iPhone odprti čisti editor samodejno PASS

User doda TEST-SYNC-25, staro besedilo ohrani, Save1; user potrdi samodejno
osvežitev istega odprtega iPhone opravila brezreopen. AndroidSave08:05:21.357UTC,
en records.batch20008:05:22.763, completion3none/unresolvedfalse08:05:24.644.
IPhone contenthint08:05:48.308, completion3none/unresolvedfalse08:05:51.200,
približno29.84s po Save; to ni meritev trenutka GUIosvežitve. Obaselected
scopes1/content1/finance0. Android še owncatchup completion4clean nato
unchanged; iPhone naslednji verifiedJournalOnly→unchanged. NovihHTTP84A/60B
v različno dolgih intervalih, vsi200;0x429. Znani iOS owner_pending še
prestrežen/handled, ni nova napaka ali dokaz prenovljene politike starega
prostora. AgentUI/sync/save0, payloadnihbral, konkretno besedilo potrdiuser.
Dokaz samsung-to-ios-25-summary.json, oba sveža bralnika08:06:46UTC.
NEXT reverse na novi verziji: iPhone v istiopombi DODA TEST-IPHONE-25/Save1
obvsehstarihvrsticah; Samsung naj ostanepristineopen,wait30s/report.

### 25. oktober — iPhone→Samsung obratni prenos in samodejna osvežitev PASS

User iPhone appendTEST-IPHONE-25/oldtextheld/Save1, Samsung auto-refresh
USERPASS. Logs iOSSave08:09:47.870UTC→onebatch20048.901→completion4clean
51.170; Samsung completion5clean08:10:01.223 (~13.35s afterSave, neGUIčas).
Obaselectedscope1/content1/finance0, novHTTP60Android/93iOSall200/0x429;
iOSknownowner_pendinghandled, owncatchupclean, oba kasnejeunchanged.
VAndroidlogu noveditor08:09:51 predpullom; user potrdi prihod brez ponovnega
odpiranja po prihodu spremembe. Sourcebehavior enak pristineauto-update.
AgentUI/sync/save0, payloadnihbral. Evidence ios-to-samsung-25-summary.json.
NEXT novdirtydraft test: Samsung doda DRAFT-25 brezSave v istoopombo;
iPhone doda REMOTE-25 v istoopombo+Save1; wait30s. Samsung ne sme izgubiti
osnutka in naj pokaže organizerNewerVersion nad naslovom. SamsungšeNESave.

### 25. oktober — neshranjen osnutek ohranjen in opozorilo USER PASS

Samsung DRAFT-25 ostane neshranjen; user potrdi newer-versionnotice po
iPhone REMOTE-25 Save1. Novi dnevniki: iOSbatch20008:14:42.093UTC,
cleancompletion6/7, Samsungcleancompletion6ob08:15:05.833UTC. Bothscope1/
content1/finance0;52A/83BnewHTTPall200. NoAndroidSave/UIagentactions.
KnowniOSowner_pendinghandled ostaja. Dokaz dirty-draft-25-summary.json.
Pred naslednjim korakom sourcecheck: updateTask→_put z expectedLocalRevision
ob mismatch vrže stale_edit pred enqueue. Outbox3waymerge ni dokazdialoga
za razrešitev že odprtega zastarelega editorja. Zato naslednji omejeni test
preveri Saveguard, NE obljublja izbire različic: Samsung1Save brez drugihe
sprememb, pusti rezultatviden/report exactmessage; ne ponavljajSave.

### 25. oktober — zastarel Save varno zavrnjen; razrešitev v editorju MANJKA

Samsung userSave1 ob08:17:11.947UTC, pokaže sharingStaleEditor: zapri,
odpri zadnjo različico, prej skopiraj besedilo. Osnutek DRAFT-25 ostane
odprt, user ne ponoviSave. Native novseq3214–3238 vsebuje1Save marker
in samo account.changes200→unchanged;0records.batch. Source _put guard
expectedLocalRevision→stale_edit predoutboxom potrjuje varno zavrnitev.
Ni silentoverwrite; payloadneprebran, user+source+metadata proof.
SAFETY PASS, dogovorjen uporabniški tok primerjave/izbire/združitve pa
na poti staleeditor NI implementiran. Outboxmerge tega ne nadomesti.
To je odprta funkcionalna/UX vrzel, ne končana razrešitev konflikta.
Dokaz stale-save-25-summary.json, Androidread20261025T081758Z.
NEXT priporočilo: lokalno dopolniti editorconflictreview s preservedbase/
local/remote in preverjanjem revizije; ne ponavljaj Save na telefonu.
SamsungDRAFT-25pustiopen, iPhoneREMOTE-25ostane canonical; noben reset/
reopen/discard/ročno kopiranje ni izvedeno. Ta turn ni implementiral popravka.

### 25. oktober — uporabnik sprejme ročno razrešitev za to izdajo

Uporabnik izrecno prestavi izboljšavo stale-editor postopka po javni
objavi. Varovalo in navodilo copy/reopen sta za to fazo sprejemljiva;
prejšnji predlog ustavitve testov zaradi tega UX je razveljavljen.
Novi dokument docs/POST_RELEASE_IMPROVEMENTS.md hrani potrjeno odložitev
in ločene predloge poenotenja predogleda/urejanja ter startup prehodov.
To ne zapira starih scope policy upgrade/restore/mobile drugih vrzeli.

Dogovorjen samostojni Samsungov pregled brez kabla: istiLANWiFi, JivieTest,
Mac/Docker naj ostaneta dosegljiva. Pred odklopom uporabnik razreši znani
DRAFT-25 po sprejetem postopku: Prekliči, odpri latest sREMOTE-25, dodaj
manjkajočiDRAFT-25 in Save1. Potem normalno zapre/znova odpre samoQA,
da dobi svežo omejeno diagnostično datoteko. Agent tega ne izvaja.

Predlagan pregled uporablja nove QA25 vnose v obstoječem deljenem prostoru:
novprojekt QA25 Prehod; task/assignee/dates/edit/complete; event; shopping
check/uncheck; finance ločen noviQA25račun100 začetno−12,34+20=107,66,
expenseedit15→105, deleteonlynewincome20→85; dokument/tabela/mala
nesenzitivnapriloga/ideje/vrt po razpoložljivosti. Private/local QA25
zapis posebej ne sme priti na drug račun. Delete samo newlycreated
testni posamezni objekti; ne starega prostora/MOBILE testnihrecordov/
računov/članstva/ključev. User lahko poroča module/action/time/result.
Po vrnitvi iPhone preveri shared vsebine in odsotnost novih zasebnih
vnosov; root bere metadataloge/receipts/currentrev/deletion, neplaintext.

Za samostojni krog nova wrapper server/exploratory_capture.py uporablja
iste reviewed guard+finallyrestore,1800s/1MiB, samo time/method/status/
duration/responseBytes; noben URL/header/body/token/payload. Mobilni
dnevnik ostaja3rotatingfiles×1MiB/6000eventsperprocess in lahko prej
doseže mejo; ne obljubljaj popolnega zajema vseh dejanj. Noben poslovni
test v tem koraku še ni izveden.

### 25. oktober — samostojni Samsung pregled najde počasen Create project

User screenshot09:38local Dodaj projekt v organizacijo/MobileE2EE20261018/
qa25 prehod, spinner poSave približno≥20s, končno USPEH. Čas je userocena,
ne instrumentirana meritev. Nov projekta ne ustvarjaj znova.
Readonlysnapshot aktivnega servermetadata zajema za08:37–08:39:59UTC:
1029POST, odtega691v08:37/329v08:38/9v08:39;2POST429ob08:37:47,
preostali200. Skupaj1035zahtev vključuje6GEThealth. NajdaljšiPOST86ms,
sumrequestdurations13.742s ni elapsed/actionlatency in lahko vključuje
sočasnost. Obdobje pokrivaobaodjemalca; brezoperation/account/selector
logov ni mogoče vseh klicev pripisati enemu ustvarjanju.
Sourceconfirmed OrganizationWorkspace._create onSubmit awaitcreateScope
in nato awaitcontroller.syncNow preden se obrazec zaključi. To je
konkretna UI odvisnost odsynca, ne še izmerjen celoten vzrok20s/bursta.
Odprta ugotovitev TRENUTNEGA testa: blokirajoč projektcreate/povečan
requestvolume in429. Ne prestavljaj avtomatsko postrelease zaradi drugega
dogovora o stale-editorUX. Ni fix/rebuild/phoneactions/authbusinessRPC.
Dokaz server/project-create-observation/{summary.json,metadata-snapshot.log}.
NEXTuser nadaljuje že ustvarjeni qa25 prehod/opravila; ne createagain ali
manualsync. Po USBvrnitvi poveži native events s tem časovnim oknom.

### 25. oktober — novega opravila v qa25 prehod ni mogoče čisto sinhronizirati

User novoopraviloSave; avtomatskisyncFAIL in1manualUskladizdajFAIL.
Screenshot09:40local kaže accountwidestatus, lastsuccess09:38/attempt09:40,
pending0/conflict0/blocked0 in cryptoConnectionPending besedilo.
Source sharing_errors.dart mapira crypto_reconciliation_required /
crypto_transport_required / crypto_server_upgrade_required v isto besedilo;
exactruntimecauseUNKNOWN. Ne sklepaj da je uporabnik izgubil ključe ali
mora ponovitišifriranje. Isti strežnik je že source1694c42/schema23.
Readonlyservercapture08:39–08:41:58UTC201POSTall200,max94ms,0x429;
prejšnjiburst2x429ob08:37 ne dokazuje vzroka te nove napake. HTTP200
ne pomeni cleanclientcompletion/prenosa;0UIqueues ni dokazprihodaB.
Noagentphone/UI/businessRPC/reset/rekey/fix/rebuild. Preserveistoopravilo/
projekt/requeste, userno furthermanualretry. Dokaz server/
task-create-sync-observation/{summary.json,metadata-snapshot.log}.
NEXT poSamsungUSBreturn preberifreshboundedcache originalcaughtcode/frames
in completions ter primerjaj08:40window; ne ponavljajSave/sync za diagnozo.
Ta test ostajaFAIL/open; ne nadaljuj dependentcross-device projekt testov
kot da je prenos uspel.

### 25. oktober — Utrip postavitev in nejasno dodajanje dogodka

Uporabnik med navigacijo v qa25 prehod priloži Samsung screenshot09:42
(1000012436.jpg). Vidno: kartica Današnji dogodki odrezana pri povezavi
Koledar; velika praznina pod kartico; spodnji navigacijski napisi so
delno prekriti s sistemskim navigacijskim območjem. Zabeleži kot trenutni
UIdefekt, ne dokaz izbrisanih podatkov. Rootcause (insets/layout/scroll/
transition) iz ene slike ni določen; ne pripisuj ga syncnapaki.
User opozori da sam + ne pove dovolj jasno, da dodaja dogodek. Predlog
vidnega lokaliziranega gumba Dodaj dogodek ob ustrezni prilagoditvi širini
in velikosti besedila; cilj ni samo tooltip. Preveriti celotno višino
kartic/pomikanje/spodnji safearea. Brez kode/rebuild/phoneclick/testrepeats.
Evidence today'smobile-update/ux-observations.json. User nadaljuje
samostojni pregled; tega primera ne ponavljaj med beleženjem.

### 25. oktober — Samsung po reopen spet Zaščita povezanih podatkov

User screenshot1000012438 ob09:43local po zaprtju inponovnemodprtjuQA.
ZaslonZaščitapovezanihpodatkov pove, da ni navedenih dodatnih korakov
priprave, ponujaPreveriinkončaj/Nadaljujlokalno. ZaMobileE2EE20261018
prikazuje noveprenosešifrirane/starekopijeohranjene/rokizbrisanepotrjen
in akcijepregled/finance/noviključi. PodtemMOBILE-PROJECT-1 kartica.
Zabeležena ponovna pojavitev že prej zaključenega accountwizardja; exact
startup/completionflag/newscope razlog UNKNOWN do nativeevidence.
To ni iOSrestorewarning, ne dokaz izgubljenih ključev ali nešifriranih
novih prenosov; earlierbriefSamsungscreenidentity ostajaunknown.
Userprejšnjidogovor30dni po uspešniobnovi starihkopij ostaja; screenshot
ne potrdi izvedbe te politike. User naroči samo beleženje, brezklikov/
rebuild/reset/ponovnepriprave ali spremembehrambe. Evidenceux-observations.

### 25. oktober — Koledar skrit in vrnitev na pogled ni razumljiva

UserSamsung screenshot1000012440/09:44local: qa25prehod, Planer, izbran
Koledar, naslovČasovnica in seznamDogodeks25/Novoopravilos25/projekt.
Koledarskamreža ni vidna; user ne najde načina ponovnegaprikaza.
Ellipsismenuviden, ni jasnegapreklopa aliPrikažikoledar. Evidentiraj
navigacijsko/UXtežavo: jasenpreklop prikaza in razumljivo ujemanje
izbranegazavihka/dejanskegapogleda. Screenshot ne določi ali gre za
collapse/timelinemode/renderbug, dogodkiso vidni vlisti/ne data-lossclaim.
Useronlyrecord, noagentUI/sourcechanges/retest. Evidenceux-observations.json.

### 25. oktober — gospodinjstvo se ustvari bistveno hitreje

Uporabnik naSamsungu poroča, da je ustvarjanje novega gospodinjstva
bistveno hitrejše od ustvarjanja projekta znotraj obstoječega deljenega
prostora (prej ocenjenih≥20s). Točnega časa gospodinjstva ni navedel;
gre za kvalitativno primerjavo različnih poti, ne kontrolirano meritev.
Ne sklepaj da ima novo gospodinjstvo iste člane/deljenje ali da je vzrok
že določen. Ohranimo kot uporabno razliko za poznejšo primerjavo dnevnikov.
Nakupovalnega seznama v projektu user ni našel in meni, da je to smiselno;
zato prehaja na preizkus nakupov v gospodinjstvu. Odsotnost v projektu
ni potrjena napaka in ni zahteva za dodajanje funkcije.
BrezagentovihUI/server/businessdejanj ali ponovitveustvarjanja.

### 25. oktober — Računi prostora napačna pot in neuspešen Save računa

Samsung userreport09:48 screenshot1000012442: Finance vprojektu, izbrani
scopeMOBILE-PR…truncated (ne sklepaj qa25/gospodinjstvo). Userklik
Računiprostora→Dodajračun neposredno; pričakuje seznam računov prostora
inšele nato dodajanje, s praznimstanjem če je seznam res prazen.
Na screenshotu piše računišeNISONAVOLJO/poveziteinosvežite, Dodajzapis
je disabled in oblačekred. Unavailable ni empty; seznam mora razlikovati
nalaganje/nedostopnost/napako/pravilnoprazenizid.
LočenFUNCTIONALFAIL: userporočashranjevanjenovegaračunaniuspešno.
Exacterror/attemptcount niso navedeni;slikaneprikazujeSaveerrorja.
Ni dokaza izgubeali uspešnegacreate; no new retry/create/financebalance
scenariountilresolved. Preserveexistingdraftifpresent. Po priklopu
preberi retainednativeokoli09:48local in correlateaccountcreateguard.
Userfeedbackrecordedonly, noimplementation/phoneactions. UX+FAILv
today'smobile-update/ux-observations.json.

### 25. oktober — gospodinjski vrt zmeden in Save neuspešen

UserSamsung screenshot1000012444/09:50local, vrtaqa25/Sezona2026,
scena2gredici. Userzahteva prenovo risanja in premikanja med prikazi.
LočenoFUNCTIONALFAIL: redcopySpremembnibilomogočeshraniti/Osnutekješe
odprt/poskusiznovaaliodprizadnjo; spodajNeshranjenespremembe. Točna
izvorna napaka/attemptcountneznana, genericcopy ni dokazstaleconflict
alisyncnapake. Prikazanascena ni proof persistence.
Preserveopen draft; NOretry/close/reopen/reset odagenta ali priporočila
za diagnozo. Po reconnect preveri obstoječednevnike; če UIcatch ni
instrumentiran, pošteno navediomejitev namesto ugibanja.
CelovitaUXprenovaje predlogvPOST_RELEASE_IMPROVEMENTS, prioritetni
terminšezadogovor; savefailure ostaja currenttestbug, ni odložen
skupajzvizualno prenovo. Brezkode/build/phoneactions/retest.

### 25. oktober — ponovni zagon ne ohrani zadnjega prostora

Uporabnik poroča, da se ob ponovnem odprtju aplikacije odpre lokalni
prostor namesto nazadnje odprtega. Pričakovano: obnovi zadnji izbrani
prostor, če obstaja in je dostopen trenutnemu računu; sicer jasen fallback.
Vzrok še ni določen (persistenca/obnova/poznejši startup ali protection
redirect). Brez reprodukcije, sprememb kode ali posega v odprti vrtni
osnutek. Zabeleženo v današnjem ux-observations.json.

### 25. oktober — prvi samostojni pregled izvornih poti

User dovoli začetek analize brez prisotnosti. Read-only pregled kode in
zbranih metapodatkov; brezpodagentov/phoneactions/novihtestov/rebuild/
productedits. Konkretnotakojšnje ugotovitve:

- ProjektOrganizationWorkspace._create awaitcreateScope→awaitsyncNow;
  createScope šeawaitrefreshLocal. Blokirajoča UIpot potrjena; deleži
  dejanskega20s čakanja in izvorrequestbursta ostajajo za nativeevidence.
- SharedFinanceWorkspace Računiprostora onPressed→actions.account(),
  SharedFinanceActions.account brezargumenta odpira kreiranje računa
  vnadrejenem prostoru, če pravice/snapshot dopuščajo. UX povezava
  neposredno potrjena; shranjevanje računa je ločen nedoločen problem.
- Shared timeline route→SharedAgendaPage(timeline:true). Ta komponenta
  riše seznam+filtre, ne mesečnekoledarskemreže. Lokalni koledar je druga
  komponenta. Screenshot ni dovolj za fullnavtrace, je pa verjetna
  razlaga zakaj uporabnik ne najde prikaza mreže: vtemview ga sploh ni.
- Startup cachedcompletion se primerja z manifestom trenutnega kataloga
  prostorov. Obmismatch gre readyphase nazaj vCryptoMigrationWizard;
  spremembakataloga po novihprostorih je možna povezava s ponavljanjem,
  NE potrjen runtimevzrokbrezlocalcompletionevidence.
- GardenSaveError pokriva vse non-CollaborationException, vključno z
  možnimi workspace/revision/storage errorji. Ne diagnosticirajstale
  zgoljizcopy. QAlogger originalcatchhooks so sync/finance, ne gardenUI;
  exactUIerror morda ne bo vretainedlogs.
- selected_space:$partition seže shranjuje in bere. Ne gre kar za
  manjkajočo funkcijo pomnjenja; preiskati partition/startupnavigation
  fallback/override. SafeArea inNavigationBar tudi obstajata, zato
  clippedUI ne pripiši kar manjkuSafeArea brez runtimebounds.

30-minmetadata zajem končan, gatewayconfigrestored. Čas08:24:44–08:54:23UTC,
4576POST:4564x200/8x429/4x409, maxPOST274ms. Vsi odjemalci skupaj,
ni attribution posamičnimSave;409 lahko pričakovan konflikt ni sam
po sebi dokazbuga.8rate-limits potrjuje aktualnirequestvolumeproblem.
Dokazi first-source-review.json in server/manual-captures/20261025T085443Z.
Naslednje: pridobiti existingSamsunglogs ob priklopu, brezreprodukcije;
prioriteta functionalSave/sync/requestvolume predUX. Žeuspešni testi
se ne ponavljajo, garden draft ostaja nedotaknjen.


## 25. oktober — odpravljanje po samostojnem mobilnem preizkusu

Uporabnik je znova priklopil Samsung in odobril analizo ter popravke. Trije
podagenti GPT-6.1 Sol/high so ločeno obravnavali sync, shranjevanje in vmesnik;
glavni agent je pregledal spremembe, med agenti je bil opravljen tudi neodvisni
izvorni pregled. Telefon je bil uporabljen samo za branje obstoječih dnevnikov.
Noben nov klik, Save, sync, zagon, gradnja ali namestitev ni bil izveden.
Produkcija, originalni Samsung paket, testni podatki, ključi in osnutki ostajajo
nedotaknjeni. Strežnik ni bil spremenjen.

### Potrjen vzrok ponavljajoče sync napake in popravek

Sveži Android diagnostic-read-20261025T090434Z.json vsebuje 13 napak
`directory_proof_pending` v zagonu events-1 (08:43–08:51 UTC). Stack vodi v
CryptoBusinessRouter.needsFinanceForTaskDerivations, ki je pred ugotovitvijo,
ali sploh obstaja nerazrešena povezava opravilo–strošek, zahteval offline
preverjanje glave prostora. To je lahko padlo zaradi nepopolnega lokalnega
dokaza in prekinilo zaključek sinhronizacije. To ni dokaz izgubljenih ključev.
Natančna prva napaka ob 09:40 lokalno ni zajeta: prejšnji dnevnik je prej dosegel
omejitev velikosti. Kasnejši ponavljajoči vzrok je neposredno potrjen.

Popravek najprej preveri obstoj dejanske lokalne odvisnosti. Če je ni, ne izvaja
nepotrebnega preverjanja. Če obstaja, uporabi običajno spletno pridobitev in
preverjanje podpisane glave; podpisana finančna vloga ter ostala varovala
ostanejo. Ni spremembe ključev, formatov zahtev, potrdil ali dovoljenj.
Napaka je preprečevala tudi potrditev account.changes kazalca; ohranitev te
zaščite je pravilna, odstranjen je napačen razlog za prekinitev.

V istem zagonu je bilo 1062 HTTP zahtev, od tega 626 označenih sync, 286 account,
76 scopeManagement. Nobenih prihrankov na telefonu še nismo izmerili in ne trdimo,
da so s tem odpravljeni vsi 429. Ostale poti ostajajo predmet omejene meritve.

### Spremembe v kodi

- Ustvarjanje projekta po potrjeni strežniški operaciji in lokalni projekciji
  ne čaka še celotne sinhronizacije. Obstoječi koordinator dobi zahtevo za sync.
  Nujna kriptografska priprava in zapis ustvarjenega projekta ostaneta obvezna.
- Računi prostora odprejo seznam z ločenim Dodaj račun. Potrjeno prazen seznam
  se razlikuje od nedostopnega ali še nepripravljenega. Član samo projekta vidi
  zgolj že dovoljene podatke iz projektnega izbora računov, brez dostopa do
  bilance ali upravljanja nadrejenega prostora.
- Skupni Koledar ima mesečno mrežo in viden preklop Koledar/Časovnica.
  Obstoječi filtri ter ločitev prostorov ostanejo.
- Utrip in skupni koledar imata vidno besedilo Dodaj dogodek.
- Shranjevanje vrta preverja pravila za prostor, zajet v odprtem osnutku,
  namesto naključno trenutno izbranega skupnega prostora. Znane vrste napak
  dobijo ustrezno obstoječe besedilo; osnutek ostane odprt. To je potrjena
  ločena napaka, ne še dokaz vzroka uporabnikovega neuspešnega Save ob 09:50.

### Lokalno preverjanje in omejitve

20 različnih novih kontrol PASS: sync 4, vrt/finance 6, navigacija 10.
Nobena že uspešna kontrola ni bila ponovljena. Testne priprave so imele nekaj
napak; ponovljeni so bili samo neuspešni primeri. Ciljne analize so brez napak
in opozoril, ostajajo že obstoječe slogovne informacije. git diff --check PASS.

En dodaten Android layout test je dosegel preverjanja scrolla in spodnjih
odmikov, vendar se je zaključil z napako pospravljanja testne priprave.
Pospravljanje je popravljeno, test pa po tretjem poskusu ni bil ponovljen:
NE štejemo ga za PASS. Izvor odrezanega Utripa ni potrjen in ni slepega popravka
SafeArea. Testi niso dokaz delovanja nove različice na napravah ali benchmark.

### Še odprto, brez prikrivanja ali obvoza varoval

1. Natančen izvor prvotnega neuspešnega Save finančnega računa in vrta.
   Lokalni SQLite scenariji uspejo; ohranjeni dnevniki nimajo originalnega
   UI-catch razloga. En omejen read-only logcat pregled ni našel takšne napake.
   Trenutni QA hook beleži sync/finance sync, ne originalnega garden UI catch.
2. Ponovni čarovnik zaščite. Izvor kaže primerjavo podpisanega completiona s
   trenutnim katalogom; nov prostor lahko spremeni hash. Točen shranjeni
   completion na telefonu ni prebran. Ne smemo samodejno podpisovati novega
   completiona ali obiti dejansko nedokončane obnove. Predlog: ločiti status
   spremenjenega pregleda od obvezne obnove; ta prenova še ni implementirana.
3. Začetna izbira lokalnega namesto zadnjega prostora. Obe izbiri sta že
   shranjeni in obnovljeni. Izvorni pregled ni našel brezpogojnega resetiranja;
   pot obvestila lahko spremeni izbor, vendar zanjo v tem primeru ni dokaza.
4. Odrezan Utrip/spodnja navigacija in celovita prenova risanja vrta.
5. Meritev preostalih zahtevkov in potrditev popravkov na isti testni namestitvi.

Naslednja mobilna gradnja naj zajame tudi originalni UI save-catch, razlog
startup odločitve in izvor spremembe izbranega prostora z omejenimi metapodatki;
napake naj imajo ločeno omejeno hrambo, da jih običajni HTTP promet ne izrine.
Ta razširitev diagnostike in nova namestitev še nista izvedeni. Pred namestitvijo
je treba zaščititi morebitni odprti osnutek; ne izvajati ponovitve starih PASS.

Dokazi: build/qa/mobile-manual-fixes-20261025/{sync,saves}/ in
build/qa/mobile-navigation-fixes-20261025/. Izvorni dnevniki ostanejo v
build/qa/jivie-mobile-update-20261025/android/. Brez commita/pusha tega sklopa.


## 25. oktober — Samsung posodobljen z diagnostiko odprtih napak

Uporabnik je naročil diagnostiko in posodobitev ISTE Jivie Test; ponovitve
opravlja uporabnik. Pred posegom je screenshot pokazal Osebno → Planer/Opravila,
brez odprtega obrazca. To je začetna izbira pred posodobitvijo: prvi ponovni
prikaz Osebno sam po sebi NE bo dokaz napake pomnjenja prostora. Ne trdimo,
da smo obnovili osnutek, ki ga je uporabnik že prej zaprl brez shranjevanja.

Trije obstoječi Sol6.1/high podagenti: QA-only diagnostika, Android gradnja,
bralnik/neodvisni pregled; root pregled in namestitev. Prejšnji diagnostični
pomočniki/dnevniki ostanejo. Nova namespace jivie_qa_mobile_issues_20261025_v2,
buildtag android-mobile-fixes-20261025-r1. Zajame originalne garden/account/form
catch izjeme, vrste/kode in največ8 dovoljenih sourcefile/line okvirjev;
startup phase/incomplete/completion/catalog odločitve; read/write/restored
izbiro prostora z izvorom in matchesStored; mere/insete/textscale/area ob spremembi.
Brez imen, vsebine zapisov, gesel, ključev, URL ali surovih sporočil napak.

Napake in odločitve imajo vsaka 3×256KiB krožno hrambo brez življenjske omejitve
števila dogodkov. Promet ima ločeno 3×1MiB/6000 dogodkov; izčrpanje prometa ne
izklopi zajema napak. Vsak tok ima lastno vrsto256 in mejo2048B/dogodek; ob
preobremenitvi ali rotaciji se lahko del dokazov vseeno izgubi. Identitetni tokeni
so soljeni le za tekoči proces (ne primerjati čez restart); booleans primerjajo
shranjeno in obnovljeno izbiro znotraj zagona. Če sploh ni računske seje, manjka
sharedRead/startup phase; odsotnost dogodka ni dokaz konkretnega vzroka.

Štiri nove diagnostične kontrole, pet novih kontrol parserja in en roundtrip
vseh9vrst dogodkov PASS; stari funkcionalni PASS niso ponovljeni. Končna analiza
celotne QA lib:0errors/0warnings,505styleinfos. Ena gradnja/ena namestitev.
Manifest630datotek vključuje627aktualnih worktreevhodov, vseh10spremenjenih
produktnih poti (tudi2noviUI datoteki), triQAhelperje in26overlays. Podpis,
package, nativeknjižnice, vaultnamespace ter exactTLS ostanejo isti.

APK SHA256 f0d65765d4d2b626c284908c716caf9a3d09ba5c465339fc2da061dee853a4ff.
Package si.triparna.jivie.e2eetest.android20261018, istiUID10292/dataDir.
Po cold backup in install-r potrjena vsebinska enakost VSEH20noncache datotek,
121789474B, vključno vault in trajnimi osnutki/namerami. AndroidKeystore ni
izvožen/izbrisan; istaidentiteta/podpis. OriginalGooglePlay metadata nespremenjena,
produkcija in testni strežnik nista spreminjana. Lokalni18801 runninghealthy,
MacIP192.168.132.29 ostaja. Agentlaunch/UI/sync0; QA je po preverjanju ZAPRTA,
novcache namespace še ne obstaja. Native logging/dejanski popravki še niso PASS.

Private kopija je v Library/Application Support/JivieLocalTest/
20261025-mobile-diagnostic-update/Android; dokazi/paket/source/bralnik v
build/qa/mobile-diagnostic-update-20261025/. Odstranjenih samo646preverjenih
obnovljivih datotek te gradnje (1316586945B); APK/izvor/kopije/ključi ohranjeni.

NASLEDNJE: uporabnik odpre Jivie Test, počaka15s, nič ne potrjuje, sporoči zaslon.
Najprej preberemo startup diagnostiko. Ne odpirati uspešno preverjenih opravil,
ne ustvarjati novega projekta/povabila, ne manualsync. Nato po rezultatih
posamično iste odprte napake. Branje:
python3 build/qa/mobile-diagnostic-update-20261025/android/read_diagnostics.py


### Nový diagnostični zagon — runtime vzrok ponovnega čarovnika potrjen

User odpre QA in poroča pretirano/confusing besedilo. Root samo screenshot in
novreader, brez UI/sync/mutacij. 09:33:12 UTC: phase=ready,
incompleteScopeRecovery=false, cachedCompletion=true, catalogMatch=false,
showMigrationWizard. Sprožilec je neujemanje trenutnega kataloga s prejšnjo
potrditvijo; natančna spremenjena postavka kataloga NI prebrana. Ne trdi, da
je treba znova šifrirati bazo ali da vsi prostori že izpolnjujejo vse pogoje.
Screen Zaščita povezanih podatkov navaja ni dodatnih korakov, vendar ponuja
Preveri in končaj/Nadaljuj lokalno in per-space review/finance/key actions:
UX preobremenitev potrjena. Predlog: read-only ocena v ozadju; ob dejanski
potrebi en konkreten korak, tehnične podrobnosti sekundarne. Ni implementacije
ali samodejnega podpisovanja/rotacije/granta. 34HTTP200,0capturedfailure,
NOcompletionevent → ne šteje clean fullsyncPASS. Izbira lokalno matchesStored,
skladna s prednamestitvenim Osebno, NI reprodukcija last-space buga.
Dokazi novi android/first-startup-review.json + v njem navedena screen/diagnostics.


### 25. oktober — poenostavljen zagon zaščite (lokalna izvedba)

Uporabnik potrdi predlog po dokazani startup odločitvi catalogMatch=false.
Skupna ocena za račun/napravo zdaj loči spremembo kataloga od začetne priprave,
nedokončane obnove in manjkajoče potrditve. Samo sprememba kataloga pokaže
kratko neobvezno obvestilo »Preglej«. Nedostopno preverjanje ni uspeh; ponudi
izrecen ponovni pregled. Brez dodatnega pregledovanja vseh prostorov, samodejnih
podpisov, potrditve, grantov ali rotacije. Varovala povezanih zapisov ostanejo.
Po osvežitvi se ponovno preveri lokalna faza/obnova in trenutni lastni device
snapshot, da preklic naprave ali neveljavna potrditev ne postaneta neobvezna.

Ročni pregled ohrani dejanske potrebne korake in napake, zaključene/tehnične
podrobnosti pa zloži pod »Podrobnosti zaščite«. Pregled je vezan na račun;
menjava računa ali odstranitev gostiteljskega prikaza zapre točno njegov route,
ne drugega odprtega zaslona. Vrnitev osveži skupno oceno enkrat za isti račun.
11 novih core kontrol PASS; 12 novih UI kontrol PASS. Dve prvotni UI fixture
napaki popravljeni, ponovljena samo neuspešna primera; uspešnih testov ni rerun.
Core prvih10 kontrol pred dodatnim device guardom, nova11. pokrije ta guard;
UI prvih11 pred dispose guardom, nova12. pokrije odstranitev in tuji route.
Ne predstavlja mobilnega ali full-sync PASS. Sol6.1/high podagenti, root pregled.
Dokazi: build/qa/startup-protection-ux-20261025/core/ in
build/qa/mobile-protection-ux-update-20261025/{ui,shared,android}/.

Android r2 nameščen v isti Jivie Test (si.triparna.jivie.e2eetest.android20261018).
1 gradnja/1 install-r/0 agentlaunch/UI/sync; isti podpis, UID10292, dataDir in
native knjižnice. APK SHA256 00e9c354c089b9b9b8ed5325ebe9d9de0c63aee2523992adae723ae42344aa96.
631 zamrznjenih datotek iz aktualnega dirty izvora, analiza QA0errors/0warnings
(503styleinfos); neodvisni pregled12sourcehashov PASS. Pred zaprtjem sveži
screenshot istega protectionwizard, brez odprtega editform; r1 diagnostika
shranjena. Svež cold backup in po namestitvi byte parity VSEH20noncache datotek,
121854426B. Keystore ni bran/izvožen/izbrisan. OriginalPlay metapodatki in
baseAPK isti; produkcija, backend, iPhone nedotaknjeni. Private backup:
Library/Application Support/JivieLocalTest/20261025-protection-ux-update/Android.
Nova omejena QA diagnostika v3/tag android-protection-ux-20261025-r2 beleži
assessmentstatus/reason in originalcatch; dva nova adaptersmoke PASS, stari
logger/reader/PASS nespremenjeni. Native ocena in odzivnost še čakata uporabnika.
645 obnovljivih datotek te gradnje (1316013219B) odstranjenih; APK, izvor,
ključi, dokazi in kopije ohranjeni. QA zaprta, sveži diagnostični imenik še ni nastal.

NASLEDNJE: uporabnik odpre Jivie Test, počaka15s, za zdaj ne klikne »Preglej«
ali sync. Nato read-only preverimo nov zaslon in oceno; ne ponavljamo uspešnih
prenosov/vnosov. Reader:
python3 build/qa/mobile-protection-ux-update-20261025/android/read_diagnostics.py


### 25. oktober — r2 uporabnikov prvi zagon: neobvezno obvestilo PASS

User odpre SamsungQA in počaka brez potrjevanja. Root read-only screenshot+
reader ob10:10:51UTC: Osebno/Utrip, kratek catalog-change notice/Preglej,
brez prisilnega wizard. Assessment catalogChanged pri1058ms od začetka
loggerja (ne cold-start benchmark).8HTTP/8x200, en scopes.catalog; account.changes
2x približno30s narazen, oba unchanged, brez fullcontent/finance prenosa v
zajetem oknu.0capturedfailure; ni fullsync/write/globalreadiness dokaza.
Osebno matchesStored, skladno s preupdateizbiro, ne lastspacebug reprodukcija.
Native nonblockingstartup PASS; ne ponavljaj. Evidence android/first-startup-review.json.
NEXTuser enkrat Preglej, pusti ročni pregled odprt, brezFinish/technicalactions;
preverimo novo zloženo vsebino, nato nadaljujemo odprte save napake.


### 25. oktober — r2 ročni Preglej: končni prikaz uspešen, nalaganje utripa

User enkrat Preglej, brezFinish; poroča prikaz/izginjanje prostorov. Root samo
screenshot+reader: finalreview brezerror/busy, enabledPreveriinkončaj,
Nazajvaplikacijo in zaprtePodrobnosti. Source _discover objavi vse kandidate,
nato inspect po enem; UI nullstate šteje kot necommitted in vsakcommittedkartico
premakne pod zaprtepodrobnosti. To pojasni uporabnikovo opažanje; vmesni video
ni zajet. UXNAPAKA odprta: stabilno nalaganje, nato končne skupine, brez skakanja.
ReviewHTTPokno10:14:38–40UTC:26HTTP200 (catalog6/account5/headGet5/
directory.status8/directory.read2), brezmutationHTTP;0capturedfailure.
Ponavljanje catalog/account pri per-scopeinspect zabeleženo za pregled ponovne
uporabe že preverjenega konteksta; freshness/signature varoval ne odstranjuj.
Ne gre za neskončno zanko: po koncu v zajemu samo običajni account.changes.
Ni fullcompletion/syncPASS. Agent0UI/sync. Evidence android/manual-review-observation.json.
NEXTuser enkratPreveriinkončaj, počakareturn/error; brezdrugihgumbov.


### 25. oktober — r2 potrjena zaščita; qa25 sync še nepotrjen

UserFinish→qa25prehod→oblaček brezmanualsync. Rootreadonlyscreen+reader:
protectionReady200/receiptget200, assessmentcurrent/none10:17:39UTC. Novo
potrditev zaščite označimo uspešno, ne ponavljaj. Sharedselectionaccessibletrue/
matchesStoredtrue. Screen uskladitev še ni potrjena, attempt ni zabeležen,
0pending/0conflict/0blocked/brezerror. Probe10:17:52 verifiedJournalOnly→unchanged→
cursorAcknowledged, brezfullsynccompletion; ne sklepaj da so vsi stari vnosi
preneseni.0capturedfailures,87newHTTP200 med odčitkoma (vključuje potrditev in
periodične probes), ni performancePASS. Evidence android/protection-completed-project-sync.json.
NEXTuser Uskladi zdaj ENKRAT, pustiresultopen; nadaljevanje prej neuspešnega
synca qa25, ne nova priprava/povabilo/vnos. Root0UI/sync.


### 25. oktober — ročni sync preveri uspešno, oblaček ostane »nepotrjeno«

Userreport1click/noresponse. Root0UI/sync, screenshot ostaja unconfirmed/
neverattempted/0queues/noerror. Novi log ima interactive account.changes200
10:22:13(109ms) in10:22:23(66ms), oba unchanged; števila klikov ne sklepamo iz
2jobov. Backgroundprobes normal30s. Nobene zajete failure/fullsynccompletion.
Source: _coordinateSyncPass unchanged branch vrne pred _performSync in ne
zapiše lastSyncAttemptAt/lastSuccessfulSyncAt; dialog dejansko watcha provider.
To pojasni pomanjkanje povratne informacije, ni dokaz nedostavljenega dotika
ali zagotovilo prenosa starih podatkov. OPENUX: ločiti uspešno preverjanje brez
sprememb od prenosa, prikazati ročno aktivnost/rezultat brez siljenja fullsynca.
Evidence android/manual-sync-noop-review.json. NEXT nov dejanski edit na ISTEM
prej problematičnem Novo opravilo s25 vqa25:appendQA25-SYNC-OKnotes/1save,
oldtextpreserved, automatic sync, brezmanualretry. NeponavljajstarihPASS.


### 25. oktober — qa25 dejansko shranjevanje in autosync PASS

UserappendQA25-SYNC-OK v obstoječeNovoopravilos25/1Save/ohranjeno besedilo,
poročagreen+~5s. Rootread-onlyscreen zelen, logsave10:24:42.082943,
records.batch20044.067681,receipt20044.092775;completionseq1/none/unresolvedfalse/
retryfalse46.669295, nato cursorACK. Save→completion4.586s, save→batchreply1.985s.
SelectedWork1scope/content1/finance0. EditorEntered→firstFrame69ms (ne cela
interaktivnost). Novo dejansko urejanje/avtosync PASS, neponavljaj; vsebina markerja
na drugi napravi še ni preverjena.55newHTTP200 med odčitkoma, ne splošni perfPASS.
Diagnosticfailure1 existing_scope_upgrade_pending: source explicitcaught/expected
defer starega scopepolicyupgrade, ne terminalsyncfailure. Ohranjeno za poznejši
pregled pravil in diagnostike; ne preimenuj v prenosno napako ali trdi0caught.
Evidence android/task-edit-autosync-result.json. NEXT user close via recentapps/
reopen to test exactpersistedqa25selection; ne novtask/manualsync. Podatki isti.


### 25. oktober — pomnjenje zadnjega prostora USER PASS

Uporabnik zapre Jivie Test iz nedavnih aplikacij, jo ponovno odpre in brez izbire
vidi qa25 prehod. To je prvi izrecni preizkus ponovnega zagona po shranjeni izbiri
tega projekta: USER PASS, ne ponavljaj. Agent ni izvajal novih device/read/sync
klicev; ne trdi ponovne runtime potrditve zaščite ali sinhronizacije.
Naslednje nadaljevanje odprtega garden-save testa: gosp25 → obstoječi vrtaqa25,
majhen premik ene obstoječe grede, en Save; ohrani vsebino/osnutek, brez novega
vrta ali ponovnih klikov ob napaki. Uporabnik poroča o napaki ali uspehu.


### 25. oktober — vrt: grede USER PASS, sezona/kulture lokalni konflikt

User novegrede SavePASS, potemlepšiprikaz+sezona/kulture SaveFAIL. Screenshot
»Zapis se je vmes spremenil ali kopija vsebuje obstoječe zapise ... uvoz ...«,
Neshranjene spremembe; osnutekostajaodprt. Originaldiagnostic gardenSave
10:29:49.150372 organizer_conflict,22msafterSaveEntered; frames
GardenRepository._current114→updateGarden123→_change69/queue37. Predstorage.write:
currentmissing ali revision/createdAtmismatch. Konkretne primerjanevrednosti niso
zajete, ne trdi točne revisionrazlike/druguporabnik/network/cryptoFAIL.
PrvoSave10:29:28, synccompletion10:29:32.540none/unresolvedfalse. Drugpoznejši
synccompletion ne pomeni uspeha zavrnjenega gardenSave. Editor uporabi začetni
widget.garden kotbase; kandidat lasten save/syncprojection stale-base, potrebno
lokalnorepro dvehurejanj ssyncvmes. Konfliktnegaguarda ne odstraniti.
Dodatno OPENcopy: omemba uvoza pri normalnem shranjevanju je zavajajoča.
Root screenshot+reader/sourceonly,0UI/sync/retry/build. Pusti phoneeditorodprt,
ne reinstall/force-stop zaradi živih seasons/cultures osnutkov. Evidence
android/garden-season-save-failure.json. Uspešnega risanja ne ponavljati.


### 25. oktober — lokalni popravek vrtnega ACK in drugega urejanja

User naroči localrepro/fix s Sol6.1/high; izrecno dovoli zavreči testni phone
draft za poznejšo ponovitev. Dva nova Sol6.1/high podagenta (izvedba in neodvisni
pregled), root source/rezultati. Brez phone/Docker/server/nativebuild/install.
Repro uporablja pravo SQLite memory, SharedGardenStorage, GardenRepository,
outbox ter repository push/ACK/pull, sintetični legacy transport. Prvo shranjevanje
premakne gredo, drugi editor zajame rev3 pred ACK; identični ACK prej dvigne rev4
ob nespremenjeni vsebini/createdAt in zavrne naslednji season/crop save. To dokazuje
lokalni mehanizem; originalphone primerjane vrednosti niso bile zajete.

Popravek v collaboration_sync_actions _applyRemote prejme acknowledgedOperation
SAMO iz uspešnega push ACK v isti epoch/lease transakciji. Lokalno revizijo vrta
ohrani samo za točen livegarden, isti account/partition, expected→expected+1
serverrevision, brez drugega queuedop, ob popolnoma enakem request/current/canonical
payloadu. Primerjava canonical JSON odpravlja le različen vrstni red ključev;
ne izpušča revizij/timestampov ali drugih polj. Serverrevision/remote knjigovodstvo
se posodobi. Vseh11 drugih callsites ohrani prvotno delovanje (noackargument).
_current, storage CAS, workspace/identity/author, izbris/obnova in prave spremembe
ostanejo strogi. Ni migracije sheme ali spreminjanja starih podpisanih zahtev.

4 novi podatkovni primeri PASS: oba zaporedna save+ACK z novo sezono/kulturo;
prava novejša vsebina istega računa zavrnjena; delete+exactrestore ne oživi starega
editorja; naprednejši canonicalexpected+2 ne šteje kot nespremenjeni lastniACK.
Novi UI primer PASS za ohranjen odprti osnutek in dedicated gardenEditConflict
SL/EN; ne omenja uvoza ali kopiranja besedila. Po copy spremembi je bil ponovljen
samo ta prizadeti primer. Prejšnji uspešni funkcionalni testi niso ponovljeni.
Ledger ohrani2začetna fixtureFAIL, nato dejanski predpopravni FAIL in postfixPASS,
UIfixturecompileFAIL in popravek; ne trdi manjšega števila vseh invocations.
Analiza0errors/0warnings,9obstoječihstyleinfos; končniUI/l10n0issues/diffcheckPASS.
Root potrdi10končnih hashov. Dokazi build/qa/garden-season-save-fix-20261025/.

Meje: sintetični transport ni encrypted-proof/native test. Sočasna zunanja
projekcija istega canonical med pendingoutbox lahko še konzervativno povzroči
konflikt v stari poti; ni trditve o popravku vseh race scenarijev. Samsung še
uporablja r2, nov popravek NI NAMEŠČEN. Naslednje posodobitev iste testne aplikacije
in uporabnikova ponovitev samo neuspešnega garden season/cultures koraka.


### 25. oktober — Samsung r3 z garden ACK popravkom nameščen

User izrecno sameQAupdate+diag/preservedata/nooriginalprod. Sol6.1/high agent
stage/build, rootreview/preflight/coldbackup/install. Preclose screenshot isti
neuspešni gardeneditor; user prej izrecno dovolil zavreči ta testni neshranjeni
osnutek, zato QAforce-stop brez save. Stari r2 dnevnik prebran/ohranjen.
1build1install-r,0agentlaunch/UI/manualsync; istipackage/sign/UID10292/dataDir/
nativelibs/vaultnamespace/exactTLS. APK SHA256
f2dd86f84f2b8b18b3c62ef74805a416a1c04af15d9e78769bda1fb584039a77.
631frozenfiles/628currentproductinputs/22dirtyfiles/27overlays; final garden
10hashes isti kot lokalno preverjena izvedba. QAanalyze0errors0warnings503infos.
Brez novih funkcionalnih testov ali ponovitve PASS. Nova namespace
jivie_qa_mobile_garden_20261025_v4/tagandroid-garden-fix-20261025-r3 uporablja
preverjeni schema2/hooki1x, ločen gardenSaveEntered/originalcatch/synccompletion/
networkmetadata. Brez novih vsebinskih/ključnih podatkov v diagnostiki.

Freshcold vseh20noncachefiles122160970B byteparity po namestitvi potrjena.
Keystore ni bran/izvožen/izbrisan. OriginalPlay metadata/baseAPK isti; produkcija,
backend in iPhone nedotaknjeni. Privatebackup Library/Application Support/
JivieLocalTest/20261025-garden-update/Android. QA ostane zaprta; novdiagnostični
imenik še odsoten. Native gardenfix šeNEPREVERJEN.645regenerablebuildcachefiles
1316033876B odstranjeno; APK/source/evidence/backups/keys ohranjeni.
Dokazi build/qa/mobile-garden-update-20261025/android/; reader read_diagnostics.py.
NEXTuser odpre istoJivieTest→gosp25→vrtaqa25→lepšiprikaz; dodasezono/kulturo
obstoječigredi/1Save/wait15s, no redrawbeds/manualsync; pustiresultopen/report.


### 25. oktober — r3 sezona/kulture na Samsungu PASS

User »zdaj dela vse«. Freshreadonly log: gardenSave10:48:14.150,
records.batch20016.037,completionseq1/none/unresolvedfalse/retryfalse18.549.
Save→completion4.399s,0capturedfailure. Garden season/culture save+autosync
USER/nativePASS; neponavljaj. Ni dodatnega drugega-deviceplaintext dokaza.
Root0UI/sync. Evidence mobile-garden-update-20261025/android/garden-native-result.json.
NEXTprejfailedfinance account: existingMOBILE-PROJECT-1→Finance→Računi prostora,
zaenkrat samo seznam (brez novega računa, da ne podvojimo morebitnega prejšnjega).


### 25. oktober — finance: račun qa25 že viden, ne ustvarjamo dvojnika

User odpreMOBILE-PROJECT-1→Finance→Računiprostora/noadd. Rootscreenshotdejansko
Financepage(ne ločenaccountdialog), green, enabledDodajzapis, card»racun qa25·EUR«/
Računnadrejenegaprostora. Obstojprojekcije potrjen; ne vemo kdajustvarjen/izid
izvirnegafailedsave, ne štej separateaccountdialogUXPASS. Novi interval131HTTP200/
0capturedfailure, vključuje backgroundcompletionseq2none; ni atribucija enemukliku.
45directory.status/23headGet zapisano za poznejšo optimizacijo, ne globalperfPASS.
NEXTnovexpenseTEST-FINANCE-25/12,34EUR/existingracunqa25 vMOBILE-PROJECT-1,
1Save/wait15s/noManualsync; no duplicateaccount. Root0UI/sync.
Evidence android/finance-existing-account-review.json pod mobile-garden-update-20261025.


### 25. oktober — nov finančni vnos: lokalno shranjen, sinhronizacija neuspešna

25. oktober — **TEST-FINANCE-25 localsave PASS, finance sync FAIL**.
User1Save12,34EUR/racunqa25; formclosed/visible. Rootreadonlyscreenredcloud,
projectexpense12.34. Fresh10:54read: financeCaught crypto_business_ack_projection_pending
10:54:09.730/31.119UTC; completions3/4 crypto_reconciliation_required unresolvedtrue.
Exact boundary frozenr3 requireExactBusinessProjection4527 via3158/3118/2189;
missing/mismatchedfield NOTlogged. HTTP373all200 interval inclidle/nav; notproof
exactexpenseapplied. Policyexisting_scope_upgrade_pending separatelycaught,
notestablishedrootcause. No retry/duplicateentry/agentUI/sync/build/install.
NEXTlocal ACK/projection reproduction preserving sameexpense/signatures; no PASS
repeats. Evidence mobile-garden-update-20261025/android/finance-expense-failure-review.json.

Dnevnik potrdi mesto ustavitve pri primerjavi podpisane zahteve z lokalno preverjeno projekcijo. Ne razkrije, kateri pogoj manjka (zapis, scope/domain/id, revision, proof hash, type ali deleted); to zahteva lokalno reprodukcijo. Ne sklepamo, da gre za omrežje, izgubo podatkov ali že dokazano isti vzrok kot pri vrtu. Na telefonu ne ponavljamo shranjevanja ali ročne sinhronizacije.


### 25. oktober — lokalni popravek potrjevanja stroška z računom nadrejenega prostora

Napako smo ponovili z veljavnim podpisanim stroškom in dokazilom za račun nadrejenega prostora. Izhodna validacija je uspela, vhodna projekcija pa je pri najnovejšem dokazilu različice 1 začela zgodovino pri predhodniku 0. `CryptoProjectionPending` je pustil strošek neprojiciran, zaključno preverjanje pa je sporočilo `crypto_business_ack_projection_pending`. To je potrjena lokalna napaka, skladna z mobilnim simptomom; mobilni dnevnik notranjega razloga in številk različic ni zajel.

Popravek v `crypto_finance_account_choices.dart` najprej obdela posebej avtenticirano trenutno dokazilo in šele nato predhodnike. Podpisna, identitetna in finančna preverjanja ter izvirne zahteve ostanejo.

Štiri nove lokalne kontrole uspešne: trenutna različica + projekcija/ACK; zavrnitev napačnega hasha; starejše dokazilo prek prave podpisane verige; nadaljevanje iste že potrjene podpisane zahteve po prihodu manjkajočega dokazila, z nespremenjenimi bajti/hashom in natanko enim stroškom, brez novega batch klica. Test uporablja pravi SQLite, podpisovanje, šifriranje, zgodovinsko verigo, pull, projekcijo in zaključevanje; zaupanje imeniku in glavam prostora ter transport sta sintetična. Ne gre za nov celovit HTTP ali mobilni test.

Vsi poskusi in meje so v `build/qa/finance-parent-ack-fix-20261025/local-results.json`, dnevniki ob njem. Neodvisni in glavni pregled uspešna, končna ozka statična analiza brez ugotovitev. Uspešni testi se niso ponavljali.

Samsung ni posodobljen; isti strošek TEST-FINANCE-25 ostaja. Naslednje: posodobitev iste Jivie Test z ohranjenimi podatki, nato uporabnik nadaljuje obstoječo sinhronizacijo brez ponovnega vnosa ali shranjevanja. Telefoni, produkcija in strežnik v tem koraku nespremenjeni.

Ločena odprta ugotovitev iz pregleda izvora: `crypto_business_project_relocation.dart::_historicalLinks` preda trenutni zapis verigi, ki pričakuje predhodnika. To je druga pot (premikanje projekta), brez nove reprodukcije in brez popravka v tem koraku. Razlika pri zgodovinskem preverjanju deviceSnapshot upravljavca je le kandidat za ločen pregled, ne potrjen vzrok tega mobilnega primera.


### 25. oktober — Samsung r4: namestitev finančnega popravka in nova diagnostika

25. oktober — **Samsung QA r4 financefix nameščen; čaka user nadaljevanje istega stroška**.
User izrecno sameQAupdate/preservedata/diag. Sol6.1/highbuild+independentdiag
review,rootinstall.1build1install-r APK6a6a2f9a…46685,106374901B; istiQApackage
/sign/UID10292/dataDir/native.so/TLS/Keystore namespace.631frozen/23dirtyproduct/
28QAoverlays, testedchoicesef06852f…c0636exact;analysis0error0warning46styleinfos.
Newdiag3innerprojectioncatches;1newobserverPASS/parser4accept2reject; failures
finitecodes+8sourceframes, no rawpayload/keys/URLs. Namespace
jivie_qa_mobile_finance_20261025_v5/tagandroid-finance-fix-20261025-r4.
Rootcoldbackup20noncachefiles122420834B; entireprofile+vault exactbyteparity.
OriginalPlayAPKhash/meta unchanged, iPhone/backend/prod0actions. QAforce-stopped
fromFinanceoverview(noeditor),0launch/UI/sync, freshdiagnosticdirabsent; QA CLOSED.
644regeneratedcachefiles1316103928B removed; source/APK/backups/keysheld.
Evidence/reader build/qa/mobile-finance-update-20261025/android/read_diagnostics.py;
root-final-verification.json/profile-preservation-evidence.json. NativefixNOTYETPASS.
NEXTuser openJivieTest wait20s→MOBILE-PROJECT-1Finance→cloudonly, noSave/no
newexpense/noUskladi; continue existingTEST-FINANCE-25. Inspectfreshdiag before
requesting manual action. Do notrepeat oldPASS.

Namestitev je pripravljena za uporabnikov prvi zagon. Dejanski uspeh nadaljevanja finančne sinhronizacije še ni preverjen. Ponovni vnos TEST-FINANCE-25 ni potreben.


### 25. oktober — finančna sinhronizacija po r4 uspešna; izmerjena počasnost

25. oktober — **Samsung r4 finančni continuation native PASS; hitrost odprta**.
User odpre/wait/noSave/noManual; root screenFinancegreen/expense12.34EUR,
no bubblevisible. Completion11:17:09.250UTC none/unresolvedfalse/retryfalse;
0finance/innerprojectionfailure,0records.batch; retainedreceiptreads8.
Knownpolicyexisting_scope_upgrade_pending caughtdefer ni terminalnapaka.
SelectedWork→completion13178ms,firstrecorded→completion15362ms;
238HTTP200 skozi completion,287celcapture21s inclstartup/nav; ne oneexpensebenchmark.
User>10s potrjeno, performance OPEN; neopravičuj vsega kotnujnaenkripcija.
Nobennovvnos/noagentUI/sync; no peer/balance/exactplaintextbinding read.
Evidence mobile-finance-update-20261025/android/finance-native-resume-result.json.
NeponavljajPASS. NEXTreadonlyparentaccountracunqa25 pregled istegastroška/salda.

Uspeh prenosa in odzivnost sta ločeni ugotovitvi. Zaključek je uspešen, a trajanje ostaja odprto za ciljano analizo iz že zajetega dnevnika; uspešnega uporabniškega testa ne ponavljamo. Zeleni oblaček in zaključen cikel ne nadomeščata ločenega pregleda salda nadrejenega računa.


### 25. oktober — pregled računa in prometa prek Samsung UI

25. oktober — **Samsung navigacija dovoljena; parent strošek viden, saldo OPEN**.
User izrecno dovoli rootpotipke za pregled. ADBinput deluje: Cancelaccounteditor
(noSave),Closeaccounts,selector,parentMobileE2EE20261018,2scroll;6UIactions,
0save/delete/manualsync. AccounteditoropeningBalance1000EUR. ParentFinance
warning »Pregled projektnih financ še ni popoln… po uskladitvi vseh dovoljenih
projektov«, greencloud; racunqa25 showscurrencyonly, saldo hidden. Allfilters,
1visibleexpense actualtitle »test fin 25«(usertestlabelTEST-FINANCE-25),12.34EUR,
Knjiženo,MOBILE-PROJECT-1,racunqa25,MobileASynthetic; totalexpense12.34.
GUIparentexpensePASS, noSQLidentity/dedupe/peerproof; BALANCE NOTPASS. Newdiag
61HTTP200(inclbackground),0newfailure/0completion,30sprobesunchanged; warning
rootcauseNOTdiagnosed. No retry tests/sync/build/server/prod. Sameexpenseheld.
Evidence mobile-finance-update-20261025/android/parent-finance-read-review.json.
NEXTtargetparentaggregatecompleteness, no expense reentry/repeatPASS.

Uporabnikova pripomba je upravičena: pot prek Računi prostora vodi na seznam z urejanjem, ne na promet/saldo. Za pregled smo morali zamenjati izbrani prostor na nadrejeno organizacijo. To ni bila napaka uporabnika. Prenos stroška ostaja uspešen; prikaz celotnega salda je ločena odprta kontrola.

### 25. oktober — lokalni popravek popolnosti pregleda in neposreden pregled računa

Uporabnik naroči popravek nepopolnega pregleda/skritega salda in preprostejši dostop do računa. Potrdi, da račun pripada nadrejenemu prostoru. GPT 6.1 Sol/high podagenta izvedeta podatkovni in UI del, tretji neodvisno pregleda spremembe; glavni agent pregleda izvor in dokaze. Obstoječi podatki, telefoni in strežnik niso nadgrajeni v tem koraku; produkcija ostane nedotaknjena.

**Lokalno potrjen vzrok:** selektivna sinhronizacija izbere spremenjeni projekt in nadrejeni prostor, ne pa še nepripravljenega drugega projekta. Celotni saldo zato ostane pravilno skrit. Druga reprodukcija potrdi, da pri že potrjenem strežniškem kazalcu naslednje preverjanje »ni sprememb« preskoči tudi ta lokalni manjkajoči podatek. To sta reprodukciji s pravim SQLite, koordinatorjem, materializacijo in izračunom; transport in meja avtoritete sta sintetična. Nista dokaz točnega notranjega vzroka na Samsungu.

Popravek dopolni samo manjkajoče, zaostale ali še nepotrjene odvisne projektne finance in povezane podatke plačil. Projekte obdela pred skupnim pregledom. Pridobivanje ostane pod običajnimi preverjanji dovoljenj, podpisov in popolnosti. Isti koordinator lahko zazna tudi obstoječe lokalno nepopolno stanje brez novega shranjevanja stroška. Isti nespremenjeni razlog poskusi samodejno enkrat na življenjsko dobo seje; ne uvaja ponavljanja celotne sinhronizacije vsakih 30 sekund. Izrecni »Uskladi zdaj« omogoča ponoven poskus. Samo neznana podpisana topologija oziroma lažna zastavica skupne popolnosti ne sproži take obnove in ne odklene salda.

Podatkovni del: 14 različnih novih kontrol PASS in ena ločena karakterizacija celotne začetne sinhronizacije. Dva namerna reprodukcijska FAIL in štiri napake priprave testa so ohranjeni v dnevniku; ponovljeni so samo neuspešni primeri, največ dva izvajanja oziroma ena napaka na primer. Preverjeni so pravilen saldo v sintetičnem primeru (1000 − 12,34 = 987,66), ohranitev enega obstoječega stroška brez novega pošiljanja, omejitev pridobivanja na ustrezne projekte, neposeganje v zavrnjene/izbrisane/druge prostore, mirujoča ponovna preverjanja in izrecni ročni ponovni poskus. Dokazi: `build/qa/parent-finance-fix-20261025/data-local-results.json` in pripadajoči dnevniki.

**Navigacija:** Finance projekta → Računi prostora → Pregled računa. Urejanje ostane ločen gumb. Pregled uporabi obstoječi finančni prikaz, izbere ta račun ter skrije spreminjanje finančnih zapisov. Preverja trenutno sejo, dostop in obstoj računa; član s pravico zgolj do projekta ne pridobi pregleda celotnega nadrejenega računa. Pet različnih novih UI kontrol PASS, ozka analiza brez ugotovitev. Kontrola prehoda iz popolnega v nepopoln pregled potrdi, da že prikazani saldo izgine, strošek in opozorilo pa ostaneta. Dokazi: `build/qa/finance-account-overview-20261025/local-results.json`.

**Meja mobilnega dokaza:** trije omejeni poskusi branja stanja prek Dart VM so se končali s transportnim timeoutom; nobeno stanje ni bilo prebrano, ni četrtega poskusa. Samsung ni posodobljen in saldo tam še ni potrjen. Naslednji mobilni korak po posodobitvi ostane pregled istega računa in istega stroška, brez novega vnosa, shranjevanja ali ponovitve uspešnega prenosa. Trajanje prejšnjega uspešnega synca ostaja ločena odprta ugotovitev.

**Dodatna povezana napaka popolnosti:** prejemnik `finance3.payments` je ignoriral izrecni `complete=false` iz šifrirane projekcije in lahko z nepopolnim odgovorom nadomestil denarne premike ter zapisal potrdilo svežine. Lokalna reprodukcija to potrdi. Popravek ohrani obstoječe dogodke, projekcije, denarne premike in čakajoče namere; ob izrecno nepopolnem odgovoru odstrani samo potrdilo svežine, po potrjeni transakciji obvesti prikaz in vrne stanje čakanja. Ohrani tudi zaporedno številko opaženega nepopolnega odgovora, vezano na generacijo dostopa: poznejši starejši odgovor ne more ponovno potrditi napačnega salda. Popoln odgovor iste ali novejše številke lahko nadaljuje običajno obdelavo. Stari strežniki brez neobveznega polja ohranijo obstoječo pogodbo.

Osem različnih novih kontrol prejemnika PASS, vključno z ohranitvijo podatkov, zavrnitvijo zastarelega odgovora/spremenjenega dostopa, obvestilom po transakciji in nadaljevanjem ob popolnem odgovoru. Ohranjena sta dva namerna reprodukcijska FAIL ter začetna napaka priprave testa; noben uspešen primer ni ponovljen, največ dve napaki na primer. Ozka analiza brez ugotovitev. Dokazi: `build/qa/finance-linked-payment-completeness-20261025/local-results.json`. To je dodatna lokalno potrjena napaka, ne dokaz, da je povzročila konkretno Samsungovo opozorilo.

Skupaj 27 različnih novih namenskih kontrol popravkov PASS ter ena ločena začetna karakterizacija. Podatkovna analiza nima napak/opozoril, vsebuje deset že obstoječih slogovnih informacij. UI in prejemnik plačil nimata analitičnih ugotovitev. Brez gradnje, namestitve, strežniških sprememb ali ponovitve uspešnih mobilnih testov.

### 25. oktober — Samsung r5: namestitev in omejeni mobilni pregled

Uporabnik naroči posodobitev iste Jivie Test, samostojen preizkus in opazovanje hitrosti. Telefon je odklenjen; čas izklopa je že 600.000 ms, ostane 10 minut, izveden je dotik praznega dela začetnega zaslona. GPT 6.1 Sol/high pripravi en paket iz aktualnega izvora v obstoječem QA delovnem imeniku; glavni agent pregleda izvor, paket, nato namesti in upravlja samo Jivie Test. Brez novega vnosa, shranjevanja ali ročne sinhronizacije.

Namestitev: en build (18,4 s), en `install -r`, paket SHA256 `96127c74040923b557d74145c6729d747524500ef0d66175fdab5ab7002fb13e`, 106.382.989 bajtov. Isti package/signature/UID 10292/dataDir/native knjižnice/TLS/Keystore namespace. Pred namestitvijo hladna varnostna kopija; vseh 20 nepredpomnjenih datotek, skupaj 122.529.482 bajtov, po namestitvi vsebinsko enakih. Originalna Google Play aplikacija ima isti APK in metapodatke. iPhone, backend in produkcija niso spreminjani. Po namestitvi odstranjenih 1.316.208.313 bajtov obnovljivih datotek gradnje; paket, izvor, kopije in ključi ostanejo.

**Novo potrjeno:** Finance projekta → Računi prostora → Pregled računa deluje na Samsungu. Račun `racun qa25` je izbran, prikaz je samo za branje, urejanje je ločeno. Viden je obstoječi `test fin 25`, 12,34 EUR, v MOBILE-PROJECT-1. Agent je sprva izbral nepotrebno pot skozi meni projekta in se vrnil; to je navigacijski ovinek pri testiranju, ne nov poslovni poskus. Uspešnih prenosov ali shranjevanj ni ponavljal.

**Neuspešna kontrola:** skupni pregled še vedno kaže opozorilo o nepopolnosti in skriva saldo. Lokalni popravek manjkajočega drugega projekta ni odpravil konkretnega mobilnega stanja. Ne označujemo celotnega finančnega popravka kot mobilni PASS.

**Zajeto dejansko stanje:** nova r5 seja omogoči branje VM prek HTTP. Prvi omejeni poskus se ustavi pri velikosti seznama razredov (2 MiB), drugi poveča samo to mejo na 16 MiB in uspe s 36 bralnimi klici. Brez eval/invoke, SQL, vsebin finančnih zapisov ali ključev. Stari r4 STOP3 ostane nespremenjen, noben nadaljnji poskus ni izveden. Vsi trije prostori imajo `financeSnapshotComplete=true`, zaporedja 1/4/2, veljaven dostop in pravico pisanja. Nadrejeni prostor pa ima `organizationFinanceComplete=false`, prazen seznam zahtevanih prispevkov ter prazna zahtevana zaporedja. Prikaz ima `cashAvailable=false`. S tem je potrjen konkretni pogoj skritega salda; še ni ugotovljeno, katero preverjanje podpisane skupne pokritosti je vrnilo nepopolnost. Naslednja lokalna diagnoza mora izhajati iz tega stanja, ne ponavljati shranjevanja ali slepo graditi novega paketa.

**Hitrost:** Androidovo merilo prikaza aktivnosti ob hladnem zagonu je 1.125 ms (ni čas dokončane sinhronizacije). Novi pregled je viden na prvem posnetku približno 1,13 s po dotiku; meritev vključuje namerno čakanje 800 ms in zajem slike, zato ni natančna meritev prve sličice. V dnevniku od 11:51:56 do 11:56:59 UTC je 65 HTTP odgovorov, vsi 200, brez zajetih napak in brez novega batch zapisovanja. Deset preverjanj vrne »ni sprememb«; devet po zagonu traja 66–331 ms, mediana 108 ms, na približno 30 sekund. Polna sinhronizacija se ni sprožila. Ti časi niso primerljivi s prejšnjimi 13,178 s prenosa čakajočega finančnega zapisa.

Dokazi: `build/qa/mobile-parent-finance-update-20261025/android/native-test-result.json`, `native-gate-r5-http-state2.json`, `profile-preservation-evidence.json`, `installation-evidence.json` in zasloni v istem imeniku. Sveža diagnostika uporablja `jivie_qa_mobile_parent_finance_20261025_v6`; bralnik je `read_diagnostics.py`. Telefon ostane v novem pregledu istega računa. Commit/push ni izveden.


### 25. oktober — skriti saldo: natančen vzrok in lokalni popravek

Uporabnik je naročil nadaljevanje izboljšave salda po uspešnem prenosu istega stroška. Na isti Samsung Jivie Test r5 je običajni pregled zgodovine računa ponovno preveril finančno politiko; skupna pokritost je ostala nepopolna kljub trem popolnim lokalnim finančnim posnetkom. Prazen seznam zahtevanih projektov je skupni rezultat zavrnitve, ne dokaz praznega podpisanega seznama projektov.

Omejeni debugger je najprej potrdil prestreženi `CryptoAuthorityPending` v `organizationFinanceCoverage`. Zajem izvorne izjeme je nato pokazal `directory_proof_pending`: `directoryAt → _verifyHead → _currentHead → verifiedScopeDescriptor → organizationFinanceCoverage`, pri branju opisa podprojekta. Ta klic je uporabljal privzeti `online:false` pred poznejšim spletnim preverjanjem glave. Manjkajoča dokazila zato niso mogla priti do običajnega preverjevalnika. Popravek dovoljuje njihov prenos na tej točki z `online:true`; podpisi, identiteta, podpisana povezava s staršem, seznam projektov, finančne pravice, popolnost posnetkov in končna preverjanja ostanejo.

Ločeno je lokalni vzročni test potrdil obstanek starega `organizationFinanceComplete=false` pri nespremenjenem strežniškem kazalcu. Isti koordinator zdaj enkrat na nespremenjeno stanje predpogojev preveri pokritost starša. Neuspešno preverjanje ostane nepopolno in ne sproži ponavljajočih zahtevkov vsakih 30 sekund. Sprememba prijave ali podatkov omogoči novo preverjanje. Lokalni podatki nikoli sami ne potrdijo pravilnega salda.

Validacija: 6 novih kontrol nadaljevanja in 5 novih kontrol preverjanja podprojekta PASS; dve namerni začetni odpovedi dokazujeta napaki. Dve napaki testnega ogrodja sta odpravljeni; že uspešnih testov nismo ponavljali. Preverjevalniki identitete in transport so v lokalnih testih sintetični; dejanski Samsungov sklad klicev posebej povezuje popravek z opaženo napako. Neodvisni izvorni pregled obeh popravkov PASS. Novega mobilnega prikaza salda ta lokalni izid še ne potrjuje.

Diagnostika: prvi zajem vrnitve uspešen; drugi zaradi neimenovanega `catch` ni razkril razloga; tretji zajem izjeme se je ustavil pri omejitvi 10 postankov (večkratna propagacija iste izjeme), vendar je zajel navedeni izvor in pot podprojekta. Prvi debugger je po odstranitvi prelomnih točk ostal ustavljen; namensko čiščenje je takoj potrdilo nadaljevanje. Končno stanje vseh zajemov: aplikacija teče, način prestrezanja izjem `None`, nič prelomnih točk, lastne povezave odstranjene. Nobenih poslovnih sprememb, novih stroškov ali ročne sinhronizacije. Običajna branja lahko objavijo preverjene kontrolne točke in opažanja.

Dokazi: `build/qa/parent-finance-coverage-continuation-20261025/`, `build/qa/parent-finance-child-authority-20261025/`, ter `coverage-history-review.json` v r5 Android dokazih. Naslednja je ena posodobitev iste testne aplikacije in pregled istega računa, brez novih vnosov. Produkcija, originalna aplikacija in iPhone ostajajo nedotaknjeni.


#### Končni mobilni rezultat istega računa — r6 PASS

Ista Jivie Test na Samsungu je posodobljena (en build, ena namestitev z ohranjenimi podatki, en zagon). Pregled računa `racun qa25` zdaj pokaže **987,66 EUR**, skladno z začetnimi 1.000,00 EUR in obstoječim odhodkom 12,34 EUR. Opozorila o nepopolnem pregledu ni več. Pregled je ostal samo za branje, račun je izbran. Ni novega stroška, shranjevanja ali ročne sinhronizacije.

Samodejno popravilo finančne pokritosti: od izbire dela do uspešnega zaključka **8.181 ms**; od začetka diagnostike 10.387 ms. Naslednje preverjanje nespremenjenega stanja traja **258 ms**, brez ponovne celotne uskladitve. V zajemu 206 odgovorov HTTP 200. Ena že znana interno odložena priprava stare politike zapisov (`crypto_record_policy_existing_scope_upgrade_pending`) je zabeležena; končni cikel je `code=none`, `unresolved=false`, `retry=false`. To ni meritev novega prenosa stroška ali dokaz takojšnje sinhronizacije na iPhonu.

Vseh 20 datotek nepredpomnjenega profila (122.598.218 B) je čez namestitev bajtno enakih. Originalna Play aplikacija je nespremenjena. APK r6 ima SHA256 `50423761df1bd96718a5a6fcbb872e1645f7087e2fa25331fc7c71af8b2c1d57`. Preverjanje pred namestitvijo je najprej ustavila pričakovana razlika diagnostičnega dodatka; po izrecnem pregledu diff je sledila ena dejanska namestitev, ne slepo ponavljanje. Odstranjenih je 614 obnovljivih datotek gradnje (1.299.708.851 B); viri, paket, dokazila, ključi in varnostne kopije ostanejo.

Dokaz prikaza: `build/qa/mobile-balance-visibility-20261025/android/overview.png`. Povzetek: `native-test-result.json` v isti mapi. Telefon je ostal na tem pregledu računa. Produkcija, strežniška koda in iPhone niso bili spremenjeni. Ta test je zaključen in se ga ne ponavlja.


### 25. oktober — priprava iPhona za isti strošek in saldo

Ista aplikacija `si.triparna.jivie.e2eetest.ios20261018` je posodobljena na trenutno kodo, vključno z obema preverjenima popravkoma salda. GPT 6.1 Sol/high je pripravil en iOS archive (70,095 s), root je pregledal izvorne hashe, podpis in identiteto ter izvedel eno namestitev. Podpisni profil, certifikat, Keychain service/group in testni CA ostajajo enaki. Analiza nima napak ali opozoril; 46 obstoječih slogovnih informacij ostane. Testov nismo ponavljali.

Pred namestitvijo je bil normalno zaprt samo točen proces Jivie Test. Sveža zasebna kopija ima štiri datoteke šifrirane shrambe, skupaj 7.328.134 B; po namestitvi so vse štiri bajtno enake. Aplikacija ostane zaprta, brez zagona, UI dejanj, shranjevanja ali ročnega synca. iOS je zamenjal pot vsebnika, identiteta in vsebina sta ohranjeni. Samsung, produkcija in strežnik niso bili spreminjani.

IPA SHA256: `41938d59f38ab8d4ec3d361486f45a2c5f5e1cd410dbe59f67aa044cf0adc428`. Sveži diagnostični prostor je `jivie_qa_ios_balance_visibility_20261025_v1`, oznaka `ios-balance-visibility-20261025-r1`; beleži omejene kode, čase in števce brez vsebin zapisov ali ključev. Mapa še ne obstaja, ker nova aplikacija ni bila zagnana. Branje po uporabnikovem testu: `python3 build/qa/mobile-balance-visibility-20261025/ios/read_diagnostics.py --after-user-test`. Bralnika še nismo izvajali.

Odstranjeni so samo trije obnovljivi imeniki te gradnje (1.190.178.816 B); archive, IPA, simboli, izvor, dokazila in kopije ostanejo. Dokazi: `build/qa/mobile-balance-visibility-20261025/ios/final-bounded-summary.json`.

Naslednje opravi uporabnik: odpre isto Jivie Test, po potrebi zapre znano opozorilo z »Nadaljuj v lokalne podatke«, počaka 20 sekund, nato pregleda obstoječi strošek 12,34 EUR v MOBILE-PROJECT-1 → Finance. Prek Računi prostora → Pregled računa preveri pričakovani saldo 987,66 EUR. Brez ponovnega vnosa ali Uskladi zdaj. iOS prenos in prikaz salda sta do tega pregleda še nepreverjena.


### 25. oktober — iPhone: isti strošek in saldo PASS, upravlja agent

Uporabnik izrecno prepusti upravljanje iPhona agentu. Device Hub dejansko sprejema dotike; neposredni posnetek po dotiku včasih še kaže staro sličico, zato iz tega ne merimo hitrosti aplikacije. En zagon iste Jivie Test, en »Nadaljuj v lokalne podatke«, nato Finance istega MOBILE-PROJECT-1. Brez dodatne gradnje/namestitve, novega vnosa, shranjevanja ali ročnega Uskladi zdaj. Samsung, produkcija in konfiguracija strežnika ostanejo nedotaknjeni.

**Native PASS:** viden je obstoječi `test fin 25`, 12,34 EUR, račun `racun qa25`. Finance → Računi prostora → Pregled računa odpre prikaz samo za branje z izbranim računom in **987,66 EUR**. Opozorila o nepopolnem pregledu ni; projektni oblaček je zelen. Telefon ostane na tem pregledu. To zaključi isti test prikaza na drugem telefonu; ne ponavljamo Samsungovega PASS ali vnosa stroška.

**Časi in dnevnik:** dva samodejna zaključka imata `code=none`, `unresolved=false`, `retry=false`. Prvi finančni sklop od selectedWork do completion traja 13.338 ms (14.023 ms od začetka diagnostike), drugi 10.554 ms. Za drugim sledijo samo preverjanja »ni sprememb« na približno 30 sekund, 61–148 ms. Zajetih 563 HTTP odgovorov, vsi 200; to ni dokaz optimalnega števila zahtevkov ali meritev prenosa novega stroška. Dva začetna finančna sklopa in njihov obseg ostaneta zabeležena za morebitno nadaljnjo optimizacijo, brez ponovnih testov v tem koraku.

Prestreženi sta 2× `directory_proof_pending` v finance projection (`session_crypto_access.dart:1435` → `crypto_finance_account_choices.dart:1080/1347/2271`) ter 5× `crypto_record_policy_owner_pending` v baseline politike. To so zajeta vmesna stanja; poznejša zaključka in dejanski saldo sta uspešna. Ne enačimo prve poti s prej popravljeno child coverage potjo in ne trdimo, da dnevnik nima nobenega opozorila. Znano začetno opozorilo obnove ter neblokirajoča pasica »Povezani prostori so se spremenili« ostaneta ločeni odprti UX ugotovitvi; nove potrditve zaščite nismo sprožili.

Dokazi: `build/qa/mobile-balance-visibility-20261025/ios/native-test-result.json`, `expense-visible.png`, `overview.png` in zadnji `diagnostic-read-20261025T124619386091Z.json`. Bralnik je samo bral metapodatke; ni sprožil synca. Izvorna koda ni spremenjena, novih testov/commit/push ni.


### 25. oktober — začetna opozorila in finančni prvi prehod, ciljni lokalni popravki

Uporabnik omeji obseg na začetna opozorila, začetno sinhronizacijo in jasen »Dodaj dogodek«. Vrt je izrecno prestavljen v poznejšo fazo (`POST_RELEASE_IMPROVEMENTS.md`); koledar in širša navigacija čakata. Trije GPT 6.1 Sol/high podagenti pripravijo analizo/popravke in nove ozke kontrole, root pregleda spremembe, dodatno je opravljen vzajemni neodvisni pregled.

**Opozorila:** pri iOS gre za dokumentirano ohranjeno QA diagnostično mapo, ne okvaro šifrirane baze. Novi `retainedCopiesOnly` nastane samo po preverjenem ključu/probe/bazi, dokončanem journalu, končanem picker pregledu, brez starih znanih baz ali občutljivih nezaščitenih nastavitev in s pozitivnim številom neuvrščenih ohranjenih datotek. Takšna namestitev odpre aplikacijo brez ponavljajočega ročnega Continue; kratko opozorilo Kopije/Copies in dostopno pojasnilo o nepotrjeni zaščiti teh kopij ostaneta. Nobena mapa ni izključena iz pregleda ali izbrisana. Dejanska obnova, nedokončana migracija in napake zagona obdržijo varovala.

Dokazana ločena napaka: uspešen `finishAccountProtection` sproži dogodek osvežitve povzetkov, začetna ocena pa ga prej ni poslušala. Zdaj se ista ocena za točen račun/napravo osveži enkrat; vrnitev iz pregleda po uspehu ne sproži podvojenega branja. Veljavni ali še nerazloženi premik podpisanega kataloga ostane neblokirajoče obvestilo. Točne razlike prejšnjega mobilnega kataloga nismo zajeli in jih ne razglasimo za nepomembne. Podpisana potrditev pripravljenosti se ne preskakuje.

**Sinhronizacija:** obstoječi iOS dnevnik ima 256 HTTP v prvem in 301 v drugem finančnem sklopu; slednji se začne 30 sekund po zaključku in ga izbere lokalna potreba po pokritosti starša, ne podvojeni zahtevek v vrsti. Nato je šest preverjanj, vsako z enim `account.changes`. Ni dokazano, da je vseh 301 zahtev odveč. Konkretna reprodukcija pokaže manjkajoče dovoljenje običajnega prenosa imenika pri preverjanju trenutnega finančnega korenskega dokazila: `_verifyManager` vrne `directory_proof_pending`, poznejši accountChoices pa isto dokazilo lahko pridobi. Aktualni finance pull zdaj omogoči ta običajni preverjeni prenos samo za trenutno korensko dokazilo; natančni head/epoch/accessRevision, omejeni konteksti, zgodovina, podpisi in poslovna pravila ostanejo preverjeni. Koordinatorja ali naslednjih potrebnih preverjanj ne ugašamo.

**Dodaj dogodek:** trenutna koda že uporablja vidno prevedeno besedilo v Utripu in časovnici; dodatna produktna sprememba ni potrebna. Štiri nove kontrole SL/EN pri širini 320 px in 2× besedilu preverijo čitljivost, semantiko, najmanjšo višino in enkraten klic dejanja. Gumb ostane skrit, če prostor nima pravice dodajanja. Trenutni S25 prikaz gospodinjstva gosp 25 ga ni kazal; sama slika ne dokazuje manjkajočega callbacka ali napačne gradnje, ker je v deljenem pregledu odvisen od readOnly stanja. Pravice niso bile spremenjene.

**Lokalni rezultat:** 8 novih kontrol opozoril, 7 finančnih in 4 prikaza PASS; nič analitičnih napak/opozoril, obstoječe slogovne informacije ostanejo. Finančni test uporablja dejanski SQLite/Sodium/podpisane zapise in natančno projekcijo, vendar sintetično razreševanje imenika. Predhodni namerni FAIL dokaže finančni vzrok; napake ogrodij so ohranjene. Stari PASS niso ponovljeni; ena nova že uspešna offline kontrola je bila pomotoma vključena v drugi finančni filter in je označena, ne šteta dvakrat. Največ trije poskusi na primer. Nove mobilne meritve in namestitve sledijo ločeno; lokalni rezultat ne dokazuje zmanjšanja mobilnega števila zahtevkov.

Dokazi: `build/qa/startup-warning-cleanup-20261025/`, `build/qa/startup-sync-duplicate-20261025/`, `build/qa/add-event-label-20261025/`. Namestitveni korak uporablja `build/qa/startup-polish-20261025/`, iste QA identitete, brez kopiranja celotnih delovnih imenikov. Produkcija in strežniška koda nista spremenjeni.


#### Ciljna mobilna posodobitev istega okolja — oba zagona PASS

Isti QA aplikaciji sta posodobljeni, vsaka z eno gradnjo in eno namestitvijo. Android APK `fcae2b478b1956d9c49c7c490e4cf5e6645272224e348327bd01c07232d83ee0` (106.379.993 B), iOS IPA `5330bda76d095620209c69262889e67344e002c9f6a9495f1812108715ada972` (16.856.101 B). Iste identitete/podpisi/Keychain oziroma Keystore/CA in izvorne kriptografske knjižnice. Android vseh 20 nepredpomnjenih datotek (122.809.748 B) ter iOS vse štiri vault datoteke (7.664.006 B) čez namestitev bajtno enake. Originalni Play APK in metapodatki ter originalni iOS metapodatki ostanejo isti; strežnik in produkcija brez posegov.

Root upravlja samo testni aplikaciji prek CUA. Samsung odpre prvotni gosp 25 neposredno, ocena zaščite current/none. Za preverjanje gumba izbere Osebno, vidi »Dodaj dogodek«, odpre pravilni prazni obrazec in ga prekliče brez vnosa/shranjevanja; nato vrne gosp 25. V tem gospodinjstvu gumb ni bil viden že pred posodobitvijo; iz slike ni potrjen razlog readOnly stanja, pravice ostanejo nespremenjene. iPhone po enem zagonu odpre MOBILE-PROJECT-1/Utrip brez »Obnove celotne namestitve« in brez Continue; viden je imenovan gumb za dogodek. Kratko opozorilo o kopijah ostane. Neobvezen catalogChanged pregled ostane viden in ni samodejno potrjen.

Dnevniki po novem zagonu: Android 14 HTTP odgovorov, vsi 200, osem unchanged preverjanj 245/107/83/108/71/124/74/80 ms; iOS 8 odgovorov, vsi 200, dve unchanged preverjanji 62/79 ms. Ni zajetih failure dogodkov niti polnega finančnega cikla. Ker imata računa že pripravljene dokaze in ni novih sprememb, to NE dokazuje prihranka 301 zahtev ali hitrejšega hladnega finančnega prenosa; vzročni finančni popravek je dokazan lokalno, mobilna hladna reprodukcija ni ponovljena. Ni novega stroška, ročnega synca, vrta, povabila ali starih uspešnih prenosov.

Priprava iOS se je prvič ustavila pri dvoumnem kontekstu starega pbxproj diagnostičnega popravka, pred kakršnimkoli zapisom QA izvora. Obratni popravek zdaj uporabi natančne vrstice in preveri vsebino; drugi poskus priprave uspe. Gradnja in namestitev sta bili vsaka samo eni. Prvi root klic Android bralnika je imel iOS-ov argument --after-user-test in se je ustavil v parserju brez dostopa do naprave; pravilen klic brez argumenta je uspel. Ti pripravljalni napaki nista napaki aplikacije in ne pomenita ponovitve mobilnih testov.

Odstranjenih 1.299.724.940 B Android in 1.190.072.320 B iOS izključno obnovljivih datotek gradnje; paketi, archive/dSYMs, izvor, ključi, varnostne kopije in dokazi ostanejo. Končni dokazi: `build/qa/startup-polish-20261025/android/native-targeted-result.json`, `ios/native-targeted-result.json`, slike ter manifesti/potrdila o ohranitvi podatkov. Uporabnik lahko nadaljuje svoj pregled na obeh telefonih. Vrt/koledar nista predmet tega sklopa; commit/push ni naročen ali izveden.


### 25. oktober — uporabnikov samostojni preizkus: počasne finance in iskanje prejemnikov

Izrecno naročilo: samo zapisovanje, brez sprememb kode, diagnostike na napravah/strežniku, novih testov ali namestitev. Uporabnik testira odklopljen od računalnika; to ne pomeni odsotnosti omrežja.

1. **Finance — uspešno, vendar še vedno počasno.** Uporabnik poroča, da se finančne spremembe uspešno sinhronizirajo, vendar »traja in traja«. Točen čas, vrsta spremembe in vzrok še niso izmerjeni. Odprta težava odzivnosti ostaja; prejšnja hitra preverjanja brez sprememb niso dokaz hitrosti dejanskega finančnega prenosa. Poznejša diagnoza naj uporabi dnevnike tega preizkusa in loči čakanje do zagona, prenos/preverjanje ter osvežitev prikaza; ne zahtevamo ponovnega vnosa že uspešno prenesenih zapisov.

2. **Naslednja nadgradnja deljenja — iskanje obstoječih uporabnikov istega strežnika.** Uporabnik želi prejemnika poiskati in izbrati, ne poznati njegovega celotnega uporabniškega imena na pamet. Obseg so uporabniki, znani strežniku, ne samo že obstoječi sodelavci pošiljatelja. Predlagan preprost potek: Deli → poišči uporabnika po delu prikaznega/uporabniškega imena → izberi nedvoumno označen račun → pošlji običajno povabilo. Prejemnik še vedno izrecno odloči o sprejemu; rezultat iskanja sam ne podeli dostopa ali ključev. Iskanje naj bo za prijavljene uporabnike istega strežnika in naj razkrije samo identifikacijo, potrebno za pravilno izbiro, ne vsebin prostorov. Iskanje/prikaz e-pošte in točna pravila imenika še niso dogovorjena. To je tehnično izvedljiva smer, ne trditev, da obstoječi backend že ponuja ustrezen iskalni endpoint. Termin glede javne objave ni določen; ne prestavljamo samodejno na seznam po objavi.

Status: obe točki zapisani za nadaljnjo obravnavo. Izvedba trenutno ni naročena; uporabnik nadaljuje preizkušanje.


### 25. oktober — kritična uporabniška ugotovitev: izguba dostopa po urejanju preglednice

Uporabnik med samostojnim preizkusom poroča naslednje zaporedje v skupnem prostoru: (1) ustvari preglednico, (2) jo shrani, (3) jo uredi, (4) ponovno shrani, (5) aplikacija izgubi dostop z obrazložitvijo »dostop preklican«. Nato je deljeni projekt še viden, celotni prostor pa ne več. To je uporabniško poročilo, ne še pregled dnevnikov. Točna naprava, prostor, preglednica in čas dogodka še niso potrjeni v tem poročilu; predhodni kontekst je samostojni mobilni preizkus brez povezave z računalnikom, ne dokaz odsotnosti omrežja.

Prioriteta: visoka, pred nadaljnjo presojo pripravljenosti izdaje. Ni dokazano dejansko administrativno preklicano članstvo, izguba podatkov ali konkretna vzročna povezava v kodi. Treba je ločiti pravi odvzem pravic od napačne razlage napake preglednice/sinhronizacije in ločenega stanja nadrejenega prostora ter projekta. Ohraniti isto sejo, podatke, podpisane zahteve in diagnostične dnevnike; ne ponavljati vnosa/shranjevanja, odjave/prijave, novega povabila ali podelitve pravic samo zaradi reprodukcije. Po poznejšem dovoljenju za diagnostiko naj bo prvi korak pregled obstoječih dnevnikov in točnega account/scope odziva ob tem dogodku, brez spreminjanja članstva.

Trenutno še velja naročilo »samo zapisuj«. Izvedeno je le beleženje; brez dostopa do naprav/strežnika, testov ali popravkov. Uporabniku je priporočeno ohraniti trenutno stanje za diagnozo.

### 25. oktober — Preg1: napačna trajna oznaka odvzema lokalno dokazana; GUI preizkus omejen

Uporabnik dopolni incident: Samsung S25, preglednica Preg1, prostor, ki je deljen z iPhonom. Točen wire ID incidenta ni prebran. Naroči lokalno ponovitev na dveh Mac instancah. Telefoni, mobilni testni strežnik 18801 in produkcija ostanejo nedotaknjeni.

Dokazana napaka v aktualni kodi: nov test uporablja pravi SharedDocumentsContext, gateway in SQLite, a sintetični transport in članstvo. Ustvari tabelo, uspešno shrani revizijo 2, nato uspešen odgovor drugega shranjevanja vrne revizijo 3 ob simulirani izgubi lokalne veljavnosti prikaza. Naknadni check vrže navadni CollaborationException(permission_revoked), ne strežniškega CollaborationApiException. Skupni catch v collaboration_document_actions.dart to zamenja za dejanski odvzem in zapiše nadrejenemu prostoru revoked=true/blocked=true; podprojekt ostane berljiv. Sintetična strežniška avtoriteta in članstvo se ne spremenita. Prvi in edini tek novega testa PASS. To je dokaz napake te poti, ne dokaz konkretnega sprožilca na Samsungu ali GUI/E2EE prenosa. Root pregleda test, rezultat in dejanski catch; produktna koda se v tem koraku ne spreminja.

Mac okolje: isti Sync A/B sta posodobljena na aktualni izvor in omejeno QA diagnostiko, vsaka ena gradnja/namestitev r11. Iste identitete, CA in Keychain nastavitve; bajtna primerjava zaščitenih lokalnih shramb ni preverjena zaradi TCC, brez obvoda. Prvotna domneva, da je obstoječi Sync Space A organizacija, je bila napačna: oba obstoječa vrhnja prostora sta gospodinjstvi, kjer preglednice niso podprte. Zato v istem lokalnem 18821 in istih računih nastane nova sintetična organizacija QA Table Access 25, podprojekt QA Table Child 25 ter eno novo povabilo za sync_b_20261024. Ne ponavljamo starih povabil ali podelitev. B novo povabilo sprejme enkrat in samodejno pride na Utrip novega prostora; A vidi B kot člana in povabilo Accepted. Prvotne Preg1 nismo odprli ali spremenili.

Meja GUI reprodukcije: oba omejena zajema dosežeta konservativno mejo 400 HTTP zahtevkov v drsečih 60 sekundah že med pripravo organizacije/povabila oziroma sprejemom. Prvi zajem 545 odgovorov, nadaljevanje 407. To ni HTTP 429 in ni dokaz neskončne zanke. Oba programa sta običajno zaprta; novega tretjega zajema ni. Preglednica v dejanskem Mac GUI še NI ustvarjena/shranjena, zato dvouporabniška GUI reprodukcija incidenta ostaja odprta. V nadaljevanju je zabeležen invitation_invalid/403 na statusnem branju po sprejemu; sam po sebi ni dokaz odvzema prostora. Dogodki work dosežejo lastno omejitev 1024; ločeni request/error kategoriji imata svoje omejitve, zato ne trdimo popolne zgodovine dela.

Pri preverjanju zaprtja je CUA getAXState nenamerno ponovno odprl obe aplikaciji; nato sta normalno zaprti in zadnji namenjeni tek uporablja tretjo omejeno diagnostično sejo. To je napaka upravljanja testa, ne aplikacijski FAIL; ni nove gradnje ali ponovitve tabelnega scenarija. Končno odsotnost procesov preveri pgrep, brez dodatnega CUA opazovanja zaprtih aplikacij.

Naslednji predlagani popravek: ločiti neveljavnost lokalnega dokumentnega konteksta od potrjenega odvzema pravic. Zaprt/prenovljen zaslon ali prehodno neusklajeno stanje ne sme trajno preklicati prostora. Dejanski odvzem/izbris, preverjanje trenutnega računa/naprave in pravice pred zapisom ostanejo uveljavljeni. Posebej preveriti uspešno potrjeno shranjevanje ter poznejši release, ohraniti osnutke in ne ponavljati podpisanih zahtev. Obstoječega napačno blokiranega prostora ne odklepati na slepo: potrebna je sveža preverjena avtoriteta. Za točen Samsung sprožilec je še potreben njegov obstoječi dnevnik; lokalni test sam tega ne dokazuje.

Dokazi: build/qa/mac-table-access-repro-20261025/false-revocation-seam-result.json, false_revocation_seam_test.dart, seam-attempt1.log, oba imenika diagnostics in diagnostics-continuation ter strežniški metapodatkovni posnetki. Brez commita/pusha ali spremembe produktne kode. Stari uspešni testi niso ponovljeni.

Dodatni končni pregled že obstoječih dnevnikov po zaprtju: od 15:27:26 do 15:36:52 UTC je lokalni gateway zapisal 2.026 odgovorov: 2.022×200, 3×429 in 1×403. Omejena zbiralnika sta se ustavila prej, živi izvozi aplikacij in že obstoječi gateway dnevnik pa so ohranili tudi poznejše napake. Zato prvotni podatek o doseženi meji 400 ni končno štetje in NE pomeni odsotnosti 429. Dejanski rate_limited je na scope.headGet, domain.inventory in account.status. Največje skupine so directory.status 488, scope.headGet 274 in account.status 174; account.changes predstavlja 36 klicev. Opazovani maksimum drsečih 60 sekund je 801 (sekundna natančnost dnevnika, ne dokaz strežnikovega notranjega okna). 0 tables.* in 0 tabelnih UI diagnostičnih dogodkov potrdita, da GUI scenarij ni stekel. To je dodatna ugotovitev za popravek obsega zahtevkov pri ustvarjanju/deljenju; ni meritev hitrosti financ ali dokaz vzroka Preg1.

Strežniški končni metapodatki so enaki posnetku po pripravi novega prostora in sprejemu povabila. Prvotni trije prostori, štiri članstva ter njihove kriptografske glave so ohranjeni kot nespremenjena podmnožica. Dodana sta samo nova organizacija in podprojekt ter tri vrstice članstva. Dokaz: readonly-final-analysis.json in http-through-final-quit.ndjson v istem imeniku. Za nadaljevanje ohranimo nov prostor, podprojekt in že sprejeto povabilo; brez ponavljanja priprave.

### 25. oktober — popravljena napačen odvzem dokumentnega prostora in prekomerno ponavljanje preverjanj

Novo izrecno naročilo dovoljuje oba produktna popravka. Izvedba: GPT 6.1 Sol/high podagenta za dokumente in zahtevke, neodvisen pregled istega tipa, root pregled kode in dejanski Mac GUI preizkus. Obstoječe necommittane spremembe so ohranjene. Telefoni, mobilni strežnik 18801 in produkcija niso uporabljeni.

Dokumentni kontekst: lokalna izguba veljavnosti, zaprtje zaslona ali prehodna neusklajenost zdaj trajno ustavijo samo stari dokumentni kontekst (document_context_changed). Ne zapišejo revoked na prostor in ne izbrišejo obnovljivega osnutka/predpomnilnika ali čakajoče izvirne zahteve. Pomnilniški bajti se počistijo, star kontekst se ne oživi. Pravi CollaborationApiException za permission_revoked/access_revoked/scope_deleted še vedno uveljavi blokado prostora; preverjanja računa, naprave, seje, avtorstva in pravic ostanejo. Napačna vrsta prostora in prepoved urejanja dobita svoji kodi. SL/EN besedilo zastarel pogled loči od dejanskega odvzema. Že obstoječih blokiranih prostorov ne odklepamo na slepo, ker stari zapis nima provenience vzroka; obstoječi izrecni postopek zahteva novo preverjanje avtoritete.

Šest novih regresij PASS: uspešen zapis z izgubo vidnosti in obnovo izvirne zahteve brez podvojenega učinka, pozen release po zaprtju, prehodna reconciliation blokada, prava API zavrnitev, zamenjava računa med odgovorom in nepodprta vrsta prostora. Pred popravkom en pričakovan baseline FAIL. Analiza brez napak/opozoril, ena prej obstoječa slogovna informacija. Sintetični transport, prava SQLite/dokumentna pot; ni dokaz točnega Samsung sprožilca. Dokaz false-revocation-fix-result.json v build/qa/mac-table-access-repro-20261025.

Zahtevki: public currentHead in currentMemberDirectory zdaj uporabljata obstoječo omejeno preverjeno operacijo za svojo logično pripravo dokazov. Veljavna vgnezdena operacija ohrani izvirno uro; po izteku ali razveljavitvi se naslednji podsklop preveri v novem samostojnem kontekstu, stari kontekst se ne podaljšuje. Preverjanje spremembe objave po obnovi starega prostora ostane PRED novim ovojem; neodvisni pregled je tu preprečil zakritje starega aktivnega konteksta. capabilities in invitations.resolvePreauthorization sta pravilno prepoznana kot branji, ki ne smeta sama razveljaviti celotnega posnetka. Ne gre za splošni predpomnilnik odgovorov ali zvišanje strežniške omejitve. Podpisi, najvišja starost pet sekund, identity/pins/lifecycle, explicit fresh delivery, mutation/unknown/signed-command invalidation, frozen/deleted in pendingCapability varovala ostanejo.

Pet novih kontrol PASS. Priprava glave: štirje skupni klici pred popravkom proti trem po njem, všteti tudi capabilities in snapshot; osamljeno zgodovinsko branje imenika ostane en klic. Testi pokrijejo vgnezdenje, zapis med branji, neveljaven stari kontekst, spremenjen varen pin, lifecycle, iztek 5,1 sekunde, zamenjavo identitete in zavrnitev brez samodejnega ponavljanja. Prvi tek ima ohranjene tri napake testnega ogrodja/oraklja; drugi filtrirani tek uspe. Ena nova že uspešna kontrola je ponovljena zaradi relevantne spremembe vrstnega reda varovala; starih PASS testov ne ponavljamo. Analiza brez napak/opozoril, 71 obstoječih slogovnih informacij. Dokaz build/qa/excessive-request-fix-20261025/local-results.json. To razmerje 4→3 samo po sebi ni dokaz odprave vseh prejšnjih 2026 zahtevkov.

Dejanski lokalni preizkus: isti Mac Sync A/B, vsaka ena r12 gradnja in namestitev, nato en zagon. Isti bundle ID, podpisne pravice, CA, Keychain nastavitve in izvorni kriptografski moduli; podatkov ni bilo ponastavljenih. Bajtna primerjava zaščitenega vaulta ostaja UNVERIFIED zaradi TCC, brez obvoda. Obstoječa organizacija QA Table Access 25, podprojekt in sprejeto povabilo ostanejo; brez ponavljanja create-space/invite/accept/grant. QA diagnostika je ločena od produktne kode.

Root ustvari eno novo QA-TABLE-ACCESS-25-1, pridobi urejanje in v A1 shrani PRVI-25 z enim Save and finish. Prikaz Saved, nato novo urejanje iste preglednice in DRUGI-25, ponovno en Save and finish in Saved. B odpre seznam in vidi revizijo 3; odpre isto preglednico in vidi DRUGI-25 v A1. A se vrne iz preglednice in seznama v nastavitve celotnega prostora: še vedno Owner, B Member, povabilo Accepted. Prvotni Preg1 na telefonu ostane nedotaknjen.

Prvi ciljni GUI tek PASS brez ponovitve. Oba programa normalno zaprta, odsotnost procesov preverjena s pgrep; CUA po zaprtju ni ponovno poklican. Zajem ustavljen namensko po uspehu, ne zaradi meje. Začetni končni števec: 669 HTTP, vrh 249 v drsečih 60 sekundah, brez opozorila/429/dokumentne napake; spodaj sledi končna analiza vključno s repom dnevnika. Ni primerljiv odstotni benchmark proti prejšnjemu ustvarjanju/povabilu. work diagnostika A doseže svojo omejitev 1024; request/error/UI kategorije so neodvisne. Posnetka recipient-revision3.png in owner-space-after-save.png sta v build/qa/mac-table-access-fixes-20261025.

Popravka sta lokalno preverjena; nista še nameščena na telefonih. Točen prvotni Samsung sprožilec ostaja neprebran, preverjena pa je popravljena lokalna vzročna pot in uspešen dejanski scenarij z dvema Mac uporabnikoma.

Končna analiza istega teka: 669 dejanskih HTTP odgovorov, vsi 200, nič 403/429 ali drugih ne-200, opazovani vrh 249/60 s. Zajem in rep znanega gateway dnevnika se ujemata. Nativni markerji A: ustvarjanje 616 ms, pridobitvi urejanja 503/535 ms, vrnitvi shranjevanja 691/747 ms, lokalni uveljavitvi 693/748 ms. To so časi označenih faz, ne meritev prvega izrisanega okvirja. Obe instanci brez zajetih napak dokumenta; zadnja sinhronizacijska zaključka A seq4/B seq3 imata error=null, unresolved=false in retry=false. Tri records.batch zahteve ter dve pridobitvi/dve sprostitvi urejanja ustrezajo eni novi preglednici in dvema shranjevanjema. Dejanski podpisani protokol ni bil obiden.

Končni metapodatki dostopa so bajtno enaki posnetku pred tem tabelnim preizkusom: pet prostorov, sedem članstev, pet kriptografskih stanj, hash be078e18a6b0c2f7131c7ad85e194697e2667914eccef8281b7b34b754ecf912. Prvotni prostori so nespremenjena podmnožica. Dokaz: build/qa/mac-table-access-fixes-20261025/readonly-final-analysis.json. V tem scenariju torej ni odvzema dostopa niti rate-limit napake. Ni trditve o enakem odstotnem prihranku za prejšnji drugačen scenarij ustvarjanja/deljenja.
