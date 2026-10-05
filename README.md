# Kanban Connect

Flutter aplikacija za Kanboard, ki jo razvijamo v osrednje orodje za organizacijo osebnega in družinskega življenja: prosti čas, opravila, domače projekte, nabavo in finance.

**Stanje:** na veji `codex/vsakdan-foundation` so izdelani lokalni organizator, deljenje med uporabniki in družinska nadgradnja. Aplikacija se odpre v osebnem organizatorju brez računa in strežnika. Gradnjo nadaljujemo ob pregledu stare kode in dosedanjih sprememb. Uporabnik ne zahteva ohranitve starih lokalnih podatkov ali vedenja aplikacije; bistven je preverjen arhiv vseh obstoječih strežniških podatkov z lokalnim brskalnikom. Celotna kopija je že prenesena in lokalno obnovljena, vseh 48 tabel ter 8 priponk je preverjenih. Produkcija še ni upokojena. Izvedbo, preverjanja in nadaljnje etape vodi [načrt prenove](docs/RENOVATION_PLAN.md). »Vsakdan« je delovno ime, končno ime za trgovine še ni določeno.

Navodila za delo na kodi so v [AGENTS.md](AGENTS.md). Spodnje ugotovitve o starem odjemalcu so izhodišče prenove; rezultate nove izvedbe sproti dodajamo ločeno od teh ugotovitev.

**Družinska nadgradnja:** dodelitve in skupni termini, trajen center obvestil, lokalni sistemski opomniki ter skupne finance z ločenimi pravicami. Aktualne dokaze in meje vodi [mejnik družinske nadgradnje](docs/FAMILY_UPGRADE.md). Pripravljena je izbirna FCM dostava za Firebase Spark; [njen mejnik](docs/FIREBASE_PREPARATION.md) loči implementacijo in preizkuse od še manjkajoče resnične FCM/APNs dostave. Produkcijski SMTP ter podpisana mobilna izdaja ostajajo ločeni koraki.

**Zadnja preverjena etapa:** preprostejši prvi vstop, izbirna zasebna sinhronizacija lastnih naprav ter šifrirane kopije in obnova. Lokalna izvedba uporablja FamilyHub 0.5.0 in SQLite schema 4; prijava osebnih podatkov ne pošlje samodejno. Dokazi in preostale omejitve so v [mejniku osebne sinhronizacije in obnove](docs/PERSONAL_SYNC_AND_RECOVERY.md).

Podrobnejši [pregled kode in že narejenih sprememb](docs/CODEBASE_AUDIT.md) loči napake starega odjemalca, omejitve nove osnove in dele za ponovno uporabo. Cilj je nadaljnja gradnja z jasnejšim podatkovnim modelom; ohranitev starega vmesnika ni pogoj.

[Lokalni arhiv starega sistema](docs/LEGACY_ARCHIVE.md) opisuje izveden zajem, rezultate primerjave z bazo, samostojen pregledovalnik in meje popolnosti. Zasebni izvozi ostajajo zunaj repozitorija. Orodje za ponovitev postopka je v `tools/legacy_archive/`.

## Kaj nova osnova že vsebuje

- Dnevni pregled, prihajajoča opravila, koledar, osebne in domače projekte, nakupovalne sezname ter posamezne prihodke in odhodke. Vsi ti zapisi se ustvarjajo in urejajo lokalno.
- Mobilno navigacijo **Danes / Načrti / Nakupi / Več** ter namizni stranski meni in prikaz v več stolpcih. Nevtralna svetla in temna tema z modrim poudarkom; slovenska in angleška besedila.
- Trajno osebno shrambo SQLite/Drift, lokalne ID-je, transakcijske zapise in zavrnitev urejanja zastarele revizije. Prvotni Hive se ob selitvi ohrani. Denarni zneski so cela števila v centih; EUR, USD, GBP in CHF se obravnavajo ločeno.
- Šifrirane prenosne kopije z geslom, predogledom ter obnovo osebnih podatkov in obnovitvenim pregledom skupnega dela. Napredni osebni izvoz/uvoz JSON ostaja ločena nešifrirana možnost. Poškodovane ali novejše zbirke ne nadomesti s prazno.
- Enotni center obvestil z oznakama Zame/V skupnem prostoru, združenimi cilji in osebnim prebranim stanjem. Lokalni sistemski opomniki imajo razpored, uskladitev po spremembi termina in preklic; oddaljeni push ni vključen. Strežniška SMTP vrsta je preverjena z lokalnim sprejemnikom.
- Izrecno povezavo do obstoječega Kanboardovega odjemalca v nastavitvah. Stari strežniški projekti in finance ostanejo tam; samodejnega prenosa v lokalni organizator še ni.
- Izoliran Docker ter vtičnik **FamilyHub 0.5.0**. Nova osnova vsebuje prijavo in registracijo prek povabila v aplikaciji, napravne seje, ločene skupne prostore in sinhronizacijo nakupov/projektov/opravil/dogodkov, ločene skupne finance in obvestila. [Zagon, testi in paket](docs/server/README.md), [natančna pogodba](docs/server/native-api-contract.md).

