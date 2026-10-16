# Poenostavitev povabil, deljenja in ustvarjanja prostorov

Datum: 16. oktober 2026.

Po uporabnikovi izrecni potrditvi je prenova izvedena v lokalnem izvoru Flutter
in FamilyHub. Delo so opravili trije podagenti `gpt-6.1-sol` z razmišljanjem
`high`; glavni agent je pregledal spremembe, povezal tokove in izvedel skupno
preverjanje. Izhodišče je [analiza uporabniške poti](INVITATION_AND_SHARING_UX_ANALYSIS.md).

**To ni nameščena ali objavljena različica.** Produkcija, testna gostovanja,
javni FamilyHub repozitorij, Google Play in Apple niso bili spreminjani.
Ni novih resničnih povabil, računov, e-poštnih dostav ali spremembe uporabniških
podatkov. Različice, SDK, odvisnosti, zaklenjene datoteke in dovoljenja ostanejo isti.

## Kaj uporabnik dobi

| Naloga | Nova pot |
| --- | --- |
| Povabljenec brez aplikacije | Spletna stran povabila → **Namesti za Android** → navodilo za vrnitev v prvotno e-pošto → **Odpri v aplikaciji**. |
| Nov račun iz povabila | Namenski zaslon povabila → **Ustvari račun** → pregled dejanskega dostopa → **Pridruži se prostoru** → ločena pravila, kadar so potrebna → pravi prostor. |
| Obstoječ račun | Prijava samo, če je potrebna; nato isto povabilo in izrecna pridružitev. Obnova gesla ohrani cilj. |
| Prvi zagon z ikono | Neposredna možnost **Imam povabilo**, brez iskanja po računu ali ustvarjanja lastnega doma. |
| Deljenje povezanega prostora | Ikona ob prostoru → e-pošta ali uporabniško ime → **Pošlji**. Dostop je razložen ob obrazcu; dodatna možnost je samo ogled. |
| Deljenje lokalnega prostora | Ista ikona → po potrebi prijava → povezava točno tega prostora → povabilo. Ni ponovnega označevanja prostora na splošnem zaslonu. |
| Nastavitve → Poveži in sinhroniziraj | Nadaljuje se povezovanje izbranega prostora. Prazen prostor preskoči predogled vsebine; pri obstoječih podatkih ostane izrecni pregled prenosa. |
| Novo gospodinjstvo ali organizacija | V začetnem obrazcu je **Sinhroniziraj z oblakom**. Privzeto je izključeno. Vključeno ustvari en oblačni prostor; izključeno ohrani lokalno ustvarjanje brez računa. |

## Prejemnik povabila

[Namenski čarovnik](../lib/organizer/presentation/shared/invitation_wizard.dart)
ločuje prijavo, registracijo in pridružitev. Pri prijavi oziroma registraciji
vidiš kratek kontekst povabila, polja in naslednje dejanje. Podrobnosti dostopa
so zbrane pred gumbom za pridružitev. Registracija novega e-poštnega povabila
še vedno potrdi povabljeni naslov in prijavi uporabnika, **sama pa ne sprejme
članstva**. Stari pogodbeni tok ohrani svojo semantiko.

Neznan izvor zahteva kratko potrditev pred omrežnim predogledom oziroma oddajo
poverilnic. Pri ustreznem že prijavljenem računu ali predhodno potrjenem
povabilu ni dodatnega ročnega preverjanja. Strežnik ostane preverljiv kontekst;
koda ni polje običajnega toka. Ročna rezervna pot sprejme izvirno HTTPS
povezavo FamilyHub, povezavo aplikacije ali kodo z navedenim strežnikom.

