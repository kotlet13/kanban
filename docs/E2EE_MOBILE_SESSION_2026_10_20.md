# Skupno mobilno nadaljevanje — 20. oktober 2026

**Aktualno: točen vzrok `directory_proof_pending` je zajet in odpravljen.
Isto iOS povabilo je z nameščenim popravkom `bbc61dc6…` dejansko zaključilo
`resumeAccepted` (`resumeCompleted=true`, `outcome=resumed`). Sedem novih
izvornih kontrol PASS. Prikaz skupne vsebine in preostali mobilni scenariji
s tem še niso potrjeni. Produkcija je nedotaknjena.**

## Ponovno odprta diagnoza po izrecnem naročilu uporabnika

Po čiščenju je uporabnik naročil določitev točnega izvora
`directory_proof_pending` pred novim popravkom. Spodnji trije neuspešni
poskusi ostanejo zgodovina; nov zajem ni ponovitev sprejema ali odobritve.
Ena QA diagnostična gradnja brez spremembe delovanja, IPA `ea9d6805…`,
je označila vseh 37 klicev, ki lahko dosežejo offline zavrnitev (preostalih
69 izrecno zahteva online). Neodvisni pregled pokritosti in sprememb PASS.
Isti izvorni QA imenik in predpomnilnik sta ponovno uporabljena.

Namestitev ohrani isti podpis, QA identiteto, Keychain in vse štiri šifrirane
datoteke vaulta bajtno enake. En zagon ob **17:30:02 UTC**, PID1183, in en
Continue nadaljujeta isto povabilo. [Dejanski zapis izjeme](../build/qa/jivie-mobile-readiness-20261020/ios/native-proof-diagnostic-20261020/durable-proof-result.json)
določi pot:

`resumeAccepted → CryptoScopeObservations.observe → verifyDomainCheckpoint
→ directoryAt → directory_proof_pending`.

To je klic podpisnikovega imenika pri kontrolnem zapisu, oznaka `dp_033`,
izvorna vrstica 4262 v `session_crypto_access.dart`, ne preverjanje začetnega
sidra povabila. `currentHead` in prevzem ključev sta se pred tem vrnila.
Lokalna veriga obstaja in njen konec ustreza varnemu sidru (glava, posnetek,
generacija); zahtevanega podpisnikovega zapisa ni v njej ali v predpomnilniku.
Klic ima `online=false`, zato ne sme pridobiti manjkajočega dokazila.
Iz samega zajema ni mogoče določiti, ali je zahtevani zapis starejši ali
novejši od sidra, niti potrditi njegove veljavnosti. To mora preveriti
obstoječi podpisani replay.

Zapis vsebuje le stalne oznake in logične predikate, ne vsebine, ključev,
identifikatorjev ali surovega sklada. Začetek nadaljevanja je potrjen;
zaključek ni dosežen. Sledi ozek izvorni popravek z ločenim dokazom.
Novega povabila, accept, owner granta ali poslovnega vnosa ni bilo.

### Ciljni izvorni popravek

`verifyDomainCheckpoint` ima nov izbirni `onlineAuthorDirectory=false`.
Samo `CryptoScopeObservations.observe`, po svojem obstoječem spletnem
preverjanju glave, izrecno omogoči pridobitev podpisnikovega točnega
imenika. Notranji `currentHead`/`headAt`, druga dva klicatelja ter
privzeto offline delovanje ostanejo isti; frozen/deleted evidence konteksta
nov dostop dodatno izključita. Obstoječi replay, sidro/CAS, podpis,
vloga in preverjanje zgodovine ostanejo obvezni.

Nova [ciljna regresija](../test/organizer/data/e2ee/crypto_checkpoint_author_directory_test.dart)
na stari funkcionalni poti v prvem poskusu reproducira isto
`directory_proof_pending`. Z ozkim popravkom v drugem poskusu uspe vseh
sedem novih kontrol: spletna pot observe, offline brez zahtevka,
frozen brez zahtevka, zavrnitev fork, napačnega podpisa, manjkajočega
ciljnega zapisa in vloge viewer. Varno sidro in globalna identitetna
veriga ostaneta enaka. Pozitivna kontrola doseže namensko mejo po
dejanskem preverjanju kontrolnega podpisa; predpreverjena glava v
ogrodju pomeni, da to ni dokaz celotnega native nadaljevanja ali objave
observation. [Rezultat](../build/qa/jivie-mobile-readiness-20261020/ios/checkpoint-author-fix-20261020/fixed-attempt2.log).
Scoped analiza: 0 napak, 0 opozoril, 86 obstoječih info; nova testna datoteka
brez pripomb. Glavni in neodvisni pregled PASS. Starih PASS testov nismo
ponovili.

### Dejanska potrditev na istem iPhonu

