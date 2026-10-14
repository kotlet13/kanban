# Opombe za nadgradnje in popravke

V tem klepetu zbiramo in dopolnjujemo opombe za prihodnje nadgradnje in
popravke Jivie. Začetno zbiranje je potekalo brez popravkov. Uporabnik je
14. oktobra 2026 nato izrecno naročil implementacijo, commit in push po
zaključenih sklopih ter končno javno Android izdajo in iOS TestFlight.

## Potrjene odločitve za izvedbo

- Brisanje odstrani celotno pripadajočo vsebino prostora/projekta; nadrejeni
  prostor, drugi prostori, uporabniški računi in dostop do strežnika ostanejo.
- Po zaznanem odvzemu dostopa skupna vsebina ni več dosegljiva; lastne še
  neposlane osnutke ohraniti ločeno za izvoz, brez samodejnega trajnega izbrisa
  vse lokalne shrambe.
- Odstranitev člana prekliče dostop do prostora in njegovih projektov, tudi
  prek ločenih povabil. Lastništvo pred odstranitvijo ustrezno prenesti ali
  jasno preprečiti odstranitev do rešitve lastništva.
- Vrt je slikovit in barvit celozaslonski prikaz, z vizualno rastjo po dnevih,
  zgodovino grede skozi leta in pobiranjem, ki ohrani zgodovino ter izprazni
  prikaz zasaditve. Ob ustvarjanju fizične mere vrta v metrih; prosto
  postavljanje in raztegovanje gred s približnimi merami; nastavljiv razmak
  rastlin in viden razmak med gredami. Začetni nabor osnovnih vrtnin.
- Za Vrt GPT-6 Astra/zelo visoko razmišljanje, za druge podagente GPT-6.1
  Sol/high. Windows in Linux sta za to fazo odložena; Android/iOS/macOS
  in smernice iOS ostanejo del izvedbe.

## Obravnava na vseh platformah

Dogovorjeno 14. oktobra 2026. Vse obstoječe in prihodnje opombe obravnavati z
vidika Androida, iOS-a, macOS-a, Linuxa in Windowsa. Telefonski posnetki so
izhodišče za opažanja, obseg rešitve pa vključuje vseh pet platform.

Pri vsaki težavi preveriti prikaz, navigacijo in vedenje ter primernost za
dotik, miško in tipkovnico. Upoštevati razlike med mobilnimi in namiznimi
postavitvami ter platformne posebnosti. Uspeh na eni platformi ne potrjuje
ostalih; ob prihodnji izvedbi ločeno zapisati, kaj je bilo preverjeno in kaj
ostaja nepreverjeno na posamezni platformi.

Pri vseh spremembah UX posebej upoštevati Applove Human Interface Guidelines
za iOS. Ob načrtovanju preveriti aktualne smernice za prizadete vzorce,
predvsem navigacijo, menije, obrazce, geste, dostopnost in potrjevanje
destruktivnih dejanj. Skupno vedenje aplikacije prilagoditi pričakovanjem
uporabnikov posamezne platforme; predlagane postavitve iz teh opomb je treba
pred izvedbo presoditi tudi z vidika iOS.

## 1 Ogled vnosa gesla

Zabeleženo 14. oktobra 2026. Status: lokalno izvedeno; fizični prikaz in nova izdaja še sledita.

Pri vnosu gesel omogočiti ogled vnesenega gesla, da uporabnik lažje preveri
pravilnost vnosa. Predlog prikaza: ikona očesa za preklop med skritim in vidnim
geslom; geslo je ob odprtju obrazca skrito.

## 2 Opomniki glede na rok opravila

Zabeleženo 14. oktobra 2026. Status: opomba za prihodnjo nadgradnjo.

Opomnike omogočiti nastaviti neposredno glede na rok na opravilu, brez
ločenega vnašanja datuma in ure opomnika. Predlog: izbira »ob roku« ali odmika
pred rokom, na primer 1 uro oziroma 1 dan prej. Ob spremembi roka opravila naj
se vezani opomnik ustrezno prestavi.

## 3 Odvečno besedilo v podrobnostih projekta

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka projekta
»Mansarda«. Status: lokalno izvedeno; fizični prikaz in nova izdaja še sledita.