Povabilo ostane v varni shrambi skozi prijavo, obnovo gesla in zaprtje zaslona.
Prijava iz povabila preverja tudi trajno identiteto strežnika pred oddajo
poverilnic. Menjava računa, novejše povabilo ali pozen odgovor ne nadaljuje
prejšnjega dejanja v drugem računu. Potrjeno članstvo se shrani pred odstranitvijo
žetona. Če poznejše odpiranje oziroma sinhronizacija odpove, uporabnik nadaljuje
z odpiranjem prostora; UI ne predstavlja uspešne pridružitve kot neuspešno.

Na Utripu je tudi [opozorilo na prejeta povabila](../lib/organizer/presentation/shared/received_invitation_notice.dart),
ki odpre samostojen seznam za izrecni sprejem. Tako ima povabilo na uporabniško
ime jasno vstopno točko tudi brez e-pošte. Povzetek ne razkriva imena prostora
na osnovnem zaslonu. Osveži se ob vrnitvi v aplikacijo, spremembi povabil in
vrnitvi s seznama; nima časovnega preverjanja v ozadju. Prikaz je vezan na račun
in napravo, zastarel odgovor drugega računa se skrije.

## Pravila in besedila

[Pravila sodelovanja](../lib/organizer/presentation/shared/content_moderation.dart)
so samostojen zaslon z navadnim besedilom, podatkom o upravljavcu, razširljivim
celotnim strežniškim besedilom in izrecno, privzeto neoznačeno potrditvijo.
Dejanja ostanejo dosegljiva na dnu zaslona. Že sprejeta aktualna pravila se ne
prikazujejo pri vsakem povabilu.

Po pridružitvi lahko uporabnik nadaljuje z ogledom brez sprejema pravil za
objavljanje; strežniška omejitev pisanja ostane. Pred pošiljanjem povabila ali
prenosom lokalnega prostora preklic pravil ne odda dejanja. Obrazec ohrani vnos.

Krajša slovenska in angleška besedila ohranijo pomembna dejstva: ali se deli cel
prostor ali samo projekt, skupne finance, sedanje in prihodnje projekte ter
pravice do urejanja, brisanja in upravljanja članov. Oznaka »Polni dostop« ne
skriva dejanskih pravic. Starih članstev in stare politike ne razširi zgolj nova
oznaka. Osebni lokalni podatki se zaradi prijave ali sprejema povabila ne prenesejo.

## Pošiljanje, ponavljanje in povezovanje

[Obrazec povabila](../lib/organizer/presentation/shared/scope_invitation_form.dart)
je vezan na prostor, iz katerega je odprt. Prejemnika se vnese enkrat; izbira
vloge je med dodatnimi možnostmi. Projektno povabilo ostane omejeno na projekt.
Enak ponovni poskus uporablja isto identiteto zahteve in jezik. Sprememba
računa, dovoljenj, izbranega prostora ali njegove politike prekine staro dejanje.
Po uspehu se pokaže potrditev in upravljanje članov tega prostora.

Na strežniku nova možnost `invitations3.create` sprejme e-pošto ali točno
uporabniško ime že obstoječega aktivnega računa FamilyHub. Username povabilo
je vezano na trajni ID računa; ne razkriva e-pošte in ne ustvari računa ali
članstva. Prejemnik ga izrecno sprejme v aplikaciji. Za novega uporabnika je
potrebna e-pošta. Ob izključenem SMTP lahko username povabila še vedno delujejo.

**Pošlji znova** uporablja novo atomsko operacijo `invitations3.resend`:
nastane novo povabilo, stara povezava se prekliče in njena nedokončana poštna
dostava ustavi v isti transakciji. Ponovitev iste zahteve vrne isti rezultat.
Že sprejetega povabila ni mogoče ponovno izdati na ta način. Prikazan je točen
datum in ura izteka; privzeta veljavnost ni bila samovoljno podaljšana.

[Kontekstno povezovanje](../lib/organizer/presentation/shared/connect_space_flow.dart)
ohrani prvotni lokalni ID. Ponovitev prenosa uporabi obstoječe trajne identitete
objave. Zaslon s seznamom vseh lokalnih prostorov ostane dosegljiv v računu za
splošno upravljanje, vendar ni več ovinek iz nastavitev konkretnega prostora.

