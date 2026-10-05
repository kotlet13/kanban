# Prenova osebnega in družinskega organizatorja

Dokument vodi izvedbo, odločitve, preverjanja in odprto delo. Uporabnik je 4. oktobra 2026 odobril začetek gradnje ter vzporedni razvoj telefona in namizja. Glavni agent orkestrira; izvedbo opravljajo podagenti GPT 6.1 Sol / high. Ta dokument ne pomeni, da so vse spodaj opisane funkcije že izdelane.

**Aktualna usmeritev, pozneje 4. oktobra 2026:** uporabnik je po zahtevi za pregled pojasnil, da želi nadaljevati gradnjo in je z začetkom zadovoljen. Pregled stare kode in dosedanjih sprememb usmerja razvoj, ne ustavlja novih funkcij. Ohranitev starih lokalnih podatkov aplikacije ni pogoj; bistveno je iz strežnika zajeti vse obstoječe podatke kot preverjen lokalni arhiv s samostojnim brskalnikom. Staro aplikacijo in projekte lahko nato upokojimo. Obstoječi projekti so izhodišče za razumevanje potreb in morebiten izbrani prenos, ne obvezna živa združljivost. Finance ponovno zasnujemo. Spodnje izdelane etape so zapis dosedanjega razvoja, prihodnje etape pa se po ugotovitvah prilagodijo.

## Potrjena smer

- Osrednja aplikacija za osebne načrte, prosti čas, dom, družino, projekte, nakupovanje in finance.
- Osnovno ustvarjanje, branje in urejanje deluje brez strežnika in računa ter preživi ponovni zagon. Račun je namenjen izbirnemu sodelovanju in povezovanju naprav.
- Uporabnik naj se registrira, prijavi in sprejme povabilo v aplikaciji. Predhodna prijava v spletni Kanboard ni del želenega toka.
- Družinsko članstvo in sodelovanje pri posameznem projektu sta ločena obsega. Finance so lahko osebne, skupne za dom ali del projekta, ki je namenoma zasnovan s skupnimi financami. Dostop do takega modula določa finančna politika doma/projekta; zunanji projektni sodelavec ne dobi zasebnega družinskega pregleda. To dopolnitev je uporabnik izrecno potrdil med izvedbo deljenja.
- Obvestila ostanejo v aplikaciji in vključujejo dogajanje v skupnem prostoru tudi brez osebne dodelitve. Osebno naslovljena obvestila so jasno označena. Nakupovalne spremembe so vidne in se lahko združijo; zvok, push in e-pošta imajo ločene nastavitve. Posamezni nakupovalni vnosi privzeto ne pošiljajo e-pošte. Dostava na telefon in sistemski opomniki se preverjajo ločeno od prikaza v aplikaciji.
- Mobilni in namizni vmesnik nastajata hkrati. Skupni so domena, lokalna shramba, sinhronizacija in preverjanje pravic.
- Obstoječe Kanboardove projekte, povezave in finančne podatke ohranimo v preverljivem lokalnem arhivu, dostopnem brez starega strežnika. Izvirnikov ne brišemo samodejno. Morebitno nadaljevanje izbranega projekta v novem modelu je ločen postopek.

## Oblikovanje in navigacija

Potrjen je mobilni koncept »Vsakdan«. Ime ostaja delovno. Svetla tema uporablja belo in svetlo sivo, grafitno besedilo in moder poudarek `#365BD9`; temna tema ohrani isto hierarhijo in berljivost. Nastavitev teme ne zahteva računa.

| Telefon | Namen | Namizna prilagoditev |
| --- | --- | --- |
| Danes | Naslednji dogovor, naslednja pomembna opravila, bližnjica do nakupov | Pregled v več stolpcih, brez dolgega ponavljanja vsega |
| Načrti | Prihajajoča opravila in dogodki ter projekti | Prostor za seznam in podrobnosti, koledar kot razvijajoč se pogled |
| Nakupi | Neposredno dodajanje in odkljukavanje, več seznamov | Isti podatki in dejanja z več prostora |
| Več | Finance, dom, nastavitve, povezava in deljenje | Področja neposredno v levem meniju |

