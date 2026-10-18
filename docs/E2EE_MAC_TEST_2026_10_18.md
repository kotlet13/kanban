# Izolirani native macOS preizkus E2EE — 18. oktober 2026

Nadaljevalni checkpoint, ne zaključena izdaja ali neodvisni kriptografski pregled.
Osnova: `1ff5663671b43d4ae8fcbae5db6d1a4144e36384`; različica testnih aplikacij
ostaja `1.10.1+31`. Izvirna uporabnikova aplikacija, njeni podatki/ključi in
gostovanja niso cilj tega preizkusa. Nepovezana varnostni in desktop dokument
ostaneta nedotaknjena. Ta zapis ne naroča nove gradnje ali ponovitve matrike.

Lokalni dokazi so v ignoriranem
[`build/qa/jivie-mac-e2ee-test-20261018`](../build/qa/jivie-mac-e2ee-test-20261018/)
(v nadaljevanju QA); niso priloženi commitu. UI dokazi spodaj so potrjeni
checkpointi native UI agenta iz pogovora, brez posebej shranjenih posnetkov.

## Zaključni obseg potrditve

A: lokalni trezor, enrollment, račun FILE, štirje sintetični vnosi in ponovna
prijava iste namestitve z ohranjenimi ključi so PASS. B: geslo omogoči prijavo,
pričakovano pa brez računskega FILE ali odobrene naprave ne odklene povezanih
podatkov. C: sveža obnova z izvirnim računskim FILE in preveritev istih vnosov
sta PASS. Točni checkpointi in meje so spodaj.

**D podatkovna kontinuiteta in sync sta po omejenih popravkih native PASS.**
Zadnji običajni zagon je ohranil sejo brez prijave ali čarovnikov; UI je ob
12:44 lokalno pokazal Synced, 0 pending/conflicting/blocked. Povezani dogodek
20. oktobra 09:15–10:00 (`Europe/Ljubljana`) ter obe nedokončani opravili z
opombama `PRESERVE-LOCAL-D-20261018` in `PRESERVE-CLOUD-D-20261018` so ohranjeni.
Lokalno gospodinjstvo ostaja lokalno; ni novih ali podvojenih vidnih vnosov.
Prikazan je en `Legacy D Racun`, **67.89 EUR potrjeno kot otvoritveni/referenčni
znesek**. Polni saldo ostaja skrit za opozorilom o nepopolnem projektnem
finančnem pregledu; mesečno načrtovanje zahteva novejšo pogodbo. **Polni
finančni pregled ni PASS.** D je normalno zaprt;
[runner dokaz](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-cursor-fixed-d/capture-window-evidence.json)
potrdi en zagon, 0 diagnostičnih tagov, exit 0, brez ponovitve ali shranjenega
surovega konzolnega izhoda. Ni nove produkcijske namestitve ali začetka
produkcijskega retention roka. Fizični mobilni/P8 in neodvisni P0 audit
ostajajo odprti.

## Izolacija in trenutno nameščeni paketi

| Varianta | Nameščena aplikacija v `/Users/anzenovsak/Applications/` | Bundle ID | AOT SHA256, predpona |
| --- | --- | --- | --- |
| A | `Jivie Test.app` | `si.tripar.jivie.e2eetest.a20261018` | `b9aaaa03f5b25ec6` (fix + QA diagnostika) |
| B | `Jivie Test B.app` | `si.tripar.jivie.e2eetest.b20261018` | `3ce5856eeadac2e9` (fix + QA diagnostika) |
| C | `Jivie Test C.app` | `si.tripar.jivie.e2eetest.c20261018` | `214ccc830d2c7275` (fix + QA diagnostika) |

Vsaka ima svoj `~/Library/Containers/<bundleId>` in Keychain service
`<bundleId>.secure-storage`, samo svojo skupino `CXNM99632B.<bundleId>`,
Data Protection Keychain in `first_unlock_this_device`. Dejanski podpisani
entitlements potrjujejo sandbox; profil `efc2c67c-3c84-4a9e-9dc9-bd2352cc9da3`
iste ekipe velja do 10. oktobra 2027. Testni native guard pred spremembo
Documents zahteva lastni bundle in razrešeno pot lastnega vsebnika.
URL registracije `jivie`/`vsakdan` so odstranjene, Firebase auto-init/proxy sta
izključena, Google plist ni v paketih; macOS push je tudi v Dart nepodprt.

Neodvisno so preverjeni kandidati in nato nameščeni paketi z
`codesign --verify --deep --strict`, dejanskimi entitlements/profilom in
ujemajočimi izvršnimi/AOT hashi. Ob zadnjih zamenjavah B/C sta bila oba
**še nezagnana in oba vsebnika odsotna**. Zdaj sta B/C ločeno zagnana/preverjena
in zaprta; C ni prejel A/B shrambe. A je obstoječa testna namestitev;
posodobitev paketa je ohranila identiteto in shrambo, stari testni paketi so
ohranjeni v `candidate-*-startup-fix/previous-installed/`.

