# Prenova osebnega in družinskega organizatorja

Dokument vodi izvedbo, odločitve, preverjanja in odprto delo. Uporabnik je 4. oktobra 2026 odobril začetek gradnje ter vzporedni razvoj telefona in namizja. Glavni agent orkestrira; izvedbo opravljajo podagenti GPT 6.1 Sol / high. Ta dokument ne pomeni, da so vse spodaj opisane funkcije že izdelane.

**Novo izvedbeno naročilo, 8. oktober 2026:** uporabnik je odobril izvedbo spodaj zapisanih nadgradenj. Vrstni red je popravki prikaza/prijave → commit in push → funkcionalne nadgradnje → commit in push → nova Android interna izdaja za obstoječe preizkuševalce. [Tekoča izvedba](UPGRADE_IMPLEMENTATION.md) vodi lastništvo, dokaze in aktualno dokončanost. Prejšnji zapisi »samo opomba« ohranijo izvor zahtev, niso več odlog njihove izvedbe. Javno produkcijsko izdajo, pravne potrditve in lastnikove iOS/dostopne korake še vedno obravnavamo ločeno.

**Aktualna usmeritev, pozneje 4. oktobra 2026:** uporabnik je po zahtevi za pregled pojasnil, da želi nadaljevati gradnjo in je z začetkom zadovoljen. Pregled stare kode in dosedanjih sprememb usmerja razvoj, ne ustavlja novih funkcij. Ohranitev starih lokalnih podatkov aplikacije ni pogoj; bistveno je iz strežnika zajeti vse obstoječe podatke kot preverjen lokalni arhiv s samostojnim brskalnikom. Staro aplikacijo in projekte lahko nato upokojimo. Obstoječi projekti so izhodišče za razumevanje potreb in morebiten izbrani prenos, ne obvezna živa združljivost. Finance ponovno zasnujemo. Spodnje izdelane etape so zapis dosedanjega razvoja, prihodnje etape pa se po ugotovitvah prilagodijo.

## Nazaj in odpiranje opravil, 9. oktober 2026

Uporabnik po Android preizkusu zahteva vračanje s sistemskim Nazaj na prejšnji zaslon, na začetnem zaslonu pa sporočilo **Pritisni še enkrat za izhod** in drugi pritisk za izhod. Hkrati poroča o približno trisekundnem zamiku pri odpiranju opravila. Izvedbo vodi [mejnik navigacije in opravil](NAVIGATION_AND_TASK_OPENING.md): zgodovina področij/podpogledov, prednost zapiranja dialogov ter odpiranje že vidnega opravila iz lokalne projekcije brez čakanja na sinhronizacijo celotnega računa. Pravice, finančne meje in zunanja obvestila ostanejo ločeno preverjeni. Izvedeno in preverjeno: **715 Flutter PASS / 9 opt-in HTTP preskočenih**, analiza brez napak/opozoril (37 obstoječih info), Android debug in web release gradnji. Različica ostaja 1.1.4+7; popravka še nista objavljena v novi interni izdaji.

## Vsi prostori in popravek centra obvestil, 9. oktober 2026

Uporabnik je na Samsungu S25 pokazal prazen seznam obvestil ob še vedno označenem zvončku ter naročil izvedbo izbire **Vsi**. Ta združi pregled osebnih podatkov in dovoljenih aktivnih prostorov trenutnega računa, z oznako izvora pri vsakem zapisu. Dodajanje in urejanje ostaneta vezana na dejanski prostor; zasebna sinhronizirana kopija se ne šteje dvakrat. Finančni pregled ohrani ločene pravice, valute in načrtovane/knjižene vnose. Vrt ostaja lokalen.

Zvonček in center uporabljata skupna pravila vidnosti; dostavljeno oddaljeno obvestilo ne potrebuje še lokalnega alarma, da ostane vidno. Izvedbo, regresijske preizkuse, prikaz na različnih širinah in mejo do mobilne objave vodi [mejnik Vsi in obvestila](ALL_SPACES_AND_INBOX.md).

## Dopolnitev obvestil po preizkusu FCM, 8. oktober 2026

Uporabnik je naročil dokončanje brez svoje prisotnosti, commit/push in združitev v privzeto vejo `main`, nato izrecno še novo interno Android izdajo. [Mejnik oddaljenih opomnikov](REMOTE_REMINDERS.md) vodi uporabniški tok, preverjanje in jutrišnji fizični preizkus.

