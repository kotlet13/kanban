# Lokalni šifrirani trezor — izvedba P1

Datum: 17. oktober 2026. Izhodišče pred to nadgradnjo:
`4c6b35d582d4873641c6c27bb7bbfa10da821999`.
Povezave: [glavni načrt](E2EE_UPGRADE_PLAN.md),
[karta kode](E2EE_CODE_MAP.md), [skupni status](E2EE_IMPLEMENTATION.md).

To je zapis izvedene izvorne kode in sintetičnih lokalnih preizkusov.
Ni dokaz fizične posodobitve uporabnikove naprave, nameščene izdaje ali
šifriranja obstoječih strežniških prostorov. Produkcijskih podatkov nismo odprli.
Verzija aplikacije, Flutter SDK in trgovinske oddaje ostajajo nespremenjeni.

## Obseg in jasne meje

Native aplikacija odpre skupno SQLite bazo šele po vzpostavitvi trezorja.
Šifrirana je **celotna namestitev**, vključno z vsemi odjavljenimi lokalnimi
profili, lokalnimi in prenesenimi zapisi, priponkami/slikami v SQLite BLOB,
osnutki, zgodovino, konflikti, izhodnimi vrstami in identitetami. Nismo izvedli
projekcijskega izvoza/uvoza uporabniških modelov kot nadomestila za selitev baze.

Instalacijski obnovitveni ključ in računov obnovitveni ključ sta ločena.
Datoteka namestitve odpre obstoječi fizični trezor; sama **ne vsebuje podatkovne
kopije**. Izgubljene baze ali priponk brez podatkovne kopije ne more obnoviti.
Imetnik te datoteke lahko odpre vse podatke te namestitve, če dobi tudi bazo.

Zaščita je lokalna baza in znane občutljive nastavitve. Prejšnji izvozi,
kopije starega sistema, neidentificirani stari predpomnilniki in izvorne
uporabnikove datoteke niso s tem naknadno šifrirani. Splošne trditve
»vsi lokalni podatki so šifrirani« zato še ne uporabljamo.

## Ključ, pogon in povezave

| Del | Izvedeno vedenje |
| --- | --- |
| [LocalVaultService](../lib/organizer/data/local_vault.dart) | `inspect`, `prepareRecoveryFile`, `verifyRecoveryFile`, `migrate`, `recover`; UI vidi fazo in varno kodo napake, ne ključa. |
| [SecureLocalVaultKeyStore](../lib/organizer/data/local_vault_keys.dart) | Naključen 32-bajtni ključ in ID trezorja; varna shramba mora zapis dejansko prebrati nazaj. |
| [LocalVaultCipher.configure](../lib/organizer/data/local_vault_cipher.dart) | SQLite3 Multiple Ciphers, `chacha20`, `legacy=0`, `kdf_iter=64007`, `plaintext_header_size=0`, `hmac_check=1`, `mc_legacy_wal=0`; format1. |
| [LocalVaultKey](../lib/organizer/data/local_vault_keys.dart) | `raw:` 32-bajtni ključ; HKDF-SHA256 loči ključe arhiva in nastavitev; AES-256-GCM preizkus veže obnovitveno datoteko na ID trezorja. |
| [native executor](../lib/organizer/data/collaboration_database_native.dart) | Vsaka Drift povezava dobi konfiguriran pogon pred SQL branjem; manjkajoč pogon ali ključ ustavi odpiranje. |
| [native servis](../lib/organizer/data/local_vault_native.dart) | Pot `jivie_vault_v1/data.sqlite`; pogon, journal, izvor in varnostni arhiv se preverijo pred preklopom. |

ChaCha20 uporablja overitev Poly1305 in 32 rezerviranih bajtov na SQLite stran.
Naključni ključ ni uporabniško geslo; `raw:` obide geselski KDF. Izrecna nastavitev
KDF je del zamrznjenega formata, ne trditev o uporabi geselske zaščite tega ključa.
Načrtovana menjava formata potrebuje novo verzijo in posebno selitev.

`temp_store=MEMORY` prepreči običajne SQLite začasne datoteke;
`synchronous=FULL` velja za povezave trezorja. Zahteva `memory_security=1`
na preizkušenem pogonu **ne vrne vrednosti**. Ne trdimo, da pogon zagotavlja
brisanje pomnilnika; to ne varuje pred odklenjenim kompromitiranim procesom,
OS posnetki pomnilnika ali zlonamerno tipkovnico.