Na telefonu ne postavljamo šestih velikih ploščic pred dejansko vsebino. Obseg podatkov označimo ob vsebini; preklop prostora ni obvezna ovira pred vsakim dejanjem. Na projektu imajo prednost naslednji koraki, ostale podrobnosti so dosegljive postopoma. Prazna aplikacija kaže prazna stanja in dejanja za začetek, ne predstavitvenih finančnih zneskov ali izmišljenih družinskih članov.

## Etape in merila

Trenutna odobrena izvedba dodelitev, skupnega dnevnega pregleda, obvestil, sistemskih opomnikov in financ se vodi v [mejniku družinske nadgradnje](FAMILY_UPGRADE.md). Ta loči novo delo in njegove dokaze od že zaključenega prvega deljenja.

Po arhiviranju je izdelano in lokalno preverjeno [prvo uporabno deljenje med dvema osebama](SHARING_MILESTONE.md). Vključuje račune in povabila v aplikaciji, skupne nakupovalne sezname/osnovna opravila ter transakcijsko lokalno hrambo in sinhronizacijo. Dokument mejnika loči dokaze te etape od preostalih nalog B/C in produkcijske izdaje.

### Potrjena dopolnitev: skupne finance ter obvestila in opomniki

Uporabnik je po pregledu deljenja 4. oktobra 2026 potrdil spodnjo finančno zasnovo in ponovno izrecno zahteval obvestila ter opomnike v aplikaciji. Njihova aktualna izvedba in dokazi so v [družinskem mejniku](FAMILY_UPGRADE.md); spodaj ostaja zapis zahtev. Etapa D je obvezni del uporabne družinske različice; finančna prenova je ne sme odriniti na nedoločen čas. Pri novih modulih se že v podatkovni pogodbi določijo dogodki, roki in prejemniki, da jih lahko povežemo z enim skupnim sistemom obvestil.

- Skupni člani s finančnimi pravicami lahko ustvarjajo prihodke in stroške doma oziroma finančnega obsega projekta. Posamezen zapis loči plačnika/prejemnika, finančni račun in uporabnika, ki ga je vnesel. Tabela pokaže datum, opis, vrsto, znesek z valuto, kategorijo ter te osebe/račun; po potrebi tudi projekt. Omogoči pregled vseh zapisov ter filtre po članu in računu.
- Osebni finančni zapisi se vključijo samo z izrecno izbiro. Pravice do pregleda in urejanja skupnih financ se določijo posebej. Spremembe imajo sled, kdo in kdaj jih je opravil; popravek ne prepiše izvirnega avtorstva vnosa.
- Prenos med osebnim in skupnim računom je prenos, ne nov prihodek ali strošek v skupnem seštevku. Denarni tok in prispevek posameznika sta različna pregleda; isti dogodek se ne sme šteti dvakrat.
- Obvestilo o sodelovanju (npr. povabilo ali dodelitev opravila) in časovni opomnik (rok opravila, dogodek ali načrtovano plačilo) sta ločena zapisa oziroma razloga za prikaz. Skupni center v aplikaciji pokaže neprebrano stanje in odpre pravo vsebino; pogled Danes izpostavi bližnje roke.
- Predlagana dejanja opomnika so odložitev, sprememba časa in odpiranje izvornega zapisa. Označitev obvestila kot prebranega sama ne zaključi opravila in ne pomeni, da je račun plačan.
- Osebni opomniki za lokalne podatke morajo delovati brez strežnika. Obvestila o dejanjih drugih članov prispejo ob povezavi; kasnejša uskladitev jih ne podvaja. Zaključitev, izbris ali sprememba roka posodobi oziroma prekliče zastarel opomnik.
- Dodani artikli in novi nakupovalni seznami ustvarijo vidno obvestilo o skupnem dogajanju; več povezanih dodatkov se lahko združi. Uporabnik ločeno izbira zvok, push in e-pošto po vrsti dogodka in prostoru; e-pošta ni kopija vsake spremembe ali vsakega vnosa stroška. Finančna vsebina in prejemniki upoštevajo finančne pravice, tudi ob odprtju starega obvestila.

