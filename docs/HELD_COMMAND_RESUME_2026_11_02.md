# Nadaljevanje zadržanih zahtev po pripravi zaščite — 2. november 2026

## Uporabnikova ugotovitev in obseg

Po 1.11.12 je ročni pregled pokazal `crypto_command_receipt_pending` in
`scope_rotation_required`. Tudi po obisku priprave zaščite je isti par ostal.
Izvoz ne vsebuje operacije ali prostora in lahko kaže ohranjeni stari razlog;
dejanske vrste uporabnikovih 19 zahtev ne poznamo. Uporabnik naroči lokalni
popravek, novo Android izdajo in oddajo na Google Play. Telefoni, strežnik,
uporabniški podatki, ključi in varovala ostanejo nespremenjeni med razvojem.

## Izvedba

Ročni poskus poleg exact receipt pregleda omogoča ozko nadaljevanje zahteve,
ki jo je pred pošiljanjem ustavil scope_rotation_required. Isti request ID,
podpis in vsebina ostanejo. Najprej preveri točen končni izid, nato trenutno
avtoriteto izvorne operacije, trenutno napravo in dejanski podpis. Vrsta ostane
blocked tudi med pošiljanjem; prekinitev je ne spremeni v nenadzorovan samodejni
retry. CAS po asinhronih mejah ohrani tuje spremembe. Največ 64 zahtev/1 MiB.
Zavrnitev, neznan izid, izguba pravic ali napačen podpis ne pomenijo uspeha.

Prava rotacija lahko naredi star podpisani checkpoint neuporaben. Posebna
pot za IZPELJANI `crypto2.domain.checkpoint` zato dokazuje lokalno nadomestitev:
pravi stari in novi podpisi, preverjena veriga glav do strogo novejše epohe,
isti prostor/domena/račun/naprava, povsem isti manifest/število/historyBasis,
nezmanjšano zaporedje, točen applied receipt novega preverjenega popolnega
checkpointerja, fresh unknown receipt stare zahteve ter nič zahtevkov nad
revizijami zapisov. Stara vrstica ostane blocked z vsemi izvornimi dokazi;
lokalni marker in ujemajoč audit dogodek ločeno označita izpolnjeno izpeljano
opravilo. To ni izmišljeno strežniško applied/rejected potrdilo. Marker ni v
FILE allowlisti za obnovo lokalnih namenov. Spremenjen inventar ali nepovezana
zahteva ostaneta zadržana. Ni spremembe sheme ali strežniške pogodbe.

Skupni SQL predikat uporablja marker/hash/audit/novi applied checkpoint/nič
record claims za štetje, izbiro in dostavo ter za migration in record-policy
preverjanje čakajočega dela. Ni vir pravic ali kriptografske avtoritete.
Ročni checkpoint kandidat sproži običajen celotni preverjeni prenos. Vsaka
nova dokazana nadomestitev zamenja generacijo refresh markerja; star CAS je
ne sme izbrisati. En ročni klik lahko opravi največ en dodaten celotni prehod,
če se je generacija med uspešnim prehodom spremenila. Nadaljnja sočasna dela
ostanejo vidna. Samodejni nespremenjeni poll ostaja poceni. Zelena zahteva vse
obstoječe finance/content/queue/session/conflict kontrole in končno projekcijo.

UI doda razlago scope_rotation_required in obstoječo varovano pot do zaščite;
pri pending razlogu pojasni, da je lahko prejšnji vzrok zgodovinski.

## Dokazi in omejitve

40 različnih novih lokalnih kontrol PASS: 16 queue/core, 14 checkpoint,
7 koordinator/štetje/generacije, 3 UI. Noben uspešen test ni ponovljen.
Core16 PASS1. Checkpoint11 PASS1 + missing_history fixture FAIL1, samo ta
PASS2; dva dodatna podpis/generacija testa PASS1. Root4 PASS1 + nov missing-row
PASS1 + nova dva generation testa PASS1. Pravi SQLite, libsodium podpisi,
AccountDirectoryV2, ScopeCryptoCodec proposal/activation veriga in produkcijski
checkpoint verifier; mreža, pridobivanje glav/imenikov in projekcije imajo
izrecne sintetične meje. To NI phone/native/HTTP E2E in ne potrjuje vseh
uporabnikovih dejanskih zahtev.

