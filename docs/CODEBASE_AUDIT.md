# Pregled stare aplikacije in smer nadaljnje gradnje

Datum: 4. oktober 2026. Izhodišče je commit `b2268d8793105f36ac085a39181be62dacdc28fe`; primerjava zajema tudi delovno vejo `codex/vsakdan-foundation`. Pregled vodi glavni agent s tremi podagenti GPT 6.1 Sol / high. Ugotovitve spodaj so iz kode, razen kjer je posebej naveden izveden preizkus. Napak stare aplikacije nismo reproducirali s spreminjanjem produkcijskih podatkov.

## Dogovor z uporabnikom

Gradnjo nadaljujemo. Ohranjanje starega vmesnika, lokalnega predpomnilnika in vseh starih načinov dela ni pogoj. Ključna zahteva je zajem vseh obstoječih strežniških podatkov v samostojen lokalni arhiv; šele nato lahko staro aplikacijo in projekte upokojimo. Arhiviranje ni avtomatska migracija v novi model. Stari projekti so lahko izhodišče novih zahtev in izbirnih predlog. Finance potrebujejo novo zasnovo.

## Kaj je bilo že spremenjeno

Primerjava Git ne kaže izbrisa nobene sledene izvorne datoteke. To ne pomeni, da je staro vedenje ostalo nespremenjeno: deli kode so že zamenjani oziroma odstranjeni. Izvirni commit ostaja dosegljiv v lokalni zgodovini; ob tem pregledu `HEAD`, `main` in lokalna referenca `origin/main` kažejo nanj. To ni novo preverjanje oddaljenega strežnika GitHub.

| Sprememba v delovni veji | Posledica |
| --- | --- |
| `app_router.dart`: začetna pot `/`, `/launch` preusmeri nanjo | Novi lokalni organizator je privzeti vstop; stari Kanboard je dosegljiv posebej. |
| `features/auth/connect_page.dart`, `credentials_transfer.dart` | Odstranjena izvoz/uvoz trajnih poverilnic prek QR/kode in rezervni poskus z globalnim `jsonrpc` uporabnikom. |
| `storage/credentials_store.dart`, `ai_settings_store.dart` | Ni več zapisovanja skrivnosti v SharedPreferences kot nadomestilo; stara kopija se čisti po preverjenem varnem zapisu. To je tudi sprememba obnašanja ob okvari Keychaina. |
| `storage/cache_store.dart`, `ai_chat_store.dart`, `ai_consent_store.dart` | Novi podatki so vezani na strežnik/račun. Stari skupni ključi ostanejo na disku, vendar niso avtomatsko pripisani prijavljenemu računu. Odjava briše novi obseg AI pogovorov; to ni le čiščenje obnovljivega predpomnilnika. |
| `kanboard/jsonrpc_client.dart` | HTTPS, omejene preusmeritve, brez dnevnikov s telesi zasebnih zahtev. Lokalni HTTP zahteva izrecno loopback izjemo. |
| `lib/organizer/`, `server/` | Dodana ločena lokalna osnova in razvojni FamilyHub. Ne migrirata starega strežnika ali njegovih financ. |
| Platformni projekti in odvisnosti | Uskladitev gradenj s Flutter SDK, iOS 15/macOS 12, Android Gradle; podrobnosti v načrtu. Uporabnikova različica `1.0.12+12` ostaja. |

## Obseg pregleda

Izvirnik ima 37 ročno pisanih Dart datotek v `lib/`, skupaj 17.840 vrstic brez generiranih prevodov. Največje datoteke v izvirniku so `task_details_page.dart` (2.610), `projects_page.dart` (2.069), `project_finance_table_page.dart` (2.052), `kanboard_api.dart` (1.834), `board_page.dart` (1.794) in `project_ai_chat_page.dart` (1.376).

