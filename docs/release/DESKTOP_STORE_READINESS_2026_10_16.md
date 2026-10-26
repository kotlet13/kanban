# Jivie: licence in pripravljenost za namizne trgovine

Datum pregleda: **16. oktober 2026**, Europe/Ljubljana. Izhodišče: commit
`5dc249fbb95bfc7d1b09d71e4abfbeacf35d5d46`, aplikacija `1.10.1+31`.

Uporabnik je izbral **Microsoft Store/MSIX, Snap Store in uradno Applovo
trgovino**. V tem namiznem pregledu je Applov cilj **Mac App Store**; obstoječa
iOS izdaja je relevantna za skupne politike in račun, ne pomeni pripravljene
Mac izdaje. Ta datoteka je enotno izhodišče za naslednji načrt nadgradenj.

Pregled so opravili trije podagenti **GPT-6.1 Sol / high** (licence, Microsoft
Store, Apple) in glavni agent (Snap, povezovanje in preverjanje ugotovitev).
Pregled ni spremenil aplikacije, odvisnosti, podpisnih nastavitev, računov,
strežnikov ali trgovin. Ni bilo nove gradnje, namestitve ali oddaje.
Nepovezan `docs/SECURITY_REVIEW_2026_10_15.md` je ostal nedotaknjen.

## Kako brati ugotovitve

- **Potrjeno v izvoru**: neposredno preverljivo stanje ali napaka v pregledani kodi.
- **Vrzel priprave**: manjka del izdaje ali dokaz; to ni dokaz zavrnitve trgovine.
- **Nepreverjeno**: potrebuje dejanski paket, napravo ali podatke lastnika.
- **P1**: urediti pred prvo izdajo prizadete platforme oziroma pred obljubo te funkcije.
- **P2**: dopolnitev, odločitev ali preizkus, ki ga vključimo v pripravo izdaje.

P0, torej potrjena takojšnja kritična težava v že izdani aplikaciji, v tem
omejenem pregledu ni bila ugotovljena. Poročilo ni splošni varnostni pregled.
P1 ne pomeni, da je vsaka postavka izrecna pravna zahteva trgovine: pri vsaki
je ločeno navedeno, ali gre za licenco, pogoj oddaje ali funkcionalno zahtevo Jivie.

Dokazi `pot:vrstica` se nanašajo na navedeni commit. Lokalni `.pub-cache`, SDK,
Pods in stari artefakti niso del commita; pri njih so navedene različice in meje.
Spletna pravila so bila preverjena na datum pregleda; pred oddajo jih preverimo
ponovno, posebej kadar imajo objavljen prihodnji datum začetka veljavnosti.

## Sklep za načrtovanje

Izbrane poti podpirajo brezplačno aplikacijo in posodobitve prek trgovine.
**Pripravljenost za prvo namizno oddajo še ni dokazana na nobeni od treh poti.**
Glavne skupine dela so popolna licenčna obvestila in ponudba zahtevanih izvorov,
identitete in selitev lokalnih podatkov, izdelava paketov, integracija operacijskega
sistema ter preverjena nadgradnja že nameščene različice.

Ne načrtujemo lastnega spletnega updaterja za te trgovinske različice.
Samodejna dostava nove različice ni zagotovilo takojšnje namestitve: uporabnik,
operacijski sistem, uporaba aplikacije in omrežje vplivajo na čas nadgradnje.
Objava novega paketa ostane nadzorovan izdajni korak.

| Delovni sklop | Postavke | Glavni rezultat naslednje faze |
|---|---|---|
| Licence | L-01–L-06 | Popolna obvestila, MPL/LGPL obveznosti, dokaz izvora pisav, določeni lastni pogoji |
| Identiteta in podatki | D-01, W-03, M-01, S-03 | Končne identitete z varnim prehodom obstoječih profilov |
| Trgovinski paketi | W-01, W-02, W-05, M-01–M-04, S-01 | Preverjeni MSIX, Mac distribucijski paket in strict Snap |
| Sistemske funkcije | D-02, W-04, S-02, S-04, S-05 | Opomniki, varna hramba, datoteke in povabila na dejanskem OS |
| Pravila in uporabniške informacije | D-04, D-05, M-05, M-06 | Točne deklaracije, dostopnost, presoja moderacije in pregledni dostop |
| Samodejne nadgradnje | D-03 | Dokaz N → N+1 z ohranjenimi podatki za vsako trgovino |

## Potrjena izdajna smer in stroški

| Kanal | Predlagan paket in posodobitve | Podpis/zaupanje in račun |
|---|---|---|
| Microsoft Store | MSIX; nadgradnje dostavlja Store | Store podpiše MSIX. Poseben plačljiv CA certifikat za ta kanal ni potreben. Nova registracija Individual in Company je brezplačna; tip mora ustrezati dejanskemu izdajatelju. |
| Mac App Store | Mac distribucijski paket prek Xcode/App Store Connect; posodobitve iz trgovine | Apple Developer Program, isti program kot za iOS; 99 USD/leto ali lokalna cena. Potrebna sta ustrezna Mac distribucijska identiteta in profil. Developer ID/notariziran DMG je druga pot in ni izbrana. |
| Snap Store | `.snap`, predlagano `strict`, končni kanal `stable`; osvežitve upravlja snapd | Brezplačen razvijalski račun, registracija imena in Store pregled/assertions. Ne kupujemo Windowsovega podpisnega certifikata. Imena Jivie še nismo preverjali ali rezervirali. |

