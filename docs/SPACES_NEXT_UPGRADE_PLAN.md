# Naslednja nadgradnja: prostori, organizacije in povezane finance

**Dopolnitev 10. oktobra:** pravila članstva spodaj so zgodovinski načrt politike 2. Nova uporabnikova odločitev v [uskladitvi deljenja](SPACE_SHARING_ALIGNMENT.md) določa polne pravice članov celotnega prostora nad njegovo skupno vsebino in vsemi projekti; povabilo samo v projekt ostane ozko. Ta nova odločitev ima prednost, njen prehod in izvedba pa se preverjata ločeno.

Datum dogovora: **9. oktober 2026**. Status: **izdelano in avtomatizirano preverjeno v izvoru; fizični preizkus in izdaja sledita ločeno**. Uporabnik je po dopolnitvi zahteve o izgubi strežnika naročil začetek nadgradnje. Spodnji načrt določa cilj; dejanske spremembe, preverjanja in preostale vrzeli vodi [izvedba nadgradnje prostorov](SPACES_UPGRADE_IMPLEMENTATION.md). Izhodišče in še aktivna interna Android izdaja sta **1.1.10 (13)**; dosedanje izdajne dokaze vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md).

Uporabnik je potrdil spodnjo zasnovo in jo dopolnil s pravilom: **član projekta organizacije vidi vse finance tega projekta; skupina vodij organizacije vidi vse njene projekte in njihove finance**. Ta odločitev za organizacijske projekte nadomesti prejšnji predlog dodatnega ločenega dovoljenja za branje projektnih financ. Ne spreminja zasebnosti osebnih podatkov ali drugega gospodinjstva. Pravice urejanja niso samodejno enake pravicam branja.

## 1. Pomen prostorov

Prostor določa pripadnost podatkov in sodelovanje. Lokalna hramba oziroma sinhronizacija je stanje istega prostora, ne njegova vrsta. Celota je **uporabnikova zbirka prostorov**; naziv **Osebno** uporabljamo za njegov zasebni prostor, ne za vse organizacije in gospodinjstva skupaj.

| Vrsta | Namen | Področja |
| --- | --- | --- |
| Osebno | Zasebna organizacija posameznika. | Dogodki, opravila, projekti, finance. |
| Gospodinjstvo | Skupno vsakdanje življenje skupine ljudi. | Vrt, osebe, finance, nakupi, projekti, dogodki, opravila. |
| Organizacija | Vodenje dela, projektov in financ organizacije. | Finance s stroški in prihodki, projekti, dogodki, opravila. |

Vrstni red področij še ni dokončen. Danes in Koledar sta pogleda na zapise izbranega prostora, Obvestila pa center dogajanja z jasno označenim izvorom in prejemnikom. Vsi je združeni pregled dovoljenih prostorov; ni lastnik podatkov in vanj ne ustvarjamo zapisov brez izbire dejanskega prostora.

Projekt pripada določenemu prostoru, pri organizaciji pa je tudi meja članstva in dostopa. Samostojni deljeni projekti iz sedanje izvedbe ostanejo dostopni do izrecno določene preslikave; ne pripišemo jih samodejno novi organizaciji ali gospodinjstvu.

## 2. Članstva in vidnost organizacije

| Uporabnik | Projekt, katerega član je | Finance tega projekta | Drugi projekti organizacije in njihove finance |
| --- | --- | --- | --- |
| Povabljeni, ki povabila še ni sprejel | Še brez dostopa. | Še brez dostopa. | Brez dostopa. |
| Član projekta po sprejemu povabila | Vidi projekt in njegovo vsebino. | Vidi vse projektne finance brez dodatnega finančnega povabila. | Samo ob članstvu v drugih projektih ali vlogi vodje organizacije. |
| Član skupine vodij organizacije | Vidi vse projekte organizacije. | Vidi vse njihove finance. | Vidi vse obstoječe in prihodnje projekte organizacije ter njihove finance. |
| Član organizacije brez projektnega članstva in brez vodstvene vloge | Članstvo v organizaciji samo ne odpre vseh projektov. | Brez samodejnega dostopa. | Brez samodejnega dostopa. |