Družinska nadgradnja vključuje skupni center, lokalno sistemsko razporejanje in SMTP vrsto. Uporabnik je 5. oktobra 2026 potrdil pripravo FCM na paketu Spark; izvedbo in dokaze vodi [FCM mejnik](FIREBASE_PREPARATION.md). Produkcijska konfiguracija dostave ter fizični mobilni preizkus ostajata odprta. Prikaz v aplikaciji, obvestilo na telefonu in e-poštna dostava imajo vsak svoj dokaz delovanja v [mejniku](FAMILY_UPGRADE.md).

### Dopolnitev uporabnika: skupno dogajanje in osebno naslovljena obvestila

Uporabnik je dodatno določil, da mora član vedeti, kaj se dogaja v gospodinjstvu ali projektu, tudi če mu opravilo ni dodeljeno. Razlog obvestila določa besedilo in oznako; nujnost, zvok ter dostavni kanal so ločene nastavitve. Predlagani oznaki oziroma filtra sta **Zame** in **V skupnem prostoru**; razliko označimo z besedilom/ikono, ne samo z barvo.

| Dogodek | Namen obvestila in primer | Cilj ob kliku |
| --- | --- | --- |
| Novo opravilo v skupnem projektu | Skupno dogajanje: »V Mansardo je dodano opravilo Izmera oken.« Prejemnik ni nujno izvajalec. | To opravilo v pravem projektu |
| Opravilo dodeljeno prejemniku | Osebno: »Dodeljeno ti je opravilo Izmera oken.« | Dodeljeno opravilo |
| Več novih dodelitev | Osebno, združeno: »Dodeljena so ti 3 opravila v Mansardi.« | Seznam konkretnih opravil iz obvestila, ne začetni zaslon ali nepovezana opravila |
| Nov nakupovalni seznam | Skupno dogajanje: »Dodan je seznam za vikend.« | Novi seznam |
| Dodani artikli | Skupno dogajanje: »V tedenski nakup so dodani 4 izdelki.« | Zadevni seznam s poudarjenimi dodatki |
| Dnevni pregled gospodinjstva | Skupno dogajanje: kdo ima danes kateri skupno vidni dogodek/opravilo in ob kateri uri | Dnevni pregled oziroma izbrani dogodek |
| Projektni plan ali rok | Skupno dogajanje: kdo dela kaj in kdaj; nov ali premaknjen termin oziroma rok. Prizadeti izvajalec dobi osebno različico. | Projektna časovnica ali konkretno opravilo z rokom |

Obseg načrtovane izvedbe:

- Prejemnike dogodka določajo članstvo, dostop do vsebine in nastavitve sledenja prostoru; niso omejeni na dodeljene izvajalce. Zasebni koledarski ali finančni zapisi se ne vključijo v pregled gospodinjstva samo zaradi članstva. Predlagani privzeti način ne ustvarja opozoril uporabniku za njegovo lastno dejanje; skupna zgodovina dejanje še vedno pokaže.
- En dogodek se za istega prejemnika ne podvoji kot »dodano« in »dodeljeno tebi«. Če nastaneta skupaj, izvajalec vidi osebno različico, ostali člani obvestilo o skupnem dogajanju. Poznejša samostojna dodelitev je nov dogodek.
- Več povezanih sprememb se lahko združi po prostoru, razlogu in kratkem časovnem obdobju, pri tem pa se ohrani nabor izvornih zapisov. Osebne dodelitve se ne izgubijo med splošnimi nakupovalnimi posodobitvami. Trenutni izvedbeni interval združevanja je pet minut.
- Klik iz centra obvestil ali telefonskega obvestila odpre isti konkretni cilj, tudi ob zaprti aplikaciji oziroma po potrebni prijavi. Pred odprtjem preveri pravi račun, prostor in trenutne pravice; izbrisana ali nedostopna vsebina dobi razumljivo stanje. Potrditev odprtja/prebranega ne zaključi opravila. Stanje prebranega je osebno in se za povezani račun uskladi med napravami.
- Gospodinjstvo potrebuje skupen dnevni pregled, projekt pa pregled rokov in časovnico izvajalcev. Obvestila vodijo v te poglede; ne nadomeščajo jih. Dodelitve, skupno vidni dogodki in termini so vključeni v sync2 pogodbo; v1 odjemalec ne sme prepisati novih polj.
- Preizkusi morajo vključiti nedodeljenega člana, osebno dodelitev ob nastanku in pozneje, skupino več dodelitev, nov seznam/artikle, dnevni pregled drugih članov, spremembo projektnega termina, odpiranje iz zaprte aplikacije, izgubljeno povezavo in ponovitev brez dvojnikov ter odvzem pravic pred odprtjem. Dokazi mobilne dostave in odpiranja na iOS/Android so pogoj, da telefonska obvestila predstavimo kot delujoča.

