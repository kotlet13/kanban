# Vrt — grede, sezone in zasaditve

## Prenova 8. oktobra 2026

Uporabnik je izrecno potrdil prenovo s poudarkom na zelenjavnih gredah in kolobarju ter vključitev v novo interno Android izdajo. Izvedba in končno preverjanje sta zaključena: celotni nabor **636 Flutter PASS**, 9 opt-in HTTP preskočenih, analiza brez napak/opozoril s 37 obstoječimi info. [Skupna dokazila](REMOTE_REMINDERS.md#končno-preverjanje-8-oktobra-2026) vključujejo resnično SQLite hrambo ter datume v različnih časovnih pasovih. Spodnja zgodovina prve izvedbe ni dokaz nove funkcionalnosti.

Načrt ostane ročno narisana razporeditev, ki se dopolni z letnimi sezonami. Posamezna greda ima več zasaditev: kultura, sorta, vnesena družina, načrtovano/dejansko, datumi setve, sajenja in pobiranja ter zapiski. Datumi so koledarski dnevi brez časovnega pasu, ne termini telefonskih opomnikov. Nova sezona je privzeto prazna. Uporabnik lahko izrecno kopira kulture iz prejšnje sezone; nastanejo novi načrtovani vnosi z novimi ID-ji, brez prejšnjih datumov in brez pretvorbe stare zgodovine v dejansko zasaditev novega leta.

Grede ohranijo trajne identifikatorje, zato je zgodovina vezana na isto gredo skozi leta. Razpored je skupen sezonam, ne vsakoletna kopija geometrije. Arhiviranje območja ohrani njegove zasaditve. Obstoječe risbe, imena, zapiski in koordinate se pri branju starega formata ne izgubijo.

Kolobar je informativna primerjava uporabnikovih zapisov: pri isti gredi pokaže ponovitev prepoznane družine v dejanskih zasaditvah zadnjih treh let. Pretekli načrti niso dokaz dejanske zasaditve. Prazna ali nepoznana družina ne pomeni »kolobar je primeren«; aplikacija ne ugiba družine iz imena kulture in ne pripravlja strokovnega samodejnega načrta. Slovenski oznaki bučevke in narcisovke sta preverjeni v [seznamu družin Botaničnega vrta Univerze v Ljubljani](https://www.botanicni-vrt.si/seznam-rastlin/rastline-po-druzinah).

Vrt ostane na napravi, brez povezovanja s strežniškimi prostori. Razširjena vrtna vsebina uporablja različico 2 znotraj obstoječe lokalne baze in formatov kopij. Novi bralnik sprejme stare vrtove; stari bralnik nov format zavrne in ga ne sme tiho skrajšati. Obnova, revizijski konflikti in brisanje ostanejo transakcijski. Fotografije, samodejni setveni koledar, fizično merilo in deljenje niso del te prenove.

### Preizkus nove izdaje na telefonu

1. Odpri obstoječi vrt in preveri imena, zapiske ter razpored gred. Izberi gredo, poskusi ročice in način povečave/premika. Podatki so še vedno lokalni.
2. Dodaj sezono, vanjo kulturo, sorto, družino in datume. Po zaprtju obrazca uporabi še **Shrani vrt**, nato ga ponovno odpri.
3. Dodaj drugo sezono, preklapljaj med letoma ter preveri zgodovino iste grede. Kopiranje kultur mora biti izrecno, z novimi načrtovanimi vnosi; prejšnje dejanske zasaditve ostanejo.
4. Za preverjanje opozorila uporabi isto prepoznano družino kot pri dejanski zasaditvi pretekle sezone. Opozorilo je pomoč pri pregledu lastnih vnosov, ne celovit setveni načrt.
5. Znova odpri aplikacijo brez povezave in preveri vrt. Naredi šifrirano kopijo ter pred morebitno obnovo preglej njen predogled; nove kopije potrebujejo novo različico aplikacije.

Nova Android interna izdaja **1.1.3 (6)** je aktivno objavljena za domači (15). Fizični preizkus tega novega toka še čaka uporabnika. Prejšnji preizkusi spodaj veljajo za prvotno izvedbo.

## Zgodovina prve lokalne izvedbe

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
