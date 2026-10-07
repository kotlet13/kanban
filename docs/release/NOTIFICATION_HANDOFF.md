# Predaja obvestil in izdaje — 7. oktober 2026

## Meja lastništva in stabilno mobilno stanje

Mobilna implementacija te naloge je zaključena. Noben podagent te naloge ne spreminja več aplikacijske kode in ne izvaja Flutter gradnje. Različica ostaja **1.0.0+1**, Android/iOS ID **si.triparna.jivie**. Commit, push in naslednja različica v tej nalogi niso izvedeni. Ločen javni repozitorij vtičnika ni spremenjen.

**Končna predaja: stabilno stanje, 7. oktober 2026 ob 22:31 CEST.** Glavni agent in vsi njegovi podagenti so zaključili spremembe aplikacije, namestitvenih skript in dokazne dokumentacije. Flutter gradnja, podpisovanje, upload in strežniški poseg ne tečejo več. Namestitev je končana; delitev dela se lahko nadaljuje iz tega stanja. Druga koordinacijska naloga lahko prevzame ciljne ugotovljene popravke obvestil, FCM/APNs, končni pregled, Git in naslednji cikel izdaj. Ta naloga ne bo vzporedno urejala istih datotek ali konzol.

V prejeti koordinacijski predaji je naveden uporabnikov vrstni red: dokončanje obvestil/preizkusov → commit/push mobilnega repozitorija s sporočilom natanko `popolna predelava aplikacije` → dvig različice → novi interni izdaji → testna skupina. Tu ta dejanja niso bila ponovno izvedena.

## Kar že obstaja

- Center obvestil, lokalni opomniki in izbirni FCM transport že imajo implementacijo. Ne ustvarjati drugega vzporednega sistema; dejanske vrzeli ugotoviti s pregledom obstoječih pogodbenih/preizkusnih dokazil.
- Vrt je lokalni modul: več vrtov, zapiski, pravokotna območja, risanje/premikanje/urejanje, SQLite schema 5, šifrirane kopije. Ni strežniško deljen ali sinhroniziran.
- 76 podatkovnih/regresijskih in 48 UI/navigacijskih/vodičevih testov PASS. Analyze: 35 podedovanih info, brez novih napak/opozoril. Web build in ročno shranjevanje/ponovna naložitev vrta PASS. Fizičnega telefona ta preverjanja ne nadomestijo.
- Firebase projekt **jivie-e928a**, Spark, sender **484725902593**; klientovi datoteki za oba končna ID-ja vključeni prek `tools/firebase/configure_client.py`. Lokalna konfiguracija je ignorirana in 0600. Brez Firebase Auth/Firestore/Analytics/Functions.
- Android AAB `build/releases/Jivie-1.0.0+1-android-firebase.aab`, SHA256 `ea864d6dd42346b476e986b448f5bfd2cc86f05334dac90b129bf061f9644a4e`: podpis/bundletool/manifest preverjeni. **Objavljen na internem Play kanalu 7. oktobra ob 22:02**, app `4972659047480717992`, track `4701286726300038561`. Noben seznam preizkuševalcev še ni izbran, kanal zato neaktiven. Ni javne objave.
- iOS arhiv `build/ios/archive/Runner.xcarchive` in IPA `build/releases/Jivie-1.0.0+1-ios-firebase.ipa` podpisana in preverjena. IPA 27.901.711 bajtov, SHA256 `2a5311d17267d21442fc967e9ebe902c8fb63b5f08cb1450f2c2433b9e63904a`, Apple Distribution/TriparNA, APNs production, get-task-allow false. Obstoječi managed certifikat; brez novega lokalnega certifikata/CSR ali preklicev. **Ni naložena na TestFlight.** App Store Connect app `6820232114`, team `CXNM99632B`; Xcode prijava potrjena.

## Odprte konfiguracije in preverjanja

- APNs `.p8` in strežniški FCM service-account še nista konfigurirana; vključeni Firebase viri niso dokaz dostave na zaprt telefon. Dejanska Android/iOS dostava, dovoljenja, odpiranje ciljnega zapisa in preklic dostopa še zahtevajo preizkus.
- Apple encryption compliance ni deklariran. Kopije uporabljajo AES-256-GCM/PBKDF2-HMAC-SHA256 (600.000); `cryptography_flutter` se registrira sam, uporablja CryptoKit, a tudi Dart AES fallback (med drugim manjši payloadi) in Dart PBKDF2. Trditev »samo OS šifriranje« ni veljavna. Izdajatelj mora razrešiti ustrezno izjemo/deklaracijo in države distribucije; ne nastaviti `ITSAppUsesNonExemptEncryption` na slepo.
- Uporabnik je ustvaril mailbox **jivie-test@triparna.si**, 100 MB. cPanel potrjuje SMTP **mail.triparna.si:465 SSL/TLS**, avtentikacija z geslom tega predala. Gesla ni v klepetu ali repozitoriju. Lastnik ga je shranil v zasebni `smtp-password.txt` (0600). SMTP konfiguracija je aktivna, TLS in avtentikacija z `NativeVerifiedSmtp` dejansko uspešna. Nobeno sporočilo ni bilo poslano; končni prejem in account-mail/reset tok še nista preverjena.
- Testni prejemnik e-pošte še ni neposredno potrjen v tej nalogi; ne pošiljati testne pošte samo na podlagi najdenega kontaktnega naslova.

