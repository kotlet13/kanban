# Povabila po e-pošti

## Potrjen uporabniški tok — 10. oktober 2026

Lastnik prostora v Nastavitvah prostora → Člani vnese **e-poštni naslov** in
vlogo. Strežnik povabilo dostavi po pošti. Povabljeni odpre povezavo, nov račun
ustvari z lastnim uporabniškim imenom in geslom, obstoječi uporabnik pa se prijavi.
Po prijavi ga čaka povabilo z imenom prostora, pošiljateljem in vlogo. Šele izrecni
**Sprejmi povabilo** ustvari članstvo in odpre prostor. Dodatna skrbniška potrditev
registracije ni potrebna.

Prejšnja izvedba povabila na uporabniško ime ni izpolnjevala tega dogovora.
Stara povabila ostanejo berljiva; nova možnost je verzionirana strežniška zmožnost.
Registracije ne enačimo s samodejnim sprejemom članstva.

## Merila izvedbe

- Obstoječe račune povezujemo samo prek potrjene e-poštne identitete. Nepotrjen
  naslov v starem Kanboardovem profilu ne zadostuje za dodelitev dostopa.
- Pošiljatelj ne dobi registracijske skrivnosti ali podatka o obstoju računa.
  Prejemnik ima časovno omejeno, preklicljivo povabilo v svojem poštnem predalu.
- Pošiljanje uporablja obstoječo šifrirano poštno vrsto in ločeni cron. Besedilo
  aplikacije razlikuje uvrstitev v vrsto od dejanske dostave.
- Registracija, prijava in sprejem imajo jasna sporočila o uspehu ali napaki.
  Čakajoče povabilo se ohrani med koraki, vključno z izgubljenim odgovorom;
  skrivnosti niso v navadnih nastavitvah, dnevnikih ali kopijah podatkov.
- Povezava iz pošte ponudi odpiranje aplikacije in ročni prenos kode. Odprtje
  povezave, predogled poštnega odjemalca ali spletni obisk sam ne sprejme povabila.
- Napačen račun, potek, preklic, sprememba identitete, ponovljen sprejem in
  sočasne zahteve ne odprejo tujega prostora ali ponovno podelijo odvzetih pravic.
- Osebno lokalno delo, trenutne seje, podatki in stare sinhronizacijske operacije
  ostanejo ohranjeni. Nadgradnja ne zahteva ponastavitve baze.

## Razdelitev in preverjanje

Strežniški podagent pripravi pogodbo, aditivno migracijo, dostavo in PHP teste.
Podagent podatkovne plasti pripravi modele, stanje, varno nadaljevanje povabila
in povezave. UI podagent pripravi obrazce, slovenska/angleška besedila ter
preizkuse. Glavni agent pregleda povezavo vseh treh delov, paket, nadgradnjo
testnega gostovanja in novo podpisano namizno gradnjo.

Preverimo SQLite, MySQL in MariaDB, dejanski lokalni SMTP zajem brez zunanje
pošte, odjemalčeve regresije in namizni zagon. Prejem resnične e-pošte ter sprejem
z drugim računom na Macu sta ločena uporabniška preizkusa, ki sledita pripravi.

## Stanje izvedbe

Izvedba je zaključena v veji `codex/email-invitations`, iz osnove `main` pri
`60bd43d`. Testni `jivie-test.triparna.si` je nadgrajen na FamilyHub
**0.10.0/schema14**, nova podpisana Jivie pa je odprta na Macu. Produkcija ostaja
nespremenjena. Različica aplikacije ostane **1.2.0 (14)**; ta korak ne vključuje
commita, pusha ali nove izdaje v trgovini. Resnični prejem pošte in fizični
preizkus dveh uporabnikov sledita spodnjim korakom.

### Preverjena strežniška izvedba

FamilyHub **0.10.0/schema14**, [pogodba2](server/email-invitation-api-contract.md),
uporablja dve novi nullable koloni in eno poštno tabelo. Stare seje, identitete,
operacije in članstva se pri migraciji ne prepisujejo. Obstoječi cron
`account-mail.php` dostavlja tudi povabila; dodatni worker ali poverilnica nista potrebna.

- SQLite, MySQL in MariaDB: 77 novih kontrol povabil + 48 računov + 36 izbrisa +
  93 Native API kontrol na bazo, skupaj **762 PASS**; **70 PHP lint PASS**.
