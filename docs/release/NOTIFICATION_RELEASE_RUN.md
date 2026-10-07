# Obvestila in naslednja interna izdaja Jivie

Tekoča evidenca 7. oktobra 2026, ki jo vodi koordinacijski klepet. [Predaja](NOTIFICATION_HANDOFF.md) potrjuje zaključek vzporednih sprememb, gradenj in izdaj. Mobilni ID ostane `si.triparna.jivie`, Firebase projekt `jivie-e928a`, izdajatelj TriparNA. Ta dokument ni potrdilo fizične dostave ali oddaje.

## Vrstni red

1. Pregled že izvedenih obvestil, samo potrebne dopolnitve in preizkusi.
2. Pregled stabilnih virov in Git commit/push aplikacijskega repozitorija s sporočilom natanko `popolna predelava aplikacije`, brez dodatnega telesa.
3. Dvig na `1.0.1+2`, šele po glavnem commitu/pushu; trgovinska gradiva in preverjalnik sledijo isti različici. Zgodovinski dokazi `1.0.0+1` ostanejo.
4. Sveži podpisani AAB/IPA, pregled dejanskih ID-jev, različice, podpisov in Firebase/APNs virov, nato interna oddaja. Upload in aktivna testna distribucija sta ločena rezultata.
5. Šele po oddajah ureditev skupine `Domači`. Naslovov ne ugibamo in seznama ne shranjujemo v javni Git. Dostop do namestitve ni dovoljenje za širše upravljanje App Store Connect.

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

SMTP TLS/prijava in cron na novi testni namestitvi so preverjeni, prejeto zunanje sporočilo pa še ne. Fizični Android/iPhone, prejemniški test in Apple deklaracija šifriranja so v [korakih lastnika](OWNER_ACTIONS.md).

## Tekoči izidi

Glavni commit **d551028d7e9be9a593b9d884f01b2183fcbfbe86** s sporočilom natanko `popolna predelava aplikacije` je porinjen na `origin/codex/vsakdan-foundation`. Šele nato so različica, trgovinski JSON in preverjalnik usklajeni na **1.0.1+2**. SDK/Dart odvisnosti in `pubspec.lock` ostanejo isti. Ločen javni strežniški repozitorij ni spremenjen.

Štirje modeli so nameščeni na testnem cPanelu: primerjava starih/novih SHA, zasebne kopije, štirje PHP linti in javni capabilities uspešni. Config/schema/ključi/cron niso spremenjeni. Prazen delivery worker uspešno zaključi z ničelnimi števci; to ne dokazuje prejema sporočila. Patch SHA256 je `fe31e70d66e2c87b09ab199f287c9e47c9bdebea8dcc6516c8149c86d0716804`. Dokazi: `build/qa/notification-final-check/cpanel-patch-evidence.json`.

Android AAB **1.0.1 (2)** je preverjen in objavljen na internem Play kanalu. SHA256 `0cff4cd29b4787e9c9092e6b1c9847329f87d1482164ee708a286220f4b1a78d`; prava identiteta, namenski upload podpis, bundletool, CRC in Firebase viri potrjeni. Kanal je brez izbranega seznama testerjev še neaktiven. To ni javna objava. Dokaz: `build/qa/jivie-next-release/play-internal-published.png`.

iOS prvi **1.0.1 (2)** prenos je uspel, Apple obdelava pa je vrnila `Failed`/90683 za camera/photo purpose ključa. Vzrok je `file_picker` SwiftPM manifest, ki brez izbire vključuje medijske poti; aplikacija uporablja `any/custom` dokumentni izbirnik. Podprta CocoaPods konfiguracija izključi `PICKER_MEDIA` in `PICKER_AUDIO`, zato uporabniških tokov ali opisov ne izmišljamo. Flutter projekt uporablja CocoaPods; Firebase native SDK ostane 12.19.0. Zavrnjeni podpisani paket/arhiv in njegova dokazila so ohranjeni pod `ios-swiftpm-rejected` imeni. [Flutter konfiguracija](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers#how-to-turn-off-swift-package-manager).

Popravljeni iOS razvojni arhiv preveri podpis, ID/verzijo in Firebase; pregled 23 Mach-O binarijev potrdi odstranitev camera/photo/DK referenc in ohranjen dokumentni izbirnik. Simulator gradnja, izolirana namestitev/zagon in sveža izolirana macOS Debug gradnja uspejo. Testi kopij 18 in izdajnih orodij 18 PASS, analiza ohrani 35 info. Stara macOS build mapa ima ostanke SwiftPM modulov; uporabljena je sveža DerivedData/SYMROOT/OBJROOT brez brisanja prejšnjih artefaktov. Identitete/baze/entitlements so ohranjeni.

**Ponovni iOS distribucijski izvoz in upload nista zaključena:** Xcode tudi z `-allowProvisioningUpdates` vrne `No Accounts`. Native UI je ločeno blokiran zaradi zaklenjenega Maca. Popravljeni arhiv ima razvojni profil; ni nova preverjena distribucijska IPA. [Apple dovoljuje ponovno uporabo gradnje po Failed](https://developer.apple.com/help/app-store-connect/reference/app-uploads/build-upload-statuses); ostane 1.0.1 (2). Dejanski dialog dokumentnega izbirnika, TestFlight aktivacija in `Domači` sledijo po odpravi teh pogojev. Dokazi: `build/qa/jivie-next-release/cocoapods-verification-summary.json`.