Točni hashi, poti in ohranjenih sedem izolacijskih datotek:
[končni manifest vseh treh](../build/qa/jivie-mac-e2ee-test-20261018/startup-fix-final-installed-apps.json),
[A lineage](../build/qa/jivie-mac-e2ee-test-20261018/candidate-a-startup-fix/source-lineage.json),
[B namestitev](../build/qa/jivie-mac-e2ee-test-20261018/candidate-b-startup-fix/installation-evidence.json),
[C namestitev](../build/qa/jivie-mac-e2ee-test-20261018/candidate-c-startup-fix/installation-evidence.json).
To je manifest običajnih startup popravkov. Poznejši A je dobil začasni QA UI
log kode napake, nato spodnji popravek revizije; zadnji nameščeni AOT je
`b9aaaa03f5b25ec659888b3421772b7084f3d5ff329d5282b3f118607c3d5918`,
[zadnja A namestitev](../build/qa/jivie-mac-e2ee-test-20261018/candidate-a-finance-revision-fix/installation-evidence.json).
QA UI log ni del glavnega izvora. Isto popravljeno izvorno stanje je nameščeno
tudi v [B](../build/qa/jivie-mac-e2ee-test-20261018/candidate-b-finance-revision-fix/installation-evidence.json)
in [C](../build/qa/jivie-mac-e2ee-test-20261018/candidate-c-finance-revision-fix/installation-evidence.json);
B password-only in C sveži FILE obnovitveni UI izid sta potrjena spodaj.
Prvi A zagon ima [metadata dokaz poti](../build/qa/jivie-mac-e2ee-test-20261018/launch-a.json).
Poznejši neobvezni terminalski pregled A journala/headerja je macOS zavrnil;
ne trdimo, da je reviewer neodvisno prebral fazo trezorja ali DB header.

## Točen izvorni overlay in ozka preverjanja

Vsi trije nameščeni paketi vsebujejo iste tri pregledane popravke na osnovi
`1ff5663`; sedem lastnih izolacijskih datotek vsake variante ostaja enakih.
To niso nove javne aplikacijske izdaje.

| Runtime datoteka | SHA256 pregledanega overlaya |
| --- | --- |
| `lib/organizer/data/collaboration_repository.dart` | `f4106675da1beeb465fead89bf216c437e2b40fb69c0f4736ca08efe12df9fa3` |
| `lib/organizer/data/collaboration_account_actions.dart` | `5f3f9f00bcdff7517811a4a96be74c4925f555c353cf198f60f0dc8bafc86d63` |
| `lib/organizer/data/e2ee/account_crypto_v2_workflow.dart` | `240dbdf14e2f38baf08e7c3bef947947e4fa002b405c9e76c26edcbd4942b1f2` |
| `server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php` | `5c9182bf61c94b0227c264f511aee01f4e21fc1014917e26965c02de03e3e0ea` |

Dart: prvi account wizard je prej zaradi cached-false capabilities ostal
skrit do ponovnega zagona; preverjanje lokalne ponovne odobritve je na sveži
napravi klicalo directory refresh pred preverjenim sidrom. Odstranjena je
zastarela zastavica, ostanejo sveže capabilities, serverId/epoch preverjanja;
manjkajoče/nepreverjeno sidro vrne false pred refresh, obstoječi poznejši
guard in celotni verifier ostaneta. [Diff/manifest](../build/qa/jivie-mac-e2ee-test-20261018/startup-fix-main-manifest.json).
[Pred popravkom](../build/qa/jivie-mac-e2ee-test-20261018/startup-regression-before.log)
sta obe ciljni regresiji padli. Končnih
[7 novih testov PASS](../build/qa/jivie-mac-e2ee-test-20261018/startup-regression-after-affected.log);
19 obstoječih wizard/directory testov je PASS v prejšnjem kombiniranem teku,
ki je imel tudi eno nato popravljeno blokado nove testne makete.
**Ni novega zelenega kombiniranega teka 26 testov ali celotne matrike.**
[Ciljna analiza](../build/qa/jivie-mac-e2ee-test-20261018/startup-fix-analysis.log):
0 error/0 warning, tri obstoječa info, brez novih.

PHP: native-origin scope je imel aktivirano glavo, surovi scope pa `staged`;
katalog je zato odjemalca poslal v napačno legacy obnovo. Samo discovery
izračuna `active`, kadar je surovo stanje `staged`, migration ID strogo null,
native origin obstaja in obstoječi `current()` vrne aktivno glavo. Fenced,
retired, legacy/migracijska/nepopolna stanja se ne promovirajo. `current()`
ohrani aktivacijo, epoch/body/lifecycle/cursor kontrole; podpisi niso na novo
preverjeni pri catalog branju. Veljavnost izvora sloni na obstoječih podpisanih
write poteh in nespremenjenem odjemalčevem preverjanju glave.
[Pred-fail](../build/qa/jivie-mac-e2ee-test-20261018/server/catalog-regression-before.log),
[15 po-fix PASS](../build/qa/jivie-mac-e2ee-test-20261018/server/catalog-regression-after.log)
in [oba PHP lint PASS](../build/qa/jivie-mac-e2ee-test-20261018/server/catalog-regression-lint.log)
so ozke persisted SQLite fixtures, brez trditve polnega write-protocol testa.

### Naknadno potrjena napaka revizije payment snapshot

En zagon diagnostičnega A je razkril samo dovoljene metapodatke:
`source=repository_last_error type=CollaborationException code=finance_access_changed`,
poskus `2026-10-18T08:52:20.865344Z`; sekundarne background oznake ni bilo.
A je normalno zaprt. Strežniška začasna error instrumentacija ni zajela dogodka
in je odstranjena; catalog popravek ostaja.

Pot je običajni sync → `_syncFinance` → `fetchLinkedPayments` tudi pri praznem
payment sidecarju. Potrošnik zahteva efektivno finančno revizijo, ki jo obstoječa
preverjena policy pot sestavi iz policy revizije in access revizije glave.
Snapshot je vrnil samo surovo access revizijo glave: za novi native origin je
bilo to0 namesto1. Glavni popravek doda `context.financePolicy(scope)` in samo
vrnjeni `accessRevision` vzame iz `policy['revision']`; surove revizije v
šifriranih zapisih/witnessih in zunanja equality/generation guarda ostanejo.