Druga namenska gradnja, zdaj s popravkom in svežo v4 oznako diagnostike,
IPA SHA-256 `bbc61dc62d278cd43372a736f6e5b1ab6d23c7d39bb9bed7a8093316944e6532`
(16.468.237 B), je nameščena čez isto Jivie Test. Ista QA identiteta,
profil, podpis, Keychain in TLS; štiri šifrirane vault datoteke imajo
pred/po namestitvi iste hashe. Brez nove polne izvorne kopije.

En zagon ob **17:40:34 UTC**, PID1192, in en Continue nadaljujeta prvotno
povabilo. [Sveži trajni zapis v4](../build/qa/jivie-mobile-readiness-20261020/ios/native-checkpoint-author-fix-20261020/durable-proof-result.json)
ob **17:41:21 UTC** potrdi `resumeStarted=true`, `resumeCompleted=true`,
`outcome=resumed`. To dokazuje zaključek preverjanja glave in sprejema,
prevzem ključev, `observe` in posodobitev lokalnega sidra v `resumeAccepted`.
UI se vrne v prazen obrazec za povabilo brez prejšnje rdeče napake.
PASS temelji na izrecnem zaključnem zapisu, ne na odsotnosti datoteke napake.

**Native popravek PASS v drugem poskusu ponovno odprte diagnoze**:
prvi namerni zajem v3 je razkril točen klic, drugi v4 s popravkom uspe.
Predhodni trije neuspehi so ohranjeni spodaj. Nobenega novega povabila,
Join/accept, owner granta, prijave, FILE ali poslovnega vnosa.
Prikaz in urejanje skupnega opravila na iPhonu, offline, odvzem in
obnova na fizičnih napravah ostajajo ločeni odprti testi; niso ponovno
zagnani ali označeni PASS. Prav tako ostajajo splošne P0/P8 meje.
Isti QA proces je ob **17:41:54 UTC** normalno ustavljen in odsoten.
Pasivna konzola v 87,714 s ni zajela NET oznak, zato povezava konzole
ni potrjena; dokaz uspeha je zgornji trajni zaključni zapis.
Po predaji paketa je odstranjenih pet regenerabilnih cache map iz istega
QA izvornega imenika, skupaj 1.190.924.288 B zasedenega prostora.
Vsi izvori, končni paketi, dokazi in zasebne kopije ostanejo.
[Manifest čiščenja](../build/qa/jivie-mobile-readiness-20261020/ios/checkpoint-author-fix-20261020/regenerated-cache-cleanup-manifest.json).

## Prejšnji omejeni preizkus

**Prejšnji checkpoint pred zgornjim popravkom: obe testni aplikaciji sta posodobljeni; Android
bootstrap in en običajni samodejni sync po povezavi Wi-Fi sta PASS.
Lastnikova odobritev in predaja parent/child ključev sta strežniško PASS;
iOS nadaljevanje tudi v tretjem in zadnjem native poskusu odpove z
`directory_proof_pending` pri `preview_resume_accepted`. Nadaljevanje je
FAIL/SKIP po treh poskusih; odvisni B prikaz in mobilni scenariji so
BLOCKED, brez četrtega kroga.** Po vrnitvi
je uporabnik priključil in odklenil oba telefona ter odobril namestitev in
skupne preizkuse. Nadaljujemo isti S25/A in iPhone 11/B, ista računa,
projekt in prvotno že sprejeto povabilo iz
[18. oktobra](E2EE_MOBILE_TWO_USER_TEST_2026_10_18.md).
[Priprava paketov in gostovanja](E2EE_MOBILE_READINESS_2026_10_20.md)
je ločena od spodnjih dejanskih namestitev in prvih zagonov.

Androidov prvi zagon je obstal zaradi manjkajoče registracije native
vtičnikov v novem QA paketu. Ozki QA pakirni popravek je pri drugem
poskusu dokazano odpravil bootstrap napako: stanje je `ready`, brez izjeme;
uporabnik je potrdil običajni prikaz aplikacije. Po odpravi izključenega
Wi-Fi je isti običajni samodejni sync zaključen brez napake. iOS je po
uporabnikovem običajnem Continue
pokazal avtenticiran predogled istega povabila z gumbom Join. Pred owner
grantom ni bilo novega klika; poznejše prvo nadaljevanje istega predogleda
je opisano spodaj. To ne pomeni, da je treba ponoviti sprejem: prvi omejeni
strežniški pregled je potrdil že sprejeto prvotno povabilo. En pozneje
dostavljeni owner Confirm je uspešno porabil isti sprejem ter aktiviral
parent in child z B ključi. Novega povabila ali accept ni bilo; dejansko
B branje ostaja ločeno, zdaj blokirano preverjanje.

