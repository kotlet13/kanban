# Ciljni lokalni preizkusi pred telefoni — 22. oktober 2026

**Posodobitev 23. oktobra:** po ločenem naročilu za popravek je tudi L2
zaključen s PASS na istem ohranjenem paru. L1 in L3 nista bila ponovljena.
Spodnji prvotni STOP ostaja zgodovina; popravek in novi dokazi so na koncu.

Uporabnik je naročil tri nove sklope: dokončno razrešitev konflikta opravila,
prekinitev oziroma konflikt opravila s povezanim stroškom in pravilna dejanja
ob opozorilih sinhronizacije. Uspešni stari testi se ne ponavljajo. Vsak sklop
ima trajen števec največ treh zagonov, vključno z napakami prevajanja; uspešni
podkoraki se ohranijo. Potrjene napake aplikacije se v tem testnem naročilu
zabeležijo, brez sproščanja varoval ali spreminjanja podatkov za doseganje PASS.

## Ločitev okolij

L1/L2 uporabljata nov lokalni `jivie-sync-gaps-lab-20261022` na
`127.0.0.1:59778`, lastne volumes in štiri nove sintetične identitete. Vsak
scenarij ima lasten par odjemalcev, baze in ključe, zato napaka enega ne
zahteva čiščenja stanja drugega. Stara H4/H7 odjemalca, njun odvzem dostopa,
konflikt in čakajoče delo ostanejo nedotaknjeni. Izvor je vezan samo za branje;
ni nove native gradnje, kopiranja celotnega izvora ali posegov v telefone,
produkcijo in stare QA namestitve.

Zasebni fixture in surovi dnevniki so v `/tmp/jivie-sync-gaps-lab-20261022`
z omejenimi dovoljenji. Javni metapodatki so pod
`build/qa/local-diagnostics/sync-resolution-cost-20261022/`. Priprava okolja
je PASS v drugem poskusu: prvi je naletel na še nepripravljen Dockerjev
supervisor; drugi nadaljuje isti vsebnik z omejenim čakanjem. Računi so
pripravljeni enkrat, prvi poskus PASS. To še ni rezultat poslovnih testov.

## L1 — dokončna razrešitev konflikta: PASS

Prvi zagon, 255,411 s z vključenim omejevanjem pogostosti zahtevkov; vseh
deset podkorakov PASS, nespremenjen izvor, noben HTTP 429. Dva nova konflikta
se zaključita prek dejanskega `resolveConflict`: enkrat z izbiro strežniške,
drugič z izbiro lokalne različice. Običajni `syncNow` obeh aktivnih članov
potrdi enako vsebino, strežniško in kriptografsko revizijo ter dokaz zapisa.
Pri lokalni izbiri revizija napreduje, pri strežniški ostane zmagovalna.
Oba konflikta imata dejanski strežniški odgovor 409: strežniška izbira
konča na reviziji 2, lokalna na reviziji 3. Optimistične lokalne revizije
odjemalcev niso uporabljene kot merilo ujemanja.
Konflikt in običajna čakajoča zahteva za razrešeni zapis sta odstranjena;
izvirne podpisane zahteve in rezervirane namere ostanejo nespremenjene.
Končni cikel obeh odjemalcev nima napake ali nerešenega dela.
Neodvisni pregled ohranjenih baz in dokazov potrdi tudi vse stare rezervacije;
lokalna razrešitev doda dve novi pri pričakovani reviziji 2, brez menjave
lastnika starih rezervacij. Glavni in neodvisni pregled PASS.

Pomislek iz statičnega pregleda glede manjkajoče oddaljene različice se tu
ni potrdil. To je test aktivnega člana s pravico branja; ne spreminja starega
H4 primera po odvzemu dostopa in ne trdi, da je njegova oddaljena vsebina
ponovno dostopna. L1 se po uspehu ne ponavlja.

Dokaz: `build/qa/local-diagnostics/sync-resolution-cost-20261022/launch-summary.json`.

## L2 — opravilo s povezanim stroškom: DELNO, potrjena napaka

Prvi zagon se zaključi neuspešno po 247,654 s; izvor je nespremenjen,
HTTP 429 ni bilo. Uspešni podkoraki so trajno ohranjeni in se ne ponavljajo:

- Dejansko sprejeti skupni paket vsebuje točno povezano opravilo in strošek.
  Odgovor 200/applied se namerno izgubi šele po preverjanju izvora, identitet
  obeh zapisov, podpisanega telesa, hasha in rezervacij izvirne zahteve.
- Po ponovnem odprtju iste baze odjemalec prebere pravo potrdilo iste zahteve.
  Prvotni paket ni ponovno poslan. Podpis, hash in rezervacije ostanejo enaki;
  oba odjemalca se uskladita na istem opravilu in istem strošku 10 €.

