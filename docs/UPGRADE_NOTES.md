# Opombe za nadgradnje in popravke

Uporabnik je 14. oktobra 2026 po začetnem zbiranju opomb naročil izvedbo,
commit in push po zaključenih sklopih ter nato javno Android izdajo in iOS
TestFlight. **Prvotnih 19 oštevilčenih opomb je lokalno izvedenih.** Ta status pomeni
izvorno kodo in lokalna preverjanja; nove gostovane namestitve, trgovinske
objave in fizičnega preizkusa še ne potrjuje. Dokaze, različice pogodb in
odprte izdajne korake vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md).

## Hierarhični izbirnik prostorov — izvedeno v izvoru

17. oktobra 2026 dogovorjeni razširljivi krovni prostori s projekti,
iskanje tudi po zloženih projektih ter »Deljeno z mano« samo za dostopne
projekte drugih lastnikov. [Planski dokument](SPACE_PICKER_HIERARCHY_PLAN.md)
vodi pravila prikaza, razliko med lastnikom in ustvarjalcem ter odprte
podrobnosti. Uporabnik je istega dne nato naročil izvedbo, commit in push.
[Izvedba in preverjanje](SPACE_PICKER_HIERARCHY_IMPLEMENTATION.md) ter
[nov zapis strežniških predpogojev](server/SPACE_PICKER_RELEASE_PREREQUISITES.md).
Strežnik in trgovini ostajajo nespremenjeni.

## Računi organizacije in projektni pregledi — načrtovano

17. oktobra 2026 dogovorjena začetna smer: računi na organizaciji oziroma
prostoru, projekt kot ločen pregled pripadajočih prilivov in stroškov,
brez rezerviranja denarja in podvojenih knjižb. Zabeležena tudi zanka gumba
»Dodaj v prostor«. [Novi planski dokument](ORGANIZATION_FINANCE_PLAN.md)
vodi obseg, trenutno podporo FamilyHuba in odprte izvedbene podrobnosti.
Samo načrtovanje; izvedba in izdaja nista naročeni.

## Preglednice in priloge — izvedeno v izvoru

### Preglednice v organizaciji (15. oktober 2026)

16. oktobra je uporabnik naročil izvedbo. Prazna razširljiva mreža omogoča
besedilo, številke in osnovne formule/SUM. Strežniški zaklep izključi drugega
urednika in jasno pokaže, kdo ureja; lokalni osnutki ostanejo obnovljivi ob
izgubi povezave. Podrobnosti, meje, dokaze in še odprte izdajne korake vodi
[izvedbeni zapis](TABLES_AND_ATTACHMENTS.md).

Po preizkusu na S25 dodatno izvedeni povečava mreže z dvema prstoma
(50–200 %), gumbi −/odstotek/+ in pomoč z vsemi podprtimi formulami ter
primeri. 63 ciljnih preizkusov PASS; samo aplikacijski izvor, brez nove
strežniške nadgradnje ali oddaje. [Dokazi](SPREADSHEET_ZOOM_HELP.md).

### Priloge (15. oktober 2026)

16. oktobra naročeno in izvorno izvedeno: PDF-ji, dokumenti, preglednice,
besedilo in JPEG/PNG pri dovoljenih skupnih prostorih, opravilih ter
preglednicah. Nalaganje, preverjen prenos, izrecno shranjevanje kopije,
brisanje in prijava vsebine. [Izvedba in preverjanje](TABLES_AND_ATTACHMENTS.md).
Gostovanje in nameščena aplikacija s tem še nista nadgrajena; Google Play
oddaja še vedno potrebuje novo izrecno uporabnikovo potrditev.

## Potrjene odločitve

Brisanje zajame vsebino izbranega prostora oziroma projekta in dovoljene
podrejene vsebine. Nadrejeni prostor, sorodni prostori, računi ter prijava na
strežnik ostanejo. Pred brisanjem uporabnik vidi imenovan predogled s števci,
ovirami in izrecno potrditvijo; spremenjen predogled zahteva novo odločitev.

