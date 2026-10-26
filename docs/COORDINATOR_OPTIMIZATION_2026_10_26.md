# Postopna optimizacija koordinatorja — 26. oktober 2026

Izhodišče: `66ee218`; ugotovitve P1–P8 iz
[modulnega pregleda](MODULE_SYNC_AUDIT_2026_10_26.md).
Uporabnik naroča ločene lokalne/headless kontrole ter commit in push vsakega
smiselnega sklopa. Brez posegov v telefone, obstoječe QA podatke ali produkcijo.
Meritve spodaj so števci konkretnih testnih poti, ne mobilni časovni benchmark
ali obljuba števila fizičnih E2EE HTTP zahtevkov. Starih uspešnih scenarijev
ne ponavljamo. Največ trije poskusi neuspešnega scenarija.

## Trenutno stanje po nadaljevanju P2, P6 in P8

| Točka | Stanje |
|---|---|
| P1 dokumentni signali | Izvedeno in ciljno preverjeno |
| P2 večkosovni download | Izvedena omejena ponovna uporaba preverjene projekcije med kosi iste datoteke; mobilna/HTTP meritev še ni izvedena |
| P3 znani zapisi | Izvedeno in ciljno preverjeno; finance/neznani cilji ohranijo namensko pot |
| P4 finančne izbire | Sočasne združljive priprave združene; reuse po zaključku še ni uveden |
| P5 inbox/konfiguracija | Oba sklopa izvedena in ciljno preverjena |
| P6 članstvo/povabila | Izvedene session display generacije iz koordinatorja, ciljni member refresh in ohranitev dogodkov med branjem |
| P7 email status | Izvedeno in ciljno preverjeno |
| P8 lokalni SQL/CPU | Izmerjeno; po lokalnem shranjevanju se obnovi samo spremenjeni prostor. Širša pomožna branja in lokalni signali so zapisani za pozneje |

## P1 — ciljni signali dokumentov in lastno branje

Izvedeno: lokalni signal preverjene projekcije nosi vrsto in canonical ID;
priloga še stari/novi cilj. En SQL commit objavi en paket. Seznam preglednic
posluša preglednice, podrobnost svoj ID, priloge svoj cilj in njegov izbris.
Neznana stara tombstone/legacy invalidacija ostane konservativno široka.
Signal nikoli ne prečka računa/prostora ali neuspešnega SQL commita.

Vsako dokumentno branje ima kontekstni query-origin, prenesen po async coni.
Samo lastna projekcija istega branja ne sproži ponovnega branja tega pogleda;
drugi pogledi in neodvisni koordinatorjevi commiti ostanejo obveščeni. To ni
cache dovoljenj in ne preskoči svežih dokazov, pravic ali samega branja.
Lease, osnutki, šifriranje, signed requesti in protokol so nespremenjeni.
Lastne mutacije še vedno objavijo signal; ne trdimo odprave vsakega možnega
ponovnega branja po uploadu ali navigaciji nazaj.

Nove kontrole, vseh **5 PASS v prvem poskusu**:
- 3 repository/gateway kontrole: query-origin razlikovanje; res oddaljen commit
  med branjem; target filter in device_revoked ob ohranjenem lokalnem osnutku.
- 1 pravi memory SQLite preizkus: nested commit, paketno dedupliciranje,
  rollback, partition/scope izolacija in neznan tombstone.
- 1 headless widget preizkus dejanske list→detail poti: list=1, detail=1;
  dve nepovezani spremembi ne dodata branj; matching remote revision doda
  natanko eno branje in je vidna. Lastni read-signal ne doda trailing branja.

Repository transport v teh kontrolah je sintetičen; to ni nov kriptografski
HTTP ali native dokaz. Izvorni pregled emitterja ohranja hash-change pogoj in
objavo šele po potrjenem SQL commitu. Ozka analiza: 0 napak/0 opozoril;
12 obstoječih slogovnih info (nov curly-braces info odpravljen). Diff check PASS.
Dokazi: `build/qa/coordinator-optimization-20261026/p1-*.log` (ignorirano).
Prvi skupni testni filter je izbral samo tri `coordinator` teste; SQL test
je zato zagnan posebej, ne ponovljen. Vseh pet kontrol ima samo en tek.

## Zgodovinsko stanje po prvem sklopu

Takrat P2–P7 še odprto; P8 najprej zahteva meritev lokalnega SQL/CPU, ne slepega
spreminjanja. Status naslednjih sklopov dodajamo spodaj pred njihovim commitom.

## P5a — drugo branje inboxa samo po oddaljenem ukazu

Izvedeno: `_syncCommands` vrne, ali je dejansko poskusil oddaljen ukaz.
Prazna ali lokalno zavrnjena vrsta ne povzroči drugega `_syncInbox`. Po ACK,
`notification_missing` in konfliktu se drugo branje ohrani. Nadaljevanje
shranjenih ukazov, nespremenjen request, preklici in napake ostanejo isti.

4 nove headless repository kontrole PASS: prazna vrsta ima 1 inbox.sync/0
inbox.read; ACK, poteklo obvestilo in konflikt imajo 2 inbox.sync/1 inbox.read.
ACK se uporabi; missing odstrani samo obvestilo; konflikt ostane blocked;
pravica do prostora je ohranjena. Prvi tek je ustavila sintetična fixture
brez eksplicitnega legacy routerja (crypto_reconciliation_required); dodan
fail-closed router, brez izmišljenih ključev. Drugi tek 3 PASS, ACK fixture
imela star datum 11.10. in je pravilno sprožila retencijo. Tretji tek SAMO ACK
s trenutnim datumom PASS. Ni četrtega teka ali ponovitve treh PASS.
Ozka analiza 0 napak/0 opozoril, 9 obstoječih info; nov info v testu popravljen.
Dokazi `p5a-*`. Transport je sintetičen in SQLite pravi; ne HTTP/native test.
Konfiguracijski fanout (P5b) še sledi.