### Vzporedno z nadaljnjo gradnjo — pregled, arhiv in nova podatkovna zasnova

- Primerjava izvirnega commita `b2268d8793105f36ac085a39181be62dacdc28fe` z delovno vejo; popis dejansko odstranjenih ali spremenjenih vedenj, ne samo datotek.
- Pregled aplikacijske kode, poslovnih pravil, API, hrambe, platformnih nastavitev in testov. Kritično pregledamo tudi novo lokalno osnovo in FamilyHub.
- Za vsak modul odločitev: ponovno uporabiti, prilagoditi, zamenjati ali ohraniti le kot arhivski adapter. Dolžina datoteke sama ni razlog za prepis.
- Načrt popolnega zajema starega sistema: varnostna kopija za obnovo in prenosljiv arhiv za branje sta različna izdelka. Finance ohranimo tudi v izvirnem formatu.
- Lokalni arhivski brskalnik: projekti, naloge, komentarji, podnaloge, datoteke, povezave in finančni pogled; nepopolna ali nerazumljena vsebina mora ostati označena in dostopna v izvirni obliki.
- Nova finančna domena, lokalne transakcije, pravice in pogodba izbirnega strežnika se določijo pred nadaljnjo gradnjo.
- Poslovnih podatkov in konfiguracije produkcije v tem koraku ne spreminjamo. Celotna kopija je že izdelana, prenesena in obnovljena lokalno; preverjen je arhiv 48 tabel/2.180 vrstic ter 8 priponk. [Postopek in meje](LEGACY_ARCHIVE.md). Upokojitev še ni izvedena.

### A — uporabna lokalna osnova (izdelana v razvojni veji)

- Zagon brez računa in omrežja; nov organizator je začetni zaslon.
- Trajni projekti, opravila in roki, nakupovalni seznami in artikli, dogodki ter posamezni prihodki/odhodki.
- Dnevni in prihajajoči pregled bere dejanske lokalne podatke; preklop mobilne/namizne postavitve ne izgubi stanja.
- Finančni zneski so v najmanjših denarnih enotah skupaj z valuto.
- Izvoz in preverjen uvoz varnostne kopije ne potrebujeta strežnika in ne prepišeta obstoječih drugačnih zapisov brez opozorila.
- Napaka trajnega zapisa ne sme biti predstavljena kot uspeh. Preizkusi pokrijejo restart, sočasna lokalna dejanja, zavrnjen zapis in neveljaven uvoz.
- Obstoječi Kanboard ostane izrecno dostopen. Novi lokalni podatki niso samodejno sinhronizirani ali javno deljeni.
- Obstoječe ranljivosti shranjevanja poverilnic, preusmeritev in beleženja obravnavamo pred razširitvijo povezovanja računov.

### B — strežniška pogodba, računi in povabila

- Izoliran lokalni Docker s pripeto različico Kanboarda in lastnim vtičnikom; testni podatki so sintetični.
- Različica API-ja in dejanski seznam podprtih zmožnosti. Nepodprte funkcije vračajo jasen rezultat, ne lažnega uspeha.
- Povabila v projekt: preverjanje ustvarjalčevih pravic, časovna omejitev, preklic, enkratna poraba, shranjevanje samo zgoščene skrivnosti, transakcijsko sprejemanje.
- Ločena zasnova gospodinjstev in pravic do novih modulov. Testi preverijo dostop dovoljene in prepovedane osebe na vsaki poti.
- Registracija iz aplikacije, prijava, obnova dostopa in preklicljive seje naprav; ohranjena 2FA in omejevanje poskusov. Izbira javne registracije ali registracije prek povabila ostane produktna odločitev; varna začetna smer je povabilo.
- Dokaz, da novi žeton predstavlja dejanskega uporabnika in ne globalnega `jsonrpc` skrbniškega dostopa.
- Paket ZIP za cPanel brez obveznega SSH ali stalnega procesa. Produkcijska namestitev je ločen korak po pregledu in odobritvi.