Nova dodatna runtime datoteka v glavnem izvoru:
`lib/organizer/data/e2ee/crypto_business_payments.dart`, SHA256
`b2859bc2015fd95d31003ec2e1c215026f2f700035c0b5ae96e96fe70075f4bd`.
[Manifest/diff in omejitve](../build/qa/jivie-mac-e2ee-test-20261018/payment-revision-fix-manifest.json),
[ciljni test](../test/organizer/data/e2ee/crypto_payment_snapshot_revision_test.dart).
Pred popravljanjem sta dejanska mapper/snapshot pokazala0 proti1 in4 proti7;
drugi začetni neuspehi so bili vezava fixture, brez dodatnih product ugotovitev.
[Končni4 PASS](../build/qa/jivie-mac-e2ee-test-20261018/payment-revision-after.log)
potrdi native1/head0, policy3/head4, zavrnitev odvzetega dostopa in zavrnitev
spremenjene lokalne generacije brez namestitve completeness markerja.
Fixture dobavi že avtenticiran head/origin boundary; dejanski policy mapper,
snapshot in repository delivery guarda so uporabljeni, podpisni verifier ni
predmet tega testa. [Ciljna analiza2 datotek](../build/qa/jivie-mac-e2ee-test-20261018/payment-revision-analysis.log):
0 error/0 warning, eno prejšnje runtime info in eno novo testno slogovno info
(`use_super_parameters`). **A native sync ob 11:02 lokalno PASS brez napake**;
poznejša zaščitna rotacija po rebindu in saldo po njej sta zdaj prav tako
potrjena v spodnjem A checkpointu. Ni nove finančne matrike ali spremembe obsega.

## Lastni Docker in zasebne datoteke

Nov projekt `jivie-mac-e2ee-test-20261018`, serverId
`9ca170dd-9133-43b9-a0fd-5955171b75d2`, SQLite schema20; aplikacija
`http://127.0.0.1:18790`, lokalni Mailpit `http://127.0.0.1:18792`.
App/Mailpit/mail worker so v novem internem omrežju; samo namenski gateway
povezuje novi ingress in objavi ti dve loopback vrati. Ni produkcijskih mountov,
SMTP relay ali FCM/APNs ključev. [Runtime inventar](../build/qa/jivie-mac-e2ee-test-20261018/server/resources.json),
[compose](../build/qa/jivie-mac-e2ee-test-20261018/server/compose.yaml).
`server/start.sh`, `status.sh`, `stop.sh` izvajaj z izrecnim cwd v tej QA
server mapi; `stop` ohrani podatke. Brez prune, `down -v` ali novih namestitev.

Na lastnem stacku je zamenjan samo navedeni PHP model; 180 drugih zamrznjenih
datotek/config ostane enakih. Pred tem sta zasebna rollback kopija in dosledna
SQLite kopija. [Apply dokaz](../build/qa/jivie-mac-e2ee-test-20261018/server/catalog-apply-evidence.json):
actual query-only catalog vrne active/native origin/null migration, surovo
`staged`, vseh pet šifriranih vrstic in njihovi hashi ostanejo enaki; health200,
isti serverId. Ni DBUPDATE, spremembe kvot ali ponovnega zagona strežniškega vsebnika.

Zasebni testni material je pod
`/Users/anzenovsak/Library/Application Support/JivieLocalTest/20261018/`
(imeniki0700/datoteke0600), zunaj Git. Gesla/enrollment/verification kode
uporabi samo v odobrenem UI toku; ne izpisuj jih ali vsebine FILE/Keychain.
Ne ustvarjaj novega računa ali novega enrollmenta zaradi nadaljevanja testa.
Namestitveni FILE A: `Installation A Recovery/installation-A.jivie-recovery`
(150B); računski FILE: `Account Recovery/account-e2eetest.jivie-recovery`
(509B). To sta različna ključa; noben FILE ni podatkovna kopija.
Namestitveni FILE B je ločen:
`Installation B Recovery/installation-B.jivie-recovery` (izbirnik150B),
shranjen in ponovno izbran v native UI brez branja vsebine.
Jivie SMTP ju ni poslal. Sveža C FILE obnova iz oblaka je potrjena spodaj;
nova E2EE offline podatkovna obnova ostaja nepreverjena. Omejena obnova stare
D prenosne kopije je posebej dokumentirana in ne nadomešča tega merila.

## UI checkpoint in naslednji koraki

- **A potrjeno v native UI:** namestitveni FILE Save → ponovna izbira Open →
  šifriranje lokalne baze → Pulse; first-account enrollment, običajna nastavitev
  in Mailpit verifikacija sintetične `.invalid` e-pošte; računski FILE Save →
  Open → sporočilo pripravljenih računskih/napravnih ključev.
- **A ustvarjeno enkrat:** deljeni organizacijski prostor, njegov finančni račun,
  dogodek in nedokončano opravilo z opombo; štirje logični vnosi. Lokalni pregled
  ohranjene kopije je prikazal 4 druge + 1 finančni zapis z ustreznimi sintetičnimi
  oznakami/opombo; predlog ni bil sprejet in je bil preklican. To ni sveža obnova.
- Po PHP catalog popravku je A zaključil primarni Done in prišel na Pulse;
  dogodek je viden. Navadni UI sync checkpoint 10:36 lokalno ima pending/conflict/
  blocked vse0, zadnjo uspešno sinhronizacijo »Not confirmed yet« in generično
  napako dejanja/povezave; to je zgodovinski checkpoint pred popravkom revizije.