## P5b — oddelen namig za konfiguracijo obvestil

Strežnik v isti metadata snapshot doda `notificationHintsVersion: 1` in
`notificationConfigurationChanged`. Obstoječi accountDomains/inbox ostane
združljiv s starimi aplikacijami. Cursor ima dodatni podpisani digest že
obstoječega configuration_revision; shema in poslovni podatki se ne spreminjajo.
Stari cursor brez polja zahteva eno konfiguracijsko osvežitev in se nato umiri.
Nova aplikacija ob običajnem inbox dogodku preskoči preferences/reminders
fanout. Ob resetu, spremenjenem dostopu ali poslanem ukazu ga ohrani. Stari
ali neznani strežniški hint uporablja prejšnjo konservativno pot.

**15 novih kontrol PASS:** 8 strežniških + 7 Dart repository/parser.
Strežniški prvi tek: prvih 5 kontrol PASS; test podpisa starega cursorja FAIL,
ker fixture ni uporabila obstoječe HMAC domenske izpeljave ključa. Ta sklop
razdeljen v split/compat datoteki; drugi tek samo 3 še odprte compat kontrole
PASS (stari cursor, settle, izolacija računa). Ni ponovitve prvih 5 PASS.
To je dejanski NativeAccountChanges nad disposable memory SQLite v Dockerju
brez mreže; ni nov E2EE podpisni ali HTTP test.

Odjemalec 7 PASS v prvem teku: navadni inbox 0 preference + 0 reminder branj
za 2 prostora; config/access/legacy/unknown/command vsak ohrani 2+2. Preverjen
je tudi strog tip eksplicitnega hint polja. Uporabljen pravi repository/SQL
in sintetičen legacy transport; ne trdimo prihranka fizičnih crypto HTTP.
Analiza 0 napak/0 opozoril, 9 obstoječih info. `p5b-*` dokazi, brez deploya.

## P7 — en status po potrditvi e-pošte

Repository vrne AccountStatus iz že obstoječega account.status po uspešni
potrditvi; controller ga prenese, UI ga uporabi brez drugega status klica.
Potrditev je vezana na začetno sejo/epoch; status in UI ohranita identity guard.

5 novih kontrol PASS: repository uspeh/call count + napaka confirm + napaka
status (3 PASS1); UI uporaba vrnjenega statusa + ignoriranje poznega rezultata
po zamenjavi računa (2 PASS2 po manjkajočem importu modelov v novi fixture).
Prve tri niso ponovljene. UI ima samo začetno status branje; vrnjena potrditev
ne doda drugega. Analiza 0 napak/0 opozoril, 2 stara info; nov testni info
popravljen. Dokazi `p7-*`. Obstoječi UI fake override prilagojen vrnjenemu tipu;
stari suite ni ponovno izvajan. Ni pošiljanja prave e-pošte ali sprememb računov.

## P4a — sočasna priprava finančnih izbir

Priprave se združijo samo, če so hkrati aktivne in imajo isti epoch, prostor,
refreshPolicy način, finance_access_generation in authorityReuse generation.
Uspeh ali napaka se takoj odstrani iz mape. Ni TTL ali ponovne uporabe
zaključenega rezultata; zaporedno odprtje ostane sveže. Polna priprava in
selector za odprt osnutek ostaneta ločena. Obstoječi SQL/generation guardi
in pravice se še vedno izvajajo v prvotni pripravi.

5 novih repository kontrol PASS2 po manjkajočem model importu v novi fixture:
združljivi sočasni pripravi 1 policy/1 selector, poznejše odprtje novo branje;
editor proti full; spremenjena authority generation; spremenjena finančna
generation z zavrnitvijo starega odgovora; skupna napaka se odstrani in nov
poskus uspe. Pravi memory SQLite/sintetičen legacy transport, ne E2EE HTTP.
Analiza 0 napak/0 opozoril; 2 novi slogovni info v testu popravljeni.
Dokazi `p4-*`. Širša ponovna uporaba po končanem branju zahteva preverjen
snapshot; tega ta sklop namenoma ne uvaja.

## P3 — znan nefinančni zapis prepusti osvežitev koordinatorju

Odpiranje obstoječega neizbrisanega nefinančnega zapisa s pravilnim tipom in
account/scope bindingom na strežniku z accountChangeVersions=1 ne izvaja
ločenega negotiate→scopes.list preflighta. Znan predogled opravila prav tako
uporabi skupni syncNow (namig→izbrane spremembe), brez svoje vzporedne poti
scopes.list→scope pull. Obstoječe sočasno združevanje task odpiranj ostane.
Prvi prikaz opravila ostaja lokalni. Normalni koordinator lahko dostavi že
shranjeno čakajoče delo; ne spreminja odprtega neshranjenega osnutka.

Neznani/izbrisani zapisi, inbox obvestila, membership/invitation cilji,
finance in strežnik brez podpore ohranijo namensko pot. Po koncu osvežitve
se še enkrat preveri lokalna dostopnost prostora; odvzem med čakanjem ne vrne
»available«. Brez novega TTL, permission cache ali novega periodičnega dela.