- Vodje organizacije so skupina oziroma vloga znotraj organizacije, ne skrbniki celotnega strežnika. Njihov dostop do projektov se izpelje iz te vloge; ni treba ročno vabiti vsakega vodje v vsak nov projekt.
- Vabilo jasno pove, da članstvo vključuje vpogled v vse finance projekta. To velja tudi za projektne finančne podrobnosti in priponke, ne pa za zasebno stanje plačnikove kartice ali osebne transakcije zunaj projekta.
- Matrika določa **branje**. Urejanje/brisanje finančnih zapisov, potrjevanje povračil, upravljanje članov in dodeljevanje vodstvene vloge dobijo ločena pravila pred izvedbo. Osebni plačnik, avtor vnosa in nosilec stroška niso ista vloga.
- Pravilo se uveljavi na strežniku in pri lokalni projekciji, sinhronizaciji, izvozu, priponkah, obvestilih in odpiranju povezav. Obstoječega ločenega finančnega API ne obidemo; njegove učinkovite pravice uskladimo z novo matriko.
- Po odvzemu vodstvene vloge uporabnik ohrani samo dostop iz drugih veljavnih članstev. Po odstranitvi iz projekta izgubi njegov dostop, razen če ga še ima kot vodja. Ohranitev lokalnih kopij brez povezave in ponovni pregled pravic sledita obstoječim pravilom preklica.
- Arhiviranje projekta ne sme obiti te matrike; zgodovinski podatki ostanejo dostopni upravičenim uporabnikom. Prenos projekta med organizacijama potrebuje posebej določeno spremembo pravic.

Gospodinjstva ohranijo izrecno določeno skupno finančno vidnost; projektni sodelavec organizacije ne postane član plačnikovega gospodinjstva. Izbira osebne kartice za plačilo ne odpre njene celotne evidence drugim članom projekta.

## 3. Lokalni začetek in povezava s strežnikom

1. Aplikacija brez računa omogoča ustvarjanje in urejanje osebnega prostora, gospodinjstva in organizacije. Podatki imajo trajno lokalno identiteto ter preživijo ponovni zagon in kopijo/obnovo.
2. V izboru prostora piše **Osebno**, ne Lokalna shramba. Povezava in stanje sinhronizacije sta ločeni informaciji. Enako velja za lokalno ustvarjeno gospodinjstvo ali organizacijo.
3. Ob koraku **Poveži in sinhroniziraj** uporabnik vidi, kateri obstoječi prostori se povezujejo s katerim računom/strežnikom. To je jasen začetek sinhronizacije, ne prikrit stranski učinek navadne prijave.
4. Obstoječi prostori dobijo strežniško povezavo, lokalni ID-ji in povezave med zapisi se ohranijo. Nov prostor in njegove zapise objavimo ponovljivo, brez podvajanja po izgubljenem odgovoru.
5. Če račun že vsebuje podatke, se prenesejo njegovi dovoljeni prostori. Enako ime ni dokaz, da gre za isti prostor ali osebo; združitev potrebuje preverjeno identiteto oziroma izrecno preslikavo s predogledom. Brez tihega prepisovanja.
6. Po začetni povezavi se dovoljene spremembe samodejno usklajujejo. Izpad omrežja ne ustavi lokalnega dela; čakajoče spremembe in konflikti imajo trajno evidenco. Odjava ali menjava računa ne smeta prenesti starega čakajočega dela pod novo identiteto.

Povezava s strežnikom sama ne pomeni deljenja osebnih podatkov z drugimi. Članstva se upravljajo ločeno. Tudi v sinhroniziranem načinu UI bere lokalno shrambo in ne čaka na celotno osvežitev računa, da odpre že razpoložljiv zapis.

### Trajna lokalna ohranitev tudi po izgubi strežnika

**Dodatna izrecna zahteva uporabnika, 9. oktober: tudi če strežnik trajno izgine, se podatki ohranijo na napravah.** Strežnik je namenjen sinhronizaciji in sodelovanju; njegova izguba ne sme povzročiti izgube ali zaklepa že razpoložljive lokalne vsebine. To velja za osebne podatke in upravičeno prenesene podatke gospodinjstev, organizacij ter projektov.

