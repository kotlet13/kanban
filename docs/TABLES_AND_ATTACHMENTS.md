# Preglednice in priloge — 16. oktober 2026

Uporabnik je po pogovoru izrecno naročil izvedbo obeh nadgradenj. Funkcionalnosti
so izvedene v izvornem repozitoriju in preverjene na ločenih sintetičnih
strežnikih. Produkcija/test1 ostajata na prejšnji nameščeni različici,
zamrznjeni AAB29 pa teh novih modulov ne vsebuje. Google Play oddaja še vedno
potrebuje novo uporabnikovo izrecno potrditev; Apple ostaja odložen.

## Kje sta možnosti

V Prostor → pregled povezane organizacije sta »Preglednice« in »Priloge«.
Priloge so dosegljive tudi v nastavitvah deljenega prostora, v enotnem meniju
projekta z lastnim deljenim prostorom in v meniju podrobnosti skupnega opravila.
Preglednica ima svoj razdelek prilog. Obseg je vedno pripet konkretnemu
strežniku, računu, napravi in prostoru; navigacija izbora ne menja samodejno.

## Preglednice

Prazna mreža s stolpci A, B, C … in oštevilčenimi vrsticami se sproti razširja.
Izrisuje se samo viden del. Vnosna vrstica kaže izvorno besedilo ali formulo,
celica izračunano vrednost. Podprti so besedilo, številke, sklici na celice,
+ − × ÷, oklepaji ter SUM, AVERAGE, COUNT, MIN in MAX z obsegi. Decimalna vejica
in podpičje sta podprta; cikli, deljenje z nič in preveliki izračuni imajo
jasno oznako napake brez izvajanja kode ali omrežnih formul.

Možni so izbor celic/obsega, tipkovni premiki, kopiranje/lepljenje pravokotnega
obsega, neposreden skok na naslov in prilagoditev širine stolpca. Telefonski
vnos ostane nad tipkovnico. Svetla/temna tema, SL/EN in postavitve pri
320/390/1280 ter 2× besedilu so preverjene z widget testi in izrisi.

Za »Uredi preglednico« je potrebna povezava. Zaklep velja za eno preglednico
in eno overjeno napravo; drugim je prikazan urednik in omogočen ogled.
Strežnik zaklep podaljšuje za 90 sekund, odjemalec ga obnavlja vsakih 25 sekund.
Potek, druga naprava, izgubljeni zaklep ali napačna revizija zavrnejo star zapis.
Ista overjena naprava lahko po ponovnem odprtju varno obnovi svoj še veljavni
zaklep. Stara ponovljena sprostitev ne odklene novega urednika.

Vnos se sproti hrani kot lokalni osnutek. »Shrani« oziroma »Shrani in končaj
urejanje« potrdi skupni zapis; izhod/ohranitev brez povezave ohrani osnutek za
izrecno nadaljevanje. Starejši osnutek se ne postavi samodejno nad novejšo
revizijo: uporabnik izbere obnovo, kopijo ali potrjeno uporabo shranjene
različice. Po znanem odvzemu dostopa ali izbrisu izginejo naslov, celice in
priloge; lastno neposlano delo ostane ločeno. Pozni lokalni zapis ostane pri
izvornem računu, trajna oznaka izbrisa računa pa tudi tak zapis zavrne.

Varnostne meje prve pogodbe: naslovi do ZZZ100000, največ 10000 nepraznih
celic, 4096 UTF-8 bajtov na celico, 512 KiB vsebine ter 100 preglednic na
organizacijo. Mreža ne ustvarja praznih vrstic v bazi.

## Priloge

Podprti so PDF, DOC/DOCX, ODT, XLS/XLSX, ODS, TXT, CSV, RTF ter JPEG/PNG.
Izbira datoteke je omejena pred branjem; največ 20 MiB na prilogo in 256 MiB
na prostor. Prenos po kosih preverja dolžino, SHA-256, odmik in isti cilj;
stare zahteve imajo ločena potrdila za račun/napravo/operacijo.

Seznam pokaže samo zaključene prenose. V meniju so shranitev kopije, dovoljen
izbris s potrditvijo in prijava vsebine. Izvoz je izrecen prek sistemskega
izbirnika; aplikacija datoteke ne zažene. Prenesene datoteke so dosegljive brez
povezave tudi po ponovnem zagonu, s preverjenim lokalnim predpomnilnikom do
64 MiB na prostor. Znana zavrnitev dostopa prepreči tudi uporabo predpomnilnika.