| Preverjanje | Dejanski izid in meja |
| --- | --- |
| Android namestitev | PASS v prvem poskusu: en `install -r`, isti QA ID/podpis/dataDir; predhodna zasebna kopija ohranjena. |
| iOS namestitev | PASS v prvem poskusu: isti QA bundle/storage service/group; šifrirani vault ima pred/po iste hashe. Sistem je zamenjal pot podatkovnega vsebnika, ne vsebine vaulta. |
| Android prvi zagon | FAIL pri težavi zagona, poskus 1: `PlatformException`, `channel-error` za `PathProviderApi.getApplicationDocumentsPath`; faza bootstrap `null`. Pakirni vzrok potrjen, brez dokaza napake šifriranih podatkov. |
| Android popravek | Bootstrap PASS v poskusu 2: popravljeni APK je nameščen; po enem običajnem zagonu VM potrdi `ready`, brez izjeme. Uporabnik je potrdil običajni prikaz; poznejši sync je v ločenem zapisu spodaj. |
| iOS nadaljevanje | Poskus 1 FAIL z generično napako; poskusa 2 in 3 FAIL z dokazanim `preview_resume_accepted/CryptoAuthorityPending/directory_proof_pending`. Po tretjem FAIL/SKIP, brez četrtega Retry/build/fix kroga. |
| Prvotno povabilo | Read-only PASS za ohranitev: en isti sprejem 18. oktobra, po owner grantu `consumed`, brez nadomestitve/novega sprejema. |
| Android navadni samodejni sync | PASS po uporabnikovi povezavi Wi-Fi: ni v teku, 0 pending/conflicting/blocked, brez napake; ni ročnega Sync/Retry. |
| Owner grant parent/child | PASS po enem dejansko dostavljenem Confirm: isti sprejem consumed, parent/child active epoch2 in B granti. |
| B branje skupne vsebine in odvisni mobilni testi | BLOCKED zaradi neuspešnega iOS nadaljevanja; ni novega PASS. |

Android ob **16:04:34 UTC** prejme APK SHA-256
`7fef105a9341b5ee6378a3d4e7004e6e0b0a028f24f077b73adbcdb79f15a72b`.
[Dokaz namestitve](../build/qa/jivie-mobile-readiness-20261020/android/installation-20261020/installation-evidence.json)
veže isti podpis, podatkovno mapo, eno namestitev in kopijo 16 datotek.
Po namestitvi je bil brez našega launch ukaza opažen background PID 3238;
razlog tega zagona ni pripisan. En izrecni običajni zagon ob **16:09:46 UTC**
je uporabil isti PID, brez force-stop/restarta, vnosa ali ročnega Sync.
[Prvi zagon](../build/qa/jivie-mobile-readiness-20261020/android/installation-20261020/first-launch-evidence.json)
in [omejena VM diagnostika](../build/qa/jivie-mobile-readiness-20261020/android/installation-20261020/bootstrap-state-diagnosis.json)
ločita namestitev od neuspešnega bootstrapa. `capture_armed_before_launch`
v Android dokazu se nanaša na lokalna NET/exception zajema; ne pomeni,
da je bil takrat že aktiven strežniški zajem.

[Primerjava dejanskih APK](../build/qa/jivie-mobile-readiness-20261020/android/installation-20261020/native-plugin-registration-diagnosis.json)
potrdi `GeneratedPluginRegistrant` v prejšnjem paketu in njegovo odsotnost
v novem. Implementaciji PathProvider in SharedPreferences sta prisotni v
obeh paketih; omejena PID diagnostika potrdi neuspešno samodejno iskanje
registracije. To je konkretna QA pakirna napaka, ne dokaz izgubljenega
računa, ključev ali vaulta. Uporabljen je generator obstoječega Flutterja
`pub get --offline --enforce-lockfile`, brez kopiranja starega registranta.
[Dokaz generiranja](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/generation-evidence.json)
potrdi registracijo obeh vtičnikov, iste štiri lock datoteke in nespremenjeno
Dart runtime kodo. Popravljeni APK SHA-256
`56fbc372a76df6db6f709984f47a9c2faa1bf0e4aa27aa895e217e7550bc262b`
je po neodvisnem pregledu [nameščen ob 16:18:22 UTC](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/installation-evidence.json)
čez isti QA ID/podpis/dataDir. Sveža kopija vseh štirih vault datotek se
bajtno ujema s prvotno kopijo pred današnjo posodobitvijo. En običajni
zagon ob **16:19:10 UTC**, PID 6237, sledi obema klientovima zajemoma in
izrecni potrditvi strežniškega okna 3. [Read-only VM pregled ob 16:19:29 UTC](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/bootstrap-state-diagnosis.json)
potrdi `error_class=none`, `status_phase=ready`, `busy=false`. Vzročni
bootstrap popravek je **PASS v drugem poskusu iste težave**, brez Retry,
FILE, prijave ali ponovitve poslovnih dejanj. Sam foreground ni uporabljen
kot dokaz popravka. Uporabnik je nato potrdil običajni prikaz aplikacije. Zaključeni sync in
skupni podatki še čakajo: [omejena omrežna diagnostika](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/network-reachability-diagnosis.json)
potrdi Wi-Fi OFF (`wifi_on=0`), brez povezave, z nedosegljivo potjo do
istega LAN cilja. Štiri dejanske capabilities napake so `status=0`,
`network`, `rx=0`; ni dokaza HTTP odgovora ali TLS napake. Uporabnik je
pozvan, naj telefon poveže v isti Wi-Fi kot Mac ter ohrani aplikacijo brez
ročnega Sync. Uporabnik je povezavo potrdil; read-only pregled ob
16:21:30 UTC potrdi `wifi_on=1`, obstoječo pot in isti PID. Odprt je nov
omejen zajem naravnega nadaljevanja. En [read-only VM povzetek](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/current-sync-summary.json) ob
**16:22:53 UTC** potrdi zaključen običajni sync: `notSyncing`, nič pending,
conflicting ali blocked, nič finance pending/blocked, `lastError=null`,
prisoten uspešen sync in completion sequence 5. To je **PASS samodejnega
nadaljevanja iste aplikacije po povezavi Wi-Fi**, brez klica poslovne metode,
ročnega Sync ali Retry. Ni novega TLS/code popravka ali ponovitve zagona.
[Pasivni klientov zajem](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/wifi-resumed-capture-summary.json)
zajame 158 NET zapisov, vse HTTP200/result ok, brez napak. To je
180-sekundni agregat, ne en atomski cikel ali meritev hitrosti. Ločeni
[shranjeni časi synca](../build/qa/jivie-mobile-readiness-20261020/android/native-registration-fix/stored-sync-timestamps.json)
vežejo poznejši uspešni sync ob 16:23:19 UTC na nadaljevanje po povezavi
Wi-Fi. Prvi omrežni izid je bil neuspeh okolja z izključenim Wi-Fi, nato
isti naravni prehod ob povezavi uspe; ni novega računa/fixture ali ročnega
ponovnega dejanja. Ta izid ne potrjuje novega owner granta ali B dostopa do vsebine.

