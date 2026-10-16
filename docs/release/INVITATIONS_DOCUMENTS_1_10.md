# Android1.10.0(30) — povabila, preglednice in dokumenti

16. oktober2026. Uporabnik je izrecno naročil skupno strežniško nadgradnjo,
commite/push in **novo javno Android izdajo**. Prejšnja omejitev oddaje je s tem
naročilom za to izdajo presežena. Interni kanal ostane neaktiven, Apple je odložen.
Ta dokument v tem trenutku potrjuje **lokalno podpisano kandidatko**, ne oddaje
ali Googlove odobritve. Živo namestitev in portal potrdi glavni agent ločeno.

## Obseg in izvor

Vključene so vse spremembe po AAB29: zaključevanje opravil, enotni projektni meni,
kontrast ikon, združevanje ponovno poslanih povabil, organizacijske preglednice
in priloge ter novi vodeni tokovi povabil/deljenja/ustvarjanja prostorov. Ne gre
samo za nov naslov ali spremembo besedil. Dejanski obseg in omejitve opisujeta
[izvedba povabil](../INVITATION_AND_SHARING_IMPLEMENTATION.md) ter
[preglednice in priloge](../TABLES_AND_ATTACHMENTS.md).

Zamrznjeni izvor je ločena zasebna kopija trenutnega delovnega drevesa v
`build/qa/invitations-documents-release-20261016/source`. Ker spremembe ob pripravi
še niso vse v commitu, so evidentirani gitHEAD, javni runtime diff, **vsi novi
neversionirani izvorni vhodi** in njihove SHA256 vrednosti. Sam HEAD ni dokaz
vsebine kandidatke. Nepovezani varnostni dokument ni vključen v runtime ali paket.

- Različica: **1.10.0+30**, `si.triparna.jivie`.
- **442** runtime/native vhodov, od tega **329** skupnih `lib/assets/pubspec/l10n`.
- Agregat SHA256:
  `3167fd2abe1f297330c35cb5c9401edd26021cfe58b04ca2f497d862f3e4cdde`.
- Proti zamrznjenemu AAB29: **52 spremenjenih in21 novih vhodov**,0 odstranjenih.
- Android/iOS/macOS native vhodi, trije locks, tri konfiguracije in SDK so isti.
  Konfiguracijske vrednosti niso izpisane ali dodane v javni manifest.
- Predhodni funkcionalni dokazi: **1582 Flutter PASS/16 preskokov**, nato
  **59 prizadetih PASS/1 preskok**. Celoten nabor ni ponovno izveden samo za izdajo.

Glavni lokalni dokazi: `source-input-manifest.json`, `source-diff-from-29.json`,
`public-runtime-head.diff` in dnevniki v navedeni QA mapi.

## Podpisani Android paket

Natanko ena nova podpisana gradnja je nastala iz izoliranega izvora z obstoječim
namenskim podpisom in nespremenjeno javno konfiguracijo Firebase:

`build/releases/Jivie-1.10.0+30-android-firebase.aab`

**81.261.911 bajtov**, SHA256
`9f0aab744eee5895b5450dd1d128c5eb8dae36ce1f0248bbda2b8c7a9112abb4`.
AAB29 je ohranjen. Ni nove iOS/macOS gradnje ali nameščene aplikacije.

Preverjeno: bundletool validate, ZIP CRC, isti certifikat kot29, pravilni package/
versionName/versionCode, minSDK24/targetSDK36, non-debuggable, obstoječi zasebni
ShareFileProvider, istih8 dovoljenj, isti native Firebase project/app/sender
identifikatorji in Dart AOT projekt v vseh treh ABI. Vsi trije Flutter engine
bajti so enaki29. Osem64-bitnih knjižnic ima potrjeno16KiB poravnavo; bundle
ima `PAGE_ALIGNMENT_16K`. Ni podpisnih datotek, zasebnih ključev ali service-account
poverilnic v arhivu.

V izoliranem izvoru je uspešnih **120 ciljnih Flutter testov** za release mejo,
Firebase, čarovnik povabila, ustvarjanje prostora, preglednice, priloge in obnovo
osnutkov preglednic. **23 release in7 Firebase Python kontrol PASS**; izvorni
release checker PASS. Gradnja ima ista opozorila o prihodnji opustitvi trenutnih
Gradle/AGP/Kotlin različic; nepovezane nadgradnje SDK/odvisnosti niso izvedene.

Dokazi: `android/android-release-artifact-evidence.json`, `android/build.log`,
`android/verification.log`, `isolated-feature-tests.log`, `release-tests.log`,
`firebase-tests.log`, `source-check.log` in `isolated-runtime-analysis.log` (brez ugotovitev).