- **A po popravku:** native sync11:02 lokalno PASS brez napake. Natanko en
  logout/login iste namestitve in »Use approved keys already on this device«
  rebind brez FILE PASS. Običajni UI nato potrdi prostor Owner/Shared, termin
  dogodka ter nedokončano opravilo z isto opombo. Finance so do pregleda kazale
  samo »Preparing the complete financial overview«; to je vmesni checkpoint.
- **A pregled/rotacija PASS:** po primerjavi znanega predogleda4 Other data +
  1 Finance in nespremenjenega owner/članov je ena potrditev »Accept snapshot
  and renew protection« potrdila izhodišče/nove ključe; primarni Done vrne Pulse.
  Običajni UI nato kaže isti prostor, `E2EE Test Racun`/`123.45 EUR`, dogodek
  19. oktobra10:00–10:30 in eno nedokončano opravilo. Opomba je potrjena v
  podrobnostih po prijavi in v predogledu pred rotacijo. Zaključni sync11:10
  lokalno: **Synced**,0 pending/conflicting/blocked, brez napake. A je normalno
  zaprt. Noben FILE ni bil uvožen; to je obnova dostopa iste namestitve.
- **B password-only PASS:** lasten namestitveni FILE Save → native ponovna
  izbira → šifriranje → Pulse. Prijava v obstoječi račun z geslom uspe, prikazana
  sta račun in potrjen naslov. Računski čarovnik izrecno pove, da geslo samo ne
  obnovi vsebine; ponudi Choose saved file/Approved devices, brez gumba za
  ohranjene lokalne ključe. Običajni izbirnik ima samo Personal/Local/unsynced;
  znani E2EE prostor ni viden. Noben računski FILE/odobritev naprave/nov E2EE
  identity/podatki niso dodani. B je normalno zaprt.
- **C sveža FILE obnova PASS:** lasten150B namestitveni FILE Save → native
  ponovna izbira → šifriranje. Na svežem C je uvožen prvotni509B računski FILE,
  ustvarjen pred nastankom prostora in A rotacijo; normalni tok potrdi preklic
  prejšnjih naprav in pripravljenost ključev. Predogled4 Other data + 1 Finance
  pokaže znanega ownerja, vsa imena/opombo; ena odobrena potrditev izhodišča
  obnovi zaščito, brez spremembe članov ali dodajanja/podvajanja zapisov.
  Običajni C UI potrdi en `E2EE Test Prostor`, en `E2EE Test Racun`/`123.45 EUR`,
  dogodek19. oktobra10:00–10:30 ter eno nedokončano opravilo s točno opombo.
  Zaključni sync11:20 lokalno: **Synced**,0 pending/conflicting/blocked, brez
  napake. C je normalno zaprt; A/B po tej obnovi nista ponovno odprta. To je
  sveža obnova iz oblaka z računskim FILE, **ni offline backup restore**.
- **C varnostna pošta:** [metadata dokaz](../build/qa/jivie-mac-e2ee-test-20261018/server/security-mail-after-c-recovery-metadata-20261018.json)
  poveže `crypto.recoveryStarted`, `crypto.deviceAdded`, `crypto.recoveryCompleted`,
  vsak sent/attempts1, s tremi novimi lokalnimi Mailpit sporočili, vsako brez
  priponk. Prebrane so samo dovoljene oznake/metapodatki, brez teles ali skrivnosti.
  To je **lokalni zajem**, brez trditve zunanje e-poštne dostave.
- **Ločeno D nadaljevanje:** legacy D stara → nova E2EE nadgradnja je najprej
  pokazala spodnji regresiji; po popravkih je zgornja podatkovna kontinuiteta
  in sync PASS. Polni finančni pregled ostaja odprt. Spodaj je posebej potrjena
  omejena obnova stare D prenosne kopije; to ni nova E2EE offline obnova.
  Deljenje/preklic dostopa ostaja nepreverjen. HTTP stack
  ne potrjuje HTTPS invitation onboardinga; fizični push ni del tega preizkusa.

D priprava je ločen macOS preizkus starega commita
`3ce710551f2aaf0d0583afe6bab1ce55606bbbd3`, ne fizična Android posodobitev.
Stari FamilyHub0.15/schema19 ZIP ima SHA256
`5c14ca9a79d92cf1c5f71b681d8417f44f4bfb9b474443cdad4dbb3f589f51e7`;
Kanboard1.2.54, nov projekt `jivie-legacy-upgrade-test-d-20261018`, loopback
18794/18795 in zasebni `20261018-legacy-d`. Bundle
`si.tripar.jivie.e2eetest.d20261018` in lastna shramba/Keychain ostaneta ista
pri starem/novem D. Po spodaj navedenem izhodišču in obnovah je glavni agent
odobril nadgradnjo D strežnika na schema20 in namestitev novega D appa;
prvi novi zagon je nato potrdil lokalni prehod in spodnjo izgubo prikaza seje.
Naslednji odstavki so zgodovina odpravljanja; zaključni izid je naveden zgoraj.
Stari/novi D ne smeta uporabiti A/B/C shramb, sej ali ključev.