[iOS namestitev ob 16:05:17 UTC](../build/qa/jivie-mobile-readiness-20261020/ios/native-install-20261020/installation-evidence.json)
veže IPA SHA-256
`51a42425076cad618fb96aaf8e1f71facd5b100eac72e2b372468d1216e62651`,
isti QA bundle, varno hrambo ter zasebno kopijo štirih datotek. Orodja niso
brala ali spreminjala Keychaina. Prvi opaženi zagon ob **16:09:35 UTC** ima
PID 1147. Pregled imen/velikosti brez branja vsebin potrdi samo ohranjene
`Documents/jivie_qa_invite_init_v1`, `Documents/jivie_qa_invite_init_v2`
in vault. Imenikov nismo brisali ali izključili z varnostnim obvodom.
[Inventar opozorila](../build/qa/jivie-mobile-readiness-20261020/ios/native-install-20261020/first-launch-warning-inventory.json)
in [inventar v1](../build/qa/jivie-mobile-readiness-20261020/ios/native-install-20261020/first-launch-warning-v1-inventory.json)
sta ločena od poznejšega uporabnikovega Continue in prikaza povabila.
[iOS konzolni zajem](../build/qa/jivie-mobile-readiness-20261020/ios/later-capture-20261020T160918Z/result.json)
je trajal 180,16 s in ni dobil nobene NET oznake. Ustavljen je bil samo
host konzolni proces; telefonu ni bil poslan signal ali nov zagon.
Ta prvi zajem ni potrdil povezanosti konzole; nič oznak ni dokaz odsotnosti
HTTP prometa. Poznejši [pasivni konzolni zajem istega PID 1147](../build/qa/jivie-mobile-readiness-20261020/ios/passive-console-20261020/20261020T163058Z/result.json)
se je zaključil ob 16:32:59 UTC po 120,204 s in prejel **47 dovoljenih NET
oznak, vse HTTP200**. Povezanost konzole je zdaj potrjena. Ni novega zagona,
UI vnosa, signala telefonu ali shranjenih surovih izpisov. Ta poznejši
pasivni zajem pa ne določi kode že ujete prvotne UI izjeme.

Strežniški preflight ob **16:03:06 UTC** potrdi isti
`https://192.168.132.29:18801`, običajno preverjanje istega CA/hostname,
182 točnih runtime datotek izvora `cf97e2d` in health200. Isti mobilni
mail-worker je zagnan prek pregledanega varovala za skupno sejo.
Certifikat poteče **21. oktobra ob 12:25:42 UTC / 14:25:42 lokalno**.
Preflight ne izvaja javnih ali avtenticiranih API operacij.
[Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-preflight.json).

Omejena 180-sekundna strežniška okna zajemajo samo čas, HTTP metodo,
status, trajanje in število bajtov. Nimata URL poti, operacije, IP ali
identitete klienta; zahtevkov zato ne pripisujemo A/B ali poslovnemu toku.
GET200 so združljivi z običajnimi healthchecki, ne dokaz telefonske povezave.