Viri: [Microsoft registracija](https://learn.microsoft.com/en-us/windows/apps/publish/faq/open-developer-account),
[MSIX in podpis trgovine](https://learn.microsoft.com/en-us/windows/apps/publish/faq/get-started-with-the-microsoft-store),
[Apple članstvo](https://developer.apple.com/programs/whats-included/),
[Snap objava](https://snapcraft.io/docs/releasing-your-app/),
[Snap brezplačen račun](https://forum.snapcraft.io/t/releasing-your-app/6795),
[Snap preverjanje distribucije](https://snapcraft.io/docs/explanation/security/assertions/).

Obstoječi iOS upload31 ni Mac paket. Stanje računov Microsoft/Snap, rezervacije
imen, Mac platforme v App Store Connect in novih pogodb v tem pregledu ni bilo
preverjeno v prijavljenih portalih. Nobenega soglasja nismo podali namesto lastnika.

## Licence, obvestila in izvorne obveznosti

### L-01 · P1 · MPL-2.0: dostop do točnega izvora pred distribucijo

**Status: release gap (potrjena prisotnost MPL komponent, končni AOT/paket še nepreverjen).** `dbus 0.7.12` in `gtk 2.2.0` uporabljata **Mozilla Public License 2.0**, ne BSD/MIT. Dokaz: `pubspec.lock:172`, `pubspec.lock:448`; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/dbus-0.7.12/LICENSE:1`, `/Users/anzenovsak/.pub-cache/hosted/pub.dev/gtk-2.2.0/LICENSE:1`. `dbus` uporablja tudi dejanski Linux datotečni izbirnik (`file_picker-10.3.10/lib/src/linux/file_picker_linux.dart:11`, `:23`), poleg `flutter_local_notifications_linux-8.0.1/pubspec.yaml:15`; `gtk` prek `app_links_linux-1.0.3/pubspec.yaml:16`, nativni GTK plugin je tudi v `linux/flutter/generated_plugins.cmake:8`. V `lib` in projektni distribucijski konfiguraciji ni najdenega obvestila, kje dobiti točno uporabljeni Source Code Form za MPL kodo.

**Obveznost:** MPL 3.2(a) zahteva dostopnost izvorne oblike in obvestilo prejemniku, kako jo pridobi; 3.3 dovoljuje Larger Work pod drugimi pogoji. To ni zahteva za odprtje celotne aplikacije Jivie. [MPL 2.0, §3](https://www.mozilla.org/en-US/MPL/2.0/#distribution-of-executable-form), [Mozilla FAQ Q8/Q11](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). **Potrebno/sprejem:** v dostopne Third Party Notices dodati MPL paket, točno verzijo, polno MPL licenco in trajno povezavo ali priložen arhiv točnega izvora ter dejanskih lokalnih sprememb; preveriti pot iz namestitve Snap brez razvojnih orodij in preveriti, da lastni pogoji ne omejijo pravic nad MPL izvorom. Enaka obveznost velja za vsako drugo ciljno platformo samo, če je koda dejansko ohranjena v njej; sama cross-platform closure tega ne dokazuje.

### L-02 · P1 · Native in sekundarna obvestila nimajo dokazane izdajne poti

**Status: release gap; potrjena nepokritost samodejnega Dart zbiralnika, ne potrjena kršitev še neobstoječega desktop release.** Flutter zbira `NOTICES`, sicer `LICENSE`, ter izrecni `flutter.licenses`; ne zbira samodejno vseh datotek `LICENSE-other.md` in CocoaPods/native licenc. Dokaz: `/Users/anzenovsak/Dev/flutter/packages/flutter_tools/lib/src/license_collector.dart:49`, `:97`; `pubspec.yaml:111` nima dodatne sekcije `licenses`. Korenski `docs/dependencies/drift-LICENSE.txt` ni sam po sebi paketno sredstvo (`pubspec.yaml:122`).

* **image 4.7.2:** `/Users/anzenovsak/.pub-cache/hosted/pub.dev/image-4.7.2/LICENSE-other.md:5` navaja Apache-2.0 JPEG port (notmasteryet/jpgjs). Dejanska aplikacijska pot uporablja **PngDecoder/JpegDecoder** in **encodePng/encodeJpg**, `lib/organizer/data/idea_repository.dart:444`, `:472`. Uporaba JPEG je torej potrjena. Apache tekst je že lahko prisoten zaradi drugih odvisnosti; odsotnost imena avtorja sama ni avtomatična kršitev Apache 4(c), ki je zahteva za source distribucijo. Preveriti in prenesti applicable upstream NOTICE, če obstaja, ter smiselno dostaviti celotna relevantna sekundarna obvestila. WebP/Batik TIFF/OpenEXR/PVRTC/QuickPVR so našteti v sekundarni licenci, a aplikacijska normalizacija izbira le PNG/JPEG; zanje **ni trditve**, da so v AOT ali da nastane obveznost na teh desktop izdajah. [image version license](https://pub.dev/packages/image/versions/4.7.2/license), [upstream secondary licenses](https://github.com/brendan-duncan/image/blob/main/LICENSE-other.md).
* **archive 4.0.7:** sekundarna datoteka vsebuje MIT imaya, BSD JCraft/JZLib, bzip2 ter MIT BouncyCastle; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/archive-4.0.7/LICENSE-other.md:1`. Image PNG uporablja archive (`image-4.7.2/lib/src/formats/png_encoder.dart:4`, `:69`; `png_decoder.dart:357`), toda desktop ZLib pot uporablja **native Dart ZLibCodec** (`archive-4.0.7/lib/src/codecs/zlib_encoder.dart:7`), ne nujno portiranih web deflate/inflate implementacij. Zato manjkajoč JCraft/imaya/BouncyCastle niz v notice **ni potrjeno neskladje desktop AOT**. Preveriti dejansko vključitev v končni paket; konzervativno vključiti secondary notices je enostavna rešitev. [archive version license](https://pub.dev/packages/archive/versions/4.0.7/license).
* **macOS native:** `macos/Podfile.lock:21`, `:25`, `:27`, `:32`, `:48`, `:51`, `:83` zaklenejo FirebaseCore/CoreInternal/Installations/Messaging **12.19.0**, GoogleDataTransport **10.1.0**, GoogleUtilities **8.1.0**, PromisesObjC **2.4.0**. Njihove lokalne `macos/Pods/<name>/LICENSE:1` so Apache-2.0; **GoogleUtilities vsebuje tudi MIT IsAppEncrypted**, `macos/Pods/GoogleUtilities/LICENSE:206`; dejansko ga kliče `GoogleUtilities/Environment/GULAppEnvironmentUtil.m:62`. To je konkreten dodatni MIT copyright/permission, ki ga generični Apache tekst ne pokrije. Popoln CocoaPods agregat obstaja v `macos/Pods/Target Support Files/Pods-Runner/Pods-Runner-acknowledgements.markdown:4`, `:1240`, `:1468`, toda `macos/Runner.xcodeproj/project.pbxproj:325` vsebuje le Assets in MainMenu, Pods resources script pa tega agregata ne kopira. Dodati njegovo vsebino v priložene/dostopne notice ter dokazati paket. Sam obstoj Pods acknowledgement izven `.app` ni dostava uporabniku.
* **Linux flutter_secure_storage 1.2.3 / nlohmann JSON 3.11.2:** glavni paket ima BSD-3-Clause, vendar `linux/include/json.hpp:3`–7 vsebuje dodatni MIT copyright Nielsa Lohmanna (2013–2022). `Secret.hpp:31`, `:76` in native plugin `flutter_secure_storage_linux_plugin.cc:44` dejansko uporabljajo te JSON tipe. V končni Snap inventar dodati to vgrajeno native komponento ter preveriti njen točni notice; sam BSD tekst paketa je ne pokrije. To ni ugotovitev o že razdeljenem Snapu, ki še ne obstaja. [Izvorna licenca JSON v3.11.2](https://github.com/nlohmann/json/blob/v3.11.2/LICENSE.MIT).
* **nanopb 3.30910.0:** `macos/Podfile.lock:75`, `macos/Pods/nanopb/LICENSE.txt:1`; zlib-style licenca. Acknowledgment pri binarni uporabi je zaželen, **ni obvezen**; ohranitev notice je izrecna pri source distribuciji. Ne označiti njegove odsotnosti iz UI za samostojno potrjeno kršitev.
* **Windows Firebase C++ SDK 13.12.0:** `firebase_core-4.15.0/windows/CMakeLists.txt:7`, `:28`, `:121`, `:143` prenese SDK ter linka **firebase_app**, čeprav aplikacija desktop push ne aktivira. Lock Dart BSD ne pokriva native SDK secondary licenc; arhiv in final linked dependency/notice inventar tukaj nista bila prenesena ali zgrajena. **Nepreverjeno/release gap:** zajeti SDK LICENSE/third_party notices po dejansko povezanih komponentah. Ni podlage za trditev, da se vsi auth/firestore/storage targeti s seznama na `:125` vključijo v program; stvarno linkan target je firebase_app.
* **Windows share_plus 11.1.0:** `share_plus-11.1.0/windows/share_plus_plugin.cpp:7` vključuje `vector.h`; `vector.h:1` ima Microsoft copyright in **MIT**, medtem ko glavni paket LICENSE vsebuje BSD-3-Clause. Preveriti retained template instantiations; pri distribuciji tega dela vključiti Microsoft MIT notice. SDK engine agregat že vsebuje podobne Microsoft copyright/MIT zapise (npr. za HarfBuzz), vendar niso povsem isti zapis z `All rights reserved` in vezavo na vector.h; **ni potrjena manjkajoča obveznost**, dokler ni preverjeno celotno final pokritje. Gre za preverjanje secondary notice pokritja, ne prepoved distribucije.

**Obveznost in sprejem:** MIT ohranitev copyright/permission v copies/substantial portions; BSD binary reproduction pogojev/disclaimerja; Apache-2.0 polno besedilo in applicable NOTICE, če ga upstream priloži. [MIT](https://opensource.org/license/mit), [Apache §4](https://www.apache.org/licenses/LICENSE-2.0). Po končnem pakiranju iz MSIX/Snap/.app izvleči NOTICES in morebitne ločene datoteke, primerjati z dejanskim native/runtime inventarjem in odpreti v UI brez povezave. Različne zahteve ne smejo biti združene v blanket »vsi obvezno source«.

### L-03 · P2 · Uporabnik nima dostopnega prikaza licenc

**Status: potrjena UI vrzel; sama po sebi ni dokaz vseh zakonskih kršitev.** `lib/organizer/presentation/settings_page.dart:65` gradi nastavitve brez licenc; globalni read-only `rg -n -i 'showabout|aboutdialog|license|licence' lib` ni vrnil zadetka. Ni `showLicensePage`, `LicensePage`, `LicenseRegistry.addLicense` niti druge prepoznane poti obvestil. Flutter jih sam registrira prek SDK `packages/flutter/lib/src/services/binding.dart:190`, `:203`, `:207`, vendar aplikacija ne odpre prikaza. [API showLicensePage](https://api.flutter.dev/flutter/material/showLicensePage.html).

**Pomemben pozitivni dokaz:** `build/macos/Build/Products/Debug/Jivie.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/NOTICES.Z` **obstaja**, dekompresiran vsebuje 1.438.727 znakov, vključuje Dart glavne licence, MPL, engine FreeType/HarfBuzz/ICU. Mtime **7. 10. 2026 19:45:30**: to je star debug izdelek, **ni trenutni distribucijski kandidat**. V njem niso najdeni FirebaseCore/GoogleDataTransport/Promises/native acknowledgement ali image notmasteryet/Limbic/Industrial Light in archive JCraft/imaya/BouncyCastle. To dokazuje staro mehaniko, ne končnega stanja 31. `linux/CMakeLists.txt:122` in `windows/CMakeLists.txt:102` kopirata celoten flutter_assets, zato brez preverjanja ne smemo trditi, da MSIX/Snap NOTICE ne bosta dostavila.

**Potrebno/sprejem:** Nastavitve → Licence z dosegljivim LicensePage, dopolnjenim z native/secondary in MPL source povezavami; widget preverjanje v SL/EN + dejansko preverjanje po namestitvi vseh treh formatov brez omrežja. Obstoječi kompresirani NOTICES je koristna osnova, ne dokaz uporabniške dosegljivosti ali popolnosti.

### L-04 · P2 · Pisave in Unicode: izvor ter obvestila še niso popolnoma dokazani

**Status: release gap/nepreverjeno, brez blanket sklepa o kršitvi.** Material ikone so omogočene (`pubspec.yaml:120`), Cupertino font je dejansko uporabljen (`lib/app_router.dart:29`), Cupertino `1.0.8` je MIT (`.pub-cache/.../cupertino_icons-1.0.8/LICENSE:1`) in samodejni zbiralnik ga zajame. Lokalni Flutter cache `/Users/anzenovsak/Dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt:1` pa vsebuje **CC BY 4.0**, medtem ko aktualni [Google material-design-icons LICENSE](https://github.com/google/material-design-icons/blob/master/LICENSE) kaže **Apache-2.0**. Ne sklepati licence konkretnega OTF samo iz današnjega upstream repozitorija. Dokazati hash/provenanco dejansko uporabljenega fonta in ustrezno dovoljeno licenco; pri uporabi CC BY dodati attribution/licenčno povezavo in oznako spremembe, če je podmnožen. [CC BY 4.0 §3](https://creativecommons.org/licenses/by/4.0/legalcode.en). `Roboto_LICENSE.txt` in `RobotoCondensed_LICENSE.txt` v cache sta Apache-2.0, vendar njun obstoj ne dokazuje, da se oba fonta dejansko dostavita namizni aplikaciji. Final font manifest/inventar ostaja acceptance.

`characters 1.4.1/lib/src/grapheme_clusters/table.dart:5` do `:11` izrecno pravi, da je runtime tabela generirana iz Unicode podatkov, pod Unicode licenco. `third_party/Unicode_Consortium/UNICODE_LICENSE.txt:1` je **Unicode License V3**, copyright 1991–2024. Samo root BSD datoteka tega ne zajame; SDK engine agregat sicer vsebuje Unicode License V3 (torej ni dovolj iskati samo enega naziva), vendar preverjeni SDK agregat ne vsebuje natančnega copyrighta 1991–2024 in cele normalizirane datoteke. **Sprejem:** vključiti konkretni Unicode notice ali dokazati, da enakovredno pravilno notice že obstaja v končni distribuciji. `characters/third_party/Wikipedia/License CC BY-SA 3.0.txt` ni samodejni dokaz runtime CC-BY-SA obveznosti: brez dokazljivega prenosa tega gradiva v final kodo gre za razvojne/testne podatke; ne trditi, da Jivie s tem postane CC-BY-SA. [Unicode license](https://www.unicode.org/license.txt).

### L-05 · P2 · Lastna aplikacijska licenca je ločena odločitev

**Status: nepreverjeno/release dokumentacijska vrzel, ne zahteva po odprti kodi.** Ni korenskega LICENSE za celotno Jivie aplikacijo. `publish_to: none` (`pubspec.yaml:7`) preprečuje pub objavo, ne določi pravic končnemu uporabniku. `server/plugins/FamilyHub/LICENSE:1` je MIT in po `docs/RENOVATION_PLAN.md:51` izrecno ne spremeni licence aplikacije. Izdajatelj lahko brezplačen Jivie deli kot lastniško aplikacijo, ob upoštevanju tujega OSS in trgovinskih pogojev; brezplačnost ni waiver tujih notice/MPL obveznosti. Pred izdajo potrditi lastne pravice za Jivie ter njegove pogoje/EULA in OSS carve-out; **ne dodajati MIT celotni aplikaciji samodejno**. Znamka ima zabeleženo imagegen provenanco `assets/branding/jivie/README.md:5`; brez iskanja po pravicah/registrih ni trditve o izključnosti znamke.

### L-06 · P1 · Snap native knjižnice zahtevajo tudi LGPL pregled

**Potrjene odvisnosti + vrzel končnega inventarja.** Linux neposredno povezuje
GTK 3 (`linux/CMakeLists.txt:56`) in libsecret prek varne hrambe (S-02).
Uradna GTK 3 in libsecret dokumentacija navajata **LGPL-2.1-or-later**. To sta
native knjižnici, ločeni od Dart paketa `gtk` z MPL-2.0. Zato rezultat »brez GPL/
AGPL v Dart popisu« ne pomeni, da bodo vsi bajti Snap paketa MIT/BSD/Apache.

**Potrebno:** po izbiri Snap base/GNOME content runtime in stage paketov popisati,
katere knjižnice distribuira Jivie in katere dobavlja drug runtime. Za lastne
distribuirane LGPL dele zagotoviti pravilna obvestila, licenco in dostop do
ustreznega izvora; izpolniti pogoje izbranega načina povezovanja/zamenljivosti
knjižnice. Lastni EULA ne sme izničiti pravic, potrebnih za spremembe teh
knjižnic in odpravljanje napak. Pri libgcc/libstdc++, če sta distribuirana,
preveriti tudi dejansko GCC Runtime Library Exception; ne obravnavati ju
avtomatično kot GPL brez izjeme ali kot poljubno permissive knjižnico.

**Sprejem:** vsak vgrajeni ELF/.so ima identificiran izvor, različico in
licenčno obveznost; izbran način dostave izvorov in obvestil dejansko deluje.
Ta postavka ne zahteva samodejne objave celotne kode Jivie in ne ugotavlja
kršitve v še neobstoječem Snap paketu.
Viri: [GTK 3](https://docs.gtk.org/gtk3/),
[libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/),
[LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html),
[GCC izjema](https://www.gnu.org/licenses/gcc-exception-3.1-faq.en.html).

### Native/sistemski obseg in pozitivni sklepi

Dart runtime closure v priloženem popolnem popisu je **134 paketov skupaj; 120 glavna closure / 14 samo dev**. V tem Dart popisu ni ugotovljene GPL/AGPL odvisnosti; dva paketa sta MPL-2.0. Največ licenc je permissive MIT/BSD/Apache in ni ugotovljene blanket prepovedi Microsoft/Snap/Mac Store distribucije. Vseeno to ni all-clear brez zgornjih acceptance korakov.

`sqlite3 3.7.0` je označen direct dev, vendar je `drift-2.35.1/pubspec.yaml:25` glavna odvisnost ter baza uporablja Drift: **ni pravilno izločiti SQLite iz runtime revizije**. Dart sqlite3 wrapper je MIT; privzeti native hook `sqlite3-3.7.0/lib/src/hook/compile/description.dart:64` do `:67` izbira sqlite3 GitHub binary, ne sqlcipher/sqlite3mc. Upstream SQLite jedro je [public domain](https://sqlite.org/copyright.html); konkretno končno binarno različico/hook konfiguracijo/hash še dokumentirati za vsak OS. Iz naslova podpore sqlcipher v orodju ni sklepati, da aplikacija distribuira SQLCipher.

Windows `flutter_local_notifications_windows 3.1.1` zgradi svojo FFI DLL (`windows/CMakeLists.txt:13`, `:18`; `src/CMakeLists.txt:10`) in veže sistemski runtimeobject; ni ugotovljenega dodatnega WinToast/Windows App SDK NuGet prenosa v tem source. flutter_secure_storage_windows uporablja Flutter ter OS knjižnice, brez bundled crypto odvisnosti iz svojega CMake. Za C/C++ runtime in Windows SDK velja še popis dejansko distribuiranih DLL; samo razvojni SDK ni runtime odvisnost.

Linux dejansko native linka GTK in libsecret; sistemske povezave in bodoče Snap stage/base knjižnice so ločen predmet končnega paketnega inventarja. Googletest FetchContent v nekaterih pluginih je test-only; ne prenašati testnih licenc/targetov v trditev o runtime, če niso zapakirani. macOS platformni frameworki niso samodejno isto kot redistribuiran OSS. Dart 120 closure vključuje web/Android/iOS ter build hook orodja; točnega platformnega AOT retention brez končnih desktop paketov ne potrjujem.

FamilyHub je ločen strežniški MIT projekt; komunikacija z njim prek HTTP ne pomeni, da PHP/Kanboard/SwiftMailer kode dostavimo v namiznem MSIX/Snap/MAS paketu. Ta revizija ne spreminja niti ne ocenjuje njegove celotne strežniške distribucije. Nepovezan varnostni dokument ni bil odprt.

## Skupne platformne ugotovitve

### D-01 · P1 · Identiteta trgovine in obstoječi podatki zahtevajo skupen načrt

**Potrjeno v izvoru + vrzel priprave.** Razvojne namizne identitete so namenoma
ohranjene: Linux `com.example.kanban` v `linux/CMakeLists.txt:11`, Mac in Windows
imata enako zgodovinsko omejitev, opisano v `docs/release/PLATFORM_NOTES.md`.
To ni dovoljenje za slepo preimenovanje. Osrednja SQLite baza se odpira v
Documents prek `lib/organizer/data/collaboration_database_native.dart:6`, ne v
isti lokaciji kot vse nastavitve in skrivnosti. Hive se inicializira ločeno v
`lib/organizer/data/organizer_storage.dart:131`.

**Potrebno:** popis SQLite/WAL/SHM, Hive, nastavitev, osnutkov, prenesenih vsebin,
varne shrambe in obnovitvenih podatkov za vsako staro in novo identiteto. Izbrati
končne Store identifikatorje ter varen prenos, ki ne prepiše že obstoječega cilja.
Prenos sej je dovoljen samo, kjer ga podpirajo pravice platforme; sicer jasna
ponovna prijava z ohranjeno lokalno vsebino. Ne poskušati pridobiti tujega keychaina.

**Sprejem:** sveža namestitev in nadgradnja obstoječega testnega profila ohranita
vsebine, osnutke, nedostavljeno delo in preference; prekinjen prenos je ponovljiv,
preklic ohrani vir, novejša baza se ne ponastavi. Dokaz za vsako platformo posebej.

### D-02 · P1 · Funkcije obvestil še niso enake na vseh namizjih

**Potrjeno v izvoru; funkcionalna vrzel, ne samodejna kršitev pravil trgovine.**
`FlutterNotificationScheduler.supported` vključuje Android/iOS/macOS, ne pa
Windows/Linux (`lib/organizer/platform/flutter_notification_scheduler.dart:17`).
`FirebasePushSdk.supported` vključuje samo Android/iOS
(`lib/organizer/platform/remote_push/firebase_push_sdk.dart:26`). Namizni center
v aplikaciji je ločena funkcija in ni dokaz sistemske dostave pri zaprti aplikaciji.
UI omejitve že razkriva (`lib/l10n/app_en.arb:326`, `:483`).

**Potrebno:** določiti in implementirati realni obseg lokalnih/oddaljenih
opomnikov na posameznem namizju; pri Linuxu ne predpostaviti podpore za prihodnje
časovno načrtovanje samo zato, ker plugin zna pokazati trenutno obvestilo.
Morebitna ožja prva izdaja potrebuje jasno produktno odločitev in točen opis.
Prisotnost Firebase SDK v paketu sama ne pomeni vključenega push ali analitike.

**Sprejem:** preveriti dovoljenja, zvok/tišino, časovni pas in poletni čas,
odpiranje pravilnega zapisa, podvojitve, odjavo ter vedenje pri zaprtem oknu,
končanem procesu, spanju in ponovnem zagonu. Trgovinski opis obljublja samo
dejansko preverjene kombinacije.

### D-03 · P1 · Dokaz posodobitve mora zajeti podatke, ne samo številke različice

**Vrzel priprave.** Repo ima migracije lokalne sheme (`schemaVersion = 10`,
`lib/organizer/data/collaboration_database.dart:10`, `:38`), nima pa dokaza
nadgradnje dveh javnih namiznih trgovinskih paketov. Mobilni release dokazi in
widget testi tega ne nadomestijo.

**Potrebno:** pripraviti ponovljiv izdajni postopek, vezan na commit, zaklenjene
odvisnosti, Flutter SDK in SHA paketa; konfigurirati pravilno naraščanje verzij.
Na napravi preveriti prehod N → N+1 prek vsake trgovinske poti, brez lastnega updaterja.
Povrnitev binarnega paketa ne pomeni samodejno povrnitve združljive baze.

**Sprejem:** isti račun in lokalni profil po nadgradnji, ohranjena neodposlana
vrsta/osnutki/obvestilne preference, varno končanje odprtega urejanja, uspešen
ponovni zagon; varno opozorilo ali zavrnitev nezdružljive starejše različice.
Za Snap posebej preveriti `refresh` in `revert` glede na izbrano lokacijo baze.

### D-04 · P2 · Deklaracije, posnetki in pregledni dostop morajo opisovati namizni paket

**Vrzel priprave + nepreverjeno v portalih.** Obstoječi opisi in galerije so
mobilni. Spletna zasebnost že obravnava preglednice/priloge in omejitev Mac push
(`website/public/privacy/index.html:14`), vendar posebej ne opredeli Windows/Linux
opomnikov, Snap snapshots ali končne namizne distribucije. Že obstoječa politika
in izbris nista manjkajoča v celoti: UI ima `jivie_public_links.dart`,
`settings_page.dart` in `onboarding/account_deletion_panel.dart`.

**Potrebno:** za vsako končno platformo preveriti dejansko obdelavo podatkov
(tudi izbirno sinhronizacijo in vključene SDK), uporabniške licence, opis omejitev,
podporo, kategorijo, starostne odgovore, jezike in prave namizne slike. Pripraviti
pregledni strežnik/račun z neosebnimi podatki in navodili za skupne funkcije,
lokalni način in izbris. Gesel ne zapisovati v ta dokument. Lastnik preveri
identiteto izdajatelja in morebitne EU trader/DSA obrazce; brezplačna cena sama
ne določi statusa trgovca.

**Sprejem:** opisi in obrazci se ujemajo z distribuiranim paketom, javne podporne
povezave delujejo, pregledovalec lahko preveri ključne funkcije brez osebnega
računa razvijalca, omejitve izbrisa in kopij so natančne. Obstoječi strežniški
mehanizmi niso v tem koraku ponovno testirani ali spreminjani.
Vir za EU podatke: [Apple DSA/trader](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

### D-05 · P2 · Dostopnost je treba preveriti na dejanskih namizjih

**Dobra podlaga + nepreverjeno.** Obstajajo namizni meniji/bližnjice
(`lib/organizer/presentation/desktop/desktop_commands.dart:271`), Semantics in
upravljanje preglednice s tipkovnico (`lib/organizer/presentation/tables/spreadsheet_grid.dart:373`). Obstoječi
`docs/DESKTOP_UX.md` izrecno pušča fizični preizkus bralnikov zaslona odprt.

**Sprejem:** ključni tokovi samo s tipkovnico, vrstni red fokusa, modali in
Escape/Enter; Narrator, VoiceOver in izbrani Linux bralnik; povečano besedilo,
200 % DPI, kontrast in ozko okno. Dostopnostne oznake trgovine uporabiti le
za dejansko preverjeno podporo. To ne zahteva ponovitve celotne mobilne matrike.

## Microsoft Store / Windows

### W-01 · P1 · Manjka pogodba in postopek pakiranja MSIX

**Potrjeno v izvoru + vrzel priprave.** Ni `msix_config`, MSIX/Appx package
manifesta ali sledljivega postopka pakiranja. `windows/runner/runner.exe.manifest:2`
je Win32 DPI/OS manifest, ne MSIX manifest. Odsotnost paketa `msix` v pubspec
sama ni napaka: izberemo lahko drugo ustrezno orodje. CI prav tako ni pogoj trgovine.

**Potrebno:** rezervacija pravega izdelka in nato točni Name/Publisher/Store ID,
entrypoint, ikone, jeziki, capabilities, odvisnosti in Windows.Desktop minOS.
Pri Flutter full-trust Win32 preveriti `runFullTrust`; pravic ne širiti na zalogo.
Identiteto preverjati v končnem generiranem manifestu in ne samo nastavitvah orodja.

**Sprejem:** validen MSIX/bundle iz zamrznjenega izvora, ujemanje identitete s
Partner Center, clean install/uninstall, WACK brez blokirajočih napak in
dokumentirane morebitne izjeme. Lokalni testni podpis je ločen od podpisa
Microsoft Store; zanj ne potrebujemo nakupa certifikata za javno spletno distribucijo.
Viri: [zahteve MSIX](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements),
[full-trust pakiranje](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion),
[certifikacija](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-certification-process).

### W-02 · P1 · Windows Release, DLL in podprte arhitekture niso preverjeni

**Nepreverjeno.** `docs/DESKTOP_UX.md:79` navaja neizvedeni Windows/Linux native
gradnji. `windows/CMakeLists.txt:75` naprej namesti engine, vtičnike, native
assets in AOT, vendar še ni dokaza zagona na čistem Windows. Obstoječi compatibility
GUID v `runner.exe.manifest:11` ne določa minimalnega Windows builda.

Zaklenjeni `firebase_core 4.15.0` v Windows CMake uporablja Firebase C++ SDK
**13.12.0** in poveže `firebase_app`, četudi D-02 izključi desktop FCM.
`flutter_local_notifications_windows` ima FFI DLL. Odsotnost file_picker,
path_provider ali sqlite iz C++ registratorja sama ni napaka, saj uporabljajo
tudi Dart/FFI. Podpora Flutter ogrodja za Arm64 ne dokazuje podpore vseh vtičnikov.

**Potrebno/sprejem:** določiti prvi podprti cilj in minOS po najstrožji odvisnosti;
preveriti Release na čisti napravi brez Flutterja/Visual Studia, VC++ runtime
in celoten DLL/native-asset inventar. Na vsaki oglaševani arhitekturi morajo
delovati lokalni zapis/restart, SQLite, DPAPI hramba, datoteke, časovni pas,
povezave, deljenje in dogovorjena obvestila. Ne oglaševati Arm64 samo iz nastavitve ogrodja.
Viri: [Flutter Windows distribucija](https://docs.flutter.dev/platform-integration/windows/building),
[podprte platforme](https://docs.flutter.dev/reference/supported-platforms).

### W-03 · P1 · MSIX virtualizacija in stara Windows hramba potrebujeta migracijski dokaz

**Potrjeno v izvoru + nepreverjeno v paketu.** `Runner.rc:92` pojasnjuje, zakaj
ostajata `CompanyName=com.example` in `ProductName=kanban` (`:95`, `:101`).
Zaklenjeni `flutter_secure_storage_windows 3.1.2` uporablja DPAPI in
ApplicationSupport (`lib/src/flutter_secure_storage_windows_ffi.dart:180` v paketu),
ki ga path_provider izpelje iz teh metapodatkov. Documents baza iz D-01 je
ločena od AppData; ni podlage za trditev, da odstranitev aplikacije izbriše vse.

**Potrebno/sprejem:** D-01 in D-03 izvedemo tudi za nepakiran profil → MSIX,
MSIX N → N+1 in uninstall/reinstall. Preveriti dejansko AppData virtualizacijo,
DPAPI branje/pisanje in stabilno package family. Samo vidni copyright
`Runner.rc:99` lahko uredimo ločeno od identitet, ki vplivajo na shrambo.
Viri: [MSIX virtualizacija](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization),
[identiteta paketa](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/package-identity-overview).

### W-04 · P1 · Registracija in posredovanje povabil v odprto instanco manjkata

**Potrjeno v izvoru + nepreverjen runtime.** `app_links` je registriran
(`windows/flutter/generated_plugin_registrant.cc:19`), parser sprejema obe
shemi (`lib/organizer/platform/invitation_links/invitation_link.dart:7`),
MSIX registracije protokolov pa ni. `windows/runner/main.cpp:8` nima
`SendAppLinkToInstance()` ali drugega primerljivega instance-forwarding mehanizma.

**Potrebno/sprejem:** deklarirati `jivie` in `vsakdan`, urediti podprto
posredovanje obstoječi instanci ter preveriti hladno/toplo aktivacijo,
napačno/poteklo povabilo, preklic, menjavo računa in odstranitev registracij.
Drug zagon ne sme povzročiti podvojenega sprejema ali nekontroliranega sočasnega
urejanja istega profila. Ročni vnos povabila ostane dosegljiv.
Vir: [app_links Windows](https://github.com/llfbandit/app_links/blob/main/doc/README_windows.md).

### W-05 · P1 · Store različico je treba določiti ločeno od Win32 file version

**Vrzel priprave, ne potrjeno napačen paket.** `Runner.rc:63` iz Flutter verzije
ustvari štiridelno file version; `1.10.1+31` zato ne pomeni, da že obstaja MSIX
z enako verzijo. Microsoftova pravila za opisane Windows 10/11 Store pakete
rezervirajo zadnji del verzije za Store in predpisujejo `.0`.

**Potrebno/sprejem:** definirati enolično, naraščajoče mapiranje za MSIX,
ki omogoča tudi več popravkov iste semantične različice. Preveriti generirani
Package/Identity Version in dejansko nadgradnjo; Android buildNumber ne kopirati
slepo v četrto mesto. Izbira npr. `1.10.31.0` je možnost za dogovor, ne v tem
pregledu sprejeta ali izvedena nova verzija.
Vir: [Store package version](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements#package-version-numbering).

**Časovna opomba pravil:** 16. 10. 2026 velja Microsoft Store policy **7.19**.
Glavna stran že objavlja **7.20**, ki začne veljati **22. 10. 2026**.
Za poznejšo oddajo je treba pregled opraviti proti takrat veljavnim pravilom.
Finančni razdelek Jivie je evidenca denarja, ne ugotovljena bančna povezava;
iz samega imena »Finance« ne sklepamo o kršitvi pravil za finančne storitve.
Vira: [7.19](https://learn.microsoft.com/en-us/windows/apps/publish/store-policy-archive/store-policy-7-19),
[7.20](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies).

## Mac App Store

### M-01 · P1 · Odločitev o App Store Connect zapisu in Store podpis še nista zaključena

**Vrzel priprave.** `macos/Runner/Configs/AppInfo.xcconfig:12` ohranja
`com.example.kanban`. Dodajanje Mac platforme obstoječemu iOS zapisu zahteva isti
bundle ID; ločen Mac zapis lahko uporablja svojo identiteto. To je odločitev
pred D-01, ne razlog za takojšnje preimenovanje.

`macos/Runner.xcodeproj/project.pbxproj:574`, `:650`, `:706` vsebuje ad-hoc
`CODE_SIGN_IDENTITY = "-"`; macOS `DEVELOPMENT_TEAM` ni nastavljen. Obstoječi
uspešni podpisani Mac v `docs/release/MAC_REVIEW_LOGIN.md` je razvojni paket.
To ne dokazuje odsotnosti ustreznih certifikatov v računu, dokazuje pa
nezaključeno repozitorijsko Store podpisno pot.

**Potrebno/sprejem:** po odločitvi o zapisu in migraciji pripraviti ustrezno
Mac distribucijsko podpisovanje, Release arhiv in Xcode Validate App. Preveriti
vse Mach-O podpise, dejanske sandbox/Keychain entitlements in odsotnost
razvojnega `get-task-allow`; po distribucijski namestitvi prijava/restart/datoteke
delujejo. Developer ID/notarizacija za spletno distribucijo nista nadomestilo.
Viri: [Apple dodajanje platform](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/),
[vrste certifikatov](https://developer.apple.com/help/account/certificates/certificates-overview/),
[Flutter Mac izdaja](https://docs.flutter.dev/deployment/macos).

### M-02 · P1 · Manjka kategorija aplikacije za Mac

**Potrjeno v konfiguraciji.** `macos/Runner/Info.plist:4` ne vsebuje
`LSApplicationCategoryType`; v pregledanem Mac projektu ni druge nastavitve
kategorije. To je zahtevani podatek v postopku priprave Mac App Store.

**Potrebno/sprejem:** izbrati ustrezno kategorijo (kandidat Productivity),
dodati jo v konfiguracijo in preveriti končni `.app/Contents/Info.plist` ter
Xcode validacijo. Vidni placeholder copyright v `AppInfo.xcconfig:15` uskladiti
z izdajateljem, ne da bi mimogrede spreminjali podatkovno identiteto.
Viri: [Flutter projektne nastavitve](https://docs.flutter.dev/deployment/macos),
[Apple kategorija](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype).

### M-03 · P1 · Podprti Maci in končni native paket še niso dokazani

**Nepreverjeno, dobra izvorna podlaga.** Minimum macOS **12.0** je usklajen v
`macos/Podfile:1`, Xcode projektu in Info.plist. Samo Debug določa
`ONLY_ACTIVE_ARCH=YES`; odsotnost Release izključitev še ni dokaz univerzalnega
paketa. `macos/Podfile.lock` vključuje Firebase **12.19.0** in druge native
odvisnosti; uspešni iOS31 arhiv jih za macOS ne potrjuje.

**Potrebno/sprejem:** odločiti podporo Intel/Apple Silicon, preveriti dejanske
arhitekturne slice in minOS vseh vgrajenih frameworkov ter zagon na deklariranem
minimumu in aktualnem macOS. Ciljni tokovi: lokalni CRUD/restart, varna hramba,
prijava, preglednica, priponka, izvoz/obnova, obvestilo in povabilo. Podpora mora
biti enaka v paketu, trgovini in dokumentaciji.

### M-04 · P1 · Izvozna klasifikacija šifriranja mora vključiti šifrirane kopije

**Potrjena uporaba + nepreverjen zaključek obrazcev za Mac.**
`lib/organizer/data/portable_backup_crypto.dart:12` uporablja AES-256-GCM in
PBKDF2-HMAC-SHA256 (`:13`). Ne gre samo za sistemski HTTPS. Odsotnost
`ITSAppUsesNonExemptEncryption` v Info.plist sama ni napaka, če so pravilni
odgovori urejeni v App Store Connect; samodejni vpis `false` pa ni primeren popravek.

**Potrebno/sprejem:** pregledati končno Mac kriptografsko sestavo in ciljne države,
na tej podlagi zaključiti Apple export compliance oziroma potrebno dokumentacijo.
Ne kopirati brez presoje odgovora starega iOS builda. Dejanski Mac posnetki naj
sledijo specifikaciji, npr. 1280×800 ali 2560×1600, ne iPhone/iPad galeriji (D-04).
Viri: [Apple šifriranje](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations),
[zahtevani posnetki](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

### M-05 · P1 · Pravila za uporabniško vsebino potrebujejo presojo blokiranja in filtriranja

**Nepreverjena skladnost; prijave in skrbniška moderacija že obstajajo.**
`lib/organizer/data/collaboration_moderation.dart:212` omogoča prijave vsebin,
članov, tabel in prilog; `NativeModerationAdminService.php:36` pozna odstranjevanje
vsebine in omejitev člana. V pregledanih poteh ni dokazan uporabniški tok
blokiranja drugega člana ali ločeno opredeljeno filtriranje. Skrbniška omejitev
sama ne dokazuje vseh uporabniških zmožnosti iz Applovega pravila 1.2.

**Potrebno:** preslikati dejanske tokove zasebnih skupin in self-hosted strežnikov
na zahteve za uporabniško vsebino; opisati filtriranje, prijavo, blokiranje,
kontakt in obravnavo prijav. Kjer obstoječa rešitev ne zadostuje, predlagati
uporabniški tok in strežniško uveljavitev, ki ohrani pravilno finančno zgodovino.
To ni trditev o že potrjeni zavrnitvi Apple ali dovoljenje za spremembo produkcije.

**Sprejem:** z dvema sintetičnima računoma demonstrirati obseg prijave,
prenehanja neželenih stikov, omejitve člana in odstranitve vsebine; pravilno
vedenje na samostojnem strežniku in jasna navodila za pregledovalca.
Vir: [Apple pravilo 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).

### M-06 · P2 · Pregled dejanskega SDK/privacy arhiva, brez napačne preslikave iOS zahtev

**Nepreverjeno.** V `macos/Runner` ni lastnega `PrivacyInfo.xcprivacy`; odvisnosti
imajo svoje manifeste. Končni Mac arhiv in njegovo zbirno privacy poročilo nista
bila ustvarjena ali pregledana. Aktualno Apple besedilo o required-reason API
izrecno našteva iOS/iPadOS/tvOS/visionOS/watchOS, ne macOS. Zato odsotnosti Mac
app manifesta ne označujemo kot potrjeno ITMS-91053 kršitev.

**Potrebno/sprejem:** pregledati dejansko vgrajene SDK in njihove manifeste,
zbirno poročilo ter App Privacy odgovore za končni paket. Ne dodajati praznega
manifesta ali trditve »no data collected« samo zaradi lokalnega načina.
Viri: [Apple required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api),
[App Privacy](https://developer.apple.com/app-store/app-privacy-details/).

**Že dobra Mac podlaga:** Release sandbox, odhodno omrežje, user-selected
read/write in Keychain skupina obstajajo (`Release.entitlements:5`); shemi
`jivie` in `vsakdan` sta deklarirani (`Info.plist:5`). File picker 10.3.10 dejansko
shrani podane bajte. Lokalni opomniki podpirajo Mac, oddaljeni push pa ne (D-02).
Razvojni Mac ima zgodovinski dokaz uspešne prijave/restarta; to ostaja koristen
dokaz, vendar ne nadomesti preverjanja nove Store identitete in paketa.

## Snap / Linux

### S-01 · P1 · Paket Snap in namizna registracija še ne obstajata

**Potrjeno v izvoru + vrzel priprave.** Pregled `git ls-files` in imen datotek ni
našel `snapcraft.yaml`, `.snapcraft.yaml`, datoteke `.desktop` ali izdajnega
postopka Snap. `linux/CMakeLists.txt:83` naprej pripravi običajen Flutter bundle,
kar še ni trgovinski paket. Linux native gradnja ni potrjena v obstoječem
`docs/DESKTOP_UX.md`.

**Potrebno:** recept z izbrano podprto osnovo, arhitekturami, `grade: stable`,
`confinement: strict`, opisom/licenco/kontaktom, ikono in namiznim vnosom.
Zakleniti dejanski Flutter SDK; lokalni pregled je našel Flutter **3.47.2**,
Dart **3.13.2**, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`.
Spodnja meja v pubspec ni dokaz uporabljenega SDK. Določiti GTK/GNOME runtime,
native knjižnice in minimalne povezave do sistema. `classic` ni rezervni način,
s katerim bi obšli manjkajoč sandbox načrt; zahteva ločeno upravičenost/pregled.

**Sprejem:** uspešna Linux release gradnja in namestitev strogo omejenega paketa
na čist podprt sistem, zagon iz programskega menija, pravilna ikona/ime,
brez manjkajočih `.so` ali nepojasnjenih AppArmor zavrnitev.
Viri: [Flutter Snap izdaja](https://docs.flutter.dev/deployment/linux),
[recept Snap](https://ubuntu.com/docs/snapcraft/latest/reference/snapcraft-yaml/),
[omejevanje Snap](https://snapcraft.io/docs/explanation/security/snap-confinement/).

### S-02 · P1 · Varna hramba potrebuje ločen načrt povezave Secret Service

**Potrjena odvisnost + vrzel priprave.** `flutter_secure_storage_linux 1.2.3`
uporablja `libsecret-1>=0.18.4` (`linux/CMakeLists.txt:15` znotraj paketa) in
`SecretStorage`; aplikacija ga uporablja za seje in povabila, npr.
`lib/organizer/state/collaboration_provider.dart:34`.
Snapov `password-manager-service` nima privzetega samodejnega povezovanja.
Uspeh nezapakiranega programa zato ne potrjuje prijave v Snap.

**Potrebno:** določiti podprto varno hrambo v strict paketu, utemeljiti potreben
interface ter po potrebi zaprositi za auto-connect oziroma ponuditi jasen
uporabniški korak. Ne nadomestiti varne hrambe s plaintext datoteko ali
SharedPreferences. Zapakirane native knjižnice vključiti tudi v licenčni popis.

**Sprejem:** prijava, zaprtje, ponovni zagon, odjava, zaklenjen/manjkajoč keyring
in nepovezan interface imajo preverjeno vedenje; skrivnosti se ne izgubijo
tiho in ne izpišejo. Lokalni način ima razumljivo obravnavo nedosegljive hrambe.
Vir: [password-manager-service](https://snapcraft.io/docs/reference/interfaces/password-manager-service-interface/).

### S-03 · P1 · Dokumenti, notranja baza in Snap snapshots niso še usklajeni

**Potrjeno v izvoru + nepreverjeno v Snap.** SQLite je v sistemskem Documents
(`collaboration_database_native.dart:7`); `path_provider_linux 2.2.1` vrne
`xdg.getUserDirectory('DOCUMENTS')` (`lib/src/path_provider_linux.dart:70`).
To ni samodejno Snapova zasebna lokacija in je treba preveriti tudi manjkajoči
XDG Documents imenik. Repo nima izbire `SNAP_USER_DATA`/`SNAP_USER_COMMON` ali
preverjene migracije. Ti lokaciji imata različno vedenje pri nadgradnji/povrnitvi.

**Potrebno:** notranje podatke umestiti v izbrano trajno zasebno lokacijo z
migracijo D-01; ne zahtevati širokega dostopa do home samo zaradi notranje baze.
Za prenos iz starih skritih map po potrebi preveriti `personal-files`, ki zahteva
Store deklaracijo, ali uporabiti uporabnikov izvoz/uvoz. Upoštevati Snapove
lokalne varnostne posnetke tudi pri dokumentiranju izbrisa aplikacije/podatkov.

**Sprejem:** local-first deluje brez omrežja, izbire dokumentne mape in prijave;
preverjena `refresh`/`revert`/odstranitev ter obnovitev, brez ponastavitve ali
podvojitve podatkov. Dokumentacija razlikuje strežniški izbris, lokalni izbris,
izvoz in Snapov posnetek.
Viri: [podatkovne lokacije](https://snapcraft.io/docs/reference/administration/data-locations/),
[posnetki](https://snapcraft.io/docs/how-to-guides/manage-snaps/create-data-snapshots/),
[personal-files](https://snapcraft.io/docs/reference/interfaces/personal-files-interface/).

### S-04 · P1 · Povabila nimajo popolne Linux aktivacije

**Potrjeno v izvoru; dejanski zagon še ni preizkušen.** Manjka `.desktop`
registracija za `jivie` in legacy `vsakdan`. Runner uporablja
`G_APPLICATION_NON_UNIQUE` (`linux/runner/my_application.cc:156`) in
`local_command_line`, ki pokliče `activate` (`:97`), ne pa celotne poti
`command-line`, ki jo posluša `gtk 2.2.0` in `app_links_linux 1.0.3`.
`lib/main.dart:15` ne sprejema argumentov; skupni receiver sicer obstaja
(`lib/organizer/platform/invitation_links/invitation_link_providers.dart:19`).
Posredovanje argumentov Dart projektu samo po sebi ni posredovanje AppLinks toku.

**Potrebno:** dokončati native aktivacijo in posredovanje povabila obstoječi
instanci, `.desktop` MIME registracijo ter uskladiti GTK ID/D-Bus s Snap
dovoljenji. Uporabniške povezave preverjati po obstoječih pravilih, ne kot ukaze.

**Sprejem:** hladen in topel zagon za obe shemi, veljavno/neveljavno/poteklo
povabilo, menjava računa in preklic; isti proces/urejevalnik se ohrani in ne
pride do dvojnega sprejema. Ločeno preveriti nameren drugi zagon aplikacije.
Vir: [navodila avtorja app_links za Linux](https://github.com/llfbandit/app_links/blob/main/doc/README_linux.md).

### S-05 · P2 · Datotečni portali so že uporabljeni; preveriti je treba paket

**Dobra podlaga + nepreverjena integracija.** Zaklenjeni `file_picker 10.3.10`
na Linuxu uporablja D-Bus `org.freedesktop.portal.FileChooser`, ne zenity/kdialog
(`lib/src/linux/file_picker_linux.dart:18`). Izvoz dejansko preda bajte in paket
jih zapiše (`:198`); ne beležimo napačne ugotovitve, da save dialog le vrne pot.
Aplikacija uporablja ta izbirnik za kopije, priloge in fotografije.

**Potrebno:** z izbrano namizno razširitvijo Snap preveriti portalne pravice,
GNOME/Wayland in izbrano drugo podprto okolje. Dodatnih home/removable-media
pravic ne dodajati brez konkretne potrebe.

**Sprejem:** uvoz/izvoz `.vsakdan`, JSON, fotografije in 20 MiB priloge; pravilni
bajti po shranjevanju, preklic brez zapisa, zunanja lokacija prek portala,
nedosegljiv portal brez lažnega uspeha. To je paketni test, ne razlog za
samodejno menjavo `file_picker`.
Vir: [Snap in XDG portali](https://snapcraft.io/docs/explanation/snap-development/xdg-desktop-portals/).

## Vrstni red za naslednji načrt nadgradenj

1. **Dogovori in identitete:** lastni pogoji uporabe/licenca L-05, pravni izdajatelj,
   imena in ID trgovin, Mac skupni ali ločeni App Store zapis, ciljni OS/arhitekture
   in dogovorjeni obseg sistemskih obvestil. Izhodišče so D-01/D-02, W-01/W-02/W-05,
   M-01/M-03 in S-01. Lastniku v tej fazi ne nalagamo nakupa Windows certifikata.
2. **Skupna licenčna in podatkovna podlaga:** L-01–L-04/L-06, D-01, W-03, S-03.
   Najprej popis in načrt migracije; šele nato spreminjanje identitet oziroma poti.
   Uporabniku dostopna obvestila pripraviti iz dejanskih komponent in njihovih verzij.
3. **Platformna integracija:** W-04, S-02/S-04/S-05, D-02 ter Mac podpis/kategorija.
   Posamezne platforme je po dogovoru mogoče obdelovati vzporedno, skupne podatkovne
   spremembe pa morajo imeti eno odgovorno integracijo.
4. **Pravila in vsebina izdaje:** M-04/M-05/M-06 in D-04/D-05. Točen opis,
   privacy/license podatki in pregledni scenariji se pripravijo za dejansko zgrajeno
   kandidatko. Prisotnost obrazca v kodi še ni uspešen tok iz trgovinskega paketa.
5. **Paketi in ciljna validacija:** izolirane native Release gradnje, inventar
   vgrajenih knjižnic/fontov/NOTICE, certifikacijska orodja in čiste namestitve.
   Tu se zaključi AOT/native licenčna preverba iz L-02/L-04; pred tem je popis
   zaklenjenih paketov širši od končnega binarnega izdelka.
6. **Prehod med različicama in oddaja:** D-03, nato pregled vseh P1 in relevantnih
   P2. Pripraviti konkretne pakete, dokaze in osnutke trgovin za ločeno naročeno
   oddajo. Ta revizija sama ni naročilo registracije, podpisa pogojev ali objave.

Izvedbeni načrt naj za vsako postavko ohrani ID, lastnika, odvisnosti, status,
dokaz izvedbe in datum. Zaključek pomeni izpolnjen sprejemni kriterij, ne samo
spremenjeno vrstico kode. Nova ugotovitev sodi v to isto datoteko, dokler ne
nastane posebej naročen izvedbeni načrt.

## Ciljno preverjanje pred prvo izdajo

| Področje | Potreben dokaz |
|---|---|
| Paket in identiteta | Commit/SDK/locks/hash; dejanski manifest, arhitekture, native podpisi in minimalni OS |
| Licence | Dostopna obvestila brez omrežja, MPL/LGPL izvor in pogoji izpolnjeni, secondary/native/font pokritje iz končnega paketa |
| Lokalni način | Hladen zagon brez računa/omrežja, ustvarjanje/urejanje in ponovni zagon brez izgube |
| Podatki | Migracija starega profila, SQLite in osnutki, izvoz/obnova, preklic in prekinitev postopka |
| Varna hramba | Prijava/restart/odjava, zaklenjena ali zavrnjena sistemska hramba, brez plaintext obvoda |
| Povezave | Hladen/topel `jivie` in `vsakdan`, ena instanca, pravi račun, neveljavno povabilo, preklic |
| Datoteke | Fotografija, 20 MiB priloga, `.vsakdan` in JSON, dejanski bajti, uporabniška izbira, preklic |
| Obvestila | Samo dogovorjene in opisane platformne funkcije, izklopi, zvok, pravi čas in cilj ob odprtju |
| Dostopnost | Tipkovnica, fokus, bralnik, kontrast, DPI/besedilo, SL/EN na dejanski platformi |
| Pravila in računi | Zasebnost, izbris, prijava vsebine/člana, dogovorjeno blokiranje, kontakt in reviewer tok |
| Nadgradnja | N → N+1 prek kanala, ohranjene nastavitve in čakajoče delo, prekinitev, nedowngradljiva novejša baza |

Te kontrole so merila za prihodnjo izvedbo, **ne rezultati tega pregleda**.
Ne naročajo nove splošne mobilne/strežniške testne matrike ali novih živih povabil.

## Obseg in preverjanje tega poročila

Pregledani so sledljivi konfiguracijski in izvorni vhodi, vsi zaklenjeni Dart
paketi z lokalnimi licencami, izbrane native knjižnice/Pods in secondary licence,
SDK zbiranje NOTICE ter relevantna uradna pravila. Lokalni cache je dokaz
pregledane različice, ne zagotovilo vsebine prihodnjega paketa.

Končni MSIX/Snap/Mac Store artefakti in njihove namestitve niso bili ustvarjeni.
Prijavljeni portali, aktualna veljavnost poverilnic, rezervacije imen, znamke,
vse pravne okoliščine izdajatelja ter vse native licence še neizbranega Snap base/
stage sestava niso preverjeni. Obstoječe zgodovinske rezultate ločujemo od novih
dejstev. Spletno besedilo Jivie je bilo pregledano iz repozitorija; ta pregled
sam ne potrjuje trenutne HTTPS vsebine gostovanja.

Dokumentacijska kontrola ob zaključku: ujemanje zaklenjenih paketov s popisom,
preverjene navedene repozitorijske datoteke/vrstice, enolični ID ugotovitev,
`git diff --check` ter pregled obsega sprememb. Aplikacijskih testov pri tej
dokumentacijski nalogi nismo ponavljali.

## Dodatek: popoln zaklenjen Dart/Flutter popis

Spodnji inventar je del istega poročila. Podrobne native/sekundarne in licenčne
izjeme so v L-01–L-06; samo glavna licenca paketa ne predstavlja celotne licence
vse vključene tuje kode. Ta tabela ni formalni SBOM že zgrajene namizne izdaje.


Zaklenjenih paketov: **134**. Rekurzivna `dependencies` closure iz glavnih odvisnosti: **120**; samo razvojna closure: **14**. Closure je širša od dejansko zadržanega desktop AOT: vključuje platforme, build hooks in platform interfaces. Ne predstavlja trditve, da se vsak paket distribuira na vsaki namizni platformi. `sqlite3` se kljub `direct dev` uporablja prek `drift` (`drift-2.35.1/pubspec.yaml:25`); `code_assets`, `hooks`, `native_toolchain_c`, `record_use` so hook/build orodja, ne nujno runtime binarno breme.

| Paket | Zaklenjena različica | Licenca lokalnega vira | Obseg | Dokaz in primarni vir |
|---|---|---|---|---|
| `_flutterfire_internals` | 1.3.77 | BSD-3-Clause | glavna dependency closure | pubspec.lock:4; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/_flutterfire_internals-1.3.77/LICENSE:1`; [vir](https://pub.dev/packages/_flutterfire_internals/versions/1.3.77/license) |
| `app_links` | 7.2.1 | Apache-2.0 | glavna dependency closure | pubspec.lock:12; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/app_links-7.2.1/LICENSE:1`; [vir](https://pub.dev/packages/app_links/versions/7.2.1/license) |
| `app_links_linux` | 1.0.3 | Apache-2.0 | glavna dependency closure | pubspec.lock:20; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/app_links_linux-1.0.3/LICENSE:1`; [vir](https://pub.dev/packages/app_links_linux/versions/1.0.3/license) |
| `app_links_platform_interface` | 2.0.4 | Apache-2.0 | glavna dependency closure | pubspec.lock:28; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/app_links_platform_interface-2.0.4/LICENSE:1`; [vir](https://pub.dev/packages/app_links_platform_interface/versions/2.0.4/license) |
| `app_links_web` | 1.0.4 | Apache-2.0 | glavna dependency closure | pubspec.lock:36; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/app_links_web-1.0.4/LICENSE:1`; [vir](https://pub.dev/packages/app_links_web/versions/1.0.4/license) |
| `archive` | 4.0.7 | MIT + LICENSE-other.md (glej ugotovitve) | glavna dependency closure | pubspec.lock:44; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/archive-4.0.7/LICENSE:1`; [vir](https://pub.dev/packages/archive/versions/4.0.7/license) |
| `args` | 2.7.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:52; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/args-2.7.0/LICENSE:1`; [vir](https://pub.dev/packages/args/versions/2.7.0/license) |
| `async` | 2.13.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:60; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/async-2.13.0/LICENSE:1`; [vir](https://pub.dev/packages/async/versions/2.13.0/license) |
| `boolean_selector` | 2.1.2 | BSD-3-Clause | samo dev | pubspec.lock:68; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/boolean_selector-2.1.2/LICENSE:1`; [vir](https://pub.dev/packages/boolean_selector/versions/2.1.2/license) |
| `characters` | 1.4.1 | BSD-3-Clause + Unicode License V3 (generirana runtime tabela; preveriti attribution) | glavna dependency closure | pubspec.lock:76; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/characters-1.4.1/LICENSE:1`; [vir](https://pub.dev/packages/characters/versions/1.4.1/license) |
| `checked_yaml` | 2.0.4 | BSD-3-Clause | samo dev | pubspec.lock:84; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/checked_yaml-2.0.4/LICENSE:1`; [vir](https://pub.dev/packages/checked_yaml/versions/2.0.4/license) |
| `cli_util` | 0.4.2 | BSD-3-Clause | samo dev | pubspec.lock:92; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/cli_util-0.4.2/LICENSE:1`; [vir](https://pub.dev/packages/cli_util/versions/0.4.2/license) |
| `clock` | 1.1.2 | Apache-2.0 | glavna dependency closure | pubspec.lock:100; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/clock-1.1.2/LICENSE:1`; [vir](https://pub.dev/packages/clock/versions/1.1.2/license) |
| `code_assets` | 2.1.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:108; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/code_assets-2.1.0/LICENSE:1`; [vir](https://pub.dev/packages/code_assets/versions/2.1.0/license) |
| `collection` | 1.19.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:116; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/collection-1.19.1/LICENSE:1`; [vir](https://pub.dev/packages/collection/versions/1.19.1/license) |
| `convert` | 3.1.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:124; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/convert-3.1.2/LICENSE:1`; [vir](https://pub.dev/packages/convert/versions/3.1.2/license) |
| `cross_file` | 0.3.5+2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:132; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/cross_file-0.3.5+2/LICENSE:1`; [vir](https://pub.dev/packages/cross_file/versions/0.3.5+2/license) |
| `crypto` | 3.0.7 | BSD-3-Clause | glavna dependency closure | pubspec.lock:140; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/crypto-3.0.7/LICENSE:1`; [vir](https://pub.dev/packages/crypto/versions/3.0.7/license) |
| `cryptography` | 2.9.0 | Apache-2.0 | glavna dependency closure | pubspec.lock:148; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/cryptography-2.9.0/LICENSE:1`; [vir](https://pub.dev/packages/cryptography/versions/2.9.0/license) |
| `cryptography_flutter` | 2.3.4 | Apache-2.0 | glavna dependency closure | pubspec.lock:156; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/cryptography_flutter-2.3.4/LICENSE:1`; [vir](https://pub.dev/packages/cryptography_flutter/versions/2.3.4/license) |
| `cupertino_icons` | 1.0.8 | MIT | glavna dependency closure | pubspec.lock:164; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.8/LICENSE:1`; [vir](https://pub.dev/packages/cupertino_icons/versions/1.0.8/license) |
| `dbus` | 0.7.12 | MPL-2.0 | glavna dependency closure | pubspec.lock:172; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/dbus-0.7.12/LICENSE:1`; [vir](https://pub.dev/packages/dbus/versions/0.7.12/license) |
| `drift` | 2.35.1 | MIT | glavna dependency closure | pubspec.lock:180; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/drift-2.35.1/LICENSE:1`; [vir](https://pub.dev/packages/drift/versions/2.35.1/license) |
| `equatable` | 2.1.0 | MIT | glavna dependency closure | pubspec.lock:188; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/equatable-2.1.0/LICENSE:1`; [vir](https://pub.dev/packages/equatable/versions/2.1.0/license) |
| `fake_async` | 1.3.3 | Apache-2.0 | samo dev | pubspec.lock:196; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/fake_async-1.3.3/LICENSE:1`; [vir](https://pub.dev/packages/fake_async/versions/1.3.3/license) |
| `ffi` | 2.1.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:204; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/ffi-2.1.5/LICENSE:1`; [vir](https://pub.dev/packages/ffi/versions/2.1.5/license) |
| `file` | 7.0.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:212; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/file-7.0.1/LICENSE:1`; [vir](https://pub.dev/packages/file/versions/7.0.1/license) |
| `file_picker` | 10.3.10 | MIT | glavna dependency closure | pubspec.lock:220; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/file_picker-10.3.10/LICENSE:1`; [vir](https://pub.dev/packages/file_picker/versions/10.3.10/license) |
| `firebase_core` | 4.15.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:228; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_core-4.15.0/LICENSE:1`; [vir](https://pub.dev/packages/firebase_core/versions/4.15.0/license) |
| `firebase_core_platform_interface` | 8.1.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:236; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_core_platform_interface-8.1.1/LICENSE:1`; [vir](https://pub.dev/packages/firebase_core_platform_interface/versions/8.1.1/license) |
| `firebase_core_web` | 3.12.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:244; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_core_web-3.12.0/LICENSE:1`; [vir](https://pub.dev/packages/firebase_core_web/versions/3.12.0/license) |
| `firebase_messaging` | 16.7.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:252; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_messaging-16.7.0/LICENSE:1`; [vir](https://pub.dev/packages/firebase_messaging/versions/16.7.0/license) |
| `firebase_messaging_platform_interface` | 4.10.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:260; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_messaging_platform_interface-4.10.0/LICENSE:1`; [vir](https://pub.dev/packages/firebase_messaging_platform_interface/versions/4.10.0/license) |
| `firebase_messaging_web` | 4.2.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:268; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/firebase_messaging_web-4.2.5/LICENSE:1`; [vir](https://pub.dev/packages/firebase_messaging_web/versions/4.2.5/license) |
| `fixnum` | 1.1.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:276; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/fixnum-1.1.1/LICENSE:1`; [vir](https://pub.dev/packages/fixnum/versions/1.1.1/license) |
| `flutter` | 0.0.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:284; `/Users/anzenovsak/Dev/flutter/packages/flutter/LICENSE:1`; [vir](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE) |
| `flutter_launcher_icons` | 0.14.4 | MIT | samo dev | pubspec.lock:289; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_launcher_icons-0.14.4/LICENSE:1`; [vir](https://pub.dev/packages/flutter_launcher_icons/versions/0.14.4/license) |
| `flutter_lints` | 5.0.0 | BSD-3-Clause | samo dev | pubspec.lock:297; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_lints-5.0.0/LICENSE:1`; [vir](https://pub.dev/packages/flutter_lints/versions/5.0.0/license) |
| `flutter_local_notifications` | 22.3.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:305; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_local_notifications-22.3.1/LICENSE:1`; [vir](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1/license) |
| `flutter_local_notifications_linux` | 8.0.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:313; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_local_notifications_linux-8.0.1/LICENSE:1`; [vir](https://pub.dev/packages/flutter_local_notifications_linux/versions/8.0.1/license) |
| `flutter_local_notifications_platform_interface` | 12.2.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:321; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_local_notifications_platform_interface-12.2.0/LICENSE:1`; [vir](https://pub.dev/packages/flutter_local_notifications_platform_interface/versions/12.2.0/license) |
| `flutter_local_notifications_web` | 1.0.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:329; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_local_notifications_web-1.0.0/LICENSE:1`; [vir](https://pub.dev/packages/flutter_local_notifications_web/versions/1.0.0/license) |
| `flutter_local_notifications_windows` | 3.1.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:337; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_local_notifications_windows-3.1.1/LICENSE:1`; [vir](https://pub.dev/packages/flutter_local_notifications_windows/versions/3.1.1/license) |
| `flutter_localizations` | 0.0.0 | Flutter SDK/inherited BSD-3-Clause | glavna dependency closure | pubspec.lock:345; `/Users/anzenovsak/Dev/flutter/LICENSE:1`; [vir](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE) |
| `flutter_plugin_android_lifecycle` | 2.0.33 | BSD-3-Clause | glavna dependency closure | pubspec.lock:350; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_plugin_android_lifecycle-2.0.33/LICENSE:1`; [vir](https://pub.dev/packages/flutter_plugin_android_lifecycle/versions/2.0.33/license) |
| `flutter_riverpod` | 2.6.1 | MIT | glavna dependency closure | pubspec.lock:358; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_riverpod-2.6.1/LICENSE:1`; [vir](https://pub.dev/packages/flutter_riverpod/versions/2.6.1/license) |
| `flutter_secure_storage` | 9.2.4 | BSD-3-Clause | glavna dependency closure | pubspec.lock:366; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage-9.2.4/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4/license) |
| `flutter_secure_storage_linux` | 1.2.3 | BSD-3-Clause | glavna dependency closure | pubspec.lock:374; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage_linux-1.2.3/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage_linux/versions/1.2.3/license) |
| `flutter_secure_storage_macos` | 3.1.3 | BSD-3-Clause | glavna dependency closure | pubspec.lock:382; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage_macos-3.1.3/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage_macos/versions/3.1.3/license) |
| `flutter_secure_storage_platform_interface` | 1.1.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:390; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage_platform_interface-1.1.2/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage_platform_interface/versions/1.1.2/license) |
| `flutter_secure_storage_web` | 1.2.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:398; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage_web-1.2.1/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage_web/versions/1.2.1/license) |
| `flutter_secure_storage_windows` | 3.1.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:406; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_secure_storage_windows-3.1.2/LICENSE:1`; [vir](https://pub.dev/packages/flutter_secure_storage_windows/versions/3.1.2/license) |
| `flutter_test` | 0.0.0 | Flutter SDK/inherited BSD-3-Clause | samo dev | pubspec.lock:414; `/Users/anzenovsak/Dev/flutter/LICENSE:1`; [vir](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE) |
| `flutter_timezone` | 5.1.0 | Apache-2.0 | glavna dependency closure | pubspec.lock:419; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/flutter_timezone-5.1.0/LICENSE:1`; [vir](https://pub.dev/packages/flutter_timezone/versions/5.1.0/license) |
| `flutter_web_plugins` | 0.0.0 | Flutter SDK/inherited BSD-3-Clause | glavna dependency closure | pubspec.lock:427; `/Users/anzenovsak/Dev/flutter/LICENSE:1`; [vir](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE) |
| `glob` | 2.2.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:432; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/glob-2.2.0/LICENSE:1`; [vir](https://pub.dev/packages/glob/versions/2.2.0/license) |
| `go_router` | 16.3.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:440; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/go_router-16.3.0/LICENSE:1`; [vir](https://pub.dev/packages/go_router/versions/16.3.0/license) |
| `gtk` | 2.2.0 | MPL-2.0 | glavna dependency closure | pubspec.lock:448; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/gtk-2.2.0/LICENSE:1`; [vir](https://pub.dev/packages/gtk/versions/2.2.0/license) |
| `hive` | 2.2.3 | Apache-2.0 | glavna dependency closure | pubspec.lock:456; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/hive-2.2.3/LICENSE:1`; [vir](https://pub.dev/packages/hive/versions/2.2.3/license) |
| `hive_flutter` | 1.1.0 | Apache-2.0 | glavna dependency closure | pubspec.lock:464; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/hive_flutter-1.1.0/LICENSE:1`; [vir](https://pub.dev/packages/hive_flutter/versions/1.1.0/license) |
| `hooks` | 2.2.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:472; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/hooks-2.2.0/LICENSE:1`; [vir](https://pub.dev/packages/hooks/versions/2.2.0/license) |
| `http` | 1.6.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:480; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/http-1.6.0/LICENSE:1`; [vir](https://pub.dev/packages/http/versions/1.6.0/license) |
| `http_parser` | 4.1.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:488; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/http_parser-4.1.2/LICENSE:1`; [vir](https://pub.dev/packages/http_parser/versions/4.1.2/license) |
| `image` | 4.7.2 | MIT + LICENSE-other.md (glej ugotovitve) | glavna dependency closure | pubspec.lock:496; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/image-4.7.2/LICENSE:1`; [vir](https://pub.dev/packages/image/versions/4.7.2/license) |
| `intl` | 0.20.3 | BSD-3-Clause | glavna dependency closure | pubspec.lock:504; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/intl-0.20.3/LICENSE:1`; [vir](https://pub.dev/packages/intl/versions/0.20.3/license) |
| `js` | 0.6.7 | BSD-3-Clause | glavna dependency closure | pubspec.lock:512; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/js-0.6.7/LICENSE:1`; [vir](https://pub.dev/packages/js/versions/0.6.7/license) |
| `json_annotation` | 4.10.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:520; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/json_annotation-4.10.0/LICENSE:1`; [vir](https://pub.dev/packages/json_annotation/versions/4.10.0/license) |
| `leak_tracker` | 11.0.2 | BSD-3-Clause | samo dev | pubspec.lock:528; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/leak_tracker-11.0.2/LICENSE:1`; [vir](https://pub.dev/packages/leak_tracker/versions/11.0.2/license) |
| `leak_tracker_flutter_testing` | 3.0.10 | BSD-3-Clause | samo dev | pubspec.lock:536; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/leak_tracker_flutter_testing-3.0.10/LICENSE:1`; [vir](https://pub.dev/packages/leak_tracker_flutter_testing/versions/3.0.10/license) |
| `leak_tracker_testing` | 3.0.2 | BSD-3-Clause | samo dev | pubspec.lock:544; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/leak_tracker_testing-3.0.2/LICENSE:1`; [vir](https://pub.dev/packages/leak_tracker_testing/versions/3.0.2/license) |
| `lints` | 5.1.1 | BSD-3-Clause | samo dev | pubspec.lock:552; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/lints-5.1.1/LICENSE:1`; [vir](https://pub.dev/packages/lints/versions/5.1.1/license) |
| `logging` | 1.3.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:560; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/logging-1.3.0/LICENSE:1`; [vir](https://pub.dev/packages/logging/versions/1.3.0/license) |
| `matcher` | 0.12.20 | BSD-3-Clause | samo dev | pubspec.lock:568; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/matcher-0.12.20/LICENSE:1`; [vir](https://pub.dev/packages/matcher/versions/0.12.20/license) |
| `material_color_utilities` | 0.13.0 | Apache-2.0 | glavna dependency closure | pubspec.lock:576; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/material_color_utilities-0.13.0/LICENSE:1`; [vir](https://pub.dev/packages/material_color_utilities/versions/0.13.0/license) |
| `meta` | 1.19.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:584; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/meta-1.19.0/LICENSE:1`; [vir](https://pub.dev/packages/meta/versions/1.19.0/license) |
| `mime` | 2.0.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:592; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/mime-2.0.0/LICENSE:1`; [vir](https://pub.dev/packages/mime/versions/2.0.0/license) |
| `native_toolchain_c` | 0.19.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:600; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/native_toolchain_c-0.19.5/LICENSE:1`; [vir](https://pub.dev/packages/native_toolchain_c/versions/0.19.5/license) |
| `path` | 1.9.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:608; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path-1.9.1/LICENSE:1`; [vir](https://pub.dev/packages/path/versions/1.9.1/license) |
| `path_provider` | 2.1.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:616; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider-2.1.5/LICENSE:1`; [vir](https://pub.dev/packages/path_provider/versions/2.1.5/license) |
| `path_provider_android` | 2.2.22 | BSD-3-Clause | glavna dependency closure | pubspec.lock:624; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider_android-2.2.22/LICENSE:1`; [vir](https://pub.dev/packages/path_provider_android/versions/2.2.22/license) |
| `path_provider_foundation` | 2.5.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:632; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider_foundation-2.5.1/LICENSE:1`; [vir](https://pub.dev/packages/path_provider_foundation/versions/2.5.1/license) |
| `path_provider_linux` | 2.2.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:640; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider_linux-2.2.1/LICENSE:1`; [vir](https://pub.dev/packages/path_provider_linux/versions/2.2.1/license) |
| `path_provider_platform_interface` | 2.1.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:648; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider_platform_interface-2.1.2/LICENSE:1`; [vir](https://pub.dev/packages/path_provider_platform_interface/versions/2.1.2/license) |
| `path_provider_windows` | 2.3.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:656; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/path_provider_windows-2.3.0/LICENSE:1`; [vir](https://pub.dev/packages/path_provider_windows/versions/2.3.0/license) |
| `petitparser` | 7.0.1 | MIT | glavna dependency closure | pubspec.lock:664; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/petitparser-7.0.1/LICENSE:1`; [vir](https://pub.dev/packages/petitparser/versions/7.0.1/license) |
| `platform` | 3.1.6 | BSD-3-Clause | glavna dependency closure | pubspec.lock:672; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/platform-3.1.6/LICENSE:1`; [vir](https://pub.dev/packages/platform/versions/3.1.6/license) |
| `plugin_platform_interface` | 2.1.8 | BSD-3-Clause | glavna dependency closure | pubspec.lock:680; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/plugin_platform_interface-2.1.8/LICENSE:1`; [vir](https://pub.dev/packages/plugin_platform_interface/versions/2.1.8/license) |
| `posix` | 6.0.3 | MIT | glavna dependency closure | pubspec.lock:688; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/posix-6.0.3/LICENSE:1`; [vir](https://pub.dev/packages/posix/versions/6.0.3/license) |
| `process` | 5.0.6 | BSD-3-Clause | glavna dependency closure | pubspec.lock:696; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/process-5.0.6/LICENSE:1`; [vir](https://pub.dev/packages/process/versions/5.0.6/license) |
| `pub_semver` | 2.2.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:704; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/pub_semver-2.2.1/LICENSE:1`; [vir](https://pub.dev/packages/pub_semver/versions/2.2.1/license) |
| `record_use` | 1.1.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:712; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/record_use-1.1.1/LICENSE:1`; [vir](https://pub.dev/packages/record_use/versions/1.1.1/license) |
| `riverpod` | 2.6.1 | MIT | glavna dependency closure | pubspec.lock:720; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/riverpod-2.6.1/LICENSE:1`; [vir](https://pub.dev/packages/riverpod/versions/2.6.1/license) |
| `screen_retriever` | 0.2.0 | MIT | glavna dependency closure | pubspec.lock:728; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/screen_retriever-0.2.0/LICENSE:1`; [vir](https://pub.dev/packages/screen_retriever/versions/0.2.0/license) |
| `screen_retriever_linux` | 0.2.0 | MIT | glavna dependency closure | pubspec.lock:736; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/screen_retriever_linux-0.2.0/LICENSE:1`; [vir](https://pub.dev/packages/screen_retriever_linux/versions/0.2.0/license) |
| `screen_retriever_macos` | 0.2.0 | MIT | glavna dependency closure | pubspec.lock:744; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/screen_retriever_macos-0.2.0/LICENSE:1`; [vir](https://pub.dev/packages/screen_retriever_macos/versions/0.2.0/license) |
| `screen_retriever_platform_interface` | 0.2.0 | MIT | glavna dependency closure | pubspec.lock:752; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/screen_retriever_platform_interface-0.2.0/LICENSE:1`; [vir](https://pub.dev/packages/screen_retriever_platform_interface/versions/0.2.0/license) |
| `screen_retriever_windows` | 0.2.0 | MIT | glavna dependency closure | pubspec.lock:760; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/screen_retriever_windows-0.2.0/LICENSE:1`; [vir](https://pub.dev/packages/screen_retriever_windows/versions/0.2.0/license) |
| `share_plus` | 11.1.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:768; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/share_plus-11.1.0/LICENSE:1`; [vir](https://pub.dev/packages/share_plus/versions/11.1.0/license) |
| `share_plus_platform_interface` | 6.1.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:776; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/share_plus_platform_interface-6.1.0/LICENSE:1`; [vir](https://pub.dev/packages/share_plus_platform_interface/versions/6.1.0/license) |
| `shared_preferences` | 2.5.4 | BSD-3-Clause | glavna dependency closure | pubspec.lock:784; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences-2.5.4/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences/versions/2.5.4/license) |
| `shared_preferences_android` | 2.4.20 | BSD-3-Clause | glavna dependency closure | pubspec.lock:792; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_android-2.4.20/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_android/versions/2.4.20/license) |
| `shared_preferences_foundation` | 2.5.6 | BSD-3-Clause | glavna dependency closure | pubspec.lock:800; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_foundation-2.5.6/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_foundation/versions/2.5.6/license) |
| `shared_preferences_linux` | 2.4.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:808; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_linux-2.4.1/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_linux/versions/2.4.1/license) |
| `shared_preferences_platform_interface` | 2.4.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:816; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_platform_interface-2.4.1/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_platform_interface/versions/2.4.1/license) |
| `shared_preferences_web` | 2.4.3 | BSD-3-Clause | glavna dependency closure | pubspec.lock:824; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_web-2.4.3/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_web/versions/2.4.3/license) |
| `shared_preferences_windows` | 2.4.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:832; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/shared_preferences_windows-2.4.1/LICENSE:1`; [vir](https://pub.dev/packages/shared_preferences_windows/versions/2.4.1/license) |
| `sky_engine` | 0.0.0 | mešan agregat engine/third-party (ni samo Apache) | glavna dependency closure | pubspec.lock:840; `/Users/anzenovsak/Dev/flutter/bin/cache/pkg/sky_engine/LICENSE:1`; [vir](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/LICENSE) |
| `source_span` | 1.10.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:845; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/source_span-1.10.2/LICENSE:1`; [vir](https://pub.dev/packages/source_span/versions/1.10.2/license) |
| `sqlite3` | 3.7.0 | MIT | glavna dependency closure | pubspec.lock:853; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/sqlite3-3.7.0/LICENSE:1`; [vir](https://pub.dev/packages/sqlite3/versions/3.7.0/license) |
| `stack_trace` | 1.12.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:861; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/stack_trace-1.12.1/LICENSE:1`; [vir](https://pub.dev/packages/stack_trace/versions/1.12.1/license) |
| `state_notifier` | 1.0.0 | MIT | glavna dependency closure | pubspec.lock:869; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/state_notifier-1.0.0/LICENSE:1`; [vir](https://pub.dev/packages/state_notifier/versions/1.0.0/license) |
| `stream_channel` | 2.1.4 | BSD-3-Clause | glavna dependency closure | pubspec.lock:877; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/stream_channel-2.1.4/LICENSE:1`; [vir](https://pub.dev/packages/stream_channel/versions/2.1.4/license) |
| `string_scanner` | 1.4.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:885; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/string_scanner-1.4.1/LICENSE:1`; [vir](https://pub.dev/packages/string_scanner/versions/1.4.1/license) |
| `term_glyph` | 1.2.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:893; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/term_glyph-1.2.2/LICENSE:1`; [vir](https://pub.dev/packages/term_glyph/versions/1.2.2/license) |
| `test_api` | 0.7.12 | BSD-3-Clause | samo dev | pubspec.lock:901; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/test_api-0.7.12/LICENSE:1`; [vir](https://pub.dev/packages/test_api/versions/0.7.12/license) |
| `timezone` | 0.11.1 | BSD-2-Clause | glavna dependency closure | pubspec.lock:909; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/timezone-0.11.1/LICENSE:1`; [vir](https://pub.dev/packages/timezone/versions/0.11.1/license) |
| `typed_data` | 1.4.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:917; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/typed_data-1.4.0/LICENSE:1`; [vir](https://pub.dev/packages/typed_data/versions/1.4.0/license) |
| `url_launcher` | 6.3.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:925; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher-6.3.2/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher/versions/6.3.2/license) |
| `url_launcher_android` | 6.3.28 | BSD-3-Clause | glavna dependency closure | pubspec.lock:933; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_android-6.3.28/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_android/versions/6.3.28/license) |
| `url_launcher_ios` | 6.3.6 | BSD-3-Clause | glavna dependency closure | pubspec.lock:941; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_ios-6.3.6/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_ios/versions/6.3.6/license) |
| `url_launcher_linux` | 3.2.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:949; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_linux-3.2.2/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_linux/versions/3.2.2/license) |
| `url_launcher_macos` | 3.2.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:957; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_macos-3.2.5/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_macos/versions/3.2.5/license) |
| `url_launcher_platform_interface` | 2.3.2 | BSD-3-Clause | glavna dependency closure | pubspec.lock:965; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_platform_interface-2.3.2/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_platform_interface/versions/2.3.2/license) |
| `url_launcher_web` | 2.4.1 | Apache-2.0 | glavna dependency closure | pubspec.lock:973; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_web-2.4.1/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_web/versions/2.4.1/license) |
| `url_launcher_windows` | 3.1.5 | BSD-3-Clause | glavna dependency closure | pubspec.lock:981; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/url_launcher_windows-3.1.5/LICENSE:1`; [vir](https://pub.dev/packages/url_launcher_windows/versions/3.1.5/license) |
| `uuid` | 4.5.2 | MIT | glavna dependency closure | pubspec.lock:989; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/uuid-4.5.2/LICENSE:1`; [vir](https://pub.dev/packages/uuid/versions/4.5.2/license) |
| `vector_math` | 2.4.3 | BSD-3-Clause | glavna dependency closure | pubspec.lock:997; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/vector_math-2.4.3/LICENSE:1`; [vir](https://pub.dev/packages/vector_math/versions/2.4.3/license) |
| `vm_service` | 15.0.2 | BSD-3-Clause | samo dev | pubspec.lock:1005; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/vm_service-15.0.2/LICENSE:1`; [vir](https://pub.dev/packages/vm_service/versions/15.0.2/license) |
| `web` | 1.1.1 | BSD-3-Clause | glavna dependency closure | pubspec.lock:1013; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/web-1.1.1/LICENSE:1`; [vir](https://pub.dev/packages/web/versions/1.1.1/license) |
| `win32` | 5.15.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:1021; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/win32-5.15.0/LICENSE:1`; [vir](https://pub.dev/packages/win32/versions/5.15.0/license) |
| `window_manager` | 0.4.3 | MIT | glavna dependency closure | pubspec.lock:1029; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/window_manager-0.4.3/LICENSE:1`; [vir](https://pub.dev/packages/window_manager/versions/0.4.3/license) |
| `xdg_directories` | 1.1.0 | BSD-3-Clause | glavna dependency closure | pubspec.lock:1037; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/xdg_directories-1.1.0/LICENSE:1`; [vir](https://pub.dev/packages/xdg_directories/versions/1.1.0/license) |
| `xml` | 6.6.1 | MIT | glavna dependency closure | pubspec.lock:1045; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/xml-6.6.1/LICENSE:1`; [vir](https://pub.dev/packages/xml/versions/6.6.1/license) |
| `yaml` | 3.1.3 | MIT | glavna dependency closure | pubspec.lock:1053; `/Users/anzenovsak/.pub-cache/hosted/pub.dev/yaml-3.1.3/LICENSE:1`; [vir](https://pub.dev/packages/yaml/versions/3.1.3/license) |