Pogodba ne uporablja `assert` za preverjanje pogona. Napačen ključ se zavrne
ob dejanskem branju sheme, ne šele glede na uspeh `PRAGMA key`.
[pubspec.yaml](../pubspec.yaml) določa `sqlite3: 3.7.0` in native hook
`source: sqlite3mc`. Za računov modul je dodan `sodium: 4.0.4`; ozke prehodne
spremembe so v zaklenjenem `pubspec.lock`, brez menjave SDK ali app verzije.

## Ponovljiva selitev in ohranitev

1. Izključni OS zaklep prepreči sočasno selitev novih procesov. Naključen ključ
   se najprej preverjeno shrani, nato se atomsko shrani javni journal. Prekinitev
   med tema korakoma ponovno uporabi že shranjeni ključ.
2. Uporabnik lokalno shrani obnovitveno datoteko in jo ponovno izbere. Šele
   preverjanje istega ključa/trezorja odpre fazo `recoveryVerified`.
3. `BEGIN IMMEDIATE` na stari bazi zadrži druge pisce med kopiranjem. Ločena
   bralna povezava uporablja neposredni `VACUUM INTO` v **šifrirani** kandidat;
   ni vmesne plaintext baze, prenosa skozi model ali rekey edine kopije.
4. [LocalVaultSnapshot.fingerprint](../lib/organizer/data/local_vault_snapshot.dart)
   primerja vso shemo, vse tabele in SQLite podatkovne tipe, ne samo znanih
   tabel aplikacije. Vključuje indekse, trigerje, poglede, neznana polja,
   `sqlite_sequence`, implicitne rowid, BLOB in surove bajte TEXT. SQLite cookie
   `schema_version`, ki ga VACUUM spremeni, se izrecno nastavi na izvorno vrednost.
   Virtuelne tabele in primer brez dosegljivega rowid se varno zavrnejo.
5. Nastane ločen šifriran arhiv prvotnih DB/WAL/SHM/journal/Hive datotek in
   občutljivih nastavitev. Shranjen je po kosih z dolžino in SHA256. Ponovno
   odpiranje, SQLite integrity in vsak hash so obvezni pred odstranjevanjem izvora.
6. Šele potrjen kandidat in arhiv omogočita trajni `candidateVerified`, premik
   kandidata in trajni `switched`. Pri prekinitvi med premikom in journalom se
   obstoječi cilj primerja z izvorom. Nepričakovan cilj v predhodni fazi pomeni
   `vault_state_conflict`; nikoli se ga ne prepiše.
7. Stare SQL povezave in writer transakcija se zaprejo pred čiščenjem datotek.
   Nastavitve se šifrirajo s preverjenim branjem nazaj; nato se odstranijo znani
   plaintext izvori. Končni journal je `complete`.

[LocalVaultFiles](../lib/organizer/data/local_vault_files.dart) uporablja zasebne
0700/0600 poti, zavrne symlink in sinhronizira datoteko ter imenik. Premik med
imenikoma na POSIX sinhronizira oba starša. Journal se piše prek `.next` in
atomskega premika. Windows veja uporablja `MoveFileExW` z `WRITE_THROUGH`;
jena odpornost proti fizičnemu izpadu še ni preverjena.

Po `switched` je nova baza edini zapisovalni vir. Ponovitev čiščenja nikoli
ne povrne starega arhiva čez nove zapise. Poškodovan/manjkajoč arhiv prepreči
brisanje ostankov; spremenjeni ponovno nastali Hive ostane ohranjen.
`cleanupPending` dovoli novo šifrirano bazo, vendar jasno ohrani nedokončan
status. Napaka občutljivih nastavitev lahko zadrži njihove odvisne storitve.

**Vse stare instance morajo biti zaprte.** Android posodobitev običajno ustavi
star proces; na namizju je to izrecen izdajni predpogoj. Stari binarni program
ne pozna novega OS zaklepa in lahko po preklopu piše v staro ali že odvezano
odprto datoteko. WAL test dokazuje ohranitev že potrjenih WAL zapisov, ne podpore
sočasnemu staremu piscu po preklopu. Izbris datoteke ni zagotovilo fizičnega
izbrisa starih strani na flashu, snapshotih ali starih kopijah.

## Hive, nastavitve in skrivnosti

Hive-only namestitev je podprta: pred čiščenjem se `committed_snapshot` preveri
z istim bralnikom in `OrganizerBackupCodec`. Surovi Hive ostane v overjenem
šifriranem arhivu. [HiveOrganizerStorage.open](../lib/organizer/data/organizer_storage.dart)
na native privzeti poti bere arhivirane bajte v **pomnilniški** Hive backend;
obstoječi atomski SQLite importer zato še vedno izvede svojo transakcijo in
`migration_snapshot`. Ne nastaja nova plaintext Hive kopija. Novejši ali
poškodovan Hive blokira čiščenje in se ne obravnava kot prazna shramba.