- Lokalno ustvarjeni in uspešno preneseni zapisi so v trajni shrambi, ne le v začasnem predpomnilniku. Izpad gostovanja, nedosegljiv naslov, napaka prijave ali potek strežniške seje jih ne izbrišejo, ne izpraznijo pogledov in ne zahtevajo dosegljivega strežnika za ponovno odprtje po zagonu aplikacije. Morebitni lokalni ključi za branje ne smejo biti dostopni samo prek starega strežnika.
- Pregledovanje, iskanje, lokalni opomniki in urejanje v okviru zadnjih znanih dovoljenj ostanejo mogoči. Nove spremembe se trajno shranijo; prikaz jasno pove, da niso sinhronizirane. Povabila, spremembe strežniških pravic, e-pošta in oddaljena dostava brez strežnika ne morejo biti potrjeni kot izvedeni.
- Enako velja za že prenesene priponke in datoteke: povezava URL ne šteje kot lokalno shranjena vsebina. Pred oznako popolne razpoložljivosti brez povezave preverimo zapise in priponke; nedokončane prenose ali pomanjkanje prostora pokažemo. Edine lokalne kopije ne odstranjujemo kot običajni predpomnilnik. Vsebine, ki je naprava nikoli ni prejela, po izgubi strežnika ne moremo obnoviti iz te naprave.
- Izvoz, šifrirana kopija in obnova lokalno razpoložljivih podatkov morajo delovati brez starega strežnika, tudi po poteku seje. Vključijo podprte priponke, povezave, revizije in čakajoče spremembe; ne vsebujejo strežniških poverilnic. Sinhronizacija ni varnostna kopija za primer izgube same naprave.
- Omogočimo izrecno nadaljevanje v samostojnem lokalnem načinu z ohranjenim izvorom podatkov. Poznejša povezava z nadomestnim strežnikom potrebuje predogled prenosa, preverjanje identitete in pravic ter preprečevanje podvajanja. Starih članstev, žetonov in čakajočih operacij ne pošiljamo nespremenjeno drugemu strežniku. Uporabnik ne postane skrbnik starih skupnih prostorov samo zaradi izpada.
- Ponovna dosegljivost, prazna obnova ali druga namestitev na istem URL ne smejo samodejno izbrisati lokalnih podatkov. Ločimo identiteto strežnika, veljavne izbrise, nepopolne odgovore in obnovo baze; ob neskladju ohranimo lokalno vsebino ter zahtevamo uskladitev s predogledom.
- Nedosegljivost ali potek seje nista potrjen preklic članstva. Že potrjenega preklica pa ne obidemo z odklopom ali obnovo stare kopije: ravnanje s tako vsebino sledi pravilom preklica, zavrnjeno čakajoče delo ostane ohranjeno in se ne deli pod drugo identiteto. Ta razlika ne sme blokirati običajnega lokalnega dela ob izginulem strežniku.

Obvezni preizkus: po uspešni sinhronizaciji odklopimo strežnik, ponovno zaženemo aplikacijo in simuliramo potek seje. Preverimo branje, urejanje, priponke, lokalne opomnike, kopijo ter obnovo na drugi napravi brez starega strežnika. Nato preverimo vrnitev istega strežnika, prazno obnovo in zamenjavo strežnika; noben korak ne sme tiho izgubiti podatkov ali podvojiti finančnih zapisov. Preizkus znanega preklica članstva ostane ločen. Avtomatizirane dokaze že izvedenih poti vodi [izvedbeni dnevnik](SPACES_UPGRADE_IMPLEMENTATION.md); fizični preizkus dveh telefonov še sledi. Skupne priponke še nimajo dokončane uporabniške poti. Samostojna pretvorba obnovljenih finančnih prenosov in povezanih plačil je omejena: izvirniki ostanejo v šifriranem arhivu, nepopolni finančni pogled je izrecno označen.

## 4. Gospodinjstva in prihodnja povezana družina

Prvi uporabniški tok naj bo preprost: ustvari eno gospodinjstvo. Podatkovni model že zdaj dopušča več gospodinjstev; ne vsebuje pravila »en uporabnik = eno gospodinjstvo«.

- Vsako gospodinjstvo ima trajni ID, ime, izbirni naslov, članstva ter svoje podatke.
- Isti uporabniški račun lahko pripada več gospodinjstvom. Oseba brez računa, npr. otrok, je ločen pojem od uporabnika in dovoljenja za prijavo.
- Predvidimo izrecno povezavo iste osebe med gospodinjstvi, brez samodejnega združevanja po imenu in brez samodejnega deljenja vseh njenih zapiskov.
- Družina lahko pozneje povezuje več gospodinjstev na različnih naslovih. Naslov ni identiteta družine ali meja dovoljenj.
- Poznejša faza omogoči deljene dogodke, opravila, projekte in dogovorjene finance med gospodinjstvi. Zapis ima določen izvor/lastništvo in izrecne prejemnike; spremembo deljenega dogodka morata videti obe strani brez dveh nepovezanih kopij.