### C — sinhronizacija novega sistema in izbirni prevzem iz arhiva

- Povezava lokalnih identifikatorjev s strežniškimi; različice zapisov, evidenca sprememb in izbrisov, ponovljive zahteve.
- Lokalni zapis in odhodna sprememba sta atomarna, kadar je sinhronizacija vključena. Osebni način brez strežnika ne proizvaja neskončne vrste za neobstoječo povezavo.
- Dve napravi, offline urejanje in reconnect: neodvisne spremembe ostanejo, konflikt na istem zapisu je jasno obravnavan.
- Preverjena odpoved dostopa med delom brez povezave. Zajem sprememb iz Kanboardovega spletnega vmesnika je potreben le za objekte, ki jih bo dovoljeno urejati tudi tam; starega vmesnika ne ohranjamo samodejno kot drugi urejevalnik vseh novih modulov.
- Izbirno nadaljevanje izbranih arhiviranih projektov v novem modelu, s sledjo izvora in brez dvojnikov. Samostojen arhiv ostane nespremenjen. Finančnih pravil ne pretvarjamo v preprost seznam transakcij brez dokazane semantične skladnosti.
- Načrt priponk in lokalne zaščite baze, časovnih pasov ter migracij pred širšo uporabo z zasebnimi podatki.

### D — obvestila in družinska vsakodnevna uporaba

- Trajen osebni seznam obvestil z označevanjem prebranega in odpiranjem prave vsebine; ločena osebna dodelitev in dogajanje v skupnem prostoru, tudi za nedodeljene člane. Združevanje povezanih dogodkov brez izgube osebnih dodelitev.
- Skupen dnevni pregled gospodinjstva ter projektni roki/časovnica z izvajalci; obvestila odpirajo konkretni zapis ali ustrezni filtrirani pogled.
- Lokalni opomniki z dejanskim sistemskim razporejanjem; testi dovoljenj, ponovnega zagona in časovnega pasu.
- Strežniški prejemniki na podlagi pravic in nastavitev prostora; SMTP, izbirni povzetki, ponovitve brez podvajanja. Nakupovalne spremembe so vidne v aplikaciji, e-pošta za posamezni artikel je privzeto izključena.
- Potisna obvestila za iOS/Android z ločeno preverjeno dostavo in odpiranjem konkretne vsebine ob zaprti aplikaciji; kanal in zvok sta nastavljiva. Izbran je Firebase Cloud Messaging na paketu Spark; podatki in avtentikacija ostanejo lokalno oziroma v FamilyHub. Firebase projekt uporabnik ustvari pozneje.

### E — stabilizacija in izdaja

- Testi najpomembnejših tokov, migracij, pravic in varnostnih kopij.
- Vizualen in funkcionalen pregled telefona, tablice ter namizja v obeh temah in jezikih.
- Podpisane mobilne gradnje, dovoljenja in pravilne nastavitve trgovin; App Store in Play objava sta ločena od lokalne gradnje.
- Matrika dejansko preverjenih platform; uspešen spletni build sam po sebi ne potrdi vseh native pluginov.

## Tehnične meje prve izvedbe

Ohranimo Flutter, Riverpod, GoRouter in lokalizacijo. Stari izračuni so referenca za razumevanje arhiva; o ponovni uporabi odločajo ugotovitve pregleda. Nova domena je ločena v `lib/organizer/{domain,data,state,presentation}`. Obstoječi `lib/features` ter `lib/kanboard` sta trenutno še dostopna, vendar njuna trajna ohranitev ni pogoj prenove.