| Okno | Dokazani čas in rezultat |
| --- | --- |
| 1 | Aktivnost potrjena 16:04:43 UTC; zaključek/obnova konfiguracije 16:07:35 UTC. 6 GET200, nič POST, skupaj 378 B odgovorov. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window1-summary.json). |
| 2 | Aktivacija uspela v tretjem omejenem poskusu; opažena 16:10:23 UTC, zaključek/obnova 16:13:12 UTC. 6 GET200, 27 POST200 in 1 POST403; skupaj 75.571 B odgovorov. Vzrok/klient za 403 ni dokazan. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window2-summary.json). |
| 3 | Prvi poskus aktivacije PASS, opažen 16:18:55 UTC, zaključek/obnova 16:21:48 UTC. 6 GET200 in 21 POST200; skupaj 19.370 B odgovorov. Android ob izključenem Wi-Fi ni dokazal HTTP; združenih POST ne pripisujemo A. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window3-summary.json). |
| 4 | Naravno nadaljevanje po povezavi Wi-Fi ter poznejši pregled key details; prvi poskus aktivacije PASS, opažen 16:22:03 UTC, zaključek/obnova 16:24:56 UTC. 6 GET200, 175 POST200; skupaj 481.139 B odgovorov. Brez ročnega Sync/Retry/zagona; pred zaključkom ni potrjenega Confirm. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window4-summary.json). |
| 5 | Pred owner Confirm prvi poskus aktivacije PASS, opažen 16:25:08 UTC, zaključek/obnova 16:28:01 UTC. 6 GET200 in 247 POST200; skupaj 642.515 B odgovorov. Prva dva dotika nista sprožila dejanja; točno prekrivanje dejanskega začetka z oknom ni dokazano. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window5-summary.json). |
| 6 | Pred nadaljevanjem istega iOS predogleda prvi poskus aktivacije PASS, opažen 16:29:25 UTC, zaključek/obnova 16:32:19 UTC. 6 GET200 in 390 POST200; skupaj 1.852.081 B odgovorov. UI napaka ni vezana na konkretno operacijo/klienta. Zajem je nato OFF. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window6-summary.json). |
| 7 | Pred enim diagnostic iOS zagonom/Continue prvi poskus aktivacije PASS, opažen 16:44:21 UTC, zaključek/obnova 16:47:15 UTC. 6 GET200 in 348 POST200; skupaj 1.499.197 B odgovorov. Dejanski samodejni resume je poskus 2; njegova koda prihaja iz klientovega cache dokaza. Zajem je OFF. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window7-summary.json). |
| 8 | Pred finalnim iOS enim zagonom aktiviran v prvem poskusu, opažen 16:55:41 UTC, zaključek/obnova 16:58:35 UTC. 6 GET200 in 230 POST200; skupaj 1.018.980 B odgovorov. Native resume je poskus 3 FAIL, koda iz dveh v2 cache datotek. Izvirna gateway konfiguracija točno obnovljena, zajem OFF. [Dokaz](../build/qa/jivie-mobile-readiness-20261020/joint-session/server-metadata-window8-summary.json). |

Prva dva poskusa aktivacije okna 2 sta odpovedala pri `nginx -t` nad
spremenjenim bindom, pred aktivacijo zajema. Oba sta povrnila izvirno
konfiguracijo. Ista začasna metadata konfiguracija v `/tmp` je bila veljavna;
točen vzrok prvih dveh napak ni dokazan. Tretji poskus je pred lintom dodal
`fsync` in primerjavo vseh bind bajtov znotraj gatewaya ter uspel. Po koncu
je izvirna konfiguracija spet točno obnovljena; ni samodejne ponovne aktivacije.
Oba prva zagona telefonov sta bila **pred dokazano aktivacijo okna 2**;
strežniško okno njunega začetka ne pokriva. Lokalna klientova diagnostika je
ločena. Zagona ali dejanj zaradi te vrzeli ne ponavljamo.

[En read-only pregled ob 16:14:02 UTC](../build/qa/jivie-mobile-readiness-20261020/joint-session/retained-original-invitation-readonly.json)
uporabi hash točno prvotnega zasebnega tokena in isti potrjeni B kontekst,
brez izpisa tokena, imen, e-pošte, ključev ali vsebine. `query_only` SQL
transakcija potrdi eno nepodvojeno, nenadomeščeno povabilo `accepted`, isti
račun in e-pošto ter en `accepted` zapis z **18. oktobra ob 18:57:55 UTC**.
Povabilo poteče 25. oktobra ob 16:36:10 UTC. Parent organization je še v
epoch1/accessRevision0; B nima membership vrstice, parent grantov ali
child projektnih grantov. Lastnikova predaja torej ostaja odprta.
Pregled ni API replay, novo sprejetje ali mutacija.