Po zaznanem izbrisu ali odvzemu dostopa aplikacija skrije skupno vsebino in
prekliče aktivne lokalne opomnike. Lastno še neposlano delo ohrani ločeno za
izrecen izvoz in bralni pregled, brez samodejnega pošiljanja ali ponovne
podelitve dostopa. Običajne kopije ne vključujejo nedovoljene skupne vsebine.
Odstranitev člana prekliče tudi njegove neposredne dostope in povabila v
podrejenih projektih; pred odstranitvijo mora biti rešeno lastništvo.

Vrt ima celozaslonski prizor, vizualno rast po dnevih, zgodovino iste grede
skozi leta in izrecno pobiranje. Mere vrta so v metrih; grede se prosto
postavljajo in raztegujejo, z vidnimi merami in razmiki. Uporabnik nastavi
razmik rastlin ter izbere ilustracijo iz osnovnega nabora vrtnin.

Pri izvedbi so bile upoštevane mobilne in namizne postavitve ter smernice iOS.
Za Vrt je uporabnik izbral GPT-6 Astra z zelo visokim razmišljanjem, za druge
podagente GPT-6.1 Sol/high. Android, iOS in macOS so v obsegu aktualne izdaje;
native gradnji Windows in Linux sta po njegovi poznejši odločitvi odloženi.
Uspeh widget testa ali gradnje ne potrjuje fizične uporabe druge platforme.

## 1 Ogled vnosa gesla

Status: lokalno izvedeno. Geslo je ob odprtju skrito; ikona očesa preklopi
med skritim in vidnim vnosom. Izbira pomaga preveriti vnos brez spreminjanja
prijavne semantike ali shranjevanja gesla v besedilno nastavitev.

## 2 Opomniki glede na rok opravila

Status: lokalno izvedeno. Uporabnik lahko izbere opomnik ob roku, eno uro ali
en dan pred rokom. Čakajoči opomnik sledi spremembi roka; dokončanje opravila,
izbris ali odstranitev roka ga prekliče. Ponovna otvoritev opravila ga sama
ne obudi, že dostavljen opomnik pa se zaradi premika roka ne dostavi znova.

Izbira deluje za lokalna opravila brez računa in za dovoljeni oddaljeni vir.
Strežnik čas izračuna iz svojega veljavnega opravila. Ohranijo se stari
absolutni opomniki in izvirne identitete čakajočih ukazov.

## 3 Odvečno besedilo v podrobnostih projekta

Status: lokalno izvedeno. »Okvirno trajanje« je privzeto zloženo pojasnilo.
Ocena dela, manjkajoči podatki in razlaga izračuna ostanejo dosegljivi po
razširitvi; ne zavzemajo več stalnega prostora pred koledarjem projekta.
Odločitev je skrivanje v razširljivem razdelku, ne odstranjevanje podatkov.

## 4 Sporočilo za prazen dan v koledarju projekta

Status: lokalno izvedeno. Prazen izbrani dan pove, da za ta dan v projektu ni
opravil. Ločeno slovensko in angleško besedilo ohrani razliko med praznim
dnevom in projektom, ki sploh še nima opravil.

## 5 Arhiviranje v nastavitvah prostora

Status: lokalno izvedeno. Samostojni gumb »Arhiviraj« je odstranjen iz skupnega
ovoja delovnih zaslonov. Upravljanje prostora je v njegovih nastavitvah;
projektni seznam opravil ima kontekstni meni iz opombe 10. Skupni Utrip ne
ponuja dejanja, ki bi brez jasnega cilja arhiviralo celoten izbrani prostor.

## 6 Urejevalnik projekta glede na njegov prostor

Status: lokalno izvedeno. Organizacijski projekt kaže svojo organizacijo in
ne ponuja zavajajoče izbire »Osebno / Dom«. Urejevalnik ohrani načrtovani
termin, faze in mejnike ter dovoljen dostop do deljenja. Sprememba prikaza ne
seli projekta ali članstev v drug prostor; zapis preveri trenutni kontekst
in pravice, tudi če se med odprtim obrazcem spremenijo.

## 7 Odstranitev člana iz deljenja prostora

Status: lokalno izvedeno. Odstranitev člana gospodinjstva ali organizacije
prekliče tudi njegove neposredne projektne dostope in čakajoča povabila v
podrejenih prostorih. Lastništvo podrejenega projekta je treba prej prenesti;
zavrnjena odstranitev ne spremeni članstev delno.