- Strežniški FCM je nastavljen; en ciljni diagnostični opomnik je Google sprejel za registrirani Samsung. Uporabnik je potrdil prikaz na zaklenjenem telefonu in klik do pravega opravila. Cron in APNs imajo ločene dokaze v [cPanel zapisu](server/CPANEL_SETUP.md#13-fcm-na-testnem-strežniku-8-oktober-2026).
- Dodano je ustvarjanje, sprememba in preklic **oddaljenega razporejenega opomnika** za skupno opravilo, dogodek in načrtovan finančni zapis. Obrazec uporablja obstoječi pogodbi `putReminder`/`cancelReminder`; trajna čakalna vrsta in strežniška potrditev imata ločeni stanji. Lokalni »Odloži 15 min« ostaja ločen tok. Nov fizični preizkus je načrtovan po posodobitvi.
- Nastavitve zdaj ločijo **registracijo telefona** od **izbire kategorij za posamezen prostor**. Povzetek pokaže vključene kategorije ali odsotnost izbire, opomniki pa so prvi in razširjeni. Uporabnikov izbor ostane izrecen; ne vključujemo samodejno vseh kategorij ali e-pošte.

## Potrjena smer

- Osrednja aplikacija za osebne načrte, prosti čas, dom, družino, projekte, nakupovanje in finance.
- Osnovno ustvarjanje, branje in urejanje deluje brez strežnika in računa ter preživi ponovni zagon. Račun je namenjen izbirnemu sodelovanju in povezovanju naprav.
- Uporabnik naj se registrira, prijavi in sprejme povabilo v aplikaciji. Predhodna prijava v spletni Kanboard ni del želenega toka.
- Družinsko članstvo in sodelovanje pri posameznem projektu sta ločena obsega. Finance so lahko osebne, skupne za dom ali del projekta, ki je namenoma zasnovan s skupnimi financami. Dostop do takega modula določa finančna politika doma/projekta; zunanji projektni sodelavec ne dobi zasebnega družinskega pregleda. To dopolnitev je uporabnik izrecno potrdil med izvedbo deljenja.
- Obvestila ostanejo v aplikaciji in vključujejo dogajanje v skupnem prostoru tudi brez osebne dodelitve. Osebno naslovljena obvestila so jasno označena. Nakupovalne spremembe so vidne in se lahko združijo; zvok, push in e-pošta imajo ločene nastavitve. Posamezni nakupovalni vnosi privzeto ne pošiljajo e-pošte. Dostava na telefon in sistemski opomniki se preverjajo ločeno od prikaza v aplikaciji.
- Mobilni in namizni vmesnik nastajata hkrati. Skupni so domena, lokalna shramba, sinhronizacija in preverjanje pravic.
- Obstoječe Kanboardove projekte, povezave in finančne podatke ohranimo v preverljivem lokalnem arhivu, dostopnem brez starega strežnika. Izvirnikov ne brišemo samodejno. Morebitno nadaljevanje izbranega projekta v novem modelu je ločen postopek.

## Oblikovanje in navigacija

### Nova znamka in izdaja — odločitev 5. oktobra 2026

Odločitev z dne 5. oktobra je nova aplikacija z novo znamko, ločena od Kanban Connect. **7. oktobra 2026 je uporabnik izbral Jivie (dživi)** ter naročil začetek priprav za iOS in Android. Ikona predstavlja življenje kot čim bolj abstrakten preplet **zemlje, vode in zraka**; čebela in dobesedni trinity knot nista zahteva. Glavni agent vodi oblikovanje in pregled, podagenti GPT‑6.1 Sol / high izvajajo preimenovanje kode in pripravo izdaje. Potrjena zasnova vmesnika spodaj ostaja osnova.

Nova lokalna konfiguracija mobilne aplikacije uporablja `si.triparna.jivie` in `1.0.0+1`; stare trgovinske aplikacije ne spreminjamo. Uporabnik je dovolil registracijo novih aplikacij v App Store Connect/Play Console ter testne izdaje; aktualno stanje vodi [predaja testnih izdaj](release/TEST_RELEASE_STATUS.md). Javna izdaja ni izvedena. Ohranimo podatkovne formate, interno Dart ime `kanban`, obstoječe namizne identitete za dostop do shrambe in branje starih povabil. Nova povabila uporabljajo `jivie://invite`. [Priprava izdaje](release/README.md) vodi aktualne dokaze, opravila in omejitve; [platformne opombe](release/PLATFORM_NOTES.md) pojasnijo podpis ter združljivost. Prvi spletni pregled imena ni preverjanje znamke ali domene; podobna zdravstvena aplikacija Jivi obstaja.

Dejanski bralni pregled Play Console: Kanban Connect uporablja `com.takndev.kanbanconnect`; zadnja interna izdaja je `1.0.12`, koda 12, javna izdaja ni aktivna, nastavitev aplikacije je dokončanih 0/11. Račun TaknDevs je označen kot organizacijski. Stara aplikacija prikazuje zahtevo 12 preizkuševalcev/14 dni; uporabnik pojasnjuje, da izvira iz prenosa aplikacije iz njegovega prejšnjega osebnega računa. Tega pogoja ne prenašamo na novo aplikacijo v organizacijskem računu. [Googlova dokumentacija](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) opredeli to zahtevo za nove osebne račune. Interno/izbrano testiranje priporočamo za kakovost, ne kot domnevno obvezni 12/14 korak nove objave.

Uporabnik je potrdil brezplačno aplikacijo. Model: brezplačno lokalno delo; lastni strežnik za izbirno sinhronizacijo in sodelovanje; poznejše upravljano gostovanje kot izbirna plačljiva storitev. V tej izdaji ne dodajamo plačil ali naročnin. Cena, obseg podpore in način obračuna prihodnjega gostovanja še niso določeni. Vtičnik FamilyHub pripravljamo za ločen javni repozitorij pod MIT; to ne spremeni licence celotne aplikacije. Prodajo digitalnih storitev bo treba uskladiti s [pravili Googla](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en) in [Appla](https://developer.apple.com/app-store/review/guidelines/#other-purchase-methods).

**Dopolnitev 7. oktobra:** izdajatelj je TriparNA (triparna.si), uporabnik je kupil jivie.app. [Statična spletna stran](../website/README.md) je pripravljena v slovenščini in angleščini za ročni prenos ZIP v javno korensko mapo domene na cPanelu. Vključuje predstavitev, pomoč, zasebnost ter pripravo povezave do samopostrežnega izbrisa na lastnem strežniku. Stran ne zbira poverilnic, ne uporablja analitike in ne izvaja samega izbrisa; dejanski postopek opravi ustrezen FamilyHub na izbranem strežniku. Spletna objava in dosegljivost javnih URL še nista preverjeni.

Izbris uporabniškega računa gradimo za **self-hosted** strežnik. Vključuje dejanski račun Kanboarda, povezane seje, osebne podatke in prispevke po izrecnem predogledu. Skupnih vsebin drugih ustvarjalcev ne brišemo prikrito; izbire za naslednika in ohranitev skupne strukture so ločene. Urejanja vsebine zapisov drugih ustvarjalcev lahko ostanejo, ker ni zgodovine avtorstva po poljih. Pri starem spletnem Kanboardu ostanejo posebej dokumentirane omejitve odvisnosti in že začetih zahtev. To ni dokaz popolnega izbrisa UGC ali sprejetja v trgovini. Upravljano gostovanje z lastnimi pravili hrambe bo ločena prihodnja izvedba.

Pred objavo: preverimo znamko in registriramo nove identifikatorje, preverimo podpisan AAB in iOS arhiv (za novo aplikacijo sta potrebna izbrana ekipa in profil), objavimo javne strani, izpolnimo resnične podatkovne deklaracije ter zagotovimo pregledovalcem dostop do skupnih funkcij. [Uporabniški izbris](ACCOUNT_DELETION_CLIENT.md) in [strežniška pogodba FamilyHub 0.6.0](server/account-deletion-contract.md) sta zdaj izdelana in lokalno preverjena; opisana legacy omejitev in ohranjena tuja vsebina nista dokaz popolnega odstranjevanja UGC ali sprejema v trgovini. Odjava in izbris finančnega računa ostajata ločeni dejanji. Zunanjo dostavo SMTP/FCM/APNs in celotno shranjevanje/obnovo kopije preverimo na pravih napravah. [Google: izbris računa](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en), [Apple: zasebnost in računi](https://developer.apple.com/app-store/review/guidelines/#privacy).

[Kratek prvi vodič](FIRST_TIME_GUIDE.md) predstavi lokalni začetek in štiri glavna področja. Odpre se iz začetnega namiga in nastavitev, omogoča preskok ter si zapomni ogled. Ne ustvarja podatkov in ne vključi povezave/obvestil. Strani zasebnosti, pomoči in izbrisa so povezane tudi iz nastavitev aplikacije; njihove javne destinacije čakajo na uporabnikovo objavo pripravljenega ZIP-a.

Odprta arhitekturna odločitev za samostojno gostovanje: uradni mobilni paket ima en Firebase projekt, trenutni FamilyHub pa pošilja neposredno v ta projekt. Lasten drugačen Firebase projekt zahteva lasten mobilni build; našega storitvenega/APNs ključa ne delimo upraviteljem drugih strežnikov. Predlog je izbirni skupni posrednik za generična push obvestila, z ločenimi pravicami, omejitvami in preklicem. **Posrednik še ni izdelan ali potrjen kot obvezna storitev.** Lokalno delo, sinhronizacija, center obvestil, lokalni opomniki in konfigurirana e-pošta niso odvisni od njega.

Potrjen mobilni koncept, prvotno imenovan »Vsakdan«, nadaljujemo pod imenom Jivie. Svetla tema uporablja belo in svetlo sivo, grafitno besedilo in moder poudarek `#365BD9`; temna tema ohrani isto hierarhijo in berljivost. Nastavitev teme ne zahteva računa.

| Telefon | Namen | Namizna prilagoditev |
| --- | --- | --- |
| Danes | Naslednji dogovor, naslednja pomembna opravila, bližnjica do nakupov | Pregled v več stolpcih, brez dolgega ponavljanja vsega |
| Načrti | Prihajajoča opravila in dogodki ter projekti | Prostor za seznam in podrobnosti, koledar kot razvijajoč se pogled |
| Nakupi | Neposredno dodajanje in odkljukavanje, več seznamov | Isti podatki in dejanja z več prostora |
| Več | Finance, dom, nastavitve, povezava in deljenje | Področja neposredno v levem meniju |

Na telefonu ne postavljamo šestih velikih ploščic pred dejansko vsebino. Obseg podatkov označimo ob vsebini; preklop prostora ni obvezna ovira pred vsakim dejanjem. Na projektu imajo prednost naslednji koraki, ostale podrobnosti so dosegljive postopoma. Prazna aplikacija kaže prazna stanja in dejanja za začetek, ne predstavitvenih finančnih zneskov ali izmišljenih družinskih članov.

## Etape in merila

Trenutna odobrena izvedba dodelitev, skupnega dnevnega pregleda, obvestil, sistemskih opomnikov in financ se vodi v [mejniku družinske nadgradnje](FAMILY_UPGRADE.md). Ta loči novo delo in njegove dokaze od že zaključenega prvega deljenja.

Po arhiviranju je izdelano in lokalno preverjeno [prvo uporabno deljenje med dvema osebama](SHARING_MILESTONE.md). Vključuje račune in povabila v aplikaciji, skupne nakupovalne sezname/osnovna opravila ter transakcijsko lokalno hrambo in sinhronizacijo. Dokument mejnika loči dokaze te etape od preostalih nalog B/C in produkcijske izdaje.

### Potrjena dopolnitev: skupne finance ter obvestila in opomniki

Uporabnik je po pregledu deljenja 4. oktobra 2026 potrdil spodnjo finančno zasnovo in ponovno izrecno zahteval obvestila ter opomnike v aplikaciji. Njihova aktualna izvedba in dokazi so v [družinskem mejniku](FAMILY_UPGRADE.md); spodaj ostaja zapis zahtev. Etapa D je obvezni del uporabne družinske različice; finančna prenova je ne sme odriniti na nedoločen čas. Pri novih modulih se že v podatkovni pogodbi določijo dogodki, roki in prejemniki, da jih lahko povežemo z enim skupnim sistemom obvestil.

- Skupni člani s finančnimi pravicami lahko ustvarjajo prihodke in stroške doma oziroma finančnega obsega projekta. Posamezen zapis loči plačnika/prejemnika, finančni račun in uporabnika, ki ga je vnesel. Tabela pokaže datum, opis, vrsto, znesek z valuto, kategorijo ter te osebe/račun; po potrebi tudi projekt. Omogoči pregled vseh zapisov ter filtre po članu in računu.
- Osebni finančni zapisi se vključijo samo z izrecno izbiro. Pravice do pregleda in urejanja skupnih financ se določijo posebej. Spremembe imajo sled, kdo in kdaj jih je opravil; popravek ne prepiše izvirnega avtorstva vnosa.
- Prenos med osebnim in skupnim računom je prenos, ne nov prihodek ali strošek v skupnem seštevku. Denarni tok in prispevek posameznika sta različna pregleda; isti dogodek se ne sme šteti dvakrat.
- Obvestilo o sodelovanju (npr. povabilo ali dodelitev opravila) in časovni opomnik (rok opravila, dogodek ali načrtovano plačilo) sta ločena zapisa oziroma razloga za prikaz. Skupni center v aplikaciji pokaže neprebrano stanje in odpre pravo vsebino; pogled Danes izpostavi bližnje roke.
- Predlagana dejanja opomnika so odložitev, sprememba časa in odpiranje izvornega zapisa. Označitev obvestila kot prebranega sama ne zaključi opravila in ne pomeni, da je račun plačan.
- Osebni opomniki za lokalne podatke morajo delovati brez strežnika. Obvestila o dejanjih drugih članov prispejo ob povezavi; kasnejša uskladitev jih ne podvaja. Zaključitev, izbris ali sprememba roka posodobi oziroma prekliče zastarel opomnik.
- Dodani artikli in novi nakupovalni seznami ustvarijo vidno obvestilo o skupnem dogajanju; več povezanih dodatkov se lahko združi. Uporabnik ločeno izbira zvok, push in e-pošto po vrsti dogodka in prostoru; e-pošta ni kopija vsake spremembe ali vsakega vnosa stroška. Finančna vsebina in prejemniki upoštevajo finančne pravice, tudi ob odprtju starega obvestila.

Družinska nadgradnja vključuje skupni center, lokalno sistemsko razporejanje in SMTP vrsto. Uporabnik je 5. oktobra 2026 potrdil pripravo FCM na paketu Spark; izvedbo in dokaze vodi [FCM mejnik](FIREBASE_PREPARATION.md). Produkcijska konfiguracija dostave ter fizični mobilni preizkus ostajata odprta. Prikaz v aplikaciji, obvestilo na telefonu in e-poštna dostava imajo vsak svoj dokaz delovanja v [mejniku](FAMILY_UPGRADE.md).

### Dopolnitev uporabnika: skupno dogajanje in osebno naslovljena obvestila

Uporabnik je dodatno določil, da mora član vedeti, kaj se dogaja v gospodinjstvu ali projektu, tudi če mu opravilo ni dodeljeno. Razlog obvestila določa besedilo in oznako; nujnost, zvok ter dostavni kanal so ločene nastavitve. Predlagani oznaki oziroma filtra sta **Zame** in **V skupnem prostoru**; razliko označimo z besedilom/ikono, ne samo z barvo.

| Dogodek | Namen obvestila in primer | Cilj ob kliku |
| --- | --- | --- |
| Novo opravilo v skupnem projektu | Skupno dogajanje: »V Mansardo je dodano opravilo Izmera oken.« Prejemnik ni nujno izvajalec. | To opravilo v pravem projektu |
| Opravilo dodeljeno prejemniku | Osebno: »Dodeljeno ti je opravilo Izmera oken.« | Dodeljeno opravilo |
| Več novih dodelitev | Osebno, združeno: »Dodeljena so ti 3 opravila v Mansardi.« | Seznam konkretnih opravil iz obvestila, ne začetni zaslon ali nepovezana opravila |
| Nov nakupovalni seznam | Skupno dogajanje: »Dodan je seznam za vikend.« | Novi seznam |
| Dodani artikli | Skupno dogajanje: »V tedenski nakup so dodani 4 izdelki.« | Zadevni seznam s poudarjenimi dodatki |
| Dnevni pregled gospodinjstva | Skupno dogajanje: kdo ima danes kateri skupno vidni dogodek/opravilo in ob kateri uri | Dnevni pregled oziroma izbrani dogodek |
| Projektni plan ali rok | Skupno dogajanje: kdo dela kaj in kdaj; nov ali premaknjen termin oziroma rok. Prizadeti izvajalec dobi osebno različico. | Projektna časovnica ali konkretno opravilo z rokom |

Obseg načrtovane izvedbe:

- Prejemnike dogodka določajo članstvo, dostop do vsebine in nastavitve sledenja prostoru; niso omejeni na dodeljene izvajalce. Zasebni koledarski ali finančni zapisi se ne vključijo v pregled gospodinjstva samo zaradi članstva. Predlagani privzeti način ne ustvarja opozoril uporabniku za njegovo lastno dejanje; skupna zgodovina dejanje še vedno pokaže.
- En dogodek se za istega prejemnika ne podvoji kot »dodano« in »dodeljeno tebi«. Če nastaneta skupaj, izvajalec vidi osebno različico, ostali člani obvestilo o skupnem dogajanju. Poznejša samostojna dodelitev je nov dogodek.
- Več povezanih sprememb se lahko združi po prostoru, razlogu in kratkem časovnem obdobju, pri tem pa se ohrani nabor izvornih zapisov. Osebne dodelitve se ne izgubijo med splošnimi nakupovalnimi posodobitvami. Trenutni izvedbeni interval združevanja je pet minut.
- Klik iz centra obvestil ali telefonskega obvestila odpre isti konkretni cilj, tudi ob zaprti aplikaciji oziroma po potrebni prijavi. Pred odprtjem preveri pravi račun, prostor in trenutne pravice; izbrisana ali nedostopna vsebina dobi razumljivo stanje. Potrditev odprtja/prebranega ne zaključi opravila. Stanje prebranega je osebno in se za povezani račun uskladi med napravami.
- Gospodinjstvo potrebuje skupen dnevni pregled, projekt pa pregled rokov in časovnico izvajalcev. Obvestila vodijo v te poglede; ne nadomeščajo jih. Dodelitve, skupno vidni dogodki in termini so vključeni v sync2 pogodbo; v1 odjemalec ne sme prepisati novih polj.
- Preizkusi morajo vključiti nedodeljenega člana, osebno dodelitev ob nastanku in pozneje, skupino več dodelitev, nov seznam/artikle, dnevni pregled drugih članov, spremembo projektnega termina, odpiranje iz zaprte aplikacije, izgubljeno povezavo in ponovitev brez dvojnikov ter odvzem pravic pred odprtjem. Dokazi mobilne dostave in odpiranja na iOS/Android so pogoj, da telefonska obvestila predstavimo kot delujoča.

### Vzporedno z nadaljnjo gradnjo — pregled, arhiv in nova podatkovna zasnova

- Primerjava izvirnega commita `b2268d8793105f36ac085a39181be62dacdc28fe` z delovno vejo; popis dejansko odstranjenih ali spremenjenih vedenj, ne samo datotek.
- Pregled aplikacijske kode, poslovnih pravil, API, hrambe, platformnih nastavitev in testov. Kritično pregledamo tudi novo lokalno osnovo in FamilyHub.
- Za vsak modul odločitev: ponovno uporabiti, prilagoditi, zamenjati ali ohraniti le kot arhivski adapter. Dolžina datoteke sama ni razlog za prepis.
- Načrt popolnega zajema starega sistema: varnostna kopija za obnovo in prenosljiv arhiv za branje sta različna izdelka. Finance ohranimo tudi v izvirnem formatu.
- Lokalni arhivski brskalnik: projekti, naloge, komentarji, podnaloge, datoteke, povezave in finančni pogled; nepopolna ali nerazumljena vsebina mora ostati označena in dostopna v izvirni obliki.
- Nova finančna domena, lokalne transakcije, pravice in pogodba izbirnega strežnika se določijo pred nadaljnjo gradnjo.
- Poslovnih podatkov in konfiguracije produkcije v tem koraku ne spreminjamo. Celotna kopija je že izdelana, prenesena in obnovljena lokalno; preverjen je arhiv 48 tabel/2.180 vrstic ter 8 priponk. [Postopek in meje](LEGACY_ARCHIVE.md). Upokojitev še ni izvedena.

### A — uporabna lokalna osnova (izdelana v razvojni veji)

- Zagon brez računa in omrežja; nov organizator je začetni zaslon.
- Trajni projekti, opravila in roki, nakupovalni seznami in artikli, dogodki ter posamezni prihodki/odhodki.
- Dnevni in prihajajoči pregled bere dejanske lokalne podatke; preklop mobilne/namizne postavitve ne izgubi stanja.
- Finančni zneski so v najmanjših denarnih enotah skupaj z valuto.
- Izvoz in preverjen uvoz varnostne kopije ne potrebujeta strežnika in ne prepišeta obstoječih drugačnih zapisov brez opozorila.
- Napaka trajnega zapisa ne sme biti predstavljena kot uspeh. Preizkusi pokrijejo restart, sočasna lokalna dejanja, zavrnjen zapis in neveljaven uvoz.
- Obstoječi Kanboard ostane izrecno dostopen. Novi lokalni podatki niso samodejno sinhronizirani ali javno deljeni.
- Obstoječe ranljivosti shranjevanja poverilnic, preusmeritev in beleženja obravnavamo pred razširitvijo povezovanja računov.

### B — strežniška pogodba, računi in povabila

- Izoliran lokalni Docker s pripeto različico Kanboarda in lastnim vtičnikom; testni podatki so sintetični.
- Različica API-ja in dejanski seznam podprtih zmožnosti. Nepodprte funkcije vračajo jasen rezultat, ne lažnega uspeha.
- Povabila v projekt: preverjanje ustvarjalčevih pravic, časovna omejitev, preklic, enkratna poraba, shranjevanje samo zgoščene skrivnosti, transakcijsko sprejemanje.
- Ločena zasnova gospodinjstev in pravic do novih modulov. Testi preverijo dostop dovoljene in prepovedane osebe na vsaki poti.
- Registracija iz aplikacije, prijava, obnova dostopa in preklicljive seje naprav; ohranjena 2FA in omejevanje poskusov. Izbira javne registracije ali registracije prek povabila ostane produktna odločitev; varna začetna smer je povabilo.
- Dokaz, da novi žeton predstavlja dejanskega uporabnika in ne globalnega `jsonrpc` skrbniškega dostopa.
- Paket ZIP za cPanel brez obveznega SSH ali stalnega procesa. Produkcijska namestitev je ločen korak po pregledu in odobritvi.

### C — sinhronizacija novega sistema in izbirni prevzem iz arhiva

- Povezava lokalnih identifikatorjev s strežniškimi; različice zapisov, evidenca sprememb in izbrisov, ponovljive zahteve.
- Lokalni zapis in odhodna sprememba sta atomarna, kadar je sinhronizacija vključena. Osebni način brez strežnika ne proizvaja neskončne vrste za neobstoječo povezavo.
- Dve napravi, offline urejanje in reconnect: neodvisne spremembe ostanejo, konflikt na istem zapisu je jasno obravnavan.
- Preverjena odpoved dostopa med delom brez povezave. Zajem sprememb iz Kanboardovega spletnega vmesnika je potreben le za objekte, ki jih bo dovoljeno urejati tudi tam; starega vmesnika ne ohranjamo samodejno kot drugi urejevalnik vseh novih modulov.
- Izbirno nadaljevanje izbranih arhiviranih projektov v novem modelu, s sledjo izvora in brez dvojnikov. Samostojen arhiv ostane nespremenjen. Finančnih pravil ne pretvarjamo v preprost seznam transakcij brez dokazane semantične skladnosti.
- Načrt priponk in lokalne zaščite baze, časovnih pasov ter migracij pred širšo uporabo z zasebnimi podatki.

### D — obvestila in družinska vsakodnevna uporaba

- Trajen osebni seznam obvestil z označevanjem prebranega in odpiranjem prave vsebine; ločena osebna dodelitev in dogajanje v skupnem prostoru, tudi za nedodeljene člane. Združevanje povezanih dogodkov brez izgube osebnih dodelitev.
- Skupen dnevni pregled gospodinjstva ter projektni roki/časovnica z izvajalci; obvestila odpirajo konkretni zapis ali ustrezni filtrirani pogled.
- Lokalni opomniki z dejanskim sistemskim razporejanjem; testi dovoljenj, ponovnega zagona in časovnega pasu.
- Strežniški prejemniki na podlagi pravic in nastavitev prostora; SMTP, izbirni povzetki, ponovitve brez podvajanja. Nakupovalne spremembe so vidne v aplikaciji, e-pošta za posamezni artikel je privzeto izključena.
- Potisna obvestila za iOS/Android z ločeno preverjeno dostavo in odpiranjem konkretne vsebine ob zaprti aplikaciji; kanal in zvok sta nastavljiva. Izbran je Firebase Cloud Messaging na paketu Spark; podatki in avtentikacija ostanejo lokalno oziroma v FamilyHub. Firebase projekt uporabnik ustvari pozneje.

### E — stabilizacija in izdaja

- Testi najpomembnejših tokov, migracij, pravic in varnostnih kopij.
- Vizualen in funkcionalen pregled telefona, tablice ter namizja v obeh temah in jezikih.
- Podpisane mobilne gradnje, dovoljenja in pravilne nastavitve trgovin; App Store in Play objava sta ločena od lokalne gradnje.
- Matrika dejansko preverjenih platform; uspešen spletni build sam po sebi ne potrdi vseh native pluginov.

## Vrt — prva lokalna izvedba

**Nadaljnja odobrena prenova, 8. oktober:** uporabnik je izbral poudarek na zelenjavnih gredah in kolobarju ter izrecno naročil izvedbo predloga v isti novi interni izdaji kot opomnike. Načrt v ospredju, povečava/premik, urejanje velikosti gred, letne sezone, več kultur na gredo (sorta, družina, datumi, zapiski), zgodovina in informativna opozorila ponovljene družine. Obstoječe risbe in ID-ji ostanejo; ni samodejne delitve, vzorčnih podatkov, strežniškega modula ali fotografij. Podatkovni in prikazni del izvajata ločena podagenta. Končni obseg in dokaze vodi [Vrt](GARDEN.md).

**Zahteva uporabnika, 7. oktober 2026:** dodati modul **Vrt**, v katerem uporabnik ustvari svoj vrt ter sam zapiše in nariše, kje bo kaj imel. Prva izvedba je lokalna: več vrtov, zapiski in skica s poimenovanimi pravokotnimi območji. Deljenje in strežniška sinhronizacija Vrta nista del te etape. [Dokazi izvedbe](GARDEN.md): 76 podatkovnih/regresijskih in 48 UI/navigacijskih/vodičevih preizkusov PASS; mobilna namestitev je ločen pogoj.

Prvi obseg:

- Ustvarjanje in poimenovanje lastnega vrta.
- Ročni zapiski o tem, kaj želi uporabnik posaditi in kam.
- Preprost urejevalnik skice oziroma tlorisa: narisati razporeditev vrta, označiti posamezne dele in jim dodati napise, da je razvidno, kje bo kaj.
- Shranjevanje in poznejše urejanje zapiskov ter skice lokalno, brez računa in strežnika; vsebina mora preživeti ponovni zagon ter biti vključena v kopijo in obnovo.

Telefon uporablja zavihek Več, namizje stranski meni. Risanje in premikanje dopolnjuje obrazec za dostopno urejanje položaja in velikosti v odstotkih skice. Fizično merilo, prostoročno risanje, rastlinski katalog in deljenje ostajajo prihodnji obseg.

## Opomba za prihodnjo nadgradnjo — projektne časovnice

**Aktualni status:** Izvedba 8. oktobra: faze/mejniki, intervalni mesečni koledar, ocene minut in razpoložljivost ter trajno Play/Pause merjenje so izdelani. Končna integracija in interna objava se vodita v [izvedbenem dnevniku](UPGRADE_IMPLEMENTATION.md). Spodaj ostaja izvorni zapis zahtev.

**Zamisel uporabnika, 7. oktober 2026; za zdaj samo opomba, brez začetka izvedbe.** Projekt naj dobi časovnico kot koledar znotraj projekta. Glavni poudarek so faze in mejniki: jasno mora biti, katera opravila je treba dokončati za prvo fazo, katera za drugo ter koliko ur dela je predvidenih za vsako. To razširja osnovni razpored izvajalcev in terminov iz [družinske nadgradnje](FAMILY_UPGRADE.md); tamkajšnji dokazi ne potrjujejo spodnjih novih funkcij.

Želeni obseg za prihodnjo zasnovo:

- Projektni koledar oziroma časovnica pokaže opravila z okvirnim začetkom in koncem.
- Projekt lahko razdelimo na poimenovane faze z mejniki. Vsaka faza poveže opravila, ki so potrebna za dosego njenega mejnika, ter pokaže njihovo dokončanost.
- Opravilo ima oceno potrebnega dela; pri fazi je vidna predvidena količina ur. Ciljni pregled je: »Za prvo fazo potrebujemo ta opravila in približno X ur; za drugo fazo druga opravila in približno Y ur.«
- Na projektu oziroma posameznem opravilu lahko določimo okviren čas, ki mu ga uporabnik lahko posveti na dan ali teden. Ta razpoložljivi čas pomaga načrtovati izvedbo faz.
- Koledarski začetek/konec, ocena potrebnih ur in razpoložljivi dnevni/tedenski čas so ločeni podatki: večdnevni termin sam po sebi ne pomeni enakega števila ur dela.

**Poznejša dopolnitev:** gumba **Play/Pause** na opravilu začneta oziroma začasno ustavita odštevanje zastavljenega časa. Pregled naj loči oceno, dejansko porabljeni in preostali čas; iztek časovnika sam po sebi ne pomeni dokončanega opravila ali doseženega mejnika.

Ob začetku zasnove dorečemo povezavo med oceno faze in ocenami njenih opravil, razmerje med projektnim ter posamičnim dnevnim/tedenskim časom in pravilo, kateri zastavljeni čas odšteva časovnik. Lokalno načrtovanje sledi osnovni zasnovi brez računa in strežnika, s trajno hrambo ter kopijo/obnovo; morebitno skupno urejanje potrebuje svojo pogodbo in preverjanje pravic. Ta zapis je izvor zahteve; uporabnik je pozneje istega dne izrecno odobril izvedbo in interno izdajo.

## Opomba za prihodnjo nadgradnjo — finančni čarovnik in napoved

**Aktualni status:** Izvedba 8. oktobra: finančni računi, mesečna pravila za plačo/kredit/kartico/drugo, napoved in potrditev dejanskega zneska so izdelani. Dan 31 se omeji na zadnji dan meseca; vikend plače ima petkovo in ponedeljkovo vprašanje za isti vnos. Prazniški koledar ni vključen. Končne dokaze vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md). Spodaj ostaja izvorni zapis zahtev.

**Zamisel uporabnika, 7. oktober 2026; za zdaj samo opomba za naslednje faze, brez začetka izvedbe.** V financah naj izbirni čarovnik z nekaj vprašanji pomaga pripraviti osnovno napoved denarnega toka in opomnike za pričakovane prilive ter obveznosti.

Predvidena vprašanja:

| Korak | Vprašanje | Odgovor in nadaljevanje |
| --- | --- | --- |
| 1 | Kdaj imaš redni mesečni priliv oziroma plačo? | Datum iz koledarčka ali »Nimam«. Če ga ima: koliko okvirno? |
| 2 | Ali imaš kredit? | Da/ne. Če da: koliko in kdaj? Pri zasnovi ločimo skupni znesek kredita od mesečnega obroka, ki vpliva na napoved. |
| 3 | Ali imaš kreditno kartico z odloženim plačilom? | Da/ne. Če da: kdaj je poravnava? Datum iz koledarčka. |
| 4 | Ali imaš še druge ponavljajoče mesečne prilive? | Da/ne. Če da: kdaj in koliko? Omogoči več vnosov; že vnesene plače ne podvoji. |
| 5 | Ali imaš ponavljajoče mesečne stroške? | Da/ne. Če da: kdaj in koliko? Omogoči več vnosov. |

Odgovori ustvarijo urediv načrt ponavljanja in osnovno napoved po datumih. Okvirni zneski in pričakovani datumi ostanejo jasno ločeni od dejansko prejetih prilivov ter plačanih obveznosti. Potrditev dejanskega dogodka uskladi pripadajočo napoved, da se isti priliv ali strošek ne šteje dvakrat. Zneski ohranijo valuto; različnih valut ne seštevamo brez izrecnega pravila pretvorbe.

Opomnik za plačo:

- Na pričakovani dan uporabnik dobi obvestilo z vprašanjem **»Ali si že dobil plačo?«**. Odgovor **Da** odpre vnos dejanskega zneska in potrditev priliva.
- Po zahtevi uporabnika načrtovanje plače upošteva delovne dni. Če izbrani datum pade na soboto ali nedeljo, se vprašanje pojavi pred vikendom in po njem: praviloma v petek ter ponedeljek. To sta preverjanji istega pričakovanega priliva, ne dve napovedani plači.
- Če uporabnik prejem potrdi že pred vikendom, se nadaljnje vprašanje za ta mesečni priliv prekliče. Brez potrditve priliv ostane pričakovan; sam opomnik ga ne knjiži kot prejetega.
- Uporabnik je zahteval potisno obvestilo. Zasnova ga poveže z obstoječim centrom obvestil in sistemskimi opomniki: lokalno načrtovani opomnik mora delovati brez strežnika, izbirna oddaljena push dostava pa uporablja ločen konfiguriran kanal. Odprtje obvestila vodi v potrditev pravega priliva in finančnega obsega.

Ob zasnovi dorečemo začetno stanje za napoved, ponavljanje datumov po mesecih, praznike in delovne dni, spremenljiv znesek poravnave kartice ter ravnanje, če plača tudi po vikendu še ni prispela. Osebni načrt ostane lokalen, trajno shranjen in vključen v kopijo/obnovo; skupni finančni obseg in morebitna sinhronizacija zahtevata izrecno izbiro ter obstoječe finančne pravice. Čarovnik ne vključi samodejno deljenja ali obvestil. Ta zapis je izvor zahteve; uporabnik je pozneje istega dne izrecno odobril izvedbo in interno izdajo.

## Opomba za prihodnjo nadgradnjo — člani gospodinjstva brez računa

**Aktualni status:** Izvedba 8. oktobra: poimenovane osebe brez prijave ter ločen izvajalec in osebe, na katere se zapis nanaša, so izdelani. Oseba ni članstvo ali račun in ne dobi pravic oziroma push dostave. Končne dokaze vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md). Spodaj ostaja izvorni zapis zahtev.

**Zahteva uporabnika; za zdaj samo opomba za naslednje faze, brez začetka izvedbe.** V gospodinjstvo naj bo mogoče ročno dodati osebe, ki nimajo svojega uporabniškega računa, ter zanje voditi opravila oziroma povezati opravila, ki se nanje nanašajo.

Želeni obseg:

- Dodajanje in urejanje profila člana gospodinjstva z imenom, brez obvezne e-pošte, prijave ali povabila za ustvarjanje računa.
- Pri opravilu izbrati člana brez računa kot izvajalca oziroma označiti, na katerega člana se opravilo nanaša. To sta ločeni povezavi: opravilo, povezano z osebo, lahko opravlja nekdo drug.
- Pregled in filtriranje opravil po članu gospodinjstva, da uporabnik vidi in ureja opravila, ki jih vodi zanj.
- Avtorstvo in spremembe opravil ostanejo pripisani dejanskemu uporabniku, ki jih je vnesel oziroma uredil. Profil osebe brez računa sam po sebi ne ustvari prijave, dostopnih pravic ali prejemnika potisnih obvestil.
- Dodajanje oseb in vodenje opravil zanje deluje lokalno brez strežnika, s trajno hrambo ter kopijo/obnovo. Morebitno deljenje teh profilov in opravil v skupnem gospodinjstvu je izrecno ter upošteva pravice tega prostora.

Ob zasnovi dorečemo, kdo prejema opomnike za taka opravila ter kako člana pozneje izrecno povežemo z njegovim računom, če ga ustvari, ob ohranitvi povezanih opravil. Ta zapis je izvor zahteve; uporabnik je pozneje istega dne izrecno odobril izvedbo in interno izdajo.

## Opomba za prihodnjo nadgradnjo — potrditev registracije in veljavnost prijave

**Aktualni status:** Izvedba 8. oktobra: jasna potrditev ustvarjenega računa in preverjene e-pošte ter zmožnostno podaljševanje aktivne seje so preverjeni in poslani v Git v commitu `54f3061`. FamilyHub 0.6.1+ ohrani isti bearer/napravo in v zadnjih sedmih dneh podaljša sejo na 30 dni; preklicana ali potekla seja se ne obnovi. Spodaj ostaja izvorni zapis zahtev.

**Povratna informacija uporabnika, 8. oktober 2026; za zdaj zapis za nadgradnjo, brez spremembe aplikacije.** Pri prvem Android preizkusu je uporabnik poročal, da je ustvarjanje računa s kodo uspelo, vendar ni dobil jasne potrditve uspeha ali poziva k prijavi. Datum izteka seje je povzročil dodatno nejasnost.

Pregled kode potrjuje, da `auth.enroll` ob ustvarjanju računa izda tudi napravno sejo, odjemalec pa jo shrani in uporabnika samodejno prijavi. Ločena ponovna prijava zato ni potrebna. Tok nima izrecnega sporočila o uspešno ustvarjenem računu. Strežnik trenutno izda sejo za 30 dni (2.592.000 sekund), brez samodejnega podaljševanja; datum pomeni veljavnost prijave na napravi, ne življenjske dobe računa ali podatkov.

**Dopolnitev istega preizkusa:** uporabnik je dejansko prejel e-pošto s potrditveno kodo in poroča o uspešni potrditvi naslova v aplikaciji. Tudi ob tem ni dobil jasnega sporočila o uspehu. To potrjuje prejem in uporabniški preizkus preverjanja e-pošte; obnova gesla in druge vrste obvestil s tem še niso preizkušene.

Predvidena izboljšava:

- Po uspehu jasno prikazati »Račun je ustvarjen. Prijavljen si kot …« ter preiti na pregled povezanega računa z razvidnim strežnikom in naslednjimi koraki. Ne zahtevati druge prijave, kadar je seja že uspešno shranjena.
- Če je račun ustvarjen, shranjevanje prijave pa ne uspe, jasno usmeriti v prijavo z ustvarjenim računom; uporabnik naj ne ponavlja ustvarjanja s porabljeno kodo.
- Po uspešni potrditvi e-poštne kode prikazati »E-poštni naslov je potrjen«, zapreti vnos kode in osvežiti vidno stanje naslova v nastavitvah računa. Uspeh prikazati šele po strežniški potrditvi, ne že ob zahtevi za pošiljanje kode; napaka naj ostane jasno ločena.
- **Potrjena zahteva uporabnika, 8. oktober 2026: seja se mora samodejno podaljševati.** Ob običajni uporabi naj uporabnik ostane prijavljen brez ponovnega vnosa gesla vsakih 30 dni. Zahteva je zdaj izvedena v commitu `54f3061`; uporaba potrebuje strežnik z zmožnostjo `sessionRenewal`.
- Prikaz veljavnosti uskladiti s samodejnim podaljševanjem, da tehnični datum izteka ne daje vtisa zaprtja računa ali obvezne mesečne prijave. Odjava, preklic naprave, sprememba gesla in deaktivacija računa morajo še vedno ustaviti dostop; podaljševanje preklica ne sme obiti. Podrobnosti obnove seje in dolgotrajne odsotnosti ostajajo predmet zasnove. Začasen izpad povezave ne sme izbrisati lokalnih ali čakajočih podatkov in ne konča osnovne lokalne osebne uporabe.
- Ohraniti izrecno izbiro osebne sinhronizacije; uspešna registracija ali podaljšanje seje je ne smeta samodejno vključiti.

Viri preverjenega trenutnega vedenja: `NativeEnrollmentService::execute`, `NativeAuthService::issue`, `CollaborationAccountRecovery.enroll`, `CollaborationAccountActions._authenticate` in `showAccountEnrollment`. Pri izvedbi preveriti jasen uspešen zaključek, napako shranjevanja seje, samodejno podaljševanje, zavrnitev podaljšanja po preklicu ter vrnitev po izpadu povezave brez izgube lokalnih ali čakajočih podatkov.

## Opomba za prihodnjo nadgradnjo — organizacije in izbira prostora

**Aktualni status:** Izvedba 8. oktobra: enotna izbira osebnega prostora, doma, organizacije in njenih projektov je izdelana. Projekti imajo izrecna članstva in finančne pravice; članstvo organizacije jih ne odpre samodejno. Arhiviranje je obnovljivo in ohrani vsebino. Končne dokaze vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md). Spodaj ostaja izvorni zapis zahtev.

