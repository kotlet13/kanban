# Mobilna testna priprava — 24. oktober 2026

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
