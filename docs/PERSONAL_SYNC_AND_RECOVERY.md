# Osebna sinhronizacija, prvi vstop in obnova

## Obseg in stanje

Uporabnik je 5. oktobra 2026 potrdil naslednje tri nadgradnje in za zdaj odložil Google Play Console. **Izvedba je pripravljena in preverjena lokalno**, z vtičnikom FamilyHub 0.5.0 in lokalno shemo SQLite 4. To ni produkcijska namestitev; izvedene preizkuse in preostale omejitve navaja zaključek dokumenta. Prejšnje dokaze vodi [priprava FCM](FIREBASE_PREPARATION.md).

1. Začetek brez računa, povezava lastnih naprav ali skupni dom; prijava, vpis s povabilom, prvi račun, preverjanje e-pošte in obnova gesla v aplikaciji.
2. Izbirna zasebna sinhronizacija osebnih zapisov med napravami istega računa. Članstvo v domu teh podatkov ne odpre drugim.
3. Šifrirana prenosna varnostna kopija in preverjena obnova lokalnih podatkov, vključno z dostopnimi skupnimi zapisi in čakajočim delom.

Ponavljajoča opravila, finančne projekcije in priponke so naslednji obseg. Dejanska nastavitev SMTP, Firebase/APNs, podpisane izdaje in namestitev na produkcijo so ločeni koraki. Noben test te etape ne sme spreminjati produkcijskih podatkov ali pošiljati sporočil zunanjim prejemnikom.

## Dogovor o podatkih

- Lokalni način ne potrebuje računa, strežnika ali uspešno odprte varne hrambe prijave. Prijava ne vključuje prenosa osebnih podatkov.
- Osebna shramba se zaradi skupne transakcije zapisa, sinhronizacijske operacije in vezave prostora preseli iz Hive v SQLite. Prenos je preverjen in ponovljiv; izvorni Hive ostane ohranjen. Poškodovanega ali novejšega izvora ne nadomestimo s praznim.
- Vključitev zasebne sinhronizacije je izrecna, s predogledom vsebine. Prehod določi en vir za nadaljnje urejanje in prikaz; isti podatki se na zaslonu Danes ne prikažejo dvakrat. Selitev, čakajoče operacije in oznaka aktivnega vira se zapišejo v isti transakciji.
- Strežnik zagotovi največ en osebni prostor na račun. Povabila, dodatna članstva in dodelitev finančnih pravic drugim uporabnikom so v tem prostoru prepovedani tudi prek neposrednega API klica.
- Osebni finančni zapis ohrani izvirni pomen in povezavo s projektom. Potuje po ločeni finančni pogodbi, ne prek splošnega `sync2`; selitev ne izmišljuje finančnih računov ali prenosov.
- Odjava in menjava računa skrijeta podatke prejšnjega računa ter ohranita njegovo čakajoče delo. Novi lokalni zapisi se ne pripnejo drugemu računu samodejno. Premor sinhronizacije ne izbriše odhodnih operacij.

## Račun in povabila

FamilyHub 0.5.0 uporablja additivno migracijo schema 9. Prvi račun uporablja kratkotrajno enkratno kodo, ki jo izda upravitelj, ne javne neomejene registracije ali skrbniških poverilnic v aplikaciji. Upraviteljska izdaja je mogoča prek zaščitenega obrazca Kanboarda, brez obveznega SSH dostopa. Ponovitev istega obrazca ne izda nove kode. [Pogodba računa in namestitev](server/account-api-contract.md).

Sprememba naslova za obnovo zahteva ponovno potrditev gesla in po potrebi TOTP. Preverjanje e-pošte ter ponastavitev gesla uporabljata enkratne časovno omejene kode, katerih zgoščene vrednosti so v bazi. Uspešna ponastavitev prekliče obstoječe seje; TOTP se z njo ne obide. Brez strežniške konfiguracije e-pošte aplikacija ne sme prikazovati uspešno poslanega sporočila.

Povezava povabila odpre pregled v aplikaciji in zahteva izrecen sprejem. Ne vsebuje trajnega prijavnega žetona in ne povzroči samodejne menjave računa. Lastna URL shema ni dokaz nastavljenih in preverjenih Universal Links/App Links za produkcijsko domeno.

## Varnostna kopija in obnova

Prenosni format uporablja AES-256-GCM, iz gesla izpeljan ključ PBKDF2-SHA256 s 600.000 ponovitvami, naključni 16-bajtni salt in 12-bajtni nonce ter overjeno glavo. Različica, velikost (največ 64 MiB ovojnice oziroma 32 MiB odprte vsebine) in parametri izpeljave ključa so omejeni pred drago obdelavo. Geslo kopije ni geslo strežniškega računa in se ne shrani v kopijo ali nastavitve.

