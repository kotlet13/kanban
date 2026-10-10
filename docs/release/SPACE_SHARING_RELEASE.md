# Interna izdaja deljenja prostorov — 10. oktober 2026

Uporabnik je naročil commit/push, nadgradnjo samo `jivie-test.triparna.si`, novo
Mac gradnjo in Android interno izdajo za nadaljnji preizkus dveh računov.
Produkcijska namestitev, javna objava in iOS distribucija niso del tega koraka.

## Izvor in različica

- Funkcionalni commit `70f6113` in izdajna priprava `e0bc9a1` sta poslana na
  `origin/codex/email-invitations`.
- Nova različica je **1.3.0+15**. Identitete, SDK, zaklenjene odvisnosti in
  platformna konfiguracija ostanejo nespremenjeni.
- [Uskladitev deljenja](../SPACE_SHARING_ALIGNMENT.md) določa funkcije in meje.
  Celotno preverjanje kode: 947 Flutter PASS / 13 opt-in preskočenih,
  dejanski Dart/HTTP in ponovni zagon SQLite brez strežnika PASS,
  2505 PHP kontrol na treh bazah. Analiza ima 35 podedovanih info brez napak
  ali opozoril. To so dokazi izvora; namestitev in distribucija sledita ločeno.

## Strežniška nadgradnja

Testni strežnik je uspešno nadgrajen **0.10.0/schema14 → 0.11.0/schema15**.
Paket `FamilyHub-0.11.0-sharing-source-final.zip` ima SHA256
`d6f0b91c7fe539442ee6b0b84c017e14ee5fd23801aecc0a26f9b451f456288f`.
Pomočnik je ohranil račune, gesla, identiteto, konfiguracijo ter obstoječe politike
prostorov. Sveža kopija je obnovljena v MariaDB 10.11.19 brez omrežja in brez
zagonov aplikacije/delavcev: **85 tabel, 204 vrstice, 1.335 zasebnih datotek**.
SHA256 arhiva je `8b30d2da14799e1365cb69f766d9ad8d0c4fcf8f95b73d3889a1aa1e186aeb4e`;
kopija je zunaj repozitorija in spletnih map. Pred ponovnim odprtjem so primerjani
vsi stari stolpci vseh tabel ter obnovljena originalna cron in `.htaccess`.
Zunanji HTTPS potrdi istega strežnika ter novo pogodbo3; pet novih/obstoječih
zaščitenih metod brez prijave vrne 401/auth_required. Vseh pet delavcev je po
preklopu samodejno ustvarilo nov veljaven status z dovoljenji 0600. [Podrobnosti namestitve](../server/CPANEL_SETUP.md#16-deljenje-prostorov-10-oktobra--familyhub-0110--schema15).

**Prehod obstoječega prostora na policy3 je ločen:** lastnik mora v Nastavitvah
prostora pregledati dodatne prejemnike in spremembo potrditi. Nadgradnja sheme
starih dovoljenj ne razširi sama. Novi prostori uporabljajo novo politiko.

## Distribucija in fizični preizkus

Google Play potrdi **Aktivno / 1.3.0 (15) — povabila in deljenje prostorov**, na voljo
internim preizkuševalcem **10. oktobra 2026 ob 20:07**, samo seznam **domači (15)**.
Shranjene so SL/EN opombe; podpora napravam je nespremenjena.
[Posodobitev za preizkuševalce](https://play.google.com/apps/internaltest/4701286726300038561).

- AAB: `build/releases/Jivie-1.3.0+15-android-firebase.aab`, 79.376.858 bajtov.
- SHA256: `0145b042b3ea9a2df3680566d5457bab09ea84295393068494cc348f97028490`.
- Preverjeni so podpis z istim certifikatom kot 14, ZIP CRC/bundletool,
  `si.triparna.jivie`/15/min24/target36, enaka dovoljenja, Android Back callback,
  vseh osem 64-bitnih knjižnic pri 16 KiB in native/Dart Firebase `jivie-e928a`.
- **328 zamrznjenih vhodov** se ujema z izdajnim commitom `e0bc9a1`;
  18 izdajnih in 7 Firebase testov ter izvorni checker PASS. Široka medijska
  dovoljenja in drugi pogoji javne izdaje ostajajo na ločeni checklisti.
- Dokazi: `build/qa/jivie-sharing-release/android-release-artifact-evidence.json`,
  `source-input-manifest.json`, `play-internal-1.3.0-15-active.jpg` in
  `play-testers-domaci-15.jpg`.

Mac **1.3.0 (15), arm64 Debug** je v
`build/qa/jivie-sharing-mac-20261010/SignedProducts/Debug/Jivie.app`.
Globok strogi podpis, isti certifikat/profil/Keychain skupina in **325 vhodnih
hashov** so preverjeni. Vseh294 skupnih Android/Mac vhodov se ujema. Ohranjeni
so `com.example.kanban`, SDK/zaklenjene odvisnosti ter vseh 152 datotek starega
podpisanega artefakta. To je lokalna podpisana razvojna gradnja, ne Mac App Store
ali notarizirana distribucija.

Nova aplikacija je zagnana prek Computer Use; pot njenega procesa je preverjena.
Račun **takndev**, potrjen naslov in **Doma · Organizacija · Član · Deljeno** so
ohranjeni. V Nastavitvah prostora je viden prvi račun kot lastnik ter obvestilo,
da mora lastnik pregledati prehod stare politike. Migracije politike nismo izvedli.
Dokazi: `build/qa/jivie-sharing-mac-20261010/verification-summary.json`,
`runtime-check.json`, `android-overlap-verification.json` in `mac-launched-doma.png`.

Po obeh novih namestitvah preverimo urejanje med računoma, podedovan dostop do
obstoječega in novega projekta, projektno omejeno povabilo, finance in preklic
posamezne poti dostopa. Fizični preizkus ne sledi samodejno iz avtomatiziranih testov.
