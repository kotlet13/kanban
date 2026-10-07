# Jivie: platformna priprava

Stanje lokalne priprave 7. oktobra 2026. Končni mobilni ID je `si.triparna.jivie`. Novi evidenci trgovin sta ustvarjeni; [aktualno stanje testnih izdaj](TEST_RELEASE_STATUS.md) loči lokalno pripravo, konzoli, podpisovanje in dejanske prenose. Zgodovinska preverjanja spodaj ne potrjujejo svežih paketov tega ID ali fizične dostave obvestil.

## Mobilni identiteti

- Android `namespace` in `applicationId`: `si.triparna.jivie`; aktivnost je v paketu `si.triparna.jivie`. Vidno ime je **Jivie**. Stara aplikacija `com.takndev.kanbanconnect` ima drugo namestitev in podatkovno območje.
- iOS Runner uporablja `si.triparna.jivie` v Debug, Profile in Release; RunnerTests uporablja `si.triparna.jivie.RunnerTests`. `CFBundleDisplayName` in `CFBundleName` sta **Jivie**. Predhodni lokalni iOS projekt je uporabljal `com.example.kanban`, ne Androidovega produkcijskega identifikatorja.
- Nova mobilna namestitev samodejno ne vidi baze ali varne shrambe starega ID-ja. Ta sprememba ničesar ne izbriše; uporabnik lahko podatke prenese z obstoječim izvozom in obnovo. Tehnični format `.vsakdan` ostane združljiv.
- Android, iOS in macOS deklarirajo povabila `jivie://invite`; razvojna povabila `vsakdan://invite` ostanejo podprta. Dart preveri vsebino povezave in pravice. Lastništvo sheme samo po sebi ni preverjanje povabila; druge aplikacije lahko registrirajo enako zasebno shemo.
- Interni kanal `vsakdan/remote_push_readiness` ostane nespremenjen. Firebase/APNs konfiguracija mora pripadati novemu mobilnemu ID-ju; uspešno prevajanje ni dokaz dostave.

## Podpisovanje Android

Gradle bere samo lokalni `android/jivie-key.properties`. Predloga je v [`android/jivie-key.properties.example`](../../android/jivie-key.properties.example). Obstoječi `android/key.properties` in njegov ključ ostaneta nedotaknjena ter se za Jivie ne uporabita samodejno.

Release potrebuje `applicationId=si.triparna.jivie`, neprazne `storeFile`, `storePassword`, `keyAlias` in `keyPassword` ter obstoječo datoteko keystore. Naloga `validateReleaseSigning` se izvede pred `preReleaseBuild`. Rezervno podpisovanje z debug ključem ni omogočeno. Dejanske geselske datoteke in keystori so ignorirani. Predloga ni veljaven podpis. Po uporabnikovem naročilu testnih izdaj je pripravljen ločen lokalni Jivie upload key (RSA 3072, PKCS12), zasebna mapa 0700/datoteke 0600; stari ključ ni bil prebran ali uporabljen. Končna podpisana AAB in Play App Signing se preverita ločeno.

Android `targetSdk` je izrecno 36. Trenutni lokalni Flutter SDK ima tudi `compileSdkVersion=36`; Gradle za prevajalni SDK še naprej uporablja Flutterjevo vrednost. Različica aplikacije ni zvišana s platformno prenovo.

## Podpisovanje Apple

Uporabnik je potrdil izdajatelja TriparNA; `DEVELOPMENT_TEAM=CXNM99632B` je nastavljen za vse iOS Runner/RunnerTests konfiguracije. Zasebni Apple ključi niso bili izvoženi ali prebrani. Pregled javnih metapodatkov lokalnih podpisnih potrdil je pokazal razvojni ekipi:

| Ekipa | Team ID | Lokalno potrdilo |
| --- | --- | --- |
| Anze Novsak | `P5N4497MLX` | Apple Development |
| TriparNA z.o.o. | `CXNM99632B` | Apple Development |

Pred novo Xcode prijavo so bili lokalni profili preverjeni za druge aplikacije (`si.triparna.huesky`, `com.triparna.drozer`); to niso bili profili Jivie. Po uporabnikovi dejanski prijavi 7. oktobra 2026 je root v Xcode preveril račun Anže Novšak ter ekipo TriparNA z.o.o. z vlogo Admin. App ID `si.triparna.jivie` ima v portalu Push Notifications; ustvarjena je tudi nova App Store Connect evidenca Jivie.

V vseh treh Runner konfiguracijah je vključeno samodejno podpisovanje z ekipo `CXNM99632B` in `CODE_SIGN_ENTITLEMENTS=Runner/RemotePush.entitlements`. Vir določa `APNS_ENVIRONMENT=development` za Debug in `production` za Release/Profile. To sta projektni nastavitvi; dejansko podpisano okolje se preveri skupaj s profilom. Nobena nastavitev `ITSAppUsesNonExemptEncryption` ni bila dodana ali ugibana.

