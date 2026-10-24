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