Vsebina obsega osebne podatke in podatke trenutno dostopnega računa, njihove izvirne ter čakajoče različice, konflikte in podprte nastavitve. Prijavni žetoni, gesla, FCM/APNs skrivnosti in identiteta naprave za dostavo niso prenosljivi. Izvoz upošteva trenutno znani preklic in ločene finančne pravice tudi po asinhronem čakanju.

Obnova ima predogled in izrecno izbiro dovoljenega načina združevanja oziroma zamenjave. Podatki in dnevnik želenih nastavitev se obnovijo v eni SQL transakciji; nastavitve SharedPreferences se nato uveljavijo ponovljivo. To ni skupna transakcija dveh različnih shramb. Skupni zapisi in njihove operacije najprej ostanejo v šifriranem območju za obnovo: dokument ni dokaz članstva. Po odklepu je dovoljen ločen arhivski pregled generičnih naslovov z jasno označenim izvornim računom; finančni pregled zahteva ustrezno trenutno identiteto in pravice. Ponovno pošiljanje zahteva ujemajočo identiteto strežnika in računa, sveže preverjene pravice ter izrecno nadaljevanje. Izvirni ID operacij prepreči podvojitev že izvedenih finančnih sprememb.

Kopija odjemalca ni celotna varnostna kopija strežnika. Ne zajame vsebine, ki je naprava ni prenesla, ali priponk, ki še niso del novega organizatorja. Vmesnik mora pokazati nepopolnost. Šifriranje izvoza tudi ni dokaz dodatnega šifriranja aktivne SQLite/Hive baze; ta ostaja ločena tehnična zahteva.

## Lastništvo izvedbe

| Izvajalec | Obseg |
| --- | --- |
| `kanboard_backend` — GPT 6.1 Sol / high | `server/`, `docs/server/`, API pogodbe, migracije, strežniški preizkusi in paket |
| `local_core` — GPT 6.1 Sol / high | `lib/organizer/data`, `domain`, `state` in njihovi testi; selitev, sinhronizacija, kopije in obnova |
| `mobile_desktop_ui` — GPT 6.1 Sol / high | Vmesnik, platformne povezave, prevodi, začetni tokovi in testi prikaza |
| Glavni agent | Uskladitev pogodb, odvisnosti, ta dokument/README/načrt, pregled rezultatov in integracijsko preverjanje |

## Merila dokončanosti

- Prvi lokalni zagon brez računa; zavrnjen Keychain ne blokira osebnega dela.
- Selitev obstoječega Hive, ponovni zagon in simulirana napaka med selitvijo brez izgube ali dvojnikov.
- Izrecen prenos osebnih podatkov na napravi A; naprava B istega računa jih prebere in uredi; račun C ne dobi dostopa.
- Osebne finance in povezave s projekti preživijo selitev, sinhronizacijo in obnovo brez spremembe zneskov.
- Sočasne spremembe, izgubljeni odgovori, premor, ponovni zagon, odjava in menjava računa ohranijo čakajoče delo.
- Vpis s kodo, povabilo, potrditev e-pošte, ponastavitev gesla ter zavrnjene potekle/ponovljene kode; TOTP in preklic sej.
- Kopija z osebnimi ter skupnimi podatki, konflikti in neposlanimi operacijami; napačno geslo, poškodba, nepodprta različica in nedovoljena finančna vsebina so zavrnjeni brez delne obnove.
- Obnova na novo lokalno bazo; nič se ne pošlje pred ustrezno prijavo in izrecnim nadaljevanjem, že potrjene operacije se ne podvojijo.
- Svetla in temna mobilna/namizna postavitev; uvožene povezave ne obidejo preverjanja identitete.
- Smiselni Flutter in strežniški testi, analiza, gradnje za splet/Android/iOS simulator/macOS; rezultate in omejitve vpišemo šele po dejanskem preverjanju.

## Odvisnosti