## Ustvarjanje s sinhronizacijo

[Skupni obrazec](../lib/organizer/presentation/shared/create_space_dialog.dart)
ponudi sinhronizacijo za **obe** vrsti prostora. Ob prijavi ohrani ime, vrsto,
naslov in odločitev. Prijavljenemu uporabniku pokaže račun in gostitelja.
Ustvarjanje v oblaku ustvari eno strežniško destinacijo; ne ustvari še drugega
nepovezanega lokalnega prostora. Ostali člani dostop dobijo šele s povabilom.

Pred oddajo se v lokalno SQLite shrambo zapiše obnovljiv osnutek s podatki,
računom in nespremenljivima ID-jema prostora ter zahteve. Po neznanem izidu
ponovni zagon ali ponovno odprtje nadaljuje isti poskus. Podatkov oddanega
poskusa ni mogoče tiho spremeniti. Drug račun ga ne nadaljuje. Uporabnik lahko
medtem ustvari drug **lokalni** prostor; nerešeni oblačni osnutek se ohrani.
Potrjeni izbris računa odstrani samo njegov pripadajoči osnutek.
Predolge vnose in nepodprto ustvarjanje organizacije aplikacija zavrne še pred
zapisom takega poskusa. Obrazec ostane popravljiv; lokalna napaka se ne spremeni
v zaklenjen poskus z neznanim strežniškim izidom.

## Pogodbe in združljivost

Spremembe so opisane v [pogodbi povabil](server/email-invitation-api-contract.md)
in [pogodbi deljenja](server/space-sharing-api-contract.md). Novi zmožnosti
`usernameInvitations` in `invitationResend` se oglašujeta ločeno in zahtevata
podporo pogodbi 3. Starejši strežnik obdrži e-poštno pot; aplikacija ne poskuša
nevarnega obvoda na stara username povabila.

Ta prenova ne dodaja nove strežniške sheme. V trenutnem izvoru je že shema19
iz [predhodne nadgradnje preglednic in prilog](TABLES_AND_ATTACHMENTS.md),
ki še ni nameščena na gostovanjih. Pri prihodnji izdaji je treba upoštevati
celoten izvor, ne trditi, da gre zgolj za zamenjavo besedil ali samo teh PHP datotek.

## Preverjanje

Dokazi so v `build/qa/invitation-simplification/` in
`build/qa/invitation-simplification-20261016/`; gre za lokalne, ignorirane
artefakte, ne za produkcijske dnevnike.

- Celoten Flutter nabor: **1.582 PASS / 16 obstoječih preskokov**
  (`flutter-full-final.log`). Po zadnji ozki dopolnitvi preverjanja vnosov je
  celoten prizadeti nabor ustvarjanja, izbirnika, uvoda in povezave s shellom
  ponovno preverjen: **59 PASS / 1 obstoječ preskok**
  (`creation-final-regression.log`), vključno s tremi novimi robnimi primeri.
- `flutter analyze --no-pub`: **10 že obstoječih info** v `tools/release`,
  brez novih opozoril ali napak (`flutter-analyze-final.log`). Izvedena sta
  `flutter gen-l10n` in formatiranje spremenjenih Dart datotek.
- Končna `flutter build apk --debug --no-pub`: **PASS**
  (`android-debug-final.log`). Paket je samo lokalni debug artefakt, ni nameščen
  ali izdajni AAB. Orodje opozori na prihodnjo opustitev podpore trenutnim
  Gradle/AGP/Kotlin različicam; nepovezane nadgradnje teh odvisnosti niso izvedene.
- Ciljni prejemnikov nabor: **49 PASS**, dodatnih **19 obstoječih regresij PASS**.
  Zajemi registracije, prijave in pregleda dostopa uporabljajo dejanske pisave.
