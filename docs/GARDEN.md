# Vrt — grede, sezone in zasaditve

## Nadgradnja prizora — 14. oktober 2026

Obstoječi vrt se odpre v celozaslonskem, interaktivnem prizoru. Grede imajo
lesene robove in zemljo, rastline pa vektorske ilustracije (korenje, paradižnik,
solata, zelje, čebula, paprika, buča, fižol in nevtralna rastlina). Vzorčnih vrtov
ali zasaditev v uporabniško bazo ne dodajamo. Zasnova uporablja kodo Canvas,
brez novega SDK, knjižnice, omrežnega prenosa ali bitmap sredstev.

Dotik oziroma klik grede odpre njene zasaditve in zgodovino istega trajnega ID,
vključno s prejšnjim letom. Gumb **Grede in zgodovina** zagotavlja seznam tudi
za zelo majhne ali prekrivajoče se grede ter privzeto zložene arhivirane grede.
Prizor podpira približevanje z dvema prstoma, premik, gumbe za povečavo/ponastavitev
in tipkovnico (Tab/Enter ter Ctrl oziroma Command z +/−). **Uredi razpored** je
ločeni pogled za risanje, premikanje in raztezanje gred ter natančne obrazce.
Oba pogleda uporabljata isti osnutek. Preklop pogleda, odpiranje zgodovine ali
približevanje ne zapišejo podatkov; **Shrani vrt** je izrecen trajni zapis.

Nov vrt zahteva širino in dolžino v metrih (0,1–10.000). Stari vrtovi obdržijo
izvirne koordinate brez izmišljenega merila; mere lahko lastnik doda pozneje.
Geometrija ostaja normalizirana in skupna vsem sezonam. Z določenim merilom
obrazec gred uporablja metre, prizor pokaže približno velikost, izbrana greda
v urejevalniku najbližji razmik, podrobnosti pa razmike do drugih aktivnih gred.
Razmik je razdalja med najbližjima robovoma, tudi diagonalno; prekrivanje pomeni
nič. Preimenovanje ne zaokroži prvotne geometrije.

Zasaditev ima izbirno ilustracijo, razmik med rastlinami (1–1.000 cm) in
nastavljiv čas do polne velikosti ilustracije (1–730 dni, privzeto 60).
Prikaz rasti uporablja **dejansko** zasaditev, vneseni datum sajenja oziroma
setve in koledarske dneve; brez datuma ali pri načrtu ostane majhna rastlina.
To je uporabniku pojasnjena vizualna ocena, brez obljube agronomske natančnosti,
zrelosti ali pridelka. Izbira ilustracije ne ugiba botanične družine.
Gostota prizora sledi razmiku, z omejenim številom ikon zaradi preglednosti in
odzivnosti; risba ni popis posameznih rastlin.

**Označi kot pobrano** shrani izrecno zastavico in današnji koledarski datum ter
odstrani samo to zasaditev iz prizora. Trajni ID, kultura, sorta, družina,
prejšnji datumi, razmik, ilustracija, zapiski in zgodovina ostanejo. Greda je
vizualno prazna, ko so pobrane vse njene zasaditve izbrane sezone. Napačno oznako
je mogoče vrniti med rastoče; zabeleženi datum ostane dosegljiv v obrazcu. Sam
stari datum pobiranja nikoli samodejno ne označi zasaditve kot pobrane.
Kopiranje sezone ohrani nastavitve ilustracije in razmika, ustvari nove ID-je in
načrtovane zasaditve brez datumov in brez oznake pobiranja.

### Pogodbe in združljivost

Notranji dokument vrta **3** doda par `widthMeters`/`heightMeters` ter v vsaki
zasaditvi `harvested`, `spacingCm`, `illustration`, `visualGrowthDays`. Različica
3 strogo zahteva vse svoje ključe; nepoznana polja, napačne mere in neskladna
oznaka pobiranja se zavrnejo. Prebrani dokument 3 ohrani različico tudi po
ponastavitvi nastavitev. Obstoječi vrt brez novih podatkov še vedno izpiše
nespremenjeni format 2. Bralnik sprejme prvotni format 1 in sezonski format 2.
Vrtna zbirka 3 sprejme mešanico dokumentov 2/3, zbirki 1/2 ostajata berljivi.

Za skupni vrt novi dokument zahteva **record6/sync6**. Odjemalec zavrne zapis na
starejši strežnik pred nastankom operacije; novega dokumenta ne skrajša na v2.
Strežnik ob prvem takem zapisu zviša zahtevano pogodbo obsega na 6 in starejšemu
bralniku zavrne prenos. Izvirne čakajoče operacije formata 2 se prek novega mostu
prenesejo nespremenjene. Poskus v3 → v2 nad obstoječim skupnim vrtom je zavrnjen.
Globalni formati kopij in lokalna schema so del skupne nadgradnje; vrtnarska
vsebina ne zahteva lastne SQL migracije. Obnova ostaja atomarna, brez starega
strežnika in z revizijsko zaščito proti zastarelemu odprtemu urejevalniku.

Pravice se preverjajo ob zapisu kot prej; bralec nima gumbov za spreminjanje,
pobiranje, novo zasaditev ali brisanje. Menjava prostora/računa zavrne stari
osnutek. Arhiviranje lokalnega prostora ohrani branje, vendar takoj izključi
urejanje odprtega vrta; transakcijska kontrola zavrne zapis v arhiviran, povezan
ali izbrisan prostor tudi z novo revizijo zbirke. Izbris prostora ne omogoči
ponovnega nastanka podatkov iz starega osnutka. Odprtje, zgodovina, povečava in prazna scena ne sprejmejo pravil
skupnega prostora ali povzročijo sinhronizacijskega zapisa.

### Dokazi in meje

- Obstoječi in novi vrtni podatkovni/UI nabor: **78 PASS**, vključno z dejansko
  SQLite ponovno otvoritvijo, JSON/šifrirano obnovo, record6 zaščito, tipkovnico,
  pinch, meritvami, pobiranjem ter zastarelim osnutkom po lokalnem arhiviranju,
  povezovanju in izbrisu prostora; `build/qa/garden-upgrade-final.log`.
- Dejanski HTTP na izoliranem lokalnem FamilyHub: **20 PASS**, nova sintetična
  računa/obseg, druga naprava/član, ohranitev vseh bajtov polj, pobiranje,
  ponovitev, zastarela revizija, zavrnitve pravic/stare pogodbe/napačnih polj in
  prepoved tihega znižanja formata. `server/tests/garden-scene-integration.php`,
  `build/qa/garden-scene-php.log`; ni posega v gostovane podatke.
- Renderirani in pregledani dejanski widget prizori 320 pri 2×, 390 in 1280:
  `build/qa/garden-scene/garden-scene-{320,390,1280}.png`. Uporabljeni so samo
  pomnilniški vzorčni podatki. Ozka postavitev ohrani leto in dostopne gumbe;
  normalni prizor nima prepoznavalnika premika grede, ki bi prestrezal pinch.
- Ciljna analiza novih vrtnih datotek brez ugotovitev. Fizični Android/iPhone,
  VoiceOver/TalkBack in native macOS preizkus te izvedbe niso s tem potrjeni;
  Windows/Linux sta po aktualnem naročilu odložena. To ni dokaz objave v trgovini.

Pri zasnovi sta bili prebrani aktualni Applovi smernici
[Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)
in [Modality](https://developer.apple.com/design/human-interface-guidelines/modality):
običajni dotik/pinch, vidna vrnitev, alternativa gestam in kratke podrobnosti v
zapirljivem listu, z ohranjenim neshranjenim osnutkom.

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