Strežniška shramba je zasebna in uporablja naključne identitete ter razpršena
imena. Pred zaključkom se preverijo podpis/tip datoteke in omejena struktura
pisarniških ZIP vsebnikov. Nalaganje/prejem/preimenovanje cilja ali izbris ne
preskočijo svežih pravic, arhiva ali omejitve neposredno deljenega projekta.
Fizični izbris je trajno ponovljiv tudi po napaki diska. Izbris opravila,
preglednice, projekta, prostora ali računa vključuje pripadajoče datoteke.
Za oba nova tipa sta podprta prijava vsebine in obstoječi skrbniški postopek.

## Sinhronizacija, kopije in združljivost

Preglednice imajo ločen strežniški API z revizijo in zaklepom. Generična
pogodba record6 ter stare nespremenljive operacije ostanejo iste. Starejši
strežnik novih možnosti ne oglašuje; aplikacija to jasno pokaže. Razširitev
FamilyHub uporablja dodajalno shemo19; nobena gostovana namestitev ni spremenjena.
[Strežniška pogodba in priprava kopij](../server/plugins/FamilyHub/DOCUMENTS_API.md).

Lokalna SQLite shema ostane10. Prenosna šifrirana kopija7 ohrani upravičene
lokalne osnutke preglednic in bere stare oblike1–6. Obnova jih najprej hrani
v šifriranem obnovitvenem območju. Nadaljevanje potrebuje isti strežnik/račun,
sveže dovoljene pravice in izrecno dejanje; ne pridobi zaklepa ali pošlje
sprememb samodejno. Žetoni zaklepa/seje in predpomnjeni strežniški bajti niso
v prenosni kopiji. Za celotne kanonične preglednice in izvirne priloge je
potrebna celotna strežniška kopija baze ter zasebnega DATA_DIR. Izrecno
shranjene uporabniške kopije datotek ostanejo na uporabnikovem izbranem mestu.

## Preverjanje

- Celotni Flutter regresijski preizkus: 1505 PASS, 16 izbirnih preskokov.
  Po zadnji izboljšavi kopiranja večvrstičnih celic še 155 ciljnih PASS;
  po vključitvi istega zapisa v izvoz obnovitvenega osnutka še 54 PASS.
- Končna Android debug gradnja PASS; vseh 319 popisanih vhodov lib/assets
  in pubspec/lock je med končnim preverjanjem in gradnjo ostalo enakih.
  Ni sprememb SDK, odvisnosti, native dovoljenj ali starega AAB29.
- Dejanski Dart → HTTP → PHP → SQLite ter MariaDB: dve ločeni napravi/računa,
  izključitev drugega urednika, prevzem po sprostitvi, formule in revizije,
  star zapis, večkosovni prenos datoteke, prijavni predogledi obeh tipov,
  ponovni zagon SQLite brez povezave, ohranitev datoteke in izbris.
- 241 strežniških kontrol PASS na vsaki od SQLite, MariaDB10.11.19 in MySQL8.4
  (723), poleg 192 obstoječih lifecycle in 162 Ideas regresijskih kontrol.
  Dodajalna migracija, arhiv/pravice, sočasni HTTP, ponovitve, diskovne napake,
  zasebne poti, ODF/OOXML, prijave, odvzem dostopa in izbris računa.
- 94 PHP datotek sintaktično veljavnih; Dart analiza ima istih 10 predhodnih
  info v nepovezanih izdajnih orodjih, brez opozoril ali napak.
- Widget posnetki so v build/qa/organization-upgrades-20261016 in
  build/qa/documents-attachments-20261016. Podatki so sintetični, ne uporabniški.

Glavni dnevniki: build/qa/documents-final-full-tests.log,
documents-final-targeted-tests.log, documents-data-tests.log,
documents-http-sqlite.log, documents-http-mariadb.log,
documents-full-analyze.log ter documents-android-debug.log.
Strežniške kontrolne dnevnike vodi /tmp/documents-*.log.
Fizična uporaba novega vmesnika, sistemski izbirniki in TalkBack/VoiceOver še
niso potrjeni. Ni nove nameščene aplikacije ali trgovinskega paketa.

## Naslednja izdaja

Pred vključitvijo v javno različico pripravimo nov zamrznjen izvor/paket,
ustrezno različico FamilyHub in preverjeno nadgradnjo gostovanja na shemo19
s svežo dejansko kopijo in izolirano obnovo celotnih podatkov/datotek. Starih
pomočnikov sheme18 se ne rahlja. Posodobiti je treba deklaracijo Files and
docs v Google Play Data safety ter pregledati politiko zasebnosti/opise glede
na nove priloge. Ta zapis ni oddaja teh sprememb. AAB29 ostaja nespremenjen
(SHA-256 42cb54088ead068d9c2e21ad5e267d10a48af8a31483d0c40c7367d2e8fbd475).
