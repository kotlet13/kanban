# Sprememba prijavnega gesla — 1. november 2026

## Strežniška pogodba in varovanje podatkov

`features.passwordChange: true` oglašuje novi prijavljeni API
`account.password.change`. Zahteva sprejme `currentPassword`, `newPassword`
in opcijski `otp`. Uspešen odgovor je
`{changed: true, sessionPreserved: true, accountId, deviceId}`.
Storitev deluje tudi brez nastavljenega SMTP; starejši strežnik te zmožnosti
ne oglašuje.

Operacija preveri dejansko trenutno geslo z obstoječim `stepUp`, aktivnost in
lokalnega ponudnika računa, veljavnost napravne seje, časovno zaklepanje,
omejitev poskusov ter obstoječi TOTP in njegovo zaščito pred ponovitvijo.
Neuspešni poskusi ohranijo zapis števcev. Nova omejitev je 20 poskusov/IP/15
minut in 10 poskusov/račun/15 minut. Novo geslo zahteva najmanj 12 in največ
72 UTF-8 bajtov; ničelni bajt in neveljaven UTF-8 sta zavrnjena. Gesli se
**ne obrezujeta**: `NativeDatabase.text` ohrani bajte enako kot prijava.

Po omejevanju poskusov storitev ponovno prebere in zaklene trenutno osebo ter
točno napravo. V eni transakciji spremeni zgoščeno geslo in posodobi samo
`credentials_hash` trenutne napravne seje. Njen žeton, ID, rok veljavnosti in
push ostanejo isti. Druge native prijavne seje istega računa se prekličejo in
njihova čakajoča push dostava se ustavi. To ni preklic E2EE naprave:
kriptografske naprave, korenski ključi, certifikati, keyring, šifrirana vsebina,
članstva, podpisana zgodovina in drugi računi ostanejo nespremenjeni.

Neporabljeni reset/verify žetoni in njihove čakajoče šifrirane pošte se
prekličejo, `pending_email` se počisti. Za preverjen naslov se v obstoječo
varnostno vrsto doda fiksni dogodek `auth.passwordChanged`; podprt je tako v
pošiljalčevi allowlist kot v slovenskem/angleškem besedilu. Dogodek nima gesla,
obnovitvene datoteke, žetona ali E2EE ključa. Napaka pri shranjevanju dogodka
razveljavi celotno spremembo.

## Ločena e-poštna ponastavitev

`auth.reset.request` in `auth.reset.confirm` ohranita obstoječo ponastavitveno
semantiko: uspešna e-poštna ponastavitev prekliče **vse native prijavne seje**,
vključno s trenutno. Ne spremeni E2EE ključev ali šifrirane vsebine.

`auth.reset.confirm` dodatno sprejme opcijski par `expectedAccountId` in
`expectedServerId`. Če je naveden samo en podatek ali podatek ni UUID, vrne
`validation_error`; če se veljavna para ne ujemata z računom reset žetona in
trenutnim strežnikom, pred spremembo vrne
`password_reset_identity_mismatch` (409). Javni tok brez para ostane podprt.

## Novi lokalni dokazi

Root je centralno izvedel `server/tests/password-change-integration.php` v
novem disposable Docker procesu z `--network none --read-only --tmpfs /tmp`,
read-only izvorom in svežim SQLite `:memory:`. Nobena obstoječa baza, volumen,
strežnik ali telefon ni bila uporabljena.

- Prvih 8 novih skupin: **64 PASS, poskus 1**;
  `build/qa/password-change-20261101/backend-attempt1.log`.
- Ločeno dodana skupina `rollback`: **2 PASS, poskus 1**;
  `build/qa/password-change-20261101/backend-rollback-attempt1.log`.
- Skupaj **66 različnih kontrol / 9 skupin**. Uspešnih skupin nismo ponavljali.
- PHP lint šestih produktnih datotek in nove testne datoteke: PASS.
- Reviewer je po prvem PASS popravil samo fixture: pri TOTP replay uporablja
  že sprejeto kodo, namesto da bi ponovno računal kodo ob možnem 30-sekundnem
  prehodu. Semantika in produktni izvor sta ista; uspešna skupina ni ponovljena.

Kontrole uporabljajo pravi dispatcher, password hash/verify, TOTP, novo shemo,
realni AEAD primer in dejanske SQL spremembe. Preverijo nespremenjene E2EE
tabele ter nadaljnjo dekripcijo, ohranjeno trenutno prijavo/obnovo seje,
preklic drugih sej in njihovega push, tuje račune, točne bajte gesla,
nepravilno geslo/TOTP, zaklepanje, rate limit, neveljavne račune/seje,
razveljavitev starih žetonov, vezavo email reset ter pravo varnostno vrsto
s sintetičnim transportom. Deterministični interleaving hook med preverjanjem
pred pogoji in zaklenjenim branjem sproži pravi revoke, reset ali konkurenčno
spremembo gesla. To ni dokaz resnične sočasnosti MariaDB, HTTP, dejanske SMTP
dostave ali mobilne/native uporabe.