Pregledani so zasloni in njihove poti nalaganja/zapisovanja, modela Kanboard/finance, API in transport, vse shrambe/providerji, `lib/ai/`, skupni widgeti, zagon/router, obstoječi testi ter nova domena/podatki/stanje/prikaz. Pregled platform vključuje Gradle/manifeste, Apple projekte/plist/entitlements, web ter ogrodji Windows/Linux. Generirane lokalizacije in registratorji vtičnikov so obravnavani kot generirani izdelki; niso samostojna poslovna logika. Pregled vključuje tudi FamilyHub in njegovo testno okolje.

Velikost datotek sama ne dokazuje napake. Težava je, da isti zasloni hkrati odločajo o identiteti, obravnavajo delne omrežne rezultate, spreminjajo poslovne podatke in sestavljajo UI. Spodnji primeri pokažejo konkretne posledice.

## Ugotovitve z največjim vplivom

P1 pomeni nevarnost izgube, podvajanja ali napačne razlage uporabniških podatkov; P2 pomeni pomembno omejitev pravilnosti oziroma nove zasnove. Vrstice se nanašajo na delovno kodo ob pregledu; kjer piše »staro in novo«, je relevantna pot prisotna tudi v izvirnem commitu.

| Prednost | Ugotovitev in dokaz | Odločitev za prenovo |
| --- | --- | --- |
| P1 | Staro in novo: finance so cel JSON v razrezanih projektnih metapodatkih. `kanboard_api.dart:262` ob manjkajočem delu vrne `null`; dekodiranje prav tako ne razlikuje pokvarjenega od praznega zapisa. Zapis/čiščenje pri `:309` in naprej nimata preverjanja revizije. | Arhiv hrani izvirne metapodatke in dele. Nove finance imajo posamezne zapise, transakcije in revizije. |
| P1 | `project_finance_table_page.dart:123` manjkajoči oziroma neberljivi finančni zapis razume kot prazno tabelo. Pri `:529` odgovor starejšega shranjevanja ponovno nastavi `_data`; vmesne spremembe se lahko izgubijo. | Branje razlikuje odsotnost, napako in nepodprto različico. Potrjen zapis ne sme zamenjati novejšega osnutka. |
| P1 | Staro in novo: `FinanceTableData.fromJson` (`finance_models.dart:260`) ignorira nepoznana polja, ne preveri podprte različice in zneske ob neuspelem razčlenjevanju spremeni v 0 (`:340`). | Arhiva ne izdelujemo s pretvorbo skozi te modele; ohranimo izvirnik in posebej poročamo o napakah. |
| P1 | Staro in novo: v `task_details_page.dart:180` je način ustvarjanja odvisen le od vhodnega widgeta. Delni save nove naloge pri `:548` nastavi `_loadedTask` (`:588`), ne spremeni pa tega pogoja. Naslednji save lahko spet ustvari nalogo. Delni neuspeh ustvarjanja nakupovalnih podnalog lahko prav tako pusti že ustvarjenega starša. | Novi ukazi imajo stabilen lokalni ID in ponovljivo izvedbo. Ne prenesemo starega flowa dobesedno. |
| P1 | Staro in novo: neuspešno nalaganje dodeljivih uporabnikov postane prazen seznam (`task_details_page.dart:224`), nato se `_ownerId` počisti (`:290`). Poznejši običajni save pošlje `ownerId: 0` (`:503`). | Napaka nalaganja ne sme spreminjati lastništva. Ločimo »neznano«, »ni naloženo« in uporabnikovo izrecno odstranitev. |
| P1 | Staro in novo: shranjevanje privzete valute v `project_defaults_page.dart:91–107` prepiše valuto vseh dostopnih projektov, zneske pa pusti enake. Operacija je zaporedna in brez skupne transakcije. | Privzeta nastavitev velja za nove zapise; konverzija obstoječih zneskov mora biti ločen izrecen postopek. |
| P1 | Stara projekcija vleče stroške le iz uporabniku dostopnih projektov, preskoči napake tabel in njihov `score` prišteje brez preverjanja izvorne valute (`project_finance_table_page.dart:1316–1383`, `:1490–1511`). | Projekcija mora imeti določen obseg, valuto, datum in podatek o popolnosti; dva uporabnika ne smeta dobiti različnih navidezno popolnih skupnih bilanc. |
| P1 | Stare poti urejanja nimajo povsod vezave na identiteto začetne operacije. `task_details_page.dart:210–309` po omrežju spreminja controllerje pred preverjanjem `mounted`; shranjevanje ponovno bere aktualni API. | Repository/ukaz mora zajeti identiteto in objekt; iztek ali menjava računa ustavi staro operacijo. Popravka seznamov in AI pogovora še ne pokrivata vseh starih zaslonov. |
| P1 | Predpomnilnik in API seznam projektov nista arhiv. Typed modeli ne ohranijo vseh polj; tabla ni seznam vse zgodovine in zaprtih nalog. | Zajamemo bazo in datoteke, nato ustvarimo ločen brskalnik iz lokalne obnovljene kopije. |
| P2 | Stara projektna stroška uporabljata `task.score`, nakupi podnaloge/oznake, ročno vpisane ure skrito podnalogo. `kanboard_api.dart:952` združuje več zapisov brez transakcije. | Ti pomeni se ohranijo v arhivu, nove finance/nakupi/čas pa dobijo namenske entitete. |
| P2 | Staro premikanje strukture in nalog uporablja zaporedne RPC ter ponekod prezre vrnjen `false`; npr. `board_page.dart:298` in `board_structure_page.dart:265`. | Premik je domenski ukaz s preverjenim rezultatom, urejanjem vrstnega reda in obravnavo konflikta. |
| P2 | AI politika v projektu govori o lastnikovem ključu/strošku, dejanski `openai_local_ai_provider.dart:23–43` pa uporablja lokalni ključ iz nastavitev. UI privolitev ni izveden strežniški plačnik. | AI ostane izbiren; najprej jasna identiteta plačnika in nabor podatkov, nato funkcije. Starega lastniškega protokola ne predstavljamo kot dokončanega. |
| P2 | AI predlogi lahko uporabijo ID naloge ali prvo ujemanje naslova; izbrani stolpec ni povsod preverjen proti ciljnemu projektu (`project_ai_chat_page.dart:813–892`). | Pred potrditvijo razrešimo konkretne cilje, preverimo projekt in pravice; ne enačimo potrjenega besedila predloga s pravilnim ukazom. |
| P2 | Odpiranje priponk uporablja začasne datoteke (`attachment_share.dart:55`) in ni trajen prenos z dokazom celovitosti. | Arhiv hrani vse bajte, velikost, izvor in SHA256. Nova aplikacija posebej vodi dosegljivost priponk brez povezave. |