6 novih repository kontrol PASS1: task in shoppingList brez sprememb imata
samo account.changes; oddaljena sprememba potegne samo ustrezen prostor in
pokaže novo vsebino; potrjen odvzem vrne permissionDenied; network ohrani
lokalni task in vrne offline; neznani cilj obdrži negotiate/scopes.list in
requiresConnection. Sintetični legacy transport s pravo SQLite/koordinatorjem,
ne E2EE HTTP/native meritev. Analiza 0 napak/0 opozoril; 2 obstoječa info,
3 novi slogovni info odpravljeni. Dokazi `p3-*`.

## Zaključni pregled in Git kontrolne točke

| Sklop | Commit, push in remote HEAD potrjen |
|---|---|
| P1 | `a82b01b` |
| P5a | `ab3ab03` |
| P5b | `6eaa8b9` |
| P7 | `7d8a18d` |
| P4a | `9abd131` |
| P3 | `d6ba7ba` |

Skupaj **40 različnih novih ciljnih kontrol**: 32 Dart repository/SQL/widget
in 8 PHP assertions. Končni uspehi imajo zgoraj zapisane fixture napake in
poskuse; niso skriti ali šteti kot dodatni uspehi. Uspešnih kontrol nismo
ponavljali. Zaključna analiza vseh spremenjenih Dart datotek: exit0,
0 napak/0 opozoril, 25 obstoječih slogovnih info. `git diff --check` PASS.
To ni celotna regresija, nov HTTP E2EE scenarij, Mac GUI ali mobilni benchmark.
Ni nove gradnje/namestitve, deploya ali sprememb obstoječih testnih podatkov.
Edini strežniški tek je disposable Docker brez mreže s svežo memory SQLite.

P2/P6 zahtevata naslednji ločen korak: trenutni cache decrypted blobov že
preprečuje ponovno nalaganje cele datoteke, preostali pull/authority strošek
še potrebuje meritev. Pri članstvu/povabilih prikaz accepted statusa ne sme
ostati pripet na zastarel članstveni snapshot. Za ti poti ni uveden splošen
TTL ali preskok svežega preverjanja. P4a prav tako ne trdi odprave zaporednih
mount→editor priprav. Izvedeni sklopi se lahko neodvisno povrnejo.

## Nadaljevanje P2 — ena preverjena vsebinska priprava med kosi datoteke

Priloge in slike idej imajo eksplicitni lokalni download context, vezan na
sejo, operacijo in vse identitetne parametre (razen offset/limit). Zaključi
se tudi ob napaki. Obstoječi preverjeni read lease poteče po prvotnih 5 s;
sprememba seje, pravic, lokalne projekcije ali nepopoln/neomejen snapshot
onemogoči reuse. Blob descriptor, current/source head ter hash/velikost/cilj
vsakega kosa se še vedno preverjajo. Prenos ne spremeni podpisov ali formata.

Celoten decrypted blob je bil že prej lokalno predpomnjen po descriptor hash;
prejšnja koda torej ni nujno prenašala cele datoteke za vsak kos. Odstranjen
je ponovni attested content pull znotraj še veljavnega istega prenosa.
Generalizirana obstoječa finance-read implementacija ohrani finance alias in
privzeto domeno; prenosa financ in vsebine imata ločena konteksta.

**5 novih kontrol PASS:** 2 pravi memory SQLite/equality testi (content ne
uporabi finance completeness, 8 nespremenjenih zaporednih odjemalcev = 1
pull callback, spremenjena projekcija/lease/close prekine reuse); 3 repository
chunk-loop kontrole s sintetičnim transportom (celotni bajti, pokvarjena
vsebina, odjava med drugim kosom; vedno en context z zaključkom). Prvi tek
je imel compile napako v fixture `logout` namesto `signOut`; SQL kontroli sta
kljub skupni compiler napaki dokončali PASS. Drugi tek samo 3 chunk kontrole
PASS. Stari testi niso ponovljeni. Analiza: 0 errors/0 warnings, 12 starih info;
nov slogovni info v fixture popravljen. To ni meritev fizičnih HTTP ali test
novega E2EE protokola; dejanski prihranek je omejen z lease in velikostjo
projekcije. Dokazi `build/qa/coordinator-continuation-20261026/p2-*`.

## Nadaljevanje P6 — prikaz članstva in povabil prek sprememb koordinatorja

Account changes zdaj poganja session-only display generacije: account access/
metadata/reset, access prizadetega drevesa prostorov in invitations. Content,
finance in navaden inbox ne spreminjajo generacije prikaza. Isti vrnjeni cursor
ne povzroča vedno novih UI reloadov. Generacije niso pravice ali dokaz; vsa
branja in operacije potrditve/sprejema/ključi ostanejo preverjeni po stari poti.
Po odjavi in ob starejšem strežniku je stanje neznano in velja prejšnji fallback.

Odprta seznama članov in povabil ob ponovnem foregroundu novega protokola
počakata na koordinator, namesto samostojnega HTTP osveževanja. Lokalni ukazi
in izrecen retry še osvežijo. Dogodek med branjem/busy stanjem se ohrani za
naslednje branje. Mount ostane svež; ne uvajamo trajnega predpomnilnika
prejemnikov. Tudi obvestilo o prejetih povabilih posluša invitation generacijo.

Koordinator pri content/finance spremembi ne bere članov. Pri scope access
bere samo prizadeto odvisnostno drevo; account-wide sprememba ostane široka.
Ob potrjenem izboru access dela se stari 60s cache imenika invalidira, da ne
pokaže zastarih članov. Imena so še vedno display-only. Ni dodatnega pollerja.