- Skupna povezava Utripa, deljenja, prvega zagona in pravil: **36 PASS**.
- Strežniško: **534 ciljnih kontrol PASS** — po 52 za novega prejemnika in
  atomsko ponovno pošiljanje, 47 z izključenim SMTP ter 79 e-poštnih regresij
  na vsaki od baz SQLite, MariaDB10.11 in MySQL8.4. Izolirani sintetični podatki.
- PHP lint: **94 datotek vtičnika in 2 testni datoteki PASS**.
- Spletna stran povabila: SL/EN pri320px in povečavi besedila2× brez vodoravnega
  prelivanja; jezik ohrani fragment povabila, povezava trgovine ne vsebuje žetona.
- Vizualno pregledani widget prikazi: deljenje320/390/1280, ustvarjanje390,
  prijava/registracija/pregled povabila390. Ciljni testi dodatno preverjajo
  ozke širine, večje besedilo, pravilnost cilja, preklic, izgubljene odgovore in račune.
- Povezave novega izvedbenega dokumenta in `git diff --check`: **PASS**.
  Ni sprememb `pubspec.yaml`, lock datotek ali platformnih native direktorijev.

Ločena širša strežniška regresija `space-sharing-integration.php` se ustavi
po66 uspešnih kontrolah zaradi obstoječe nepovezane napake validacije
`householdPerson.archived` v `NativeRecordPolicy.php`: zahtevano polje ni v
dovoljenem seznamu te vrste. Ta datoteka v tej prenovi ni spremenjena.
**Celotnega širšega strežniškega nabora zato ne označujemo kot uspešnega.**

## Meje in naslednja izdaja

- Ni samodejnega prenosa povabila skozi namestitev iz trgovine. Jasna navodila
  uporabnika vrnejo na prvotno e-pošto. Native App Links oziroma Universal
  Links in samodejno nadaljevanje po namestitvi niso dodani.
- Prijava ostane z uporabniškim imenom; e-poštna prijava, čarobne povezave in
  prijava Google/Apple niso del te izvedbe.
- Pošta ostane navadno besedilo. Oddaja v poštno vrsto ne pomeni potrjene
  dostave ali branja; novo podrobno dostavno stanje ni dodano.
- Fizičen prvi vstop na uporabnikovem telefonu, hladni zagon iz njegove
  poštne aplikacije, namestitev in vrnitev ter upravljalnik gesel niso ponovljeni.
  Lokalni testi ne dokazujejo manjše potrebe po pomoči; to zahteva uporabniški preizkus.
- Pred prihodnjo namestitvijo so potrebni običajna preverjena kopija/obnova,
  usklajena FamilyHub izdaja in ciljno preverjanje na telefonu. Nobenega živega
  gostovanja ali javnega paketa ta izvedba ne nadgradi sama.
- **Google Play zahteva novo izrecno uporabnikovo potrditev.** Interna izdaja
  ni dovoljena; Apple ostaja odložen. Obstoječi zamrznjeni AAB29 teh sprememb ne vsebuje.

## Uskladitev s pogovorom »Dodaj opombo za prikaz gesla«

16. oktobra je bil na uporabnikovo zahtevo pregledan celotni povezani pogovor
`01a13b25-b773-7dd1-bdc8-655d071ec905`, njegova dokumentacija in trenutni izvor.
Pregled ne pomeni naročila za namestitev. V tem koraku ni novih sprememb
aplikacijske ali strežniške kode, izdaje, migracije oziroma novih testnih računov.

Prvotni paket19 izboljšav, vključno z ogledom gesla, Vrtom, opomniki in
upravljanjem prostorov, je opisan v [izvedbenem dnevniku](UPGRADE_IMPLEMENTATION.md).
Strežniški del do FamilyHub0.14.1/sheme18 je po zadnjih potrjenih izdajnih
zapisih že nameščen na produkciji in test1. To ni ponovna sveža preverba
gostovanih datotek v tem pregledu. Poznejši popravki zaključevanja opravil,
projektnega menija, kontrasta in združevanja ponovno poslanih povabil so
odjemalčeve spremembe; ne potrebujejo lastne nove strežniške migracije.