Aktualni rezultat je **297 Flutter testov in trije dodatni dejanski HTTP testi**, FamilyHub 0.5.0 pa ima **436 strežniških preverjanj na vsaki** od SQLite, MySQL in MariaDB. Uspeli so spletna gradnja, Android debug APK, iOS simulator in macOS debug; podrobnosti so v [zadnjem mejniku](docs/PERSONAL_SYNC_AND_RECOVERY.md). Zgodovinske dokaze ohranjajo [prvo deljenje](docs/SHARING_MILESTONE.md), [družinska nadgradnja](docs/FAMILY_UPGRADE.md) in [priprava FCM](docs/FIREBASE_PREPARATION.md). Native API je v namestitvenem ZIP privzeto izključen in na produkcijo še ni nameščen. Novi podatki so v lastnih tabelah; povabila ne odprejo starih Kanboardovih projektov ali finančnih metapodatkov. Priponke še niso del nove sinhronizacije.

Aktivna SQLite baza, ohranjeni Hive ter napredni JSON izvozi nimajo dodatnega šifriranja. Prenosni format `.vsakdan` uporablja AES-256-GCM in geslo kopije. Osebna projekcija ostaja omejena na 10 MiB/50.000 zapisov; transakcije preverjajo revizijo in identiteto. Preizkusi dveh naprav ne pomenijo potrjene uskladitve prikaza v več sočasnih procesih iste namestitve.

## Utrjena obstoječa povezava

Nove poverilnice in AI ključi se shranjujejo samo v varni shrambi. Stare kopije se odstranijo po preverjenem prenosu; napaka se pokaže uporabniku brez rezervnega plaintext zapisa. Kanboardove zahteve zahtevajo HTTPS in preverjajo izvor vsake preusmeritve. Za lokalni Docker je na prijavnem zaslonu izrecna izjema samo za `localhost`, `127.0.0.1` in `::1`. Privilegirani poskus z uporabnikom `jsonrpc`, QR izvoz gesel in dnevniki z vsebino uporabniških zahtev so odstranjeni.

Predpomnilnik, AI pogovori in projektne privolitve so ločeni po strežniku in računu. Odjava počisti zadevni obseg in zavrne pozne zapise že začetih zahtev; osebnega organizatorja ne izbriše. Stari skupni ključi predpomnilnika in AI pogovorov ostanejo na disku, vendar jih nova identiteta ne prevzame samodejno. Predpomnilnik se ponovno prenese; za uvoz starih AI pogovorov je treba najprej izrecno določiti lastništvo.

macOS Debug/Profile za lokalno gradnjo z adhoc podpisom ne dodaja `keychain-access-groups`; Xcode je zavrnil tudi prazen seznam brez razvojnega certifikata. Release ohrani skupino z `AppIdentifierPrefix` in potrebuje dejanski Apple razvojni/distribucijski podpis. Dostop do Keychaina na podpisani napravi še ni preverjen; če varna hramba zavrne dostop, tudi prijava jasno odpove. Lokalni organizator od nje ni odvisen.

## Namen aplikacije

Uporabnik naj na enem mestu vidi, kaj ga čaka, kaj ureja skupaj z družino, kako napredujejo projekti in kako ti vplivajo na čas ter denar. Običajen vstop, prijava in deljenje naj potekajo v tej aplikaciji, brez predhodnega obiska Kanboardovega spletnega vmesnika.

Pri zasnovi ločujemo osebne podatke, skupne podatke gospodinjstva in posamezne projekte, deljene tudi z ljudmi zunaj gospodinjstva. Primer: brat sodeluje pri obnovi mansarde in vidi opravila ter dogovorjeni seznam materiala; finančni pregled doma je lahko skupen članom doma, projektu pa lahko posebej omogočimo skupne finance. Zunanji sodelavec vidi samo finančni obseg, ki mu je izrecno namenjen.

Osnova uporabniške izkušnje je dnevni pregled z roki in hitrim dodajanjem. Lokalni koledar že prikazuje dogodke in roke opravil. Skupna opravila in dogodki imajo izvajalce ter termine; rutine in spremljanje prostega časa ostajajo nadaljnji obseg. Kanban tabla ostaja dostopna v obstoječem odjemalcu.

