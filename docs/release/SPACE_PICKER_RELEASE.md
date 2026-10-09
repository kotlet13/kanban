# Jivie — izdaje izbire prostorov

## Dopolnitev 1.1.7 (10): zaprti izbor

Stanje 9. oktobra 2026: funkcionalni commit/push `aad346d` in izdajna priprava `c2a2b9e` sta na `origin/codex/navigation-task-opening`. Podpisani AAB je preverjen in objavljen na istem internem kanalu. **Google Play potrdi Aktivno / 1.1.7 (10) — ikona in poravnava izbora prostora, na voljo notranjim preizkuševalcem 9. oktobra 2026 ob 12:21.** Izbran ostaja seznam **domači (15)**, podpora napravam je nespremenjena. Opombe ob izdaji so shranjene v SL/EN. Dokaz: `build/qa/jivie-space-picker-closed-release/play-internal-1.1.7-10-active.png`. [Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Popravek poravna zaprti izbor z ostalimi elementi telefonske glave ter doda ikono vrste prostora, manjše besedilo, zadržano ploskev in obrobo. Ohranjen je vsaj 48 px cilj dotika, prilagajanje povečani pisavi, celoten namig dolgega imena ter odprti meni. [Izvedbeni dokazi](../UPGRADE_IMPLEMENTATION.md) vključujejo predhodno reprodukcijo 12 px napačne poravnave.

- **48 ciljnih UI testov PASS**, vključno z izbirnim Android renderiranjem; analiza brez napak/opozoril s 37 obstoječimi info. Preverjene so širine 320/390/600/1280, SL/EN ter 1×/2× besedilo. Vizualni dokazi: `build/qa/jivie-space-picker-closed/`.
- Izdajna orodja **18 PASS** in `check_readiness.py --code-only` PASS po izrecnem dvigu različice. Prejšnjih sedem Firebase testov je bilo uspešnih; konfiguracija in koda dostave sta nespremenjeni, zato niso ponovno izvedeni.
- Gradnja `flutter build appbundle --release --dart-define-from-file=.firebase/client.json` je uspešna. Končni AAB: `build/releases/Jivie-1.1.7+10-android-firebase.aab`, **77.619.365 bajtov**. SHA256: `8136306ba4b7646f9a3410944bc1f4220f208b7e8123254c91ea221dd4df6ce0`.
- Manifest potrdi `si.triparna.jivie`, 1.1.7/kodo 10, min SDK 24/target SDK 36 in Android Back callback. Podpis se ujema z objavljenim AAB 9. Jarsigner, bundletool in ZIP CRC uspešni; `PAGE_ALIGNMENT_16K` ter vseh osem 64-bitnih ELF knjižnic sta preverjena.
- Native Firebase identiteta se ujema z AAB 9, projekt `jivie-e928a` pa je prisoten v Dart AOT vseh treh ABI. Zasebnih ključev, podpisnih datotek, service-account podatkov in client.json kot sredstva aplikacije ni v AAB.
- Dokazi paketa: `build/qa/jivie-space-picker-closed-release/android-release-artifact-evidence.json` in spremljajoči dnevniki. JSON opisuje paket pred nalaganjem; objava se vodi ločeno.

SDK, odvisnosti, identitete, podatkovne sheme in strežnik so nespremenjeni. Fizični prikaz novega popravka še čaka uporabnikov preizkus; javna objava in iOS ostajata ločena koraka.

## Prejšnja izdaja 1.1.6 (9)

Stanje 9. oktobra 2026: **Google Play potrdi Aktivno / 1.1.6 (9) — preglednejši izbor prostorov, na voljo notranjim preizkuševalcem od 11:05.** Izvorne spremembe in izdajna priprava so commitane in poslane na `origin/codex/navigation-task-opening`.

## Vsebina

Izbor prostorov ima zaobljen meni, ikone, oznake vrste prostora, jasno označeno izbiro s kljukico ter ločeno akcijo »Nov prostor«. Uporablja obstoječo svetlo in temno temo. Obstoječe izbire Vsi, osebno in skupno ter vedenje ustvarjanja, arhiva in zavrnjenega dostopa ostanejo ohranjeni.

- `58291d5`: priprava predstavitve v Googlu Play, izvornih slik in statične spletne strani.
- `d268074`: priprava ločene produkcijske namestitve; strežnik še ni aktiviran. [Stanje produkcije](../server/PRODUCTION_SETUP.md).
- `bfc85d5`: funkcionalna sprememba izbire prostorov.
- `106bbef`: izrecni dvig na `1.1.6+9` po funkcionalnem commitu/pushu.

Identiteta ostaja `si.triparna.jivie`. SDK, odvisnosti, lokalna shema in strežniške pogodbe se v tej izdaji ne spreminjajo. Pripravljena javna predstavitev še ni oddana v pregled; ta objava je namenjena obstoječim internim preizkuševalcem.

## Preverjanje

- **59 ciljnih Flutter UI testov PASS**: kompaktna glava in Vsi (46), organizacije/osebe (13).
- `flutter analyze`: brez napak/opozoril, 37 obstoječih info.
- Generiranje lokalizacije, formatiranje in `git diff --check`: uspešno.
- Telefonski širini 320/390, tablična in namizna umestitev, SL/EN in 2× povečava besedila: preverjeno.
- Dejanski render svetlega/temnega menija pri 390×844 je vizualno pregledan v `build/qa/jivie-space-picker/`; uporabljeni so izolirani testni podatki.
- Izdajna orodja **18 PASS**, Firebase orodja **7 PASS**, izvorni release checker PASS. Po dvigu različice sta izdajni nabor in checker ponovno uspešna.
- Pregled spremenjenih/novih datotek ni našel skrivnosti ali zasebnih izvozov. Vseh 15 trgovinskih PNG ustreza inventarju in hashom; slike uporabljajo sintetične podatke.

## Podpisana Android gradnja

`flutter build appbundle --release --dart-define-from-file=.firebase/client.json` je uspešen. Končni AAB je `build/releases/Jivie-1.1.6+9-android-firebase.aab`, 77.583.118 bajtov, SHA256 `561a91c14deb7b5f13a8d250df537a1e665da8673f5be1e31c3758e1e6b4d91a`.

Preverjeni so pravi ID in različica, min SDK 24/target SDK 36, omogočen Android Back callback, isti namenski upload certifikat kot pri objavljeni gradnji 8, `jarsigner`, `bundletool validate`, ZIP CRC, `PAGE_ALIGNMENT_16K` in vseh osem 64-bitnih ELF knjižnic. Native Firebase identiteta se ujema s prejšnjo izdajo; projekt `jivie-e928a` je prisoten tudi v Dart AOT vseh treh ABI. AAB ne vsebuje service-account datoteke, podpisnih skrivnosti, zasebnega ključa ali datoteke client.json kot sredstva aplikacije.

Dokaz: `build/qa/jivie-space-picker-release/android-release-artifact-evidence.json`, spremljajoči manifest, dnevniki in podpisni izhodi. Dokazni JSON opisuje stanje lokalnega paketa pred nalaganjem; stanje objave se vodi ločeno. Nov fizični preizkus prikaza na Samsungu ostaja uporabnikov korak po posodobitvi.


## Objava v Googlu Play

Naložen je preverjeni AAB zgoraj. Predogled potrdi različico 9 (1.1.6), target SDK 36 ter nespremenjeno podporo napravam. Opombe ob izdaji so shranjene v slovenščini in angleščini. »Shrani in objavi« je izveden samo za obstoječi interni kanal `4701286726300038561`; izbran ostaja seznam **domači (15)**.

Končni prikaz: **Aktivno**, najnovejša izdaja **1.1.6 (9) — preglednejši izbor prostorov**, **Na voljo notranjim preizkuševalcem**, 9. oktober 2026 ob **11:05**. Dokaz: `build/qa/jivie-space-picker-release/play-internal-1.1.6-9-active.png`. [Povezava za posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Uporabnik je nato na S25 potrdil videz odprtega menija ter opozoril na previsoko ime/puščico in manjkajočo ikono v zaprtem izboru. [Lokalno preverjeni nadaljnji popravek](../UPGRADE_IMPLEMENTATION.md) še ni del objavljene 1.1.6 (9). Javna objava, iOS in dokončanje novega produkcijskega strežnika so ločeni koraki.
