# Lokalni arhiv starega Kanboarda

Orodje bere **že preneseno in lokalno obnovljeno varnostno kopijo**. Ne uporablja
produkcijskega API, ne izvaja PHP iz kopije in ne spreminja izvirnikov. Brskalnik
je ločen od uvoza v novi organizator; ne pretvarja starih zapisov v novo domeno.

Potrebujemo celotno varnostno kopijo podatkovne baze in namestitvenega imenika
(konfiguracija, vtičniki in lokalne priponke). Izvoz iz obstoječe aplikacije/API
ne zadostuje: aktivni projekti, privzeto odprta opravila, omejena zgodovina in
uporabniške pravice lahko izpustijo zapise. Arhiv zajame trenutno ohranjene
podatke v kopiji; že izbrisane zgodovine ali priponk ne more obnoviti.

## Izvoz

Python 3.9+ in standardna knjižnica zadoščata. Za MySQL je potrebna lokalna,
izolirana obnova v uradni sliki MySQL z odjemalcem `mysql`. Orodje preveri
`--network none`, odsotnost objavljenih vrat in odsotnost host bindov. Sprejme
anonimni podatkovni volumen `/var/lib/mysql`, ki ga uradna slika ustvari sama.
Obnovo in poznejšo odstranitev tega vsebnika/volumna opravi izvajalec zajema.
Orodje ne zaganja Dockerja, ne uvaža dumpa in ne preverja produkcijskih poverilnic.

Primer po uspešni obnovi baze `legacy_archive` v vsebnik `kanboard-archive`:

```sh
python3 tools/legacy_archive/export_archive.py \
  --mysql-container kanboard-archive \
  --database legacy_archive \
  --files-root /absolute/archive/original/data/files \
  --output /absolute/archive/browse \
  --private-output /absolute/archive/private-export \
  --backup /absolute/archive/original-backup.tar.gz \
  --captured-at '2026-10-04T19:10:54+02:00' \
  --kanboard-version 1.2.54
```

`--kanboard-version` je podatek iz preverjene evidence varnostne kopije, ne sklep
iz različice lokalne slike. Za SQLite je alternativa `--sqlite /absolute/copy.sqlite`;
tudi ta mora biti koherentna varnostna kopija, ne odprta baza žive aplikacije.

MySQL bere vse tabele v eni transakciji `READ ONLY` s konsistentnim snapshotom.
Vsako polje prenese prek `HEX(CAST(field AS BINARY))`, zato novi vrstici, NUL in
Unicode ne zamenjajo meja vrstic. Cela števila ostanejo cela; ostala številska
polja ohranijo besedilno serializacijo, brez pretvorbe v Python `float`. Zasebni
izvoz hrani še izvirne HEX celice. To je serializacija vrednosti SQL, ne fizična
kopija baze. Preneseni dump in originalni paket ostajata avtoritativna izvirnika.

Izhodni mapi morata biti novi oziroma prazni, ločeni od izvirnikov in med seboj.
Obstoječega arhiva orodje ne prepiše. Imeniki dobijo način `700`, datoteke `600`.
Podatkov oziroma skrivnosti ne izpisuje v terminal; izpiše le števila in stanje.

## Kaj dobimo

`private-export/tables/*.json` vsebuje **vse tabele in vse stolpce**, tudi neznane
tabele vtičnikov, prijavne zapise in skrivnosti. Zasebni `manifest.json` vsebuje
shemo, tuje ključe, števila, inventar vseh izvirnih datotek s SHA256 ter identiteto
originalnega paketa. Ta del in izvirno kopijo varuj kot občutljivo varnostno kopijo;
nikoli ju ne postavi v koren spletnega strežnika in ju ne deli kot navadno spletno stran.

`browse/` vsebuje samostojen pregledovalnik, `archive-data.js`/JSON, javni manifest
in kopije vseh referenciranih projektnih ter opravilnih priponk. Celotne poslovne
tabele vključujejo odprta/zaprta opravila, aktivne/neaktivne projekte in steze,
komentarje, podopravila, časovne zapise, oznake, povezave, metapodatke, aktivnosti,
prehode, skupine, članstva, vloge in omejitve. Finančni markerji, vsi koščki ter
nepoznana poslovna polja ostanejo nespremenjeni. Brskalnik dekodira znani finančni
format le, ko je popoln in podprt; poškodovanega ali novejšega ne popravi sam.