- Nove kontrole vključujejo dejanski izolirani SMTP zajem, sočasno registracijo,
  potrditev naslova, sprejem in preklic med pošiljanjem, izgubljen odgovor ter
  izbris/ponovno ustvarjanje računa. Nobena testna pošta ni šla resničnemu prejemniku.
- Ločen dejanski Dart → HTTPS → FamilyHub → SMTP preizkus je uspešen; odjemalec
  zaupa izključno namenski lokalni CA, brez obhoda preverjanja certifikata.
  Preverjena sta ponovna odprtja SQLite po izgubljenem odgovoru registracije in sprejema.
- Strogo omejen namestitveni paket: **10 paketnih testov PASS**, 76 datotek;
  SHA256 `5f85e5b6c6716b4eb1baaeecf9602cab8c1dd9f83f7eeb592714cfc9e4ed032e`.
- Ločena pomočnika `server/scripts/upgrade-cpanel-jivie-email.php` in `.sh`
  zahtevata obnovo dejanske kopije pred aktivacijo. **32 kontrol pomočnika in
  21 dejanskih MariaDB kontrol PASS**. Stara nadgradnja prostorov ostane nespremenjena.

Potrditev oddaje v poštno vrsto ni dokaz prejema. Po SMTP sprejemu in izgubljenem
odgovoru je mogoča ponovna dostava iste pošte; ponovljen sprejem ne podvoji članstva.

### Preverjen odjemalec in gostovanje

- Celotni Flutter nabor: **885 PASS / 12 opt-in HTTP preskočenih**. Dve začetni
  regresiji sta bili zastareli testni zmožnosti; popravljeni fixture ohrani
  preverjanje menjave/arhiviranja prostora in preprečevanja napačnega pošiljanja.
- Analiza: **brez napak in opozoril**, 35 podedovanih informacijskih lintov.
- Ciljni testi preverijo stabilen request ID ob ponovitvi, razločen prikaz
  registracije in sprejema, čakajoča povabila ter izbor sprejetega prostora.
- Varna hramba in koordinator povezav uporabljata skupno zaporedno vrsto.
  Tri nadzorovane sočasnosti preverijo, da starejše shranjevanje ali brisanje
  ne izgubi nove povezave. Skrivnosti ne preidejo v SharedPreferences ali kopije.
- Končni dejanski **Dart → TLS → FamilyHub → SMTP: 1 PASS**, ponovljen po
  popravku vrste s svežimi sintetičnimi računi. Preverjeni so izgubljeni odgovori,
  ponovni zagon SQLite, prijava obstoječega uporabnika in zavrnitev druge identitete.
  Neskrivni dnevnik: `build/qa/email-invitations-final/dart-http-rerun/flutter-http-test.log`.
- **Android debug in podpisana macOS arm64 gradnja PASS**. Podpis, profil,
  konkretna Keychain skupina in vseh **318 zamrznjenih vhodnih datotek** so preverjeni.
  SDK, zaklenjene odvisnosti, platformne identitete ter različica ostanejo isti.
