# Prvo uporabno deljenje

Uporabnik je 4. oktobra 2026 odobril nadaljevanje po preverjenem arhivu. Cilj te etape je celoten tok med dvema osebama: povezava računa v aplikaciji, povabilo, skupni nakupovalni seznam in osnovna opravila, lokalno urejanje brez povezave ter zanesljiva uskladitev. Telefon in namizje uporabljata iste pogodbe. Ta dokument vodi obseg in dejansko preverjanje razvojne izvedbe. Produkcijska namestitev in izdaja v trgovinah sta ločena koraka.

## Meje podatkov in dostopa

- Obstoječi arhiv je samostojen in ostane nespremenjen. Ta etapa ne namešča vtičnika na produkcijo in ne briše stare aplikacije ali projektov.
- Osebna uporaba ne zahteva računa. Osebni zapisi se ne objavijo samodejno ob prijavi; deljenje je izrecno dejanje nad izbrano vsebino.
- Gospodinjstvo in posamezen deljeni projekt sta različna obsega. Članstvo v enem ne odpre drugega. V prvi pogodbi so deljiva le opravila, projekti in nakupovalni seznami/artikli.
- Novi skupni zapisi so v lastnih tabelah FamilyHub. Ne postanejo člani starih Kanboardovih projektov in ne podedujejo dostopa do njihovih metapodatkov.
- Uporabnik je dodatno pojasnil: finance so lahko osebne, skupne za isti dom ali del izrecno tako zasnovanega projekta. Finančni modul določi, katera vsebina je skupna in kdo jo sme brati/urejati; zunanji sodelavec ne dobi zasebnega pregleda doma samo s članstvom v projektu. Trenutni mejnik še ne sinhronizira financ. Finančna prenova bo ločila dejanske transakcije, načrtovane postavke in ponavljajoča se pravila; denar uporablja najmanjše enote in valuto. Pravice veljajo tudi pri izvozu in obvestilih.
- Prva registracija novega sodelavca temelji na veljavnem povabilu. Obstoječi lokalni Kanboardov račun omogoči začetek uporabe lastnega strežnika. Javno ustvarjanje skrbnikov ali globalni API ključ v aplikaciji nista del pogodbe.

## Merila dokončanosti

1. Dva sintetična uporabnika se prijavita oziroma registrirata in sprejmeta povabilo v aplikaciji. Geslo ne ostane shranjeno; naprava dobi omejeno, preklicljivo sejo. Vključenega drugega faktorja ni mogoče obiti.
2. Lastnik ustvari obseg in seznam, povabi drugo osebo ter vidi članstvo. Nečlan ne more brati, pisati ali naštevati zasebnih zapisov. Preklic prepreči naslednji strežniški dostop.
3. Lokalni zapis in odhodna sprememba sta ena transakcija. Ponovni zagon med odsotnostjo omrežja ohrani vse čakajoče spremembe. Osebni način ne ustvarja odhodne vrste.
4. Neodvisne spremembe različnih artiklov se ohranijo. Sprememba istega zapisa z zastarelo revizijo zahteva jasno rešitev; ni tihega pravila zadnjega pisca. Ponovljena zahteva ne ustvari dvojnika.
5. Izbrisi se prenesejo kot označeni izbrisi. Dnevnik sprememb in kazalec ne izpustita sočasno potrjenih transakcij; povezave med zapisi ne smejo prečkati obsega.
6. Odjava ali menjava računa ne pomeša lokalnih skupnih zbirk, poznih odgovorov in osebnih podatkov. Zavrnjenih oziroma neusklajenih sprememb ne izgubimo tiho.
7. Vmesnik jasno pokaže osebno/skupno vsebino, stanje povezave, čakajoče spremembe in konflikt. Osnovne poti so preverjene pri širinah 320/390/1280 in v SL/EN.
8. Nakupovalna dejanja ne ustvarjajo e-pošte. Sistemski opomniki, SMTP in push imajo ločeno naslednjo etapo; njihovih zmožnosti ne oglašujemo pred izvedbo.

## Lastništvo in pregled

| Lastnik | Področje |
| --- | --- |
| `kanboard_backend` | Strežniški protokol, avtentikacija, lastne tabele, dovoljenja, povabila, sinhronizacija in integracijski testi |
| `local_core` | Lokalna podatkovna plast, odhodna vrsta, transport in seje, ponudniki stanja, podatkovni ter integracijski testi |
| `mobile_desktop_ui` | Tokovi v aplikaciji, prilagoditev telefonu/namizju, prevodi in testi prikaza |
| Glavni agent | Pogodbe med plastmi, odvisnosti, dokumentacija, neodvisen pregled in končno preverjanje |