Po uporabnikovem pregledu prvotnega sprejema v nastavitvah parenta
**Mobile E2EE 20261018** je bil okrog 16:26 UTC izveden en CUA tap Confirm.
Začetni prikaz je še kazal gumb brez napake; dostava oziroma začetek
operacije nista bila s tem potrjena. [En omejen read-only posnetek po tem dejanju ob 16:27:04 UTC](../build/qa/jivie-mobile-readiness-20261020/joint-session/post-owner-original-invitation-readonly.json)
potrdi isto eno sprejetje ter še nespremenjena parent/child aktivna epoch1,
accessRevision0, brez B membership vrstic ali grantov. To ni dokaz uspešne
aktivacije ali predaje; razlog nespremenjenega stanja še ni dokazan.
Prva dva CUA dotika nista sprožila dejanja. Po odpravi fokusa priklopljenega
mirrora je bil okrog **16:28 UTC** dejansko dostavljen en Confirm: viden je
napredek in onemogočen gumb. To je en dejanski začetek operacije, ne tri
izvedene aktivacije. Po zaključku se je UI brez vidne napake vrnil v nastavitve prostora. Prej
omenjeni SQL posnetek je bil pred dokazano dostavo in zato ni dokaz
neuspeha sprožene operacije.
Po dejanskem zaključku je izveden [en ločen read-only posnetek ob 16:28:38 UTC](../build/qa/jivie-mobile-readiness-20261020/joint-session/real-owner-result-readonly.json),
prejšnji posnetek je ohranjen. Isto prvotno povabilo in isti en sprejem iz
18. oktobra sta zdaj `consumed`, brez nadomestitve ali novega sprejema.
B je active parent član z vlogo member. Parent in child imata vsak eno
aktivno epoch2/accessRevision1, prvotni epoch1 sta historical. Za B je v
parentu in childu po štiri grant-state vrstice in osem grant-entry vrstic.
Child nima neposredne B membership vrstice; ta podatek je ločen od
dokazanega podedovanega dostopa in objavljenih grantov.
**Lastnikova odobritev ter parent/child aktivacija in objava B ključev so
PASS pri enem dejansko dostavljenem Confirm.** To še ni dokaz, da je B
na telefonu dešifriral in prikazal opravilo. Ni novega accept ali SQL pollinga.

Ozki iOS izvorni pregled pojasni, zakaj se pri tem stanju lahko spet pokaže
Join: `resumeAccepted` pri že sprejetem, še ne porabljenem povabilu vrne
`null`, nato UI prikaže preview. Pot z že shranjenim pending markerjem v
`_joinEncrypted` lahko vrne čakanje brez novega accept. To je razlaga
izvora, ne neposreden pregled trenutnega Keychain markerja. Nov accept ni potreben za dokaz ohranjenega strežniškega sprejema.
Poznejše nadaljevanje istega predogleda uporablja pot že sprejetega
povabila; ne gre za novo povabilo ali ponovitev owner granta.

Po uspešnem owner grantu je bilo okrog **16:29 UTC** izvedeno prvo dejansko
iOS nadaljevanje istega predogleda, brez relaunch ali ponovitve granta.
UI je ostal na predogledu in pokazal **»Spremembe ni bilo mogoče shraniti.
Poskusi znova.«**. Ta težava ima **poskus 1 FAIL, vzrok UNKNOWN**; drugega
Retry še ni. Strežniško okno 6 v obdobju 16:29:20–16:30:10 beleži 178 POST,
vse HTTP200, brez opažene HTTP zavrnitve. Ne vsebuje pa identitete,
operacije, response kode ali vsebine, zato ne dokazuje, kateri zahtevki
so pripadali B ali kje je UI odpovedal. Stabilna iOS koda/izjema še ni
zajeta. Ni auth poizvedbe, SQL pollinga ali novega posega v sejo za
iskanje napake; najprej čaka ozka pasivna diagnostika istega procesa.

Ločen ozki izvorni pregled je odkril še napako po vrnitvi iz key approval
na seznam članov: izrazni `setState(() => _future = _load())` vrne `Future`
in v debug načinu sproži Flutter assertion. Sedemvrstični popravek v
`sharing_members.dart` uporabi sinhroni blok z isto eno `_load()` in istima
mounted/current varovaloma; pravice, predaja in navigator ostanejo isti.
Nova ozka widget regresija preveri dejanski povratek na seznam, odsotnost
izjeme in osveženega člana. Prvi tek je odpovedal zaradi začetnega fixture
prikaza; drugi baseline pokaže dejanski Future assertion skupaj z dodatnimi
Fake fixture napakami; tretji tek po popravku fixture in callbacka je PASS.
To ni čist samostojen baseline z zadnjim fixture, zato te meje ne skrivamo.
Analiza: 0 error/0 warning, dva stara slogovna info. Glavni in
[neodvisni izvorni pregled](../build/qa/jivie-mobile-readiness-20261020/joint-session/sharing-members-grant-return-independent-review.json)
sta PASS, brez novega teka testov pri neodvisnem pregledu. Popravek je
commit/push `d7533f9`. To je source popravek; ni dokaz nove native namestitve tega popravka ali pojasnilo
neznane iOS napake nadaljevanja. Owner granta ne ponavljamo zaradi te regresije.