## Tudi nova osnova potrebuje nadaljnje delo

- Ločitev `organizer/domain`, `data`, `state`, `presentation` je uporabna. Lokalni ID-ji, celoštevilski zneski in jasno zavrnjen zastarel zapis so primerna izhodišča.
- Ena vrednost Hive s celotnim stanjem je omejena osebna shramba, ne končna rešitev za deljeno urejanje. Serializacija velja znotraj ene repository instance; ni izmenjave med zavihki/napravami, odhodne vrste ali strežniških revizij. Pred sodelovanjem potrebujemo transakcije po zapisih in evidenco sprememb.
- Trenutni uvoz zavrne vsak že obstoječ ID. Primeren je za prazno zbirko ali nepovezane podatke, ne za obnovo že uporabljane zbirke na izbrani trenutek. Semantiki »uvoz« in »obnova« morata biti ločeni.
- Novi `FinanceEntry` ni nadomestilo za star model s prispevajočimi osebami, začetnim saldom, ročnimi mesečnimi prihodki, ponavljajočimi pravili in načrti. Arhiv ostane semantično zvest izvirniku; novi model se določi posebej.
- »Osebno/dom« je trenutno kategorija projekta, ne gospodinjstvo z lastništvom in pravicami. Družinske sinhronizacije še ni.
- Urejevalnik dogodka ohrani uvoženi `endsAt`, nima pa polja za urejanje konca (`organizer_actions.dart:94`). Premik začetka čez konec je pravilno zavrnjen, vendar UI še nima poti do popravka.
- Dialogi še nimajo enotnega opozorila o zavrženem osnutku; napaka časovnega osveževanja opomnikov ni prikazana v shellu. Globoke povezave, stanje koledarja med zavihki in velike zbirke zahtevajo nadaljnjo obravnavo.
- FamilyHub preverja protokol in pravice razvojnih povabil. Ni že izdelana registracija, sinhronizacija ali arhivski backend; v paketu so povabila privzeto izključena. Za zajem starega strežnika ga ne potrebujemo in ga nismo namestili.
- Varna shramba je izboljšana, vendar so njene operacije read/save/clear še brez skupne serializacije. Pred novimi sejami naprav določimo obravnavo sočasne prijave/odjave in preverimo Keychain na podpisanih napravah. Pri transportu posebej preverimo ponavljanje mutacij po preusmeritvi, ne le zaupanje ciljnemu izvoru.

