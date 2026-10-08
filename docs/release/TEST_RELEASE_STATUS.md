# Jivie — stanje testnih izdaj

## Opomniki in Vrt — priprava 1.1.3+6

Funkcionalni commit `10a9e03` vključuje oddaljeno razporejanje in prenovo Vrta. 636 Flutter PASS/9 opt-in HTTP preskočenih, ločeno 2 dejanska HTTP testa; analiza 37 obstoječih info brez napak/opozoril. Po funkcionalnem commitu je izrecno pripravljena različica 1.1.3+6. Nova podpisana gradnja in aktivacija še sledita. [Izvedba in preverjanje](../REMOTE_REMINDERS.md), [Vrt](../GARDEN.md).

## Kompaktna glava — aktivna 1.1.2+5

Premik prostora ob ikono, naziv Jivie v meniju in + Nov prostor so v funkcionalnem commitu/pushu `3d504c4`. Končni nabor 565 PASS/8 opt-in HTTP preskočenih; analiza brez napak/opozoril s 37 obstoječimi info. Izrecni dvig sledi šele po funkcionalnem commitu. Podpisana gradnja in Play aktivacija sta potrjeni: Aktivno/1.1.2 (5), na voljo internim preizkuševalcem, 8. oktobra ob 17:39. Domači (15) ostaja izbrani seznam. SHA256 AAB `9c449f5363f24b3f2346b18102e3c4378b6872b27de48f419d6ef7cafe810786`; manifest, isti upload podpis, ZIP/bundletool, vseh 8 16KiB knjižnic in native Firebase so preverjeni. Dokaz `build/qa/jivie-compact-header/play-internal-1.1.2-5-active.jpg`. Fizični novi prikaz še ni preverjen. [Dokazi in predogled](../UPGRADE_IMPLEMENTATION.md).

## Dopolnitve 8. oktobra — aktivna 1.1.1+4

Šest dopolnitev iz uporabniškega pregleda je v commitu/pushu `cbcb29d`; 544 Flutter PASS, analiza brez napak/opozoril s 37 obstoječimi info. Kandidatka uporablja isti ID in upload ključ. Podpisana gradnja, upload in aktivacija so potrjeni: Play kaže Aktivno/1.1.1 (4), na voljo notranjim preizkuševalcem, 8. oktobra ob15:03. Domači (15) ostane izbrana skupina. Dokaz: `build/qa/jivie-followup/play-internal-1.1.1-4-active.jpg`. SHA256 novega AAB je `16bc3d8013401c1c9bf24bd6354c70e1e3c710df0e71c0e25853aa4f286c5f1f`; isti upload certifikat, ZIP/bundle/16KiB in native Firebase so preverjeni. Fizična namestitev nove gradnje še ni preverjena. [Aktualni dokazi](../UPGRADE_IMPLEMENTATION.md).

## Nadgradnja 8. oktobra — 1.1.0+3

Popravki `54f3061` in nadgradnje `e73cd1c` so poslani v Git. Svež Android AAB 1.1.0 (3) uporablja isti namenski Jivie upload certifikat, ID `si.triparna.jivie`, API24+/target36 in 16KiB poravnavo osmih 64-bitnih knjižnic. SHA256 `6efb71c9701f1c9261086816a72ca80231de58b1e6e94d9128cbc0bbbb65ead7`. ZIP CRC, bundletool, podpis in Firebase projekt `jivie-e928a` so preverjeni. Upload in aktivacija sta potrjena: Play kaže `Aktivno`, `1.1.0 (3) — nadgradnje Jivie` ter »Na voljo notranjim preizkuševalcem«, datum 8. oktober ob 12:56. Nova fizična namestitev še ni preverjena; spodaj je zgodovina izdaje2. [Aktualni dnevnik](../UPGRADE_IMPLEMENTATION.md).

## Zgodovina predhodne kandidatke: 1.0.1+2

Po glavnem commitu/pushu `d551028` je bila različica izrecno zvišana. Android AAB SHA256 `0cff4cd29b4787e9c9092e6b1c9847329f87d1482164ee708a286220f4b1a78d` je podpisan, preverjen in objavljen na internem kanalu; 8. oktobra je po uporabnikovi potrditvi vključen obstoječi seznam `domači` (14 članov), kanal kaže `Aktivno`. iOS prvi upload 1.0.1 (2) je uspel, nato pa obdelava `Failed`/90683 zaradi camera/photo referenc neuporabljenega medijskega izbirnika. Dokumentna CocoaPods izvedba in razvojni arhiv sta preverjena, ponovni distribucijski izvoz pa vrne `No Accounts`. Nova uspešna iOS interna izdaja zato še ni potrjena. [Celotni aktualni potek](NOTIFICATION_RELEASE_RUN.md), [pogoji lastnika](OWNER_ACTIONS.md).