Prva osebna etapa je uporabljala Hive v ločeni shrambi: lokalni ID-ji in atomarno zamenjana vrednost s celotnim osebnim stanjem. Omejitev je bilo ponovno zapisovanje celotnega stanja. Skupne zbirke so zato dobile transakcijsko SQLite bazo prek Drift 2.35.1. Etapa osebne sinhronizacije 5. oktobra zdaj tudi osebne zapise seli v posamezne SQLite vrstice (lokalna schema 4), z atomarno oznako uspeha in ohranjenim izvornim Hive. Pokvarjen ali novejši vir se ne ponastavi. Osebni zapis, odhodna operacija in vezava zasebnega prostora imajo skupno transakcijo; sama selitev ne vključi pošiljanja na strežnik.

Izvedena osebna shramba ima omejitev 10 MiB in 50.000 zapisov ter podpira eno aktivno repository instanco. Sočasno urejanje iste zbirke v več procesih ali zavihkih ni podprto. Lokalna baza in izvozi JSON še nimajo dodatnega šifriranja. Uvoz je nedestruktivno združevanje; vsak že obstoječ ID zavrne celotno operacijo, tudi če je vsebina enaka. Izbris projekta ohrani njegova opravila, dogodke in finančne zapise brez povezave na projekt; izbris nakupovalnega seznama odstrani njegove artikle po potrditvi.

Prva etapa je vsebovala lokalni seznam zapadlih opravil; družinska nadgradnja dodaja sistemske opomnike in enotni center. Denar uporablja točne celoštevilske najmanjše enote za EUR, USD, GBP in CHF; ponavljajoče finance in projekcije ostajajo v starem odjemalcu do prenosa.

Prvi strežniški dokaz FamilyHub 0.1.0 z JSON-RPC in povabili v stare projekte ostaja ločen ter privzeto izključen. FamilyHub 0.2.0 je dodal Native API v1 z napravno sejo, registracijo prek povabila in sinhronizacijo lastnih tabel. V namestitvenem paketu je tudi ta API privzeto izključen; dovoljen je v izoliranem razvojnem okolju. FamilyHub 0.3.0 je razširil pogodbo s sync2, ločenimi financami, inboxom, opomniki in SMTP vrsto (schema 7). FamilyHub 0.4.0 dodaja izbirno FCM registracijo in dostavno vrsto (additivna schema 8); Firebase/APNs še nista konfigurirana. Novi zapisi se ne urejajo v starem Kanboardovem spletnem vmesniku. Produkcijski `DB_DRIVER=mysql` in izvozna različica 10.11.19 sta potrjena z arhivom. Nova strežniška matrika vključuje SQLite, MySQL 8.4.11 in MariaDB 10.11.19; to še ne dokazuje učinkovite konfiguracije spletnega gostovanja.

## Lastništvo in preverjanje

| Tok dela | Lastništvo | Zahtevani dokaz |
| --- | --- | --- |
| `local_core` | Nova domena, podatkovna plast, Riverpod stanje, testi podatkov | Restart, CRUD, zneski, napaka zapisa, uvoz brez izgube |
| `mobile_desktop_ui` | Tema, zagon, router, prikaz, SL/EN prevodi, UI testi; nato ločitev starih AI pogovorov | Telefon 320/390, namizje 1280, realni podatki in uporabna prazna stanja; izolacija identitet |
| `kanboard_backend` | `server/`, `docs/server/`, Docker, vtičnik; nato varna stara povezava in predpomnilnik | Verzije, dovoljeni/zavrnjeni klici, enkratna povabila, paket; poverilnice, HTTPS, ločitev računov |
| Glavni agent | Pogodbe, dokumentacija, integracija, neodvisni pregled | Skupni analyze/test/build in pregled rezultatov; napotki ter popravki prek podagentov |

Podagenti spreminjajo samo dogovorjene datoteke. Posodobitve `pubspec.lock` usklajuje glavni agent, `gen-l10n` izvaja lastnik UI. Uporabnikova verzija `1.0.12+12` se ohrani. Testiranje ne piše na produkcijski Kanboard in ne objavlja aplikacije.

## Dnevnik izvedbe

Naslednji rezultati do arhiva pripadajo prvi lokalni etapi. Novo deljenje ima ločen [dnevnik in merila](SHARING_MILESTONE.md); prejšnje gradnje niso dokaz novih sprememb.