Za neznano iOS napako je po glavnem in neodvisnem Android pregledu PASS
odobren **QA-only diagnostični kandidat z dvema datotekama**:
[izvorni preflight](../build/qa/jivie-mobile-readiness-20261020/ios/continuation-diagnostic-proposal-20261020/candidate/source-preflight.json).
Ozek catch ovitek v `invitation_wizard.dart` in novi pomočnik zapišeta samo
končno oznako faze, fiksni razred in dovoljeno kodo prve napake. Dve majhni
datoteki sta v `Library/Caches/jivie_qa_invitation_continuation_20261020`,
izven native retained-copy scannerja za Documents/tmp. Ni surovega sporočila,
stacka, payloadov, tokenov ali identitet; diagnostični IO ne postane pogoj
za aplikacijsko logiko in ne spremeni prvotne izjeme. TLS, podpisovanje,
SDK in štiri lock datoteke ostanejo isti. Ena odobrena arhivska gradnja je
uspešna; [artifact-only dokaz](../build/qa/jivie-mobile-readiness-20261020/ios/continuation-diagnostic-proposal-20261020/candidate/artifact-evidence.json)
veže IPA SHA-256
`6051f146e26f49004edb89d6762346249b8172deb285f5b0d2f20840a7885b2c`,
isti QA podpis/profil/service/group in bajtno enaka nepodpisana sodium ter
sqlite3mc. Root je paket pregledal PASS. [Ena namestitev ob 16:44:00 UTC](../build/qa/jivie-mobile-readiness-20261020/ios/native-continuation-attempt2-20261020/installation-evidence.json)
ohrani vse štiri šifrirane vault datoteke pred/po, z novo zasebno kopijo;
Keychain ni bran ali spreminjan. QA proces pred kopijo in po namestitvi ni
bil zagnan, podatkovni container UUID se je sistemsko spremenil ob enaki
vsebini. To je PASS paketa/namestitve, **ne odprave neznanega vzroka**.
Pred enim običajnim zagonom je ob 16:44:21 UTC potrjeno novo 180-sekundno
strežniško okno 7. Če ob enem root/CUA Continue skozi staro QA opozorilo
samodejna obnova izvede nadaljevanje, se šteje kot **poskus 2 iste težave**;
števca ne ponastavimo. En običajni zagon ob 16:45:16 UTC ima PID 1158. Po enem dostavljenem
root/CUA Continue je viden računski čarovnik **Zaščita povezanih
podatkov**: račun še ni pripravljen, vidni sta ohranjeni parent/child kartici
z oznako encrypted. Povabilni UI še ni prikazan. [Poznejši ozki trajni diagnostični datoteki](../build/qa/jivie-mobile-readiness-20261020/ios/native-continuation-attempt2-20261020/durable-metadata-result.json)
potrdita, da je samodejno nadaljevanje dejansko teklo in odpovedalo:
**poskus 2 FAIL — stage `preview_resume_accepted`, razred
`CryptoAuthorityPending`, koda `directory_proof_pending`**. Za ta poskus je
koda dokazana; ne sklepamo, da je bil vzrok prve generične napake nujno
isti. Računski zaščitni čarovnik trenutno prekriva dejansko napako
nadaljevanja. Takrat ni dodatnega UI dejanja, Retry/Join ali tretjega
native poskusa, auth poizvedbe, SQL pollinga ali ponovitve granta. Sledi
ozka izvorna diagnoza glavnega iOS in neodvisnega Android pregleda.

Izvorna diagnoza potrdi konkretno napačno mejo: običajni
`currentHead(..., online:true)` pri `_ensureInvitationAnchor` ni posredoval
online namena, zato je helper za zgodovinski creator prefix uporabil offline
`directoryAt` in zavrnil manjkajoči dokaz z istim `directory_proof_pending`.
Pripravljen ozki popravek v `session_crypto_access.dart` ohrani helperjev
privzeti `online=false`; samo dva običajna klica posredujeta svoj obstoječi
`online`, `directoryAt` pa ga uporabi. Frozen in drugi klici ostanejo na
prejšnji privzeti meji. Ne gre za sprostitev preverjanja podpisov, pinov ali
razvejane zgodovine.

