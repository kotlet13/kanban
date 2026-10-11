# Interna izdaja obvestil — 11. oktober 2026

Uporabnik je naročil commit/push, nadgradnjo testnega strežnika, Mac gradnjo in
Android interno izdajo. Produkcija, javna objava, iOS in merge na main niso del tega koraka.

## Izvor in preverjanje

Funkcionalni commit **bdf36d9** in izdajna priprava **13e8f46** sta poslana na
`origin/codex/email-invitations`. Aplikacija uporablja **1.3.1+16**; SDK,
zaklenjene odvisnosti, platformne identitete in konfiguracija so nespremenjeni.
[Dogovor in funkcionalni dokazi](../NOTIFICATION_DEFAULTS_AND_READ_ALL.md):
**963 Flutter PASS / 13 opt-in preskočenih**, analiza brez napak/opozoril
(35 podedovanih info), **582 PHP kontrol PASS** na treh bazah in 10 paketnih testov.

## Testni strežnik

`jivie-test.triparna.si` je nadgrajen **FamilyHub 0.11.0 → 0.11.1**, še vedno
**schema15**, brez SQL migracije ali zapisovanja uporabniških preferenc.
Sveža kopija je dejansko obnovljena v novi MariaDB 10.11.19 z `network=none`:
**86 tabel, 247 vrstic, 2.849 zasebnih datotek**. Kopija je zunaj repozitorija
in spletnih map; preverjen vsebnik je ustavljen.

- Izvorni ZIP SHA256: `630b22150b4ed090110b39804cdbf64672bcdbb8cf5964cf2a66c1db3e96befe`.
- Zasebni arhiv SHA256: `7243db513e84dd187418e961952658557f6d23624d52aca8d80da15ab6b6da5c`.
- Ob aktivaciji so vse vrstice, definicije tabel/indeksov, različice drugih
  vtičnikov, računi/gesla/serverId, konfiguracija in zasebne datoteke nespremenjeni.
- Izvirni cron in `.htaccess` sta obnovljena. Vseh pet delavcev je ob 07:30:01
  samodejno ustvarilo nov veljaven status po odprtju strani (0600).
- Read-only pregled ob 07:30:08 potrdi vseh 81 izvornih datotek, pravilne
  privzete vrednosti vseh šestih kategorij, ohranjeno shranjeno vrstico nastavitev
  in izrecni izklop. SMTP/FCM sta oglaševana prek dejanskega HTTPS API.
- Po odprtju se lahko podatki ponovno spreminjajo: 85/86 zgodovinskih tabel se
  še ujema s kopijo; ob aktivaciji se je ujemalo vseh 86. To ni vrnitev stare baze.
- Pomočnik: 34 filesystem + 22 MariaDB kontrol PASS; readonly verifier ima še
  dve celoviti sintetični MariaDB kontroli. [Postopek](../server/NOTIFICATION_UPGRADE_HELPER.md).
- Lokalni dokazi: `build/qa/notification-release-20261011/restore-evidence.json`,
  `hosted-verification.json`, `hosted-capabilities.json` in dnevniki pomočnika.

## Android

Google Play prikazuje **Aktivno / 1.3.1 (16) — preprostejša obvestila**, na voljo
internim preizkuševalcem **11. oktobra 2026 ob 07:30**, samo seznam **domači (15)**.
[Interni kanal](https://play.google.com/apps/internaltest/4701286726300038561).
Podpora napravam je nespremenjena; SL/EN opombe so objavljene.

- `build/releases/Jivie-1.3.1+16-android-firebase.aab`, 79.385.450 bajtov.
- SHA256: `e0a7bf0a9df8926a07ce230d374564f7badd8348d7a79c5134245bbc190c6315`.
- Isti podpis kot 15, ZIP/bundletool, ID `si.triparna.jivie`, min24/target36,
  enaka dovoljenja, Back callback, vseh osem 64-bitnih knjižnic 16 KiB,
  native/Dart Firebase so preverjeni.
- 329 zamrznjenih vhodov se ujema s commitom 13e8f46; 18 izdajnih in 7 Firebase
  testov ter izvorni checker PASS.
- Dokazi v `build/qa/jivie-notification-release-20261011/`:
  `android-release-artifact-evidence.json`, `source-input-manifest.json`,
  `play-internal-1.3.1-16-active.png`, `play-testers-domaci-15.png`.

## Mac

Podpisana **1.3.1 (16), arm64 Debug** je odprta iz
`build/qa/jivie-notification-mac-20261011/SignedProducts/Debug/Jivie.app`.
Strogi podpis, isti certifikat/profil/Keychain, identiteta `com.example.kanban`,
326 vhodov in vseh 295 skupnih Android/Mac hashov so preverjeni. Stari Mac/AAB15
artefakti ostanejo ohranjeni. To ni notarizirana ali Mac App Store distribucija.

Proces nove poti je preverjen; račun **takndev**, potrjeni naslov, testni strežnik,
izbrani projekt **poskus deljenja** in obstoječa obvestila so ohranjeni. Gumb
**Označi vse kot prebrano** je dejansko viden. Ni bil pritisnjen, da obvestila
ostanejo za uporabnikov preizkus. Dokazi so v istoimenski QA mapi: podpisni
povzetek, `runtime-check.json`, `android-overlap-verification.json` in
`mac-inbox-new-button.png`.

## Naslednji fizični preizkus

1. Posodobi telefon na 1.3.1 (16), preveri registracijo naprave in Android dovoljenje.
2. Telefon zakleni; iz drugega računa na Macu dodaj/spremeni skupno opravilo ali
   dogodek. Preveri push na telefonu in klik do pravega zapisa. Dostava je prek
   rednega minutnega crona; spremembe istega avtorja ne ustvarijo lastnega opozorila.
3. Preveri skupno označitev prebranega in odstranitev oznake zvončka za trenutni
   pogled. Nato preveri izklop kategorije.

Shranjeni izrecni izklopi ostanejo veljavni; po potrebi jih uporabnik v nastavitvah
vključi sam. Stara obvestila se ne pošiljajo za nazaj. Mac v tej izdaji podpira
center obvestil v aplikaciji, **ne oddaljenih sistemskih push obvestil**.
Fizični preizkus nove Android dostave ostaja odprt; objava sama ga ne dokazuje.