- Skupni `flutter test --reporter expanded`: **78/78 uspešnih**. Končni `flutter analyze`: **35 obstoječih info**, brez error/warning; normalen ukaz zaradi info še vrne kodo 1. `git diff --check` uspešen. Pri novem jedru, prikazu in varnostnih shrambah ni novih analyze ugotovitev.
- Lokalno jedro: 19 uspešnih testov, vključno z dejanskim ponovnim odpiranjem Hive, zaporednimi spremembami, revizijami, odpovedjo zapisa/flush, veljavnim in neveljavnim uvozom, obnovo providerja ter časovnim/lifecycle osveževanjem opomnikov.
- Novi vmesnik: 19 uspešnih UI/widget testov, širine 320/390/1280, svetla/temna tema, SL/EN, prazna in napolnjena stanja, urejanje, navigacija, tipkovnica in ponovni zagon prikaza. Preverjeno tudi odpiranje uvoženega datuma zunaj običajnih meja izbirnika.
- Varna stara povezava: 26 novih testov za varno hrambo in migracijo, preusmeritve, globalno identiteto, dnevnike, ločen predpomnilnik ter pozne odgovore ob odjavi. 10 dodatnih testov preverja AI shrambo/privolitve in menjavo identitete v odprtem pogovoru. Obstoječi 4 testi finančne projekcije ostajajo uspešni.
- FamilyHub: 81 uspešnih HTTP preverjanj na SQLite in 81 na MySQL 8.4.11; glavni agent je neodvisno ponovil SQLite sklop. Preverjeni so tudi sintaksa PHP, sveža namestitev s privzeto izključenimi povabili in determinističen ZIP. Podrobnosti v `docs/server/README.md`.
- Končne gradnje: web release, macOS debug in iOS simulator debug uspešne. Flutter 3.47.2 je avtomatično preselil Apple projekta na Swift Package Manager s preostankom CocoaPods, iOS na UIScene in najmanjši različici na iOS 15/macOS 12. Podpisana izdaja in Keychain na napravi še nista preverjena. WebAssembly zaradi obstoječega vtičnika varne hrambe ni potrjen; redna JavaScript gradnja uspe.
- Android debug APK uspe brez `skipDependencyChecks`; paket `com.takndev.kanbanconnect`, različica `1.0.12+12`. Minimalna uskladitev orodij: Gradle 8.14 z uradnim SHA256, AGP 8.11.1, Kotlin 2.2.20. Izolirana konfiguracija brez zasebnih podpisnih datotek omogoči `preDebugBuild`, `preReleaseBuild` pa pravilno zavrne. Za lokalni ukaz je bil uporabljen pravilen `JAVA_HOME`, brez trajne spremembe okolja.
- macOS integracija je odkrila, da ključ Keychain skupin v adhoc Debug/Profile zahteva razvojni certifikat tudi s praznim seznamom. Debug/Profile zdaj tega ključa ne dodaja in končna gradnja uspe; Release ohrani skupino s podpisnim prefiksom. Neuspeh varne shrambe ostane izrecna napaka, brez plaintext nadomestila. Gradnja sama ne potrdi delovanja Keychaina na podpisani napravi.
- Brskalniški preizkus dejanske spletne gradnje: prvi lokalni zagon brez prijave, slovenski svetli prikaz, ustvarjanje opravila/seznama/artikla, odkljukanje in ohranitev po ponovnem nalaganju. Dejanski izvoz JSON preverjen; ponovni uvoz iste kopije pravilno zavrne podvojene zapise. Testni podatki so ločeni na lokalnem izvoru, brez produkcijskih zapisov.
- Končni vizualni pregled spletne gradnje pri 390 px in namizni širini: prilagoditev navigacije in prikaza uspešna, v brskalniku ni opozoril ali napak. Lokalni ogled teče na `http://127.0.0.1:18770/`; posnetka sta v `build/qa/vsakdan-mobile.jpg` in `build/qa/vsakdan-desktop.jpg`. Namenjena sta pregledu, ne produkcijski objavi.