## Končna strežniška predaja

Nova izolirana namestitev **https://jivie-test.triparna.si/**, Kanboard 1.2.54, PHP 8.4.26, MySQL gonilnik/MariaDB 10.11.19. Stari `kan.triparna.si` ostaja nedotaknjen. Nova baza `tripar13_jivietest`, docroot `/home/tripar13/jivie-test.triparna.si`, zasebna mapa `/home/tripar13/private/jivie-test` (0700). HTTPS preusmeritev vključena, Europe/Ljubljana, d.m.Y.

FamilyHub **0.6.0 je aktiviran**, njegova migracija v `plugin_schema_versions` potrjuje **10**. ZIP SHA256 `433d45fbb8c7aa350e92beab812a7b9e7ffc1ed07bdae5d003fa1fce4e9624c0`. Varovani v3 helper `server/scripts/deploy-cpanel-fresh.php` je preizkušen z dejanskim tokenizerjem; na strežniku so uspeli check, prepare, oba linta in activate. Novi zasebni DATA_DIR ter files/cache so preverjeno zapisljivi, podmape 0700; konfiguracije/geslo/ključ 0600. Osnovna in SMTP priprava imata zasebni kopiji v `.../install/familyhub-deploy/` oziroma `.../install/smtp-setup/`. Varnostne kopije in izvirni javni data ostanejo ohranjeni; stari produkcijski podatki niso preneseni ali izbrisani.

HTTPS capabilities: `enabled`, `accountDeletion`, `privateSync`, `emailVerification`, `passwordReset`, `smtp` true; `externalPush`, `legacyProjectSharing` false. Server ID **95c11fe0-916c-48be-a3f6-999732846266**. `scopes.list` brez identitete je dejansko **401 auth_required**, tuji Origin **403 origin_not_allowed**; CORS ostaja prazno dovoljenje (native klienti delujejo brez browser Origin). Dokaz: `build/qa/garden-release/cpanel-native-api-evidence.json`. HTTP preusmeri 301 na HTTPS; javni data zahtevi preusmerita 302 na prijavo, zato ne trditi opaženega 403. Aktivni podatki so zunaj vseh pregledanih spletnih korenov.

SMTP je nastavljen prek `server/scripts/setup-cpanel-smtp.php`, ki generira 32-bajtni ključ samo na strežniku in ne izpisuje gesla. Dejansko preverjena TLS povezava/prijava, brez testnega sporočila. Po SMTP dopolnitvi se `familyhub-config.php` namerno razlikuje od začetnega SHA; osnovni deployment `--check` zato pričakovano zavrne `feature_config_changed`. Ne ponovno nameščati ali sproščati integritetnega varovala zaradi tega.

Vsi štirje CLI workerji ročno uspešni z ničelnimi števci. Dodani cron: reminders/account-mail/delivery **vsako minuto**, deletion-cleanup **vsakih pet minut**. Zasebni `*-status.json` se prepisuje pod umask 077 in ima 0600. Prvi trije dejansko periodično zagnani ob 22:25 in 22:28 +02:00; **vsi štirje**, vključno z deletion-cleanup, potrjeno zagnani ob **22:30:01 +02:00**, z ničelnimi števci in 0600 statusnimi datotekami. Dokaz: `build/qa/garden-release/cpanel-cron-executed.png`. Stara dva core crona ostajata nespremenjena. FCM worker ni dodan, ker kanal ni konfiguriran.

Dodatnih auditnih popravkov strežniškega brandinga ali SMTP revoke/send tekmovanja ta naloga ne izvaja; nadaljnja koordinacijska naloga je napovedala njihov ciljni pregled. Že implementiranih obvestil/opomnikov/FCM ne podvajati. Živemu testnemu strežniku ni bil izveden destruktiven preizkus izbrisa edinega skrbnika.

Odločitve/računi/fizični preizkusi, ki ostanejo lastniku, so zbrani v [OWNER_ACTIONS.md](OWNER_ACTIONS.md).

Podrobnosti: [stanje izdaj](TEST_RELEASE_STATUS.md), [Vrt](../GARDEN.md), [FCM priprava](../FIREBASE_PREPARATION.md), [obvestila](../NOTIFICATION_SETUP.md), [cPanel](../server/CPANEL_SETUP.md).