Račun in dostop do drugih dovoljenih prostorov ostaneta. Odjemalec po
zaznanem odvzemu skrije prenesene skupne podatke in ohrani le ločeno lastno
neposlano delo za izrecen izvoz. Naprava brez povezave spremembe ne more
zaznati pred ponovnim stikom s strežnikom; prejšnjih prenesenih ali izvoznih
kopij s tem ne prikličemo nazaj.

## 8 Povabila v arhiviran prostor

Status: lokalno izvedeno. Arhiviran prostor in njegovi podrejeni projekti
zavrnejo novo povabilo ter sprejem starega čakajočega povabila. Povabilo
prostora ne aktivira. Izrecna obnova arhiva ohrani članstva; opomnikov, ki so
med arhiviranjem zapadli oziroma bili preklicani, ne dostavi za nazaj.

## 9 Brisanje prostorov in posameznih projektov

Status: lokalno izvedeno. Lokalni in dovoljeni skupni prostori ter projekti
imajo izrecen predogled brisanja in potrditev. Celoten skupni obseg zahteva
lastnika; tuje lastništvo ali zunanje finančne povezave lahko brisanje jasno
preprečijo. Projektni izbris ohrani nadrejeno organizacijo oziroma
gospodinjstvo in nepovezane finančne zapise.

Strežnik trajno označi izbrisane identitete, zato star čakajoči zapis ne more
obuditi vsebine. Zasebne fotografije se odstranijo po potrjeni SQL
transakciji prek ponovljive vrste za čiščenje. Drugi računi, prijava in
registracije naprav ostanejo. Odjemalci izbris upoštevajo ob sinhronizaciji;
lastno neposlano delo ostane v ločenem obnovitvenem območju.

## 10 Arhiviranje in brisanje v meniju na zaslonu opravil

Status: lokalno izvedeno. Ob naslovu »Opravila« in sinhronizaciji je za
izbrani projekt meni treh pik z dovoljenima možnostma arhiviranja in
brisanja. Dejanji se nanašata na ta projekt, ne na posamezno opravilo ali
celoten nadrejeni prostor. Potrditev pokaže ime in dejanski obseg brisanja.

## 11 Približevanje table in povečanje besedila v Idejniku

Status: lokalno izvedeno. Dva prsta premikata in približujeta pogled tudi
med izbiro, risanjem in brisanjem. Drugi prst prekliče nedokončano urejevalno
potezo, ne zapiše neželene risbe ali premika elementa. Po dvigu prstov
ostane izbrano orodje uporabno.

Besedilo in lističi imajo ločena gumba za povečanje in zmanjšanje pisave.
Velikost se shrani v element, ne v povečavo pogleda; vključena je v
razveljavitev in ponovno uveljavitev. To velja tudi za oznake na fotografiji.

## 12 Meni za arhiviranje in brisanje ideje

Status: lokalno izvedeno. Vsaka uredljiva ideja ima dosegljiv meni treh pik
za arhiviranje oziroma obnovo in potrjeno brisanje imenovane table. Dejanje
velja za idejo, ne za njen prostor ali posamezni element. Bralec nima
urejevalnih dejanj; pogled Vsi obdrži natančen izvor in preveri pravice.

## 13 Arhivirane stvari v privzeto zloženem razdelku

Status: lokalno izvedeno. Arhivirani projekti, ideje in prostori so ločeni
od aktivnih elementov v privzeto zloženih razdelkih. Aktivni Utrip, opravila,
koledar in opomniki izključijo arhiviran prostor oziroma projekt. Arhiv
ostane dosegljiv za dovoljeno branje in izrecno obnovo; shranjene finančne
postavke ter zgodovina ostanejo ohranjene.

## 14 Preglednejša izbira prostora in dostop do projektov

Status: lokalno izvedeno; zasnova je izbrana. Glavni izbirnik vsebuje osebni
prostor, lokalne prostore, gospodinjstva in organizacije. Posamezni skupni
projekti so v ločenem seznamu »Deljeno z mano« z iskanjem. Projekti
nadrejenega prostora ostanejo dosegljivi v njegovem projektnem seznamu.