## Paket za poznejšo namestitev

Šest datotek pod `server/plugins/FamilyHub/Model/`:

1. `NativePasswordChangeService.php` — nova storitev.
2. `NativeAccountService.php` — usmeritev pred SMTP gate.
3. `NativeService.php` — nova capability.
4. `NativePasswordResetService.php` — opcijska vezava ponastavitve.
5. `NativeAccountMailTransport.php` — fiksna varnostna besedila.
6. `NativeSecurityMailQueue.php` — allowlist dogodka.

**Brez migracije sheme, DDL, spremembe konfiguracije ali ključev.**
`build/qa/password-change-20261101/backend-source-manifest.json` vsebuje
lokalne SHA-256 in predhodne hashe iz Git HEAD; slednji niso preverjanje žive
produkcije. Produkcijske predhodne hashe in dejansko namestitev preveri root.
Ta lokalni zapis še ne potrjuje namestitve na produkcijo ali nove Play izdaje.

## Odjemalec: neposredna sprememba in ločena e-poštna ponastavitev

V **Račun → Spremeni geslo** je obrazec dostopen neposredno, brez čakanja na
čarovnika zaščite ali nalaganje e-poštnega povzetka. Uporabi trenutno geslo,
novo geslo dvakrat in opcijski TOTP. Slovensko in angleško besedilo jasno
pove, da trenutna naprava ostane prijavljena, druge naprave pa se morajo
znova prijaviti. Gesli se posredujeta dobesedno, brez obrezovanja; nova
omejitev uporablja obstoječo validacijo 12–72 UTF-8 bajtov. Obstoječi
`SharingField` ohrani varovanje IME/focus lifecycle za skrivne vnose.

Repository pred dejanjem sveže preveri identiteto strežnika in capability
`passwordChange`. Odgovor mora potrditi `changed`, `sessionPreserved`,
isti `accountId` in `deviceId`. Epoch, partition, device in bearer ostanejo
varovani; običajna obnova veljavnosti iste napravne seje je dovoljena.
Točna operacija `account.password.change` obide vsebinski E2EE router,
zato spremembe gesla ne blokirata šifrirni floor ali nedokončana obnova
vsebine. Splošne vsebinske varovalke ostanejo iste.

Napačno trenutno geslo/TOTP ne razveljavi aktivnega bearerja. Dejanski
`device_revoked` in druge običajne prijavne napake še vedno uporabijo
obstoječo invalidacijo. Po izgubljenem odgovoru ni samodejnega ponavljanja;
obrazec pojasni, da je geslo morda že spremenjeno, in ponudi preverjanje na
drugi napravi ali e-poštno ponastavitev. Nobena nova koda ne shranjuje ali
izpisuje gesel, ne izvaja prijave/odjave ter ne inicializira ali obnavlja E2EE
ključev.

E-poštna možnost na isti kartici je jasno ločena. Zahteva potrditev opozorila:
potrditev kode prekliče **vse prijavne seje, tudi trenutno**, geslo samo pa
ne obnovi ključev ali podatkov; obnovitveno datoteko je treba ohraniti.
Strežnik/uporabniško ime sta fiksirana na začetni prijavljeni račun.
Potrditev kode pošlje `expectedAccountId` in `expectedServerId`; tuja koda
se zavrne pred spremembo. Uspeh označi samo še veljavno začetno sejo kot
`session_expired`, ohrani lokalne podatke/ključe in pokaže neposredno možnost
ponovne prijave. Kartica pri neveljavni seji onemogoči spremembo gesla.
Stari strežnik dobi jasno obvestilo o potrebni nadgradnji; geslo se ne pošlje.

## Dokazi odjemalca in omejitve poskusov

Root je serijsko izvedel nova sklopa:

- `test/organizer/data/account_password_change_20261101_test.dart`:
  **9 različnih PASS v poskusu 3**;
  `build/qa/password-change-20261101/client-core-attempt3.log`.
- `test/organizer/ui/account_password_change_20261101_test.dart`:
  **7 različnih PASS v poskusu 1**;
  `build/qa/password-change-20261101/client-ui-attempt1.log`.
- Skupaj **16 novih odjemalskih kontrol** in 66 strežniških kontrol =
  **82 različnih lokalnih kontrol**. Uspešnih UI testov nismo ponavljali.

Prvi core poskus je imel 0 PASS/9 FAIL: fixture pri samodejnem sync po
prijavi ni izrecno dovolil sintetičnega starega protokola. Popravek doda
obstoječi `SyntheticContentRouteGuard`, ki ne obide aktivnih E2EE floorov
ali restore fences, in zagotovi zaprtje baze tudi ob napaki inicializacije.
Drugi poskus je imel 8 FAIL in en navidezni PASS: novi fake je vrnil
`features` kot `Map<dynamic,dynamic>`, dejanski produkcijski decoder pa
vrne `Map<String,dynamic>`. Sync discovery je prvotno razliko prikril s
JSON kopijo; neposredna capability poizvedba jo je pravilno zavrnila.