## Local-first in deljenje

Osebno uporabo začnemo brez računa. UI bere trajne lokalne podatke SQLite; osebni zapisi so ločeni od starega Kanboardovega predpomnilnika in podatkov drugih računov. Prijava osebnih zapisov ne objavi. Zasebno sinhronizacijo lastnih naprav vključimo izrecno po predogledu; osebni prostor nima drugih članov. Izbrani seznam ali projekt z opravili lahko izrecno kopiramo v skupni prostor: nastanejo novi ID-ji, osebni izvirnik ostane, finančni zapisi se ne kopirajo.

| Način | Vedenje nove izvedbe |
| --- | --- |
| Osebno | Ustvarjanje, branje, urejanje ter osebni izvoz/uvoz brez računa in strežnika |
| Skupno, strežnik nedosegljiv | Branje prenesene vsebine in lokalno urejanje; sprememba in odhodna operacija se shranita skupaj v SQLite |
| Skupno, strežnik dosegljiv | Prenos posameznih zapisov z revizijami, ponovitve brez podvajanja ter preverjanje članstva |
| Spremenjene pravice ali isti zapis na dveh napravah | Vidno blokirano delo ali konflikt; lokalni osnutek ostane za izvoz oziroma izrecno razrešitev |

Skupna baza prek Drift hrani zapise, odhodne operacije, konflikte in kazalce v transakcijah. Prostor je gospodinjstvo ali posamezen projekt, uporabnikova vloga pa lastnik, član ali gledalec. Članstvo v enem prostoru ne daje dostopa do drugega. Nova vsebina se ureja v tej aplikaciji; Kanboardov spletni vmesnik ni drugi urejevalnik teh tabel.

Lokalni račun je ločen po naslovu strežnika in trajnih identifikatorjih strežnika ter računa. Odjava skrije skupno zbirko in ohrani neposlano delo za isti račun; drugi uporabnik ga ne sme prebrati ali poslati. Žeton naprave je v varni shrambi brez rezervne kopije v običajnih nastavitvah. Novi prenosni izvoz je šifriran; aktivna lokalna baza še nima dodatnega šifriranja.

Sinhronizacija poteka ob urejanju, vrnitvi v aplikacijo in periodično, dokler aplikacija teče. To ni zagotovljena dostava v ozadju zaprte aplikacije. Ob konfliktu uporabnik izbere strežniško različico ali ponovno odda lokalno spremembo na podlagi nove revizije. Preklic dostopa ustavi nove strežniške operacije, ne more pa takoj izbrisati kopije na nepovezani napravi. Ponovno članstvo ne pošlje prej blokiranih sprememb brez izrecnega nadaljevanja.

Za spletno deljenje sta vključena pripeta SQLite WASM in Drift worker. Nepodprta trajna hramba se pokaže kot napaka; aplikacija ne preide tiho na pomnilnik ali nekoordiniran IndexedDB. [Različice in zahteve gostovanja](docs/dependencies/README.md). Delo brez povezave velja za že naloženo aplikacijo; prvi spletni zagon brez prenosa datotek ni potrjen. Nativni paket aplikacijske datoteke vsebuje lokalno.

Šifrirana kopija vsebuje osebne podatke in dostopno preneseno vsebino trenutnega računa, čakajoče operacije ter konflikte. Obnovljeno skupno delo ostane ločeno, dokler isti račun ne opravi svežega preverjanja pravic in izrecnega nadaljevanja. Kopija ne vsebuje sej in ni celotna kopija strežnika ali neprenesenih priponk; predogled pokaže nepopolne obsege. Napredni JSON izvoz neusklajenega dela ostaja reševalna možnost. Podatki in dnevnik obnove nastavitev se zapišejo v eno SQL transakcijo; nastavitve v SharedPreferences se nato uveljavijo ponovljivo. [Pogodba, preverjanja in meje](docs/PERSONAL_SYNC_AND_RECOVERY.md).