8. oktobra je pregled istega objavljenega AAB potrdil vključeno Jivie launcher ikono: manifest, vseh pet rastrskih gostot, adaptive foreground in monochrome viri. Ločena trgovinska ikona prej ni bila dodana. `assets/branding/jivie/google-play-512.png` je zdaj naložena in shranjena v osnutek privzete slovenske predstavitve; konzola potrdi »Spremembe so bile shranjene«. Predstavitev še ni zaključena ali pregledana, zato osnutek ni dokaz prikaza ikone v trgovini. Dokaz: `build/qa/jivie-next-release/play-icon-draft-saved.png`. Uporabnik je nato 8. oktobra izrecno dovolil Android testiranje brez čakanja na iOS. Obstoječi e-poštni seznam `domači` s 14 člani je izbran in shranjen; konzola potrdi `Aktivno` za 1.0.1 (2). Drugi seznami niso izbrani. [Prijavna povezava](https://play.google.com/apps/internaltest/4701286726300038561) je predana uporabniku; dejanska namestitev na telefon še ni potrjena. Dokaz: `build/qa/jivie-next-release/play-domaci-active.png`. AAB/verzija nista spremenjena.

8. oktobra je uporabnik izrecno naročil še vključitev svojega razvijalskega Google računa. Naslov je dodan v obstoječi seznam `domači` in sprememba potrjena; konzola prikazuje 15 članov ter aktiven kanal. Dokaz brez naslovov: `build/qa/jivie-next-release/play-domaci-15-active.png`. Pridružitev testu in namestitev s tem računom še nista potrjeni.

Spodnja evidenca **1.0.0+1** ostane zgodovinski dokaz prvega cikla; ne predstavlja trenutne verzije v kodi ali zadnje Android izdaje.

Tekoča evidenca 7. oktobra 2026. Uporabnik je naročil novi ločeni aplikaciji in testni izdaji ter dokončno potrdil **`si.triparna.jivie`** za Android in iOS. Izdajatelj je TriparNA; različica ostane **1.0.0+1**. Priprava in ustvarjena evidenca nista dokaz naloženega paketa, razpoložljive testne namestitve ali javne objave.

## Potrjeni konzoli

Glavni agent je neposredno v konzolah preveril in ustvaril:

| Sistem | Potrjeno stanje | Še potrebno |
| --- | --- | --- |
| Google Play | Organizacijski račun **TaknDevs**, developer ID `4991604398202512900`; nova **Jivie**, app ID `4972659047480717992`, package `si.triparna.jivie`, brezplačna, slovenščina. Uporabnik je potrdil obe izjavi ob ustvarjanju. Sveži podpisani AAB je sprejet. | Izbrani testni dostop in namestitev na napravo. |
| Play internal testing | Track `4701286726300038561`, izdaja **1.0.0 (1) — prvi interni preizkus** objavljena 7. oktobra ob 22:02. Konzola kaže »Na voljo notranjim preizkuševalcem«, eno kodo različice in »Ni pregledano«. | Seznam preizkuševalcev je še prazen; kanal kaže »Neaktivno«. Uporabnika smo vprašali za Google račun. Zato dejanska dostopna namestitev še ni potrjena. |
| Apple Developer | App ID **Jivie TriparNA**, `si.triparna.jivie`, team **`CXNM99632B`**, z zmožnostjo **Push Notifications**. Podpisani arhiv in distribucijski IPA sta preverjena. | APNs ključ in dejanska dostava; sama zmožnost ju ne potrjuje. |
| App Store Connect | Nova **Jivie**, app ID **`6820232114`**, SKU `jivie-ios`, iOS, slovenščina, prava TriparNA ekipa in končni bundle ID. | Naloženi/obdelani build, TestFlight podatki in dejansko dovoljen notranji test. |

Pred popravkom ID je bil v Apple Developer registriran tudi `com.takndev.jivie`; ostaja neuporabljen in ni izbrani ID kandidatke. Registracije ne brišemo kot stranski učinek popravka. Stari **Kanban Connect** (`com.takndev.kanbanconnect`) ostane ločena aplikacija. Vidna zahteva 12 preizkuševalcev/14 dni pri njegovi preneseni evidenci ni dokazana zahteva nove Jivie na organizacijskem računu.

## Lokalna identiteta in Android podpis

Gradle `namespace`/`applicationId`, Kotlin aktivnost, iOS Runner v vseh treh konfiguracijah ter RunnerTests uporabljajo končni ID. Kotlin aktivnost je v `android/app/src/main/kotlin/si/triparna/jivie/MainActivity.kt`. iOS Runner in RunnerTests imajo `DEVELOPMENT_TEAM=CXNM99632B`. Namizne identitete, SQLite imena, kanali, format `.vsakdan` in podpora starim povabilom ostanejo združljivi.

Za zahtevano testno izdajo je bil ustvarjen **namenski Jivie upload key**, RSA 3072 / PKCS12, alias `jivie-upload`. Zasebni keystore in obnovitvene informacije so v `/Users/anzenovsak/.local/share/jivie/signing/` (mapa 0700, datoteke 0600); lokalni ignorirani `android/jivie-key.properties` ima dovoljenja 0600 in izrecno deklarira `applicationId=si.triparna.jivie`. Gesla so nastala naključno in niso izpisana, podana v vidnih argumentih ali vključena v repo/dnevnike. Stari `android/key.properties` in `android/app/takndev.jks` nista bila prebrana ali uporabljena. Zasebno kopijo novega ključa mora lastnik ohraniti zunaj repozitorija.

Gradle `validateReleaseSigning` pred `preReleaseBuild` preveri vse podpisne vnose, končni ID in obstoj keystora; debug fallback ni omogočen. Lokalni upload key še ni dokaz končnega podpisa ali Google app signing certifikata. Ločena priprava Play App Signing ima svoj izid v konzoli.

Ob pregledu je obstajal `build/app/outputs/bundle/release/app-release.aab` z datumom **8. marec 2026**. Ta stari artefakt ni dokaz Jivie kandidatke; uporabi se samo sveže zgrajeni in pregledani paket končnega ID.

## Apple podpisovanje

Pregled samo javnih certifikatnih metapodatkov in obstoja profilov potrdi:

- lokalno uporabno **Apple Development** identiteto za `CXNM99632B`, veljavnost do **20. junija 2027**;
- tri lokalne profile te ekipe za drugi aplikaciji (`si.triparna.huesky`, `com.triparna.drozer`), nobenega za Jivie;
- nobenega uporabnega lokalnega **Apple Distribution** certifikata te ekipe;
- glavni agent je v Apple Developer portalu preveril obstoječi **Distribution Managed** certifikat TriparNA, veljavnost do **26. septembra 2027**.

Odsotnost lokalnega distribucijskega certifikata sama zato ni dokončna blokada. [Apple cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/) omogočajo cloud podpisovanje v Xcode Organizer postopku, ko lokalni distribucijski certifikat manjka; potrebni so prava prijavljena ekipa in ustrezna dovoljenja.

Načrtovana pot samodejnega podpisovanja je bila po uporabnikovi prijavi izvedena s svežo Flutter gradnjo in App Store izvozom. Naslednji korak je prenos preverjene IPA v App Store Connect ter ločeno preverjanje obdelave in TestFlight dostopa. Cloud certifikatov ne vrtimo in obstoječih ne preklicujemo.

Xcode prijava je neposredno preverjena: Apple Accounts kaže uporabnikov račun in **TriparNA z.o.o., Admin**. Sveži `build/ios/archive/Runner.xcarchive` je podpisan z Apple Development; App Store izvoz `build/releases/Jivie-1.0.0+1-ios-firebase.ipa` uporablja obstoječi Apple Distribution certifikat TriparNA (26. september 2026–26. september 2027). IPA ima APNs `production`, `get-task-allow=false`, pravilen team/bundle ID in 27.901.711 bajtov. SHA256: `2a5311d17267d21442fc967e9ebe902c8fb63b5f08cb1450f2c2433b9e63904a`. Oba podpisa sta preverjena s strict/deep codesign. **Nov lokalni certifikat, CSR ali preklic ni bil izveden.** Dokazilo: `build/qa/garden-release/ios-firebase-artifact-evidence.json`. Arhiviranje/izvoz je zaključeno, Flutter gradnja ne teče. **IPA še ni naložena na TestFlight.**

Šifriranje kopij presega izključno Apple OS: AES-256-GCM in PBKDF2-HMAC-SHA256, CryptoKit z Dart fallbackom. Izdajateljeva presoja izjeme/deklaracije in držav distribucije ostaja odprta. `ITSAppUsesNonExemptEncryption` in compliance code nista nastavljena na slepo.

## Orodja in dejanski izvorni preizkusi

Lokalni read-only pregled: **Xcode 27.0 (`27A266a`)**, iOS/iOS Simulator **SDK 27.0**, Android SDK **36** je nameščen, Android Studio ima **JBR 21.0.8**. Sistemski `/usr/bin/java` nima privzetega runtime; neposredna Gradle uporaba potrebuje ustrezni JBR. To ne pomeni manjkajočega JDK v Android Studio. Flutter SDK ali odvisnosti niso bili nadgrajeni kot del spremembe ID.

Po spremembi ID in pripravi Android ključa so dejansko uspešni:

- `python3 tools/release/check_readiness.py --code-only`: **PASS**;
- `python3 -m unittest discover -s tools/release -v`: **18 PASS**;
- `python3 -m unittest discover -s tools/firebase -v`: **7 PASS**;
- `plutil -lint` iOS `project.pbxproj` in `Info.plist`: **PASS**;
- `git check-ignore android/jivie-key.properties`: podpisna datoteka je ignorirana.

Končna integracija Vrta: **76 podatkovnih/regresijskih + 48 UI/navigacijskih/vodičevih testov PASS**. `flutter analyze --no-fatal-infos`: 35 podedovanih info, brez novih napak/opozoril. `flutter build web --release` uspešen. Ročni spletni preizkus je potrdil ustvarjanje vrta, zapis opomb, območje prek obrazca, risanje drugega območja, shranjevanje in ohranitev po osvežitvi; pregled telefonske širine 390 je ločen od fizičnega iOS/Android preizkusa.

Sveži podpisani `build/releases/Jivie-1.0.0+1-android-firebase.aab`: **74.984.553 bajtov**, SHA256 `ea864d6dd42346b476e986b448f5bfd2cc86f05334dac90b129bf061f9644a4e`. Manifest potrdi `si.triparna.jivie`, `1.0.0`, kodo 1, target SDK 36. `jarsigner` preveri podpis in ujemanje z namenskim upload ključem; bundletool 1.18.3 validacija in ZIP CRC sta uspešna. Native Firebase viri so vključeni; zasebni strežniški/APNs ključi niso. Dokazilo: `build/qa/garden-release/android-firebase-artifact-evidence.json`. Ta točni AAB je bil naložen in objavljen na internem kanalu. Konzola pred pregledom uporablja začasno ime `si.triparna.jivie (unreviewed)`.

Zgodovinske gradnje v [platformnih opombah](PLATFORM_NOTES.md) so nastale s predhodnim ID `com.takndev.jivie`; njihovega uspeha ne pripisujemo končnemu ID. Dokaz nove notranje izdaje: `build/qa/garden-release/play-internal-release-published.png`.

## Ločeni odprti pogoji

Firebase klientovi datoteki, ki ju je prenesla druga naloga, sta preverjeni in vključeni prek lokalnega konfiguratorja za projekt `jivie-e928a` ter oba ID-ja `si.triparna.jivie`. Izhoda sta 0600 in ignorirana v Gitu. Service-account in APNs ključ še nista nastavljena. Strežnik in obe platformi potrebujejo isti projekt; sposobnost registracije ali vključena konfiguracija ne dokazujeta fizične dostave. Stanje vodi [FCM priprava](../FIREBASE_PREPARATION.md) in [nastavitve obvestil](../NOTIFICATION_SETUP.md).

Pred objavo ostanejo prava mobilna namestitev brez omrežja/restart, export–restore prek fizičnih izbirnikov, izbirni strežniški tok, test izbrisa samo s sintetičnim računom ter (če je kanal omogočen) realna FCM/APNs dostava. Javne strani, zasebnost/Data safety/App Privacy, testni dostop, trgovinska vprašanja in pregled imajo ločena dokazila v [READINESS](READINESS.md). Nova testna namestitev `jivie-test.triparna.si` je zdaj aktivna s FamilyHub 0.6.0; SMTP TLS/prijava in periodična opravila imajo ločene dokaze v [cPanel vodiču](../server/CPANEL_SETUP.md). Stara produkcija in objava statične strani nista del tega preklopa. Za nadaljevanje uporabi [predajo obvestil](NOTIFICATION_HANDOFF.md).
