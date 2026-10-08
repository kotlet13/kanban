# Obvestila in naslednja interna izdaja Jivie

## Opomniki in Vrt — priprava 1.1.3+6

Funkcionalni commit `10a9e03` vključuje oddaljeno razporejanje in prenovo Vrta. 636 Flutter PASS/9 opt-in HTTP preskočenih, ločeno 2 dejanska HTTP testa; analiza 37 obstoječih info brez napak/opozoril. Po funkcionalnem commitu je izrecno pripravljena različica 1.1.3+6. Nova podpisana gradnja in aktivacija še sledita. [Izvedba in preverjanje](../REMOTE_REMINDERS.md), [Vrt](../GARDEN.md).

## Kompaktna telefonska glava — 1.1.2+5

Koda/push `3d504c4` premakne prostor v glavo ob ikono, odstrani ime in dodatno vrstico s telefona ter dodajalno tipko zamenja z + Nov prostor v dropdownu. 565 Flutter PASS, analiza brez napak/opozoril s 37 obstoječimi info. Po funkcionalnem commitu je `1121407` izrecno pripravil 1.1.2+5. Podpisana gradnja je preverjena in Play potrdi Aktivno/1.1.2 (5), na voljo internim preizkuševalcem 8. oktobra ob 17:39. Strežnik, pogodbe ter SDK/paketi niso spremenjeni. [Aktualni dokazi](../UPGRADE_IMPLEMENTATION.md).

## Dopolnitve po uporabniškem pregledu — 1.1.1+4

Funkcionalni commit/push `cbcb29d` z levim telefonskim menijem, uporabno razpoložljivostjo, vidnostjo projekta, finančnimi povezavami/računi in napravno odložitvijo je zaključen. Končni skupni nabor: 544 PASS; analiza 37 obstoječih info brez napak/opozoril. Izdajna priprava `e9d676f` izrecno dvigne verzijo na1.1.1+4. Podpisani AAB je preverjen in objava potrjena: Play Aktivno/1.1.1 (4), na voljo internim preizkuševalcem8. oktobra ob15:03. Dokazi so v [izvedbenem dnevniku](../UPGRADE_IMPLEMENTATION.md). FCM/APNs in iOS niso del te Android oddaje.

## Aktualna nadgradnja — 8. oktober, 1.1.0 (3)

Popravki `54f3061` in funkcionalne nadgradnje `e73cd1c` so commitani/pushani ločeno s sporočilom `popolna predelava aplikacije`. Nato je `b99760d` pripravil izrecni dvig na **1.1.0+3** brez menjave SDK/odvisnosti. Android je **aktivno objavljen na istem internem kanalu**: Play kaže `1.1.0 (3) — nadgradnje Jivie`, »Na voljo notranjim preizkuševalcem«, 8. oktober ob 12:56. [Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561). Novo namestitev in fizične opomnike uporabnik še preveri.

AAB SHA256 `6efb71c9701f1c9261086816a72ca80231de58b1e6e94d9128cbc0bbbb65ead7`; ID/verzija/API36, nespremenjeni namenski upload certifikat, ZIP/bundletool, vseh 8 knjižnic 64-bit s 16KiB poravnavo in native Firebase viri so potrjeni. Končni Flutter **502 PASS**, analiza brez error/warning (35 starih info); backend **987 PASS** na treh bazah. [Funkcionalni in namestitveni dokazi](../UPGRADE_IMPLEMENTATION.md), dokaz konzole `build/qa/jivie-upgrade/play-internal-1.1.0-3-active.jpg`.

Testno gostovanje je po izolirani obnovi kopije nadgrajeno na **FamilyHub 0.7.0/schema11**, z ohranjenimi računi, gesli, serverId, konfiguracijo in izvirnim cronom. [cPanel](../server/CPANEL_SETUP.md). FCM ostane izključen. iOS zahteva svežo gradnjo 1.1.0 (3) po obnovljenem podpisnem dostopu; ne ponavljamo starega razvoja 2. [Kratek seznam lastnika](OWNER_NEXT_STEPS.md).