Konceptualno izhodišče: [Local-first software, Ink & Switch](https://www.inkandswitch.com/essay/local-first/) in [Flutter offline-first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first). Rezultati dejanskih testov so v [mejniku](docs/SHARING_MILESTONE.md).

## Izhodišče: obstoječi Kanboardov odjemalec

| Področje | Izhodišče pred prenovo |
| --- | --- |
| Povezava | URL Kanboarda, uporabniško ime in geslo ali API žeton; shranjevanje in prenos poverilnic prek QR/kode |
| Projekti | Ustvarjanje in urejanje, barve, projektne datoteke, upravljanje uporabnikov in projektnih vlog |
| Opravila | Kanban stolpci in plavalne steze, premikanje, podnaloge, komentarji, oznake, roki, ure, priponke in povezave |
| Nabava | Nakupovalni seznam kot posebna oblika naloge s podnalogami |
| Finance | Projektni stroški in proračun, mesečni prihodki, ponavljajoči in načrtovani prihodki/odhodki ter projekcija stanja |
| AI | Projektni pogovor in pomoč pri naslovih/opisih nalog; neobvezna funkcionalnost |
| Lokalna hramba | Hive za predpomnilnik projektov in tabel, SharedPreferences za nastavitve ter integracija varne hrambe |
| Jeziki in videz | Slovenščina in angleščina prek ARB, svetla/temna tema, Material in Cupertino komponente |

Ta seznam opisuje implementacijo, ne potrjenega delovanja vseh poti z živim strežnikom. Posebej prijava, deljenje in priponke potrebujejo integracijske preizkuse z različnimi uporabniškimi vlogami.

## Tehnična osnova

Flutter/Dart, `flutter_riverpod`, `go_router`, Native API in podedovani HTTP JSON-RPC. Novi osebni in skupni podatki uporabljajo SQLite prek Drift 2.35.1; Hive ostaja ohranjen vir selitve in shramba starega odjemalca. Omejitvi v `pubspec.yaml` sta Dart `^3.12.0` in Flutter `>=3.44.0`; preverjamo s Flutter 3.47.2 / Dart 3.13.2. Različica aplikacije ostaja `1.0.12+12`.

```text
lib/
  main.dart, app.dart, app_router.dart   Zagon, tema in navigacija
  organizer/domain/                    Lokalni zapisi, revizije in preverjanje
  organizer/data/, organizer/state/     Osebni/skupni SQLite, seje, sinhronizacija, kopije
  organizer/presentation/               Novi mobilni in namizni organizator
  features/auth/                       Povezava in obnova seje
  features/projects/                   Projekti, datoteke in deljenje
  features/board/                      Tabla, struktura in finance
  features/board/finance/               Izračuni finančne projekcije
  features/tasks/                      Urejevalnik nalog
  features/ai/, features/settings/      AI in nastavitve
  kanboard/                            API in JSON-RPC transport
  models/                              Podatkovni modeli
  state/                               Riverpod providerji
  storage/                             Lokalna hramba
  l10n/                                ARB in generirani prevodi
  widgets/                             Skupne komponente
test/
  finance/finance_projection_test.dart  Štirje testi finančnih izračunov
  widget_test.dart                     Preizkus začetnega zaslona
  organizer/                           Lokalna shramba in prilagodljivi zasloni
server/                                Lokalni Docker, FamilyHub, PHP testi
docs/RENOVATION_PLAN.md                 Etape, omejitve in rezultati
docs/SHARING_MILESTONE.md               Tokovi deljenja in dokazi preverjanja
docs/server/                           Strežniško okolje in pogodba API
```

Repozitorij vsebuje platformne mape za Android, iOS, macOS, Windows, Linux in web. Zagon zdaj zaščiti namizne klice z `kIsWeb` in `defaultTargetPlatform`. Preverjene so gradnje za splet, macOS, iOS simulator in Android debug APK; to še ne potrjuje vseh platformnih vtičnikov in podpisanih izdaj. Flutter 3.47.2 je pri gradnji preselil Apple projekta na Swift Package Manager ob sočasni uporabi CocoaPods za preostale vtičnike, iOS na UIScene ter najmanjši različici na **iOS 15 / macOS 12**. Windows in Linux še nista preverjena.

Android uporablja Gradle 8.14 s pripetim SHA256, Android Gradle Plugin 8.11.1 in Kotlin 2.2.20; to so minimalne različice, ki jih je zahtevala diagnostika tega Flutter SDK. Razvojna konfiguracija deluje brez zasebne datoteke `android/key.properties`; izdaja zahteva vse podpisne nastavitve in veljaven keystore ter nikoli tiho ne uporabi razvojnega podpisa.

## Lokalni razvoj

Potrebni so Flutter SDK in razvojna orodja za izbrano platformo. Za osebni organizator Kanboard ni potreben. Za testiranje starega odjemalca uporabi lokalni Docker in lasten testni račun. Običajni Dart testi ne potrebujejo živega strežnika. Posebni opt-in HTTP preizkus zahteva sintetično lokalno testno okolje; navodila so v dokumentu mejnika.

```sh
flutter --version
flutter doctor
flutter pub get
flutter gen-l10n
flutter devices
flutter run -d macos
```

Zadnji ukaz je primer za macOS; na drugi platformi izberi napravo iz `flutter devices`. Po `flutter pub get` preglej spremembe zaklenjenih odvisnosti. Produkcijskih poverilnic ne dodajaj v repozitorij ali primere.

Na pregledanem računalniku je za neposredni Gradle/Android ukaz potreben popravek poti Java samo v okolju ukaza:

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' flutter build apk --debug
```

```sh
flutter analyze
flutter test
git diff --check
```

Razvoj poteka s Flutter 3.47.2 in Dart 3.13.2. `flutter pub get` je v delovni veji uskladil sedem zaklenjenih odvisnosti s tem SDK; uporabnikova različica aplikacije `1.0.12+12` ostaja ohranjena. Začetna analiza stare kode je imela 2 opozorili in 35 informacijskih priporočil. Aktualne rezultate novih testov, analize in gradenj vodi [dnevnik izvedbe](docs/RENOVATION_PLAN.md#dnevnik-izvedbe).

Aktualni končni rezultati (**297 Flutter PASS in trije dodatni HTTP PASS**) so v [mejniku osebne sinhronizacije in obnove](docs/PERSONAL_SYNC_AND_RECOVERY.md). `flutter analyze` ima **35 podedovanih informacijskih ugotovitev**, brez napak in opozoril; zaradi teh priporočil njegov običajni ukaz še vrne neuspešno izhodno kodo. Redna JavaScript spletna gradnja uspe; WebAssembly preverjanje opozarja na nezdružljivost obstoječega `flutter_secure_storage_web`. Wasm ni potrjena ciljna platforma.

CI workflowov v repozitoriju trenutno ni.

## Izhodiščne ugotovitve pregleda

| Področje | Ugotovitev pred prenovo | Izhodišče za spremembo |
| --- | --- | --- |
| Finance | Celotna tabela je JSON v projektnih metapodatkih; večji zapisi se razdelijo na dele po 220 bajtov. Ni preverjanja revizije skupnega zapisa. | Posamezni strežniški zapisi, transakcije, preverjanje revizij in obravnava konfliktov |
| Poverilnice | `CredentialsStore` ob napaki varne hrambe preide na SharedPreferences. `AiSettingsStore` tja shrani kopijo ključa tudi ob uspešni varni hrambi. | Odpraviti nezavarovane kopije in urediti migracijo ter platformno konfiguracijo varne hrambe |
| Prenos prijave | QR/koda vsebuje geslo ali žeton, kodiran z Base64, brez dejanske omejitve veljavnosti. | Namensko povabilo ali kratkotrajna enkratna povezava za novo napravo |
| Omrežje | JSON-RPC ob preusmeritvi ponovno pošlje Authorization; privzeto beleži predoglede parametrov in odgovorov. | HTTPS, preverjanje izvora preusmeritve, dnevniki brez zasebne vsebine |
| Predpomnilnik | Ključa `projects` in `board_ID` nista ločena po strežniku in uporabniku. | Ločitev po identiteti in določeno čiščenje ob odjavi oziroma menjavi računa |
| Deljenje | Iskanje uporabnikov vključuje rezervno spletno prijavo, branje CSRF iz HTML in spletni autocomplete. | Podprt strežniški postopek za povabilo ali omejeno iskanje uporabnika |
| Obvestila | Ni vključene celotne poti za mobilna potisna obvestila. | Trajen seznam obvestil, razporejanje, dostava na naprave in odpiranje prave vsebine |
| Organizacija kode | Več zaslonov združuje UI, omrežne operacije in poslovna pravila v približno 1.800–2.600 vrsticah. | Postopna ločitev prikaza, stanja, podatkovnih operacij in domenske logike |
| Preverjanje | Testi pokrivajo projekcijo in začetni zaslon; ne pokrivajo deljenja, pravic ali sočasnega urejanja. | Preizkusi ključnih uporabniških poti in strežniških meja dostopa |

Možnost izgubljene spremembe pri sočasnem urejanju financ je sklep iz poti zapisovanja; na produkciji ni bila reproducirana. Obstoječi predpomnilnik tudi ne pomeni podpore za varno urejanje brez povezave.

## Strežniška izvedba: Kanboard in FamilyHub

Novi strežniški del je vtičnik FamilyHub brez sprememb Kanboardovega jedra. Uporablja njegove lokalne uporabniške račune, za skupne prostore, članstva, povabila, naprave in podatke pa lastne tabele. Stari projekti ostanejo v ločenem arhivu; njihovo nadaljevanje v novi domeni je izbirni postopek.

| Del sistema | Odgovornost |
| --- | --- |
| Flutter aplikacija | Lokalno urejanje, odhodna vrsta, prikaz konfliktov, račun in sodelovanje |
| Kanboard | Gostitelj vtičnika in obstoječa lokalna identiteta; stari projekti ostanejo ločeni |
| FamilyHub Native API v1 | Napravna avtentikacija, povabila in registracija, obsegi in vloge, revizije, izbrisi in ponovljive zahteve |

Prvi dokaz JSON-RPC s povabili v stare projekte ostane ločen in privzeto izključen. Novi uporabniški tok uporablja različeni Native API z Bearer žetonom naprave. Ta žeton ni globalni ključ in se ne pošilja na običajni `jsonrpc.php`. [Pogodba in meje](docs/server/native-api-contract.md).

### Prijava, povabila in dostop

Obstoječi lokalni uporabnik se prijavi v aplikaciji z geslom in, če je vključena, kodo TOTP. Strežnik omejuje poskuse, preprečuje ponovno uporabo iste TOTP kode in izda preklicljivo sejo za napravo z omejeno veljavnostjo. Geslo, stanje drugega faktorja, deaktivacija uporabnika in preklic naprave vplivajo na veljavnost seje. Zunanji prijavni ponudniki še niso podprti.

Lastnik ustvari gospodinjstvo ali projektni prostor ter povabilo za določeno uporabniško ime. Povabljenec se prijavi in sprejme povabilo ali z njim ustvari nov običajen uporabniški račun neposredno v aplikaciji. Povabilo ima rok veljavnosti in preklic; strežnik hrani zgoščeno skrivnost, predogled je ne porabi. Registracija, članstvo in poraba povabila so ena transakcija. Kodo ali povezavo `vsakdan://invite` delimo ročno. Povezava odpre pregled v aplikaciji in ne sprejme povabila samodejno. E-poštna dostava povabil ter produkcijske Universal Links/App Links še niso nastavljene.

Prvi novi račun ustvarimo v aplikaciji z enkratno kodo, ki jo upravitelj izda v zaščitenem Kanboardovem obrazcu; SSH ni potreben. Obstoječi lokalni Kanboardov račun se še vedno lahko prijavi neposredno. Potrditev e-pošte in obnova gesla imata ločene enkratne kode, omejevanje poskusov in SMTP vrsto; produkcijski SMTP še ni nastavljen. Ponastavitev prekliče napravne seje in ne obide TOTP. Aplikacija ne potrebuje skrbniškega gesla ali globalnega `jsonrpc` ključa.

Lastnik upravlja člane in povabila, član ureja vsebino, gledalec jo bere. Dovoljenja strežnik preverja za vsak obseg in zahtevo, tudi pri ponovitvah. Vloge ne odprejo drugih prostorov. Finance doma ali projekta imajo ločene pravice none/read/write. Nakupi ne ustvarjajo dogodkov starega Kanboarda; nakupovalna e-pošta je privzeto izključena.

Finančne pravice se preverjajo tudi pri izvozu, obvestilih, konfliktih in revizijski sledi. Pri poznejši uvedbi priponk ter AI konteksta veljajo enake meje. Stari finančni metapodatki so razlog, da stare poti deljenja ne vključujemo na produkciji. [Kanboardov dostop do metapodatkov](https://github.com/kanboard/kanboard/blob/v1.2.54/app/Api/Procedure/ProjectMetaDataProcedure.php).

### Finance in skupno urejanje

Obstoječa finančna vsebina ostane v arhivu v izvirnem formatu. Čisti izračuni in testi so referenca za razlago stare projekcije, ne obvezna zasnova novega modula. Za nove podatke ločimo dejanske knjižbe in stanja od prihodnjih načrtov ter pravil ponavljanja, povezane z ustreznim zasebnim ali skupnim prostorom. Finance so lahko osebne, skupne za isti dom ali skupne znotraj izrecno tako zasnovanega projekta. Strošek projekta in celoten gospodinjski proračun nista nujno isti obseg dostopa; pravice do pregleda in urejanja določimo posebej.

Skupna tabela loči plačnika/prejemnika, finančni račun in avtorja vnosa. Vključuje filtre po članu, računu, avtorju in stanju ter spletno sled sprememb. Knjiženi in načrtovani vnosi so ločeni. Prenos poveže računa iste valute v istem skupnem prostoru in se ne šteje kot prihodek ali strošek. Račun člana v tem prostoru je deljen račun; zasebni osebni zapisi se vanj ne vključijo samodejno. Prenosi med zasebnim in skupnim prostorom še niso podprti.

Deljeni finančni zapisi uporabljajo revizijo: strežnik spremembo sprejme samo, če se prej prebrana revizija še ujema. Aplikacija spremembo najprej trajno shrani lokalno; konflikt pri uskladitvi mora pokazati in omogočiti razrešitev, ne izgubiti lokalnega dela. Ponovljena zahteva ne sme podvojiti zapisa. Pri prenosu starega JSON potrebujemo preverjanje zneskov in valut, ponovljiv uvoz brez dvojnikov ter dogovor, kdaj stari odjemalci prenehajo zapisovati star format. Varnostno kopijo in postopek povrnitve določimo pred migracijo.

### Opomniki in obvestila

Center obvestil loči **Zame** od **V skupnem prostoru**. Tudi nedodeljeni člani dobijo skupno dogajanje, skladno s pravicami in nastavitvami. Lastno dejanje ne opozarja avtorja. Povezani dogodki se združijo v petminutnem oknu; odpiranje ohrani točen nabor novih dodelitev oziroma nakupovalnih dodatkov. Prebrano obvestilo ne zaključi opravila ali označi računa kot plačanega.

Gospodinjstvo ima skupni dnevni pregled, projekt pa časovnico z izvajalci, začetkom, koncem in rokom. Nastavitve po prostoru in kategoriji ločijo prikaz v aplikaciji, zvok, e-pošto ter izbirni push kanal. Nakupovalna e-pošta je privzeto izključena.

Lokalni sistemski opomniki delujejo brez Firebase in strežnika za podatke, ki so že na napravi. Sprememba ali zaključitev izvora uskladi razpored; iOS hrani najbližjih 60, Android uporablja nenatančne alarme. Na spletu ni razporejanja za zaprt brskalnik. Dostava in odpiranje sta preverjena na iOS simulatorju; fizične naprave zahtevajo ločen preizkus.

FamilyHub ustvari trajno obvestilo in SMTP opravilo v transakciji s spremembo. Cron preveri trenutne pravice/nastavitve in dostavlja z omejenimi ponovitvami ter preverjenim TLS. Lokalni SMTP sprejem je preverjen, produkcijski pa še ni nastavljen. Uporabnik je izbral Firebase Cloud Messaging na paketu Spark. Pripravo Android/iOS adapterja, varne registracije naprav in neposrednega strežniškega HTTP v1 pošiljanja vodi [FCM mejnik](docs/FIREBASE_PREPARATION.md). Lastni Firebase projekt, APNs, produkcijska konfiguracija ter preizkus na fizičnih napravah še manjkajo. Firebase ni pogoj za podatke, prijavo ali lokalne opomnike. [Nastavitve in meje dostave](docs/NOTIFICATION_SETUP.md).

Kanboardovi vtičniki lahko dodajo vrste obvestil. Kanboardov cron pokriva tudi zapadle naloge, vendar to samo po sebi ne zagotovi mobilne dostave. Na omejenem gostovanju je kandidat kratko paketno opravilo z zaklepanjem, ponovnimi poskusi in preprečevanjem podvajanja, če gostovanje omogoča primeren cron. [Vtičniki za obvestila](https://docs.kanboard.org/v1/plugins/notifications/), [cron](https://docs.kanboard.org/v1/admin/cronjob/).

## Gostovanje in razvoj strežniškega dela

Kanboard je na cPanel gostovanju. Po uporabnikovi prijavi smo 4. oktobra 2026 opravili pregled brez spreminjanja nastavitev, nalaganja datotek ali izvajanja strežniških ukazov.

| Preverjeno v portalu | Ugotovitev in njen pomen |
| --- | --- |
| Evidenca Softaculous | Namestitev Kanboarda je vodena kot **1.2.54**. Staro opozorilo odjemalca ob vsaki različici razen **1.2.50** je zdaj odstranjeno. Vtičnik ima pogodbo z dejanskimi zmožnostmi; novi tok povezovanja jo že prebere in preveri. |
| File Manager | Imenik namestitve je dostopen; mapa `plugins` je prisotna in prazna. Vmesnik ponuja nalaganje in razširjanje arhivov; namestitve vtičnika nismo izvedli. |
| PHP Selector | Nastavitve računa kažejo **PHP 8.4**, vključene cURL, OpenSSL, mbstring, PDO, gonilnike MySQL/SQLite in ZIP. Morebitne posebnosti PHP za posamezno domeno še niso preverjene. |
| Omejitve PHP | Prikazane vrednosti: 30 s izvajanja, 768 MB pomnilnika, 20 MB za posamezen naložen dokument in 50 MB za zahtevo POST. `allow_url_fopen` je izključen. |
| Onemogočene funkcije | Med njimi so `mail`, `sendmail`, `exec`, `shell_exec`, `proc_open` in sorodne funkcije. Za e-pošto načrtujemo SMTP, paketov in procesov pa ne zaganjamo iz spletnega PHP. |
| Cron Jobs | Obrazec omogoča minutni interval in prikazuje primer klica PHP CLI. Opravila nismo dodali; dejansko izvajanje, izbrano različico CLI in ponudnikove omejitve je treba še preizkusiti. |
| Terminal in SSH | Spletni Terminal se odpre do poziva lupine. Povezava SSH Access je prisotna; oddaljene povezave SSH nismo preverjali. |
| Dodatne možnosti | Vidni so Git Version Control, phpMyAdmin in R1Soft Restore Backups. Delovanja Git objave ali obnove varnostne kopije nismo preizkusili. |

To podpira izvedljivost pristopa z lastnim PHP vtičnikom; ne potrjuje še vseh zahtev ali dejanske konfiguracije Kanboarda. Lokalno Docker okolje je sprejemljiva možnost za testiranje.

Poznejši arhivski zajem istega dne je potrdil gonilnik MySQL in lokalno shrambo priponk `data/files`. Glava izvoza navaja podatkovni strežnik **10.11.19** in PHP **8.4.25**. Celoten SQL je uspešno obnovljen v izoliranem lokalnem MySQL **8.4.11**; to ni dokaz enakega pogona kot na gostovanju. Podrobnosti so v dokumentaciji arhiva.

Predlog poteka dela je lokalni razvoj vtičnika in testiranje v Dockerju z enako različico Kanboarda, PHP in vrsto baze kot na gostovanju. Namestitveni ZIP z vsemi potrebnimi odvisnostmi pripravimo lokalno in ga preizkusimo na testni namestitvi, nato ga lahko prenesemo prek cPanelovega upravljalnika datotek. To ni navodilo za namestitev v produkcijo v tej fazi.

Pred produkcijsko namestitvijo in povezovanjem resničnih podatkov še preverimo:

- različico neposredno iz izvajajočega se Kanboarda in ujemanje z evidenco Softaculous;
- učinkovito PHP konfiguracijo domene ter namestitev vtičnika na testni kopiji;
- natančen pogon baze poleg že potrjenega gonilnika/izvozne različice ter migracije na ujemajočem se testnem okolju; zajem in lokalna obnova SQL sta že preverjena;
- razpoložljivost in najmanjši interval cron opravil ter dostop do PHP CLI prek crona;
- SMTP in odhodne HTTPS povezave za povabila ter mobilna obvestila;
- HTTPS, posredovanje glave Authorization in možnost ločene testne poddomene.

V prvo arhitekturo ne vključujemo obveznega stalnega workerja, WebSocket strežnika ali Dockerja na produkcijskem gostovanju. Če potrjene omejitve preprečijo pomembno funkcijo, primerjamo namensko zunanjo storitev in spremembo gostovanja. Podatki za prijavo, sejne povezave cPanela in produkcijski izvozi ne sodijo v repozitorij.

## Odprte odločitve v izvedbenem planu

Izhodišče so uporabnikova analiza in zgoraj preverjene ugotovitve. Gradnjo vodi [načrt prenove](docs/RENOVATION_PLAN.md), med razvojem pa skupaj natančneje določimo:

- prve ključne uporabniške tokove in prednostne platforme;
- razmerje med osebnim prostorom, gospodinjstvom in zunanjimi sodelavci;
- nastavitev produkcijskega SMTP za že izvedeno preverjanje e-pošte in obnovo gesla;
- pravila vidnosti projektnih stroškov in zasebnih financ;
- ponavljanje in finančne projekcije, lokalne priponke, dodatno zaščito aktivne baze ter celotne strežniške varnostne kopije;
- hitrost osveževanja med napravami, kanale in pričakovano pravočasnost obvestil;
- preizkus paketa na testni poddomeni dejanskega gostovanja pred produkcijo;
- izbirno nadaljevanje izbranih arhiviranih projektov v novem modelu; obvezna je ohranitev arhiva, ne migracija vsega.

Zaporedje etap in preverljiva merila so v načrtu. Podrobnosti sodelovanja, registracije, migracije in izdaje niso avtomatično potrjene samo zato, ker je lokalna osnova implementirana.