- 2026-10-04: začetek implementacije na veji `codex/vsakdan-foundation`; obstoječe uporabnikove spremembe ohranjene. Trije GPT 6.1 Sol / high podagenti delajo v dogovorjenih ločenih področjih. Docker Desktop je dosegljiv.
- 2026-10-04, pozneje: celovit [pregled stare kode in nove osnove](CODEBASE_AUDIT.md), spremenjena smer na samostojen arhiv in nadaljnjo gradnjo brez obvezne migracije vseh starih podatkov. Prek Softaculous je ustvarjena in prenesena celotna kopija baze/datotek; obnovljena je lokalno brez omrežja. Neodvisno preverjenih 48 tabel/2.180 vrstic, finančna vsebina in vseh 8 priponk. Izdelana sta lokalni izvoznik in samostojen arhivski brskalnik; brez namestitve vtičnika ali urejanja poslovnih podatkov na produkciji.
- Arhivska orodja: 26 Python in 12 JavaScript testov uspešnih. Dejanski arhiv je preverjen v lokalnem brskalniku na telefonu in namizju, vključno z iskanjem, zaključenimi nalogami, finančnim prikazom in prenosom priponke z enako kontrolno vsoto. Obnovitveni MySQL je ustavljen; arhiv za pregled ne potrebuje baze ali Kanboarda. Neposredni `file://` zagon ostaja ročno preverjanje zaradi omejitve avtomatizacijskega brskalnika.

- Nadaljevanje po arhivu: trije isti podagenti gradijo prvo uporabno deljenje. Dodani so lastne strežniške tabele in Native API, transakcijska SQLite odhodna vrsta ter prilagodljivi tokovi za račun, skupne prostore, povabila in konflikte. Glavni agent preverja meje identitete, ponovljivost, odjavo, sočasne spremembe in dejansko aplikacijo. Rezultati: 126 Flutter testov, posebej 1 dejanski HTTP preizkus dveh odjemalcev, 93 native +81 legacy strežniških preverjanj na vsaki od treh baz, uspešne končne web/Android/macOS/iOS simulator gradnje. Glavni agent je v dejanski aplikaciji preveril povabilo in registracijo druge osebe ter shranjevanje, ponovni zagon in uskladitev po ustavitvi testnega strežnika. Podrobnosti in omejitve so v dokumentu mejnika.

- Družinska nadgradnja: skupne dodelitve/dogodki, dnevni pregled/časovnica, trajni inbox, lokalni sistemski opomniki, skupne finance in SMTP vrsta. Končni Flutter nabor 176 PASS, posebej oba dejanska HTTP testa PASS, analyze 35 podedovanih info. iOS simulator potrjuje tudi dostavo po prekinitvi procesa in odpiranje točnega opravila. Podrobna matrika, popravki pravic/omejitev in meje oddaljenega push so v [družinskem mejniku](FAMILY_UPGRADE.md).

- Priprava FCM 5. oktobra: 226 Flutter PASS, oba dejanska HTTP testa PASS, 352 strežniških preverjanj na vsaki od treh baz, 7 testov konfiguracijskega orodja. Android/iOS adapter, varna napravna registracija, trajni preklici in skupine so pripravljeni; resnična dostava in produkcijska namestitev še nista potrjeni. Aktualni dokazi in meje so v [FCM mejniku](FIREBASE_PREPARATION.md).

- Osebna sinhronizacija in obnova 5. oktobra: **297 Flutter PASS in trije dodatni dejanski HTTP PASS**; **436 strežniških preverjanj na vsaki od treh baz**. FamilyHub 0.5.0/schema 9 doda prvi račun z upraviteljsko kodo, preverjanje e-pošte, obnovo gesla in lastniški zasebni prostor. Odjemalec doda SQLite schema 4, izrecno sinhronizacijo lastnih naprav ter šifrirane kopije z obnovo in ohranjenimi operacijami. Končne spletna, Android debug, iOS simulator in macOS debug gradnje so uspešne. Google Play Console ostaja odložen. [Mejnik](PERSONAL_SYNC_AND_RECOVERY.md) vodi dejanske dokaze, omejitve obnove in še nenastavljene produkcijske storitve.