Vsi podagenti uporabljajo dogovorjeni GPT 6.1 Sol / high. Spremembe ostajajo na razvojni veji; uporabnikova različica `1.0.12+12` se ohrani. Natančna pogodba je v [native-api-contract.md](server/native-api-contract.md), odvisnosti hrambe pa v [dokumentaciji odvisnosti](dependencies/README.md).

## Izvedena razvojna pot

- FamilyHub 0.2.0, Native API v1: prijava lokalnega uporabnika s TOTP, omejitve poskusov, preklicljiva seja naprave, registracija samo z veljavnim povabilom. Protokol ne potrebuje globalnega API ključa ali spletne seje Kanboarda.
- Ločeni obsegi `household`/`project` ter vloge `owner`/`member`/`viewer`. Vsak strežniški dostop preveri identiteto in članstvo. Novi obsegi ne odprejo starih finančnih metapodatkov.
- Drift 2.35.1 in SQLite za skupne zapise, odhodne operacije, konflikte in kazalce. Osebni Hive ostane ločen; izrecna skupna kopija izbranega seznama ali projekta/opravila dobi nove ID-je in ohrani izvirnik.
- Strežniške revizije, trajna idempotenca zapisov in označeni izbrisi. Lokalni osnutki ostanejo pri konfliktu ali odvzetih pravicah; vrnitev članstva zahteva izrecno nadaljevanje blokiranega dela.
- Lokalna identiteta vključuje normaliziran strežnik, trajni `serverId` ter `accountId`. Menjava računa ne sme prenesti starega zahtevka z novim žetonom; pozni odgovori, shranjevanje seje in odprti obrazci imajo preverjeno mejo identitete.
- Telefon in namizje: Račun in deljenje, pregled povabila in registracija, skupni prostori, člani in preklici, izbira Osebno/Deljeno pri nakupih, izrecna skupna kopija, vidno stanje neusklajenega dela ter razrešitev konfliktov. SL/EN in obe temi.

## Dokazi preverjanja, 4. oktober 2026

| Preverjanje | Rezultat |
| --- | --- |
| Celoten Flutter sklop | **126 uspešnih**, en opt-in HTTP test je pri običajnem zagonu namenoma preskočen |
| Dejanski Dart → HTTP → FamilyHub preizkus | **1 uspešen** posebej omogočen test z dvema računoma in dvema fizičnima SQLite zbirkama |
| Podatkovni sklop organizatorja | **45 uspešnih**; vključuje 18 novih repository ter 8 novih transport/varna hramba testov |
| UI organizatorja | **40 uspešnih**: 18 osebnih in 22 skupnih, širine 320/390/1280, SL/EN in obe temi |
| `flutter analyze --no-pub --no-fatal-infos` | Brez error/warning, **35 obstoječih info** v starem odjemalcu |
| Native strežniški HTTP sklop | **93/93 na SQLite, MySQL 8.4.11 in MariaDB 10.11.19**; glavni agent je neodvisno ponovil SQLite |
| Stari strežniški regresijski sklop | **81/81 na vseh treh bazah** |
| Končne gradnje | **web release, Android debug APK, macOS debug, iOS simulator debug uspešne** |
| Dejanski namestitveni ZIP | CRC in izvorne datoteke ustrezajo, determinističen SHA256; svež izoliran vsebnik **4/4** privzetih pravil |
| `git diff --check` | Uspešen |

Podatkovni testi preverjajo fizični ponovni zagon, transakcijski rollback celotne skupne kopije, neodvisne spremembe dveh odjemalcev, izgubljen odgovor in ponovitev iste operacije, novejšo strežniško različico med konfliktom, zastarel odgovor po že novejšem prenosu, preklic/vrnitev pravic, spremembo v gledalca, prevzem lokalnega zaklepa in pozno prijavo proti novejšemu računu. Testi transporta pokrivajo HTTPS, zavrnjene preusmeritve, omejeno velikost odgovora in skupni časovni rok; varna hramba nima plaintext nadomestila.

Strežniški testi med drugim preverjajo sočasni sprejem/preklic povabila, rollback registracije, odvzem članstva med zapisovanjem, vrstni red potrjenih sprememb, izbrise in starše, zavrnitev tujih obsegov ter finančnih tipov v v1, omejitve UTF-8 in paginacije, TOTP/replay in potek naprave. Podrobnosti paketa in testov so v [strežniških navodilih](server/README.md).