Na zaslonu Prostor → Projekti → izbrani projekt je pod naslovom projekta in
nad razdelkom »Koledarski termin« blok »Okvirno trajanje«. Obvestili o
manjkajoči oceni dela in razpoložljivosti ter dolg odstavek »Upoštevamo preostalo
ocenjeno delo …« zavzamejo preveč prostora. To besedilo odstraniti iz glavnega
prikaza ali ga privzeto skriti za razširljivim pojasnilom oziroma ikono za
informacije. Končna izbira med odstranitvijo in skrivanjem še ni določena.

Točno mesto v izvoru:

- `lib/organizer/presentation/projects_page.dart`: metoda `_detail`, vključitev
  `ProjectPlanningSummary` pod naslovom projekta.
- `lib/organizer/presentation/planning/project_planning_summary.dart`:
  `ProjectCapacityPanel` pred koledarjem.
- `lib/organizer/presentation/planning/project_capacity_panel.dart`: izris
  naslova in obvestil v vrsticah 77–100 ter stalnega pojasnila
  `planningCapacityRule` v vrsticah 101–107. Dolgo pojasnilo se izriše za projekt
  (`phaseId == null`); prikaz posamezne faze ga nima.
- `lib/l10n/app_sl.arb`: besedila `planningCapacityTitle`,
  `planningCapacityRule`, `planningCapacityMissingEstimates` in
  `planningCapacityMissingAvailability`.

## 4 Zavajajoče sporočilo za prazen dan v koledarju projekta

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka projekta
»Mansarda«. Status: lokalno izvedeno; fizični prikaz in nova izdaja še sledita.

Pod izbranim dnevom v koledarju projekta se izpiše »V tem projektu še ni
opravil.«, čeprav ima projekt opravilo na drug datum. Sporočilo mora opisovati
izbrani dan, ne celotnega projekta. Želeno besedilo: »Za ta dan ni opravil na
tem projektu.«

Točno mesto: `lib/organizer/presentation/planning/project_calendar.dart`,
vrstice 256–260, veja `selectedEntries.isEmpty`. Uporablja prevod
`organizerNoMatchingTasks` iz `lib/l10n/app_sl.arb` (vrstica 133), ki ga uporablja
tudi splošni seznam opravil projekta v `projects_page.dart`. Za koledar je
potrebno ločeno besedilo, da sporočilo za prazen celoten projekt ohrani pravilen
pomen; ob izvedbi uskladiti tudi angleški prevod.

## 5 Arhiviranje v nastavitvah prostora

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka Utripa za
»Zavod Živi«. Status: opomba za prihodnji popravek.

Gumb »Arhiviraj« pod izbirnikom prostora ne spada na glavni vsebinski zaslon.
Prestaviti ga v nastavitve izbranega prostora. Sprememba velja tudi za druge
vsebinske zaslone, na katerih se isti skupni gumb prikazuje, med drugim za
podrobnosti projekta iz opombe 3.

Za zaslon Planer → Opravila velja poznejša, konkretnejša usmeritev iz opombe
10: arhiviranje in brisanje v meniju treh pik ob naslovu »Opravila« in oblaku
za sinhronizacijo.

Točno mesto: `lib/organizer/presentation/shared/sharing_workspace.dart`,
vrstice 425–449. Gumb je v skupnem ovoju pred izbiro vsebinskega prikaza
`switch (view)`, zato se pojavlja tudi nad Utripom. Uporablja `peopleArchive`
oziroma `peopleRestore` in kliče `archiveProjectScope` za izbrani obseg.
Pri prestavitvi ohraniti trenutni ciljni obseg, pravice in pomen arhiviranja.

## 6 Urejevalnik projekta glede na njegov prostor

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka urejevalnika
projekta »Zavod Živi« v organizaciji in njegove dopolnitve.
Status: opomba za prihodnji popravek.

Urejevalnik, odprt prek treh pik v projektu organizacije, ponuja »Osebno« in
»Dom«. Ti izbiri v tem kontekstu nimata smisla in zavajata glede pripadnosti
projekta. Projekt mora ostati vezan na svojo organizacijo; urejevalnik naj
jasno kaže ta kontekst.

Uporabnik želi urejevalnik projekta z možnostjo deljenja, urejanja mejnikov in
obdobja trajanja. Preurediti vsebino in vrstni red okoli teh projektnih
nastavitev ter odstraniti neustrezno izbiro »Osebno / Dom« za projekt
organizacije. Na posnetku že obstajata zložena razdelka »Načrtovani termin« in
»Faze in mejniki«; zahteva vključuje pregledno ureditev teh možnosti in
dostop do deljenja v istem urejevalniku. Natančna postavitev še ni določena.