## Kaj ponovno uporabimo

| Del | Smer |
| --- | --- |
| Flutter, Riverpod, GoRouter, ARB lokalizacija, potrjen videz | Nadaljujemo; izboljšujemo meje odgovornosti in navigacijo. |
| Nova lokalna domena in vmesnik | Razvojno izhodišče; podatkovno shrambo pripravimo za transakcije in sync, ko določimo pogodbo. |
| Stari čisti finančni izračuni in testi | Referenca za razumevanje stare projekcije in regresijske primere, ne avtomatska specifikacija novih financ. |
| Stari zasloni in adapterji | Vir zahtev in arhivske razlage; ne ohranjamo jih zaradi združljivosti za vsako ceno. |
| Kanboardovo jedro | Kandidat za naloge/projekte/identitete. Obstoječe funkcije uporabimo skozi adapter; omejitve nove domene rešuje lasten modul. |
| FamilyHub | Ločeni moduli za prijavo/povabila, pravice, sinhronizacijo, nove finance in obvestila. Brez prenosa poslovnih pravil nazaj v velik Flutter zaslon. |

Nova finančna zasnova naj loči dejanske knjižbe, račune in začetna stanja od načrtov ter pravil ponavljanja. Projektna povezava ni dovoljenje za zasebni proračun. Valuta je del zapisa; ponovljena zahteva ne podvoji stroška, konflikt pa ne prepiše tiho drugega člana. To so tehnična merila naslednje izvedbe, ne že izdelane funkcije.

## Meje preverjanja

Prejšnja izvedba je opravila 78 Flutter testov, gradnje web/macOS/iOS simulator/Android debug in 81 strežniških preverjanj na vsaki od SQLite/MySQL. To ne potrjuje vseh starih CRUD poti, obnašanja produkcijskih uporabniških vlog, podpisanega Keychaina ali Windows/Linux. Izvirna testna osnova je bila predvsem štiri teste finančne projekcije in začetni widget.

Med tem pregledom je podagent ponovno izvedel finančni in novi podatkovni sklop: **23/23 uspešnih** (4 stare projekcije in 19 novih podatkovnih testov). Uspeh teh testov ne izpodbije zgoraj ugotovljenih nepokritih poti autosave, sočasnih strežniških zapisov ali sprememb valute.

Ta pregled ni razlog za ponavljanje vseh istih buildov brez sprememb aplikacijske kode. Novi arhivski izvoz in prikaz dobita lastne preizkuse celovitosti, napak in nezaupanja vredne vsebine; rezultate dejanskega zajema vodi dokumentacija arhiva.