**Potrjena smer uporabnika, 8. oktober 2026; za zdaj zapis za nadgradnjo, brez začetka izvedbe.** Dodati prostor **Organizacija** za podjetje, zadrugo ali društvo, na primer TriparNA. Trenutna izvedba podpira osebni prostor, gospodinjstvo in samostojen deljeni projekt; organizacija z lastnimi projekti in članstvi še ni izvedena.

Dogovorjena smer:

- Z istim uporabniškim računom preklapljati med prostori, na primer **Osebno / Dom / TriparNA**, z jasno prikazanim trenutno izbranim prostorom na telefonu in namizju.
- Ustvariti in poimenovati organizacijo ter v njej voditi več projektov, sodelavce, opravila in skupne termine.
- Pri ustvarjanju projekta jasno izbrati, kateremu prostoru pripada in kdo ga vidi. Osebni projekti ostanejo zasebni, dokler uporabnik izrecno izbere deljenje.
- Ločiti članstvo v organizaciji od dostopa do posameznih projektov. Zunanjemu sodelavcu omogočiti dostop samo do izbranega projekta, brez samodejnega dostopa do drugih projektov ali vsebine organizacije.
- Po izbiri vključiti finance organizacije oziroma projekta z ločenimi pravicami za ogled in urejanje. Članstvo ali dostop do opravil sama po sebi ne odpreta financ; osebne in gospodinjske finance ostanejo ločene.
- Poenotiti pregled projektov in izbiro prostora, da uporabniku za razumevanje osebnih in skupnih projektov ni treba prehajati med nepovezanima pregledoma. Nastavitve računa in upravljanje članov ostanejo jasno dostopni.