Spodaj ostane zgodovina prejšnje 1.0.1 (2).

Tekoča evidenca 8. oktobra 2026, ki jo vodi koordinacijski klepet. [Predaja](NOTIFICATION_HANDOFF.md) potrjuje zaključek vzporednih sprememb, gradenj in izdaj. Mobilni ID ostane `si.triparna.jivie`, Firebase projekt `jivie-e928a`, izdajatelj TriparNA. Ta dokument ni potrdilo fizične dostave ali oddaje.

## Vrstni red

1. Pregled že izvedenih obvestil, samo potrebne dopolnitve in preizkusi.
2. Pregled stabilnih virov in Git commit/push aplikacijskega repozitorija s sporočilom natanko `popolna predelava aplikacije`, brez dodatnega telesa.
3. Dvig na `1.0.1+2`, šele po glavnem commitu/pushu; trgovinska gradiva in preverjalnik sledijo isti različici. Zgodovinski dokazi `1.0.0+1` ostanejo.
4. Sveži podpisani AAB/IPA, pregled dejanskih ID-jev, različice, podpisov in Firebase/APNs virov, nato interna oddaja. Upload in aktivna testna distribucija sta ločena rezultata.
5. Prvotni pogoj ureditve skupine po obeh oddajah je uporabnik 8. oktobra spremenil: Android `Domači` vključimo takoj, iOS nadaljuje po uspešni oddaji. Naslovov ne ugibamo in seznama ne shranjujemo v javni Git. Dostop do namestitve ni dovoljenje za širše upravljanje App Store Connect.

Ločen javni repozitorij Kanboard/FamilyHub in javna produkcijska izdaja nista predmet naloge. Stari Kanboard/podatki ostanejo ohranjeni.

## Implementacija in dokazi

Center obvestil, lokalni opomniki, konkretni/združeni cilji, preference in izbirni FCM že obstajajo. Drug vzporedni sistem ni potreben. Ciljni SMTP popravek trajno potrdi lease/poskus, nato sveže preveri pravice/prejemnika pod zaklepi `users → scope → job` skozi send/CAS. Dokončan preklic, deaktivacija ali izbris prepreči pošiljanje. Generično inbox sporočilo sledi aktualnemu veljavnemu naslovu; varnostne kode ohranijo ločeno vezavo. SMTP/FCM besedila so Jivie, identifikatorji in format kopij ostanejo združljivi.

- 90/90 Flutter testov v 10 datotekah; analyze izhod 0, istih 35 podedovanih info, brez napak/opozoril. SDK/odvisnosti nespremenjeni. Dokazi: `build/qa/notification-final-check/`.
- Pred-fix šest SMTP scenarijev FAIL na vsaki bazi; po popravku 36 race + 16 SMTP + 77 push + 48 account = 177 na vsaki SQLite/MySQL/MariaDB, skupaj 531. Pravi loopback SMTP, noben resnični prejemnik. Dokazi: `build/qa/smtp-race/`.
- Procesni izpad po SMTP ACK ohrani lease/števec; ponovitev po izteku uporablja isti Message-ID in lahko podvoji e-pošto. Enkratna dostava ni zagotovljena.
- PHP lint osmih datotek in `git diff --check` uspešna. Izolirana testna okolja odstranjena, druge instance/arhiv ohranjeni.

## Ponudniki in fizični preizkus

Firebase HTTP v1 API je dejansko omogočen. Klientovi konfiguraciji/generirana izhoda se ujemajo in so ignorirani v Gitu. Firebase CLI prijava je potrjena; nobena strežniška poverilnica ni v odjemalcu.