Stari D je po potrditvi native izhodišča normalno zaprt. UI je potrdil lokalno
gospodinjstvo `Legacy D Lokalni Prostor` in opravilo z opombo
`PRESERVE-LOCAL-D-20261018`; povezano gospodinjstvo `Legacy D Prostor`, račun
`67.89 EUR`, dogodek 20. oktobra 2026 od 09:15 do 10:00 (`Europe/Ljubljana`)
ter nedokončano opravilo z opombo `PRESERVE-CLOUD-D-20261018`.
Zaključni stari sync ob 11:43 lokalno je imel 0 pending/conflicting/blocked.
[Read-only strežniško izhodišče z natančnimi ID-ji](../build/qa/jivie-legacy-upgrade-test-d-20261018/server/old-baseline-readonly-20261018.json)
veže naslednje primerjave na to stanje, ne na nove testne vnose.

[OLD izolacijski diff](../build/qa/jivie-legacy-upgrade-test-d-20261018/isolation-old-d.patch)
SHA256 `7ed094a9b904081d5bd43a6e83908d02690f712d785fdc0fa458b3d0df237dda`
ima 10 datotek: štiri stare varne shrambe in šest native izolacijskih datotek.
[NEW kandidat](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-new-d/artifact-evidence.json),
[source lineage](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-new-d/source-lineage.json):
štirje pregledani Dart popravki + sedem D izolacijskih datotek, brez QA loga;
AOT `d072ddfe620473c20f9c8d756f4f0ca4542a8a18266ea52b869738e860a3d5b5`.
Neodvisni enkratni pregled dejanskega podpisa/profila/metapodatkov/hashov PASS,
ista D identiteta/service/skupina in guard pred Flutterjem. Po namestitvi in
prvem novem zagonu je D uspešno shranil ter ponovno izbral installation FILE
in šifriral lokalno shrambo. Lokalno gospodinjstvo in opravilo sta ostala vidna.
**Potrjena native regresija:** Account je nato pokazal prazen svež prijavni
zaslon namesto stare seje. Nove prijave ni bilo; D je bil zaprt. Lokalni prehod
je bil takrat potrjen samo v navedenem obsegu; povezani prehod je čakal popravek.
Lokalna pretvorba trezorja je končana: ohranjeni OLD D paket je zgodovinski
dokaz, ne varen samodejni rollback. Nadaljuj samo naprej s popravljenim novim
izvorom na obstoječih Data/Keychain. Starega D ne zaganjaj nad šifriranim
stanjem in stare kopije ne obnavljaj čez novejše stanje.
Stari `unlocked` je namenoma ohranjen, novi `first_unlock_this_device` pa ni
prirejen nazaj: kontinuiteta pri zaklenjenih plugin 9.2.4/macOS 3.1.3 in njihovem
lookup predikatu sta izvorna razlaga opažene izgube prikaza stare seje;
novi prijavni podatki ali nova identiteta niso nadomestili starega stanja.

Celotna kopija D sandbox `Data` ni uspela: običajen dostop je vrnil
`PermissionError` pred `ditto`; dovoljenja niso bila obita. Namesto tega je
stari app normalno izvozil šifrirano `.vsakdan` kopijo velikosti 13.128 B,
SHA256 `84ef92f8c58c9bcb044ab6879dd54b4ed87106913ab2b861e07e96f1d6fd22c9`.
[Ena dejanska izolirana obnova s starim repositoryjem](</Users/anzenovsak/Library/Application Support/JivieLocalTest/20261018-legacy-d/Portable Restore Verification/attempt-20261018T095158393745Z/restore-evidence.json>)
je PASS: dva lokalna prostora z enakimi ID-ji in vsebinami, tri povezane vrstice
ohranjene v karanteni z enakimi polnimi payload hashi, tri preference in brez
pending zapisov. Obnova ni uporabila omrežnega API-ja, D vsebnika ali Keychaina.
Glavni agent je sprejel ta ožji obseg za znani sintetični fixture; **to ni
celotna kopija sandboxa ali Keychaina**.

[Dejanska strežniška obnova](</Users/anzenovsak/Library/Application Support/JivieLocalTest/20261018-legacy-d-backups/20261018T094924Z/restore-proof.json>)
iz ločene celotne kopije je PASS v `network=none`: schema19, 98 tabel, 74 vrstic,
brez FK kršitev, isti row/DDL in DATA/config/private/plugin hashi. Po napaki URI
pri odpiranju kopiranega SQLite je sledila ena popravljena ponovitev; prva delna
kopija `20261018T094819Z` ostaja ohranjena. Host je odprl samo običajno zasebno
kopirano datoteko in takoj nastavil `PRAGMA query_only`, ne izvirne baze;
ta del ni trditev OS read-only načina.

Priprava je razkrila preširok zasebni bind v A/B/C strežniku. Zamenjava samo
tega mounta z `secrets.php` je
[potrjena](../build/qa/jivie-mac-e2ee-test-20261018/server/upgrade-preparation/mount-tightening-evidence.json):
isti serverId, config, volumes ter vseh pet ID-jev in celotnih šifriranih row
hashov. Tudi D cilj uporablja ožji mount. To dokazuje omejitev dostopa po
popravku; ne trdi, da prej ni bilo dostopa do datotek odjemalca.

