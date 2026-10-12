# Android 1.7.0 (25) — Utrip, Planer in nova podoba

12. oktober 2026. Funkcionalni izvor **50fd551** na main/origin.
[Prenova in funkcionalni dokazi](../UNIFIED_MOBILE_UX.md): **651 testov PASS /
1 opt-in preskok**, čista analiza ter Android debug/iOS simulator gradnji.
Uspešnega funkcionalnega preverjanja med izdajo nismo ponavljali.

Ena podpisana gradnja `build/releases/Jivie-1.7.0+25-android-firebase.aab`,
**78.412.700 bajtov**, SHA256
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447`.
AAB in checksum sta read-only; prejšnji AAB24 je ohranjen.
**320 zamrznjenih vhodov** se ujema pred in po gradnji; agregat
`d12f73f7bba26642e993058ffb150122ab9c9b8d16164f074fbdfe07d002fd6a`.
Zasebna konfiguracija je primerjana le s hashi in je enaka izdaji24.

Namenski upload podpis, native/Dart Firebase identiteta in istih8 dovoljenj
se ujemajo z izdajo24. Manifest `si.triparna.jivie`, min24/target36,
Android Back callback, share FileProvider brez kamere ali širokih storage/media
pravic. Bundletool, ZIP CRC in 16KiB poravnava vseh8 64-bitnih knjižnic PASS.
SDK in zaklenjene odvisnosti so nespremenjeni; skrivni ključi/konfiguracije niso
vključeni v sveženj. **23 izdajnih +7 Firebase kontrol in source checker PASS**.

**Play Console potrjuje Aktivno od 12. oktobra ob21:04**, na voljo notranjim
preizkuševalcem na istem seznamu **domači(15)**. Koda25 vključena,24 izključena
iz nove izdaje;0 izgubljenih/novih podprtih naprav. SL/en-US opombe objavljene.
Račun TriparNA/TaknDevs4991604398202512900, aplikacija4972659047480717992,
interni kanal4701286726300038561.
[Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Dokazi so v `build/qa/unified-ux-release-20261012/android/`:
`source-input-manifest.json`, `android-release-artifact-evidence.json`,
`play-release-evidence.json`, `play-internal-1.7.0-25-active.jpg` in
`play-testers-domaci-15.jpg`. Fizična nadgradnja telefona še ni potrjena.
FamilyHub/gostovanje/podatki/sheme/iOS/Mac/javna mobilna izdaja pri tem niso
spremenjeni.

Po dodatnem uporabnikovem naročilu je spletna predstavitev **dejansko posodobljena**:
8HTML/CSS/7 posnetkov, vseh16 javnih HTTPS200/hash PASS, sveža preverjena zasebna
kopija17 starih datotek in8 nespremenjenih drugih datotek. Vidno besedilo
zasebnosti in izbrisa ostane isto. [Spletni dokazi](../../website/README.md).

Play Console ima dejansko shranjen osnutek z aktualnima SL/en-US opisoma in
6 novimi Android posnetki **720×1280 (9:16)**; angleška objava uporabi novo
privzeto galerijo. Stare slike so ohranjene v knjižnici. Predogledi so dejanski
widget izrisi z izoliranimi vzorčnimi podatki, brez obrezovanja/popravkov vsebine
slikovnih pik ali marketinških prekrivnih napisov. Novi capture4+1 testi PASS,
ciljna analiza posnetkov čista. `play-new-screenshots-saved.jpg` in
`play-listing-evidence.json` dokazujeta shranitev; osnutek ni oddan v javni pregled.