Pripete nove odvisnosti so [`app_links 7.2.1`](https://pub.dev/packages/app_links/versions/7.2.1), [`cryptography 2.9.0`](https://pub.dev/packages/cryptography/versions/2.9.0) in [`cryptography_flutter 2.3.4`](https://pub.dev/packages/cryptography_flutter/versions/2.3.4). `app_links` zahteva Dart 3.12 / Flutter 3.44; projekt že uporablja Flutter 3.47.2 / Dart 3.13.2. Stare različice vtičnika so izpisovale vsebino povezav v dnevnike, zato jih ne uporabljamo za povezave z enkratnimi kodami. `cryptography_flutter` se na nativnih platformah registrira samodejno; izpeljavo ključa opravi podprti platformni ali ozadni izvajalnik. Različica aplikacije ostaja `1.0.12+12`.

## Končno preverjanje 5. oktobra 2026

- Celoten Flutter nabor: **297 PASS**, trije opt-in HTTP testi so v rednem zagonu preskočeni in so bili dodatno izvedeni proti izoliranim strežnikom: **3 PASS**. Novi tok preveri prvi račun, zasebni prostor na dveh ločenih bazah, zavrnitev tretjega računa, osebne finance, izgubljen odgovor, obnovo z istimi ID operacij, lokalni SMTP in preklic sej po obnovi gesla. Druga dva ohranita dokaze skupnega urejanja, opravil, obvestil in finančnih pravic.
- `flutter analyze`: brez napak in opozoril, **35 podedovanih informacijskih priporočil**. Zaradi njih običajni ukaz vrne izhodno kodo 1; prizadeti novi moduli so brez ugotovitev.
- Končne gradnje: **splet JavaScript, Android debug APK, iOS simulator debug in macOS debug uspešne**. Opozorili o prihodnji podpori Kotlin/SPM sta ohranjeni; Wasm ni potrjena ciljna platforma.

- FamilyHub: **436 preverjanj na vsaki** od SQLite, MySQL 8.4.11 in MariaDB 10.11.19. Vključujejo sočasno porabo kod, zasebni obseg, TOTP, preklic sej in lokalni SMTP. Dodatno 12 dejanskih HTTP preverjanj upraviteljskega obrazca/CSRF, 12 regresij FCM HTTP in 11 preverjanj privzeto izključenega API v razpakiranem ZIP.
- Paket `FamilyHub-0.5.0.zip`: preverjeni deterministična sestava, CRC, vsebina 53 datotek in PHP lint 68 izvornih/testnih datotek. SHA256: `8dafe588ec930d3189d60e79be727cf15d5d29fbbbdf259937f578575c389066`.
- iPhone 17 / iOS 27 simulator: hladni zagon iz testne povezave, ponoven klik iste povezave po preklicu ter izrecni prehod na predizpolnjeno povabilo. Aplikacija pokaže izvorni strežnik in ne sprejme povabila samodejno. Uporabljen je nedejaven testni naslov, brez pošiljanja zunanjih sporočil.
- Obstoječe lokalno opravilo `Test` in pripadajoči opomnik sta po nadgradnji ostala vidna; odpiranje iz centra obvestil pokaže pravo opravilo. To je dejanski dokaz selitve te zbirke, ne splošni dokaz vseh oblik podatkov.
- Dejanski spletni UI: prvi lokalni začetek brez računa, angleški mobilni vstop ter slovenski prikaz pri 390 × 844 in 1440 × 1000, svetla in temna tema. Na ločenem praznem izvoru je čarovnik zavrnil napačno geslo, prikazal predogled in obnovil testno kopijo, ki jo je ustvaril dejanski repository/codec. Po ponovnem nalaganju so ostali 1 opravilo, 1 nakupovalni seznam, 1 artikel s količino 2 kg ter 1 izdatek 15,99 EUR. Obstoječi podatki drugega izvora niso bili zamenjani.
- Dejanski spletni izvoz po pripravi prikaže »Prenos kopije je sprožen«. Vgrajeni brskalnik ni vrnil dogodka/prenesene datoteke, zato fizičnega zapisa tega prenosa nismo potrdili. Preizkus uvoza je uporabil ločeno datoteko, ustvarjeno z istim codec/repository; tega ne predstavljamo kot sklenjen UI izvoz–uvoz. Ponovni prenos v običajnem uporabniškem brskalniku oziroma native picker ostaja ročno preverjanje pred izdajo.

Preizkusi ne pomenijo namestitve na produkciji ali dostave na fizični telefon. Za podpisano izdajo ostajajo potrebni končno ime/identifikator iOS aplikacije, Apple podpis in uporabnikov Firebase/APNs projekt.

Podrobni lokalni rezultati so v `build/qa/personal-sync-recovery/` (namenoma zunaj različic); podatkovni in UI testi ostajajo v repozitoriju. Končno preverjanje uporablja Flutter 3.47.2 / Dart 3.13.2. Obstoječi arhiv starega strežnika in produkcijski podatki niso spremenjeni.

## Znane meje

- Ponovno vključevanje obnovljenega skupnega dela trenutno obravnava celoten paket. En preklican prostor lahko prepreči nadaljevanje paketa; izbira posameznih prostorov za obnovo še ni izdelana. Šifrirani paket in čakajoče delo ostaneta ohranjena.
- Finančnega dela arhiva ni mogoče odpreti zgolj z geslom kopije brez ustrezne identitete in pravic. Na novi nepovezani napravi so osebni lokalni zapisi obnovljivi, aktivacija skupnih in zasebno sinhroniziranih zapisov pa zahteva ustrezno prijavo in preverjanje pravic.
- Aktivna baza nima dodatnega šifriranja; kopija ne vsebuje priponk ali še neprenesenih strežniških podatkov. Sinhronizacija ni nadomestek kopije strežnika.
- SMTP, Firebase/APNs in produkcijski Universal Links/App Links niso nastavljeni. Prvi račun potrebuje kodo upravitelja; javna registracija ni odprta.
- macOS gradnja je preverjena; že odprte stare namizne aplikacije zaradi uporabnikovega obstoječega stanja nismo ponovno zagnali. Namizni prikaz preverjamo tudi v spletni izvedbi.
