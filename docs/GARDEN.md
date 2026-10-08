# Vrt — prva lokalna izvedba

**Dopolnitev 8. oktobra:** aktualna lokalna schema 6, JSON 4 in prenosna kopija 3 ohranijo vrtove ter berljivost prejšnjih formatov. Dejanske legacy schema4/JSON2–3/prenosne1–2 regresije so ponovno preverjene v [nadgradnji](UPGRADE_IMPLEMENTATION.md). Spodaj ostanejo dokazi prvotne izvedbe schema5.

Stanje 7. oktobra 2026. Modul omogoča več poimenovanih vrtov, lastne zapiske in preprosto skico zasaditve. Telefon ga odpre iz zavihka **Več**, namizje iz stranskega menija. Prazno stanje ne vsebuje izmišljenih vrtov ali rastlin.

## Uporaba

Uporabnik ustvari vrt, vpiše ime in zapiske ter na skici nariše pravokotna območja. Vsako območje lahko poimenuje, premakne, izbriše ali z obrazcem spremeni njegov položaj in velikost. Obrazec uporablja odstotke skice; koordinat ne zaokroži pri spremembi samega napisa. Razveljavitev ohrani zadnjih 50 sprememb območij. Izhod z neshranjenim osnutkom zahteva izbiro med nadaljnjim urejanjem in zavrženjem.

To je ročni načrt razporeditve: brez fizičnega merila, prostoročnih potez, kataloga rastlin, koledarja setve ali samodejnega načrtovanja. Deljenje in sinhronizacija vrtov še nista izvedena. Oznaka **Na tej napravi** to pove v aplikaciji.

## Hramba in kopije

- SQLite/Drift lokalna schema **5** doda `device_gardens`, ločeno od strežniških računov, prostorov in odhodnih operacij. Vrt deluje brez računa in omrežja; odjava ter izbris strežniškega računa ga ohranita.
- Revizija zapisa in generacija zbirke preprečita prepis z zastarelim urejevalnikom. Ob izbrisu ostane lokalna revizijska meja brez vsebine, zato tudi obnova istega ID-ja ne ponovno potrdi starega odprtega osnutka.
- Osebni JSON format **3** in šifrirana prenosna kopija **2** vključujeta vrtove. Stare kopije ostanejo berljive in ob obnovi ne odstranijo obstoječih vrtov. Stara shramba, ki vrtov ne podpira, zavrne njihov uvoz; ne izpusti jih tiho.
- SQL obnova vrtov poteka v isti transakciji kot drugi lokalni podatki. Napačni podatki, kolizije pri združevanju ali napaka pisanja ne smejo pustiti delne obnove.
- Omejitve: 500 vrtov, 1.000 območij na vrt, 10 MiB vrtnih podatkov; ime 200 in zapiski 20.000 znakov. Koordinate morajo biti končne, območje pozitivne velikosti in v celoti znotraj skice. Poškodovana shramba se ne ponastavi.

## Dokazi preverjanja

Končni podatkovni in regresijski nabor: **76/76 PASS** (`build/qa/garden-release/garden-core-firebase-final-tests.log`). Vključuje ponovno odprtje dejanske SQLite datoteke, migracijo 4 → 5, konflikt dveh repozitorijev, izbris in ponovno obnovo istega ID-ja v JSON ter šifrirani kopiji, atomarnost/rollback, združljivost starih kopij in izolacijo od izbrisa računa.

Vrt, navigacija in prvi vodič: **48/48 PASS**. Od tega 18 preverjanj Vrta zajema dejanski SQLite tok ustvarjanja, spremembe, ponovnega odpiranja in brisanja, neshranjen osnutek, zavrnjen zastarel zapis, premikanje do roba, ročno validacijo koordinat ter postavitve širine 320/390/1280 v slovenščini in angleščini, svetli in temni temi. Namizni meni ostane dostopen tudi pri višini 640/720.

Ročni pregled sveže spletne gradnje dodatno potrdi ustvarjanje, opombe, območje prek obrazca, risanje drugega območja, shranjevanje in ohranitev po ponovnem nalaganju. Preverjen je tudi prikaz pri telefonski širini 390. Dokazili: `build/qa/garden-release/garden-desktop-persisted.png` in `garden-mobile-drag.png` (druga slika dokazuje postavitev/izbiro, ne uspešnega premika z gesto). Preizkusni vrt je jasno poimenovan in ni samodejno dodan novim uporabnikom.

Končne mobilne gradnje in dejanska namestitev na telefon imajo ločena dokazila v [stanju testnih izdaj](release/TEST_RELEASE_STATUS.md).