Točno mesto in ugotovitev:

- `lib/organizer/presentation/organizer_editors.dart`, vrstice 480–500:
  `DropdownButtonFormField<ProjectArea>` se prikaže za vsak projekt, brez
  prilagoditve vrsti prostora.
- `lib/organizer/domain/organizer_models.dart`, vrstica 15: stara klasifikacija
  `ProjectArea` vsebuje samo `personal` in `home`.
- `lib/organizer/presentation/shared/collaboration_actions.dart`, metoda
  `project`: skupni projekt uporablja isti urejevalnik in vanj poda `area`.
  Shranjevanje ostane vezano na `scope.id`; izbira »Osebno / Dom« je polje
  projekta, ne dejanska izbira ali premik v drug prostor.

Pri prihodnji izvedbi prilagoditi urejevalnik dejanskemu prostoru in pravicam
deljenja; obstoječih projektov ali članstev ne seliti zaradi spremembe prikaza.

## 7 Odstranitev člana iz deljenja prostora

Zabeleženo 14. oktobra 2026. Status: zahteva za prihodnjo nadgradnjo in
preverjanje obstoječega vedenja.

Omogočiti odstranitev člana iz deljenja prostora. Od odstranitve naprej mora
izgubiti strežniški dostop do tega skupnega obsega in novih podatkov. Že
preneseni skupni podatki lahko ostanejo na njegovi napravi do naslednje
sinhronizacije, ko mora aplikacija zaznati odvzem dostopa. To ni izbris
uporabnikovega računa ali odvzem dostopa do strežnika in drugih dovoljenih
prostorov.

Pri prihodnjem preverjanju zajeti tudi podrejene projekte, napravo brez
povezave in njeno ponovno sinhronizacijo. Čakajoče spremembe odstranjenega
člana ne smejo obnoviti članstva ali dostopa; natančno ravnanje z lokalnimi
podatki po zaznanem odvzemu še določiti.

## 8 Povabila v arhiviran prostor

Zabeleženo 14. oktobra 2026. Status: vprašanje za prihodnje preverjanje.

Preveriti, kaj se zgodi pri pošiljanju povabila v neaktiven oziroma arhiviran
prostor: ali ga je mogoče poslati, ali ga prejemnik lahko sprejme in kakšen
dostop s tem dobi. Zajeti tudi povabilo, poslano pred arhiviranjem in sprejeto
po njem. Želeno končno vedenje določiti na podlagi ugotovitev; povabilo ne sme
tiho ponovno aktivirati prostora. Trenutno vedenje v tem klepetu ni preverjeno.

## 9 Brisanje prostorov in posameznih projektov

Zabeleženo 14. oktobra 2026. Status: zahteva za prihodnjo nadgradnjo in
preverjanje obstoječega vedenja.

Omogočiti brisanje prostorov in tudi posameznih projektov. Drugim članom lahko
že preneseni podatki ostanejo na napravi do naslednje sinhronizacije, ko mora
aplikacija zaznati izbris. Preveriti obseg izbrisa, povezano vsebino in ravnanje
s podrejenimi projekti; stare čakajoče spremembe ne smejo obuditi izbrisanega
prostora ali projekta.

Ob brisanju uporabniki ne smejo izgubiti dostopa do strežnika. Ohraniti njihove
račune, prijavo in dostop do drugih dovoljenih prostorov. Izbris posameznega
projekta ne sme izbrisati njegove organizacije ali gospodinjstva. Natančno
ravnanje z lokalnimi podatki po zaznanem izbrisu še določiti.

## 10 Arhiviranje in brisanje v meniju na zaslonu opravil

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka Planer →
Opravila za izbrani projekt »Spletna stran«.
Status: opomba za prihodnji popravek.

Odstraniti samostojni gumb »Arhiviraj« nad naslovom »Opravila«. Ob naslovu
»Opravila« in oblaku za sinhronizacijo dodati meni treh pik z možnostma
»Arhiviraj« in »Izbriši«.

Posnetek prikazuje seznam opravil projekta, ne urejevalnika posameznega
opravila. Arhiviranje in brisanje v tem meniju se nanašata na izbrani projekt
oziroma obseg, ki ga trenutno arhivira samostojni gumb. Obseg dejanja mora biti
jasen tudi uporabniku. Veljajo zahteve iz opombe 9: ohraniti račun, dostop do
strežnika in drugih prostorov ter nadrejeno organizacijo oziroma gospodinjstvo.