Ob zasnovi dorečemo vloge, dedovanje oziroma izrecno omejevanje projektnih pravic, lastništvo ter način premika ali kopiranja obstoječega projekta. Trenutno kopiranje osebnega projekta ustvari ločeno skupno kopijo; nadgradnja ne sme samodejno preseliti ali deliti obstoječih podatkov. Ohrani se local-first osnova z izbirno strežniško sinhronizacijo, preverjanjem pravic na strežniku ter obvestili, omejenimi na vsebino, do katere ima prejemnik dostop.

## Opomba za prihodnjo nadgradnjo — preglednost na manjših telefonih

**Aktualni status:** Izvedba 8. oktobra: oznake, razmiki in obrazci ob tipkovnici so popravljeni in preverjeni pri 320/360/390 px ter 2× povečavi; commit `54f3061` je poslan v Git. Po pregledu izdaje 1.1.0 (3) je uporabnik opozoril na izpuščen preizkus levega menija in izrecno naročil njegovo izvedbo. Dopolnitev uporablja levi zložljivi meni na telefonu pod 600 px; po novem posnetku je izbor prostora prestavljen v glavo ob ikono, ime Jivie ostane v meniju, + Nov prostor pa je možnost dropdowna. Android 1.1.2 (5) je interno objavljen; tablična in namizna navigacija ostaneta ločeni. [Izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md) vodi končne dokaze in novo izdajo. Spodaj ostaja izvorni zapis zahtev.