Ozek pregled izvora pred tem testom je potrdil razliko med Apple pluginoma:
macOS 3.1.3 v read/contains/update query vključi zahtevano accessibility, zato
sedanji `protectExistingLocalVaultSecrets()` stari neujemajoči zapis lahko
preskoči kot `null`. iOS 9.2.4 bere brez tega predikata, njegov write pa po
neuspešnem update uporabi delete/add. iOS native izid ni preverjen.
Pregledani izvorni popravek je namenski Apple `SecItemUpdate` samo za
pet obstoječih imen: ista service/skupina/vrednost, brez delete/add,
preverjena ciljna accessibility in identična vrednost, napake blokirajo
bootstrap. Prehod mora biti ponovljiv tudi po delni izvedbi in pred odprtjem
običajnega appa; Android ostane nespremenjen. Sam popravek klica pri
`local_vault_native.dart:611` ne zajame že končanega journala, ki se vrne pri
vrstici 518. Neodvisni pregled migracijskega diff-a ni našel produkcijskega
zadržka. Glavni pregled je nato potrdil ločeno Retry napako: po kliku je
factory ostal na enem klicu zaradi cached provider `AsyncError`. Minimalni
popravek v `_inspect()` invalidira samo errored provider. Končni ozki widget
test zdaj preveri fail → klik Retry → drugi factory, child še zaprt → uspešna
zaščita complete-journal servisa → child odprt; oba pregleda tega dela sta PASS.
Ena popravljena D gradnja je končana; njen neodvisni pregled spodaj je PASS.
Po namestitvi je sledilo spodaj opisano native nadaljevanje. Opažanje
regresije samo ne dokazuje, da je stari Keychain item izbrisan ali da je
predlagani popravek že uspešen; surove vrednosti Keychaina niso bile prebrane.

Skupni [Apple helper](../apple/JivieLegacySecrets.swift) ima SHA256
`cc880c7c371ad9dea2b1ce48c0a00cd6a82879b146ee1650de3af6c50482e154`.
Discovery nima accessibility predikata; posodobitev se veže na isti
account/service/dejansko skupino in persistent reference ter spreminja samo
accessibility. Ponovno branje zahteva iste bytes in reference. Oba native
handlerja in oba Xcode projekta vključujeta isti helper; Apple bootstrap ga
izvede pod installation lease pred vrnitvijo service tudi ob `complete`+journalu. Android obdrži dosedanjo pot in `resetOnError: false`.

[Native dokaz](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/native-proof-evidence.json)
navaja 10 ozkih fake primerov PASS ter dejanski podpisani/sandboxed macOS
prehod petih sintetičnih `unlocked` zapisov v ločeni proof skupini: isti bytes
in persistent references, pet update, ponovitev brez novih update, brez
produkcijskega add/delete. Prvotni readback query s hkratnim persistent-ref
filtrom in return flagom je macOS zavrnil z `-50`; končna različica ponovno
poišče enolično natančno identiteto in preveri prvotni ref. iOS helper typecheck
je PASS; **iOS native runtime ni bil izveden**. D Keychain ni bil cilj proofa.
[Končnih 9 ozkih Flutter PASS](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/flutter-focused-tests.log)
zajema Apple kanal/Android pot ter complete-journal lease in dejanski
fail → Retry → success bootstrap.
[Pred-fix Retry fail](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/flutter-retry-before-fix.log),
[ciljna analiza](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/flutter-targeted-analysis.log)
(0 error, 0 warning, 3 obstoječi info) ter
[končni povzetek](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/focused-verification-summary.json)
so vezani na
[manifest pregledanega izvora](../build/qa/jivie-legacy-upgrade-test-d-20261018/keychain-native-proof/reviewed-main-source-manifest.json).
Reviewer je preveril vseh 11 source/test hashov ter oba log hasha brez
neskladij, testov ni ponavljal. Bootstrap SHA256 je
`ef42fbb89756809c846d51f7ae97249d3099f3707a5c4630543be6ff7281d72b`.
To ni celotna matrika ali samostojen dokaz native obnove seje; njen poznejši
dejanski PASS je opisan spodaj in v zaključnem obsegu potrditve.

[Popravljeni D kandidat](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-fixed-d/artifact-evidence.json)
in [izvorna vezava](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-fixed-d/source-lineage.json)
sta pregledana PASS: dejanski strict/deep podpis, isti D bundle ID, service,
edina D Keychain skupina, sandbox, isti veljavni profil in resolved Documents
guard pred Flutterjem. Vseh 16 spremenjenih source hashov se ujema; oba nova
handlerja in obe Xcode povezavi na pregledani shared helper sta prisotna.
[Samo sedem izolacijskih poti](../build/qa/jivie-legacy-upgrade-test-d-20261018/fixed-d-isolation-only.patch)
ima SHA256 `e20e1ac0166fe523a5eaafd30c6f8686de87eae94d45d4b30412bc7a263c5be1`.
Dejanski kandidat ima AOT
`98e76e55a0f397077d44e85c7b0adaa2ff2e2cdc3b310aae3925bae08ae317ba`
in izvršno datoteko
`c6a4157a35e05d891a54fb2499208546437af9a306cac4c2af37ca37f385f72e`.
Ni QA diagnostike, URL registracij ali Firebase auto-init. Ob samem pregledu
kandidat še ni bil nameščen ali zagnan; po PASS je izvajalec izvedel odobreno
zamenjavo samo D paketa. Reviewer ni odpiral D Data/Keychain.

Popravljeni D je ob enem običajnem zagonu sam odprl account čarovnik
»Add a recovery key« / »This account only« z obstoječim potrjenim naslovom
`e2ee-legacy-d@jivie.invalid`. **Kontinuiteta stare seje je native PASS**:
brez nove prijave, gesla, nove identitete ali ponovne installation migracije.
Sledila sta računski FILE in committed legacy migracija. En omejen strežniški
metadata pregled je potrdil vse tri stare poslovne preslikave kot active z
origin/history, iste identitete in stare row hashe, brez pending commit.
Število 13 zajema metadata in tri poslovne vnose; ni dokaz izgube starih vnosov.

