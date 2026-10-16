# Android 1.10.1 (31) — povečava preglednic in pomoč

16. oktober 2026. Uporabnik izrecno naroči novo Google Play oddajo po izvedbi
[povečave in pomoči](../SPREADSHEET_ZOOM_HELP.md). Cilj je samo javni Android
kanal; interni kanal in Apple ostajata odložena. Strežnik ni spremenjen.
**Nova javna izdaja 1.10.1 (31) je dejansko oddana v Google Play.**
Console potrdi »1 sprememba je bila poslana v pregled« in »Spremembe v pregledu«.
Hitra samodejna preverjanja še tečejo. Upravljano objavljanje je izklopljeno;
objava sledi odobritvi. **Odobritev ali javna dostopnost31 še nista potrjeni**;
predhodna30 ostaja javno aktivna.

## Izvor in preverjanje

Ločen zamrznjen izvor:
`build/qa/spreadsheet-zoom-release-20261016-final/source`.
Osnova `5fe4fdf`, s popisanim version popravkom na **1.10.1+31**. Manifest
vsebuje 443 javnih runtime/native vhodov, 330 skupnih lib/assets/pubspec/l10n.
Agregat SHA256:
`15cfd77ecc601019cb1f27fb776f39414a7f5c3875c573bf7c161ad685bfec38`.
Proti AAB30 so spremenjeni trije vhodi (mreža, besedila in različica), dodana
je pomoč. Native Android/iOS/macOS, SDK, trije locks in tri konfiguracije so isti.
Manifest pred preverjanjem paketa ponovno potrdi bajte vseh vhodov.

70 ciljnih Flutter preizkusov v dejanskem izoliranem izvoru PASS: povečava,
poravnava oznak, drsenje/izbira/vnos po potezi, preklic/tretji prst, pomoč,
formule/TSV, obstoječe postavitve, meja izdajnega obsega in Firebase konfiguracija.
23 Python release in 7 Firebase kontrol PASS; source checker PASS, ciljna
izolirana analiza brez ugotovitev. Celotni nabor in strežniške migracije
niso ponovno izvedeni za ta ozki aplikacijski popravek.

## Podpisani paket

Ena nova podpisana gradnja iz navedenega izvora:
`build/releases/Jivie-1.10.1+31-android-firebase.aab`.
81.312.731 bajtov; SHA256:
`1ecce6df000ea69f53db8d19fab323e6d58850fda6784b107634dc60b0fb5c29`.
Prejšnji AAB30 ostane ohranjen. Bundletool validate, ZIP CRC in podpis PASS;
isti obstoječi upload certifikat, package si.triparna.jivie, API24/36,
non-debuggable, isti zasebni ShareFileProvider in istih 8 dovoljenj.
Native/Dart Firebase identitete potrjene, brez podpisnih ali strežniških
skrivnosti v arhivu. Vsi Flutter engine in drugi ne-aplikacijski .so bajti
so enaki AAB30; 8 64-bitnih knjižnic ima 16KiB LOAD poravnavo, bundle zahteva
PAGE_ALIGNMENT_16K. To ne potrjuje fizičnega 16KiB zagona.

Google pri prejšnji30 že kaže opozorilo za starejši DataStore RELRO.
Obe zadevni knjižnici sta bajtno isti30; ta izdaja ne spreminja native SDK
ali knjižnic. Prejšnja presoja je v [izdaji30](INVITATIONS_DOCUMENTS_1_10.md).

## Google Play

Svež pregled je potrdil javno30 Aktivno/1država in brez neobjavljenih sprememb.
Nov javni osnutek: production4698247597354229997/release7. Naložen je AAB31,
pripravljeni sta SL/en-US [opombi](SPREADSHEET_ZOOM_1_10_1_NOTES.json).
Končna oddaja je potrjena v Console; izid Googlovega pregleda še sledi.
Galerije, opisi, Data safety, države, splet, gostovanja in Apple niso spremenjeni.

31 je vključena,30 izključena iz nove izdaje; uvajanje100%, iste ciljne države
(prej potrjena1država/Slovenija),0izgubljenih ali novih podprtih naprav.
Končni gumb »Pošljite spremembe v pregled« je pritisnjen za natanko eno
spremembo. Končno stanje potrjuje play-release-evidence.json in
play-submitted.jpg v QA mapi; ni dodatne interne izdaje ali fizične namestitve.

Glavni lokalni dokazi: source-input-manifest.json, source-diff-from-30.json,
isolated-feature-tests.log, release-tests.log, firebase-tests.log,
source-check.log, isolated-runtime-analysis.log ter android/build.log,
verification.log, android-release-artifact-evidence.json in
native-libraries-vs-30.json v navedeni QA mapi.