**Povratna informacija uporabnika, 8. oktober 2026; za zdaj zapis za nadgradnjo, brez spremembe aplikacije.** Na Samsungu Galaxy S25 je prikaz preveč prostoren glede na razpoložljivo višino. Priloženi posnetek obrazca **Dodaj dogodek** z odprto tipkovnico SwiftKey kaže delno odrezano oznako polja **Naslov**; uporabnik potrjuje, da je obrazec pomaknjen povsem na vrh. Naslov dialoga je viden. To je opažanje dejanskega prikaza; vzrok odrezovanja še ni preverjen v kodi.

Želeni obseg:

- Prilagoditi tipografijo manjšim zaslonom: nekoliko manjša, še dobro berljiva pisava za naslove in obrazce ter bolj uravnotežena razmerja med besedilom, polji in gumbi.
- Zmanjšati odvečne navpične razmike, notranje odmike in začetno višino večvrstičnih polj, da je na voljo več uporabne vsebine. Ohraniti dovolj velike površine za dotik.
- Popraviti odmike in odrezovanje ob robovih drsne vsebine, da so oznake polj v celoti vidne tudi na skrajnem vrhu. Zmanjšanje pisave samo po sebi ni dokaz odprave te napake.
- Pravilno prilagoditi višino in drsenje ob odprti tipkovnici: izbrano polje, njegova oznaka in napaka morajo biti dosegljivi, prav tako gumba Shrani/Prekliči. Preveriti prekrivanje s stalnim spodnjim delom dialoga in obnašanje ob razširitvi načrtovanega termina.
- Pregled razširiti na druge obrazce in glavne mobilne zaslone. Za daljše obrazce preučiti urejanje čez celoten zaslon, če dialog preveč omejuje prostor; to je možnost za zasnovo, ne že izbrana rešitev.