To je konkretnejša dopolnitev opombe 5 za zaslon opravil. Obstoječi samostojni
gumb izvira iz `lib/organizer/presentation/shared/sharing_workspace.dart` in
kliče `archiveProjectScope`.

## 11 Približevanje table in povečanje besedila v Idejniku

Zabeleženo 14. oktobra 2026. Status: uporabniška opažanja in zahteva za
prihodnjo nadgradnjo oziroma preverjanje.

Uporabnik pogreša približevanje table z dvema prstoma na telefonu
(`pinch to zoom`), saj je vstavljeno besedilo majhno. Preveriti delovanje in
dosegljivost te geste v dejanskem toku uporabe, tudi ob izbranem besedilnem
elementu. Opomba opisuje uporabniško težavo; ne predpostavlja, da približevanje
v izvoru še ni izvedeno.

Omogočiti tudi povečanje samega besedila, da na tabli ostane večje neodvisno od
trenutne povečave pogleda. Predlog: nastavitev velikosti pisave ali jasno
upravljanje velikosti izbranega besedilnega elementa. Povečanje se mora shraniti
kot sprememba elementa. Natančen način upravljanja še ni določen.

## 12 Meni za arhiviranje in brisanje ideje

Zabeleženo 14. oktobra 2026. Status: uporabniško opažanje in zahteva za
prihodnji popravek.

Uporabnik v Idejniku ne najde možnosti brisanja ideje; ni jasno, ali manjka ali
je skrita. Ob posamezni ideji dodati jasno dosegljiv meni treh pik z možnostma
»Arhiviraj« in »Izbriši«. Dejanji veljata za izbrano idejo, ne za njen prostor
ali posamezni besedilni oziroma risarski element na tabli.

Ob prihodnji izvedbi preveriti obstoječo možnost brisanja in podporo
arhiviranju ter meni uskladiti s pravicami urejanja v izbranem prostoru.

## 13 Arhivirane stvari v privzeto zloženem razdelku

Zabeleženo 14. oktobra 2026. Status: splošna zahteva za prihodnjo nadgradnjo.

Arhiviranih stvari ne prikazovati med aktivnimi elementi na glavnih seznamih.
Na ustreznem zaslonu jih združiti v razdelek »Arhivirano«, ki je privzeto
zložen in pokaže vsebino šele ob razširitvi. Tako arhivirani elementi ne
zavzemajo prostora med običajno uporabo; uporabnik izrecno navede projekte
kot primer. Usmeritev velja tudi za druge arhivirane stvari iz teh opomb.

Arhiviranje mora ohraniti dosegljivost elementov prek tega razdelka in ostati
ločeno od brisanja. Pri prikazu upoštevati izbrani prostor in pravice dostopa.

## 14 Preglednejša izbira prostora in dostop do projektov

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka spustnega
seznama prostorov. Status: raziskati druge rešitve; končna zasnova ni izbrana.

Spustni seznam meša osebni prostor, gospodinjstva, organizacije in posamezne
deljene projekte. Z večjim številom projektov bo hitro postal predolg in
nepregleden. Uporabnik zavrača prikazovanje posameznih projektov v tem skupnem
spustnem seznamu in želi raziskati drugačno rešitev.

Možnosti za primerjavo:

- Izbirnik vsebuje prostore; projekte se izbira v preglednem seznamu znotraj
  gospodinjstva oziroma organizacije, z iskanjem pri večjem številu projektov.
- Samostojen zaslon za izbiro prostora in projektov, z jasno hierarhijo in
  iskanjem, namesto dolgega spustnega seznama.
- Za neposredno deljene projekte brez članstva v nadrejenem prostoru ločen
  dostop prek seznama deljenih projektov. Takemu uporabniku ne prikazati ali
  odpreti nedovoljene vsebine nadrejene organizacije oziroma gospodinjstva.

Primerjati tudi število korakov za pogosto menjavo projekta in jasnost
trenutno izbranega prostora/projekta. Arhivirane stvari morajo slediti opombi
13 in ostati v privzeto zloženem razdelku.

Točno mesto sedanjega prikaza:
`lib/organizer/presentation/shared/space_picker.dart`, `OrganizerSpacePicker`.
V isti seznam doda vse neosebne skupne obsege, vključno s projekti; arhivirane
projekte trenutno doda pod navaden naslov brez zlaganja.

## 15 Vizualna in uporabniška prenova Vrta

Zabeleženo 14. oktobra 2026. Status: izhodišče za največjo načrtovano vizualno
nadgradnjo; konkretne težave in želeno zasnovo še dopolniti.