Neposredno deljeni projekt ne odpre vsebine nedovoljenega nadrejenega
prostora. Zaprti izbirnik pokaže dejansko trenutno izbiro tudi za tak
projekt. Arhivi so zloženi; izbira preveri trenutno identiteto in dostop.
Na iOS je pregled prostora celozaslonski z varnim območjem in običajnim
platformnim prehodom, na Androidu in macOS ostane dialog.

## 15 Vizualna in uporabniška prenova Vrta

Status: lokalno izvedeno. Celozaslonski vrt ima lesene robove gred, zemljo in
vektorske ilustracije osnovnih vrtnin. Dotik grede ali seznam »Grede in
zgodovina« odpre zasaditve in zgodovino iste grede skozi leta. Ločeni
urejevalnik razporeda uporablja isti neshranjeni osnutek.

Nov vrt dobi mere v metrih; staremu jih je mogoče dodati brez spremembe
geometrije. Grede se prosto rišejo, premikajo in raztegujejo; mere in razmiki
so vidni. Gostota ilustracij sledi nastavljivemu razmiku rastlin. Rast po
koledarskih dnevih je vizualna ocena glede na vneseno dejansko setev oziroma
sajenje, ne agronomska napoved.

Izrecna označitev pobiranja odstrani zasaditev iz prizora in ohrani celotno
zgodovino. Greda je prazna, ko so pobrane vse njene zasaditve izbrane sezone.
Shranjevanje je izrecno; približevanje, ogled zgodovine in menjava pogleda
ne zapišejo osnutka. [Podrobnosti in dokazi](GARDEN.md).

## 16 Zaporedni vnos nakupov in količine na istem zaslonu

Status: lokalno izvedeno. Uspešno dodajanje artikla vrne fokus v vnos za
naslednji artikel. Napaka ohrani vneseno vsebino. Količina je na istem
zaslonu in sprejme prosto besedilo, na primer »2 kosa«, »1 kg« ali »1 paket«,
z ohranjenim tokom telefonske in namizne tipkovnice.

## 17 Odpiranje nakupovalnega seznama iz obvestila

Status: lokalno izvedeno. Odprtje obvestila pridobi celoten dovoljeni seznam
v pravilnem računu in prostoru brez nepotrebnega čakanja na splošno
sinhronizacijo. Spremenjeni artikli so označeni, prvi dosegljivi se po potrebi
pomakne v vidno območje; združen dogodek ohrani vse svoje cilje.

Odprtje obvestila ne označi artikla kot kupljenega. Izbrisan artikel ali
odvzet dostop se obravnava z dejanskim razpoložljivim ciljem oziroma
sporočilom. Povzetek več dogodkov odpre ustrezni center obvestil; uporabnik
nato izbere posamezni dovoljeni cilj. Fizična hitrost nove izdaje še ni
izmerjena na uporabnikovi napravi.

## 18 Tema in združevanje sistemskih obvestil

Status: lokalno izvedeno. Nova oblika poda dovoljeno temo dogodka in
povezani projekt, opravilo ali seznam. Android uporablja skupino in
povzetek s številom dogodkov; razširitev ohrani posamezne dogodke in njihove
cilje. Skupine so ločene po strežniku in računu.

iOS in macOS uporabljata sistemsko združevanje po niti. Končna uskladitev
lokalnih opomnikov z isto strežniško APNs nitjo je še del tekočega
izdajnega popravka; obstoječega že zapadlega obvestila zaradi spremembe
združevanja ne smemo ponovno sprožiti. Dejanski prikaz, dostava in odpiranje
na fizičnih napravah potrebujejo ločeno potrditev.

## 19 Položaj nastavitev opomnikov ob osvežitvi

Status: lokalno izvedeno. Položaj drsenja in odprti razdelki ostanejo med
osveževanjem, shranjevanjem ter sinhronizacijo. Zaslon ima svoj
ScrollController, stabilne identitete kartic in rezervirano višino
indikatorja. Regresijski test s tremi zaporednimi ponovnimi nalaganji je
uspešen; nova fizična namestitev še sledi.