Navidezni PASS za tujo reset kodo je imel preširok matcher in sprejel
`incompatible_server`; **ta rezultat je razveljavljen in ni dokaz uspeha**.
Pred tretjim poskusom je bil bistveno popravljen na točno
`password_reset_identity_mismatch` in natanko eno dejansko reset operacijo.
Tudi druge negativne kontrole zahtevajo točne kode. Tretji poskus preveri
vseh 8 prej neuspešnih in to popravljeno kontrolo; ni ponovitev veljavnega
PASS. Nobena produktna varovalka zaradi fixture napak ni bila oslabljena.

Kontrole uporabljajo pravi memory SQLite/repository in sintetični transport;
UI uporablja widget/provider seams. Vključijo dobesedna gesla, ohranjen
bearer in secure-store objekt, brez novih credential SQL zapisov, napačno
geslo/TOTP proti resnični invalidaciji naprave, star strežnik, napačno
identiteto odgovora, switch računa, vezan email reset, izgubljen odgovor
brez ponovitve ter aktivni E2EE floor z nedokončanim restore fence.
To ni nov HTTP, native IME, Samsung, E2EE obnova ali SMTP runtime PASS.
Odjemalski agent ni izvajal gradnje, namestitve, telefonskih dejanj,
produkcijskih zahtev ali Git operacij.

Končni ciljni statični pregled je zapisan v
`build/qa/password-change-20261101/client-analyze-final.log`. Ukaz:

```text
dart analyze lib/organizer/data/collaboration_account_actions.dart lib/organizer/data/collaboration_account_recovery.dart lib/organizer/data/collaboration_repository.dart lib/organizer/data/e2ee/crypto_domain_router.dart lib/organizer/domain/collaboration_models.dart lib/organizer/state/collaboration_provider.dart lib/organizer/presentation/shared/sharing_account_page.dart lib/organizer/presentation/onboarding/account_password_card.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_sl.dart test/organizer/data/account_password_change_20261101_test.dart test/organizer/ui/account_password_change_20261101_test.dart
```

Rezultat: **0 errors, 0 warnings, 2 obstoječa info** za stare neobdane
`if` stavke v `collaboration_provider.dart`; nobeden ni v novem izvoru.
Format in ciljni `git diff --check`: PASS. Produkt je po lokalnem PASS
zamrznjen za rootov pregled, commit, strežniško namestitev in pripravo javne
Android izdaje; ta odjemalski razdelek ne potrjuje njihove izvedbe.

## Produkcijska namestitev

Uporabnik je naknadno izrecno odobril strežniško nadgradnjo in novo javno
Android izdajo. Produkt `0dedf33` je commit/push. Produkcija je prejela šest
PHP datotek **1. novembra ob 18:55:00 UTC**. Paket SHA-256
`49bb4ebeccf4cec99bca266c7d08bacb978f0fd6f711361b7489cd61ac45e286`
je preverjen pred razpakiranjem v zasebno mapo. Predhodni izvorni hashi vseh
obstoječih datotek se ujemajo z manifestom; nova storitev prej ni obstajala.
PHP 8.4 lint, zasebna kopija starih datotek, atomarne zamenjave posameznih
datotek in končni hashi so uspešni. Capability je objavljena zadnja.

`config.php` pred/po ima SHA-256
`316dbbd0558c9fb1d914efcaa2651d4bcea460e58aaecaaf5830147d7a248ee4`.
Namestitveni helper ne dostopa do podatkovne baze, ne izvaja DDL in ne
spreminja nobenega uporabnikovega gesla, prijave, ključa, SMTP ali cron nastavitev.
Javni HTTPS capabilities vrne HTTP 200, isti SID in `passwordChange=true`,
`passwordReset=true`; upravljavec ostaja Anže Novšak, TriparNA z.o.o.
To ni produkcijski preizkus dejanske spremembe uporabnikovega gesla.

Dokazi: `build/qa/password-change-20261101/production-deployment-result.json`,
`production-deployed.png`, `production-capabilities-after.json`.
Rezultat je prenesen iz cPanel File Manager; SHA-256
`6908035a9e247b144666ea8278a85910efa01861d6e98773af63440f8dc95109`.
Zasebna strežniška kopija je v
`/home/tripar13/private/jivie-production/password-change-20261101/before`.
Telefoni niso bili upravljani. Naslednji korak je oddaja Android 1.11.8 (40)
in nato uporabnikov preizkus na isti prijavljeni napravi.

Android 1.11.8 (40) je oddan v javni pregled; končni dokaz in omejitve so v
`docs/release/ANDROID_1_11_8_2026_11_01.md`. Javna razpoložljivost še ni potrjena.