[LocalVaultPreferences](../lib/organizer/data/local_vault_preferences.dart)
šifrira sedem občutljivih ključev nastavitev: ID-je alarmov, SDK identiteto in
cleanup pusha, opt-in pusha ter lokalne preference opomnikov. Ovojnica je
AES-256-GCM, vezana na ime nastavitve in trezor. Če sta prisotni različni nova
šifrirana in stara plaintext vrednost, se postopek varno ustavi. Tema, jezik,
velikost okna in oznake vodiča ostajajo navadne neobčutljive preference.

[localVaultSecureStorage](../lib/organizer/data/local_vault_secure_storage.dart)
izključi Android `resetOnError`; iOS/macOS Keychain uporablja
`first_unlock_this_device`. Obstoječe seje, povabila in dostavne skrivnosti se
preverjeno ponovno zapišejo z isto vrednostjo. Izgubljen/neberljiv Keystore
ključ nikoli ne sproži brisanja, ponastavitve ali ustvarjanja prazne baze.
Faza je `recoveryRequired`; pravilna lokalna obnovitvena datoteka popravi varno
shrambo šele po overitvi obstoječega trezorja. Izbris aplikacije ni obnova.

## Mobilne datoteke in sistemske kopije

[PrivateFileChannel](../lib/organizer/platform/private_file_channel.dart) in
native handlerja nadomestijo mobilni `file_picker` pri novih uvozih/izvozih:
priponke, slike Idejnika, JSON, prenosne kopije, neusklajeno delo in obnovitvene
datoteke. Izbirnik in Dart neodvisno preverita ime, razširitev in dolžino.
Obstoječe omejitve ostajajo: slika/priponka20MiB, osebni JSON10MiB;
neusklajeno delo180MiB, skupna meja kanala192MiB. Branje poteka v omejenih kosih.

- Android: `ACTION_OPEN_DOCUMENT` neposredno bere `ContentResolver` v pomnilnik;
  `ACTION_CREATE_DOCUMENT` piše neposredno v izbrano uporabnikovo datoteko.
  Ni app-owned plaintext import/export cache. Preklic vrne ločen status.
- iOS: document picker `.open` bere security-scoped URL v pomnilnik. Izvoz
  potrebuje eno zasebno mapo `Caches/jivie-private-exports-v1/<UUID>` s pravicami
  0700/0600, `FileProtection.complete` in izločitvijo iz sistemske kopije.
  Čiščenje ob zaključku/preklicu in naslednjem varnem zagonu zajame samo ta
  namenski imenik, nikoli vseh `tmp`/Documents. Generacija zahteve, identiteta
  pickerja in faza branja zavrnejo zakasnele/dvojne native callbacke.
- OS ponudnik datotek, izbrana zunanja lokacija in uporabnikov poštni program
  upravljajo svoje kopije. Obnovitvena datoteka se ne pošlje Jivie strežniku ali
  SMTP. Uporabnik lahko shranjeno datoteko sam pripne svoji e-pošti.
- Desktop/web ohranita obstoječi OS/browser izvoz. **Web trezor ni izveden**;
  eksplicitna nepodprta veja ohrani star izvor/podatke in navadne preference.

Stari `file_picker` Android cache in iOS tmp/Documents kopije iz stare izdaje
niso zanesljivo identificirane. Brez inventarja jih ne brišemo. To je odprta
izdajna meja: lokalni DB claim ostaja ožji do varne razrešitve teh ostankov.
Povsem uporabniški izvozi ostanejo namenoma zunaj upravljanega trezorja.

Android manifest in [backup XML](../android/app/src/main/res/xml/jivie_data_extraction_rules.xml)
izključita avtomatske cloud/transfer kopije namestitve, tudi varne preference;
izrecni uporabniški izvozi ostajajo omogočeni. iOS/macOS kanal
`protectLocalStorage` izloči novi trezor in znane stare podatkovne poti iz
sistemskih kopij. Nikoli ne označi celotne uporabnikove Documents mape.
Šifriranega trezorja torej trenutno ne oglašujemo kot avtomatsko obnovljivega
prek OS backup. Prenosna kopija in datoteka ključa sta ločena uporabniška koraka.

## Preverjeno in še odprto