**6 novih kontrol PASS:** 4 repository/SQLite kontrole in 2 widget kontroli.
Content hint: 0 member reads; invitation hint: nova generacija in 0 member
reads; access znotraj starega cache: sveže branje; ožja kontrola dveh neodvisnih
prostorov: 1 member read, ne 2. UI oba seznama: 1 začetno branje, resume in
nespremenjen sync 0 dodatnih, tuji prostor 0, sprememba povabila 1, nova
sprememba med branjem 1 naknadno branje; zamenjava računa ne naloži starih podatkov.

Zgodovina napak: repository access test prva dva teka nista imela v2 member
fixture (drugi se je po neuspelem pripravljalnem skriptu pomotoma izvedel še
na nespremenjeni fixture); tretji tek z v2 praznimi zapisi PASS. Drugih dveh
že uspešnih kontrol nismo ponovili. Ločen novi ciljni selection test PASS1.
UI members PASS1; pending FAIL1 je našel resnični `setState` callback, ki je
vračal Future. Popravljene istovrstne assignment puščice v pending strani;
ponovljen samo pending PASS2. Analiza 0 errors/0 warnings/10 starih info.
Dokazi `build/qa/coordinator-continuation-20261026/p6-*`. Sintetični transport
in pravi memory SQLite/widget, ne mobilni ali fizični HTTP preizkus.

## Nadaljevanje P8 — izmerjena lokalna osvežitev po shranjevanju

Nova omejena headless meritev nad 8 sintetičnimi praznimi prostori in memory
SQLite, brez dodatnih transportnih klicev med merjenimi dejanji:

| Operacija | SQL branja | Branja zapisov prostorov | Enkraten čas |
|---|---:|---:|---:|
| polni refreshLocal | 83 | 8 | 6,325 ms |
| scoped refreshLocal | 55 | 1 | 3,915 ms |
| createTask pred popravkom | 99 | 9 | 12,730 ms |
| createTask po popravku | 71 | 2 | 11,297 ms |

To so števci ene kontrolirane poti in posamezni elapsed časi, ne statistični
CPU/native benchmark ali napoved pospeška mobilnega šifriranja. Dve branju
pri save sta obstoječi pre-read in postcommit projekcija istega prostora.

Pregled vseh `_edit`/`_recordEdit` callsiteov potrdi scope-bound mutacije
(opravila, dogodki, projekti s fazami, nakupi, osebe, vrt in ideje). Njihov
postcommit zdaj poda `scopeIds: {scopeId}`. CAS, avtorstvo, šifriranje, signed
outbox in pre-read ostanejo. Člani/finance metadata/queue ter drugi skupni
pomožni podatki se še preberejo; ne trdimo, da je cel refresh samo en prostor.

**2 novi kontroli PASS1:** baseline meritev (ni ponovljena) in nova kontrola
popravka s shranjenim opravilom, identično projekcijo nedotaknjenega prostora,
0 transportnih klicev ter dvema sočasnima lokalnima shranitvama v drugih
prostorih. Vsi trije zapisi vidni, 3 namere v outboxu, nič izgubljenega.
Analiza 0 errors/0 warnings/9 starih info. Dokazi `p8-*` v isti mapi.

Meritev lokalnega vrta in idej: skupno 48 SQL branj/22,368 ms, vsak stream
4 dogodke vključno z enim eksplicitnim diagnostičnim drain reloadom. To potrdi
možnost nadaljnjega združevanja lokalnih signalov, ne dodatnih HTTP. Teh
pre-read/CAS/own-ACK poti nismo spreminjali. Večji poseg v fanout in P4b
ponovna uporaba zaključenih finance izbir ostaneta neobvezni nadaljevanji
po ločeni meritvi; za ta korak ni podlage za nov TTL finančnih pravic.

## Zaključni pregled nadaljevanja

P2 ima še majhno omejitev stroška: kontekst se vzpostavi samo za datoteke,
večje od enega 256 KiB kosa. Manjše priloge/slike uporabijo prvotni neposredni
prenos, brez nepotrebnega zajema projekcije za neobstoječi naslednji kos.
2 novi repository kontroli PASS1 (1 KiB in točno 256 KiB): en chunk request,
0 download contextov, končni bajti isti. Večkosovni PASS niso ponovljeni;
slike idej so v tem nadaljevanju izvorno pregledane, brez novega asset HTTP testa.

Končna analiza vseh spremenjenih Dart datotek: 0 errors/0 warnings in 31
obstoječih slogovnih info; `final-changed-analysis.log`, exit 0.

Skupaj nadaljevanje vsebuje **15 različnih novih uspešnih lokalnih kontrol**
(7 P2, 6 P6, 2 P8); prejšnji PASS scenariji niso ponovno pognani. Testi imajo
pravo memory SQLite in widget/repository izvajanje, transport je sintetičen.
Ni novih dokazov mobilne hitrosti, dejanskega E2EE HTTP prihranka ali
produkcijske pripravljenosti. Napake testnih podlag in ujeti UI popravek so
zapisani zgoraj; noben scenarij ni presegel treh testnih poskusov.

Ločene Git točke tega nadaljevanja:
- `4ec1560`: večkosovni prenos in preverjena content projekcija.
- `cf5660f`: članstvo/povabila prek generacij koordinatorja in ciljni imenik.
- `e99a426`: lokalni postcommit refresh samo spremenjenega prostora.
- Naslednji mali commit: izločitev enokosovnih prenosov iz P2 konteksta in ta
  zaključna dokumentacija. Vsak push se preveri s primerjavo remote main/HEAD.

Za naslednjo fazo ostanejo neobvezna večja optimizacija lokalnih pomožnih
branj/signalov, izmerjeno utemeljena P4b finance result reuse ter dejanska
HTTP/native meritev teh sprememb. Ni spreminjanja migracij, podatkov, ključev,
pravil sprejema ali finančnih varoval. Obstoječi QA podatki, Docker storitve,
telefoni in produkcija v tem nadaljevanju niso bili uporabljeni ali spremenjeni.