Nadaljnja sočasna sprememba istega para razkrije napako. Lastnik uspešno
objavi strošek 20 € na reviziji 2, član pa ohrani osnutek za 15 €, pripravljen
na reviziji 1. Članov `sync6.pushTaskWithCost` po svežem preverjenem branju
vrže navadni `CollaborationException('stale_edit')` v
`crypto_business_router.dart:2098`. Pot za zapis obeh konfliktov v
`collaboration_sync_actions.dart` obravnava `CollaborationApiException`,
zato lokalna zavrnitev obide to pot.

Ohranjeno stanje: član ima eno čakajoče opravilo, en čakajoči finančni vnos,
en povezovalni zapis in nič konfliktov. Osnutek 15 € ostane ohranjen; lastnik
ima potrjeno različico 20 € in prazni vrsti. Test nato odpove ob iskanju
pričakovanega finančnega konflikta (`No element`); to je posledica manjkajoče
klasifikacije, ne prvotni vzrok. Za ta osnutek ne trdimo novega strežniškega
409: zavrnitev se zgodi lokalno pred objavo novega paketa.

Glavni in neodvisni pregled potrdita isto izvorno mesto ter ohranjene baze.
Izrecni finančni pregled, končna uskladitev na 15 € in pričakovani saldo
85 € so **NEPREVERJENI**, ker do teh korakov ni mogoče priti. L2 je zato
DELNO/FAIL, ne PASS. Zaradi jasnega vzroka se ustavi že po prvem poskusu;
največ trije poskusi ne pomenijo obveznih treh ponovitev iste napake.

Naslednje ločeno delo je popravek pretvorbe preverjene zastarelosti obeh
delov v uporabniško razrešljiv konflikt, z ohranitvijo izvirnega para in
varoval. Nato nadaljevanje tega istega neuspešnega podkoraka, brez ponavljanja
uspešne prekinitve/obnove ali ustvarjanja novega para. Runtime v tem naročilu
ni bil spreminjan.

## L3 — dejanja ob opozorilih: PASS

Tri nove sestavljene poti uporabljajo prave widgete delovnega prostora,
oblačka, pregleda konfliktov in izvozne funkcije:

- Čakajoče E2EE delo: gumb sproži osvežitev; novo stanje odpre primerjavo
  konflikta in ohrani lokalni osnutek brez samodejne izbire različice.
- Odvzet dostop: osnutek je še viden in na voljo za izvoz, obe dejanji
  razrešitve konflikta sta onemogočeni; ni napačnega napotila za prijavo.
- Potekla seja: osvežitev je onemogočena, izvoz ostane dosegljiv in gumb
  prijave sproži predvideni navigacijski callback.

Prvi in tretji primer sta PASS v prvem zagonu. Pri drugem je test sprva
izbral enako poimenovan gumb v prekritem oknu; popravljena je samo omejitev
iskanja na vidni pregled konflikta. Samo ta primer je ponovno zagnan in
PASS v drugem poskusu. Analiza nove datoteke nima napak, opozoril ali pripomb.
Glavni in neodvisni pregled izvora ter dokazov sta PASS.

Meja dokaza: odziv osvežitve in vsebina izvoza prihajata iz sintetičnega
kontrolerja; izbirnik prestreže bajte in prekliče shranjevanje. Prijava vodi
na testni cilj. To potrdi povezavo UI dejanj, ne dejanskega strežniškega
synca, preverjanja prijave, vsebine pravega izvoza ali platformnega shranjevanja.
Runtime aplikacije ni spremenjen.

Dokaz: `build/qa/local-diagnostics/pre-mobile-gaps-20261022/ui/result.json`.
Izvor: `test/organizer/ui/pre_mobile_sync_continuation_test.dart`.

## Končno stanje in nadaljevanje

Vsi trije sklopi so obravnavani: L1 PASS, L3 PASS, L2 delni PASS z eno
potrjeno napako in nepreverjenim zaključkom. Nobenega uspešnega starega ali
novega podkoraka nismo ponavljali. Aplikacijska in strežniška runtime koda
ostaneta nespremenjeni. Analiza obeh novih testnih datotek nima pripomb;
Python pomočnika sta uspešno prevedena. Glavni in neodvisni pregled rezultatov
in omejitev sta zaključena. To ni dovoljenje ali dokaz za produkcijsko izdajo.

Namenski vsebnik 59778 je ustavljen. Ohranjenih je približno 9,3 MB zasebnih
dokazov in odjemalcev, 228 kB javnih dokazov pred končnim povzetkom ter
3.696 KiB podatkov v namenskem volumnu. Ni novih paketov aplikacije ali
vmesnih native gradenj. Potrebno stanje je ohranjeno za popravek L2.

Primerjava Docker inventarja je zaznala spremembo nepovezanega vsebnika
`aidiagramer-langgraph-local-before-progress` iz running v exited in drugačno
sliko. Ta naloga na njem ni izvedla dejanj; zato ne trdimo, da so bila vsa
druga stanja ves čas nespremenjena. Vse mutacije te naloge so bile omejene
na novi namenski laboratorij. Podrobnosti in omejitev primerjave:
`build/qa/local-diagnostics/sync-resolution-cost-20261022/final-retention.json`.

