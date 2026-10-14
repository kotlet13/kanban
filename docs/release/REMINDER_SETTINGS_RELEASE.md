# Android 1.8.0 (27) — enotne nastavitve opomnikov

14. oktober 2026. Uporabnik izrecno naroči novo Android različico in javno
objavo; interni kanal mora ostati izklopljen. Funkcionalni commit **44bdd2b**.
[Opis vedenja](../REMINDER_SETTINGS.md) ostane vir nastavitev in njihovih mej.

## Mobilni izvor in gradnja

Nova izdaja uporablja zamrznjeno mobilno osnovo javne AAB26 (fa809b8 plus
6ae5667 povezovanje) in natanko nastavitve opomnikov iz44bdd2b. Skupni
podatkovni/UI vhodi so enaki pregledanemu popravku; mobilni organizer_shell
ima šest majhnih prenosov povezav/menija/naslova. Lokalizacije vključujejo
16 novih besedil SL/EN, brez kasnejših namiznih dodatkov. Namizna prenova
iz main ni vključena. Različica je **1.8.0+27**; dejanski aktivni iOS26 ostane
isti, ni nove Apple gradnje/oddaje.

Vseh **323 zamrznjenih vhodov** in vsi trije zasebni konfiguracijski hashi
so preverjeni pred/po gradnji; sprememba proti26 je19 vhodov, samo nastavitve
in različica. Oba locka sta byte-identical, Flutterjev pogon v vseh treh ABI
je byte-identical s26. SDK/odvisnosti/native konfiguracija niso nadgrajeni.

Podpisana `build/releases/Jivie-1.8.0+27-android-firebase.aab`:
**78.476.231 bajtov**, SHA256
`a8a328e05e3b495e6bfbcc1106d2ae70a4c5f32d12309818d3f86dced9a0bea7`.
AAB in checksum sta read-only; stare AAB25/26 ostanejo ohranjene.
Isti namenski upload certifikat, si.triparna.jivie, min24/target36, Back
callback in share FileProvider. Bundletool/signature/ZIP CRC,16KiB vseh8
64-bitnih knjižnic, istih8 dovoljenj in native/Dart Firebase identiteta
so PASS. Zasebne konfiguracije/ključev ni v paketu.

## Ciljno preverjanje

**104 testov PASS** v že preverjenem main izvajanju in nato tudi v natančno
izoliranem mobilnem izvoru te izdaje; drugi zagon potrjuje mobilni prenos
menija/zaslona, ne nove splošne funkcionalne matrike. Preverjeni so dejanska
SQLite transakcija/rollback/vrsta/ACK, menjave računov, lokalni alarmi/zvok
in izklopi po projektu, center/neprebrano ter navigacija ozkih prikazov/2×.
Izolirana analiza: **No issues found**. Pregledan je tudi widget izris z
resničnimi pisavami; vzorci so samo v testni pomnilniški shrambi.
**23 izdajnih +7 Firebase kontrol PASS**, source checker PASS. To niso
fizični preizkusi nove nameščene aplikacije.

## Play Console

Javni kanal4698247597354229997, nova izdaja3; preverjena AAB27 je naložena
neposredno v produkcijo. Samo27 vključena,26 izključena iz nove izdaje. Ime **1.8.0 (27) — enotne nastavitve opomnikov**, SL/en-US opombe
o enem zaslonu, nastavitvah prostorov/projektov in zvoku so vpisane.
**Oddaja je dejansko potrjena**: Shrani → Pošlji1spremembo v pregled →
Pošljite spremembe v pregled. Console kaže **Spremembe v pregledu** in točno
1.8.0(27) / Začetek uvajanja za vse. Hitra samodejna preverjanja še tečejo;
Google bo začel dejanski pregled po uspešnem zaključku teh preverjanj.
Uvajanje100%, ista edina država **Slovenija** sveže preverjena samo za branje;0 izgubljenih/novih podprtih naprav.
Upravljano objavljanje jeOFF, zato bo izdaja objavljena po odobritvi.
**Odobritev/javna razpoložljivost27 še nista potrjeni**; prej javna26 ostane
na voljo. Ni avtomatizacije ali ponovne oddaje istega paketa.

Interni4701286726300038561 je sveže potrjen **Neaktivno / Ta različica je
začasno zaustavljena**. Ni nove interne izdaje ali nadaljevanja preizkusa;
stari seznam/zgodovina/paketi ostanejo. Produkcijski strežnik, FamilyHub,
podatki, SMTP/FCM ključi, splet/Console opisi in deklaracije ostanejo isti.

Dokazi: `build/qa/reminder-settings-release-20261014/android/`:
source-input-manifest.json, mobile-shell-port.diff, isolated-reminder-tests.txt,
isolated-analysis.txt, build.txt, verification.txt, android-release-artifact-
evidence.json ter internal-inactive.png. public-submitted.png/.txt in play-release-evidence.json potrjujejo oddajo.