## Preverjanje vseh dostopov ob zagonu in ročno — 26. oktober

Uporabnik potrdi en pregled ob svežem zagonu v ozadju in gumb **Preveri vse dostope**. Odpiranje Utripa ne čaka na omrežje; ob zapiranju ne izvajamo opravila. Pregled je del obstoječe serializacije koordinatorja, ne nov timer ali opravilo posameznega zaslona. Ista seja v pomnilniku opravi začetni pregled enkrat; poznejši 30-sekundni krogi ostanejo changed-only. Omrežna napaka ne potrdi opravljenega pregleda, zato naslednji dovoljeni krog obstoječega razporejevalnika lahko nadaljuje. Ponovna prijava oziroma nova instanca repozitorija zahtevata svoj pregled.

### Izvedba in varovala

- `collaboration_access_review.dart`: skupni `scopes.list` skozi obstoječo overjeno kriptografsko pot, razveljavitev starega authority reuse, obstoječa omejena skupina preverjenih branj, lease in transakcijska uveljavitev z epoch/session varovalom. Ne gre za neposredno zaupanje tabeli članov na strežniku.
- Staršem sledi lokalna uveljavitev podprostorov. Manjkajoč nadrejeni prostor je dovoljen za povabilo samo v projekt; cikel ali protisloven odgovor se zavrne pred uveljavitvijo.
- Sveže preverjen prostor nadomesti staro lokalno oznako revoked. Samo blokada, povezana s starim revoked, se sprosti; ostale operativne blokade ostanejo. Starejša sequence, pending dokaz, nezdružljiva politika ali lokalna oznaka deleted se ne uporabijo za odklep.
- Dodatna najdba: `crypto_visible_task_scope.dart` je prek `...local` tudi po veljavnem preverjanju glave/članstva ohranjal staro revoked oznako. Zdaj preverjeni rezultat prekliče to lokalno zanikanje, pending veja ga ohrani. Izbrisa ne razveljavlja.
- Potrjen odvzem/izbris uporablja obstoječo `_upsertScope` obravnavo. Sama odsotnost iz kataloga pomeni unresolved/reconciliation, ne dokaz odvzema. Celotna omrežna napaka ne spreminja scope vrstic.
- Podatki, ključi, cursorji, osnutki, podpisane zahteve in receipts se ne ponastavljajo. Neodvisno blokiranih outbox operacij ne prestavimo samodejno v pending: potrebujejo obstoječo izrecno nadaljevalno pot. Lokalna regresija potrdi bajtno ohranitev originalnega requesta in osnutka.
- Gumb je v nastavitvah povezanega računa in prostora, tudi ko v računu ni nobenega vidnega prostora. Ima stanje preverjanja, zaščito pred večkratnim pritiskom, povzetek dostopnih/obnovljenih/preklicanih/nepreverjenih ter varovalo zamenjave računa. Zagon, gumb in sočasni ročni pozivi delijo isti pregled.
- Pregled ne zahteva celotnega content/finance pulla. Obstoječa kriptografska pot lahko pridobi manjkajočo šifrirano metapodatkovno vsebino ali dokaze; zato en logični scopes.list NI obljuba enega dejanskega HTTP zahtevka. Na realnih mobilnih podatkih število/čas še nista izmerjena.

### Lokalni rezultati

15 novih kontrol PASS + 2 prilagojeni obstoječi metadata-routing kontroli PASS (17 različnih kontrol):

1. 7 koordinator/SQLite: popravek stare blokade ob unchanged; nadaljnja dva kroga samo account.changes; 14 prostorov/en logični seznam in združena ročna poziva; potrjen odvzem proti izpuščenemu prostoru; offline byte parity in nadaljevanje; pending proof in poznejša ročna obnova; cikel; starejša sequence. Prvi tek vseh sedmih FAIL v pripravi zaradi manjkajoče accounts FK vrstice; drugi PASS. Vsebinsko ni bilo testnega odklepa mimo produkcijske poti; transport v tem sklopu je sintetični legacy adapter.
2. 2 novi kontroli dejanske E2EE projekcije z nadomeščenim ponudnikom preverjene glave: potrjena glava odstrani staro revoked/blocked projekcijo; zavrnjena glava ne vrne odklepa. Produkcijska SQL/projekcijska koda, ne nova kriptografska HTTP/signature integracija. Prvi tek compile fixture FAIL zaradi neubežanega SQL `$`; drugi PASS. Stari project-root PASS ni ponovljen.
3. 2 prekinitveni/hranilni: odjava med odgovorom ne uveljavi starega rezultata; osnutek in že blokiran originalni outbox request ostaneta enaka. Prvi compile fixture FAIL (manjkajoč import); drugi odjava PASS, osnutek FAIL zaradi nepopolnega sintetičnega Task payloada; tretji samo osnutek s pravim modelnim serializerjem PASS. Ni četrtega poskusa.
4. 2 widget kontroli: gumb brez vidnih prostorov, busy/rezultat; zamenjava računa skrije prejšnji rezultat. Prvi compile fixture FAIL zaradi prekritja podedovanega `calls`; drugi PASS.
5. 2 novi produkcijski router kontroli: manjkajoča preverjena identiteta in restore fence ustavita začetni pregled; ni plaintext fallback scopes.list in scope vrstice ostanejo iste. Uporabljen pravi CryptoBusinessRouter, account provider namensko zavrne; ne celoten podpisni E2EE dokaz.
6. 2 prilagojeni metadata routing kontroli zdaj neposredno preverita izjemo account.changes. Stara domneva, da hladen zagon nikoli ne preveri avtoritete, po novem dogovoru ne velja. Obnovitveno varovalo ni oslabljeno.