**Dodatna zamisel uporabnika, 8. oktober 2026:** za telefone velikosti **Samsung Galaxy S25** preučiti levi zložljivi meni, v katerem so navigacijske možnosti skrite do odprtja, namesto stalnih spodnjih zavihkov. Cilj je sprostiti prostor za vsebino. Pri mobilnem predogledu primerjati pridobljeni prostor, preglednost in dostopnost glavnih funkcij s sedanjo spodnjo navigacijo. To je predlog za preizkus, ne dokončna odločitev o zamenjavi. Uporabnik računalniške in tablične postavitve še ni preveril; ta povratna informacija se nanaša izključno na velikost S25 in ne določa sprememb za računalnik ali tablico.

Pri izvedbi preveriti S25 na fizični napravi, manjše logične širine (320–390), odprto/zaprto tipkovnico, privzeto in povečano sistemsko pisavo ter vrh in dno obrazca. Ne izključiti uporabnikove nastavitve povečave besedila. Ohraniti potrjeno svetlo/temno temo ter ločeno namizno postavitev. Ta opomba ne pomeni, da je popravek že v trenutni testni izdaji.

## Opomba za prihodnjo nadgradnjo — strošek neposredno pri opravilu

**Aktualni status:** Izvedba 8. oktobra: opravilo in pripadajoči strošek uporabljata isti finančni vnos. Lokalni zapis in skupna oddaja para sta atomarna; rok premakne načrtovani datum, plačanega datuma ne prepiše, izbris opravila odveže in ohrani strošek. Končne dokaze vodi [izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md). Spodaj ostaja izvorni zapis zahtev.