V naslednjo izvedbo sodijo model brez omejitve na eno gospodinjstvo ter jasne identitete in lastništvo. Celoten vmesnik za povezovanje gospodinjstev, skupni družinski pregled in deljenje med njimi so **poznejša faza**, ne obljuba te izdaje.

## 5. Osebno plačan strošek organizacije

Dogovorjeni scenarij: uporabnik s svojo kreditno kartico plača domeno za organizacijo oziroma njen projekt. Organizacija mora videti svoj strošek, uporabnik svojo bremenitev, gospodinjstvo pa dogovorjeno vključeno bremenitev in morebitno povračilo.

Ločimo:

- **Nosilca stroška**: organizacijo in po potrebi konkretni projekt.
- **Plačnika oziroma prejemnika**: osebo, ki dejansko plača ali prejme denar.
- **Finančni račun**: kartico, bančni račun ali drug vir plačila, s svojim lastnikom in vidnostjo.
- **Avtorja vnosa**: kdo je podatek vnesel ali uredil.
- **Povračilo**: pričakovani znesek, izvedena povračila in še odprti znesek, povezani z istim stroškom.

Predlagani obrazec: »Plačal sem osebno« → izbor računa/kartice → »Pričakujem povračilo« → izbor vključitve v gospodinjski pregled. To je izvedbeni predlog za potrjeno potrebo; osebne bremenitve se ne razkrijejo vsem gospodinjstvom samodejno. Primer brez pričakovanega povračila potrebuje izrecno obravnavo, ne tihe pretvorbe v dolg.

### Primer: domena 30 EUR

| Pogled | Ob plačilu | Po celotnem povračilu |
| --- | --- | --- |
| Projekt organizacije | Strošek domene 30 EUR; plačal uporabnik; odprto povračilo 30 EUR. | Isti strošek ostane 30 EUR; odprto povračilo je 0 EUR. |
| Osebno | Bremenitev izbranega računa/kartice 30 EUR; pričakovano povračilo 30 EUR. | Prejeto povračilo zapre pričakovani znesek; ne šteje kot nov zaslužek. |
| Izbrano gospodinjstvo | Vidna vključena bremenitev z oznako »založeno za organizacijo« in pričakovano povračilo. | Vidno prejeto povračilo; ni drugega gospodinjskega nakupa iste domene. |
| Vsi | Jasno ločeni strošek, bremenitev in pričakovano povračilo, vsak z izvorom. | Povezanih prikazov ne sešteje v več stroškov ali več prihodkov. |

Gre za en povezan poslovni dogodek z zapisi/projekcijami v ustreznih prostorih. Izvedba uporablja en kanonični strošek ter ločeno evidenco plačila in povračil; [pogodba povezanih plačil](server/linked-payments-api-contract.md) določa dostop in različice. Drugi prostor ne bere zasebnih zapisov, do katerih nima dostopa. Če eden od prostorov še ni sinhroniziran ali zapisuje brez povezave, je delni izid viden in ponovljiv, ne lažno potrjen kot popoln.

Pravila za izvedbo:

- Zneski so v najmanjših denarnih enotah z valuto. Različne valute ostanejo ločene, dokler ni določen izrecni način pretvorbe.
- Podprta morajo biti delna povračila in sled sprememb; ponovitev zahteve ne podvoji stroška ali izplačila. Več plačnikov in razdelitev enega računa nista še potrjen začetni obseg.
- Skupni prikaz loči strošek, dejansko plačilo/bremenitev in povračilo. Ne sešteva na slepo vseh finančnih vrstic iz vseh prostorov.
- Bremenitev kreditne kartice ni nujno isti trenutek kot odtok z bančnega računa. Poznejše plačilo kartičnega izpiska istega nakupa ne ustvari še enkrat.
- Načrtovani strošek, povezan z opravilom, še naprej sledi roku opravila. Dejanski datum plačila in datum povračila sta ločena; sprememba roka ne prestavi že izvedenega plačila.
- Osebni ali gospodinjski prikaz prejme samo dovoljene podatke o konkretnem plačilu/povračilu. Projektni člani vidijo vse finance projekta, ne pa drugih osebnih transakcij, celotnega stanja kartice ali zasebnih prilog zunaj projekta.

## 6. Meni, pregledi in obvestila

