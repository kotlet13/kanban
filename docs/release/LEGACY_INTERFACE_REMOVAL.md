# Odstranitev starega vmesnika — 11. oktober 2026

Uporabnik je naročil zaključek odstranitve starega uporabniškega vmesnika in njegovih
odvisnosti ter združitev na main. Jivie ima zdaj samo lokalni organizer in izbirno
sodelovanje prek FamilyHub. Različica ostane 1.3.2+17; to ni nova trgovinska izdaja.

## Izvedba

- Odstranjeni vsi stari zasloni v `lib/features/`, Kanboard JSON-RPC odjemalec,
  Kanboard/finančni modeli, stari cache/credential/default storage in providerji.
- Odstranjene poti `/launch`, `/connect`, `/projects`, `/settings/project-defaults`
  in vse `/board/*`, vključno z že odstranjenim AI. Nastavitve nimajo več razdelka
  »Obstoječi Kanboard«. Novi račun/deljenje in Nastavitve prostora ostanejo.
- Glavni razred je `JivieApp`; tema in jezik sta v
  `organizer/state/app_preferences_provider.dart`, z istimi shranjenimi ključi.
- Mrtvi prevodi so odstranjeni, lokalizacija regenerirana. Odstranjeni so testi
  ukinjenih funkcij; nove regresije preverjajo resnični novi UI in seje.
- Odstranjeni open_filex 4.7.0, qr_flutter 4.1.0 in prehodni qr 3.0.2.
  Preostali lock zapisi/checksumi in SDK meje so nespremenjeni. iOS Podfile.lock
  izgubi le open_filex 0.0.2; CocoaPods registracija je preverjena.
- Stari icon1/icon2 sta odstranjena. Linuxova ikona uporablja dejanski vključeni
  `assets/branding/jivie/icon-master.png` ob izvršljivi datoteki.

Hive ostane potreben za lokalno shrambo/migracijo organizerja. Cupertino icon font
uporablja Apple prikaz napake navigacije. Imena `.vsakdan`, sheme, SQLite/Hive boxi,
native kanali in namizne identitete ostanejo zaradi podatkovne združljivosti.
Windows ProductName se ne preimenuje: path_provider in secure storage ga uporabljata
za obstoječe podatkovne poti. Ob zagonu, novih FamilyHub sejah ali odjavi se stari
računi, AI ključi in zgodovine ne berejo ali brišejo.

FamilyHub in gostiteljski Kanboard ostaneta strežniška osnova novega sodelovanja;
njune tabele, račun in predogled izbrisa niso stari mobilni uporabniški vmesnik.
Strežniški izbris še vedno pravilno razkrije odvisnosti obstoječega računa.

## Preverjanje

- Celoten Flutter sklop: **942 PASS / 13 opt-in HTTP preskočenih**.
- Ciljna 94 + 9 preverjanja: lokalni CRUD/finance, SL/EN 320/390/1280, Android Nazaj,
  kopije/nastavitve/ponovni zagon, pravi FamilyHub kontroler/providerji, izolacija sej
  ter vse odstranjene poti pri ohranjenih starih nastavitvah.
- Celotna analiza: **No issues found**. Neodvisen izvorni pregled brez pomembnih
  ugotovitev; lokalni importi in odstranjeni prevodi nimajo preostalih uporab.
- 23 Python izdajnih/paketnih testov, source checker in JS deletion-link PASS.
- Android release AAB, web release in iOS simulator gradnja PASS.
- macOS Debug arm64 v ločenem DerivedData: BUILD SUCCEEDED. Prvi običajni Flutter
  build je naletel na stare native module Firebase v skupni izhodni mapi;
  čista izolirana gradnja uspe brez spremembe SDK ali native odvisnosti.
- Dejanski spletni prikaz nove gradnje: prazen lokalni začetek, nastavitve, preklop
  SL/EN in svetle/temne teme ter širini 390 px/namizje PASS. Brez starih menijev.

Preverjevalni AAB ima 75.600.308 bajtov, SHA256
`f92e1577d31c9e1c1c9cb78d1041317255890e86db566014b3a3943c9d72e3f3`.
Končni dekodirani manifest nima širokih storage/media dovoljenj ali open_filex
FileProvider. Obvestila/FCM in share_plus FileProvider so ohranjeni.
Bundletool validate PASS. 239 Dart/ARB/odvisnostnih hashov je shranjenih ob artefaktu;
ta omejeni inventar ni celoten izdajni manifest. AAB pod isto različico je lokalni
preverjevalni artefakt, ni nova Play kandidatka.

Dokazi, gradnje, manifest in posnetki so v ignorirani
`build/qa/legacy-interface-removal-20261011/`. Stare izdane/frozen gradnje so ohranjene.
macOS/iOS gradnji ne dokazujeta distribucijskega podpisa ali fizičnih tokov.
Linux/Windows runtime ni preizkušen. UGC, popolnost obnove/priponk, novi fizični
mobilni preizkusi in končne trgovinske deklaracije ostajajo ločeno delo.
Spletna zasebnost je že objavljena brez AI/razvojnega odstavka; ta odstranitev ne
zahteva nove objave istih spletnih datotek.