Brskalnik dobi dovoljen seznam poslovnih tabel. Prijavne/sejne/nastavitvene tabele
in neznane tabele ostanejo zasebne. Uporabniki imajo dovoljen seznam identitetnih
polj; gesla, ključi, žetoni, skrivnosti 2FA in javni projektni žetoni so izključeni.
Tudi strukturirani JSON v dogodkih se pregleda rekurzivno, vključno s camelCase
imeni in metapodatki `name`/`key` + `value`. Izpuščene tabele in redigirani stolpci
so navedeni v manifestu. Ne gre za anonimizacijo: opisi, finance, naslovi, e-pošta
in vsebina priponk so še vedno osebni podatki. Skrivnosti, ki jih je uporabnik
sam zapisal v prosto besedilo ali datoteko, se ne prepoznajo samodejno.

Pri priponkah se preverijo poti, velikost ter SHA256 kopije. Imena so varna in
ohranijo ID; aktivne spletne priponke dobijo končnico `.download`. Vsebina datotek
ostane v natančnih izvirnih bajtih. Neodobrene poti, simbolne povezave, manjkajoče
datoteke, napačna velikost, razlika v številu zapisov ali poškodovani tuji ključi
preprečijo `integrity.complete=true`. Nereferencirane datoteke, npr. sličice,
ostanejo v originalu in so popisane v zasebnem inventarju.

`complete` pomeni preverjen zajem vseh tabel in referenciranih datotek **dodanega
lokalnega vira**. Ne dokazuje, da je izvajalec prenesel vsako zunanje skladišče,
ali da je zajem baze in imenikov sočasen. To je treba preveriti pri pridobivanju
kopije. Izpuščena varnostna polja v brskalniku niso izguba zasebnega izvirnika.
Napake dajo exit `2`; neuspešen izvoz `1`; preverjen zajem `0`.

## Pregled brez starega strežnika

Odpri `browse/index.html`. Pregledovalnik uporablja lokalni `archive-data.js`,
brez `fetch`, CDN, oddaljenih slik ali vstavljanja opisov kot HTML. Povezave na
zunanje vire so le izrecna uporabniška dejanja. Priponk ne izvaja ali vdeluje.

Kadar avtomatiziran brskalnik ne dovoljuje `file://`, je na voljo omejen predogled:

```sh
python3 tools/legacy_archive/serve_archive.py \
  --archive /absolute/archive/browse --port 18482
```

Posluša izključno `127.0.0.1`, preveri `Host`, dovoli le `GET`/`HEAD`, znane
generirane datoteke in referencirane priponke. Ne omogoča seznama imenikov, ne
sledi simbolnim povezavam in ne izpostavi staršev, zasebnega izvoza ali izvirnikov.
CSP blokira omrežne zahtevke, CORP blokira vključevanje datotek z drugega izvora,
odgovori niso predpomnjeni in poti niso beležene. Ustavi ga s Ctrl-C. Končni
arhiv ostane uporaben brez tega strežnika.

## Preizkusi

```sh
python3 -m unittest discover -s tools/legacy_archive/tests -v
LEGACY_ARCHIVE_TEST_CONTAINER=kanboard-archive \
  python3 -m unittest discover -s tools/legacy_archive/tests -v
node tools/legacy_archive/viewer/tests/viewer.test.js
```

Drugi ukaz doda poizvedbo brez pisanja v lokalni MySQL za številske tipe, NULL,
binarne vrednosti, Unicode in nove vrstice. Ostali testi uporabljajo sintetiko:
celovitost zasebnih tabel, zaprte zapise, finance, skrivnosti, prehod skozi JS,
priponke, poškodovane relacije, varne poti in omejitve predogleda. Ne trdijo, da
je s tem preizkušena obnova na izvirni produkcijski različici podatkovne baze.