Dokazi: `build/qa/access-review-20261026/` (vključno z vsemi neuspelimi pripravami). Samo lokalni headless Flutter/SQLite/widget testi. Ni novega Mac GUI/HTTP scenarija, gradnje ali namestitve na telefon, spremembe obstoječih testnih shramb ali produkcije. Prvotni Samsung Mobile E2EE/Preg1 ostaja nedotaknjen; njegova dejanska obnova in mobilni čas pregleda sta naslednji ročni preizkus po namestitvi.

### 26. oktober — Samsung: vrnitev prostora in nadaljevanje Preg1 USER PASS

Po posodobitvi iste Jivie Test na 4580fbe uporabnik odpre aplikacijo: manjkajoči skupni prostor se vrne pred eno minuto; nato odpre obstoječo preglednico, jo uredi in uspešno shrani. Brez novega povabila, ponovnega vnosa ali odjave. To je uporabnikova potrditev odprave stare lokalne blokade in nadaljevanja obstoječih podatkov, ne meritev natančnega časa izrisa.

Read-only diagnostika `build/qa/mobile-access-review-20261026/android/diagnostic-read-20261026T175201890699Z.json`: 573 dogodkov nove gradnje, 131 zajetih HTTP odgovorov, vsi 200 (0 zajetih 403/429). En crypto2.records.batch ob 17:51:15.875 UTC, pridobitev in sprostitev urejanja prav tako200. Koordinator nato izbere samo1 content scope/0 finance; completion seq1 ob17:51:30.226 UTC code=none/unresolved=false/retry=false in cursorAcknowledged. Naslednje 30s preverjanje unchanged. 64.451ms completion polje pomeni čas od začetka diagnostične seje, NE trajanja shranjevanja. Ne pripisuj vseh131 zahtevkov preverjanju dostopov: zajem vključuje zagon, odpiranje/urejanje/shranjevanje preglednice in sync.

Zajet en interni caught `crypto_record_policy_existing_scope_upgrade_pending` v syncCaught; obstoječa veja ga obravnava kot odloženo nadgradnjo politike, zaključek istega cikla nima napake. Ni dokaz, da je policy nadgradnja dokončana, niti neuspeha tega shranjevanja. Prenos/prikaz iste spremembe na drugi napravi v tem koraku ni preverjen. Agent UI/save/sync/launch actions=0, zgolj branje dnevnika. Ta vrnitev prostora in shranjevanje sta PASS; ne ponavljaj brez novega razloga. Mobilni ročni gumb Preveri vse dostope je še nepreverjen.


### 26. oktober — nova mobilna ugotovitev: finance in označevanje obvestil (ODPRTO)

Uporabnik na Samsungu poroča: v skupnem prostoru račun/finance sprva niso vidni; po odprtju »Dostop do financ« se pokažejo in vnose lahko dodaja. Nato »Označi vse kot prebrano« vrne »Za finance v tem prostoru nimaš dostopa …«. Slika 1000012454.jpg ob 19:31 lokalno kaže finančna obvestila v prostoru Mobile E2EE 20261018. To ni dokaz novega dejanskega odvzema pravic. Obe ugotovitvi sta odprti; brez ponovnega klika, nadgradnje ali popravljanja podatkov v tem pregledu.

Potrjeno iz kode:
- `collaboration_notification_actions.dart`, `markInboxRead`: v eni lokalni transakciji preverja vsak izbran inbox ID. Za finančna obvestila vrne isti `finance_forbidden` tako pri finance_blocked kot pri finance_complete != 1/manjkajoči scope vrstici ali cached policy.canRead=false. Torej nepopoln lokalni prikaz in zavrnjen dostop dobita isto sporočilo. Preverjanje je pred enqueue inbox.read; ena zavrnjena postavka prekine transakcijo celotne skupine. Prava varovala session/scope/signed request ostajajo potrebna.
- `collaboration_repository.dart`, `_scopeData`: račune/vnose pokaže šele ob finance_complete=1 in policy.canRead. Odsotnost računov v tem stanju sama ne dokazuje odsotnosti strežniških podatkov ali pravic.
- `finance_permissions_dialog.dart`, `_load`: odprtje prebere members in financeGrants. Samo odprtje ne podeli pravice. Ni še dokaza, katera osvežitev med tem odpre prikaz. Staro lokalno zanikanje politike po prejšnji lažni revokaciji je kandidat, ne potrjen runtime vzrok.

Read-only zajem `build/qa/mobile-access-review-20261026/android/diagnostic-read-20261026T183400300814Z.json`: 2420 dogodkov od17:50:25 do18:33:01 UTC, 526 HTTP dogodkov v celotnem mešanem obdobju uporabe (NE toliko zahtevkov za en klik). Sync diagnostika ne zajame točne lokalne UI izjeme markInboxRead. Štirje notranji policy_existing_scope_upgrade_pending so zaključeni kot odložena priprava brez napake cikla. Ločena zadnja network napaka authority.snapshot ob18:33:01 UTC je poznejša od slike in je ne pripisujemo označevanju obvestil.

En omejen read-only VM pregled metapodatkov se je končal z timeout po6,43s; ni uspešnega odčitka konkretnega zavrnjenega inbox ID/politike. Zapis v `build/qa/finance-inbox-observation-20261026/attempts.json`; brez nadaljnjih slepih poskusov, eval/invoke, UI dejanj ali poslovnih klicev. Produkcija, podatki in podpisane zahteve nespremenjeni.