Sveži `flutter build ipa --release --dart-define-from-file=.firebase/client.json` je uspešen. Arhiv `build/ios/archive/Runner.xcarchive` vsebuje `si.triparna.jivie`, različico `1.0.0`, build `1`, SDK `iphoneos27.0` in Xcode build `27A266a`. Podpisan je z obstoječim **Apple Development: Anze Novsak (NK77P772M5)**, ekipa `CXNM99632B`; njegov razvojni profil Jivie ima `aps-environment=development` ter `get-task-allow=true`. To je podpisan razvojni arhiv, ki ga lahko Xcode Organizer uporabi za distribucijo.

Izvoz App Store IPA je prav tako uspel: `build/releases/Jivie-1.0.0+1-ios-firebase.ipa` (27.901.711 bajtov), SHA256 `2a5311d17267d21442fc967e9ebe902c8fb63b5f08cb1450f2c2433b9e63904a`. Paket ima podpis **Apple Distribution: TriparNA z.o.o. (CXNM99632B)** z že obstoječim potrdilom, izdanim 26. septembra 2026 in veljavnim do 26. septembra 2027. SHA256 certifikata je `EF:95:BA:6F:FD:E1:F8:89:83:EE:41:92:B2:18:6B:6A:C6:E7:CF:2D:15:C3:53:44:C0:57:8F:8F:97:96:7E:06`. Novi Store provisioning profil Jivie določa `aps-environment=production`, `get-task-allow=false`, pravi application ID in ekipo. `codesign --verify --deep --strict` potrdi razvojno in izvoženo aplikacijo. Lokalni seznam uporabnih podpisnih identitet ima pred in po postopku isti dve razvojni identiteti; novega lokalnega certifikata/CSR ali preklica ni bilo. Podpis je uporabil že obstoječe distribucijsko potrdilo, brez izvoza zasebnega ključa. [Apple dokumentacija za cloud-managed certifikate](https://developer.apple.com/help/account/certificates/cloud-managed-certificates) opisuje njihovo uporabo v distribucijskem postopku.

Javno lokalno dokazilo brez napravnih ID-jev ali poverilnic je `build/qa/garden-release/ios-firebase-artifact-evidence.json`. Profila sta bila pregledana brez izpisa celotne vsebine. Flutterjev pregled opozori na privzeto launch-image predlogo; arhiviranje in izvoz sta kljub temu uspešna. Izidi oddaje, obdelave in TestFlight se vodijo v [evidenci testnih izdaj](TEST_RELEASE_STATUS.md). Klasifikacija šifriranja, zbirno poročilo zasebnosti ter dejanska FCM/APNs dostava ostanejo ločeni dokazi.

## Namizje in splet

macOS produkt, `.app`, Xcode shema, testni gostitelj in prikaz so **Jivie**, bundle ID pa ostane `com.example.kanban`. Tako se ne preseli obstoječi sandbox ali Keychain. To ni predlog identifikatorja za novo izdajo v Mac App Store. Za ločeno namizno aplikacijo je potreben načrt prenosa lokalnih podatkov in poverilnic.

Windows naslov okna in opis sta **Jivie**, izvršljiva datoteka pa `jivie.exe`. Tehnična `CompanyName=com.example` in `ProductName=kanban` ostaneta, ker nameščena `path_provider_windows` in `flutter_secure_storage_windows` iz njiju določita lokacijo obstoječe shrambe. Zato lahko stari tehnični naziv še ostane v lastnostih datoteke. Odločitev o ločeni namizni shrambi potrebuje izrecno migracijo.

Linux naslov okna je **Jivie**, izvršljiva datoteka `jivie`; `APPLICATION_ID=com.example.kanban` ostane zaradi lokacije aplikacijske shrambe. Prenos starega imenika, ki ga je nekoč določalo ime izvršljive datoteke, zunaj običajnega `path_provider_linux` prehoda ni bil fizično preverjen. Windows in Linux nista prevedena na tem macOS računalniku.

Spletni naslov, PWA ime in opis so Jivie. Sprememba imena ne spreminja spletnega izvora, baze IndexedDB ali vsebine lokalne shrambe. Šele nov izvor pomeni ločeno shrambo; izbira in gostovanje izvora nista del tega koraka.

## Zasebnost in dovoljenja

Odstranjena je zastarela iOS razlaga dostopa do kamere, ki je govorila o skeniranju in uvozu poverilnic. V trenutnih odvisnostih ni kamera/skener paketa ali delujočega takšnega uporabniškega toka. Morebitni prihodnji skener potrebuje novo dejansko dovoljenje in lokalizirano razlago.

Lokalni opomniki in izbirni push ohranijo obstoječa dovoljenja/registracije. Native koda ne dodaja analitike ali samodejnega zagona Firebase. Manifesti zasebnosti nameščenih pluginov obstajajo za `flutter_secure_storage`, `file_picker`, `path_provider_foundation` in `shared_preferences_foundation`; v preverjeni nepodpisani iOS release gradnji je 28 paketnih manifestov. Pred oddajo je še potreben pregled zbirnega poročila zasebnosti iz končnega distribucijskega arhiva. To ni dokončan App Privacy odgovor ali politika zasebnosti za trgovino. Zbiranje podatkov je odvisno tudi od izbirne sinhronizacije, obvestil in AI nastavitev; odgovorov ne izpolnjuj zgolj iz praznega aplikacijskega manifesta.

## Preverjanje

- `plutil -lint` za oba `project.pbxproj`: uspešno.
- Python `plistlib`, XML in JSON pregled platformnih datotek: uspešno; preverjeni obe shemi, prikaz Jivie ter trije iOS Runner in trije RunnerTests ID-ji.
- `git check-ignore` potrdi ignoriranje obeh lokalnih Android podpisnih nastavitev.
- `git diff --check`: uspešno ob platformni spremembi.

Zgodovinsko mobilno preverjanje po pripravi ikon, pred dokončno izbiro `si.triparna.jivie` (predhodni ID `com.takndev.jivie`):

- `:app:validateReleaseSigning` in `:app:preReleaseBuild`: pričakovana zavrnitev zaradi manjkajočega ločenega `android/jivie-key.properties`. Drugi ukaz potrjuje, da preverjanje podpisa ni samo samostojna naloga, temveč varuje začetek release gradnje.
- `flutter build apk --debug`: uspešno. `aapt2` pregleda dejanski paket: ID `com.takndev.jivie`, ime Jivie, aktivnost `com.takndev.jivie.MainActivity`, različica `1.0.0` (1), cilj in prevajalni SDK 36, obe shemi povabil ter prilagodljiva ikona s foreground in monochrome različicama. Pregledane mere vseh zapakiranih PNG ikon; izluščena launcher ikona je bila tudi vizualno pregledana.
- `flutter build ios --release --no-codesign`: uspešno, 31,4 MB. Pregled dejanskega `Runner.app/Info.plist` potrdi Jivie/nov ID/različico, obe shemi, minimum iOS 15 in SDK `iphoneos27.0`. Podpisna mapa `_CodeSignature` manjka, kot zahteva nepodpisana gradnja. `assetutil` potrdi neprosojne AppIcon različice, vključno z 1024 × 1024 marketing ikono.
- `flutter build ios --simulator --debug`: uspešno. Aplikacija je nameščena in zagnana na iPhone 17 simulatorju z iOS 27.0. Vizualni pregled pokaže ime in ikono Jivie ter začetni zaslon brez računa s praznimi stanji. To je preverjanje začetnega zagona, ne vseh lokalnih ali skupnih uporabniških tokov. Morebitni sistemski napis »Nazaj v Kanban« pripada prej odprti aplikaciji v simulatorju; dejanski aktivni paket je `com.takndev.jivie`.
- `flutter doctor -v`: brez težav. Neposredni zagon Gradle je sprva zavrnil zastarelo okoljsko pot `JAVA_HOME`; uporabljen je bil samo ukazni popravek na `/Applications/Android Studio.app/Contents/jbr/Contents/Home`, brez spremembe uporabnikovih nastavitev.

Lokalni dnevniki, pregled pakiranja in posnetek simulatorja so v ignorirani mapi `build/qa/jivie-release/`. Razvojni APK in nepodpisani iOS paket nista artefakta za oddajo v trgovino. Gradle opozarja na prihodnjo opustitev podpore različicam Gradle 8.14, AGP 8.11.1 in Kotlin 2.2.20; iOS opozarja, da `flutter_secure_storage` in `open_filex` še uporabljata CocoaPods namesto Swift Package Manager. Neodvisna nadgradnja ni bila izvedena. iOS runtime potrdi manjkajočo konfiguracijo Firebase, kar ustreza neaktivnemu izbirnemu push kanalu; fizična dostava ostaja nepreverjena. Windows in Linux nista bila zgrajena.

Skupni končni pregled je dodatno uspešno zgradil macOS debug `Jivie.app` in spletni JavaScript release. Izhodni macOS plist ohrani podatkovni bundle ID, spletni naslov/manifest pa novo znamko; oba paketa vsebujeta novo ikono. macOS uporablja obstoječi CocoaPods za tri plugine, spletni Wasm dry-run ostaja neuspešen zaradi obstoječega `flutter_secure_storage_web`. [Skupna evidenca](README.md).