- [Dejanska nadgradnja testnega gostovanja](server/CPANEL_SETUP.md#15-e-poštna-povabila-10-oktobra--familyhub-0100--schema14)
  sledi obnovi 84 tabel, 169 vrstic in 583 zasebnih datotek v izolirani MariaDB
  10.11.19. Gesla, računi, serverId in dostava so ohranjeni; vsi cron delavci so
  se po odprtju znova izvedli. Produkcijska strežnika sta nespremenjena.

### Pripravljeni Mac in fizični preizkus

Nova aplikacija teče iz:
`build/qa/jivie-email-invitations-macos-20261010/SignedProducts/Debug/Jivie.app`.
Gre za podpisano razvojno gradnjo z obstoječo namizno identiteto
`com.example.kanban`, ne za Mac App Store izdajo. Odprt je Račun in deljenje →
Imam povabilo, s testnim naslovom in prazno kodo. Resnični račun ali geslo v tem
koraku nista bila vnesena. Dokazi podpisa in izvora so v isti mapi QA.

1. V novi gradnji se lastnik prijavi, izbere skupni prostor in v Nastavitvah
   prostora → Člani pošlje povabilo na drugi e-poštni naslov.
2. Prejemnik odpre poštno povezavo in aplikacijo; če sistem povezave ne odpre,
   uporabi ponujeni ročni prenos povezave/kode v Imam povabilo.
3. Novi uporabnik izbere uporabniško ime in geslo; obstoječi se prijavi.
   Nato posebej sprejme povabilo. Preverimo uspešno sporočilo in pravi prostor.
4. Na telefonu ostane prvi uporabnik, na Macu drugi. Preverimo skupno opravilo,
   spremembo v obe smeri, ponovni zagon in obvestilo.

**Trenutna Play izdaja 1.2.0 (14) še nima novega obrazca za e-poštna povabila.**
Do naslednje interne izdaje lahko prvi korak izvedemo na Macu kot lastnik, se
odjavimo in nato tam sprejmemo povabilo kot drugi uporabnik. Telefonski prvi
račun ostane prijavljen. Nova Android izdaja je ločen naslednji korak.

### Fizični preizkus predogleda — 10. oktober

Uporabnik je potrdil dejanski prejem povabila po e-pošti in uspešno odpiranje
Jivie na Macu prek spletnega gumba. Prvi klik **Preveri povabilo** je pokazal
napačno splošno sporočilo o neuspelem shranjevanju. Diagnostična podpisana gradnja
je reproducirala `CircularDependencyError`: `CollaborationController` je
invalidiral `securePendingInvitationProvider`, ki je odvisen od tega istega
kontrolerja. Izjema se je zgodila pred strežniškim predogledom; enako je vplivala
na **Nadaljuj do povabila** po ponovnem zagonu.

Koda povabila se je pravilno ohranila v varni shrambi. Zajet je samo tip izjeme
in sklad klicev, brez kode, podatkov HTTP ali poverilnic, v
`build/qa/email-invitations-preview-fix/safe-diagnostic.txt`. Začasni diagnostični
prikaz je odstranjen iz izvora. Prejšnjih 885 uspešnih testov ni zajelo te
povezave dejanskih providerjev; dodane regresije morajo uporabiti pravi kontroler
in ločeno preizkusiti celoten tok povezave po odjavi.

Popravek v `collaboration_provider.dart` uporablja neodvisen signal spremembe.
Projekcija še vedno opazuje identiteto računa, kontroler pa ne invalidira svojega
odvisnega providerja. Osvežitev po zaključku poskusa pokrije predogled, registracijo,
brisanje shranjenega povabila ter sprejem po kodi ali ID-ju, tudi po izgubljenem
odgovoru. Pravila registracije, pravic, strežniški API in varna hramba so isti.
**4 novi testi z resničnim kontrolerjem PASS** preverijo reaktivnost, ločen sprejem,
izgubljen odgovor, menjavo računa ter ohranitev novejše kode.

**33 ciljnih UI testov PASS**, vključno z dvema novima preizkusoma celotnega
odjavljenega toka native povezave pri 390 in 1280 px z resničnim kontrolerjem ter
opazovano projekcijo. Ločeni sintetični full-shell primer z odjavo med testom je
zastal v asinhroni testni pripravi in ni vključen kot dokaz uspeha; menjavo računa
preverjajo podatkovni testi. Celotna analiza ima **35 obstoječih info, brez napak
in opozoril**. Ta ciljna preverjanja dopolnjujejo zgodovinski nabor 885, ne pomenijo
ponovnega zagona vseh testov po popravku.

Na dejanskem Macu je z istim uporabnikovim povabilom potrjeno nadaljevanje iz
ponovno odprte aplikacije in uspešen strežniški predogled prostora ter vloge.
Gumb email2 se glasi **Ustvari račun**, saj sprejem članstva sledi posebej;
legacy fhi1 ohrani svoje prejšnje besedilo in vedenje. Račun ali članstvo med
diagnostiko nista ustvarjena. Strežnik, shema, SDK, odvisnosti in različica
aplikacije se v tem popravku ne spreminjajo.

Končna podpisana razvojna aplikacija tega popravka je
`build/qa/jivie-email-invitations-preview-fix-20261010/final2/SignedProducts/Debug/Jivie.app`.
Strogi podpis, isti certifikat/profil/skupina Keychain in vseh **318 vhodnih hashov**
so preverjeni. Ta artefakt nadomesti prejšnjo gradnjo pri nadaljevanju fizičnega
preizkusa; stare gradnje ostanejo ohranjene. Začetek registracije in sprejem
članstva ostaneta uporabnikova koraka.

### Ponovitev po zatikanju po registraciji — 10. oktober

Uporabnik je po ustvarjanju drugega računa zaprl aplikacijo, ker nadaljevanje ni
napredovalo. Ponovno odprta podpisana gradnja `final2` je ohranila prijavo in
potrjeni e-poštni naslov. Strežniški pregled je potrdil obstoj drugega računa;
registracija je torej uspela. Sveži standardni predogled izbrisa je pokazal
**0 zasebnih/skupnih zapisov, 0 članstev in 1 napravo/sejo**. Sprejem prostora
še ni bil opravljen.

Na uporabnikovo izrecno zahtevo je pripravljen običajni aplikacijski izbris.
Uporabnik je sam vnesel ponovno overitev in potrditev ter izvedel izbris.
Naknadni omejeni read-only pregled testne baze je potrdil **0 ustreznih
uporabnikov, 0 Native identitet, 0 potrjenih e-poštnih identitet in 0 povabil
za izbrisani drugi račun**. Neposrednega SQL brisanja, spreminjanja gesla ali
izdajanja nadomestne seje ni bilo. Prvi račun in produkcija nista bila predmet
posega. Za ponovitev je potrebno novo povabilo; prejšnja povezava je odstranjena
skupaj z računom.

Najden je drugi, ločen vzrok neskončnega napredka: `SharingPendingInvitations`
je primerjal identiteto objekta `PendingInvitation`. Predogled shrani nove
metapodatke in osveži varno projekcijo, ta pa vrne nov objekt istega povabila.
`didUpdateWidget` je zato spet sprožil predogled. Regresija z resničnim
kontrolerjem in providerji je v 20 okvirjih namesto ene zahteve zaznala deset.
To je napaka odjemalčevega prikaza po registraciji, ne dokaz neuspešne
registracije ali strežniškega zastoja.

Minimalni popravek primerja strežniški naslov, kodo in vezavo na račun.
Lastne spremembe metapodatkov (`serverId`, rok, ID povabila) ne sprožajo
ponovnega nalaganja. Obstoječa ločitev po računu/napravi in zaščita pred poznimi
odgovori ostaneta. Registracija še vedno ne sprejme članstva samodejno.

Sprememba povabila med že tekočim sprejemom se shrani kot zahteva za odloženo
osvežitev. Zaključek poskusa jo obdela tudi po izgubljenem odgovoru, zato novejše
povabilo ni samo varno shranjeno, temveč postane vidno brez ponovnega odprtja
zaslona. Dve novi regresiji z resničnimi providerji sta uspešni: stabilen
predogled po registraciji, novo povabilo in menjava računa ter novo povabilo med
sprejemom z izgubljenim odgovorom. Noben test ne sprejme novega povabila samodejno.

Končni ciljni nabor povabil: **31 PASS**. Analiza spremenjenega widgeta in novega
testa je brez ugotovitev; `git diff --check` je uspešen. Predhodni celotni nabor
921 uspešnih testov pripada zaključeni spremembi prikaza sinhronizacije; po tem
ozkem popravku je ponovno izveden navedeni ciljni nabor.

Nova podpisana macOS arm64 razvojna gradnja je
`build/qa/jivie-email-invitation-retest-20261010/SignedProducts/Debug/Jivie.app`.
Gradnja in strogi podpis sta uspešna; certifikat, profil, Keychain skupina ter
`com.example.kanban` ostanejo isti. Preverjenih je vseh **321 zamrznjenih vhodov**,
prejšnji `final2` artefakt je ohranjen. Nova aplikacija vključuje tudi dokončani
kompaktni prikaz sinhronizacije, ostaja pa **1.2.0 (14)**. Glavni agent jo je
zagnal in odprl prijavo z vpisanim naslovom testnega strežnika. Nadaljevanje
čaka prijavo lastnika za pošiljanje novega povabila; ponovna registracija in
izrecni sprejem z drugim računom v tej gradnji še nista fizično potrjena.
Ta korak ne vključuje commita, pusha, nove Android objave ali spremembe
strežniške kode/sheme. Dokazi gradnje so v `verification-summary.md` iste mape.

Lastnik se je nato prijavil v novo Mac gradnjo. Na njegovo izrecno izbiro je bilo
iz **Doma** poslano novo e-poštno povabilo z vlogo **Član**; aplikacija ga pokaže
med aktivnimi povabili in potrdi uvrstitev v poštno vrsto. Mac je odjavljen za
nadaljevanje kot drugi uporabnik. To še ni potrditev dejanskega prejema nove
pošte ali nove registracije/sprejema. Med pripravo je odkrit dodaten prikazni
rob: odstranitev starega neveljavnega shranjenega povabila ga lahko zaradi
takojšnjega nalaganja s starim widgetom spet shrani. Novo povabilo ga ob odprtju
nadomesti; ločeni minimalni popravek odstranitve in regresija sta v preverjanju.

Uporabnik je nato potrdil prejem nove pošte in izvedel registracijo drugega
računa. Dejanski AX pregled nove Mac gradnje potrjuje prijavljenega prejemnika,
potrjeni e-poštni naslov ter stabilno kartico **Povabilo čaka na tvojo odločitev →
Doma → Član → Sprejmi povabilo**. Neskončnega napredka po registraciji ni več.
To je fizična potrditev popravka zanke; ločeni sprejem in nadaljnje skupno delo
se preverjata posebej.

Uporabnik je nato izrecno sprejel povabilo. Dejanski izbor prostora kaže **Doma**,
Nastavitve prostora pa **Organizacija · Član · Deljeno** ter lastnika in drugega
uporabnika kot člana. Registracija → ločeni sprejem → pravo članstvo so fizično
potrjeni. Računski zaslon pa je nato pokazal porabljeno povabilo kot neveljavno:
ista težava zastarelega `widget.pending` prizadene tudi takojšnje nalaganje po
uspešnem sprejemu. Članstva ne razveljavi; pred končnim ponovnim zagonom je
potreben še popravek čiščenja shranjenega povabila.

Popravek po uspešni odstranitvi in uspešnem sprejemu uporabi
`_load(refreshSaved: true)`: najprej prebere aktualni
`securePendingInvitationProvider.future`, nato ponovno preveri sejo. Tako ne
uporabi starega `widget.pending` pred naslednjim izrisom. Začetno nalaganje,
ročna ponovitev in semantične spremembe ohranijo obstoječi vhod, da ne podvojijo
prvega predogleda. Neodvisni bralni pregled končne spremembe je uspešen.

Končni ciljni nabor po tem dodatku: **33 PASS**; štiri nove regresije pokrivajo
stabilen predogled po registraciji, novo povabilo ob izgubljenem odgovoru na
sprejem, odstranitev neveljavnega povabila in novo povabilo med odstranjevanjem.
Ciljna analiza in `git diff --check` sta uspešna. Dodaten eksperimentalni
widget scenarij za povsem uspešen sprejem se je ustavil v testni kombinaciji
resnične SQLite povezave in simuliranega časa; odstranjen je iz končnega nabora
in ni štet kot uspešen. Dejanski sprejem na Macu je potrjen ločeno zgoraj;
fizično čiščenje in ponovni zagon nove gradnje sledita spodaj.

Končna podpisana macOS arm64 razvojna aplikacija je
`build/qa/jivie-email-invitation-retest-cleanup-20261010/SignedProducts/Debug/Jivie.app`.
Gradnja, globok strogi podpis in vseh **321 vhodnih hashov** so preverjeni;
certifikat, profil, Keychain skupina, `com.example.kanban` in **1.2.0 (14)**
ostanejo isti. Prejšnja retest aplikacija ima vseh 152 datotečnih hashov
nespremenjenih. Dokazi so v `verification-summary.md/.json` iste mape.

Glavni agent je novo aplikacijo zagnal, zaprl star poziv za povezavo in na
računskem zaslonu odstranil porabljeno shranjeno povabilo. Kartica je izginila;
Nastavitve prostora so ohranile **Doma · Organizacija · Član · Deljeno** in oba
člana. Nato je aplikacijo dejansko zaprl in ponovno zagnal. Starega poziva ni
več; račun je ostal prijavljen in e-pošta potrjena, **Doma** izbran, na računskem
zaslonu ni stare kartice, seznam članov še vedno kaže lastnika in drugega člana.
Aplikacija je ostala odprta v Nastavitvah prostora za nadaljnji preizkus.

To potrjuje resnični tok novega prejemnika od e-pošte do članstva ter trajno
odstranitev starega povabila. Samodejno čiščenje takoj po novem uspešnem sprejemu
v cleanup gradnji ni bilo znova fizično ponovljeno, saj članstvo že obstaja;
uporablja isto popravljeno pot svežega branja. Skupno ustvarjanje/urejanje
projektov, opravil in financ med telefonom ter Macom ostaja naslednji ločeni
fizični preizkus. V tem koraku ni novega commita, pusha, Android izdaje ali
posega v strežniško kodo/shemo oziroma produkcijo.