## Trgovinske slike in besedila

Iz **trenutnih dejanskih widgetov** je na novo izrisanih20Android PNG-jev:
10prizorov ×SL/EN, vsak720×1280. Sintetični pomnilniški podatki, dejanske pisave,
običajne sence in navigacija; brez uporabniških računov, nameščene baze ali
strežniških sprememb. Angleški prizori imajo lastna angleška besedila; niso
preimenovane slovenske kopije. Pikseli niso obrezani, retuširani ali sestavljeni.

Javna galerija ima **8SL+8EN** slik: Utrip, opravila, Idejnik, **preglednica**,
projekt, nakupi, Vrt in finance. Preglednica nadomesti stari koledarski posnetek.
Sveža koledar in povabilo ostaneta lokalni alternativi. Vseh8 starih prizorov je
ponovno izrisanih za primerjavo; oba Idejnikova izrisa sta bajtno enaka prejšnjima,
ker se vidni prizor ni spremenil; stari posnetki15.oktobra ostanejo ohranjeni.

[Manifest slik in vrstni red](INVITATIONS_DOCUMENTS_1_10_SCREENSHOTS.json) navaja
izvor, mere, hashe, primerjavo s prejšnjimi datotekami in pot do enolično imenovanih
nalagalnih kopij. Priporočena galerija je v
`build/qa/invitations-documents-store-20261016/play-gallery/{sl,en}`.
ZIP: `build/releases/Jivie-1.10.0+30-android-store-screenshots.zip`, SHA256
`38a5694e13f036094fc6bb260cafd264aa2d1a7309b8668a3d986a48a1d7bbf6`.

Zajemne regresije:6 obstoječih scenarijev in2nova preglednica/povabilo PASS.
Preverjeni so20PNGformatov/mer/neprosojnosti/različnosti, istost runtime z AAB,
16bajtno enakih nalagalnih kopij in17ZIP CRC vnosov. Vizualni pregled zajema vse
izbrane SL/EN slike. Preglednica kaže resnične izračunane vsote; prazna izbrana
celica ne spreminja podatkov ali pridobi zaklepa.

[Opombe za izdajo](INVITATIONS_DOCUMENTS_1_10_RELEASE_NOTES.json) so pod500znaki
na jezik. `STORE_LISTINGS.json` je lokalni predlog daljših SL/ENopisov
(3757/3821znakov), ki doda preglednice in dokumentne priloge ter ohrani obstoječe
pomembne omejitve. Imena, kratka opisa, ikona in feature graphic ostanejo isti.
To še ni dokaz shranitve/objave v Console.

## Predlagana Google Data safety dopolnitev

Nova kategorija: **Files and docs → Files and docs**. Predlog za pregledane poti:
**Collected Yes / Shared No / Optional Yes / Ephemeral No**; namena
**App functionality** in **Fraud prevention, security and compliance**.

Datoteke se na izbrani strežnik prenesejo šele po uporabnikovi izbiri. Za osnovno
lokalno uporabo niso potrebne. Datoteke, imena, MIME, velikost, hash, avtorstvo in
cilj niso zgolj začasno obdelani. Namen AF zajema zasebno shrambo, prenose in
upravičen dostop; SEC zajema izrecno prijavo z metapodatki in kontekstom.
`Shared No` temelji na istem preverjenem pravilu za pričakovano uporabnikovo
izrecno deljenje iz prejšnje deklaracije; **ne** na tem, da je strežnik self-hosted.
Prenos na uporabnikov strežnik je še vedno zbiranje po Googlovi opredelitvi.

Obstoječi **Photos** ostane zbran/izbiren/nezačasen, AF+SEC; poleg normaliziranih
fotografij Idejnika zdaj zajema tudi izvirneJPEG/PNGpriloge. Normalizacije Idejnika
ne smemo pripisati dokumentnim prilogam. Datotečni izvirniki in njihovi vgrajeni
metapodatki se ohranijo. Če jih izvorna datoteka vsebuje, lahko to vključuje
lokacijske podatke; odsotnostGPSdovoljenja sama ne pomeni, da teh metapodatkov
ni v izbranih bajtih. To naj glavni agent posebej upošteva ob pregledu aktualnih
Console vprašanj o lokaciji in objavljenih trditev. Priloge niso end-to-end
šifrirane; prenos uporabljaHTTPS, upravičenci in strežniški upravljavec lahko
berejo izvirnike.