Google Cloud zahteva prvo ločeno sprejetje pogojev; potrditev ni prejeta. Strežniška FCM identiteta/ključ in razvojni/produkcijski APNs ključ še niso pripravljeni. FCM na testnem strežniku ostane izključen. Dostave na fizičen telefon ne označujemo kot potrjene.

SMTP TLS/prijava in cron na novi testni namestitvi so preverjeni. Uporabnik je 8. oktobra potrdil dejanski prejem e-poštne kode in uspešno preverjanje naslova v Android aplikaciji; manjka jasno sporočilo o uspehu. Obnova gesla, običajna e-poštna obvestila, preostali fizični Android/iPhone preizkusi in Apple deklaracija šifriranja ostajajo ločeni koraki v [evidenci lastnika](OWNER_ACTIONS.md).

## Tekoči izidi

Glavni commit **d551028d7e9be9a593b9d884f01b2183fcbfbe86** s sporočilom natanko `popolna predelava aplikacije` je porinjen na `origin/codex/vsakdan-foundation`. Šele nato so različica, trgovinski JSON in preverjalnik usklajeni na **1.0.1+2**. SDK/Dart odvisnosti in `pubspec.lock` ostanejo isti. Ločen javni strežniški repozitorij ni spremenjen.

Štirje modeli so nameščeni na testnem cPanelu: primerjava starih/novih SHA, zasebne kopije, štirje PHP linti in javni capabilities uspešni. Config/schema/ključi/cron niso spremenjeni. Prazen delivery worker uspešno zaključi z ničelnimi števci; to ne dokazuje prejema sporočila. Patch SHA256 je `fe31e70d66e2c87b09ab199f287c9e47c9bdebea8dcc6516c8149c86d0716804`. Dokazi: `build/qa/notification-final-check/cpanel-patch-evidence.json`.