Dodatna izbirna sprememba sporočila ob vrnitvi iz account wizard NI vključena:
5 widget kontrol je po fixture napakah doseglo STOP3, zato je izvorni popravek
wizard povrnjen; kontrole ostanejo izrecno skipped za prihodnje delo. Trije
UI testi v izdaji so PASS (en R2, dva R3), brez ponavljanja PASS. Nobenega
četrtega poskusa. Ta omejitev ne skriva neuspešnega testa vključene sync kode.

Neodvisen pregled Sol6.1/high in root: varovala iste podpisane zahteve, dokaz
nadomestitve, SQL/network meje, FILE izolacija in generacijska dirka. Najdena
IGNORE/CAS dirka je popravljena z novo generacijo in dodatnimi ciljnimi testi.
Dokazi: build/qa/held-command-resume-20261102/{core,checkpoint,ui,root}/.

Po javni posodobitvi isti račun, brez reset/reinstall/obnove; en Uskladi zdaj.
Preostala resnična ovira ostane prikazana. Ta izdaja ne obide manjkajočih
pravic ali dokazil in ne obljublja razrešitve neznanih vrst zadržanih zahtev.

Končna skupna analiza 19 Dart datotek: 0 napak, 0 opozoril, 34 predhodnih slogovnih info (vključno z dodatno pregledanima migration/policy datotekama). Root 3 nove testne info popravljene; testna analiza 0 issues. Diff check PASS.

## Uporabniški preizkus po oddaji 45 — 10:37 UTC

Uporabnik posreduje screenshot 1000012611 in izvoz z enim vnosom:
`preflight / crypto_command_receipt_pending`, čas
`2026-11-02T10:37:39.806682Z`. Na screenshotu ni številke različice ali števila
preostalih zadržanih zahtev. Izid uporabniškega preizkusa: sinhronizacija še
ni potrjena; to NI runtime PASS popravka. Izginotje scope_rotation_required
ni dokaz odpravljene rotacije ali manjšega števila zahtev.

Bralni pregled kode potrdi diagnostično vrzel: v
collaboration_sync_actions.dart, končni blok `retainedFailures.isNotEmpty`,
po običajnem prenosu odstrani preflight podrobnosti in ponovno sestavi le
kategoriji iz SQL EXISTS nad aktivnimi blocked crypto zahtevami ter karanteno
plačil. Zato lahko specifični ohranjeni ali sveže dobljeni razlog izgine,
četudi ista zahteva ostane blocked. Izvoz sam ne pove, katera od poti ga je
ustvarila ali katera operacija/guard/receipt rezultat je zadnja ovira.

Dodatno: terminal lookup lahko vrne unknown ali zavrnitev vpogleda brez
spremembe retained response; resume velja le za točen unresolved /
authority_pending / scope_rotation_required. Ostalih vrst ni varno sprostiti
na slepo. Dokazana checkpoint nadomestitev ima še stroge pogoje istega
inventarja, iste naprave in preverjene nove verige/potrdila.

Naslednja potrebna diagnostika mora varno razlikovati operacijo, končni
rezultat receipt lookup (unknown/denied/applied/rejected), izvedeno ali
preskočeno nadaljevanje in njegov aktualni guard ter število aktivnih held
zahtev. Zgodovinski razlog naj bo izrecno ločen od aktualnega izida; podatki
morajo pripadati še vedno aktivni isti zahtevi, ne sosednjemu zapisu. Ne
izvažati ID-jev, podpisov, ključev ali vsebin. Te informacije v uporabnikovem
trenutnem JSON niso prisotne, zato dejanski vzrok ostaja nepotrjen.

V tem pregledu ni izvajanja testov, posegov v telefone/strežnik/uporabniške
podatke, produktnih sprememb, nove gradnje ali objave. Obstoječih uspešnih
testov nismo ponavljali. Uporabniku ne nalagamo nove obnove ali ponovitev
čarovnika na podlagi generičnega rezultata.