## 23. oktober — popravek in nadaljevanje istega L2: PASS

Uporabnik izrecno odobri popravek. Implementacijo in neodvisni pregled
opravijo podagenti GPT‑6.1 Sol/high, glavni agent pregleda kodo in rezultate.
Sprememba je omejena na lokalno primerjavo revizij v `pushTaskWithCost`:
po preverjenem branju obeh domen zastarelost vrne obstoječi paired `conflict`
z obema kanoničnima strežniškima različicama. Identiteta, tip, revizija in
oznaka izbrisa se ujemajo s preverjenim zapisom; pred vrnitvijo se preveri
še aktualnost računa. Manjkajoči zapis ostane izrecno `null`.

Prednostna pot že pripravljene podpisane zahteve, podpisi, rezervacije,
preverjanje dokazov in dovoljenj ostanejo nespremenjeni. Napak podpisov,
odvzema dostopa ali zamrznjenega prostora se ne pretvarja v poslovni
konflikt. Lokalna razvrstitev konflikta ni nov strežniški odgovor 409 in
sama ne dovoljuje zapisa. Ohranjen je izrecni finančni pregled pred izbiro
lokalne različice obeh delov.

Sedem novih ozkih kontrol je PASS v drugem poskusu. Prvi je odpovedal pri
tipizaciji testne priprave še pred izvedbo primerov; uspešnih testov ni bilo
ponovljenih. Drugi izvirni Flutter dnevnik vsebuje sedem uspehov in
`done.success=true`. Naknadni parser povzetka je odpovedal in povzetek je
bil obnovljen iz istega dnevnika brez novega teka; točen procesni izhod ni
bil shranjen in je označen kot neznan. Scoped analiza obeh datotek ima
nič pripomb. Te kontrole uporabljajo sintetično mejo preverjenega branja;
ne dokazujejo samega kriptografskega preverjanja ali HTTP prenosa.

Dejansko nadaljevanje istega L2 prek lokalnega HTTP strežnika je **PASS v
drugem skupnem zagonu**, 72,331 s, izhod 0 in nespremenjen izvor
`eb72dc817378453b27f4cdf0c7d7a5146a05629535eb9863763955addce947c0`.
Sedem prej uspešnih podkorakov ostane pri enem poskusu; priprava računa,
prostora, deljenja ter izguba odgovora in obnova se ne ponovijo.
`paired_conflict` je PASS v poskusu 2, `explicit_financial_review` PASS
v prvem poskusu. Stari `errorType`/stack v trajnem zapisu konflikta sta
zgodovinska podatka prve napake, ne nova napaka drugega zagona.

Običajna razrešitev opravila z lokalno različico se pravilno zavrne z
`requires_finance_resolution`. Nato pravi `resolveFinanceConflict` in
navadni `syncNow` obeh odjemalcev potrdita isto opravilo ter isti povezani
strošek **15 €**, brez podvojitev ali odvezanega vnosa. Ob začetnem stanju
100 € je končni saldo **85 €**. Kanonična vsebina, revizije in dokazi se
ujemajo, obe vrsti ter povezovalni zapisi so prazni in zaključni sync nima
napake ali nerešenega dela. HTTP 429 ni bilo; to ni meritev hitrosti,
ker test namerno omejuje pogostost zahtevkov.

Primerjava pred/po ohrani vse stare podpisane zahteve, rezervirane namere in
11 obstoječih rezervacij revizij; članova namerna razrešitev doda štiri nove
pri pričakovani reviziji 2. Prvotni sprejeti paket ni ponovno poslan. En nov
članov paket prejme 200; starih 11 strežniških zgodovinskih zapisov ostane
med sedanjimi 15. L1 podatki in njegovi dokazi ostanejo enaki. Namenski
vsebnik 59778 je znova ustavljen, njegove baze, ključi in volumes ohranjeni.
Sveža primerjava stanj/slik drugih vsebnikov ne pokaže sprememb; to ni
trditev o popolni enakosti njihove notranjosti. Glavni in neodvisni pregled
popravka, kontrol in ohranjenega L2 stanja sta PASS.

Dokazi novih kontrol:
`build/qa/local-diagnostics/paired-task-cost-conflict-20261023/`.
Dokazi nadaljevanja in primerjav ohranjenega stanja:
`build/qa/local-diagnostics/sync-resolution-cost-20261022/corrections-20261023/`.
Stari neuspešni zagon in podpisano stanje ostanejo ohranjeni. Telefonov,
produkcije in drugih testnih namestitev se ta popravek ne dotika; novih
native paketov ali namestitev ni. Zaključni uporabnikov preizkus na
telefonih ostaja ločen naslednji korak.