**Zgodovinski D blocker pred cursor popravkom:** običajni samodejni sync je
pokazal generični `invalid_response`, ob 0 pending/conflicting/blocked.
Izvorna izjema ni bila zajeta iz native stacka; D je bil zaprt. Predlagana
[zasebna QA diagnostika](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/private-qa-overlay.patch)
in [strogi capture runner](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/capture_d_post_migration_diagnostics.py)
sta neodvisno pregledana PASS, še brez nove diagnostične gradnje ali zagona ob
tem checkpointu. Sprememba je samo v eni QA source datoteki: prvotno 24 statičnih faz,
finite type/code ter regex-only source basename/line/column; brez exception
message ali raw stack izhoda. Runner sprejme samo polni dovoljeni tag, ostale
stdout/stderr bytes zavrže v pomnilniku, shrani 0600 log in zaključi zajem po
prvem tagu ali 60 s, brez avtomatske ponovitve. Končni odobreni tok po 60 s
brez taga ohrani isti proces za omejen UI pregled, nato sledi normalni CmdQ;
zajem se ne podaljša. Zagon sta tedaj blokirala nepripeta candidate hasha.
Diagnostična
gradnja je bila nato zadržana: izvajalec je pred gradnjo našel neskladje med
ohranjenim finančnim cursorjem/revizijo 1/2 in raw head revizijo 0 v business
pull odgovoru. Spodnji ozek repro je to pot potrdil. Ločena diagnostic-only
gradnja ni bila izvedena; poznejši odobreni kandidat združuje produkcijski
popravek in pregledano rezervno QA diagnostiko, z dodatno statično fazo
`cursor_transition` (skupaj 25 faz) ter isto runner allowlist vrednostjo.

Neodvisni ozek pregled je našel še povezano izvorno vrzel pri cursor domeni:
`_upsertScope` ohrani ordinary `scopes.cursor` in `finance_cursor`, business
pull pa filtrira po novi `crypto_received.sequence > caller cursor` in ob
praznem izidu vrne isti cursor. Crypto checkpoint/population poti ne resetirajo
ordinary cursorjev; finance reset samo ob spremenjeni policy reviziji ne
pokrije stare 2 → nove 2. Zato lahko stari cursor preskoči že verificirane
crypto projekcije v ordinary tabelah. To je potrjeno iz izvora, **ne dokazana
izguba podatkov ali iz native stacka dokazan vzrok takratne D izjeme**.
Pregledani popravek doda idempotenten prehod pred ordinary cursor read po
preverjenem current headu, descriptorju in migration genesis. Null origin ne
zapiše markerja; verificiran native origin zapiše markerja brez ponastavitve.
Pri migriranem scopeu ista repo transakcija pod epoch/lease ponastavi oba
ordinary cursorja ter finance access/completeness in zapiše dva
partition/scope/domain/v1 markerja. Ponovitev markerjev ne resetira znova;
zapisi, immutable pending zahteve in konflikti niso izbrisani. Finance pull
vrne verified business policy revizijo, raw crypto revision/CAS/proofs in
obstoječi mismatch guard ostanejo nespremenjeni.

[Pred-fix repro](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/finance-cursor-prefailure.log)
dejanskega runtime pulla in repository guarda vrne `invalid_response`.
[Končnih 8 ozkih PASS](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/cursor-transition-focused.log)
zajema tudi pravi SQLite fault pri drugem markerju (oba reseta/markerja
rollback, po odstranitvi faulta retry PASS) ter prekinitev po checkpointu
(complete ostane false, retry brez novega reseta obnovi projekciji).
[Analiza](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/cursor-transition-analysis.log)
ima »No issues found«.
[Vezani manifest](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/cursor-transition-verification.json)
in [source diff](../build/qa/jivie-legacy-upgrade-test-d-20261018/proposal-post-migration-diagnostics/cursor-transition-source.patch)
sta neodvisno pregledana PASS; štirje source/test hashi ter vsi navedeni
patch/log hashi se ujemajo. Fixture poda že authenticated head/origin mejo;
preverja actual runtime/repository/SQLite, ne novega signature verifierja ali
native D izida. Poznejši običajni D UI in sync sta s spodnjim combined
kandidatom dosegla zgornji omejeni PASS.

[Combined D kandidat](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-cursor-fixed-d/artifact-evidence.json)
in [source lineage](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-cursor-fixed-d/source-lineage.json)
imata neodvisni omejeni pregled PASS: isti podpisani D ID/skupina/service,
sandbox/profil/guards in vseh sedem nespremenjenih izolacijskih hashov.
Kandidat ima skupaj 19 spremenjenih poti; zunaj sedmih izolacijskih poti
ustreza pregledanemu main izvoru z natančno apliciranim QA patchom. QA
dopolnitev je preverjena v pomnilniku,
ohrani novi cursor hook in doda samo pregledane diagnostične faze, vključno
s `cursor_transition`. QA patch SHA256 je
`c6eddab32bfb50ecef0309e0848b12fadf924c801334773f5b32e6f544c0a5f6`;
generirani build config ima `JIVIE_TEST_SYNC_STAGE_DIAGNOSTICS=true`.
Dejanski AOT je
`0ffbdfe8e3b886edc7ba01c3ad9a81ab1fbe31ab261c37274b4528a467327178`,
izvršna datoteka pa
`b7ef483881c6ff97065934aebd11e4ab91198280a330d17572a970b941c11f55`.
Ob pregledu je bil pogoj za package-only namestitev izpolnjen, namestitve ali
zagona pa še ni bilo. Poznejša
[namestitev](../build/qa/jivie-legacy-upgrade-test-d-20261018/candidate-cursor-fixed-d/installation-evidence.json)
in zgornji en zagon sta nadaljevala isto stanje. Runner je vezan samo na ta pregledana hasha;
njegov pregledani allowlist zdaj vključuje še `cursor_transition`.

