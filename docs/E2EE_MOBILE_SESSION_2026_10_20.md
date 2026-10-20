# Skupno mobilno nadaljevanje — 20. oktober 2026

**Aktualni checkpoint: obe testni aplikaciji sta posodobljeni; Android
bootstrap in en običajni samodejni sync po povezavi Wi-Fi sta PASS.
Lastnikova odobritev in predaja parent/child ključev sta strežniško PASS;
iOS prvo nadaljevanje je pokazalo generično napako neznanega vzroka.
Dejansko B branje skupne vsebine še čaka.** Po vrnitvi
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
B branje ostaja ločeno preverjanje.

| Preverjanje | Dejanski izid in meja |
| --- | --- |
| Android namestitev | PASS v prvem poskusu: en `install -r`, isti QA ID/podpis/dataDir; predhodna zasebna kopija ohranjena. |
| iOS namestitev | PASS v prvem poskusu: isti QA bundle/storage service/group; šifrirani vault ima pred/po iste hashe. Sistem je zamenjal pot podatkovnega vsebnika, ne vsebine vaulta. |
| Android prvi zagon | FAIL pri težavi zagona, poskus 1: `PlatformException`, `channel-error` za `PathProviderApi.getApplicationDocumentsPath`; faza bootstrap `null`. Pakirni vzrok potrjen, brez dokaza napake šifriranih podatkov. |
| Android popravek | Bootstrap PASS v poskusu 2: popravljeni APK je nameščen; po enem običajnem zagonu VM potrdi `ready`, brez izjeme. Uporabnik je potrdil običajni prikaz; poznejši sync je v ločenem zapisu spodaj. |
| iOS zagon / prvo nadaljevanje | Po znanem retained-copy opozorilu in fizičnem Continue isti predogled. Po owner grantu prvo nadaljevanje FAIL z generično napako; vzrok neznan, drugega Retry ni. |
| Prvotno povabilo | Read-only PASS za ohranitev: en isti sprejem 18. oktobra, po owner grantu `consumed`, brez nadomestitve/novega sprejema. |
| Android navadni samodejni sync | PASS po uporabnikovi povezavi Wi-Fi: ni v teku, 0 pending/conflicting/blocked, brez napake; ni ročnega Sync/Retry. |
| Owner grant parent/child | PASS po enem dejansko dostavljenem Confirm: isti sprejem consumed, parent/child active epoch2 in B granti. |
| B branje skupne vsebine | PENDING; ni novega PASS. |

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
Dejanska povezanost konzole zato ostaja nepotrjena, nič oznak pa ne dokazuje
odsotnosti HTTP prometa.

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
sta PASS, brez novega teka testov pri neodvisnem pregledu. To je source
popravek; ni dokaz nove native namestitve tega popravka ali pojasnilo
neznane iOS napake nadaljevanja. Owner granta ne ponavljamo zaradi te regresije.

Produkcija, originalni trgovinski aplikaciji, Mac 18811 in benchmark 59776
ostanejo nedotaknjeni. Aktivni QA podatki in FILE so ohranjeni; običajno
delo aplikacije lahko zapisuje lastne metapodatke. Pri vsaki težavi velja
isti števec največ treh poskusov: ob tretjem neuspehu dokaz in SKIP/BLOCKED,
brez novega računa, fixture ali ponastavitve števca. Uspešnih starih scenarijev
ne ponavljamo. Po potrjenem Android bootstrapu, običajnem samodejnem syncu in enem
uspešnem owner grantu čaka dejansko B branje; mobile/P0/P8 in produkcijska pripravljenost ostajajo odprti.
