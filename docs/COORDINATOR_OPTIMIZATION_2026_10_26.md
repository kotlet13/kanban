# Postopna optimizacija koordinatorja — 26. oktober 2026

Izhodišče: `66ee218`; ugotovitve P1–P8 iz
[modulnega pregleda](MODULE_SYNC_AUDIT_2026_10_26.md).
Uporabnik naroča ločene lokalne/headless kontrole ter commit in push vsakega
smiselnega sklopa. Brez posegov v telefone, obstoječe QA podatke ali produkcijo.
Meritve spodaj so števci konkretnih testnih poti, ne mobilni časovni benchmark
ali obljuba števila fizičnih E2EE HTTP zahtevkov. Starih uspešnih scenarijev
ne ponavljamo. Največ trije poskusi neuspešnega scenarija.

## Trenutno stanje po šestih implementacijskih sklopih

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