Ozek source pregled finančne omejitve: migracija pri captured `scopeMetadata`
uporabi `CryptoMigrationScopeBaseline.load`, ki za household in organization
doda `financeTopology`; `withScopeBaseline` jo ohrani, verifier pa jo zahteva
in validira (`crypto_migration_canonical_stage.dart:63`,
`crypto_migration_scope_baseline.dart:98`, `crypto_migration_record_source.dart:434`).
Ni izvorne podlage za trditev, da migrirani household topology sploh ne izdaja.
`organizationFinanceCoverage` poleg nje zahteva preverjene popolne finančne
inventories/checkpoints ustreznih otrok ter root observed completeness
(`crypto_business_router.dart:2615`). Ob manjkajoči potrditvi vrne incomplete;
policy mapper začne s false, UI pa nepopoln saldo skrije. To razvrsti opozorilo
kot odprto mejo celotne coverage/projekcije; natančna preostala veja ni bila
native diagnosticirana. Ni dokaz izgube otvoritvenega zneska in ni trditve
zaključenih polnih financ. Novih finančnih testnih krogov nismo odprli.

Pri nadaljevanju primerjaj iste sintetične vrednosti, brez novih vnosov:

| Vnos | Pričakovana vrednost |
| --- | --- |
| Prostor | `E2EE Test Prostor`, organizacija, Owner/Shared |
| Finančni račun | `E2EE Test Racun`, začetno stanje `123.45 EUR` |
| Dogodek | `E2EE Test Dogodek`, 19. oktober 2026, 10:00–10:30, `Europe/Ljubljana` |
| Opravilo | `E2EE Test Opravilo`, nedokončano; opomba `PREIZKUS-E2EE-20261018-A` |

Same-install logout/login lahko uporabi eksplicitno lokalno odobritev z
ohranjenimi ključi (`crypto2.device.rebind`); to ni dokaz obnove samo z geslom.
Rebind spremeni naprave v računskem imeniku; scope head še veže prejšnji
device snapshot, zato so ohranjeni podatki berljivi, novi zapisi pa zahtevajo
pregled/rotacijo (`account_protection_ready.dart:350`, `session_crypto_access.dart:5688`).
Finančni UI pri `financeSnapshotComplete != true` namenoma skrije pregled
(`shared_finance_workspace.dart:211`, `collaboration_repository.dart:739`);
zelena ikona oblaka sama ne potrjuje popolnosti finančne projekcije.
[Po rebindu istih5 ID-jev in celotnih row hashov](../build/qa/jivie-mac-e2ee-test-20261018/server/native-records-after-rebind-readonly-20261018.json)
se ujemajo z obema znanima prejšnjima kopijama. Ob potrjenih običajnih treh
UI vnosih to dovoljuje normalen pregled znanega sintetičnega izhodišča:
Review protection → predogled4 Other data/1 Finance z vsemi pričakovanimi
imeni/opombo, isti owner/člani, brez manjkajočega/neuspešnega zapisa → izrecna
potrditev in obnovitev zaščite. Salda ne zahtevaj pred nujno rotacijo; **račun in
123.45 EUR preveri po njej v običajnem UI**. Ob odstopanju predloga ne sprejmi.
C je bil pred obnovo svež in ločen od A/B. Zgornji zaključni A/B/C UI
checkpointi so potrjeni PASS; ta opis varnega predogleda je razlaga že
opravljenega toka, ne preostali A/B/C korak.

## Omejitve dokazov

UI je prej prikazal »Too many attempts«; ohranjeno zadnje crypto2 okno je imelo
363/600 zahtev (08:20:17–08:21:17 UTC), ob pregledu08:22:20 že poteklo.
Točne zgodovinske 429 poti ni v ohranjenih logih; kvote niso spremenjene in
uspešen metadata pregled ni dokaz uspešnega synca. [Read-only dokaz](../build/qa/jivie-mac-e2ee-test-20261018/server/native-records-readonly-20261018.json)
ima pet šifriranih vrstic, 0 legacy vrstic in 0 zadetkov petih točnih sintetičnih
markerjev v pregledanih celicah. Ni dešifriranje ali dokaz preslikave vseh štirih
logičnih vnosov. Catalog popravek sam ni dokaz obnove.
Poznejši omejeni client log je določil zgoraj opisano napako revizije;
ni dokaz uspešnega synca, ponovne prijave ali obnove.

Finance so prikazale opozorili o potrebni novejši strežniški finance pogodbi za
mesečno načrtovanje in nepopolnem projektnem pregledu do sinhronizacije vseh
dovoljenih projektov. V A/C je potrjen navedeni sintetični prikaz 123.45 EUR;
v D samo otvoritveni/referenčni znesek 67.89 EUR. Polnega D salda, drugih
saldov, obdobij in celotnih financ nismo validirali. Menjava/reset gesla,
nova E2EE offline podatkovna obnova, fizične naprave in deljenje še niso preizkušeni;
zgornja omejena stara D prenosna obnova je ločen dokaz. Predhodni
ENOSPC/build-cwd zapleti imajo ločene QA dnevnike; po popravku so bili A/B/C
grajeni posamično z izrecnim cwd in preverjenimi kandidati. Ne ponavljaj gradenj
zaradi teh zgodovinskih neuspehov. Ni javne oddaje, gostovanja ali P8 zaključka.