- **Dom** odstranimo kot podvojeni projektni pogled. Gospodinjstvo predstavlja prostor zgoraj; obstoječa oznaka domačega projekta se ohrani kot kategorija/filter pri Projektih.
- **Načrti** postanejo **Opravila**, brez podvojenih podzavihkov Projekti in Koledar. Ista sprememba se smiselno prenese v telefonski meni, tablično navigacijo in namizje.
- Področja sledijo tabeli prostorov. Organizacija v Danes in Koledarju dejansko združuje dogajanje svojih dovoljenih projektov; ne vrača istega seznama projektov za vsak menijski cilj.
- **Vrt** dobi pripadnost gospodinjstvu, lokalno hrambo ter izbirno sinhronizacijo in deljenje po pravicah prostora. Označba »lokalno« je prehodno pojasnilo sedanje izvedbe, ne končni nadomestek povezave s prostorom.
- **Račun** skrbi za prijavo, strežniško povezavo in sinhronizacijo. **Nastavitve prostora** skrbijo za člane, povabila in vloge, tudi vodje organizacije. Podvojene vsebinske poglede odstranimo iz računa.
- **Osebe** v gospodinjstvu ostanejo evidenca ljudi in njihovih obveznosti; **Člani** pomenijo dejanski dostop uporabniških računov. Ustvarjanje osebe ne ustvari dostopa.
- Obvestila o novih in osebno dodeljenih opravilih ostanejo različna. Projektne/dnevne spremembe in finančna povračila odprejo pravi zapis/prostor. Isti povezani dogodek istemu prejemniku ne ustvari podvojenih opozoril zaradi več prikazov.
- Pravica vodje videti vse ne pomeni samodejne vključitve e-pošte/push za vsako spremembo vseh projektov. Preference dostave ostanejo ločene; nakupovalni artikli privzeto ne pošiljajo posamezne e-pošte.

## 7. Prehod iz sedanje izvedbe

Pregled kode pri 1.1.10 je pokazal: lokalni Dom filtrira domače projekte, v skupnem prostoru pa odpre Projekti; organizacija pri več delovnih področjih vrne seznam projektov; Vrt uporablja neodvisno lokalno hrambo; Načrti podvajajo Projekte in Koledar. To so izhodiščne vrzeli, ne stanje po tej nadgradnji.

Pred spremembo hrambe ali pravic pripravimo:

1. Popis dejanskih modelov, shem, API zmožnosti, obstoječih članstev in finančnih politik. Določimo nove verzije pogodbe ter vedenje starega odjemalca/novega strežnika in obratno.
2. Kopijo in preverjeno obnovo; nato ponovljivo selitev s trajnimi ID-ji in preslikavo obstoječih osebnih/skupnih prostorov, projektnih korenov, operacij in povezav.
3. Izrecno preslikavo obstoječih vrtov in osebnih nakupovalnih seznamov. Nova razdelitev menija ne sme skriti ali izbrisati teh podatkov. Pred dodelitvijo gospodinjstvu uporabnik vidi cilj in posledico deljenja; do takrat so stari lokalni podatki še dosegljivi.
4. Pregled prehoda obstoječih organizacijskih projektov na pravilo vidnosti vseh projektnih financ. Seznam uporabnikov, ki s tem dobijo širši vpogled, mora biti v predogledu migracije. Dokument ne spreminja živih dovoljenj; preklop je ločen preverjen izvedbeni korak.
5. Ohranitev starih kopij, čakajočega dela in podatkov, ki jih starejši odjemalec še ne razume. Neznanega formata ne ponastavimo. Zavrnjenega dela ne preusmerimo v drug račun/prostor.

Kanboard ostane izbirni strežnik, razširjen s FamilyHub. Nove modele dodajamo v lastne tabele vtičnika z migracijami; podatkov ne vračamo v razrezane metapodatke. Gostovanje mora ostati izvedljivo na cPanelu brez stalnega procesa. Ta načrt ne vključuje posega v produkcijo, spremembe različice aplikacije ali nove trgovinske objave.

## 8. Vrstni red izvedbe in merila dokončanosti