Uporabnik ocenjuje, da je modul Vrt tehnično dobro izveden, njegova sedanja
uporabniška izkušnja pa je daleč od lepe in prijetne uporabe. Načrtovati
temeljito vizualno in UX prenovo modula. Tehnična kakovost sama ne pomeni
ustreznega prikaza ali enostavne uporabe.

Konkretne pripombe, primere zaslonov in pričakovane tokove zbirati v
nadaljevanju. Končna postavitev še ni določena. Pri načrtovanju velja skupno
pravilo vseh petih platform in upoštevanje smernic iOS. Ta opomba ne naroča
sprememb podatkovnega modela ali izvedbe popravkov.

## 16 Zaporedni vnos nakupov in količine na istem zaslonu

Zabeleženo 14. oktobra 2026. Status: zahteva za prihodnjo nadgradnjo.

Po vsakem uspešno potrjenem vnosu nakupa ponovno osredotočiti vnosno polje za
naslednji artikel, da je mogoče hitro dodajati več artiklov zaporedoma brez
ponovnega izbiranja polja. Ob neuspešnem shranjevanju ohraniti vneseno vsebino.

Na istem zaslonu omogočiti tudi vnos količine oziroma števila kosov. Ohraniti
sedanjo možnost prostega besedila, ne omejiti polja na številke: na primer
»2 kosa«, »1 kg« ali »1 paket«. Uskladiti tok potrjevanja in fokusa za telefonsko
tipkovnico ter tipkovnico na namizju, z upoštevanjem smernic iOS.

## 17 Odpiranje nakupovalnega seznama in označitev spremembe iz obvestila

Zabeleženo 14. oktobra 2026. Status: uporabniško opažanje in zahteva za
prihodnji popravek.

Uporabnik je bil v prostoru Dom; po odprtju obvestila o nakupovalnem seznamu
je trajalo predolgo, da se je odprl dejanski seznam oziroma dodani artikel.
Vzrok zakasnitve še ni preverjen.

Ob dotiku obvestila o spremembi nakupovalnega seznama neposredno odpreti pravi
seznam v pripadajočem računu in prostoru. Na seznamu jasno označiti konkretno
spremembo oziroma spremenjeni artikel in ga po potrebi pomakniti v vidno
območje. Ob združenem obvestilu označiti vse zajete spremembe. Končen način
vizualnega označevanja še določiti.

Preveriti pot od obvestila do seznama in odpraviti nepotrebno čakanje ali
vmesno navigacijo. Ob odprtju ohraniti preverjanje pravic; branje obvestila ne
sme samodejno označiti artikla kot kupljenega. Upoštevati tudi spremembe, pri
katerih je artikel že izbrisan ali dostop do seznama odvzet.

## 18 Tema in združevanje sistemskih obvestil

Zabeleženo 14. oktobra 2026 na podlagi uporabnikovega posnetka Androidovega
prikaza obvestil. Status: zahteva za prihodnjo nadgradnjo.

Jivie trenutno na posnetku kaže samo »Imate novo obvestilo.«. Uporabnik želi
videti vsaj osnovno temo dogodka in uporabne podrobnosti. Pri enem obvestilu
jasno navesti vrsto dogodka in povezani projekt, opravilo ali nakupovalni
seznam, na primer:

- »Sprememba na projektu X«.
- »Dodeljeno vam je opravilo …«.
- »Sprememba na opravilu Y«.
- »Dodan je izdelek v nakupovalnem seznamu Z«.

Več obvestil združiti v skupen, privzeto zložen sistemski prikaz s številom
obvestil in smiselnim povzetkom, namesto ločene vidne vrstice za vsako
obvestilo. Ob razširitvi omogočiti pregled tem in podrobnosti. Uporabnikov
vizualni zgled je združeni prikaz Codex/ChatGPT na posnetku.

Združevanje prikaza mora ohraniti posamezne dogodke in dostop do njihovih
pravih ciljev. Povezati z opombo 17 za nakupovalne sezname. Pravila združevanja
in odpiranja skupnega povzetka še določiti, vključno z dogodki iz različnih
prostorov oziroma računov.

Zasnovo presoditi na vseh petih platformah in jo prilagoditi sistemskim
možnostim posamezne platforme ter smernicam iOS. Ta opomba se nanaša na
sistemska obvestila; ni zahteva za posnemanje Androidove postavitve na vseh
platformah.