**Zahteva uporabnika, 8. oktober 2026; za zdaj zapis za nadgradnjo, brez začetka izvedbe.** Opravilo lahko vsebuje strošek, ki ga uporabnik doda že pri ustvarjanju ali urejanju opravila. Ta strošek se prikaže tudi v financah, brez ponovnega ročnega vnosa v finančnem modulu.

Želeni obseg in povezava z obstoječimi pravili financ:

- V obrazcu oziroma podrobnostih opravila omogočiti izbirni vnos stroška z zneskom, valuto in potrebnimi finančnimi podatki; uporabiti enaka pravila za plačnika, finančni račun in avtorja kot v financah.
- **Dopolnitev uporabnika, 8. oktober 2026: datum stroška je vezan na rok opravila.** Datuma ni treba vnašati posebej; ob spremembi roka se ustrezno premakne tudi datum načrtovanega stroška v financah. Datum dejanskega plačila ostane ločen, da sprememba roka ne prepiše že evidentiranega plačila. Ob zasnovi določiti še ravnanje pri opravilu brez roka oziroma ob odstranitvi roka.
- Ustvariti en finančni zapis, povezan z opravilom. Prikaz in urejanje pri opravilu ter v financah uporabljata isti zapis, da se znesek v seštevkih ne podvoji. Iz financ mora biti razvidno, na katero opravilo in morebitni projekt se nanaša.
- Jasno ločiti načrtovani strošek od dejanskega oziroma plačanega. Dokončanje opravila samo po sebi ne potrdi plačila; sprememba stroška se uskladi v obeh pogledih.
- Pri skupnem opravilu upoštevati izbrani finančni prostor in ločene pravice za ogled/urejanje financ. Dostop do opravila ne razkrije zasebnega stroška in samodejno ne deli osebnih financ; preverjanje velja tudi na strežniku.
- Vnos osebnega opravila in povezanega stroška mora delovati lokalno brez povezave ter biti vključen v kopijo/obnovo. Pri vključeni sinhronizaciji ponovitev zahteve ne sme ustvariti dodatnega stroška; finančni zapis ostane v ločeni finančni pogodbi.

Ob zasnovi dorečemo možnost več stroškov na enem opravilu, povezovanje že obstoječega finančnega zapisa ter obnašanje ob kopiranju, premiku ali izbrisu opravila. Brisanje opravila ne sme tiho izbrisati finančne evidence. Ta opomba ne pomeni, da je povezani vnos že na voljo v trenutni testni izdaji.

## Tehnične meje prve izvedbe

Ohranimo Flutter, Riverpod, GoRouter in lokalizacijo. Stari izračuni so referenca za razumevanje arhiva; o ponovni uporabi odločajo ugotovitve pregleda. Nova domena je ločena v `lib/organizer/{domain,data,state,presentation}`. Obstoječi `lib/features` ter `lib/kanboard` sta trenutno še dostopna, vendar njuna trajna ohranitev ni pogoj prenove.

Prva osebna etapa je uporabljala Hive v ločeni shrambi: lokalni ID-ji in atomarno zamenjana vrednost s celotnim osebnim stanjem. Omejitev je bilo ponovno zapisovanje celotnega stanja. Skupne zbirke so zato dobile transakcijsko SQLite bazo prek Drift 2.35.1. Etapa osebne sinhronizacije 5. oktobra zdaj tudi osebne zapise seli v posamezne SQLite vrstice (lokalna schema 4), z atomarno oznako uspeha in ohranjenim izvornim Hive. Pokvarjen ali novejši vir se ne ponastavi. Osebni zapis, odhodna operacija in vezava zasebnega prostora imajo skupno transakcijo; sama selitev ne vključi pošiljanja na strežnik.

Izvedena osebna shramba ima omejitev 10 MiB in 50.000 zapisov ter podpira eno aktivno repository instanco. Sočasno urejanje iste zbirke v več procesih ali zavihkih ni podprto. Lokalna baza in izvozi JSON še nimajo dodatnega šifriranja. Uvoz je nedestruktivno združevanje; vsak že obstoječ ID zavrne celotno operacijo, tudi če je vsebina enaka. Izbris projekta ohrani njegova opravila, dogodke in finančne zapise brez povezave na projekt; izbris nakupovalnega seznama odstrani njegove artikle po potrditvi.

Prva etapa je vsebovala lokalni seznam zapadlih opravil; družinska nadgradnja dodaja sistemske opomnike in enotni center. Denar uporablja točne celoštevilske najmanjše enote za EUR, USD, GBP in CHF; ponavljajoče finance in projekcije ostajajo v starem odjemalcu do prenosa.

Prvi strežniški dokaz FamilyHub 0.1.0 z JSON-RPC in povabili v stare projekte ostaja ločen ter privzeto izključen. FamilyHub 0.2.0 je dodal Native API v1 z napravno sejo, registracijo prek povabila in sinhronizacijo lastnih tabel. V namestitvenem paketu je tudi ta API privzeto izključen; dovoljen je v izoliranem razvojnem okolju. FamilyHub 0.3.0 je razširil pogodbo s sync2, ločenimi financami, inboxom, opomniki in SMTP vrsto (schema 7). FamilyHub 0.4.0 dodaja izbirno FCM registracijo in dostavno vrsto (additivna schema 8); Firebase/APNs še nista konfigurirana. Novi zapisi se ne urejajo v starem Kanboardovem spletnem vmesniku. Produkcijski `DB_DRIVER=mysql` in izvozna različica 10.11.19 sta potrjena z arhivom. Nova strežniška matrika vključuje SQLite, MySQL 8.4.11 in MariaDB 10.11.19; to še ne dokazuje učinkovite konfiguracije spletnega gostovanja.

## Lastništvo in preverjanje

| Tok dela | Lastništvo | Zahtevani dokaz |
| --- | --- | --- |
| `local_core` | Nova domena, podatkovna plast, Riverpod stanje, testi podatkov | Restart, CRUD, zneski, napaka zapisa, uvoz brez izgube |
| `mobile_desktop_ui` | Tema, zagon, router, prikaz, SL/EN prevodi, UI testi; nato ločitev starih AI pogovorov | Telefon 320/390, namizje 1280, realni podatki in uporabna prazna stanja; izolacija identitet |
| `kanboard_backend` | `server/`, `docs/server/`, Docker, vtičnik; nato varna stara povezava in predpomnilnik | Verzije, dovoljeni/zavrnjeni klici, enkratna povabila, paket; poverilnice, HTTPS, ločitev računov |
| Glavni agent | Pogodbe, dokumentacija, integracija, neodvisni pregled | Skupni analyze/test/build in pregled rezultatov; napotki ter popravki prek podagentov |