Android AAB **1.0.1 (2)** je preverjen in objavljen na internem Play kanalu. SHA256 `0cff4cd29b4787e9c9092e6b1c9847329f87d1482164ee708a286220f4b1a78d`; prava identiteta, namenski upload podpis, bundletool, CRC in Firebase viri potrjeni. Po izrecni uporabnikovi odločitvi 8. oktobra je obstoječi seznam `domači` (14 članov) izbran in shranjen; kanal zdaj kaže `Aktivno` za 1.0.1 (2). Drugi seznami niso izbrani. [Pridružitev preizkusu](https://play.google.com/apps/internaltest/4701286726300038561); namestitev na uporabnikov telefon še ni potrjena. To ni javna objava. Dokaza: `build/qa/jivie-next-release/play-internal-published.png` in `build/qa/jivie-next-release/play-domaci-active.png`.

iOS prvi **1.0.1 (2)** prenos je uspel, Apple obdelava pa je vrnila `Failed`/90683 za camera/photo purpose ključa. Vzrok je `file_picker` SwiftPM manifest, ki brez izbire vključuje medijske poti; aplikacija uporablja `any/custom` dokumentni izbirnik. Podprta CocoaPods konfiguracija izključi `PICKER_MEDIA` in `PICKER_AUDIO`, zato uporabniških tokov ali opisov ne izmišljamo. Flutter projekt uporablja CocoaPods; Firebase native SDK ostane 12.19.0. Zavrnjeni podpisani paket/arhiv in njegova dokazila so ohranjeni pod `ios-swiftpm-rejected` imeni. [Flutter konfiguracija](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers#how-to-turn-off-swift-package-manager).

Popravljeni iOS razvojni arhiv preveri podpis, ID/verzijo in Firebase; pregled 23 Mach-O binarijev potrdi odstranitev camera/photo/DK referenc in ohranjen dokumentni izbirnik. Simulator gradnja, izolirana namestitev/zagon in sveža izolirana macOS Debug gradnja uspejo. Testi kopij 18 in izdajnih orodij 18 PASS, analiza ohrani 35 info. Stara macOS build mapa ima ostanke SwiftPM modulov; uporabljena je sveža DerivedData/SYMROOT/OBJROOT brez brisanja prejšnjih artefaktov. Identitete/baze/entitlements so ohranjeni.

**Ponovni iOS distribucijski izvoz in upload nista zaključena:** Xcode tudi z `-allowProvisioningUpdates` vrne `No Accounts`. Native UI je ločeno blokiran zaradi zaklenjenega Maca. Popravljeni arhiv ima razvojni profil; ni nova preverjena distribucijska IPA. [Apple dovoljuje ponovno uporabo gradnje po Failed](https://developer.apple.com/help/app-store-connect/reference/app-uploads/build-upload-statuses); ostane 1.0.1 (2). Dejanski dialog dokumentnega izbirnika, TestFlight aktivacija in iOS testni dostop sledijo po odpravi teh pogojev; Android seznam `domači` je že vključen. Dokazi: `build/qa/jivie-next-release/cocoapods-verification-summary.json`.

## Dopolnitev Android preizkuševalcev

8. oktobra je uporabnik izrecno naročil še vključitev svojega razvijalskega Google računa. Naslov je dodan v obstoječi seznam `domači` in sprememba potrjena; konzola prikazuje 15 članov ter aktiven kanal. Dokaz brez naslovov: `build/qa/jivie-next-release/play-domaci-15-active.png`. Pridružitev testu in namestitev s tem računom še nista potrjeni.

## Težava pri namestitvi na uporabnikov telefon

8. oktobra uporabnik poroča, da je Jivie zdaj vidna, ob namestitvi pa Play prikaže splošno napako. Telefon je Samsung Galaxy S25. Podrobnosti objavljene izdaje kažejo 19.184 podprtih modelov, API 24+, arm64-v8a/armeabi-v7a/x86_64 in podporo 16 KB strani pomnilnika. Namestitev na njegov telefon ostaja nepotrjena; ti podatki ne potrjujejo vzroka napake. Modelno specifični katalog zahteva nove pogoje, ki niso sprejeti. Uporabnik je nato potrdil, da napaka nastane takoj ob pritisku za namestitev, preden se prenos začne. Naslednja slika prikazuje sporočilo, da aplikacije ni mogoče prenesti, brez konkretne kode napake. Predlagan je preizkus ponovnega zagona Trgovine Play in čiščenja samo njenega predpomnilnika ter primerjava s prenosom druge aplikacije; rezultat še ni znan. Zaradi samega sporočila izdaja in dostop nista bila spremenjena.

Uporabnik je nato potrdil uspešno namestitev in zagon Jivie na Samsungu Galaxy S25 po prisilni ustavitvi Trgovine Play. Posnetek prikazuje novo ikono in zaslon za povezavo računa. To je uporabniško potrjen zagon, ne opravljen celoten fizični preizkus sinhronizacije, kopij ali obvestil. Naslednja ovira uporabniškega toka je registracija: UI ponuja prijavo, povabilo in prvi račun s kodo; javna registracija brez kode/povabila ni izvedena. Sveži testni capabilities potrdi `accountEnrollment=true`; upraviteljeva stran za izdajo prve kode je pripravljena, koda v tem koraku še ni izdana.

V naslednjem koraku je bila na uporabnikovo zahtevo izdana enkratna koda za prvi račun na testnem strežniku. Uporabnik 8. oktobra poroča, da je registracija uspela, vendar brez jasnega sporočila o uspehu. Pregled kode potrjuje samodejno prijavo ob registraciji in 30-dnevno napravno sejo; prikazani 7. november pomeni njen iztek. Povratna informacija in predlagana izboljšava sta zapisani v [načrtu prenove](../RENOVATION_PLAN.md#opomba-za-prihodnjo-nadgradnjo--potrditev-registracije-in-veljavnost-prijave). Koda in poverilnice niso del dokumentacije. To še ne potrjuje fizičnega preizkusa skupnega urejanja, sinhronizacije ali dostave obvestil.