Glavni agent je dodatno skozi dejansko spletno aplikacijo na dveh ločenih izvorih (`127.0.0.1:18770` in `18771`) preveril:

1. Prijavo sintetičnega lastnika, ustvarjanje gospodinjstva, seznama in artikla.
2. Ustvarjanje povabila v UI, predogled, registracijo drugega sintetičnega računa in sprejem brez odpiranja Kanboardovega spletnega vmesnika.
3. Skupni seznam, odkljukanje prvega artikla in dodajanje drugega pri članu; oba rezultata postaneta vidna lastniku.
4. Ustavitev samo lokalnega razvojnega strežnika, nov lokalni artikel ter ponovno nalaganje aplikacije. Seja, vsebina in neposlana sprememba ostanejo.
5. Ponovni zagon strežnika, prazno odhodno vrsto in prenesen artikel pri drugi osebi.

To je preizkus nedosegljivega API-ja pri že nameščeni/naloženi aplikaciji, ne dokaz prvega prenosa spletne aplikacije brez interneta. Podatki so sintetični; produkcijski strežnik in arhiv nista spremenjena. Končni spletni prikaz je vizualno preverjen pri širinah 320, 390 in 1280, v novi seji brskalnika ni napak ali opozoril. Posnetka sta lokalno v `build/qa/sharing/mobile-shared-light.png` in `desktop-shared-light.png`. Običajna širina brskalnika je po preizkusu obnovljena.

## Preostale meje

- Native API ostaja v namestitvenem paketu privzeto izključen. Pred resnično uporabo sledi namestitev na testno poddomeno gostovanja, preverjanje HTTPS/Authorization/CORS, varne hrambe na podpisanih napravah in postopka obnove. Produkcija ni nameščena ali upokojena.
- Prvo osebo povežemo z obstoječim lokalnim Kanboardovim računom. Obnova gesla, preverjanje e-pošte in zunanji ponudniki prijave še niso vključeni. Koda povabila se deli ročno; ni e-poštne dostave ali samodejnega odpiranja aplikacije s povezavo.
- Ustvarjanje prostora in povabila zahteva omrežje. Upravljavski ukazi še nimajo trajne lokalne odhodne vrste: izgubljen odgovor in novo uporabniško ponavljanje lahko ustvarita dodaten prazen prostor/povabilo. To ne velja za sinhronizirane zapise, ki ohranijo isti ID operacije ob ponovitvi. Pred ponavljanjem preveri seznam prostorov/povabil.
- Izvoz neusklajenega dela je reševalni zapis operacij, ne popolna varnostna kopija skupne baze ali pripravljen uvoz v osebno domeno. Lokalna baza in izvozi niso dodatno šifrirani. Žeton je v varni shrambi. Odjava ohrani osnutke za isti račun, vendar jih skrije drugemu.
- Sinhronizacija teče med uporabo in ob vrnitvi v aplikacijo, ne kot zagotovljen proces v ozadju zaprte aplikacije. Preklic ne more izbrisati že pridobljene kopije na nepovezani napravi.
- Dogodki, priponke in finance še niso vključeni v novo sinhronizacijo. Finance bodo podpirale osebni obseg, skupen dom in izrecno tako zasnovane projekte z lastnimi pravicami. Obvestila v ozadju, SMTP in push ostanejo naslednja etapa.
- Windows/Linux in podpisane mobilne izdaje niso potrjene. Osebni Hive še podpira eno aktivno instanco; večprocesna koordinacija nove skupne baze ne pomeni, da jo podpira tudi stara osebna shramba.

## Ponovitev preverjanj

```sh
flutter test --no-pub --reporter expanded
flutter analyze --no-pub --no-fatal-infos
docker compose -f server/compose.yaml exec -T kanboard php /familyhub-tests/native-integration.php
```

Posebni HTTP preizkus v `test/organizer/data/collaboration_http_integration_test.dart` se omogoči z `KANBAN_SHARED_HTTP_FIXTURE` na zasebno datoteko, ustvarjeno s testnim `native-seed.php`. Sprejme samo izrecno sintetično loopback okolje. Poverilnic, zasebne fixture in dnevnikov z uporabniškimi podatki ne dodajaj v Git. Za strežniški paket in matriko baz uporabi strežniška navodila; testov z istim namenskim zapisom za omejevanje poskusov ne izvajaj sočasno nad isto bazo.