Podagenti spreminjajo samo dogovorjene datoteke. Posodobitve `pubspec.lock` usklajuje glavni agent, `gen-l10n` izvaja lastnik UI. Uporabnikova verzija `1.0.12+12` se ohrani. Testiranje ne piše na produkcijski Kanboard in ne objavlja aplikacije.

## Dnevnik izvedbe

Naslednji rezultati do arhiva pripadajo prvi lokalni etapi. Novo deljenje ima ločen [dnevnik in merila](SHARING_MILESTONE.md); prejšnje gradnje niso dokaz novih sprememb.

- Skupni `flutter test --reporter expanded`: **78/78 uspešnih**. Končni `flutter analyze`: **35 obstoječih info**, brez error/warning; normalen ukaz zaradi info še vrne kodo 1. `git diff --check` uspešen. Pri novem jedru, prikazu in varnostnih shrambah ni novih analyze ugotovitev.
- Lokalno jedro: 19 uspešnih testov, vključno z dejanskim ponovnim odpiranjem Hive, zaporednimi spremembami, revizijami, odpovedjo zapisa/flush, veljavnim in neveljavnim uvozom, obnovo providerja ter časovnim/lifecycle osveževanjem opomnikov.
- Novi vmesnik: 19 uspešnih UI/widget testov, širine 320/390/1280, svetla/temna tema, SL/EN, prazna in napolnjena stanja, urejanje, navigacija, tipkovnica in ponovni zagon prikaza. Preverjeno tudi odpiranje uvoženega datuma zunaj običajnih meja izbirnika.
- Varna stara povezava: 26 novih testov za varno hrambo in migracijo, preusmeritve, globalno identiteto, dnevnike, ločen predpomnilnik ter pozne odgovore ob odjavi. 10 dodatnih testov preverja AI shrambo/privolitve in menjavo identitete v odprtem pogovoru. Obstoječi 4 testi finančne projekcije ostajajo uspešni.
- FamilyHub: 81 uspešnih HTTP preverjanj na SQLite in 81 na MySQL 8.4.11; glavni agent je neodvisno ponovil SQLite sklop. Preverjeni so tudi sintaksa PHP, sveža namestitev s privzeto izključenimi povabili in determinističen ZIP. Podrobnosti v `docs/server/README.md`.
- Končne gradnje: web release, macOS debug in iOS simulator debug uspešne. Flutter 3.47.2 je avtomatično preselil Apple projekta na Swift Package Manager s preostankom CocoaPods, iOS na UIScene in najmanjši različici na iOS 15/macOS 12. Podpisana izdaja in Keychain na napravi še nista preverjena. WebAssembly zaradi obstoječega vtičnika varne hrambe ni potrjen; redna JavaScript gradnja uspe.
- Android debug APK uspe brez `skipDependencyChecks`; paket `com.takndev.kanbanconnect`, različica `1.0.12+12`. Minimalna uskladitev orodij: Gradle 8.14 z uradnim SHA256, AGP 8.11.1, Kotlin 2.2.20. Izolirana konfiguracija brez zasebnih podpisnih datotek omogoči `preDebugBuild`, `preReleaseBuild` pa pravilno zavrne. Za lokalni ukaz je bil uporabljen pravilen `JAVA_HOME`, brez trajne spremembe okolja.
- macOS integracija je odkrila, da ključ Keychain skupin v adhoc Debug/Profile zahteva razvojni certifikat tudi s praznim seznamom. Debug/Profile zdaj tega ključa ne dodaja in končna gradnja uspe; Release ohrani skupino s podpisnim prefiksom. Neuspeh varne shrambe ostane izrecna napaka, brez plaintext nadomestila. Gradnja sama ne potrdi delovanja Keychaina na podpisani napravi.
- Brskalniški preizkus dejanske spletne gradnje: prvi lokalni zagon brez prijave, slovenski svetli prikaz, ustvarjanje opravila/seznama/artikla, odkljukanje in ohranitev po ponovnem nalaganju. Dejanski izvoz JSON preverjen; ponovni uvoz iste kopije pravilno zavrne podvojene zapise. Testni podatki so ločeni na lokalnem izvoru, brez produkcijskih zapisov.
- Končni vizualni pregled spletne gradnje pri 390 px in namizni širini: prilagoditev navigacije in prikaza uspešna, v brskalniku ni opozoril ali napak. Lokalni ogled teče na `http://127.0.0.1:18770/`; posnetka sta v `build/qa/vsakdan-mobile.jpg` in `build/qa/vsakdan-desktop.jpg`. Namenjena sta pregledu, ne produkcijski objavi.

- 2026-10-04: začetek implementacije na veji `codex/vsakdan-foundation`; obstoječe uporabnikove spremembe ohranjene. Trije GPT 6.1 Sol / high podagenti delajo v dogovorjenih ločenih področjih. Docker Desktop je dosegljiv.
- 2026-10-04, pozneje: celovit [pregled stare kode in nove osnove](CODEBASE_AUDIT.md), spremenjena smer na samostojen arhiv in nadaljnjo gradnjo brez obvezne migracije vseh starih podatkov. Prek Softaculous je ustvarjena in prenesena celotna kopija baze/datotek; obnovljena je lokalno brez omrežja. Neodvisno preverjenih 48 tabel/2.180 vrstic, finančna vsebina in vseh 8 priponk. Izdelana sta lokalni izvoznik in samostojen arhivski brskalnik; brez namestitve vtičnika ali urejanja poslovnih podatkov na produkciji.
- Arhivska orodja: 26 Python in 12 JavaScript testov uspešnih. Dejanski arhiv je preverjen v lokalnem brskalniku na telefonu in namizju, vključno z iskanjem, zaključenimi nalogami, finančnim prikazom in prenosom priponke z enako kontrolno vsoto. Obnovitveni MySQL je ustavljen; arhiv za pregled ne potrebuje baze ali Kanboarda. Neposredni `file://` zagon ostaja ročno preverjanje zaradi omejitve avtomatizacijskega brskalnika.

- Nadaljevanje po arhivu: trije isti podagenti gradijo prvo uporabno deljenje. Dodani so lastne strežniške tabele in Native API, transakcijska SQLite odhodna vrsta ter prilagodljivi tokovi za račun, skupne prostore, povabila in konflikte. Glavni agent preverja meje identitete, ponovljivost, odjavo, sočasne spremembe in dejansko aplikacijo. Rezultati: 126 Flutter testov, posebej 1 dejanski HTTP preizkus dveh odjemalcev, 93 native +81 legacy strežniških preverjanj na vsaki od treh baz, uspešne končne web/Android/macOS/iOS simulator gradnje. Glavni agent je v dejanski aplikaciji preveril povabilo in registracijo druge osebe ter shranjevanje, ponovni zagon in uskladitev po ustavitvi testnega strežnika. Podrobnosti in omejitve so v dokumentu mejnika.

- Družinska nadgradnja: skupne dodelitve/dogodki, dnevni pregled/časovnica, trajni inbox, lokalni sistemski opomniki, skupne finance in SMTP vrsta. Končni Flutter nabor 176 PASS, posebej oba dejanska HTTP testa PASS, analyze 35 podedovanih info. iOS simulator potrjuje tudi dostavo po prekinitvi procesa in odpiranje točnega opravila. Podrobna matrika, popravki pravic/omejitev in meje oddaljenega push so v [družinskem mejniku](FAMILY_UPGRADE.md).

- Priprava FCM 5. oktobra: 226 Flutter PASS, oba dejanska HTTP testa PASS, 352 strežniških preverjanj na vsaki od treh baz, 7 testov konfiguracijskega orodja. Android/iOS adapter, varna napravna registracija, trajni preklici in skupine so pripravljeni; resnična dostava in produkcijska namestitev še nista potrjeni. Aktualni dokazi in meje so v [FCM mejniku](FIREBASE_PREPARATION.md).

- Osebna sinhronizacija in obnova 5. oktobra: **297 Flutter PASS in trije dodatni dejanski HTTP PASS**; **436 strežniških preverjanj na vsaki od treh baz**. FamilyHub 0.5.0/schema 9 doda prvi račun z upraviteljsko kodo, preverjanje e-pošte, obnovo gesla in lastniški zasebni prostor. Odjemalec doda SQLite schema 4, izrecno sinhronizacijo lastnih naprav ter šifrirane kopije z obnovo in ohranjenimi operacijami. Končne spletna, Android debug, iOS simulator in macOS debug gradnje so uspešne. Google Play Console ostaja odložen. [Mejnik](PERSONAL_SYNC_AND_RECOVERY.md) vodi dejanske dokaze, omejitve obnove in še nenastavljene produkcijske storitve.