**Preglednice in priloge iz tega pogovora je treba vključiti v isto naslednjo
strežniško izdajo kot prenovo povabil.** V trenutnem delovnem izvoru so že skupaj,
vendar namestitveni paket in postopek še nista pripravljena. Preverjeno:

1. `Schema/Mysql.php` in `Schema/Sqlite.php` zahtevata shemo19.
   `Schema/DocumentsSchema.php` doda pet tabel za preglednice, priloge,
   dele prenosa, ponovljive operacije in čiščenje. `Plugin.php` še vedno
   poroča0.14.1; pred izdajo potrebuje novo različico in usklajena javna navodila.
2. `tools/plugin_release/source_manifest.json` še nima petih novih datotek:
   `DOCUMENTS_API.md`, `Model/NativeAttachmentService.php`,
   `Model/NativeDocumentService.php`, `Model/NativeTableService.php` in
   `Schema/DocumentsSchema.php`. Samo bralni klic zbiralnika paketa je zato
   pravilno zavrnil izvor z `Unreviewed or missing source files`. ZIP ni nastal.
   Datoteke je treba pregledati in izrecno dodati, varovala ne izključiti.
3. Primerjava z lokalnim javnim FamilyHub repozitorijem pri59119dc/v0.14.1
   pokaže štiri nove in17 spremenjenih PHP datotek;73 PHP datotek je enakih.
   To je primerjava izvorov, ne popis trenutnega gostovanja. Javni repo ostane
   nespremenjen do priprave pregledane nove izdaje.
4. `server/scripts/upgrade-0.14.0` je vezan na stari izvor, prehod17→18 in
   različico0.14.0. Za prehod18→19 je treba pripraviti ločen preverjen postopek
   z aktualnimi identitetami in hashi. Starih pinov oziroma preverjanj se ne rahlja.
5. Kopija mora zajeti vse tabele, celoten zasebni DATA_DIR, konfiguracijo,
   ključe, izvor in cron. Obnova mora biti dejansko preverjena v izolaciji.
   Preveriti je treba PHP ZipArchive za pisarniške priloge, zasebne pravice
   shrambe in obstoječi `cli/reminders.php`, ki zdaj čisti tudi priloge.
6. Pred namestitvijo je treba odpraviti zgoraj opisano napako
   `householdPerson.archived` in ponoviti prizadete strežniške regresije.
   `NativeRecordPolicy.php` je bajtno enak lokalnemu javnemu0.14.1 izvoru;
   napaka ni nastala zaradi novega čarovnika ali preglednic. Skupno izdajo je
   treba preveriti tudi prek kombinacije deljenja/odvzema/izbrisa in dokumentov.
7. Za aplikacijsko izdajo ostanejo potrebni nov zamrznjen paket, preverjanje
   dejanskega prvega vstopa na telefonu ter uskladitev Files and docs v Play
   Data safety in pregled politike zasebnosti/opisov zaradi dokumentnih prilog.
   V pregledanem pogovoru omenjene širše ideje za preglednice niso avtomatično
   dodatne obljubljene funkcije; dejanski izvedeni obseg vodi
   [zapis preglednic in prilog](TABLES_AND_ATTACHMENTS.md).

Priporočen vrstni red je: odpraviti ugotovljeni strežniški zastoj → pripraviti
in preveriti združeni izdajni/migracijski paket → sveža kopija in prava obnova
→ nadgradnja preglednega test1 → ciljni preizkus povabil in dokumentov →
nadgradnja produkcije → nova aplikacijska izdaja po ločeni izrecni potrditvi.