Predlagan naslednji popravek: ločiti lokalno pripravljenost financ od dejanske pravice; po obnovi dostopa ciljno uskladiti finančno stanje prek obstoječega koordinatorja. Pri skupinskem označevanju obravnavati nedostopno/zastarelo obvestilo ločeno, z ohranjenimi preverjanji računa in prejemnika ter podpisano potjo. Najprej lokalna regresija mešane skupine obvestil in obnovljenega prostora; brez ponovitve uspešnega mobilnega prenosa ali Preg1.

Uporabnik dodatno pojasni: kliknil je prav gumb **Dostop do financ na vrhu modula Finance**, brez opisanega spreminjanja dovoljenj. Pred tem je modul prikazoval opozorilo o manjkajočem dostopu (točno besedilo ni zajeto); po kliku so se prikazale finančne informacije. Ne opisuj tega samo kot praznega seznama računov. Sveži read-only posnetek Samsung19:39 v `build/qa/finance-inbox-observation-20261026/current-screen.png` potrdi isti gumb pod naslovom Finance, zelen oblaček in omogočen Dodaj zapis, obenem pa »Pregled projektnih financ še ni popoln …«. To je trenutno stanje, ne posnetek stanja pred klikom. Gumb v `shared_finance_workspace.dart:183` odpira `showFinancePermissions`; ni bil ponovno pritisnjen. Vzročna povezava prikaza z branjem members/grants ali sočasnim koordinatorjem še ni izolirana.


### 26. oktober — ciljni popravek finančnega dostopa in inbox receipts, lokalno PASS

Uporabnik potrdi, da ima legitimno dodeljene finančne pravice, nato izrecno naroči popravek. Ne spreminjamo dodeljenih pravic. Lokalno reproducirana vrzel: preverjanje dostopov obnovi prostor, vendar star finance policy denial in nepopoln snapshot ne izbereta običajne finančne poti, kadar account.changes ostane unchanged. To potrdi vzrok v tej lokalni reprodukciji; ni naknadni dokaz natančne runtime vrstice Samsungovega prvotnega klika.

Izvedba:
- Preverjeni začetni/ročni pregled dostopov za dostopne prostore z obnovljenim dostopom, neznano/zavrnjeno cached finančno politiko ali nepopolnim snapshotom zapiše lokalno zahtevo za ciljni finančni pregled. Zasebni izključeni prostori so izvzeti. To ni grant ali nastavitev complete.
- Obstoječi koordinator zahtevo združi s finance hints tudi ob unchanged strežniškem cursorju. Običajni policy/pull in podpisna preverjanja ostanejo. Ni novega timerja, UI omrežnega preflighta ali full content synca. Po uspehu ali sveži pravi zavrnitvi se zahteva porabi; naslednji nespremenjeni krog ne ponovi finance policy/pull. Omrežna/prehodna napaka zahtevo ohrani za obstoječi mehanizem nadaljevanja. Ključ zahteve je vezan na točno particijo, brez LIKE wildcard ujemanja URL-ja.
- Inbox read receipt ne zahteva več finance_complete=1: gre za oznako obvestila, ne dostop do finančnega zapisa. Še vedno preverja trenutni račun, scope, dejansko cached pravico in finance_blocked. Transakcija skupine ter podpisan immutable inbox.read prenos sta ohranjena. Prave zavrnitve se ne preskakujejo potiho in ni delnega uspeha skupine, prikazanega kot popoln uspeh.
- Ni resetov, sprememb formata ali oslabitve kriptografskih preverjanj. Že blokiranih zahtev ne postavljamo samodejno nazaj v pending.

6 novih lokalnih kontrol PASS:
1. Mešana skupina task+finance obvestil se označi prebrana tudi ob nepopolnem finančnem snapshotu; snapshot ostane nepopoln, ustvarita se dve inbox.read zahtevi.
2. Prava finance denial v drugi postavki razveljavi celotno skupino, brez prebranih oznak ali queued zahtev.
3. Lokalno revoked prostor s staro finančno prepovedjo se obnovi in prenese račun ob unchanged cursorju; naslednji krog brez finance branj.
4. Že obnovljen prostor s preostalo staro finančno prepovedjo se popravi brez odpiranja dovoljenj.
5. Sveža strežniška finančna zavrnitev ostane zavrnitev, brez pulla in brez ponavljanja naslednji krog.
6. Prekinitev policy branja ohrani zahtevo in blocked finance_outbox bajtno; nadaljevanje popravi stanje in porabi zahtevo, blocked vnos ostane enak. Test uporablja sintetični blocked request, ne novega dokaza realnega kriptografskega podpisa.

Prvi tek: oba inbox testa PASS; trije finance testi se ustavijo v podlagi zaradi INSERT ob že obstoječem account cursorju. Podlaga uporablja upsert; drugi tek SAMO teh treh PASS. Resilience test prvič compile FAIL zaradi manjkajočega importa transport exception, drugič PASS. Noben četrti poskus ali ponovitev PASS. Prava memory SQLite/repository/materializacija in sintetični transport, brez novega HTTP/native/GUI dokaza. Dokazi v `build/qa/finance-inbox-observation-20261026/`: local-tests-attempt1.log, finance-tests-attempt2.log, resilience-attempt1/2.log, analyze-final.log. Scoped analiza brez napak/opozoril, deset obstoječih style infos. Produkcija, telefoni, nameščeni paketi in obstoječe testne baze v tem popravku nedotaknjeni. Naslednje: posodobitev iste Jivie Test in ozka mobilna potrditev obeh novih ugotovitev, brez ponavljanja starih PASS.


