# Lokalna shramba podatkov

Organizator uporablja pripeti `drift: 2.35.1` in SQLite za osebne in skupne podatke. Etapa zasebne sinhronizacije seli osebni Hive z ohranjenim izvorom; prijava ne pomeni prenosa na strežnik. Skupna podatkovna povezava omogoča transakcije nad posameznimi zapisi, odhodnimi spremembami in vezavo osebnega prostora.

Drift in zaklenjeni `sqlite3` zahtevata Dart najmanj 3.10. Nadgradnja povezav povabil je pozneje spodnjo mejo v `pubspec.yaml` uskladila na `^3.12.0` in Flutter najmanj 3.44. Nameščeni Flutter SDK 3.47.2 pri tem ni bil nadgrajen, uporabnikova različica aplikacije ostaja `1.0.12+12`.

`sqlite3: 3.7.0` je izrecna razvojna odvisnost za teste migracije resnične stare SQLite datoteke. Gre za isto različico, ki jo je že uporabljal Drift, brez zamenjave pogona ali nadgradnje paketa.

Spletna izvedba vsebuje lastni kopiji `web/drift_worker.js` in `web/sqlite3.wasm`; med uporabo ju ne prenaša s CDN. Obe sta iz iste [uradne izdaje Drift 2.35.1](https://github.com/simolus3/drift/releases/tag/drift-2.35.1). Prenos je bil preverjen proti SHA256, ki ga za sredstva navaja GitHub API. Izvorni URL-ji, velikosti in kontrolne vsote so v [drift-web-assets.json](drift-web-assets.json); licenca Drift je ohranjena v [drift-LICENSE.txt](drift-LICENSE.txt). Nativna odvisnost `sqlite3` in preostale prehodne različice so v `pubspec.lock`.

Ob nadgradnji odvisnosti skupaj posodobi oba spletna modula, kontrolne vsote in preverjanja hrambe. Uporabljaj uradna sredstva iz izdaje, ki ustreza zaklenjeni različici, ne dinamičnega naslova `latest`.

[Dokumentacija spletne izvedbe](https://drift.simonbinder.eu/platforms/web/) pojasnjuje izbiro hrambe in omejitve brskalnikov. `sqlite3.wasm` se mora ponujati kot `application/wasm`. Nekateri načini zahtevajo COOP/COEP; njuna uporaba mora biti preverjena skupaj z ostalimi funkcijami aplikacije. Izvedba deljenja mora zavrniti pomnilniški način in način IndexedDB brez koordinacije zavihkov, saj ne izpolnjujeta dogovorjene trajnosti. Osebni del ni odvisen od varne hrambe prijave ali strežnika, potrebuje pa podprto trajno lokalno SQLite shrambo; nepodprtega spletnega pogona ne nadomesti tiho s pomnilnikom.

## Sistemski opomniki

Za lokalne opomnike sta dodana pripeta [`flutter_local_notifications` 22.3.1](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1) in [`flutter_timezone` 5.1.0](https://pub.dev/packages/flutter_timezone/versions/5.1.0). Neposredna odvisnost `timezone: ^0.11.0` je zaklenjena na 0.11.1. Razreševanje je dodalo osem paketov, brez nadgradnje prej prisotnih paketov. Odvisnosti ne pomenijo, da je dostava že preverjena; izvedbo in dokaze vodi [mejnik družinske nadgradnje](../FAMILY_UPGRADE.md).

Paket opomnikov zahteva najmanj Flutter 3.38.1. Projekt uporablja 3.47.2. Android zahteva Java 17 in desugaring 2.1.4; obstoječi AGP 8.11.1 zadošča. Razporejanje uporablja običajne, časovno nenatančne alarme brez dodatnega dovoljenja za točne alarme. Na Applovih platformah je treba inicializacijo uskladiti z obstoječim UIScene življenjskim ciklom. Spletna različica paketa ne omogoča časovnega razporejanja obvestil. To so meje ponudnika, ne razlog za onemogočanje centra obvestil v aplikaciji.

Adapter uporablja polno bazo `timezone/data/latest_all.dart`: dejanski iOS preizkus je pokazal, da skrajšana zbirka ne prepozna identifikatorja `Europe/Ljubljana`. Ob neznanem časovnem pasu ne preide tiho na UTC.

Ta paket ne izvaja oddaljene potisne dostave. Firebase/FCM je potrjen ločen izbirni kanal; uporabnik je potrdil Apple Developer račun, Firebase projekta in APNs za to aplikacijo pa še ni nastavljal. Za iOS [FCM uporablja APNs in zahteva Apple ključ](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). Konfiguracija dostave ne sme postati pogoj za osebno uporabo, lokalno bazo ali prijavo v FamilyHub.

## Izbirna oddaljena obvestila

Za pripravo FCM sta 5. oktobra 2026 dodana pripeta uradna paketa [`firebase_core` 4.15.0](https://pub.dev/packages/firebase_core/versions/4.15.0) in [`firebase_messaging` 16.7.0](https://pub.dev/packages/firebase_messaging/versions/16.7.0). Razreševanje doda sedem paketov, brez nadgradnje obstoječih odvisnosti. Ne dodaja Firebase Auth, Firestore, Analytics ali Cloud Functions. Mobilna konfiguracija je izbirna; osebna uporaba ostane neodvisna. Dokaze vodi [priprava FCM](../FIREBASE_PREPARATION.md).

## Povabila in šifrirane kopije

Etapa zasebne sinhronizacije pripne `app_links 7.2.1`, `cryptography 2.9.0` in `cryptography_flutter 2.3.4`. Razreševanje doda sedem novih paketov, brez posodobitev prej zaklenjenih paketov. Podprti URL dogodki in njihova platformna nastavitev sledijo [uradni dokumentaciji app_links](https://pub.dev/packages/app_links/versions/7.2.1); šifriranje uporablja [cryptography](https://pub.dev/packages/cryptography/versions/2.9.0) in izbirno pospeševanje prek [platformnega vtičnika](https://pub.dev/packages/cryptography_flutter/versions/2.3.4).

Izbrana različica `app_links` odpravlja izpis vsebine povezav v dnevnike, ki je bil prisoten v pregledanih starejših različicah 6.4.1 in 7.0.0. Zahteva Dart 3.12 / Flutter 3.44, njen Android minimum je 24. Izolirana kompilacija njegove Android knjižnice je uspela z obstoječim AGP 8.11.1 / Gradle 8.14. Uspeli so tudi končni Android debug APK, iOS simulator debug, macOS debug in spletna JavaScript gradnja; dejanske uporabniške tokove ter omejitve navaja [mejnik](../PERSONAL_SYNC_AND_RECOVERY.md). Pripetost odvisnosti sama ne potrdi delovanja globokih povezav ali obnove podatkov.