[Štiri nove ozke kontrole](../build/qa/jivie-mobile-readiness-20261020/ios/invitation-anchor-fix-20261020/fixed-attempt3.log)
so PASS v tretjem source poskusu: online hladen zgodovinski prefix,
offline zavrnitev brez HTTP, ponarejen podpis in fork. Prvi source tek je
obstal zaradi manjkajočega `pinRoot` v fixture
(`directory_freshness_pending`); drugi na stari kodi potrdi pravi
`CryptoAuthorityPending(directory_proof_pending)`; tretji s popravkom
potrdi štiri PASS. Pozitivni primer se namerno ustavi pri `headGet`
sentinel izjemi po dveh preverjenih directory branjih: dokazuje prehod
anchor meje, **ne celotnega resume, ključev ali native prikaza vsebine**.
Neodvisni Android in glavni pregled popravka ter diff-check so PASS.
Finalni [kandidatov paket](../build/qa/jivie-mobile-readiness-20261020/ios/invitation-anchor-fix-20261020/candidate/artifact-evidence.json)
SHA-256 `a08bfa240fbf5e56d6d88199f0993219e7584a96dd27ad60f544cc5bcb829a54`
je zgrajen in glavno/neodvisno pregledan PASS. Poleg anchor popravka
vsebuje že pregledani `sharing_members` void callback popravek ter v2
build/cache oznako, ki ohrani prvotno v1 diagnostiko. SDK/locks/TLS/podpis
so isti, nepodpisani sodium/sqlite3mc sta bajtno enaka.
[Ena namestitev ob 16:55:20 UTC](../build/qa/jivie-mobile-readiness-20261020/ios/native-continuation-attempt3-20261020/installation-evidence.json)
ohrani štiri vault datoteke (1.802.630 B), novo zasebno kopijo in iste
varne storage identitete; Keychain ni bran ali spremenjen. Pred kopijo je
bil opažen stari 6051f146 proces neznanega izvora; priprava se je ustavila,
root je potrdil odsotnost sočasnega UI in proces je bil normalno zaprt.
Tega opažanja ne štejemo za dokaz novega funkcionalnega poskusa.
Strežniško okno 8 je potrjeno ob 16:55:41 UTC pred enim običajnim zagonom
ob 16:55:49 UTC, PID 1170. Samodejni resume po enem root/CUA Continue se je dejansko izvedel kot
**zadnji native poskus 3 iste težave in FAIL**. [V2 trajni dokaz](../build/qa/jivie-mobile-readiness-20261020/ios/native-continuation-attempt3-20261020/durable-metadata-result.json)
ponovno pokaže `preview_resume_accepted`, `CryptoAuthorityPending`,
`directory_proof_pending`. Source anchor kontrole ostanejo štiri PASS,
vendar **popravek ni odpravil potrjene native meje**; ne trdimo rešene
native napake ali dokazanega celotnega vzroka. Dosežena je izrecna meja
treh native poskusov: nadaljevanje označimo FAIL/SKIP, odvisno B branje,
dvosmerno deljenje, lokalno ločenost po deljenju, finančno članstvo/pravice
in saldo ter offline/odvzem pa BLOCKED.
Ni četrtega Retry, builda, novega popravnega kroga, novega računa/fixture,
ponovnega Join ali owner granta. Source števec je ločen od native
nadaljevanja (zdaj trije izvedeni poskusi iste težave).

[Končni iOS izid](../build/qa/jivie-mobile-readiness-20261020/ios/native-continuation-attempt3-20261020/outcome.json)
loči trajni dokaz napake od konzolnega zajema: zadnji pasivni zajem je
trajal 114,478 s in prejel nič dovoljenih NET oznak, zato povezanost
konzole v tem zadnjem procesu ni potrjena. Dejanska koda napake je
preverjena v dveh fiksnih v2 cache datotekah, ne iz odsotnosti konzolnih
oznak. Zgodnejši uspešni pasivni zajem 47 oznak ostane ločen dokaz.
iOS PID 1170 je normalno zaprt s SIGTERM in potrjeno odsoten ob
**16:57:20 UTC**; Android QA PID 6237 je force-stopped in potrjeno odsoten
ob **16:57:24.073360 UTC**. Ciljana sta samo točna QA paketa, podatki/seji,
FILE in nameščena paketa ostanejo ohranjeni. Ni odjave, brisanja ali novega
account/auth/grant dejanja.

Produkcija, originalni trgovinski aplikaciji, Mac 18811 in benchmark 59776
ostanejo nedotaknjeni. Aktivni QA podatki in FILE so ohranjeni; običajno
delo aplikacije lahko zapisuje lastne metapodatke. Pri vsaki težavi velja
isti števec največ treh poskusov: ob tretjem neuspehu dokaz in SKIP/BLOCKED,
brez novega računa, fixture ali ponastavitve števca. Uspešnih starih scenarijev
ne ponavljamo. Potrjeni Android bootstrap, običajni samodejni sync in en owner grant
ostanejo PASS. Po tretjem iOS neuspehu so odvisni B prikaz ter mobilno
nadaljevanje BLOCKED/SKIP; mobile/P0/P8 in produkcijska pripravljenost
ostajajo odprti.
