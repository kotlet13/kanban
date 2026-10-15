# Jivie1.9.0(28) — pripravljeno, oddaji še sledita

15. oktober2026. Uporabnik naroča javniAndroid in iOSTestFlight, brez javne
iOSoddaje. Windows/Linuxnative delo je odloženo. [Izvedba](../UPGRADE_IMPLEMENTATION.md).

## Končni izvor in paketi

Runtime **6ce59cf3958dbf5c7f5bc7b0e788049c0508b412**, main/push.
421zamrznjenih runtime/native vhodov,308skupnih; agregat
`3f403c42f2c1cf3ea4ed4d38a99119fb250c05c0a49e3879b0d94cbf7695296c`.
V primerjavi z vmesnim7af so spremenjene samo tri runtime datoteke: scheduler,
adapter in sharing_workspace. Nativekonfiguracije/3locks/SDK/Firebase isti.

- Android `build/releases/Jivie-1.9.0+28-android-firebase.aab`:80226012bajtov,
  SHA256`347d6d8b1a25c61c846a84c73d1112c8a6e41c6cd71dcb2bf36b64650fd3c61c`.
  Podpis/certifikat/bundletool/CRC/8dovoljenj/3ABIengine/Firebase/16KiBPASS.
- iOS `build/qa/upgrade-release-20261014/source/build/ios/archive/Runner.xcarchive`:
 216181591bajtov/213datotek, strictdeepsign/identiteta/Firebase/18privacyPASS.
 CLIexportNoAccounts; **StoreIPAše ni izvožen ali naložen**. ObičajniXcode
 Organizer uporablja obstoječecloud podpisovanje, brez novihključev/profilov.
- macOS `build/qa/upgrade-release-20261014/macos/DerivedData/Build/Products/Debug/Jivie.app`:
 svežiDerivedData/arm64PASS, namiznicom.example.kanbanohranjen, nepodpisan/nezagnan.

Dejansko3gradnje na platformo.8500f75 in7af sta ohranjena v rejected mapah
skupaj z izvorom/logi/razlogom; noben kandidat ni bil naložen. Samo6ceje veljaven.
Dokazi v ignorirani `build/qa/upgrade-release-20261014/local-release-evidence.json`.

## Preverjanje

CelotniFlutter7af:1298PASS/15izrecnihopt-inpreskokov. Končne tri runtime
spremembe:62postavitvenih in27scheduler/adapter/coordinatorpreverjanjPASS.
Končnaanaliza6ce:10prejšnjih informacijskih ugotovitev v orodjih,0warning/error.
Sourcechecker/23izdajnih/7FirebasePASS. Žive naprave in novaOSobvestila niso
fizično potrjeni.

## Živo gostovanje in prekinitev

[Strežniški zapis](../server/UPGRADE_0_14.md) potrjuje produkcijskipredhodni
zajem/dosledno92tabel319vrstic2DATAkopijo. Brave zavrne prenosZIP-a, Mac
se zaklene. IzoliranaobnovaNIcončana; nobenstage/migracija/CodeSwapni izveden.
Varovana vrnitev izvirne produkcije je potrjena22:21:27UTC14okt:
API200/istiSID/schema17/old96/configključi/originalcron. Vse zasebne kopije
in prekinjene vhodne mape ostanejo. Ni nadaljevanja s to staroabortmapo;
potrebni novi sveži capture/pause/kopija, nato resnična izoliranaobnova.
Test1 je še ločen izdajni korak, test2ostaja zunaj tega postopka.

## Portala

Svež read-onlyGooglePlay potrdi **1.8.0(27), Na voljo vGoogluPlay**,
release3/100%/1država,14okt21:42. Prejšnje pending27 je zgodovina.
**28 še ni naložen ali oddan**. Interna izdaja ni ustvarjena/ponovno vključena.
iOS28še ni izvožen/AppleComplete/TestFlightTesting. Prejšnja26ostane.
Ob odklenitviMac nadaljevati: preverjeno gostovanje -> javniAndroid28,
XcodeStoreexport/strictIPAverifier/ASCComplete/encryptionstandard+FranceNo
-> obstoječiTestFlightPredjavnoobjavo z ohranjenimi starejšimi gradnjami.
JavneAppStoreoddaje ne izvajati.


## Novi trgovinski posnetki

15. oktobra je uporabnik izrecno naročil nove zajeme med čakanjem na
odklenitev Maca. Pripravljenih je **48 slik**: osem prizorov v slovenščini
in angleščini za Android telefon, iPhone in iPad. Prizori so Utrip, opravila,
koledar, odprta tabla Idejnika, projekt z mejniki, nakupovalni seznam z vnosom
artikla in količine, novi celozaslonski Vrt ter finance. iPad ohrani dejansko
širšo postavitev s stransko navigacijo.

Gre za izrise dejanskih gradnikov končnega runtime izvora 6ce59cf z ločenimi
vzorčnimi podatki v pomnilniku. To niso fizični zajemi naprav ali dokaz
sistemske tipkovnice/statusne vrstice. Fotografija v Idejniku je obstoječi
preverjeni slikovni vzorec. Slike niso naknadno grafično spreminjane.
Vrt uporablja pravi potisnjeni MaterialPageRoute z možnostjo vrnitve;
zajemi uporabljajo običajne sence in platformne pisave.

Vsak od treh sklopov ima šest uspešnih capture preizkusov in čisto ciljno
analizo. Vseh 48 slik je vizualno pregledanih. Validator potrdi dimenzije
720×1280, 1320×2868 in 2064×2752, popolno neprosojnost, različne slike za
vsako napravo/jezik/prizor ter vseh 421 nespremenjenih izdajnih vhodov.
Aplikacije, odvisnosti, različice in obstoječi izdajni paketi niso spremenjeni.

PNG-i so v `build/qa/upgrade-store-20261015`;
[manifest s hashi in vrstnim redom](UPGRADE_SCREENSHOTS_1_9.json) je shranjen
v repozitoriju. Paket `build/releases/Jivie-1.9.0+28-store-screenshots.zip`
ima 48 PNG-jev in manifest, CRC je preverjen. SHA256:
`a8a342e4a67c2c655f74c0b46ba147d9158e8c9b024c7fe94ee6b9aec355e4ca`.
Posnetki še niso naloženi v Google Play ali App Store Connect.