### 26. oktober 19:53 — označevanje inbox: dejanski Samsung vzrok ujet

Oba QA sta pred tem uspešno posodobljena na ad06e36; evidence `build/qa/mobile-finance-access-fix-20261026/HANDOFF.md`. User pravi, da prikaz financ že deluje, novi cilj je samo mark-all-read. Izrecno dovoli agentu en klik na Samsungu. Aktualni screenshot potrdi prav zaslon Obvestila in gumb. Agent postavi dve ozki debugger breakpoint mesti v nameščeni debug gradnji (notification actions157/163), nato natanko1 adb tap na viden gumb.

**Native dokaz** `android/inbox-debug/capture1.json`: ustavitev na PRVEM throw mestu157, inbox id18, categoryfinance/targetfinanceEntry, scope04beef63-4eaf-490a-8056-03fa3f506e28. Scope blockedfalse/archivedfalse/revokedfalse/deletedfalse. Lokalna SQL vrstica obstaja in ima finance_blocked=1. Zavrnitev se zgodi PRED cached policy preverjanjem in PRED enqueue/inbox HTTP. Breakpointa odstranjena in aplikacija nadaljevana; ni spreminjanja spremenljivk, eval/invoke ali poslovnih klicev skozi VM. Skupina ostane neprebrana.

**Native read-only potrditev pravic** `android/inbox-debug/state2.json`: za ISTI parent enabledtrue/grantwrite/revision2/readAccessFromMembershiptrue/managedByOrganizationPolicytrue/organizationFinanceCompletetrue in financeSnapshotCompletetrue. To ni manjkajoča pravica ali nepopoln snapshot: uporabnik ima pravilen lokalno preverjen finančni dostop. Prvi dodatni state-read s polnim getClassList se konča ConnectionClosedError; drugi uporablja samo znano library in12bralnihRPC, PASS. Noben dodatni tap. Prvi breakpoint zajem10RPC/PASS1.

Koda uporablja finance_blocked tudi kot varovalo čakajočih zapisov: _hideFinance/_blockFinanceWrites ga postavita, obnovljena politika in uspešen pull ga ne počistita; resumeBlockedFinanceChanges ga sprosti skupaj s ponovnim pošiljanjem blokiranih vnosov. Običajni novi write preveri finance_blocked skupaj z dejanskimi blocked finance_outbox vnosi. Inbox receipt pa je napačno preverjal samo zastavico, tudi ob veljavnem grantwrite in popolnem snapshotu. Prejšnji popravek finance_complete je bil resnična druga pomanjkljivost, vendar ni odpravil tega dejanskega mobilnega primera.

Naslednji ciljni popravek: ločiti finančno write-queue blokado od pravice do oznake prebranosti; obdržati scope/session in pravo finance canRead preverjanje ter podpisano inbox.read pot. NE čistiti finance_blocked na silo in NE auto-resubmit starih blocked zahtev. Lokalna regresija mora vključiti natančno combination finance_blocked1+grantwrite+complete1 in ohranitev blokirane vrste. V tem diagnostičnem koraku ni novega produktnega popravka/builda/installacije, iPhone/produkcija nespremenjena.

Reader prvotno zavrne lokalno schema identiteto zaradi starega build/namespace v kopirani shemi; popravljeni samo ti dve identiteti za obe platformi, omejitve/validacija nespremenjene. Nato Android finite reader104dogodki predklikom/116pokliku uspešno; UI izjema ni syncCaught, zato je odločilen debugger dokaz, ne odsotnost failure dogodkov.


### 26. oktober — popravek dejanske Samsung inbox blokade, lokalni RED → GREEN

User izrecno naroči samo lokalni popravek in test točnega primera; S25 odklopi, namestitev bo pozneje. `markInboxRead` ne uporablja več finance_blocked kot zanikanja pravice branja obvestila. Obstoječi _readableReminderScope, scope.blocked/archived, cached finance policy.canRead, current-account/epoch, stillEligible in transakcija ostanejo. Ne spreminjamo finančnih vrst, podatkov, podpisnega protokola ali dovoljenj. Ni avtomatskega sproščanja blokiranih finančnih zahtev.

Pred popravkom nova lokalna reprodukcija grantwrite/revision2/finance_complete1/organizationFinanceCompletetrue/finance_blocked1 pade z finance_forbidden na notification_actions157, tako kot native zajem. Po popravku štiri ciljne kontrole PASS: write in read grant dovolita mešano skupino dveh receipts, pri čemer lokalni finance account payload, celotna blocked finance_outbox vrstica in finance policy/blocked/complete flags ostanejo bajtno/enakovredno nespremenjeni; oba queued inbox.read imata izvirni expectedRevision1. Prava finance denial ohrani neprebrano skupino in nič queued commands, prav tako prava scope blokada kljub stale eligible UI. Stari test, ki je zahteval zavrnitev tudi ob veljavnem read grant, je nadomeščen s tem pravilnim contractom.

Dokazi `build/qa/inbox-write-block-repair-20261026/`: reproduction-attempt1.log (pričakovani produktni FAIL, ne fixture napaka), targeted-tests.log (4PASS, write drugi tek/read+2negative prvi), analyze.log (No issues found). Pravi lokalni repository/SQLite s sintetičnim transportom, ne novo mobilno/HTTP/signature preverjanje. Stari PASS niso ponovljeni, brez build/install/UI/device/server dejanj. Oba telefona sta še na ad06e36; nov popravek čaka uporabnikovo vrnitev in posodobitev iste Jivie Test.