| Korak | Rezultat | Ključni dokaz |
| --- | --- | --- |
| 1. Pogodba modela in pravic | Prostori, članstva, vodje organizacije, finančne povezave in načrt migracije. | Matrika dovoljenih/zavrnjenih dostopov in dogovorjene verzije API; razrešena vprašanja spodaj. |
| 2. Lokalna osnova prostorov | Vse tri vrste nastanejo brez računa, zapisi imajo pravilen prostor; Vrt se varno poveže z gospodinjstvom. | CRUD brez omrežja, ponovni zagon, kopija/obnova, nadgradnja obstoječih podatkov brez izgube. |
| 3. Navigacija in pregledi | Meni sledi vrsti prostora; Opravila brez podvojitev; pravi organizacijski Danes/Koledar in Vsi. | Telefon 320/390 px, tablica 700 px, namizje 1280 px; daljša imena, večja pisava, Nazaj ter noben prikaz tujega prostora. |
| 4. Povezane finance | Organizacijski strošek z osebnim plačilom, vključitvijo v gospodinjstvo in povračilom. | Primer domene 30 EUR, delno/celotno povračilo, kartica, brez dvojnega štetja, ločene valute in dovoljena vidnost. |
| 5. Sinhronizacija in sodelovanje | Varna prva povezava lokalnih prostorov, uskladitev obstoječega računa, projektno članstvo, vodstveni dostop in trajna lokalna ohranitev po izgubi strežnika. | Dva računa/napravi, izgubljeni odgovori, sočasne spremembe, preklic člana/vodje, menjava računa; izginuli strežnik + restart + potek seje + lokalno urejanje/kopija/obnova; varna ponovna povezava ali zamenjava strežnika. |
| 6. Obvestila in zaključni preizkus | Pravilni prejemniki, povezave in nastavitve dostave za nove tokove. | Center/push odpre pravi zapis; brez podvojitev ali zasebnih podatkov napačnemu prejemniku; fizični Android preizkus. |

Koraka 4 in 5 se zaključita s skupnim preizkusom: **TriparNA → projekt → uporabnik plača domeno → gospodinjstvo vidi bremenitev → organizacija povrne denar → vsi dovoljeni pogledi se uskladijo**. Vrt in druge skupne vsebine dobijo svoje teste sinhronizacije; finančni primer jih ne nadomesti. Interno izdajo pripravimo po preverjeni izvedbi kot ločen izdajni korak.

Glavni agent vodi načrt, pogodbe, integracijo in pregled. Izvedbo razdeli med podagente **gpt-6.1-sol / high** z jasnim lastništvom področij/datotek; skupne modele in lokalizacijo ureja dogovorjeni lastnik. Nove domenske logike ne kopičimo v `organizer_shell.dart`.

## 9. Sprejete izvedbene odločitve in poznejše razširitve

- Vodstveno vlogo določi lastnik organizacije. Branje projektnih financ sledi potrjeni matriki; urejanje in potrjevanje povračil zahtevata finančno pravico pisanja izvora. Splošne organizacijske finance berejo lastnik in vodje; prej izrecno dodeljene pravice se ohranijo.
- Osebno plačilo brez pričakovanega povračila ne ustvari terjatve. Že povezanim stroškom ne dovolimo tihe spremembe zneska, valute ali brisanja; varne spremembe naslova, opomb in načrtovanega roka ostanejo mogoče. Storno oziroma popravljanje že izvedenega plačila je poznejši, še neizdelan tok.
- Vključitev v gospodinjstvo se določi izrecno za konkretno plačilo. Zasebni ID, naziv in stanje osebnega računa se ne delijo s projektom ali gospodinjstvom.
- Stari vrtovi in nakupovalni seznami ostanejo dostopni ter dobijo izrecno ciljno gospodinjstvo. Samostojni deljeni projekti ostanejo v svojem obsegu; ni samodejne združitve po imenu.
- Prva objava lokalnih prostorov ohrani ID-je, predogled in ponovljivost. En običajni zasebni prostor uporablja obstoječi `personal.ensure`; dodatni osebni prostori iz obnovljene kopije ostanejo ločeni. Povezava dveh strežnikov, več plačnikov in povezovanje več gospodinjstev v družino ostajajo poznejše razširitve.

Podrobna pravila za delne izide, ponovno prijavo, obnovo in finančne omejitve so v [izvedbenem dnevniku](SPACES_UPGRADE_IMPLEMENTATION.md).

## Povezana dokumentacija

- [Glavni načrt prenove](RENOVATION_PLAN.md)
- [Dejansko izvedene nadgradnje in izdaje](UPGRADE_IMPLEMENTATION.md)
- [Lokalna uporaba, zasebna sinhronizacija in obnova](PERSONAL_SYNC_AND_RECOVERY.md)
- [Pogled Vsi in center obvestil](ALL_SPACES_AND_INBOX.md)
- [Sedanja izvedba Vrta](GARDEN.md)
- [Strežniška pogodba Native API](server/native-api-contract.md)