Za samostojno kategorijoLocation je bil nato preverjen tudi neposreden odgovor
v uradnemFAQ »If one data type is collected as part of another, should I declare
both?«. Google zahteva obe kategoriji, kadar drugo vrsto namensko pridobivaš;
primer je uporaba fotografij za določanje osebnih značilnosti. Tudi odgovor oIP
veže lokacijsko kategorijo na dejansko določanje lokacije. **Naša uporaba tega
pravila:** izvirni bajti priponk se ohranijo, vendar Jivie/FamilyHub ne bere,
ne izlušči in ne uporabljaEXIFGPS oziroma lokacije uporabnika/naprave. Zato
zgolj morebitna lokacija znotraj uporabnikove izbrane datoteke ne dodaja samostojne
Location kategorije tej deklaraciji. Photos inFiles/docs ostaneta prijavljeni,
zasebnost pa izrecno razloži ohranjene metapodatke. To je omejena presoja konkretne
kode po uradnemFAQ, ne posebna Googlova odobritev ali splošna izjema zaGPSpodatke.

Preglednice/formule sodijo v obstoječo uporabniško vsebino; vsebina je lahko tudi
finančna glede na namensko uporabo. Ne uvajamo splošne izjeme za poljubne dokumente
ali nove oglasne/analitične namene. Deklaracija mora zajeti vse trenutno omogočene
različice in poti. [Uradna Googlova navodila](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
so bila preverjena16.oktobra2026; določajo prenos z naprave, datoteke skupaj z
metapodatki, izbirnost ter izključitev nekaterih uporabniško začetih deljenj.

Dokazi kode:

- `NativeAttachmentService.moderationEvidence`170–179: ime in metapodatki
  konkretne priloge ter ime/revizija nadrejenega cilja; ne zadrži datotečnih bajtov.
- `NativeTableService.moderationEvidence`83–90: do100 surovih vrednosti celic,
  po200UTF-8bajtov, oznaka krajšanja, število celic, metapodatki prilog ter hash.
- `NativeModerationService`: bajte fotografij posebej zadrži samo pri prijavi
  Idejnika. Iz tega ni dovoljeno sklepati, da se izvirnik priponke nikoli ne shrani;
  običajna uporabniška priloga seveda ostane v zasebni datotečni shrambi.

## Predlagana objavljena zasebnost — odsek SL

**Preglednice in dokumentne priloge.** V povezani organizaciji lahko urejaš
preglednice. Na izbrani strežnik se shranijo naslov, celice, formule, revizije in
podatki o začasnem zaklepu urejanja. Dokumente in slike izbereš s sistemskim
izbirnikom ter jih pripneš prostoru, opravilu ali preglednici; dostop sledi
pravicam tega cilja. Priloge se prenesejo kot izvirne datoteke, skupaj z morebitnimi
vgrajenimi metapodatki. V nasprotju s fotografijami Idejnika se ne normalizirajo
in se jim vgrajeni metapodatki ne odstranjujejo. Izvirnik lahko berejo upravičeni
člani in upravljavec izbranega strežnika. Prenesene kopije so v lokalnem
predpomnilniku za ogled brez povezave. Znani odvzem dostopa onemogoči nadaljnji
ogled v aplikaciji; ne odpokliče že shranjenih izvozov. Shranitev izvirne kopije
na drugo mesto sprožiš izrecno prek sistemskega izbirnika. Prenos uporabljaHTTPS,
vsebina pa ni šifrirana od pošiljatelja do prejemnika.

**Prijave in kopije.** Pred prijavo preglednice ali priloge vidiš prejemnika in
konkretni posnetek. Pri preglednici vključuje omejeni izbor celic in metapodatke
prilog; pri prilogi njene metapodatke in kontekst, brez nove zadržane kopije
celotne datoteke v dokazih prijave. Prenosna šifrirana kopija lahko vsebuje lastne
lokalne osnutke preglednic. Ne vsebuje sej, žetonov zaklepa ali celotnih strežniških
izvirnikov dokumentnih prilog. Celotna strežniška kopija potrebuje bazo in
zasebni imenik podatkov; kopije izvozov na drugih mestih upravljaš sam.

## Proposed published privacy section — EN

**Spreadsheets and document attachments.** In a connected organization, you can
edit spreadsheets. The selected server stores their titles, cells, formulas,
revisions and temporary editing-lock information. Select documents and images
with the system file picker and attach them to a space, task or sheet; access
follows that target’s permissions. Attachments are transferred as original files,
including any embedded metadata. Unlike Ideas photos, they are not normalized
and their embedded metadata is not removed. Authorized members and the selected
server operator can read the originals. Downloaded copies are cached locally
for offline viewing. A known access revocation prevents further viewing in the
app; it cannot recall exports already saved elsewhere. Saving an original copy
to another location requires your explicit system-picker action. Transfers use
HTTPS; the content is not end-to-end encrypted.

**Reports and backups.** Before reporting a sheet or attachment, you review the
recipient and exact evidence. Sheet evidence includes a bounded selection of
cells and attachment metadata; attachment evidence includes its metadata and
parent context, without retaining a new complete-file copy in the report.
An encrypted portable backup may contain your local sheet drafts. It excludes
sessions, editing-lock tokens and complete server originals of document
attachments. A complete server backup requires the database and private data
directory; you control copies exported to other locations.

Objavljeno zasebnost je treba hkrati uskladiti glede trenutnega privzetega zvoka:
manjkajoča nastavitev je vključena, vsaka že shranjena izbira pa ostane ohranjena.
To je že izveden popravek29, ne nova migracija30. Spletni generator/objavo in
končno Console shranitev izvaja glavni agent; ta dokument ju sam ne potrjuje.

## Pred portalom

Glavni agent potrdi dejansko nadgradnjo produkcije in preglednega test1 na nov
FamilyHub/shemo19 po sveži kopiji in pravi izolirani obnovi; starega pomočnika
sheme18 ne prilagaja z rahljanjem varoval. Potrdi nov pregledni dostop, objavljeno
zasebnost in Console deklaracije za isto AAB. Šele nato naloži ta hash v javni
kanal z obstoječoSlovenijo in100%uvajanjem. Interni kanal inApple ostaneta odložena.
Fizični novi Android tokovi/sistemski izbirniki niso dokazani z widget testi.

## Dodatna presoja opozorila Play o RELRO/16KiB

Svež pregled portala za že javni29 je prikazal opozorilo za
`libdatastore_shared_counter.so` v `arm64-v8a` in `x86_64`. To ni nova regresija30:
obe knjižnici sta v29 in30 bajtno enaki, vključeni prek
`shared_preferences_android2.4.20`/AndroidXDataStore1.2.0. Opomba knjižnice navaja
stari upstreamNDKr20; različica lokalnegaNDK sama ne prevede takšnega prebuilt-a.

Prejšnji izdajni preverjevalnik je preverjalLOAD/ZIPporavnavo, ne ločene geometrije
RELRO. Zato je bila zdaj dodana **ločena bralna presoja dejanskih ELFglav in
sekcij**, brez spreminjanja ali ponovne gradnje paketa:

- LOAD začetki so0,0x4000in0x8000, vsi s poravnavo0x4000.
- GNU_RELRO začne na0xc000, imaMemSiz0x1000 in konča na0xd000. Samo test
  `(VirtAddr+MemSiz)%0x4000` zato vrne0x1000 in pojasni opozorilo.
- ZadnjiRWLOAD se konča že na0xc250. Edina običajna spremenljiva `.data` je
  **pred**RELRO, pri0x8000..0x8008. ZaRELRO ni nobene naknadne zapisljive
  `.data`/`.bss`, ki bi jo zaščita do0x10000 pomotoma naredila samo za branje.

[Uradna navodila Android](https://developer.android.com/guide/practices/page-sizes#relro-flag)
pojasnjujejo, da je problematičen napačen konecRELRO, kadar mu v istemLOADsledi
zapisljiva vsebina. Preverjen je tudi
[dejanski AOSPAndroid17linker](https://android.googlesource.com/platform/bionic/+/refs/tags/android-17.0.0_r1/linker/linker_phdr_16kib_compat.cpp):
`phdr_table_get_relro_min_align` preverjaRELROkot predponoLOADz nadaljnjo
zapisljivo vsebino. Pri teh dveh knjižnicah seRELROzačetek ne ujema z nobenim
LOADzačetkom, zato ta preverba ne zmanjša dovoljene poravnave; tudi naslednja
preverba prekrivanjaLOADstrani uspe.

**Sklep:** surovo opozorilo ne potrjuje opisanega sesutja pri konkretni postavitvi
teh knjižnic in samo po sebi ni razlog za novo gradnjo30 ali hitro menjavoAPIjev.
Ne trdimo, da je Google opozorilo odstranil ali da je nov paket fizično preizkušen
na16KiBnapravi. Povezane naprave ni bilo; obstoječaAVDja nista dokaz16384bajtne
strani. Če bi portal pokazal dejansko blokirno napako, je ta neodvisna od lokalne
presoje in je ne obidemo.

Dodatni dokazi so v `android/relro-29-30-assessment.json`, izločenih pregledanih
knjižnicah `android/relro-libs/` ter lokalno shranjenem izvoru
`android/aosp-android17-linker-compat.cpp`. IzvirnaAAB29in30ter njuni hashi so isti.