| Dokaz | Rezultat in meja |
| --- | --- |
| Native vault/cipher/web testi | 27 PASS; 11 crash checkpointov, dva profila, vse vrste vrst/zgodovine/BLOB, WAL, Hive-only, napačen/izgubljen ključ, disk-full, neznana struktura, poškodovan arhiv, neskladen journal/cilj. |
| Novi channel/parser/actual adapter fakes | 7 PASS; exact request bytes, napačna razširitev/velikost/ime/tip/shape, preklic, napačen save/cleanup odgovor, dejanska backup in attachment adapterja. |
| Skupaj zadnji ozki IO/vault/obstoječi file testi | 45 PASS; ne pomeni fizičnega native picker testa. |
| UI/podatkovne regresije po prvi full zbirki | 81 PASS in naknadnih25 PASS za zadnja dva sklopa; zbirki se prekrivata. Štiri stare trditve7→8 so bile neskladne že v HEAD, writer je že izvažal8. |
| Samostojni nativeasset AOT probe | Šifriran ponovni vstop, odsoten plaintext sentinel, zavrnjen napačen ključ in navadni OS SQLite; brez assertov. `memory_security` ni dosegljiv. |
| Napačen AOT pogon brez nativeassets | `vault_cipher_unavailable`, brez plaintext fallback. |
| Swift handler | Celotna datoteka grammar PASS; izolirana enaka helperja platform typecheck PASS z iOS simulator SDK/Flutter framework (dve opozorili zastarelih picker initializerjev). Ni app gradnje ali fizičnega delovanja. |
| Android handler | Kotlin2.2.20 izvorni compile PASS z lokalnim Android36/Flutter/Lifecycle jar; brez Gradle/app gradnje in brez fizičnega picker preizkusa. |

Samostojni sintetični probe je [tools/local_vault_cipher_probe.dart](../tools/local_vault_cipher_probe.dart):
`dart build cli -t tools/local_vault_cipher_probe.dart -o build/qa/local-vault-aot`.
Navadni `dart compile exe` brez nativeasset povezovanja ni izdajni način;
negativni probe `--expect-unavailable` namenoma preveri to napačno vezavo.

Pred mobilno izdajo ostajajo obvezni: prava old→new posodobitev z vsemi profili,
prekinitev/ponovni zagon in disk-full na napravah, Keystore izguba brez reseta,
ponovno branje res shranjene datoteke, iOS suspend/resume s pending WAL transakcijo
(pri `plaintext_header_size=0`), cold restore, sistemske kopije in zaklep naprave.
Windows/Linux povezovanje, Keychain/Keystore in atomski I/O zahtevajo svoje dokaze.
Starih binarnih različic po `switched` ne nameščamo kot rollback: stare aplikacije
lahko ustvarijo novo prazno legacy bazo. Downgrade/reinstall/OS restore potrebuje
usklajeno podatkovno obnovo, ne samodejnega plaintext fallbacka.

Ti fizični P8 pogoji ostajajo odprti tudi po uspešni strežniški PHP matriki ali
sintetičnem FILE preizkusu. Nova native crypto odvisnost zahteva ponovni pregled
Apple encryption izjave pred prihodnjo iOS gradnjo/oddajo. Zdaj ni spremembe
plist deklaracije ali portala, nove native gradnje ali trgovinske oddaje.

## Dodatna meja obvestil (N02)

Lokalni razporejevalnik in Androidov prikaz podatkovnih push sporočil sedaj
posredujeta OS samo »Jivie« in splošno prevedeno besedilo opomnika. Naslovi
opravil, zneski in vsebina sporočila ne vstopijo v pluginov shranjeni schedule
ali skupinski povzetek, tudi če prispe star podatkovni push. Konstruktorja
lokalnega adapterja in remote push lifecycle zahtevata izrecne zaščitene
preference. Po varnem zagonu trezorja adapter enkrat prekliče stare čakajoče
lokalne prikaze; koordinator jih ponovno izpelje iz ohranjenih zapisov opomnikov.
Zapisov opomnikov in centra obvestil ta prehod ne izbriše.

Ozki testi preverijo dejanske argumente pluginovega method channel, SL/EN
sentinele, povzetke ter ponovljiv preklic/ponovno razporeditev; niso fizični
Android/iOS dokaz. Že dostavljene OS zgodovine ne moremo varno izbrisati iz vseh
sistemskih kopij. OS-prikazanega starega APNs/FCM `notification` sporočila, ki
je bilo poslano pred nadgradnjo, Dart pred prikazom ne more prepisati; ostaja
omejena meja že poslanih sporočil, strežniški novi payload pa mora biti splošen.

## Primarni viri

- [SQLite3MC ChaCha20/Poly1305, parametri in reserve32](https://utelle.github.io/SQLite3MultipleCiphers/docs/ciphers/cipher_chacha20/).
- [SQLite3MC pragma vrstni red, raw32B ključ, dejanski preizkus ključa](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/).
- [sqlite3 native build hooks in sqlite3mc](https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html).
- [Drift: native šifriranje](https://drift.simonbinder.eu/platforms/encryption/).
