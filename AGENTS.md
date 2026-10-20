# Navodila za delo na projektu

20. oktober — **čiščenje prostora po izrecnem naročilu uporabnika**.
Odstranjenih 284 regenerabilnih map prevajanja iz repozitorijevih
`build`/`.dart_tool` in zasebnih `share-20261019/source-a,b`: Xcode
intermediates/module/index caches, Dart flutter_build/hooks_runner in
Gradle intermediates. Prosti prostor približno30→75GiB; manifest je
`build/qa/cleanup-20261020/cache-cleanup-manifest.json`. Izvorne kopije,
končni paketi/arhivi, dnevniki, podatki, FILE/ključi in Docker volumes
ostanejo; APK56fbc372…/IPAa08bfa24… SHA256 po čiščenju ista. iPhone
težave nismo nadaljevali. Manjkajoči build cache se obnovi ob naslednji
gradnji; ne obnavljaj ga samo zaradi starega dokaznega manifesta.
**Za nadaljnje delo:** ponovno uporabi obstoječi QA source/build imenik.
Novo polno kopijo naredi samo za potrebno vzporedno ali baseline primerjavo.
Po preverjeni predaji paketa odstrani odvečne vmesne rezultate; ohrani
potrebne končne pakete, majhen izvorni diff/manifest in dokaze. Zaradi
čiščenja ne ustvarjaj novih kopij build cachev in ne ponavljaj PASS testov.

20. oktober — **obe testni aplikaciji nameščeni; mobilna odobritev prostora in projekta potrjena**.
[Aktualna skupna seja](docs/E2EE_MOBILE_SESSION_2026_10_20.md):
isti Sol6.1/high podagenti in glavni/neodvisni pregled. Android prvi QA APK
ni vseboval GeneratedPluginRegistrant; originalna VM izjema channel-error
PathProviderApi je potrjena. Generator ob istem SDK/lockih in nov APK56fbc372…
odpravita pakirno napako v drugem poskusu; isti podpis/storage, štiri vault
datoteke pred/po enake, bootstrap ready in uporabnikov običajni zaslon PASS.
S25 je imel Wi-Fi izklopljen; po uporabnikovi povezavi samodejni sync PASS,
vrste0/0/0 in lastError null. iOS ista IPA51a42425…/shramba; stari QA
diagnostični mapi povzročita znano opozorilo, fizični Continue ohrani prijavo.
En dejansko dostavljen owner Confirm aktivira parent in child epoch2;
isti prvotni sprejem je consumed, B ima članstvo in ključe. NE PONAVLJAJ
Confirm/accept/povabila. CUA prikaza uporabljaj v glavnih oknih Android
Studia/Device Huba, ne v ločenih kompaktnih oknih z nezanesljivim klikom.
iOS prvo nadaljevanje po odobritvi FAIL s splošno napako; diagnostični
drugi in tretji poskus zajameta preview_resume_accepted /
CryptoAuthorityPending / directory_proof_pending. Po tretjem STOP/SKIP,
brez četrtega Retry, novega povabila ali novega kroga diagnostike.
Ozek izvorni popravek prenese obstoječi online parameter v preverjanje
sidra povabila; offline/frozen in varovala ostanejo ista. Štiri nove
kontrole PASS v tretjem izvornem teku (prvi fixture FAIL, drugi stara koda
z isto pending napako); pozitivna kontrola doseže headGet, ni celotni
resume. Glavni/neodvisni pregled PASS, analiza0error/0warning/65starihinfo.
Končna iOS IPAa08bfa24… vsebuje ta popravek in spodnji callback popravek;
ista QA shramba/podpis/TLS, štiri vault datoteke pred/po namestitvi enake.
Kljub temu native nadaljevanje ostane FAIL, točno notranje mesto napake
še ni dokazano. Dvosmerno urejanje/offline/finančna meja/odvzem so BLOCKED
za B-jevim še nepotrjenim branjem. Ločena debug napaka setState callback returned
Future po vrnitvi iz odobritve je popravljena v izvoru; en ciljni widget PASS
v tretjem poskusu po fixture popravkih, analiza brez error/warning in
glavni/neodvisni pregled PASS. Android ostaja na APK56fbc372… brez poznejših
izvornih popravkov; uspešnega granta nismo ponovili. Produkcija/trgovinski aplikaciji/Mac18811/benchmark59776
nedotaknjeni, aktivni QA podatki ohranjeni. Mobile/P0/P8/N7 ostajajo odprti.
Spodnje navedbe »brez namestitve« opisujejo prejšnjo pripravo.

20. oktober — **iOS podpisovanje popravljeno po novem izrecnem naročilu; oba paketa pripravljena**.
[Aktualno nadaljevanje](docs/E2EE_MOBILE_READINESS_2026_10_20.md):
isti Sol6.1/high podagent in neodvisni/glavni pregled. Odstranjeni podvojeni
Runner ključi; prvi novi arhiv pokaže nezdružljivost Manual z Xcode-managed
profilom. Končno single Automatic/Apple Development samo Runner, brez
globalnega profila/certifikata ali provisioning/device flags. Učinkovite
nastavitve 3 Runner/43 odvisnosti pregledane pred arhivom. Drugi novi arhiv
PASS, isti že lokalni profil/certifikat in QA ID/service/Keychain. IPA51a42425…
16.460.353 B, strictdeep/profile/entitlements PASS. sqlite3mc unsigned isti;
sodium vseh14 code/data sekcij in exports isti, razlikuje se LC_UUID16B in
podpis; ne trdimo wholebyte parity. Stari3FAIL in novi prviFAIL ohranjeni.
SDK/locks/glavni izvor cf97e2d isti, Android/server v tem nadaljevanju isti.
Ni naprav/namestitev/zagonov/scenarijev/konzole; čakamo uporabnikovo vrnitev.
Spodnji iOS BLOCKED je zgodovina, ne trenutno stanje. CA še vedno velja do
21.10.2026 12:25:42UTC; ne podaljšujemo zaupanja. P0/mobile/P8/N7 odprti.

20. oktober — **priprava telefonov delno zaključena; iOS BLOCKED po treh gradnjah**.
[Priprava in nadaljevanje](docs/E2EE_MOBILE_READINESS_2026_10_20.md):
uporabnik naroči pripravo, skupni testi šele po vrnitvi domov. Sol6.1/high
podagenti, glavni pregled. Izvor cf97e2d zamrznjen (1560 vhodov,
7756cdb9…); main runtime/SDK/locks isti. Android APK 7fef105a… pripravljen,
isti QA ID/podpis/storage, vseh 7 native knjižnic enakih, brez namestitve.
Isti mobilni Docker18801 posodobljen: 182 source datotek, shema20,
vseh220 tabel vrstično istih in499 SQLite objektov istih. Zasebna kopija212
datotek preverjena; app/gateway/Mailpit tečejo, worker namenoma ustavljen.
CA velja do21.10.2026 12:25:42UTC. iOS ni ustvaril novega paketa: globalni
profil, nato globalni podpisnik, nato podvojeni Runner CODE_SIGN_STYLE
Manual/Automatic; napake naše QA priprave, ne app/Apple račun. Po3poskusih
STOP, brez četrtega teka; predlog popravka samo shranjen, ni uporabljen.
Diagnostika pripravljena, dejanski priklop konzol še NEPREVERJEN. Nobenih
telefonskih ukazov, namestitev, zagonov ali poslovnih scenarijev; isti
računi/FILE/sprejeto povabilo/pending owner grant se ohranijo. Produkcija,
Mac18811/benchmark59776/trgovini nedotaknjeni. P0/mobile/P8/N7 odprti.

20. oktober — **skupna dokazila pravic med finančnim branjem zaključena**.
[Izvedba in dokazi](docs/E2EE_FINANCE_AUTHORITY_REUSE.md): GPT-6.1 Sol/high
podagenti, glavni in neodvisni pregled PASS. Isti operation/snapshot/prvotna
5s ura znotraj obstoječega per-scope finance konteksta; napaka, mutacija,
fresh boundary, sočasnost, lifecycle/identity/pin/generation umaknejo uporabo.
Pin union razveljavi tudi stare podlage; prazni task reconciliation brez
nepotrebne sveže meje, neprazni ohrani notranji guard in fresh boundary.
15 novih kontrol PASS (10 prvi poskus, 5 signed drugi po HTTP stub fixture
popravku); en prizadeti no-op primer PASS drugi poskus po fixture popravku.
Končna scoped analiza 0 error/0 warning/66 starih info. Primerjava 5cca8bb
in nove kode obe prvi PASS: 54→47 HTTP, 13→6 snapshotov, 683.951→383.867 B
odgovorov (−43,88 %), povprečje 1,015→0,859 s le dva loopback vzorca.
Inventory +2.380 B zaradi checkpointa ločeno; 3 finance/62 starih podpisanih
zahtevkov točno ohranjeni, saldo 33,33/strošek 12,34, vrste/napake/429 nič.
Originalni klient in 55 predhodnih dokazov isti; Docker59776 spet ustavljen.
Brez starih PASS/native ponovitev, produkcija/stare QA/SDK/locks isti.
P0/mobile/P8/N7 ostajajo odprti; ni nove namestitve ali trditve pripravljenosti.

20. oktober — **capability poizvedbe združene znotraj enega synca** po
naročilu naslednjega cilja; GPT-6.1 Sol/high podagenti/glavni pregled.
[Izvedba in dokazi](docs/E2EE_SYNC_CAPABILITY_DISCOVERY.md): točen
transport/seja/epoch/current, ločena anonymous/bearer odgovora, svež kontekst
vsakega syncNow tudi nested, finallyclose, failure/mismatch brez retencije,
globoke kopije. _negotiate/accountCryptoPreview/directorycap povezani;
authority/podpisi/5s/freshboundary/urnik/server/kvote nedotaknjeni.
21novihPASSposkus1, scoped0error/0warning/1oldinfo, neodvisni/glavniPASS.
HTTP2af5fb4→nova:69→54HTTP(−21,74%),cap17→2,snapshot13→13,
717.179→681.575Bodgovorov,čas1,058→1,015s(le2lokalnavzorca,brez
trditve zanesljivega pospeška). Inventory+2.376B zaradi napredovanja
checkpointa med vejama dokumentirano. Obe veji prviPASS/6ciklov200,
0napak/429/vrst,3finance/62predhodnihsigned točno isti. Izvirni klient
in stare meritve nedotaknjeni; novi capability-comparison kopiji ločeni.
Docker59776 spet ustavljen; prod/stareQA/native/SDK/locks isti.
P0/mobile/P8/N7 odprti; nobenega novega poslovnega urejanja ali starihPASS.

20. oktober — **prenos preverjenega lastnega imenika zmanjšan** po naročilu
naslednje optimizacije; trije GPT-6.1 Sol/high, glavni/neodvisni pregled.
[Izvedba in meje](docs/E2EE_AUTHORITY_DIRECTORY_TRANSFER.md):33vrstic/2datoteki,
obstoječi directoryAfterGenerations samo za lasten rekonstruiran prefix ob
točnem ujemanju varnega sidra; cold/mismatch brez namiga, zgodovinski
after0 pade na izvirno podpisano branje. Brez sharedauthority/TTL/urnika/
kvote/Firebase/server/schema sprememb.12novih guardPASSposkus1,2podpisana
fallbackPASSposkus2(prvi samo fixturepinFAIL), scoped0error/0warning/1oldinfo.
HTTP609cc52→nova koda na enakih ločenih postedit kopijah:69→69HTTP,
1.363.662→714.801B odgovorov(−47,58%), zahtevki+936B. Čas1,093→1,084s
je šum, pomemben pospešek ni dokazan. Authority13/capability17 ostaneta.
Strežniški checkpoint med vejama napreduje(+2.374B inventory), dokumentirano.
Obe veji prviPASS,6ciklov200/0error429,3finance/62predhodnihsigned točno
ohranjeni, saldo33,33/strošek12,34,vrste0/0/0. Originalni klient isti;
Docker59776 spet ustavljen. Prod/stareQA/native/SDK/locks nedotaknjeni.
P0/mobile/P8/N7 ostajajo odprti; ni ponavljanja starihPASS ali novega urejanja.

20. oktober — **namenska meritev hitrosti sinhronizacije PASS**.
[Rezultati in meje](docs/E2EE_SYNC_SPEED_2026_10_20.md): isti zasebni
Docker59776/odjemalec, trenutna73fd3d6, brez produkcijskih sprememb.
Začetni cikel1,976s/99HTTP; trije brez novih vnosov1,100/1,052/1,053s,
vsak69HTTP/1.316.134B odgovorov; en title-only edit1,935s/137HTTP,
pending1→0,0napak/429, isti saldo/vnosi/53starih podpisanih zahtevkov.
Authority snapshot13klicev/89,4%prejetih teles v običajnem ciklu; capability17.
To je loopback majhen nabor, ne mobile/internet ali dokaz odstotka pospešitve.
Prvi HTTPtekPASS, pred njim popravljena statična napaka novega ogrodja;
uspešni scenariji niso ponovljeni. Docker spet ustavljen, izvirnik enega
spremenjenega testnega naslova zasebno ohranjen. Naslednje optimizacije samo
predlog; produkcija/stareQA/native/SDK/locks/urnik/Firebase nedotaknjeni.

20. oktober — **samodejna obnova zastarele izbire računov popravljena** po
novem izrecnem naročilu; dva GPT-6.1 Sol/high, glavni/neodvisni pregled.
[Izvedba in dokazi](docs/E2EE_ACCOUNT_CHOICES_STALE_RECOVERY.md): `ensure`
obravnava isti dovoljeni stale tudi po materializeAvailable; ordinary-only
`forOffer` discovery preskoči obstoječe4stale kode pred materializacijo.
Capture3/kandidati/podpisi/pini/pravice/ročne odobritve ohranijo stroge
zavrnitve; ista2poskusa, brez spreminjanja starih podpisanih zahtevkov.
9novih ensurePASS(poskus3: fixtureFAIL, stari praviFAIL, popravljeniPASS),
3dodatni discoveryPASS(poskus1); stari uspešni testi niso ponovljeni.
HTTPstariFAIL potrjen(poskus2, prvi samo compilefixtureFAIL); popravljeni
prviFAIL razkrije forOffer mejo, drugiPASS na ISTEM stanju brez čarovnika.
Nov zero-opening račun v istemparentu,2choices,0error/0unresolved/0rateLimits,
saldo33,33EUR/strošek12,34EUR, vsi3phase-finance in vseh48phase-signed
zahtevkov točno ohranjeni (tudi prvotna2/42). Docker59776 spet ustavljen,
zasebno stanje ohranjeno; prod/stareQA/mobile/SDK/locks/Firebase/urnik isti.
Spodnji OPEN za source_set_changed je zgodovina pred tem popravkom.
P0/mobile/P8/N7 ostajajo odprti. Končna analiza v zapisu, commit/push;
brez native namestitve ali ponovitve prejšnjega benchmarka.

20. oktober — **skupno preverjeno branje financ zaključeno v izvoru** po
naročilu samo prvega nadaljevanja; trije GPT-6.1 Sol/high, glavni pregled.
[Izvedba in dokazi](docs/E2EE_FINANCE_READ_REUSE.md): per-scope kontekst
običajnega finančnega synca, lazy account/shared access, ločen runtime na
poslovni dispatch. Samo dokončan attested pull+checkpoint/izpeljave z
izvirno največ5s authority lease in točnim transakcijskim SQL odtisom sme
preskočiti ponovno branje. Pisanje/nepodprti dispatch/ne-attest/napaka/
sprememba dokazil razveljavijo podlago; ni globalcache ali podaljšanja TTL.
Veliki obsegi nad128records/128received/8checkpoints/256KiB gredo po običajni
poti. Jedro16PASS(poskus1), integracija4PASS(poskus2; prvi fixturemap type),
nov dejanski HTTP parPASS: finance58→39HTTP/7→4pull, celotno88→85HTTP;
isti saldo33,33EUR/strošek12,34/ID/revizije/vsebina/1choice/2completepayment
markerja. Bajti in čas niso boljši/dokazani: prvi cikel dodatna metadata
preverjanja, brez ponovitev za lepšo meritev. Priprava2FAIL source_set_changed,
tretji isti-stanje explicit prepare/approve/finish PASS; stari requests ostali.
Samodejni ensure po materializeAvailable ostaja ločen OPEN, ni popravljen.
Ni dejanskega novega testa menjave pina/identitete/lifecycle, temveč izvorni
pregled in generične kontrole guardov. Novi Docker59776 ustavljen, zasebno
stanje ohranjeno; produkcija/stareQA/SDK/locks/trgovini/urnik/Firebase isti.
N7odvzema in starihPASS ne ponavljaj. P0/mobile/P8 ostajajo odprti.
Končna analiza0error/0warning/515starihinfo, novi helper/test brez pripomb;
izvedba commit/push, brez namestitve.

20. oktober — **združeno pridobivanje pravic zaključeno v izvoru** po novem
ozkem naročilu uporabnika; GPT-6.1 Sol/high podagenti in glavni pregled.
[Izvedba, dokazi in nadaljevanja](docs/E2EE_AUTHORITY_BATCHING.md): izbirni
`crypto2.authority.snapshot` združi račun/prostor/dovoljene projekte, ohrani
podpise, direct-child-only, ločene finance, zavrnitve in isto največ5s mejo.
Stari strežnik ostane na točnih metodah; večji paketi/historija imajo omejitve
in nadomestne posamezne poti. Ni novega TTL ali spremembe urnika/pusha.
12novih odjemalčevih kontrol PASS (sočasni fallback v2.poskusu), dejanski HTTP
račun/starš/projekt+ponarejen podpis PASS v2.poskusu; prvi HTTP zajem je
ogrodje/izgubljen rezultat, ne appFAIL/PASS, delno stanje ohranjeno. SQLite
42novih kontrol PASS v3.poskusu po ozkem popravku read-side housekeeping;
MariaDB10.11.19 šest sočasnostnih kontrol PASS v1.poskusu. PHP lint PASS,
celotni analyze0error/0warning/515info, novi helper/testi čisti. HTTP14→4
vključuje capability (originalne metode13); JSON32.460→67.991B, torej ni
dokaza manjše pasovne širine ali nove meritve native412. Velike zgodovine
in celotni strošek ostajajo odprti. Novi HTTP59775 vsebnik ustavljen/stanje
ohranjeno, nova MariaDB vsebnika odstranjena. A-r12/B-r13/Docker18811 ter
stare/mobileQA/prod/trgovine/SDK/locks/sheme in nepovezana dokumenta isti.
N7/P0/mobile/P8 niso zaključeni; ne ponavljaj starih uspešnih scenarijev.
Predlogi osveževanja ob zaslonu/aktivaciji,5min omejitve, push in združevanja
finančne vsebine so samo zapisani za morebitno naslednje naročilo.

19. oktober — **omejeno nadaljevanje N7 zaključeno pri tretjem poskusu**.
[Končni dokazi in odprte meje](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md):
A-r12/B-r13/isti Docker18811, oba normalno zaprta. Odvzema in uspešnih
N0–N6 nismo ponovili. Izvorni activation-boundary popravek5PASS; B optional
finance parent-unavailable9PASS/native syncPASS; readonly/reconciliation
guard2PASS/native tretji poskusPASS: star task brez urejanja, izvirni lokalni
osnutek ohranjen1pending/0conflicting/1derivedblocked, nič task transporta.
B ne prejme V5, neodvisni direct projekt ostane dostopen (poskus2, ne ponovi).
N7 ni neomejen fullPASS: sveža serverwrite-denial ni izvedena; generic
blocked opozorilo napačno enači reconciliation z revoked/explicitresume.
Besedilo ostane OPEN/SKIP po3.poskusu, brez četrtega kroga.
A čakalne vrste0 in finance brez napake; starega directory_proof_pending
vzročnega popravka ne zatrjujemo. No-work guard4PASS, vendar strošek še
412HTTP/cikel, bistven prihranek ni dokazan. Costposkus2 analizaBLOCKED:
potreben ločen bounded combined-read pristop, brez unsafe cache/TTL/kvote;
brez umetnega3.poskusa. Skupaj20novih ciljnih kontrolPASS, brez celotne
ponovitve zbirk. Produkcija/stareQA/trgovini/SDK/locks nedotaknjeni;
P0/mobile/P8 in produkcijska pripravljenost ostajajo odprti.

19. oktober — **novo naročilo: popraviti zaključek odvzema in pending sync,
nato finančno opozorilo in strošek zahtevkov**. Nadaljuj ISTI Mac A/B in
ISTI N7; odvzem obeh epoch3 je že izveden, A-AFTER-REVOKE-V5 že shranjen.
Ne ponavljaj Remove/Save/prijav/FILE ali uspešnih N0–N6. Novi ozki popravki,
ciljni testi in potrebne izolirane gradnje so odobreni; produkcija/stare QA
ostanejo nedotaknjene. Delo isti GPT-6.1 Sol/high, glavni pregled.
**Nova izrecna meja: največ trije poskusi rešitve težavnega testa.** Ob
tretjem neuspehu zapiši dokaz in test preskoči; nadaljuj naslednji neodvisni
test, odvisne označi blokirane/neizvedene. Vodi števec po težavi, ne
začenjaj novega kroga z novimi računi/fixtures. Na koncu poročaj PASS/FAIL/
BLOCKED. Prvi popravek zaključka odvzema prekine staro authority-operation
memo po preverjeni aktivaciji;5novih ciljnih PASS, baselineFAIL, brez novega
odvzema. A r10 nameščen in en polni navadni cikel PASS: Synced0/0/0,
finance brez napake,418HTTP vsi200. Vrste so bile prazne že ob BEGIN,
vzrok starega pending ni dokazan; originalni V5 je strežniško applied/rev5.
B r8 native meja poskus1 FAIL: crypto_account_choices_target po offers in
contentpull pri direct-child-only brez dostopnega parenta;162HTTP vsi200,
brez writeprobe. Oba appa zaprta. Naslednji B popravek/tek je poskus2/3;
po prvi primarni napaki zapri, ne čakaj ponavljajočih avtomatskih ciklov.

19. oktober — **zaključek Mac deljenja: N4/N5/N6 PASS, N7 delno potrjen**.
[Dokazi in naslednje meje](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md): isti
A-r9/B-r8/Docker18811. N6 B dejansko prebere MAC-DIRECT-TASK z
N6-DIRECT-CONTENT, ne vidi MAC-PARENT-2/soseda; A starš ima samo A owner.
En projektni Send/Accept brez kartic/FILE; settings in prvi owner-read429
se nadaljujeta po naravnem izteku, brez novega povabila. N7 en Remove
20:22:33UTC strežniško uspe za prvotni starš+child: oba activeepoch3, B
odsoten iz signed rosters/aktivnih članstev/grantov, nič pending heads;
enapplied intent/activation affected2. Klient kljub temu zajame
crypto_membership_applied_head_missing; poznejši UI kaže samo A owner.
NE PONOVI Remove. En A-AFTER-REVOKE-V5 Save20:26:13 na istem MAC-SHARED-1
ostane1pending/0conflicting/0blocked; A normalno zaprt20:27:34. Novega
prenosa/odklonjenega pisanja pri B ni dokazano, zato N7 ni celotni PASS.
B ob enem odprtju še kaže cached B-OFFLINE-V4 z vidnimi edit kontrolniki;
write NI poskušen. Neodvisni direct projekt ostaja v izbirniku. Oba appa
normalno zaprta, B20:29:05UTC; seji/vsebnika/FILE/pending podatki ohranjeni.
Finančno directory_proof_pending in foreground strošek/429 ostajata odprta.
Brez novih gradenj/finančne diagnostike ali ponavljanja starih PASS;
nadaljnje delo popravi konkretna zaključek odvzema in pending sync ter
nadaljuje ISTO stanje. P0/mobile/P8 in produkcijska pripravljenost niso
zaključeni. Produkcija, stare QA, trgovini in nepovezana dokumenta isti.

19. oktober — **N5 offline/restart/samodejni prenos PASS; nadaljuje se N6**.
Isti A-r9/B-r8, brez novih gradenj. Samo novi gateway18811 je bil ustavljen
20:02:03.920–20:03:19.167UTC (75.247s), nato isti container obnovljen/running.
B en Save B-OFFLINE-V4 na istem MAC-SHARED-1, pending1/0/0; običajni quit/
restart brez povezave ohrani vsebino. Po povezavi B samodejno Synced0/0/0,
A ob20:04:24 dejansko prebere B-OFFLINE-V4 na istem enem opravilu. Glavni
pregled slik PASS, brez ponovnega Save/Sync/prijave/FILE. Finančno opozorilo
A ostaja ločeno in prenosa ni preprečilo. N6 MAC-PARENT-2 je ustvarjen
natanko enkrat; zgodnji retained-draft notice je bil normalen vmesni prikaz,
ne napaka (66HTTP vsi200, poznejši UI dokončan). Pripravljata se samo nujna
MAC-DIRECT-ONLY in MAC-PRIVATE-SIBLING. N7 odvzem še ni začet. Podrobnosti v
[runbooku](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md); stari PASS se ne ponavljajo.

19. oktober — **prednostna vrnitev na N5–N7 po uporabnikovem opozorilu na zanko**.
Finančni stranski testi/gradnje USTAVLJENI; brez r10 ali live-proof sprememb.
Izvor r9 d066b1ab… ohranjen, nameščena A-r9/B-r8. N4 dvosmerno opravilo in
lokalna ločenost PASS se ne ponavljata. En omejen existing-other HTTP ensure
41RPC/1s ni ponovil checkpoint hipoteze: dva choice_manager peer/child
online=false proof_pending, končni publication_required; diagnostični FAIL,
ne recovery PASS. Sledi dejanski N5 offline/restart istega MAC-SHARED-1,
nato N6 direct-child in N7 revoke. Samo novi Docker18811 gateway se začasno
ustavi po koordinaciji UI; vedno obnovi po offline checkpointu. Finančno
account-wide opozorilo je ločena odprta omejitev, ne pogoj za nov build.
Zajemi le nov dejanski zastoj scenarija, pred retry. Podatki/prod/stare QA isti.

19. oktober pozno zvečer — **isti Mac A/B ohranjeni; dvosmerna vsebina PASS, account-wide sync še ne**.
[Točni dokazi](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md): R8 A/B nameščena,
A r9 po dodatnem šestvrstičnem popravku običajnega stale certifikata. 5novih
ciljnih discovery kontrol PASS, analiza čista, glavni/neodvisni pregled PASS;
izvor d066b1ab…/freeze6304ca83…. A r9 artifactb9a25ed2…/AOT745a4183…;
B ostane r8. Prvi pasivni A19:54:49UTC zdaj directory_proof_pending pri
sync_finance,197HTTP vsi200, nič batch/propose/delegate/certify. Pot po drugem
offers pride do sveže prepare odvisnosti inventory/lifecycle/observations;
verifier checkpointa uporablja offline directoryAt za podpisnikov prefix.
To je konkreten izvorni kandidat, ne še dokazan točen native podpisnik ali
popravek. Pred novo gradnjo preverjamo celotno pot; ne sproščamo pin/authority
ali offline varoval. A normalno zaprt19:55:36UTC, B zaprt, oba podatki/seji
isti. N4 A-V3/B-V2 in zasebna ločenost PASS ostanejo, brez ponovitev. N5 ni
začet, gateway teče; N6/N7 odprta. Produkcija/stare QA/trgovini isti.

19. oktober zvečer — **Mac dvosmerno deljenje in lokalna ločenost PASS; r8 odpravlja terminalni konflikt izbire računov**.
[Aktualni dokaz](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md): isti A/B/Docker18811,
eno MAC-SHARED-1: A je dejansko prejel B-V2, B ob19:38UTC A-V3. B lokalni
LOCAL-B-PRIVATE ostane Personal/Local in je odsoten v A AllTasks. N4 PASS;
ni novega povabila ali ponovitve Save. R6 popravi crypto_revision namesto
legacy_revision pri izbiri računov: vzročni HTTP preizkus in native B
Synced0/0/0 PASS. A Done se je ohranil; r7 zajame ločen sync_finance /
crypto_business_delivery_pending. En omejen read-only server dokaz poveže
A terminalni409 conflict s točno enim financeAccountChoice v znanem child.
R8 zamrznjeni izvor5625acbf… zahteva točen podpisani terminalni conflict in
svežo popolnoma preverjeno novejšo izbiro; originalni request/receipt/claim
ostanejo. Devet novih negativnih HTTP kontrol PASS, analiza čista in
neodvisni/glavni pregled PASS. Pozitivna sintetična HTTP obnova NI dokazana;
hladni drugi klient ostane pending, razširjanje vaje ustavljeno brez resetov.
Zero mutacij pomeni samo naštete poslovne RPC, ne vseh metadata zapisov.
Freeze13d555bc…; pripravljata se zaporedni r8 gradnji ob istem vsebniku/
Keychain/TLS/SDK/locks. Oba appa normalno zaprta19:39:50UTC. Najprej pasivni
A native dokaz razrešitve njegovega pravega konflikta, brez Done/Save/Sync.
N5 offline NI začet, gateway ni ustavljen; N6 direct-child in N7 revoke
ostajata odprta. Foreground strošek ostaja omejitev. Produkcija, stare
Mac/mobile QA namestitve, trgovini in nepovezana dokumenta isti.

19. oktober — **Mac deljenje obstoječega projekta PASS; prva B sprememba čaka diagnozo sync parserja**.
[Checkpoint in meje](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md): po odklepu
isti A/B in Docker18811, eno MAC-SHARED-1/A-V1 ter eno parent povabilo.
B registracija/e-pošta/računski FILE PASS, LOCAL-B-PRIVATE ohranjen pred Join.
Prvi accept je uspel na strežniku, UI pa primerjal nekanonični URL; r3 popravek
istega čarovnika (7novih widget+2journal PASS) dejansko nadaljuje isto dejanje
z nič novimi accept RPC in pokaže čakanje na ključe. En A Confirm access
aktivira parent v epoch2 z B, child epoch2 ostane pending ob429 (434HTTP v vezanem oknu).
En poznejši Finish project access lokalno zavrne scope_rotation_reauthorization_required;
nič write RPC, poznejši pull409 ni vzrok. Primerjava potrdi samo napredovanje
A/B directory heads, vsi root/device/epoch/role/access basis/revision isti.
R4 manager dopušča samo preverjeni zgodovinski prefix ob nespremenjeni
avtoriteti in originalnem osnutku/DEK/zahtevah; uporablja obstoječi child ali
parent kontekst tudi pred headPut. Realni izolirani HTTP preizkus istega
osnutka pred/po objavi PASS, točna stara vsebina prebrana, brez drugega
sprejema/parent aktivacije;14novih negativnih PASS, analiza čista, neodvisni
pregled PASS. Oba podpisana r4 nameščena čez ista vsebnika/Keychain.
En native A Finish16:58UTC uspe (568HTTP vsi200,6grant/1activate),
brez novega accept/headPut; B startupDone zadene dokazani account.status429.
A se normalno zapre ob17:01:48UTC; en B isti saved-invite Retry uspe,
182HTTP vsi200/brez accept ali mutacij. B ob17:02:26UTC dejansko prebere
MAC-CHILD-1/eno MAC-SHARED-1/A-V1. N3 PASS, brez primerjave kartic.
En B Save B-V2 in prvi Rules Accept ob17:03UTC oddata en records.batch200;
prikaz pri A še ni preverjen. B sync je invalid_response/FormatException,
prva primarna oznaka že pred spremembo; ničpending/conflicting/blocked,
HTTP okni vsi200. QA logger ne bere FormatException.message, zato se
pripravljena samo B finite-code diagnostika brez surovih podatkov, privacy
kontrole PASS. R5 source-b ima samo QA helper delta, plan33b55945…;
NI zgrajen/nameščen. Mac spet zaklenjen, CUA zahteva ročni odklep in
uporabnik je vprašan. A zaprt, B r4 PID45559 ohranjen. Po odklepu normalno
zapri B, ena r5 B-only gradnja/pregled/namestitev in samodejni sync zajem.
Ne ponavljaj Save/Sync/setup/FILE/povabila/parent granta.
Dvosmerno urejanje/offline/direct-child/revoke ostajajo odprti; večji
foreground strošek ni rešen z idle popravkom. Produkcija, stare Mac/mobile
QA namestitve, trgovini in nepovezana dokumenta isti. Spodnji jutranji
checkpoint je zgodovina pred nadaljevanjem.

19. oktober — **dve novi Mac namestitvi pripravljeni; deljenje čaka odklep Maca**.
[Checkpoint in meje](docs/E2EE_MAC_SHARING_TEST_2026_10_19.md): izolirani
Jivie Test Share A/B in Docker18811; A račun/e-pošta/FILE ter isti
MAC-SHARE-SPACE/MAC-CHILD-1 pripravljeni, B lokalni LOCAL-B-PRIVATE ohranjen.
Prvi child create je zadel429; isto delno delo se je nadaljevalo brez novega
scope/projekta. Popravljena zastarela account povzetka, odvisnost startup
preverjanja in podvojene finančne preflight poti; ustaljeni strošek220→140.
Nov urnik:60s idle, takojšnje novo delo,15/30/60 backoff, identity-bound
RetryAfter, polni začetki/zaključki; brez authority cache ali višje kvote.
52 novih ciljnih +7 prizadetih PASS, analiza0error/0warning/73starihinfo;
neodvisni pregled PASS. Dve podpisani r2 gradnji nameščeni čez isti lastni
vsebnik/Keychain, stara paketa ohranjena. Native A pasivno307HTTP/200,
nič429, drugi prehod61s po koncu prvega; B še ni povezan. Mac je zaklenjen,
CUA zahteva ročni odklep; po r2 ni novega opravila/povabila. Nadaljuj pri
MAC-SHARED-1/A-V1, nato istem enkratnem povabilu B; ne ponavljaj setupa A/B.
Dvostransko deljenje/child grant/offline/direct-child/revoke ostajajo odprti.
Produkcija, prejšnji Mac/mobile QA, trgovini in nepovezana dokumenta isti.

19. oktober — **deljenje E2EE poenostavljeno v izvoru** po novi izrecni
odobritvi uporabnika; trije GPT-6.1 Sol/high, glavni pregled/integracija.
[Izvedba in meje](docs/E2EE_SHARING_SIMPLIFICATION.md): običajni tok nima
obvezne primerjave kartic. Prvi stik zaupa povezavi računa z javnim ključem
pri gostovanju; podpisano verigo preveri in koren varno zapomni. Nepričakovana
zamenjava ostane blokirana, ročna primerjava neobvezna. Javni podatki
upravljavca so vidni ob povezavi/povabilu in v nastavitvah; nikoli se ne
izpeljejo iz zasebnih skrbniških/SMTP podatkov. Ključi vsebine ostanejo na
napravah. Model ne ščiti pred namerno zamenjavo prve identitete pri gostovanju.
Trajna lastnikova odobritev nadaljuje tudi obstoječe podedovane projekte,
preveri popoln podpisan seznam in ohrani vloge/finance/preklic/svežino;
običajno branje prevzame manjkajoče dovoljene ključe. Ciljni testi zaupanja,
UI, nadaljevanja in sprejema ključev PASS; končni analizni rezultat vodi zapis
izvedbe. Nov izoliran Docker HTTP potrdi isti sprejem z enim zahtevkom,
odobritev, branje prejšnje projektne vsebine ter zavrnitev po dejanski menjavi
korena brez predaje ključev. Hladni poti imata izmerjenih 152/70 zahtevkov;
večji prostori in fizični tok ostajajo za nadaljnje preverjanje. Samo nov
začasni vsebnik in njegove sintetične skrivnosti so odstranjeni. Produkcija,
ohranjene Mac/mobilne QA namestitve/podatki, SDK/locks/verzije/trgovini so
nedotaknjeni. Mobilni spodnji checkpoint še ni nadaljevan, P0/P8 nista
zaključena; ni nove native gradnje ali namestitve. Nepovezana varnostni in
desktop dokument ostaneta nedotaknjena.

18. oktober — **mobilni E2EE QA: skupno opravilo/sync/mail in isti B predogled/registracija/e-pošta/FILE potrjeni; B je sprejel isto povabilo, owner grant še čaka**.
[Aktualni checkpoint in vezani dokazi](docs/E2EE_MOBILE_TWO_USER_TEST_2026_10_18.md):
A je shranil eno MOBILE-SHARED-1 v istem projektu; UI/samodejni sync in en
read-only server snapshot potrdita en task/receipt, brez podvojitve. Eno
originalno organizacijsko povabilo je samodejno dostavljeno po izoliranem QA
public URL popravku. Android QA je bil ob 18:15:08 UTC začasno force-stopped,
brez odjave/čiščenja; seja in podatki ostanejo ohranjeni.
Na istem iOS PID 662 je kandidat 13149f9e… po QA PEM popravku dosegel origin
in dejanski HTTPS predogled istega povabila. Prvotni zajem je dokazal
TlsException pri QA konstrukciji, ne Keychain/SQL/session napake; isti CA,
withTrustedRoots:false in točen HTTPS cilj ostanejo. NativeService zdaj
oglašuje invitation v4 samo ob cryptoReady: old FAIL → dva dejanska dispatch
primera/6 kontrol PASS, lint PASS; QA zamenjava samo 1/181 datotek, brez
app gradnje/DDL/restarta. Deljeni gateway limiter je opažen, individualna A
atribucija ali zgodovinski vzrok 429 nista dokazana. Po naravnem izteku je
en Retry dosegel predogled (eaf94400…). Prvi B Submit ni napredoval;
pozneje sta bili ugotovljeni različni password/confirmation polji. Obe sta
popravljeni iz iste pripravljene zasebne vrednosti; en popravljeni Submit ob
18:23:32.742 UTC je dosegel računov FILE čarovnik/pending email verification
(603af61b…). To še ni FILE/Join/grant PASS. Začasni QA gateway zajem vsebuje
le čas/metodo/status/trajanje, 23 POST/200; prvotna konfiguracija je ob
18:24:11 UTC obnovljena. Končni email-bound pregled potrdi en B račun,
verification token ob 18:23:33 in SMTP accepted ob 18:23:36, en poskus
(9b020bd1…). Dejanski username se razlikuje od obeh pripravljenih selectorjev;
njune ničelne najdbe niso dokaz odsotnosti računa. En vnos email kode ob
18:27:33.636 UTC pokaže »Potrjen naslov«; en native Save/re-pick istega
509 B account FILE pokaže pripravljene account/device ključe. Mešano rdeče
opozorilo je odstranil en status-only Retry, brez nove FILE/inicializacije;
natančen prejšnji vzrok ni dokazan. En Končano pri praznem katalogu je uspel brez napake/unavailable soglasja;
običajni Back je vrnil isto avtenticirano povabilo in en Join odprl primerjavo
kartic (6101db73…). A je po uporabnikovem odklepu pokazal javno kartico prek
odobrenega UI in bil nato spet ustavljen brez odjave/čiščenja. Prvi typed
Compare ni uspel; dejanski vneseni bajti niso dokazani. En read-only pregled
potrdi, da invitation creator head/generation ustrezata kartici (0b9acd37…);
ni spremembe varoval ali novega povabila. Prenos SendClipboard + native Paste
in en Compare ob 18:57:55.360 UTC sta sprejela isto povabilo: B čaka owner
ključe (18d1f5e5…). Omejeni strežniški zajem potrdi accept SUCCESS/200 in exact
rollback ob 18:58:35.720 UTC (d5f43db1…). Prvotna input napaka in GetClipboard
host-sentinel izid nista dokončno pojasnjena. B javna kartica je zdaj
pridobljena ob prvem Copy/Get (sentinel pred Copy, brez host write po njem),
327 B/f2cbe65d…; exact7/account/server/canonical pregled PASS (1c5aa3d2…).
A je po uporabnikovem odklepu spet odprt v isti seji na parent settings;
owner grant še ni izveden. B se je normalno vrnil Settings→Utrip→shranjeno
isto povabilo in dobil »Preveč poskusov«, brez Retry in brez atribucije A.
Parent grant bo razširil učinkovite pravice, ne samodejno pripravil child
DEK; generični child review ohrani stari roster, zato je pot za novega
inherited B označena kot SOURCE CONCERN, ne potrjena native napaka ali PASS.
A IME je preoblikoval B kartico; poznejši browser Copy/native-menu Paste je
potrdil exact 327 B/f2cbe65d… vnos. En Compare je nato povzročil native Flutter
framework6281 assertion; prvi native stack ni zajet, grant ni izveden. A je
19:18:53 UTC ustavljen z ohranjeno sejo/podatki. Ozki source reproducer je
pokazal prvi used-after-disposed controller error in nato isto sekundarno
assertion. Skupni Stateful dialog zdaj drži controller do unmounta, oba
callerja ohranita trust/current/result varovala in prvotni razlagi; rawinput
ostane nespremenjen, IME korekcije izključene. 8 novih ciljnih lifecycle PASS
(Android/iOS × Confirm/Cancel/barrier/Back), scoped 0 error/0 warning in
7 starih runtime info; poznejši test-only slogovni popravek brez ponovnega
widget teka. Vezani dokaz 31474292… loči source dokaz od nezajetega prvega
native stacka. En novi Android APK cc019674… je z install -r nameščen ob
istem dataDir/podpisu; običajni zagon je PID 28910. S25 je fizično zaklenjen,
čaka uporabnikov odklep; debug attach readiness še čaka. Console connected,
native fix PASS in grant niso potrjeni. Artifact/source povezavi sta v
runbooku; dostop do MOBILE-PROJECT-1 ostane ločen checkpoint, brez objave
lokalnega MOBILE-LOCAL-B.
Prejšnji parser fix: 7 PASS; readiness widget fixture NOT COMPLETED, ne
PASS. Podrobna zgodovina/diagnostika in hashi so v runbooku; QA diagnostike
ni v main. Owner potrditev identitete/grant, dvostransko deljenje, odvzem, offline/physical
recovery/upgrade, P0/P8 in produkcijska pripravljenost ostajajo odprti.
Produkcija/trgovini, izvirni aplikaciji/podatki in Mac PASS so nedotaknjeni;
FILE/poverilnice ostanejo zasebne, nepovezana dokumenta ostaneta nedotaknjena.

18. oktober — **mesečno pravilo na istem izoliranem D dejansko sinhronizirano**.
[Dokazi in meje](docs/E2EE_MAC_TEST_2026_10_18.md): contract-2/3 gate popravek
ohrani ACL/completeness in staro E2EE obliko; dodatna active-grant admission
pot po dveh svežih authority mejah ohrani exact key/commitment preverjanje.
16 novih ciljnih monthly in 4 dodatni admission PASS; brez ponovitve prejšnjih
uspešnih zbirk. Začetni native save/readback je ohranil 2 pending; en varen
QA tek je zajel `scope_keys_pending`, nato je končni navadni D ista requesta
zaključil brez nove prijave, obnove, pravila ali ročnega Sync. Zaključeni
samodejni cikel ob 13:58: Synced, 0 pending/conflicting/blocked, brez napake.
Eno `E2EE D Mesecni Preizkus`, planned expense 1.23 EUR na Legacy D Racun,
prvi datum 20. september 2027; ponovni prikaz brez podvojitve, današnji saldo
67.89 EUR nespremenjen. Obe opozorili sta odsotni, D normalno zaprt. To je
own-account mesečna pot, ne čezobsežna pravila ali fizični mobilni/P8/P0 audit.
Produkcija, strežniška koda/sheme in izvirna namestitev so nespremenjeni;
QA diagnostike ni v končnem paketu/main. Spodnja mesečna omejitev je zgodovina.

18. oktober — **polni sintetični D saldo potrjen po poznejšem izrecnem naročilu**.
[Novi dokazi](docs/E2EE_MAC_TEST_2026_10_18.md): ozek popravek dveh runtime
datotek prepreči, da policy refresh prepiše preverjeno finančno coverage;
sveži head/inventory/checkpoint in child guards ostanejo. Šest novih ciljnih
testov PASS, scoped analiza čista; prejšnjih uspešnih zbirk ni bilo ponovljenih.
Ena izolirana D gradnja in zamenjava samo testnega paketa ohranita iste
podatke/sejo brez prijave. Običajni Finance UI: celotni saldo 67.89 EUR,
income/expense 0.00, en Legacy D Racun; incomplete project opozorila ni več.
Samodejni sync ob 13:10 Synced, 0 pending/conflicting/blocked, brez napake.
D je po enem običajnem zagonu in preverjanju normalno zaprt, brez urejanja
ali ročnega Sync.
Mesečno opozorilo o potrebni novejši pogodbi ostaja ločeno odprto; fizični
mobilni/P8 in neodvisni P0 audit niso zaključeni. Produkcija, strežniki/sheme
in izvirna uporabnikova namestitev so nespremenjeni; brez nove trgovinske oddaje.
Spodnji zapis o nepotrjenem polnem D saldu je zgodovinski checkpoint ob 12:44.

18. oktober — **izolirani native macOS E2EE preizkus zaključen v omejenem obsegu**.
[Dokazi in meje](docs/E2EE_MAC_TEST_2026_10_18.md): A ponovna prijava iste
namestitve z ohranjenimi ključi PASS; B se z geslom prijavi, pričakovano pa
brez računskega FILE ali odobrene naprave ne odklene vsebine; sveža C obnova
z izvirnim računskim FILE PASS. Ločeni D stari → novi macOS prehod po ozkih
Apple Keychain in cursor/revision popravkih ohrani sejo ter lokalne/povezane
vnose, brez nove prijave ali podvojitev; končni sync ob 12:44 je Synced,
0 pending/conflicting/blocked. D račun 67.89 EUR je preverjen samo kot
otvoritveni/referenčni znesek; **polni saldo in finančni pregled nista potrjena**,
opozorili o coverage in mesečni pogodbi ostajata. Vsi testni appi so zaprti.
To niso fizični Android/iOS preizkusi, zaključek P8 ali neodvisni P0 audit.
Produkcija in izvirna uporabnikova namestitev ostajata nedotaknjeni; ni nove
produkcijske namestitve, trgovinske oddaje ali začetka produkcijskega retention
roka. Nepovezana varnostni in desktop dokumenta ostaneta nedotaknjena.

18. oktober — **E2EE nadgradnja v zaključnem preverjanju izvora** po
poznejšem izrecnem naročilu za izvedbo in končni commit/push; trije
GPT-6.1 Sol/high podagenti, glavni pregled/integracija.
[Izvedba in točni dokazi](docs/E2EE_IMPLEMENTATION.md),
[protokol](docs/E2EE_PROTOCOL.md) in [prvotni načrt P0–P8](docs/E2EE_UPGRADE_PLAN.md)
ločijo potrjene meje od še nedokončanih poslovnih poti. Migracija, sveža
FILE obnova in zadnji povezani poslovni izbris so potrjeni z vezanimi teki in
nadaljevanji istega stanja. Generacija B, sveža FILE obnova in običajno
branje priponke ter seznam in umik migriranih opomnikov use3 so potrjeni z
vezanim nadaljevanjem istega stanja. Celotni Flutter66 je razkril regresije;
prizadete ponovitve69/70 so jih zaključile, analiza ima0 error/0 warning ter510 info.
To ni nov sveži celotni tek. Podrobni source/log hashi,
zgodovinska PHP matrika in poznejša prizadeta preverjanja so navedeni v izvedbi.
Ni trditve dokončane podpore ali neodvisnega pregleda P0; fizična/native in
izdajna merila P8 ostajajo odprta. Prvi hladni prenosi imajo dokumentirano
omejitev zmogljivosti. Lokalna uporaba ostane brez računa, datoteko uporabnik
shrani/deli sam, nikoli prek Jivie SMTP. Stari berljivi strežniški viri/kopije
niso odstranjeni: za uporabnikovi gostovanji ostaja30 dni po dokumentirani
dejanski uspešni obnovi NOVE šifrirane kopije, ločeno za vsako gostovanje;
neuspešna obnova rok zadrži. Čiščenje je poznejši namestitveni korak.
Gostovanja ostajajo na zadnjem dokazanem0.15/schema19; ni nove app verzije,
gradnje ali trgovinske oddaje. Android31/iOS31 te kode ne vsebujeta.
Nepovezana varnostni in desktop dokumenta ostaneta nedotaknjena.
Spodnji planski zapis je zgodovina pred poznejšim naročilom za izvedbo.

17. oktober — **E2EE, šifrirana lokalna shramba in obnovitvena datoteka samo načrtovani**
po izrecnem naročilu. [Načrt](docs/E2EE_UPGRADE_PLAN.md) in
[zemljevid kode](docs/E2EE_CODE_MAP.md): dva GPT-6.1 Sol/high za izvor,
GPT-6 Astra/high za ključne povezave in migracijo, glavni pregled/integracija.
Nadaljevalni čarovnik »Dodajanje obnovitvenega ključa« ob nadgradnji in
prvi povezavi; datoteka nastane lokalno in se shrani/deli po uporabnikovi
izbiri, nikoli prek Jivie SMTP. Potrjena dodatna odločitev: lokalna uporaba
ostane brez računa, e-pošta pogojuje vnose povezanega računa. Geslo danes
prejme PHP, zato samo ne odklepa E2EE na novi napravi; potrebna datoteka ali
potrjena naprava. Celotna lokalna namestitev, finance4, deljenje in nespremenljivi
stari zahtevki ostanejo migracijske invariante; brez tihega praznjenja ali
podvajanja. Protokol/knjižnice in dokazljiva obnova zahtevajo preverjanje pred
izvedbo. **Ni naročila za implementacijo, commit/push, gostovanje, gradnjo ali
trgovinsko oddajo.** Nepovezana varnostni in desktop dokumenta ostaneta nedotaknjena.

17. oktober — **organizacijske finance in projektni pregledi izvedeni v izvoru**
po naknadnem izrecnem naročilu »dej kr nared nadgradnjo še financ«; trije
GPT-6.1 Sol/high podagenti, glavni pregled/integracija.
[Izvedba](docs/ORGANIZATION_FINANCE_IMPLEMENTATION.md): neposreden račun prostora,
projektni strošek/priliv ostane en kanoničen zapis z računom starša; skupni
račun/projektni filter, brez projektnega podvojenega denarja. Finance4/pogodba3,
varne projektne izbire brez salda, contributor IDs+sequence in zadnja odstranjena
povezava varujejo popolnost. Stari projektni računi/osebna plačila ohranjeni;
lokalna objava, task-cost in kopija8/baza10 ohranijo točne povezave/ACK.
104 zaključnih UI/projekcijskih PASS,72 podatkovnih ter24 zaključnih task-cost
PASS (prekrivanje); kopije/predogled26+1, repository4, združljivost1–7 PASS.
1506 strežniških kontrol na SQLite/MariaDB/MySQL,20PHP lint PASS; analiza
samo10starihinfo brez novih. [Novi strežniški predpogoji](docs/server/ORGANIZATION_FINANCE_RELEASE_PREREQUISITES.md):
potrebna nova usklajena koda FamilyHuba, brez DDL; sveža kopija/prava obnova
pred poznejšo namestitvijo. Ni novega gostovanja/crona/SDK/locks/verzije appa,
gradnje ali trgovinske oddaje; AAB31 te kode ne vsebuje. Samo commit/push.
Čezobsežna mesečna pravila ostajajo izven te faze; stara pravila dostopna.
Nepovezana varnostni in desktop dokument ostaneta nedotaknjena.

17. oktober — **hierarhični izbirnik prostorov izveden v izvoru** po naknadnem
izrecnem naročilu, s tremi podagenti GPT-6.1 Sol/high in pregledom glavnega.
[Izvedba](docs/SPACE_PICKER_HIERARCHY_IMPLEMENTATION.md): krovni prostori se razširijo v
projekte, iskanje zajame tudi zložene veje; »Deljeno z mano« samo dostopni
projekti drugih trenutnih lastnikov. Tuj projekt pod dostopnim prostorom je
viden v drevesu in kot bližnjica, projekt brez dostopa do starša samo v deljenem
razdelku. Lastništvo že obstaja, prvotni ustvarjalec krovnega prostora ni
ločen trajni podatek. Lokalni/skupni/inline projekti odprejo točen pregled;
isti osebni resolver in identiteta/generacija preprečita zastarele izbire.
56 ciljnih in123 navigacijskih regresij PASS, analiza samo10starihinfo brez novih.
[Novi strežniški predpogoji](docs/server/SPACE_PICKER_RELEASE_PREREQUISITES.md):
ni potrebna nova shema/API/namestitev, pred javno izdajo ozke žive kontrole.
Naročen samo commit/push, brez strežnika/gradnje/trgovinske oddaje.
Finančna nadgradnja ostaja samo načrt; nepovezana varnostna in desktop dokumenta nedotaknjena.

17. oktober — **računi organizacije in projektni pregledi samo načrtovani**.
[Dogovor](docs/ORGANIZATION_FINANCE_PLAN.md): finančni račun pripada organizaciji
oziroma prostoru, projektni »podračun« je za začetek ločen pregled njegovih
prilivov/stroškov brez rezervacije denarja ali podvojenih knjižb. Projektni
proračun ni račun. Zabeležena zanka »Dodaj v prostor« → ista organizacija;
Finance2 še ne povezuje splošnih projektnih transakcij z računom nadrejenega
prostora, potrebna bo razširitev aplikacije in FamilyHuba na istem gostovanju.
Uporabnik naroči samo nov planski dokument, nato pogovor o naslednji nadgradnji.
Ni naročila za implementacijo, strežniško nadgradnjo ali trgovinsko oddajo.

16. oktober — **iOS1.10.1(31) dejansko naložen v Apple po novem naročilu**.
[Dokazi](docs/release/IOS_TESTFLIGHT_1_10_1.md). Isti aktualni Android31 izvor
3ce7105/main,443izdajnih/330runtime vhodov;48iOS/3locks/SDK/config isti28.
En nov arhiv, obstoječi Cloud Managed Distribution/Store profil do26.9.2027,
manageVersion/internalOnlyOFF/symbolsON; Organizer **App upload complete**
16:11EuropeLjubljana. IPA28.449.881B/SHA33d7b387…/CRC/strictdeep/productionAPS/
18privacy/Firebase PASS;23ciljnihFlutterPASS. 40novih iPhone/iPadSLENwidget
slik/16capturePASS,32RGBnalagalnih slik ohrani vsakvidnipiksel; **še niso naložene**.
Portal priJivie/TestFlight vrača napako; po lastnikovi ponovni prijavi/Safari
**AppleComplete31 potrjen**, IDcae5d3b5…;25/26Testing/1tester nameščena26.
Razdelek31napaka/AddBuild»Nobuildsavailable«/detailWhatToTestdisabled;
FreeAppsActive, brezpogodb. **Testing31 še NI potrjen**;
encryption/WhatToTest/skupina/Appleosnutek/slike še odprti. Ne ponovi gradnje ali
uploada31 zaradi portala. Nobene javneAppleoddaje/novihpravic/pogodb/strežniške
aliGooglePlayspremembe. Nepovezan varnostni dokument ostane nedotaknjen.

16. oktober — **Android1.10.1(31) dejansko oddan javno** po novem izrecnem
naročilu. [Dokazi](docs/release/SPREADSHEET_ZOOM_1_10_1.md). Povečava preglednic
in pomoč iz5fe4fdf, izoliranih443vhodov/330runtime,3spremenjeni+1nov proti30.
Ena podpisana AAB31SHA1ecce6df…/81.312.731B; istiSDK/locks/config/native/
podpis/8dovoljenj,9ne-app.so bajtnoisti30,8×64bitLOAD16KiB/bundleCRC PASS.
70izoliranihFlutter+23release+7FirebasePASS/sourcecheckerPASS/analizačista.
Production4698247597354229997/release7,31vključena/30izključena,100%/iste
države/SLen-USopombe/0izgubljenihnaprav. Končno »1sprememba poslana v pregled«,
**Spremembe v pregledu**, hitre kontrole še tečejo/upravljanoOFF.
**Javna31/odobritev še nista potrjeni.** Svež Play pred oddajo potrdi javno30
Aktivno/1država/brezneobjavljenih; starejši pending30 je zgodovina.
Galerije/DataSafety/opisi/splet/strežniki/sheme/Apple isti, interni ni uporabljen.
Obstoječe DataStoreRELRO opozorilo30/isti knjižnici, fizični16KiB ni potrjen.
Ta odobritev velja za31; naslednja oddaja potrebuje novo izrecno naročilo.

16. oktober — **povečava preglednic in pomoč pri formulah izvedeni v izvoru**
po uporabnikovem S25 preizkusu. [Dokazi](docs/SPREADSHEET_ZOOM_HELP.md).
Pinch50–200% samo mreža/besedilo/oznake, ohranjen položaj pod prstoma,
−/odstotek/+ s ponastavitvijo100%; pomoč SL/EN z vsemi5funkcijami/primeri.
63ciljnihPASS (9novih dejanskih potez/poravnava/vnos/preklic/pomoč), analizačista.
Ni strežniške nadgradnje/sheme/SDK/locks/dovoljenj/nove gradnje ali Playoddaje;
obstoječi AAB30 tega popravka ne vsebuje. Fizični zoom še ni potrjen.

16. oktober — **produkcija in pregledni test1 nadgrajena; Android1.10.0(30) oddan javno**.
[Strežnika](docs/server/UPGRADE_0_15.md), [izdaja](docs/release/INVITATIONS_DOCUMENTS_1_10.md),
[splet](docs/release/WEBSITE_DOCUMENTS_20261016.md). Nova izrecna odobritev uporabnika
izvedena s tremi GPT-6.1-sol/high podagenti in pregledom glavnega agenta.
Izvor6c8a2fc/main poslan; javni FamilyHubdd5ae02/v0.15.0, ZIP5c14ca9…107datotek/94PHP.
Sveži ločeni zasebni kopiji in dejanski izolirani MariaDB10.11.19 obnovi PASS:
produkcija93tabel423vrstic/SHA76002f71…, test1 93tabel343vrstic/SHAed0feed3…;
vsaka2DATA/2imenika/101starihizvorov, vsi row/CREATE/config/ključ/cron hashi isti.
Oba končna checkpointa **released**, APIpausedfalse/workersrestoredtrue;
shema19 doda5praznih tabel,107izvorov,3računi4/10naprav ohranjenih. JavniHTTPS200/
istiSID/enabled/invitation3/preglednice/priloge/SMTP/push potrjeni. Test2 isti.
Zaključnih2331strežniških kontrol (777SQLite/MariaDB/MySQL),102PHP lint in11paketnih PASS;
1582Flutter/16skip,59prizadetih/1skip,120izoliranih izdajnih +23/7kontrol PASS.
Ena podpisana AAB30SHA9f0aab74…/442vhodov/istiSDK/locks/konfiguracije/native/
podpis/8dovoljenj/engine/16KiBporavnava. Opozorilo stare DataStoreRELRO knjižnice
je pregledano in dokumentirano; fizični16KiBpreizkus ni izveden.
Javna izdaja4698247597354229997/release6,30vključena/29izključena/100%/Slovenija,
SLen-USopombe,0izgubljenih ali novih podprtih naprav. Obe galeriji8aktualnih
720×1280slik, nova opisa inFiles/docs12.vrsta DataSafety shranjeni. Natanko6sprememb
končno potrjenih: **Spremembe v pregledu**; Googlove hitre kontrole še tečejo,
upravljano objavljanje OFF. **Odobritev ali javna30 še NISTA potrjeni**; javna29
ostaja do odobritve. Interni kanal ni uporabljen, Apple ostaja odložen.
Spletna SL/ENzasebnost in pomoč dejansko objavljeni: preverjena25datotečna kopija,
4HTMLzamenjani,21drugih datotek/pravice/lastništvo isti,4HTTPS200/hash PASS.
Ni dejanskih novih povabil ali fizične namestitve30. Nepovezan varnostni dokument
ostane neversioniran. Naslednje je izid Googlovega pregleda; nova izdaja potrebuje
novo izrecno naročilo, brez ponavljanja splošne testne/gradilne matrike.

16. oktober — **nova izrecna uporabnikova odobritev usklajene izdaje**:
nadgradi `jivie.triparna.si`, naredi commite/pushe in oddaj novo javno različico
v Google Play; po potrebi posodobi trgovinske posnetke glede na aktualni UI.
Delo vodijo trije podagenti GPT-6.1 Sol/high pod nadzorom glavnega agenta.
Pripravljamo FamilyHub0.15.0/schema19 in Android1.10.0(30), vključno s
preglednicami/prilogami, poenostavljenimi povabili in prej izvedenimi popravki.
To dovoljenje velja za to konkretno izdajo; interni kanal in Apple ostaneta
odložena. Pred DDL ostanejo obvezni sveži zajem, celotna kopija in dejanska
izolirana obnova; pregledni test1 se uskladi z izdajo. Zajema produkcije/test1
sta potrdila0.14.1/schema18/101datoteko/iste identitete/ZipArchive/zasebni DATA.
Svež Play potrdi29 javno od15okt10:14, brez neobjavljenih sprememb in brez30.
Priprava ni dokaz nameščene0.15 ali oddane30. Zaključne dokaze bosta vodila
docs/server/UPGRADE_0_15.md in docs/release/INVITATIONS_DOCUMENTS_1_10.md.

16. oktober — **povabila, prvi vstop in deljenje poenostavljeni v izvoru** po
izrecnem naročilu; trije podagenti gpt-6.1-sol/high, glavni agent integrira in preveri.
[Izvedba in meje](docs/INVITATION_AND_SHARING_IMPLEMENTATION.md).
Namenski čarovnik ohrani povabilo skozi prijavo/registracijo/obnovo, izrecni Join
in ločena pravila; Utrip pokaže prejeta povabila. Neposredna ikona Deli, točen
lokalni cilj brez ponovnega checkboxa, gospodinjstvo/organizacija že pri nastanku
ponudita »Sinhroniziraj z oblakom«. Trajen osnutek prepreči podvojitev ustvarjanja.
FamilyHub pogodba3 doda obstoječega username prejemnika in atomsko resend;
SMTP-off username deluje, nove uporabnike še vedno povabi po e-pošti.
Celotni Flutter1582 PASS/16obstoječih preskokov;534ciljnih strežniških kontrol
SQLite/MariaDB10.11/MySQL8.4 in96PHP lint PASS. Analiza10starihinfo brez novih
warning/error; Android debug PASS. Zaključne ozke regresije so v zapisu izvedbe.
Širša space-sharing PHP zbirka ima nepovezan obstoječ householdPerson.archived
validation zastoj po66kontrolah; ni trditve, da je celotni strežniški nabor zelen.
Ni spremembe verzije/SDK/locks/native dovoljenj, namestitve, živih povabil,
gostovanj, javnega plugin repozitorija ali trgovinske oddaje. Ta prenova ne
dodaja sheme; predhodna izvorna shema19 še čaka usklajeno izdajo in pravo kopijo/obnovo.
**Google Play samo po novi izrecni potrditvi; brez internih izdaj, Apple odložen.**
AAB29 teh sprememb ne vsebuje. Prvotna analiza zdaj povezuje zapis izvedbe;
nepovezan docs/SECURITY_REVIEW_2026_10_15.md ostane nedotaknjen.

16. oktober — **organizacijske preglednice in dokumentne priloge izvedene v izvoru**
po izrecnem naročilu. [Izvedba in meje](docs/TABLES_AND_ATTACHMENTS.md).
Razširljiva mreža, formule/SUM, izključni 90s zaklep z obnovo, lokalni osnutki,
offline ogled in šifrirana prenosna kopija7; priloge prostora/opravila/tabele,
20MiB/datoteko, zasebni prenosi, ACL/odvzem/brisanje/prijave vsebine.
Dodajalna FamilyHub shema19 je samo v izvoru; gostovanja niso nadgrajena.
1505 Flutter PASS/16 preskokov, zaključnih155 in54 ciljnih PASS;
723 novih strežniških kontrol na SQLite/MariaDB10.11/MySQL8.4,192 lifecycle
in162 Ideas PASS. Android debug PASS,94 PHP lint PASS, analiza samo10starihinfo.
Ni nove nameščene aplikacije ali izdajnega paketa; AAB29/SDK/locks/dovoljenja isti.
Pred izdajo potrebuje gostovanje svežo kopijo/pravo obnovo in shemo19,
FamilyHub novo različico ter Play Files/docs deklaracijo/pregled zasebnosti.
**Google Play ostaja odložen do nove izrecne potrditve; Apple še odložen.**
Nepovezana neversionirana docs/SECURITY_REVIEW_2026_10_15.md in
docs/INVITATION_AND_SHARING_UX_ANALYSIS.md nista del te izvedbe.

15. oktober — **ideja organizacijskih preglednic posebej zapisana** v
[opombah](docs/UPGRADE_NOTES.md#preglednice-v-organizaciji-15-oktober-2026):
razširljiva prazna mreža/besedilo/številke/osnovne formule/SUM. Predlog zaklepa
ene tabele med urejanjem z ogledom za druge, jasnim obvestilom, potekom in
zaščito osnutka; online urejanje/offline ogled je predlog za nadaljnji dogovor.
**Samo načrtovanje, brez naročila za implementacijo ali trgovinsko oddajo.**

15. oktober — **priloge so zabeležena predvidena nadgradnja**, ne trenutna
implementacija: nalaganje/pripenjanje PDF-jev, dokumentov in podobnih datotek.
[Opomba](docs/UPGRADE_NOTES.md#priloge-15-oktober-2026). Natančna mesta/prenos/
omejitve/pravice še določimo; preglednice in njihov zaklep so za zdaj samo
pogovor. Ni aplikacijske, strežniške ali trgovinske spremembe.

15. oktober — **ponovna povabila istemu e-naslovu združena v prikazu**.
[Dokazi](docs/INVITATION_RESEND.md). Po preklicu in novi izdaji v istem scopeId
nova vrstica »Ponovno poslano povabilo«, stare preklicane skrite; normalizacija
trim/lower, prava vloga/rok/status in točni ID preklica. Več še veljavnih
povezav ostane posamezno preklicljivih, legacy username/prostori/prejemniki ločeni.
35ciljnihUI PASS/10novih,320/390/1280SL/EN; analiza isti10prejšnjihinfo.
Samo UI/l10n, zgodovina in strežnik nespremenjena, brez dejanskega povabila ali
native gradnje. **Ni Google Play oddaje; potrebna je nova izrecna potrditev.**
AAB29 zamrznjen/isti, popravka ne vsebuje.

15. oktober — **kontrast zapolnjenih ikon popravljen v izvoru**: skupni Shrani
uporablja onPrimary tudi v AppBar, nakupi onPrimary, Idejnik onSecondaryContainer.
[Dokazi](docs/EDITOR_ICON_CONTRAST.md). Pred-fix dejanski kontrast1,03:1;
63ciljnihPASS/20novih primerov, svetla/temna in Android/iOS/macOS widgeti,
aktivne ikone vsaj4,5:1, indikator vsaj3:1, disabled/busy brez zapisov.
Analiza isti10prejšnjihinfo/brezwarningerror. Brez nove native gradnje,
spremembe verzije/strežnika/SDK/locks ali trgovinske oddaje. AAB29isti;
**Google Play še naprej samo po novi izrecni uporabnikovi potrditvi.**

15. oktober — **odprti deljeni projekt ima en združen meni** ob naslovu:
urejanje/arhiviranje/brisanje/prijava glede na obstoječe pravice; oblaček ostane.
[Dokazi](docs/PROJECT_MENU_FIX.md). Isti lifecycle handlerji in predogled izbrisa,
inline projekt cilja svojID namesto nadrejenega prostora, bralec samo prijavo;
36ciljnihUI PASS pri320/390/1280, analiza isti10info/brezwarningerror.
Popravek je samo izvor, brez native gradnje/strežnika/version/SDK/locks sprememb.
**Ni nove Google Play oddaje; ta še vedno zahteva novo izrecno potrditev.**
AAB29 ostane zamrznjen in teh zadnjih popravkov ne vsebuje.

15. oktober — **nova izrecna omejitev uporabnika za prihodnje izdaje**:
nadaljujemo lokalne popravke in spremljanje aplikacije, vendar **nove izdaje
v Google Play ne oddaj brez nove uporabnikove izrecne potrditve**. Prejšnje
splošno dovoljenje za javno objavo ne velja za naslednje popravke. Že oddana
Android1.9.1(29) ostane; uporabnik ni naročil njenega umika. Ne ustvarjaj
interne izdaje. Novo prijavljena težava: opravilo »Preizkus push« v Dom,
Planer/Opravila, nima delujočega preklopa zaključka v skupnem pregledu,
podrobnostih ali urejevalniku. Popravek je lokalno izveden: dejanski krogec/skupni pregled, detail checkbox in
status obstoječega task editorja.65ciljnihPASS/analiza10starihinfo brezwarningerror.
Točen lokalni/skupni/zasebni izvor brez menjave izbora, zaščita identitete/ACL,
READONLY/arhiv, busy/preurejanje, SQLite/outbox/rollback, Cancel in linkedcost.
[Dokazi](docs/TASK_COMPLETION_FIX.md). Verzija/SDK/locks/strežnik isti,
ni nove gradnje ali trgovinske oddaje; popravek NI v zamrznjenem AAB29.

15. oktober — **privzeti zvok vključen za nove/manjkajoče nastavitve, obstoječe ohranjene**.
[Dokazi](docs/release/DEFAULT_SOUND_1_9_1.md). Izrecni uporabnikov popravek:
vsak že shranjen true/false ostane, tudi stari materializirani false; brez
migracije/backfilla/čiščenja ali prepisovanja. Funkcionalnia51f98e/main,
51ciljnih PASS tudi v izoliranem izvoru,180PHP/MariaDB10.11.19 kontrol PASS;
analiza isti10info/brezwarningerror. Ena podpisana Android1.9.1(29),421vhodov,
SHA42cb5408…/istiSDK/locks/native/config/podpis/engine/8perms/16KiB/23+7PASS.
**Dejansko oddana javno: »Spremembe v pregledu«**,100%/Slovenija/29vključena/
28izključena/SLenUSopombe/0izgubljenihnovihnaprav/natanko1sprememba;
galerije/opisi isti, interni kanal ni uporabljen. Javna29/odobritev še NISTA
potrjeni. Svež Console potrdi prejšnjo28 javno od15okt07:58/100%/1država.
Javni FamilyHub59119dc/v0.14.1/ZIP8d756b75…102vnosov/90PHPisti/javni200hashCRC.
Produkcija/test1 dejansko0.14.1/schema18: natanko3PHP zamenjani, zasebni stari101
viri ohranjeni;93tabel376/337vrstic,3računi4/9naprav,21/1surove preference
bajtnoiste, config/gesla/ključi/data/core/cron/modeisti. Checkpointcomplete,
HTTPS200/istiSID/enabled/push2, brezSQLUPDATE/DDL/workerbootstrap ali nove
uporabniške dostave. Pomočnikova realna sintetična vaja+4negativnavarovalaPASS.
Test2 ostane isti; Apple/TestFlight izrecnoodložen, Windows/Linuxkasneje.
Fizični zvok29 ni preverjen; stare uporabnikove izklope ohrani.

15. oktober — **Android1.9.0(28) dejansko oddan za javno posodobitev z novima SL/ENgalerijama; Appleodložen**.
[Dokazi](docs/release/UPGRADE_1_9.md#portala). Na uporabnikovo zahtevo uporabljen
Codexvgrajenibrskalnik/prijavljeniTaknDevs; istiAAB28/SHA347d6d8b… uspešno
naložen prek običajnegafilechooser, brez spremembe dovoljenj ali novegradnje.
BravefileURLzahteva je odveč. Javni4698247597354229997/release4,28vključena/
27izključena/100%/obstoječa1državaSlovenija/SLen-USopombe;0izgubljenih/0novih
naprav. Obe galeriji8novih720×1280 slik:Utrip/opravila/Idejnik/Vrt/projekt/
nakupi/koledar/finance; ENlastniangleškiprizori/bajtnoenakeprefiksanekopije.
Stari elementi ohranjeni v knjižnici, ikona/featureisti. Ohranjenaprejšnja
kratka/celotnaopisaSLenUS tudi vključena, skupno7sprememb dokončno potrjenih.
**»Spremembe v pregledu« potrjeno04:44UTC15okt**, hitrapreverjanjašetečejo/
upravljanoOFF/objavapoodobritvi. **Odobritev/javna28šeNIPOTRJENA**, doslej
javna27ostane. Internikanalostajaneaktiven/nobeneinterneizdaje. Posnetek
android-public-28-submitted.png in besedilni dokazvbuild/qa/upgrade-release-20261014.
Uporabnik **izrecnoodložiAppleTestFlightinželisamoAndroid**: iOS28žeuploadcomplete,
vtemkorakuniAppleposega/CompleteTesting28dokaza/alijavneoddaje. Nobenega
ponovnegaciklusa gradnje/testov/strežniškemigracije. Koda/SDK/locks/dovoljenja/
končniAAB/IPA/prod+test1schema18/test2/splet soisti; naslednjeizidGooglovegapregleda.

15. oktober — **produkcija in pregledni test1 dejansko nadgrajena na0.14/schema18; iOS28naložen**.
[Strežniški dokazi](docs/server/UPGRADE_0_14.md), [izdaja](docs/release/UPGRADE_1_9.md).
Po odklenitvi novi ločeni capture/kopiji/resnični MariaDB10.11.19obnovi
networknone/noports/nobinds: prod92tabel322vrstic2DATA/SHA44eb4355…;
test1 92tabel313vrstic2DATA/SHA823a8681…. Stage/apply/verify/release PASS;
4stolpci+1prazna tabela/101source; vsi zgodovinski zapisi/gesla/naprave/
config/ključi/core/HTTPS/originalcron ohranjeni. Oba checkpointa released/
APIpausedfalse/workerCronRestoredtrue, javniAPIHTTPS200/istiSID/enabled/
novi kontrakti/push2. Produkcija3računi4naprave, test1 3računi8naprav; test2
nespremenjen. Stara abort mapa ni uporabljena za migracijo; stara319kopija
zdaj tudi resnično obnovljena izključno kot zgodovinski dokaz.
Xcodeobstoječicloudpodpis/profil26.9.2027/StoreIPA28.211.421B/SHA1f4564d1…
CRC/strictdeep/productionAPS/18privacy/DartFirebase PASS; isti6cearhiv
Organizer **uploadcomplete**, brez nove gradnje. AppleComplete in
TestFlightTesting28 še nista potrjena; uporabnik potrebuje spletno prijavo
vSafari. Androidrelease4 javni osnutek z SL/en-USopombami shranjen; **AAB28
ni naložen/oddán**, slike niso naložene. Razširitev zahteva dovoljenje
»Allow access to file URLs«, običajniOSpickerOpen ostaja onemogočen;
zahtevano uporabnikovo dejanje z razlago dostopa. Agent ni spreminjal
varnostnih dovoljenj. JavniAndroid27ostane, interniNeaktivno; iOSsamoTestFlight.

15. oktober — **novih 48 trgovinskih zajemov pripravljenih**, po izrecnem
naročilu med čakanjem na odklenitev Maca. [Zapis](docs/release/UPGRADE_1_9.md#novi-trgovinski-posnetki),
[manifest](docs/release/UPGRADE_SCREENSHOTS_1_9.json). Osem dejanskih prizorov
(Utrip/opravila/koledar/Idejnik/projekt/nakupi/Vrt/finance) × SL/EN × Android
telefon/iPhone/iPad; 720×1280/1320×2868/2064×2752. Ločeni sintetični pomnilniški
podatki, brez nameščene aplikacije ali strežniških zapisov. Vrt ima dejansko
potisnjeno pot in vrnitev, običajne sence/pisave; iPad pravo širšo postavitev.
18 capture PASS, tri ciljne analize čiste, vseh 48 vizualno pregledanih;
validator vseh 421 izdajnih vhodov isti kot 6ce59cf, dimenzije/neprosojnost/
različnost/49 ZIP CRC vnosov PASS. ZIP v build/releases s SHA a8a342e4…;
PNG-i v build/qa/upgrade-store-20261015. **Ni nove aplikacijske gradnje ali
spremembe AAB28/IPA, ni nalaganja novih slik ali trgovinske oddaje.**
Mac/strežniška obnova in oddaji ostajajo odprti koraki prejšnjega zapisa.

15. oktober — **vseh19 naročenih nadgradenj lokalno izvedenih in poslanih na main**.
[Izvedba](docs/UPGRADE_IMPLEMENTATION.md), [izdajni status](docs/release/UPGRADE_1_9.md).
Končni runtime6ce59cf/1.9.0+28: vrt/celozaslonska rast/grede/metri/zgodovina,
Idejnik/pinch/velikost/arhiv, rokiopomnikov, hierarhija/projektni editor,
članstva/brisanje/ownrecovery/earlyfinanceACL, nakupi/fokus/obvestila, gesla
in stabilne nastavitve opomnikov. Celotni7af1298PASS/15skip, zaključni62UI+27Darwin
PASS; analiza10prejšnjihinfo/brezwarningerror. Tretji zamrznjeni6ce kandidat
421/308runtime, AAB28SHA347d6d8b…/podpis/Firebase/8perms/16KiB/23+7PASS; iOSarhiv
in svežiMacDebugPASS,3gradnje/platformo, prvi2zavrnjeni/ohranjeni. **NiAAB28
uploada, IPAizvoza/TestFlight28 ali javne28oddaje.** Maczaklenjen; lastnik
potrebujeodklenitev zaobičajniOrganizer/portala. Windows/Linuxodložena.
FamilyHubjavni dd81e061/v0.14.0/schema18/paketSHAe6fda75…dejanskoobjavljen,
v0.13tagohranjen; živa produkcija/test1ostajata0.13/schema17. Produkcijski
svežicapture/prepare/pause503/65svarovalo/real92tabel319vrstic2DATAkopija
PASS, vendarBraveblokiraZIPprenos, pravaizoliranaobnovaNIcončana. **NobeneDDL
aliCodeSwap.** Pregledaniabort.php/shdejanskoobnoviAPI200/old96/schema17/
isteključe/config inbajtnioriginalcron22:21:27UTC14okt; zasebnabackup/state
ohranjena. Navadniindex302normalen;API200preverjenstrogoTLS/istiSID.
Prednadaljevanjempotrebninovcapture/pause/freshkopija/pravaobnova; stare
abortmapeNEuporabi zamigracijo. Test1/test2nespremenjena; produkcija
SMTP/FCMspetoriginaldelavci. **SvežPlayread-onlypotrdi1.8.0(27) javno
Na voljo vGooglePlay,100%/1država od14okt21:42**, release3;27ni večpending.
InterniAndroidostajaizključen/Neaktivno; vseprihodnjeoddajeizključnojavne.

14. oktober — **Android1.8.0(27) dejansko oddana za javno posodobitev** po
izrecnem naročilu, interni kanal potrjenoNeaktivno. [Dokazi](docs/release/REMINDER_SETTINGS_RELEASE.md).
Nastavitve opomnikov44bdd2b na izolirani mobilniAAB26osnovi/fa809b8+6ae5667,
6majhnih mobileShell prenosov; namizna prenova ni vključena.104ciljnihPASS
v dejanskem izoliranem izvoru/Noissues/23+7izdajnihPASS. Ena podpisanaAAB27,
323frozeninputs/19spremenjenih, oba locks/3config hash isti, byte-identical
Flutterengine/isti cert/Firebase/8dovoljenj/bundleCRC/16KiB PASS.78.476.231B,
a8a328e0…; prejšnjiAAB26ohranjen. Produkcija4698247597354229997/release3,
27vključena/26izključena,100%/Slovenija/SLen-USopombe/0novihizgubljenih
naprav. Ena sprememba dokončno potrjena: **Spremembe v pregledu**, hitra
Googlova preverjanja še tečejo; upravljanoOFF/objava po odobritvi.
**Ni potrjene odobritve/javne27/fizičnega novegaUI**, prej javna26ostane.
Interni4701286726300038561Neaktivno, brez nove interne izdaje ali nadaljevanja.
SDK/native/dovoljenja/gostovanja/FamilyHub/sheme/podatki/SMTPFCM/splet/Apple
isti; naslednje izid Googlovega pregleda, ne nova oddaja ali splošna matrika.

14. oktober — **Več → Nastavitve opomnikov lokalno izvedeno** po izrecni
uporabnikovi izbiri enega zaslona. [Dokazi in semantika](docs/REMINDER_SETTINGS.md).
Zgoraj množični preklopi trenutnih dovoljenih obsegov/kategorij, spodaj lokalni
prostori/projekti in skupni kanonični obsegi, vrste tudi Ideas; naprava/status
na istem zaslonu. Stara ločena razdelka odstranjena iz splošnih Nastavitev.
Lokalne izjeme dejansko uskladijo alarm/zvok in center/neprebrano; skupni
zvok brez druge lokalne zvočne zavore. SQLite batch/vrsta/ACK/rollback,
identiteta pred zapisom in pozne napake; validator kopije sprejme Ideas.
**104 ciljnih Flutter PASS**, ozki320/390 in1280/2×, pregledan390widgetizris,
Android debug PASS; analiza samo10prejšnjih info vtools/release. Obstoječi
opt-outi in legacy nastavitve ostanejo. Množično velja za trenutne skupne
obsege, novi lokalni dedujejo napravo; ne trdi, da strežnik hrani nov globalni
profil. **Ni nove trgovinske izdaje/fizičnega novega UI**; Androidjavni26/
interniNeaktivno/FamilyHub/sheme/gostovanja/SDK/locks/dovoljenja/splet/Apple
isti. Naslednji izdajni korak izključno javni, po naročilu, ne interni kanal.

14. oktober — **produkcijski FCM vključen, Google OAuth/validate_only200 in
dejanski push cron PASS**. [Dokazi](docs/server/PRODUCTION_PUSH.md). Lastnik
izrecno potrdi novi jivie-production-fcm-sender/FCMAPIAdmin/enJSONključ,
obstoječi testni sender isti. Ključ0600/zasebne0700 zunaj vseh15 rootov,
isti pregledani helper check/prepare/lint/activate in offline preflight PASS;
ločen32-byte pushkey, SMTPinclude ohranjen. Istiad569ID, HTTPS200/externalPush/
smtp/email=true; en nov minutely flock worker, stari cron bajtno ohranjen,
dejanski dnevnik46s/vsi števci0. Google validacija ne dostavi obvestila.
**Fizični prikaz še ni potrjen**: lastnik odstranil Android/pozabil geslo;
pojasnjena admin menjava istega anze.novsak (users.password), agent gesla ni
spreminjal. Lastnik nato potrdi uspešno prijavo in »Naprava je registrirana«,
read-only baza1aktivniAndroid za isti projekt. Pripravlja pravi oddaljeni
opomnik izUI; fizična dostava še sledi, ne nova
matrika/gradnja. Androidjavni1.7.1(26)/interniNeaktivno/FamilyHub0.13/schema17/
podatki/splet/test1/test2/Apple isti; APNs/redne kopije še ločeno. SMTPhelper
po FCMinclude/cron spremembi namerno zavrne nove hashe; ne obnavljaj starega
stanja ali rahljaj varoval. Povabilo ima HTTPS/deeplink, še nima Playinstall
povezave; besedilo ni spremenjeno.

14. oktober — **produkcijski pravi Android opomnik samodejno sent, fizični
prikaz/odpiranje potrjena**. [Dokazi](docs/server/PRODUCTION_PUSH.md). Lastnik
obnovi geslo sam, prijava/registracija PASS; read-only1Android/1pending, nato
1delivered/1sent/attempts1. Brez ročne dostave ali dodatnega obvestila. Lastnik
»dubu sm obvestilo, lahko ga odprem«, zvoka ni. Dom/reminders nima shranjene
preference, dejanski resolver sound=false; splošni »Opomniki na tej napravi«
zvok je lokalen. Naročeno Dom→Nastavitve obvestil→Opomniki→Zvok opomnikov;
shranitev in fizični zvok še sledita. Ne spreminjaj Androida ali ponavljaj
matrike; naslednje samo1zvočni preizkus. Povezava do opomnika je za urejevalca
ločeni zvonček splusom ob vrstici; prejšnja ⋯usmeritev popravljena.

14. oktober — **iOS1.7.1(26) dejansko AppleComplete/TestFlightTesting**.
[Dokazi](docs/release/IOS_CONNECTION_RELEASE.md). Lastnik potrdi namestitev25
in naroči isti popravek povezovanja kot javniAndroid26. Izoliranifa809b8+
6ae5667/version,285skupnih vhodov isti kotAAB26,333frozen/48native/oba locks/
SDK/18privacy/Firebase isti;7ciljnihPASS. Sveži arhiv/obstoječi cloudpodpis,
IPA c98d7f0e…/CRC/strictdeep/productionAPS PASS; upload16:24/buildb4430…Complete.
Lastnik sam sprejme novo13.10 razvojno pogodbo; StandardEncryption+FranceNo
shranjen. Predjavnoobjavo1tester/2builds:26Testing,25ohranjen; kratka navodila
shranjena. ASC1.7.1/build26Saved, pregledno geslo zdaj prisotno (samo bool,
brez branja/izvoza, pravilnost ni preverjena). **Ni javne iOS oddaje ali
fizičnega26/APNs dokaza**; naslednje ciljni iPhone tok in pregledni dostop/
oddaja. Android26/javni status/interniNeaktivno/splet/gostovanja/FamilyHub/
podatki ostajajo; sočasno produkcijskoSMTP delo ni del te iOS nadgradnje.

14. oktober — **produkcijski SMTP dejansko vključen in prejem v Prejeto potrjen**.
[Dokazi](docs/server/PRODUCTION_MAIL.md). Lastnik izbere obstoječi predal
admin@jivie.triparna.si in sam vnese geslo v skrit terminalski poziv, brez
branja/izpisa/klepeta/Git. Pravi tripar13, zasebna primerjana kopija obeh
konfiguracij/crontaba; TLS/prijava cp-21:465 PASS, ločeni32-byte mail ključ,
datoteke0600/imeniki0700. Vključeni smtp/emailInvitations/emailVerification/
passwordReset, isti ad569serverId; oba nova minutely mail workerja exit0,
cron dnevnika48s/0600, stare vrstice ohranjene. SPF/DKIM/PTR že veljavni,
dodan samo DMARC p=none za poddomeno (isti kot nadrejena politika). Natanko
eno benigno testno sporočilo lastniku, fizično »Prispelo v Prejeto«; brez
dejanskega povabila/registracije/reset sprememb.7 lokalnih varoval/PHP lint
PASS. FamilyHub0.13/schema17/računi/vsebina/AndroidAAB26/Console/splet/iOS/
test1/test2 isti. FCM in redne produkcijske kopije še ločeno odprto delo.
Kopija konfiguracije ni kopija podatkov; poštni ključ ohrani za pending vrste.

14. oktober — **Google Play povezava dejansko objavljena na jivie.app SL/EN**.
Uvodni in zaključni gumb na obeh domačih straneh ter povezava v nogi vseh8
strani odpirajo javni `si.triparna.jivie`. Besedilo odraža javni Android v
Sloveniji, iOS ostane v pripravi. Sveža zasebna kopija25 datotek dejansko
preverjena; objavljenih8 HTML,17 drugih datotek/pravice/lastništvo ohranjenih.
Vseh8 HTTPS200/hash PASS, ozka390/320 prikaza brez prelivanja; dejanski klik
odpre Jivie/TaknDevs/Namesti in opombe popravljene26. [Dokazi](docs/release/WEBSITE_GOOGLE_PLAY_LINK.md).
Android/AAB26, Console, FamilyHub, gostovane aplikacije in podatki ostanejo isti.
Prihodnje Android izdaje še vedno izključno javne, interni kanal Neaktivno.

14. oktober - **javni Android1.7.1(26) dejansko Aktivno / Na voljo vGooglePlay od05:48**, sveze prebrano v produkciji4698247597354229997/release2. [Dokazi](docs/release/PUBLIC_CONNECTION_UPDATE.md#confirmed-public-availability---14-october). Google je prej oddano26 odobril/objavil; ni nove oddaje/gradnje.1drzava/regija, istaAAB26/hash; interni kanal ostaja po narocilu Neaktivno. Starejsi pendingReview26 je zgodovina. User po lastni izjavi brez podatkov odstrani app in izstopi iz preizkusa; njegovPlay se kaze beta naslov/stare slike. Razsiritev izstopa ni fizicno potrjena; svetovano samo PlayStorecache/javniURL. Prihodnje Android izdaje izkljucno javne, brez ponovnega splosnega testnega kroga. Koda/SDK/locks/dovoljenja/gostovanja/FamilyHub/podatki/iOS/splet isti; SMTP/FCM/kopije se loceno delo.

14. oktober — **ista Android1.7.1(26) dejansko oddana za javno posodobitev;
interni kanal Neaktivno**. [Dokazi](docs/release/PUBLIC_CONNECTION_UPDATE.md).
Uporabnik fizično potrdi »Ok, zej povezovanje dela«. AAB26/hashisti brez nove
gradnje/promoviran iz knjižnice v produkcijo4698247597354229997/release2,
100%/samoSlovenija, SL/en-USopombe; samo1sprememba končno potrjena in **Spremembe
v pregledu**, hitra Googlova preverjanja še tečejo. UpravljanoobjavljanjeOFF,
objava po odobritvi; **javna26/odobritev še nista potrjeni**, javna25 ostane
aktivna. Interni4701286726300038561 potrjeno začasno zaustavljen/Neaktivno,
brez izbrisa paketov/zgodovine/testerjev. **Nova uporabnikova usmeritev: vse
prihodnje Android objave izključno javne; ne ustvarjaj internih izdaj in ne
nadaljuj internega kanala brez novega izrecnega naročila.** Lokalni ciljni testi
in preverjanje artefakta ostanejo. Izvor/SDK/locks/dovoljenja/gostovanja/
FamilyHub/podatki/iOS/splet isti, brez nove matrike; SMTP/FCM/redne produkcijske
kopije še ločeno odprto delo. Naslednje izid javne posodobitve26, ne nova oddaja.

14. oktober — **Android1.7.1(26) dejansko Aktivno za domači(15) od05:24**,
[Dokazi](docs/release/SPACE_CONNECTION_RELEASE.md). Popravek6ae5667 po potrditvi
predogleda povezovanja lokalnega gospodinjstva/organizacije odpre obstoječa
pravila strežnika; izrecni sprejem nadaljuje isto publikacijo enkrat, preklic
in menjava računa ohranita lokalno vsebino brez prenosa. Pre-fix regresija FAIL,
29ciljnihUI/podatkovnih PASS,7isti testi tudi v izoliranem izvoru PASS; ciljna/
izolirana analiza Noissues (main10prej obstoječih info v screenshottools).
Ena podpisana AAB26 iz izoliranegafa809b8/AAB25 plusnatanko1runtimepopravek+
version;320zamrznjenih vhodov, oba locks/SDK/confighashi/isti podpis/Firebase/
8dovoljenj, bundle/CRC/16KiB/23+7source PASS. Desktop spremembe niso vključene.
26vključen/25izključen v novi interni izdaji,0novih/izgubljenih naprav. Fizični
preizkus uporabnika še sledi; produkcijskiSMTP/FCM šeOFF, gostovanja/sheme/
podatki/iOS25/splet/javniFamilyHub isti. **Svež read-only Console potrdi tudi
javno1.7.0(25) Aktivno/Na voljo vGooglePlay od14.okt04:52**, ena država/regija;
Google je sam zaključil prejšnjo oddajo, starejši »v pregledu« je zgodovina.
Javna izdaja ni umaknjena/nadomeščena v tem koraku,26je samo interna. Uporabnik
naroča najprej fizični preizkus26, nato javno posodobitev/umik aktivne25.

14. oktober — **iOS App Privacy dejansko objavljen, TestFlight povabilo Invited**.
[Dokazi](docs/release/IOS_PUBLIC_PREPARATION.md). Lastnik je sam potrdil Publish;
agent je preveril vidno Published by Anže Novšak. Po izbiri »isti račun« dodan
samo obstoječi lastnikov Account Holder/Admin v Pred javno objavo: **1tester/
1build25**, brez novih upravljavskih pravic; prihodnje samodejne gradnje OFF.
E-poštna dostava/sprejem/fizična namestitev še niso potrjeni. Naslednje kratki
iPhone tokovi, pregledno geslo neposredno vASC ter končna oddaja. **Ni javne
iOS oddaje ali fizičnega/APNs dokaza**. Android/paketi/koda/SDK/locks/dovoljenja/
strežniki/podatki ostajajo isti; starejši pendingPrivacy/0tester zapis je zgodovina.

13. oktober — **iOS1.7.0(25) dejansko naložen in AppleComplete** iz istega
mobilnegafa809b8 kotAndroid25. [Dokazi](docs/release/IOS_PUBLIC_PREPARATION.md).
283lib/assets hashi/oba locks isti; sveži arhiv, Organizerobstoječi cloudpodpis
do26.9.2027, izvoženIPA7df6c483…/strictdeep/CRC/productionAPS PASS,18 SDKmanifestov.
CLI NoAccounts je obit po običajni prijavljeni XcodeUI poti, brez novihključev.
Applebuild4abbd687… jeReadytoSubmit/Test poStandardEncryption+FranceNo;
ni lažnegaNoEncryption ali slepegaInfo.plistfalse. ASC1.7/SLenopisa3391/3475,
14 sprejetih iPhone/iPad widget slik z odprto tablo,0EUR/samoSlovenija/
AvailableonAppRelease/18+ in kontakt/navodila/build25so shranjeni.
InternaPredjavnoobjavo ima1build/**0testerjev**, AppleIDše čaka. AppPrivacy12
vrst je dokončanpredlog brezTracking; **končniPublish čaka izrecno potrditev**
zaradiApplovega soglasja o točnosti/pravilih/posodabljanju. ReviewerUsername
je pripravljen, **geslo mora lastnik vnesti neposredno vASC**, ne klepet/Git.
**Ni javne iOS oddaje ali fizičnega iPhone/APNs dokaza**; naslednje pending
potrditve/TestFlight/fizični ključni tokovi/končna oddaja. AndroidAAB25/hash,
njegova oddaja, SDK/locks/dovoljenja/namestitve/gostovanja/podatki ostanejo.

13. oktober — **produkcija jivie.triparna.si dejansko FamilyHub0.13.0/schema17**,
po uporabnikovi novi Kanboard1.2.54 namestitvi. [Dokazi](docs/server/PRODUCTION_SETUP.md).
Sveža dejanska kopija in izolirana MariaDB10.11.19 obnova PASS:48tabel/40vrstic/
2datoteki; vsi row/CREATE/config/cron hashi. Po65sdrain migracije do17,92tabel/
44FH, **0Native računov/0naprav/nič uporabniške vsebine**; jivie_admin ohranjen,
47starih tabel/2100core datotek isti,96plugin datotek točnih. Novi serverId
ad56910f-ca2e-41ee-af0d-3f18081497cf. Zasebni config/data0600/0700 izven15docrootov,
HTTPS200/capabilities Ideas/assets/reports/enrollment in anonimni401 PASS.
2nova minutely workerja, stari crontab ohranjen, sveža dnevnika. Prvi račun še
ni ustvarjen; odprt FamilyHub enrollment, kode/gesla določi lastnik. Native
admin login pred prvim računom ne izvajaj. **SMTP/FCM OFF; email povabila/reset
in oddaljeni push še ne delujejo**, redne kopije še niso nastavljene. Kopija je
prednamestitvena, ne kopija prihodnjih uporabnikov. Pomočnik208kontrol PASS,
celotna Softaculous predloga in javni PLUGINS_DIR popravljena pred migracijo.
AndroidAAB25/test1/test2/app/splet/javni plugin repo ostajajo isti. Naslednje
prvi račun, produkcijska pošta/push/redne kopije, ne nov splošni testni krog.

13. oktober — **prva javna Android1.7.0(25) izdaja za Slovenijo je dejansko
oddana**. [Dokazi](docs/release/PUBLIC_ANDROID_SLOVENIA.md). Produkcija4698247597354229997/
release1 uporablja isti knjižničniAAB25/hash; samoSlovenija, uvajanje za vse,
SL/en-US začetne opombe. Sveža opisa3391/3475 ustrezata izvoru,7slik ostane.
Končni potrditveni gumb za11sprememb pritisnjen; Console **Spremembe v pregledu**.
Hitra samodejna preverjanja še tečejo pred dejanskim pregledom. Upravljano
objavljanjeOFF: objava po odobritvi; **odobritev/javna dostopnost še ni potrjena**.
Brez nove gradnje, izvornih/SDK/locks/dovoljenj/strežnikov/podatkov/Mac sprememb.
Naslednje izid Googlovega pregleda, ne ponovna oddaja ali nov splošni testni krog.

13. oktober — **FamilyHub povezava in razlaga lastnega strežnika sta objavljeni
na jivie.app SL/EN; oba Play opisa sta shranjena kot osnutek**.
[Dokazi](docs/release/FAMILYHUB_WEBSITE_AND_PLAY.md). Uporabnik je po premisleku
potrdil brezplačen Jivie + brezplačen javni FamilyHub pod MIT, pozneje izbirno
plačljivo upravljano gostovanje; repo je sam ponovno odprl, anonimno potrjen.
4 HTML objavljeni po preverjeni kopiji25 datotek,21 drugih datotek/pravice
ohranjene;4 HTTPS200/hash PASS. SL3391/en-US3475 znakov po reloadu enakih izvoru.
Odprtokodnost je izrecno samo FamilyHub. Ista Android AAB25/hash, brez nove
gradnje, gostovane nadgradnje ali javne oddaje. Naslednje države/Pregled objave.

13. oktober — **FamilyHub0.13.0 dejansko javno objavljen** v uporabnikovem
[kotlet13/kanban_family_hub](https://github.com/kotlet13/kanban_family_hub),
main/root commit7571d1b brez staršev in tagv0.13.0. [Dokazi](docs/release/FAMILYHUB_PUBLIC_REPOSITORY.md).
MIT s TriparNA copyrightom ohranjena byte-identical; Kanboard1.2.54 MIT preverjen,
plačljivo gostovanje/podpora dovoljeno, brez izključnega gostovalnega monopola.
105 dovoljenih javnih datotek,87 PHP byte-identical preverjeni izdaji; PHP88
tokenizer PASS, vseh97 ZIP vnosov/CRC/bajtov in anonimni HTTPS200 PASS. Javni
README/NOTICE/config.example brez gesel/docs/tools, brez appGit zgodovine,
konfiguracij/ključev/SQL/podatkov/kopij/internih pomočnih namestitev. Lokalni
repo `/Users/anzenovsak/Git/kanban_family_hub`; javni ZIP b90c73a7… pod dist/tagom.
Git noreply samo v novem repozitoriju; drugih identitet ne spreminjaj. Ob prihodnji
izdaji sinhroniziraj pregledani javni repo in nov tag, ne prepiši v0.13.0.
AndroidAAB25/SDK/locks/dovoljenja/živa gostovanja/podatki/Mac/splet/Console isti;
naslednje ista mobilna AAB25/države/Pregled objavljanja, ni nove funkcionalne matrike.

13. oktober — **odprta tabla Idejnika dejansko dodana na jivie.app SL/EN in
Google Play**: fotografija, vezana rdeča oznaka, risba police in lističa;7/8
telefonskih slik v shranjenem osnutku in8 spletnih posnetkov. En-US podeduje isto
galerijo; shranitev preverjena po reloadu. [Dokazi](docs/release/IDEAS_BOARD_SCREENSHOT.md).
720×1280 neobrezan widget izris iz izoliranega fa809b8/AAB25,283 javnih
lib/assets hashov PASS; dejanska foto normalizacija/cache/uredljivi elementi.
Vzorci samo v pomnilniški SQLite, ne v nameščeni aplikaciji ali strežniku.
Sveža spletna kopija24 datotek dejansko preverjena, objavljeni2HTML+PNG,
22 drugih datotek/pravice ohranjeni,3 HTTPS200/hash PASS. Android1.7.0(25)
AAB/izvor/SDK/locks/dovoljenja/FamilyHub/podatki/Mac nespremenjeni; ni javne oddaje.
Naslednje ista AAB25/države/Pregled objavljanja, ne nov splošni testni krog.

13. oktober,19:48 — **pregledni test1 FamilyHub0.13/schema17 in Google navodila
dejansko shranjena**. [Dokazi](docs/release/REVIEW_SERVER_UPGRADE.md). Sveža
dejanska kopija/izolirana MariaDB10.11.19 obnova:86 tabel/295 vrstic/2 datoteki/
2 imenika, vsi row/CREATE/config/HTTPS/cron/file hashi PASS. Po resničnem65s
drain sta nameščeni migraciji16/17, natanko6 praznih tabel,92 skupaj/96 datotek;
3 računi/7 naprav/isti95c1serverId/gesla/seje/config/DATA/core/SMTP/FCM/cron
ohranjeni, stare kode/kopije zasebno. Native HTTPS200/record5/Ideas/assets/prijave,
politika200 in anonimni slike/sync401. Macov jivie_review ohranjen, Idejnik in
dejanski report preview PASS, Usklajeno/0 čakajočih/spornih/zadržanih. Brez oddaje
prijave, admin ukrepa, sprejema pravil ali nove table/fotografije. Navodila476/500
v Console shranjena in ponovno preverjena; isto ime/geslo/URL. Android1.7.0(25)
AAB hash isti, app izvor/SDK/locks/dovoljenja/test2/produkcija/splet nespremenjeni.
**Naslednje javna izdaja istega AAB25, države in Pregled objavljanja**, ne ponoven
splošni testni krog. Javna oddaja/Googlova odobritev še nista izvedeni.

13. oktober — **Google Play pregledna prijava `jivie_review` na Macu PASS**, tudi
po ponovnem zagonu; dejansko vidni projekt/opravilo, nakupi in vzorčni odhodek
5 EUR. [Dokazi](docs/release/MAC_REVIEW_LOGIN.md). Nepodpisani desktop QA paket
ni imel Keychain dovoljenj; isti prevedeni paket je zdaj podpisan z obstoječo
identiteto/profilom/skupino, deep strict PASS in 315 izvornih vhodov nespremenjenih.
Paket `build/qa/review-access-mac-20261013/SignedProducts/Debug/Jivie.app` je odprt
s preglednim računom; geslo je vnesel uporabnik, ni prebrano/izvoženo. Console
navodila še kažejo test1 (record1–4, brez Ideas/prijav); test2 podpira aktualne
funkcije. **Pred oddajo uskladi pregledno gostovanje/navodila**, ne nov splošni
testni krog. Strežniki/Console/Android1.7.0(25)/izvor/SDK/locks ostajajo isti;
ni javne oddaje, nove Android gradnje ali vključitve zasebne sinhronizacije.

12. oktober,22:08 — **Data safety za Android1.7.0(25) dokončno shranjen v
Pregled objavljanja**, vseh11 vrst/podatkovni nameni/izbirnost potrjeni v
razširjenem predogledu. IARC je žeKončano; po končnem Shrani začetni seznam
10/11 izgine in izdajni koraki niso več zaklenjeni. To ni oddaja v pregled
ali javna objava. [Dokazi](docs/release/ANDROID_PHOTOS_DATA_SAFETY.md#koncna-shranitev-za-android17025).
Naslednje: preverjen Googlov dostop ter javna izdaja iste AAB25/države/povzetek.
Android/strežniki/desktop koda/SDK/dovoljenja niso spremenjeni v tem koraku.

12. oktober — uporabnik je naročil **namizno postavitev macOS/Windows/Linux**,
macOS UX najprej. [Izvedba](docs/DESKTOP_UX.md): neposredna prilagodljiva stranska
navigacija, iskanje dovoljenih izvornih zapisov, podrobnosti ob vsebini z lastnim
Navigatorjem, platformni meniji/⌘ oziromaCtrl ter namizni Utrip/projekti/finance/
Idejnik. Glavni Več ostane mobilni; namizni pripomočki so neposredno dosegljivi.
Osnutek se ne zamenja z drugim zapisom ali izgubi med navigacijo/resize; menjava
prostora potrebuje Shrani/Prekliči, varnostni preklic zapre le podrobnosti.
Računi/povabila/potrditve ostanejo modalni. Native namizno okno ostane namizno
tudi pri640×480; veliki mobilni prikazi ostanejo isti. **695 UI/projekcija/tema
PASS /1 opt-in skip**, dodatni640×480/2× PASS, analiza brez ugotovitev, sveža
izolirana macOS Debug gradnja PASS(brez podpisovanja). Običajna gradnja je imela
starXcodemodulni cache; svežDerivedData reši brezSDK/dependency sprememb.
Windows/Linux nativegradnji, fizična namizna uporaba/bralniki niso preverjeni.
Verzija ostane1.7.0+25, ni nove trgovinske/mobile/spletne izdaje ali namestitve.
Aktivni AAB25 ostaja prejšnji izvorfa809b8; gostovanje/FamilyHub/podatki/sheme/
kopije/SDK/locks/poverilnice/dovoljenja so nespremenjeni.

12. oktober,21:38 — **IARC za Android1.7.0(25) dejansko Končano**, PEGI3/
Interakcija uporabnikov; prijava uporabnikov/vsebine popravljena naDa.
Korak1 je že končan, novega sprejema pogojev ni bilo; končni povzetek shranjen
v Pregled objavljanja, ne celotna oddaja Googlu ali javna mobilna objava.
[Dokazi in matrika](docs/release/IARC_1_7_0.md). DataSafety še potrebuje končno
shranitev. Koda/gradnja/dovoljenja/strežniki/Apple in tekoče desktop spremembe
ostanejo; uporabljamo isto AAB25, ne ponavljamo funkcionalnega testnega kroga.

12. oktober,21:04 — nova interna **Android1.7.0(25) je Aktivno** za isti domači(15).
Vsebuje enoten Utrip/Planer/Prostor/Več iz50fd551. Ena podpisana AAB25,320
zamrznjenih vhodov, isti upload podpis/Firebase/8 dovoljenj kot24; bundle/CRC/
16KiB/23+7 izdajnih kontrol in source checker PASS. Prejšnjih651 funkcionalnih
PASS/1skip in čiste analize ne ponavljamo. [Dokazi](docs/release/UNIFIED_UX_RELEASE.md).
Po nadaljnjem naročilu **jivie.app dejansko posodobljen**:8HTML/CSS/7 novih
posnetkov, vseh16 HTTPS200 in točen hash. Sveža zasebna kopija17 datotek
dejansko preverjena;8 drugih datotek/config/.htaccess ohranjenih. SL/EN
zasebnost/izbris imata isto vidno vsebino. [Spletni dokazi](website/README.md).
6 novih720×1280 Android widget posnetkov in SL/en-US opisa dejansko shranjenih
v Play osnutek; stare slike ostanejo v knjižnici. Posnetki uporabljajo izolirane
vzorčne podatke; niso dokaz fizičnega telefona. Fizična nadgradnja25 še sledi.
FamilyHub/test2/produkcija, podatki/sheme, SDK/locks/iOS/Mac in javna mobilna
oddaja niso spremenjeni. DataSafety/IARC ostajata ločeno odprto delo.

12. oktober — uporabnik je naročil skupen Android/iOS UX in podagente Sol6.1/high.
**Utrip · Planer · Prostor · Več** so izvedeni kot štirje stalni cilji; ta usmeritev
ima prednost pred starejšim telefonskim predalom. Planer: Opravila/Koledar/Idejnik.
Prostor: projekti/finance ter področja vrste prostora; vrt ostane lastna domena.
Utrip uporablja dejanske dovoljene podatke danes/naslednjih7dni/projekti/opravila.
Nevtralna svetla/temna tema z modrim poudarkom, platformna tipografija/prehodi,
48-točkovni dotiki in prilagoditev 2× besedilu. Ne vračaj stalnih zastavic,
navpičnih editor dejanj ali raztezajočega statusa sinhronizacije.
**651 UI/projekcija/tema PASS /1 opt-in preskok**, analiza brez ugotovitev,
Android debug/iOS simulator gradnji PASS;28 widget posnetkov z izoliranimi
testnimi zapisi. [Dokazi in meje](docs/UNIFIED_MOBILE_UX.md). Mac je zaklenjen:
dejanski simulator UI, fizični iPhone in VoiceOver/TalkBack niso potrjeni.
Različica ostane1.6.1(24), ni nove trgovinske izdaje. Sheme, podatki, pravice,
strežniki, SDK, zaklenjene odvisnosti in dovoljenja ostanejo isti.

12. oktober,15:36 — po uporabnikovem dovoljenju za shranjeno geslo je prijava
**jivie** dejansko uspela prek običajnega samodejnega izpolnjevanja; geslo ni bilo
prebrano/izpisano. **SL/EN zasebnost z Idejnikom/fotografijami je objavljena** na
jivie.app, vseh8HTML HTTPS200/bajtni hash ter oba pogojna cache preverjanja PASS.
Pred objavo zasebna tar kopija celotnega public_html,20 drugih datotek/imenikov
z enakimi bajti/pravicami; PHP/.htaccess/.well-known/assets ohranjeni. Paket8HTML
je isti e175fdd8..., sprememba samo spletne vsebine. Prejšnja ovira prijave je
odpravljena; Data safety vseh11 vrst ostaja shranjen osnutek, ni oddan v pregled.
[Dokazi](docs/release/ANDROID_PHOTOS_DATA_SAFETY.md#objava-po-prijavi-s-shranjenim-geslom).
Android1.6.1(24), FamilyHub in Apple nespremenjeni. Naslednji korak je oddaja
in preostali konkretni javni obrazci, ne ponovna prijava ali nov testni krog.

12. oktober — Android fotografije: **Data safety vseh11 vrst dejansko shranjen kot
osnutek** za trenutno interno1.6.1(24). Photos dodan, vsi odgovori uporabe/namena
izpolnjeni; CollectedYes/SharedNo/OptionalYes/EphemeralNo, HTTPS in obstoječi
privacy/delete URL. [Matrika in dokaz izvedbe](docs/release/ANDROID_PHOTOS_DATA_SAFETY.md).
Ni oddaje v pregled ali javne objave. SL/EN zasebnost je pripravljena v preverjenem
8HTML paketu; **spletna objava čaka prijavo cPanel jivie**, ker je seja potekla in
lastnik ni pri računalniku. Ne uporabi tripar13 kot nadomestila. Koda/gradnja/
8dovoljenj/SDK/strežniki so isti; Apple je izrecno odložen. Uporabnik je potrdil,
da popravljena rokica/pan/zoom na Androidu zdaj deluje. Naslednji korak je spletna
objava z zasebno kopijo in HTTPS/cache preverjanjem, nato ločena oddaja deklaracije;
ne nov splošni testni krog ali nova gradnja samo zaradi deklaracije.

12. oktober — po fizični Android prijavi zamrznjene rokice je popravek
**Android1.6.1(24) Aktivno za domači(15) od12:36**. Funkcionalnif6520a0/
metadata196b711, [dokazi](docs/release/IDEAS_PAN_ZOOM_RELEASE.md). Sam onPanCancel
je ohranjal otroški PanGestureRecognizer in kradel viewerjeve poteze; ves
risarski komplet je zdaj skupaj izključen v hand/read-only načinu. Menjava
orodja/ACL/boardID prekliče nedokončano potezo; podatki/fotografije/osnutki/
formati/strežnik ostanejo. Pred-fixdejanski pan odpove360/800/1280,
20 ciljni UI PASS/čista ciljna analiza; novi testi dejansko pan/pinchajo po
risanju/izbiri/dviguprsta/reentry in ne spreminjajo JSON table. Ena podpisana
AAB24,317 frozeninputs/isti cert+Firebase+8perms kot23/bundle/CRC/16KiB/23+7
source PASS;23 ohranjen in iz nove izdaje izključen,0 novih/izgubljenih naprav.
Uporabnik je potrdil osnovno fizično delo Idejnika na Androidu; fizični
preizkus popravljenih potez24 še ni potrjen. FamilyHub0.13/schema17,
gostovanje, SDK/locks, iOS/Mac/splet/javna objava niso spremenjeni.

12. oktober — po naročilu naslednjega koraka je **test2 FamilyHub0.13.0/schema17**
in **Android1.6.0(23) Aktivno za domači(15) od11:52**. Funkcionalni03ce0de/
metadata528185a, [dokazi](docs/release/IDEAS_RELEASE.md). Sveža dejanska kopija
obnovljena v izolirani MariaDB10.11.19 (networknone/noports/nobinds):90 tabel/
149 vrstic/2 datoteki/2 imenika, vsi row/create/file/config/marker hashi PASS.
GDJPEGPNG pozitivno tudi v spletnem API. Guarded helper0c2747de… po dejanskem
65s drain doda2 prazni tabeli, namesti96 datotek, ohrani149 vrstic/definicije/
identitete/config/data/core/HTTPS/cron/SMTP/FCM; samo metadata16→17. Stari
vtičnik in kopije ostanejo zasebno, trenutni IDf48b/account1/devices2 isti.
HTTP200/ideas+ideaAssets/record5, anonimne slike/sync5 so401, obstoječi admin
reports dosegljiv; noben Native sprejem/prijava/ukrep ni oddan. Test1 ostane
0.11.2/schema15/HTTP200/95c1. Aktualna0.13 kopija mora zajeti vse podatkovno
drevo s fotografijami; stari helper16 po migraciji ni dokaz kopije17.
Ena podpisana AAB23,317 frozen inputs/isti cert+Firebase+8perms kot22, brez
kamere/širokihmedia/storage, bundle/CRC/16KiB/23+7/source PASS.22 ohranjen in
iz nove izdaje izključen,0 izgubljenih/novih naprav. Telefon fizično še ni
posodobljeno potrjen. Mac/iOS/produkcija/splet/javna oddaja niso spremenjeni.
Na test2 FCM/SMTP ostaneta OFF; obvestilni center je podprt, oddaljena dostava
ni nov fizični dokaz. DataSafety/IARC/javno preverjanje še sledijo.

12. oktober — uporabnik je naročil izvedbo **Idejnika**: lokalno izvedene uredljive
table z besedilom/lističi/risbami, fotografijami in nanje vezanimi oznakami,
premikom/merilom/rotacijo, pan/zoom ter undo/redo. Lokalni osebni/gospodinjski/
organizacijski/projektni prostori, Vsi z izrecnim ciljem, osnutki ločeni od Save.
Deljenje ima dejanske zasebne foto bajte, sync5/record5, obvestila ideas, združitev
različnih elementov/ohranjeni konflikt, celotno prijavo s fotografijami.
**Odjemalec schema9/kopija5, FamilyHub0.13.0/schema17 v izvoru**. Stare kopije in
izvirne čakajoče operacije ostanejo. Šifrirana samostojna obnova table/fotografije
brez starega strežnika je dejansko PASS. Izrecni zasebni prenos in lokalna objava
kopirata tudi osnutke brez objave; predogled pokaže ločene števce. Anonimni osebni
izvirniki se po prenosu ne obudijo pri odjavi. Viewer lahko bere/prijavi ob
zapisovalnem blocked, brez pravic urejanja; preklicane politike niso obite.
**1060 Flutter uspešnih/14 opt-in preskokov**, vseh18 prejšnjih testnih predpostavk
razrešenih v12 podatkovnih/28 UI PASS,42 ciljni UI/13 novi podatkovni PASS, dejanski
Dart/HTTP PASS.468 PHP kontrol na3 bazah,3 migracije16→17 z ohranjenimi hashi/
definicijami/identiteto,8 admin kontrol,87 PHP lint,18 paketnih PASS. Analiza brez
ugotovitev, Android debug/web release PASS, istih8 dovoljenj brez kamere/širokih
media/storage. image4.7.2 je že zaklenjen, premaknjen v runtime; SDK/locks verzije
nespremenjene. [Izvedba/paketa/naslednji korak](docs/IDEAS_IMPLEMENTATION.md).
**Ni nove gostovane ali trgovinske izdaje**: test2 ostaja0.12/schema16, aktivni
Android1.5.2(22), iOS/Mac/splet/produkcija nespremenjeni. Pred gostovano17 sta
nujna GD in sveža dejanska kopija/obnova16 s celotnim zasebnim datotečnim drevesom.
SL/EN zasebnost je lokalno usklajena s fotografijami, Console/javna oddaja ne.

12. oktober — korekcija urejevalnikov je objavljena: **Android1.5.2(22) Aktivno
od08:54** za isti domači(15). Funkcionalni02cbfec/metadata1c39057, [dokazi](docs/release/EDITOR_ACTIONS_RELEASE.md).
Prijava ob naslovu; ena vrstica redDelete/Cancel/Saveicon v sorodnihCRUD obrazcih.
133 ciljnihUI PASS/analizaNoissues;305 frozeninputs, isti podpis/Firebase/8perms
kot21, bundle/CRC/16KiB/23+7kontrol PASS. Ena podpisanagradnja; AAB20/21 ohranjena.
Naložen22/21izključen,0 izgubljenih/novihnaprav. Telefon fizično še ni nadgrajen;
strežniki/sheme/podatki/iOS/Mac/javna izdaja niso spremenjeni.

12. oktober — dodatna izrecna korekcija urejevalnikov: obstoječi gumb »Prijavi
vsebino« sodi ob naslov obrazca. Spodaj ena poravnana vrstica: rdeča ikona
brisanja, besedilni Prekliči, ikona Shrani z namigom. Ne vračaj navpičnega
OverflowBar razporejanja teh dejanj. Uskladi sorodne obrazce Shrani, ne spreminjaj
semantike registracije/povabil/potrditev/oddaje prijave. [Dogovor in obseg](docs/EDITOR_ACTIONS_LAYOUT.md).
Ta korekcija je po interni1.5.1(21), pozneje objavljena v1.5.2(22).
Poverilnice, strežniki, sheme in pravice ostanejo isti.

12. oktober — po izrecnem naročilu je interna **Android1.5.1(21) Aktivno od08:22**
za isti **domači(15)**. Funkcionalni aa1db2b/metadata1ba60b6; stalne zastavice
so prestavljene v meni/podrobnosti. [Dokazi](docs/release/CONTEXTUAL_REPORTS_RELEASE.md).
304 zamrznjeni vhodi, isti podpis/Firebase/8 dovoljenj kot20, bundle/CRC/16KiB/
23+7 kontrol PASS. Predhodnih201 ciljnih UI PASS in čiste analize ne ponavljamo.
Naložen preverjeni AAB21,20 izključen,0 izgubljenih/novih naprav. Telefon fizično
še ni nadgrajen; FamilyHub/test1/test2/iOS/Mac/javna izdaja niso spremenjeni.

12. oktober — uporabnik je zavrnil stalne zastavice prijave ob vrsticah.
Prijava sodi v običajni meni »…« ali podrobnosti; uporabniška prijava v meni
ob članu. Ohraniti je treba bralni dostop do prijave in izrecno oddajo obrazca.
[Korekcija prikaza](docs/MODERATION_AND_REPORTING.md#uporabnikova-korekcija-prikaza--12-oktober)
je sprememba izvora po AAB1.5.0(20), pozneje objavljena v21; strežnik ni nadgrajen.
Ne trdi, da je ta prikaz že nameščen na telefonu. Google ne predpisuje stalne
zastavice; ne vračaj je v sezname. Pogodbe, sheme in podatki ostanejo isti.

12. oktober — po nadaljnjem izrecnem naročilu sta izvedena gostovana namestitev
in interna izdaja: **test2 FamilyHub 0.12.0/schema16**, **Android 1.5.0 (20) Aktivno
za domači (15) od 07:32**. Metadata 9275d92; [dokazi](docs/release/MODERATION_RELEASE.md).
Sveža dejanska kopija obnovljena v izolirani MariaDB 10.11.19: 86 tabel/141 vrstic/
2 datoteki, vsi hashi PASS. Helper bda2dcd4... po 65s praznjenju prometa doda 4 prazne tabele,
namesti 91 datotek, ohrani vse stare vrstice/definicije/identitete/config/data/core/
HTTPS/SMTP/FCM/cron; originalni plugin/kopiji ostanejo zasebno. HTTP200/isti f48b
serverId, moderation1+pravila1, javna SL/EN politika in obstoječi admin reports
dejansko dosegljivi. Noben Native sprejem/prijava/ukrep ni oddan v imenu lastnika.
Podpis/Firebase/dovoljenja kot 19, 303 zamrznjenih vhodov, bundle/CRC/16KiB/23+7 kontrol PASS.
Test1 ostaja 0.11.2/schema15/HTTP200/isti 95c1ID; produkcija, iOS, jivie.app nespremenjeni.
Telefon še ni fizično nadgrajen; nova Mac gradnja še ni nameščena (stara zaprta
za ustavitev sinhronizacije). Fizični tok in javna oddaja še sledita. Stari backup helper15 po
migraciji ne potrjuje kopije16. Ne razglasi celotne javne izdaje ali obnove za končano.

12. oktober — uporabnik je naročil nadgradnjo prijav/pravil v Jivie in FamilyHub,
z delom lokalno; portali, gostovana namestitev in fizični preizkus sledijo doma.
**FamilyHub0.12.0/schema16** in odjemalčev tok sta lokalno izvedena: izrecni
strežniško uveljavljeni sprejem pred skupnimi uploadi, omejeni spletni predogled
in prijave vsebine/vidnih članov, APP_ADMIN TLS/CSRF obravnava, revizijsko varni
ukrepi in odpravljive omejitve prostora. Prijave ostanejo na izbranem strežniku,
ne pri TriparNA/cPanel ponudniku. Lokalno/zasebno delo, branje, joining/reporting
in varnostni preklici so ločeni; pending/opId/izvoz ostanejo. **1028 Flutter PASS /
14 opt-in skips**, ločen dejanski Dart/HTTP PASS, analiza brez ugotovitev,
**192 PHP kontrol / 3 migracije15→16 / 83 PHP lint PASS**, Android debug PASS.
Izvorna/paketna/Firebase preverjanja so uspešna. [Dokazi, paketi in naslednji
korak](docs/MODERATION_AND_REPORTING.md). Portali niso uporabljeni, nobena živa
namestitev ni nadgrajena: testni strežniki ostanejo0.11.2/schema15 in aktivni
Android1.4.1(19) **nima novih prijav**. Appverzija/SDK/locks/podpis niso spremenjeni;
novo podpisano kodo različice pripravimo po vrnitvi. SL/EN zasebnost je pripravljena
lokalno, ne objavljena. IARC/DataSafety/javni pregled še niso zaključeni. Meje
obnove iz server-loss dnevnika ostanejo; ne razglasi celotne javne izdaje za končano.

11. oktober — po izrecnem naročilu nove Android gradnje s popravki je podpisana
**1.4.1 (19)** dejansko **Aktivno** na istem internem kanalu za **domači (15)**,
od **21:55**. Metadata `1b7e7f6` so main/origin; vsebujejo `d627bbe`, `1284ca3`
in `3d91b37`. 300 zamrznjenih vhodov, isti podpis/Firebase kot AAB18, enakih osem
dovoljenj brez širokih media/storage, bundle/CRC/16 KiB in 23+7 izdajnih kontrol
PASS. Funkcionalnih 1002 PASS/13 skips in čiste analize brez novih sprememb nismo
ponavljali. [Dokazi](docs/release/ANDROID_FIXES_RELEASE.md). Fizična nadgradnja19
še ni potrjena. Console zasebnost je shranjena, Data safety je osnutek desetih
kategorij. IARC ponovno zahteva neoznačen sprejem pogojev; agent ga ni sprejel.
Aktualni deljeni organizer še nima terms/reportcontent/reportuser toka, ki ga
Google zahteva tudi za zaprte skupine. Javna kandidatka ni oddana/odobrena;
naslednji korak so te konkretne zahteve, ne nov splošni testni krog. Strežniki,
iOS, SDK in odvisnosti niso spremenjeni.

## Namen in dogovorjeni obseg

11. oktober — zaključeni dovoljeni deli fizičnega test2 izpada: dejanska strežniška
kopija obnovljena v izolirani MariaDB 10.11.19 (86 tabel/134 vrstic/2 datoteki,
vsi hashi PASS). Test2 začasno HTTP503; Mac ohrani podatke, ustvari/uredi task
in finančni 7 EUR; ponovni zagon ohrani vrsto 3. Odkriti blokiran izvoz HTTP503 je
popravljen **3d91b37 na main/origin**: **1002 Flutter PASS / 13 opt-in preskočenih**,
analiza brez ugotovitev; veljavne zavrnitve pravic ostanejo failclosed. Nova podpisana
Mac 1.4.0 (18), 297 ujemajočih vhodov/iste podpisne identitete, dejansko shrani JSON
2 task + 1 finance brez skrivnosti. Isti test2 je vrnjen: HTTP200/isti serverId,
Usklajeno/vrsta 0; read-only baza potrdi 3 zapise in 3 receipts 200 za izvirne opId,
vsak enkrat. Končni gospodinjski ledger 131/75/25 EUR, skupaj 231, prihodki 50/odhodki 19.
Nič ni trajno izbrisano. [Končni izid in meje](docs/server/SERVER_LOSS_TEST.md#končni-izid-tega-preizkusa--11-oktober-2059).
Uporabnik je odsoten in izrecno dovolil izpust nedosegljivih testov: fizični
povračili 10/20, Android offline/expiry, novi celotni klientski šifrirani kopiji in
samostojna obnova praznega profila so NEPREVERJENO. Živi Android18 novih
popravkov še nima. Ne razglasi celotnega A–F ali javne izdaje za dokončane.

11. oktober — dejanski dvosmerni preizkus test2 potrdi Androidove trenutne finance
138/75/25 EUR in novo `Slt android` na Macu; uporabnik potrdi tudi Androidov hladni
zagon ter projektni strošek 30 EUR/stanje 70 EUR. Priprava odkrije prvi payment
bootstrap (prazen finance3 snapshot se ni prenesel) in zavajajoč predogled kopije.
Oba popravka sta lokalno preverjena: **965 Flutter PASS / 13 opt-in preskočenih**,
analiza brez ugotovitev. Predogled loči osebno/drugo lokalno/preneseno/ohranjena
izhodišča ter evidence plačil; format/schema/izvoz so isti. Nova podpisana Mac
gradnja in dejansko plačilo/kopija še sledita; izdani Android18 novih popravkov
še nima. Test2 backup helper hosted read-only check potrdi1 račun/2 napravi/
86 tabel/2 zasebni datoteki; gostovani export+dejanska obnova še čakata.
[Dokazi](docs/server/SERVER_LOSS_TEST.md#dva-popravka-odkrita-med-pripravo).
Strežnik je dosegljiv, nič ni izbrisano, celoten A–F ni zaključen.

11. oktober — račun slt_test na ločenem test2 je ustvarjen in potrjen. Mac je
objavil SLT gospodinjstvo (4 zapisi + vrt); read-only baza potrdi vseh 5 vrst po 1.
Android uporabnik potrdi isto vsebino na 1.4.0. Fizična objava je odkrila star
DropdownButton assertion po vezavi izbranega lokalnega prostora. Funkcionalni
**d627bbe** je na main/origin: prehod sledi točnemu bindingu istega računa; pozna
izbira ne prepiše uporabnikove izbire/Vsi ali novega računa. Lokalni katalog se iz
account-only toka ne odpre po nepotrebnem. **950 Flutter PASS / 13 opt-in
preskočenih**, analiza brez ugotovitev; 8 novih real-provider/SQLite regresij.
[Dokazi in stanje](docs/server/SERVER_LOSS_TEST.md#prva-fizična-objava-in-popravek-izbora).
Nova podpisana Mac 1.4.0 (18) je odprta z ohranjeno prijavo; dejanska nova objava
organizacije/projekta potrdi prehod brez napake. Finančni ledger gospodinjstva
potrdi 138/75/25 EUR, skupaj 238 EUR, prihodek 50/odhodek 12 EUR. Osebno
plačilo projektnega stroška še čaka na pregled nedosegljivega UI dejanja; Android18 v Play še nima tega popravka,
appverzija/strežnik/shema/SDK niso zvišani ali nadgrajeni. Celotni A–F še čakajo,
strežnik ni izključen ali izbrisan.

11. oktober — uporabnik je pripravil kopiji na Macu/Androidu in poročal o ničlah.
[Preverjanje](docs/server/SERVER_LOSS_TEST.md#predogled-ničel--11-oktober) je pokazalo
zavajajoč predogled: osebni števci ne štejejo ločenih prenesenih zapisov/financ in
drugih lokalnih prostorov, čeprav jih izvoz vključuje. Macov skupni projekt je še
viden; shranjena šifrirana kopija je ohranjena zasebno in strukturno preverjena,
z uporabnikovim geslom dejansko odprta: osebno0, 2 strežniška obsega, 0 prikazanih
operacij. Obnova ni potrjena. 39 ciljnih testov PASS ni fizični dokaz obnovljene
vsebine. Popravek predogleda in regresija oseben0/skupno>0 še nista izvedena;
Mac je po kopiji standardno odjavljen iz test1; novi slt_test je po uporabnikovi
oddaji potrjen v novejšem dodatku zgoraj. Noben strežnik ni odstranjen.

11. oktober — uporabnik je naročil preizkus izgube strežnika z novim ločenim
`jivie-test2.triparna.si`, prijavo/urejanjem in kasnejšo odstranitvijo. [Protokol](docs/server/SERVER_LOSS_TEST.md)
loči sinhronizacijo, dejansko kopijo, izpad, offline/restart/expiry ter samostojno obnovo.
Svež zaprti Kanboard 1.2.54/FamilyHub 0.11.2 paket je lokalno preverjen; SMTP/FCM
ključi drugih namestitev se ne kopirajo. Na računu tripar13 je ustvarjena ločena
domena z veljavnim TLS in nova baza tripar13_jivietest2; uporabnik je sam oddal
Softaculous namestitev Kanboard 1.2.54. FamilyHub 0.11.2/schema15 je dejansko
nameščen: nova identiteta f48b41ae-c6bb-4f2d-ae13-0aa7fa255993, ohranjeno jedro/DB
vrstice, 83 datotek vtičnika; config/data sta zasebna, HTTP301→HTTPS, SMTP/FCM
izključena. Skrbniška spletna prijava je potrjena; prvi aplikacijski račun še čaka.
Izhodišče Mac 1.3.2 (17) je takndev/test1/Vsi; dejansko preverjanje kopije in odjava
sta v novejšem dodatku zgoraj. Prva faza izgube je
reverzibilna samo za test2; trajni cPanel izbris potrebuje konkretno potrditev pri
dejanju in predhodno preverjeno kopijo. Fizični A–F so še ČAKA, običajna seja je 30 dni.

11. oktober — nadaljevanje po main merge: podpisana interna Android izdaja
**1.4.0 (18)** iz `7fb5ed9` na main (cleanup `7726d76`, merge
`b6832c2`). 298 zamrznjenih vhodov, isti podpis/Firebase kot AAB17, manifest brez
širokih media/storage dovoljenj, 16 KiB, 23 izdajnih in 7 Firebase kontrol PASS.
[Dokazi in stanje oddaje](docs/release/CLEAN_ORGANIZER_RELEASE.md).
Google Play potrjuje **Aktivno**, za isti seznam **domači (15)**, od **12:41**.
Prava shranjena prijava je v Codexovem brskalniku; organizacijski račun se imenuje
**TaknDevs**, njegov potrjeni ID `4991604398202512900` je račun TriparNA. Ne sklepaj
o napačnem računu zgolj iz tega imena; prejšnja trditev o manjkajočem dostopu je popravljena.
FamilyHub, iOS in javna objava niso spremenjeni; fizična nadgradnja še ni preverjena.

11. oktober — uporabnik je naročil popolno odstranitev starega mobilnega vmesnika
in njegovih odvisnosti ter združitev na main. `lib/features`, `lib/kanboard`, stari
modeli/providerji/credential/cache/default storage in vse stare poti so odstranjeni.
Glavni razred je `JivieApp`; novi organizer, FamilyHub, nastavitve, finance in kopije
ostanejo. open_filex/qr_flutter/qr in stari ikoni so odstranjeni, druge zaklenjene
odvisnosti/SDK nespremenjeni. Podatkovni formati, baze, Hive in namizne identitete
so ohranjeni; poverilnice/predpomnilnik starega odjemalca in AI ključi se ne berejo
ali brišejo. **942 Flutter PASS /
13 opt-in preskočenih**, analiza **No issues found**, Android/web/iOS simulator ter
izolirani macOS Debug PASS. [Aktualni dokazi](docs/release/LEGACY_INTERFACE_REMOVAL.md)
imajo prednost pred starejšimi opisi dosegljivega Kanboard UI spodaj.
Različica in nameščene interne aplikacije, Play, iOS ter FamilyHub niso spremenjeni.

11. oktober — prva javna izdaja je izrecno **brez AI**. Stari klepet, nastavitve,
pomoč pri opravilih, neposredne poti, providerji in OpenAI transport so odstranjeni
iz izvora. Končni preverjevalni AAB nima širokih storage/media dovoljenj iz open_filex;
FileProvider in obvestila ostanejo. Stari lokalni podatki/ključi se ob nadgradnji
ne brišejo ali nalagajo. SL/EN zasebnost je objavljena s podporo `support@jivie.app`
(uporabnik potrdi delujoč predal). Po njegovi nadaljnji izrecni korekciji javna
zasebnost nima odstavka o AI ali razvojni zgodovini; opisuje prvo dejansko izdajo.
972 Flutter PASS / 13 opt-in preskočenih, analiza 31 podedovanih info brez napak
ali opozoril; [aktualni dokazi in meje](docs/release/NO_AI_FIRST_RELEASE.md).
Različica, nameščene interne aplikacije, Play, iOS in FamilyHub ostajajo nespremenjeni.

11. oktober: predstavitvena stran **jivie.app** je po uporabnikovem naročilu objavljena
na ločenem cPanel računu `jivie`, `/home/jivie/public_html`. Vseh osem SL/EN strani
(predstavitev, pomoč, zasebnost, izbris) je preverjenih s HTTPS 200 in ujemanjem paketa;
HTTP se preusmeri na HTTPS. Obstoječe PHP nastavitve in `.well-known` so ohranjene,
kopija in prenosni ZIP sta zunaj javne mape. [Dokazi objave](website/README.md) imajo
prednost pred starejšimi 403/404. Besedilo sledi 1.3.2 in pošteno ohrani razkritje še
dosegljivega AI ter omejitve obnove. To ni javna mobilna objava, končna trgovinska
deklaracija ali poseg v FamilyHub produkcijo; njihove odprte postavke ostanejo.

Najnovejša dopolnitev 11. oktobra je [popravek prebranosti in sedemdnevna hramba obvestil](docs/INBOX_READ_STATE_AND_RETENTION.md). Ikona kaže trenutno stanje, namig dejanje; neprebrano je krepkejše in barvno poudarjeno. Rok teče od readAt, ne createdAt; ponovljeno branje ne podaljša roka, unread ga prekliče. Strežniško čiščenje uporablja obstoječi cron opomnikov in visibility_revision na schema15. Minimalna lokalna potrdila preprečujejo ponovno ustvarjanje opomnikov iz še odprtih opravil/financ. `notification_missing` pri zastarelem inbox.read ne sme blokirati celotnega prostora. Izvedba je objavljena: funkcionalni `74aa41c`, različica `eafb30b` in strežniška priprava `8de8cc7` so na `origin/codex/email-invitations`. Android **1.3.2 (17)** je aktiven za **domači (15)** od 08:26; nova podpisana Mac gradnja je odprta z ohranjeno prijavo takndev. Testni strežnik je **FamilyHub 0.11.2/schema15**, po dejanski izolirani obnovi **86 tabel, 273 vrstic in 5.886 zasebnih datotek**, brez ponastavitve podatkov. [Izdajni dokazi](docs/release/INBOX_RETENTION_RELEASE.md) imajo prednost pred starejšimi stanji spodaj. Produkcija, iOS, javna objava in main niso spremenjeni.

Najnovejši izdajni korak 11. oktobra: funkcionalni **bdf36d9** in različica **13e8f46** sta na `origin/codex/email-invitations`. Android **1.3.1 (16)** je aktiven za **domači (15)** od 07:30, nova podpisana Mac gradnja je odprta kot takndev. Testni strežnik uporablja **FamilyHub 0.11.1/schema15**, brez migracije ali spremembe shranjenih preferenc, po sveži izolirani obnovi **86 tabel, 247 vrstic, 2.849 zasebnih datotek**. Vseh pet rednih delavcev je po odprtju potrjeno svežih. [Izdajni dokazi](docs/release/NOTIFICATION_DEFAULTS_RELEASE.md) imajo prednost pred starejšimi stanji spodaj. Fizični Android push preizkus nove izdaje še sledi; Mac ima center v aplikaciji, ne oddaljenega sistemskega push. Produkcija, javna objava, iOS in main niso spremenjeni.

Dopolnitev 11. oktobra: uporabnik je na Androidu potrdil prehod politike Doma, prikaz novega projekta/opravila drugemu računu na Macu ter spremembo z Maca na telefon s povezanim stroškom brez podvojitve. Obvestila pod zvončkom so potrjena na obeh napravah. Nova naročena lokalna nadgradnja je [privzeti push in skupno označevanje prebranega](docs/NOTIFICATION_DEFAULTS_AND_READ_ALL.md): odsotne nastavitve kategorij pomenijo push/inApp ON, email/sound OFF, shranjeni izklopi ostanejo; napravno dovoljenje in registracija sta ločena. »Označi vse kot prebrano« zajame upravičeno vsebino trenutnega filtra, ne zaključi opravil ali plačil in ne zajame kasnejših prihodov. Nastavitve kategorij so uredljive tudi brez registracije trenutne naprave. Gostovanje in nameščena 1.3.0 (15) te nove spremembe še nimata; macOS sistemski push ostaja neizveden. Preverjeno: **963 Flutter PASS / 13 opt-in preskočenih**, 582 PHP kontrol na treh bazah, 10 paketnih testov ter analiza brez napak/opozoril (35 podedovanih info). Podrobni dokazi in meje so v navedenem dokumentu.

Izdajni korak 10. oktobra je zaključen: funkcionalni commit **70f6113** in izdajna priprava **e0bc9a1** sta poslana na `origin/codex/email-invitations`. **FamilyHub 0.11.0/schema15** je nameščen samo na `jivie-test.triparna.si`, po sveži preverjeni obnovi **85 tabel, 204 vrstic, 1335 zasebnih datotek** v izolirani MariaDB 10.11.19. Računi/gesla/serverId/SMTP/FCM ter originalni cron so ohranjeni. Android **1.3.0 (15)** je aktiven za **domači (15)** od 10. oktobra ob 20:07. Nova podpisana Mac 1.3.0 (15) je odprta, račun takndev in Doma sta ohranjena. Stara Doma politika se ni samodejno razširila: lastnik mora pregledati in potrditi prehod v Nastavitvah prostora. Skupno fizično urejanje še sledi. [Izdajni dokazi](docs/release/SPACE_SHARING_RELEASE.md) imajo prednost pred prejšnjimi stanji izvora/gostovanja spodaj. Produkcija, javna izdaja in iOS niso spremenjeni.

Nova izrecna odločitev 10. oktobra: [uskladitev deljenja](docs/SPACE_SHARING_ALIGNMENT.md) ima prednost pred starejšo matriko organizacije. Povabilo v celoten prostor (gospodinjstvo/organizacijo) daje dostop do skupne vsebine, financ ter vseh obstoječih in prihodnjih projektov. Povabilo samo v projekt ostane omejeno na njegov projekt, opravila, dogodke, obvestila in finance; ne ustvari članstva nadrejenega prostora. Uporabnik je dodal **»Člani bodo lahko delali vse«**: v deljenem obsegu lahko tudi urejajo/brišejo, upravljajo finance ter vabijo/upravljajo člane. Ne uvajaj novega finančnega dovoljenja ali nove vloge manager za ta tok. Osebne identitete, drugi zasebni prostori in zaščita lastništva ostanejo ločeni. Stara dovoljenja se ne razširijo tiho; nova različica politike potrebuje opisan predogled prehoda. Izvedba je lokalno preverjena: **947 Flutter PASS / 13 opt-in preskočenih**, dejanski Dart/HTTP z drugim in tretjim računom ter ponovno odprto SQLite brez strežnika PASS, **2505 PHP kontrol PASS** na treh bazah. Analiza ima 35 podedovanih info brez napak/opozoril; Android debug in web release sta uspešna. Izvor FamilyHub je **0.11.0/schema15**, gostovanje ostaja 0.10.0/schema14 in odprta Mac aplikacija ostaja prejšnja gradnja. App verzija ostane 1.2.0+14; ni nove trgovinske izdaje. Izhodiščni commit **0cdf468** je poslan na `origin/codex/email-invitations`, nova uskladitev je lokalna. Podrobnosti in meje vodi navedeni dnevnik.

Ponovitev povabila po registraciji, 10. oktober: uporabnik je drugi prazni testni račun izbrisal po standardni poti, nato prek nove pošte ustvaril drugega uporabnika in posebej sprejel povabilo. Mac potrjuje **Doma · Organizacija · Član · Deljeno** ter prvega uporabnika kot lastnika. Zanka predogleda je odpravljena s primerjavo `(serverUrl, token, accountPartition)`; lastni `serverId`/rok/ID niso sprožilec. Sprememba med busy se po zaključku obdela tudi po izgubljenem odgovoru. Uspešna odstranitev/sprejem prebere sveži `securePendingInvitationProvider.future`, ker stari `widget.pending` lahko obudi porabljeno povezavo. **33 ciljnih testov PASS**, štiri nove regresije uporabljajo resnični kontroler/providerje; ciljna analiza brez ugotovitev. Nova podpisana cleanup Mac gradnja ima preverjenih 321 vhodov. Dejanska odstranitev starega povabila ter ponovni zagon ohranita prijavo, Doma in članstvo brez starega poziva. Skupno urejanje dveh naprav še ni fizično potrjeno. Strežnik in Android izdaja ostaneta nespremenjena. [Dokazi](docs/EMAIL_INVITATIONS.md#ponovitev-po-zatikanju-po-registraciji--10-oktober).

Stanje sinhronizacije, 10. oktober: uporabnik je zahteval kompakten oblak ob naslovih na vseh obstoječih prikazih sinhronizacije. Ne vračaj raztezajoče statusne vrstice/kartice; prikaz ima stalnih 88 × 48 logičnih točk in rezervirano mesto za osveževanje. Dotik odpre sprotne podrobnosti ter ustrezna dejanja. Zeleno stanje zahteva dejanski uspeh celotnega postopka brez čakajočega/blokiranega dela ali konfliktov; časi so vezani na trenutno sejo in identiteto, po zagonu neznani do novega preverjanja. Pozni odgovor starega računa ne sme prenesti uspeha ali napake v novega. Povezana plačila upoštevajo tudi lastne števce in nepopolnost. **921 Flutter PASS / 12 opt-in preskočenih**, analiza brez napak/opozoril (35 podedovanih info); mobilna/namizna geometrija in sintetični widget posnetki so preverjeni. Ni nove izdaje ali spremembe strežnika. [Izvedba in meje](docs/SYNC_STATUS_INDICATOR.md).

Fizični preizkus povabila 10. oktobra je potrdil prejem e-pošte in odpiranje Mac aplikacije, razkril pa `CircularDependencyError`: kontroler je invalidiral projekcijo povabila, ki je odvisna od njega. Popravek uporablja neodvisen `pendingInvitationRevisionProvider`; ne vračaj neposredne invalidacije `securePendingInvitationProvider` iz `CollaborationController`. Regresije uporabljajo resnični kontroler in opazovano projekcijo, saj podvojen testni kontroler napake ni zaznal. Isti resnični predogled na Macu je po popravku uspešen. Registracija in izrecni sprejem z drugim uporabnikom še sledita; pri email2 mora gumb za ustvarjanje računa odražati ta ločena koraka. [Dokazi](docs/EMAIL_INVITATIONS.md#fizični-preizkus-predogleda--10-oktober).

Povabila po e-pošti, 10. oktober: potrjeni tok je naslov → poštna povezava → registracija/prijava v aplikaciji → izrecni sprejem → pravi prostor. Nova registracija po invitation2 ne dodeli članstva. Izvor in ločeni testni `jivie-test.triparna.si` uporabljata **FamilyHub 0.10.0/schema14**, po preverjeni dejanski obnovi 84 tabel, 169 vrstic in 583 zasebnih datotek v izolirani MariaDB 10.11.19. Računi, gesla, identiteta in konfiguracija so ohranjeni; produkcija je nespremenjena. **885 Flutter PASS / 12 opt-in preskočenih**, ločen dejanski Dart/TLS/SMTP PASS, 762 ciljnih PHP kontrol na treh bazah, 70 PHP lint, 10 paketnih testov ter 32 + 21 kontrol nadgradnje PASS. Analiza nima napak/opozoril, ostane 35 podedovanih info. Android debug in podpisana macOS arm64 gradnja sta uspešni; 318 zamrznjenih vhodnih datotek se ujema. Nova Jivie je odprta na Macu, fizični preizkus še sledi. Različica aplikacije ostane 1.2.0 (14); Play gradnja še nima novega e-poštnega obrazca. Ta korak ne vključuje commita, pusha ali nove izdaje. [Izvedba in meje](docs/EMAIL_INVITATIONS.md) imajo prednost pred starejšim opisom povabil. Varna hramba in koordinator povezav morata uporabljati isto zaporedno vrsto; pozni odgovor starega povabila ne sme izbrisati novega.

Izvedba novega modela prostorov, 9. oktober: izvor uporablja lokalno schema8, vsebino šifrirane kopije4 (bere1–3), FamilyHub0.9.0/schema13 in record4 za gospodinjske vrtove. Kanonični finančni API ostaja finance2; finance3 je ločena dopolnilna evidenca povezanih plačil, oglaševana z `linkedPaymentContractVersions`. Podpora povezanim plačilom ne spreminja teles ali identifikatorjev starih čakajočih operacij. Politika organizacije2 daje članom projektno finančno branje in vodjem pregled vseh projektov; stara politika1 se razširi šele po lastnikovem predogledu dodatnih prejemnikov. Izbris računa uporablja politiko3 v aplikaciji in spletnem obrazcu; ohranjena skupna finančna dejstva ter zasebne odstranitve so navedene v predogledu. [Izvedbeni dnevnik](docs/SPACES_UPGRADE_IMPLEMENTATION.md) je vir dejanskih testov in preostalih omejitev. Po naslednjem uporabnikovem naročilu je ločeni testni jivie-test.triparna.si nadgrajen na FamilyHub0.9.0/schema13; pred migracijo je dejanska kopija obnovljena v izolirani MariaDB10.11.19 (79 tabel,181 vrstic,215 zasebnih datotek). Računi/serverId/SMTP/FCM so ohranjeni, podatki niso ponastavljeni. Produkcija ostane nespremenjena; [dokazi gostovanja](docs/server/CPANEL_SETUP.md#14-nadgradnja-prostorov-9-oktobra--familyhub-090--schema13).

Zaključno preverjanje prostorov: **856 Flutter PASS / 11 opt-in HTTP preskočenih**, ločen dejanski Dart/HTTP preizkus z drugim odjemalcem in ponovnim odprtjem datoteke SQLite brez strežnika PASS. **1554 PHP kontrol PASS** na SQLite/MySQL/MariaDB, 66 PHP lint in 10 paketnih testov PASS. Analiza nima napak/opozoril, ostane35 podedovanih info starega odjemalca. Android debug in web release gradnji sta uspeli. Po naslednjem izrecnem naročilu je pripravljena in aktivno objavljena interna Android **1.2.0 (14)** za domači (15), 9. oktobra ob 20:23. Podpisani AAB, 18 izdajnih testov, source checker, manifest, 16 KiB in Firebase so preverjeni; 317 zamrznjenih vhodnih datotek se ujema. [Izdajni dokazi](docs/release/NOTIFICATION_RELEASE_RUN.md#prostori-in-povezane-finance--aktivna-12014). Fizični preizkus dveh naprav, nova iOS gradnja in javna izdaja še sledijo. Samo različica aplikacije in njeni metapodatki so zvišani; platformna konfiguracija, SDK in zaklenjene odvisnosti so nespremenjeni. Funkcionalne meje so v izvedbenem dnevniku, ne sklepaj o živi različici iz izvorne kode.

Dodatna izrecna zahteva 9. oktobra: izguba ali trajna nedosegljivost strežnika ne sme izbrisati ali zakleniti lokalno ustvarjenih oziroma upravičeno prenesenih podatkov in priponk, niti po ponovnem zagonu ali poteku seje. Načrt mora zagotoviti lokalno delo, kopijo/obnovo brez starega strežnika in varen postopek ponovne povezave; nedosegljivosti ne enači s potrjenim preklicem članstva. Novo jedro ohrani prenesene zapise in delo po poteku seje; zaznana druga identiteta strežnika blokira nov promet, ne izbriše lokalne vsebine. Samostojna obnova ustvari nove lokalne ID-je in ohrani izvirni arhiv/operacije. Finančni prenosi in povezave plačil se pri tej pretvorbi še ne aktivirajo: označi nepopoln finančni pregled, izvirnike pa ohrani v šifriranem arhivu. Skupne priponke še nimajo dokončane poti; URL ni lokalna datoteka. Dokaze in natančne meje vodi [izvedba prostorov](docs/SPACES_UPGRADE_IMPLEMENTATION.md).

Najnovejša potrjena smer, 9. oktober 2026: [načrt naslednje nadgradnje prostorov in financ](docs/SPACES_NEXT_UPGRADE_PLAN.md). Osebno, gospodinjstvo in organizacija so vrste prostorov; lokalnost/sinhronizacija je stanje istih prostorov. Za organizacijske projekte velja nova izrecna odločitev: sprejeti član projekta vidi vse finance tega projekta, skupina vodij organizacije pa vse njene projekte in njihove finance, tudi prihodnje. Pravice urejanja ostanejo ločene, zasebne finance drugih prostorov se s tem ne razkrijejo. Ta odločitev ima prednost pred starejšim predlogom ločenega dovoljenja za branje organizacijskih projektnih financ. Načrt je po zadnjem naročilu izveden v izvoru; javna/živa sprememba ima ločeno dokazilo. Meni sledi vrsti prostora, Dom je odstranjen, Načrti se imenujejo Opravila; oznaka domačega projekta se ohrani. Vsi ni zapisovalni cilj. Stari vrtovi/nakupi ostanejo dostopni do izrecne dodelitve gospodinjstvu.

Aplikacijo razvijamo v osrednje orodje za osebno in družinsko organizacijo: prosti čas, opravila, domače projekte, nabavo in finance. Uporabnik naj iz aplikacije upravlja tudi svoj račun in deljenje projektov.

Uporabnik je zahteval zasnovo local-first: osnovna osebna uporaba mora delovati brez strežnika, tudi za ustvarjanje in urejanje podatkov. Izvedbo gradimo po [načrtu prenove](docs/RENOVATION_PLAN.md). Lokalni osebni način je osnova; izbirna sinhronizacija, sodelovanje in strežniška obvestila imajo ločena merila dokončanosti.

Repozitorij vsebuje obstoječi Flutter odjemalec za Kanboard; prenova dodaja lokalni organizator in strežniški vtičnik. Dejanski napredek, preverjene funkcije in odprte omejitve vodi načrt prenove. Predlogov, vmesnih gradnikov in testnih prototipov ne predstavljaj kot dokončanih uporabniških tokov.

Uporabnik je 4. oktobra 2026 potrdil mobilno oblikovno smer, vzporedno namizno izvedbo in začetek gradnje. Zahteva podagente `gpt-6.1-sol` z razmišljanjem `high`; glavni agent razdeljuje delo, usklajuje pogodbe, vodi dokumentacijo in preverja rezultate. Podagenti naj imajo jasno lastništvo datotek in se neposredno uskladijo o skupnih vmesnikih. Spremembe ene naloge ne smejo prepisati dela druge.

Zadnja usmeritev istega dne ima prednost: uporabnik je izrecno pojasnil, da je z začetkom gradnje zadovoljen in želi graditi naprej. Pregled stare kode in dosedanjih sprememb je podlaga za boljše odločitve, ne ustavitev razvoja. Ohranitev starega vedenja in lokalnih podatkov aplikacije ni pogoj; bistveno je iz strežnika zajeti vse obstoječe podatke v preverjen lokalni arhiv z brskalnikom. Staro aplikacijo in projekte lahko nato upokojimo, ne da bi vse preselili v novo domeno. Obstoječi projekti so lahko izhodišče zahtev ali izbirnega prenosa. Finance potrebujejo ponovno zasnovo. Dosedanja lokalna osnova in FamilyHub sta razvojna gradnika, ne zavezujoča končna arhitektura. Dovoljenje za nadaljnjo gradnjo in zajem arhiva ni dovoljenje za izbris produkcijskih podatkov; lokalnih podatkov ne briši brez izvedbene potrebe.

Potrjen videz: nevtralna svetla/temna tema, grafitno besedilo, zadržan moder poudarek; bež in žajbljevo zelena nista potrjena smer. Prvotni telefon je uporabljal spodnje zavihke Danes, Načrti, Nakupi, Več. Po uporabnikovem pregledu 8. oktobra je izrecno naročen levi zložljivi meni za telefone; nova izvedba pod 600 px neposredno odpre vsa področja. Tablična širina 600–899 px ohrani spodnje zavihke, namizje od 900 px stranski meni. Po uporabnikovem posnetku istega dne telefonska glava vsebuje ikono, izbor prostora in zvonček, naziv Jivie ostane v meniju; dodatna vrstica izbire in ločeni dodajalni gumb sta odstranjena. Spustni seznam vsebuje + Nov prostor z izrecno vrsto in imenom; brez računa odpre povezavo. Dokaze in stanje izdaje vodi `docs/UPGRADE_IMPLEMENTATION.md`. Na začetku pokaži uporabnikove resnične podatke ali uporabna prazna stanja, nikoli vzorčnih družinskih članov, dogodkov ali finančnih zneskov. Prejšnje delovno ime »Vsakdan« je 7. oktobra 2026 nadomestilo potrjeno ime Jivie.

Kompaktna glava po uporabnikovem posnetku je preverjena s 565 Flutter PASS in analizo brez napak/opozoril (37 obstoječih info). Funkcionalni commit/push `3d504c4`, izrecna izdajna priprava `1121407`; Android **1.1.2 (5)** je aktiven na istem internem kanalu za domači (15), dokaz v `build/qa/jivie-compact-header/play-internal-1.1.2-5-active.jpg`. Server/schema/SDK/dependency lock so nespremenjeni, novi fizični prikaz čaka uporabnikov preizkus.

Uporabnik je 7. oktobra 2026 izbral **Jivie**, izgovorjeno **dživi**, in naročil pripravo nove iOS/Android izdaje ter ikone: življenje kot abstrakten preplet zemlje, vode in zraka. Aplikacija je brezplačna; prodaja upravljanega gostovanja je poznejša faza, brez sedanje naročnine ali plačilnega toka. Glavni agent vodi oblikovanje, integracijo in pregled; kodo pripravljajo podagenti `gpt-6.1-sol` / `high`. Zadnja izrecna uporabnikova korekcija istega dne določa novi Android/iOS ID `si.triparna.jivie` (nadomesti prejšnji razvojni `com.takndev.jivie`); pripravljamo ta ločeni ID in začetno različico `1.0.0+1`. Registracija identifikatorjev v trgovinah, izbira podpisne ekipe, podpis in objava imajo ločene dokaze. Stari Kanban Connect (`com.takndev.kanbanconnect`) ostane ločena aplikacija. Namiznih identitet, imen baz, protokolov in formata `.vsakdan` ne menjaj zgolj zaradi znamke; podatkovna združljivost ostane ohranjena. Nova povabila uporabljajo `jivie://invite`, stara `vsakdan://invite` ostanejo berljiva. Podrobnosti vodi [priprava izdaje](docs/release/README.md).

Google Play račun je organizacijski. Zahteva 12 preizkuševalcev/14 dni je vidna pri stari aplikaciji, ki jo je uporabnik prenesel iz osebnega računa; ne predstavljaj je kot ugotovljeno zahtevo nove aplikacije. Ime Jivie je uporabnikova odločitev, ne dokaz preverjene znamke ali domene. Pri prvem pregledu obstaja podobno poimenovana zdravstvena aplikacija Jivi; začetno spletno iskanje ni preverjanje pravic do imena.

Uporabnik je istega dne potrdil izdajatelja **TriparNA (triparna.si)** in sporočil nakup domene **jivie.app**. Predstavitvena stran je statičen paket za njegov cPanel; priprava ZIP ni dovoljenje za objavo ali poseg v gostovanje. V tej fazi ni upravljanega gostovanja, naročnin ali plačil. Vtičnik FamilyHub pripravimo za ločen javni repozitorij pod MIT, z ohranjenimi tujimi obvestili; to ne določa licence celotnega mobilnega repozitorija. Zahtevan je kratek prvi uporabniški vodič, brez vzorčnih podatkov ali samodejne privolitve v sinhronizacijo. Modul **Vrt** je uporabnik pozneje istega dne naročil v izdelavo: več poimenovanih vrtov, zapiski in ročno risanje razporeditve, lokalna hramba ter kopija/obnova. Prva izvedba ostane lokalna in se ne prenaša samodejno v zasebni ali skupni strežniški prostor. Prva izvedba in 76 podatkovnih ter 48 UI/regresijskih testov so preverjeni; dokaze in meje vodi `docs/GARDEN.md`. Uporabnik je tudi izrecno dovolil ustvarjanje novih evidenc aplikacije in testnih izdaj v obeh trgovinah; ob težavi s prijavo se pri zadevni trgovini ustavimo in mu sporočimo. Javna produkcijska izdaja ni predmet tega dovoljenja.

Nadaljevanje 8. oktobra: oddaljeni razporejeni opomniki in prenovljen Vrt so izdelani ter lokalno preverjeni. 636 Flutter PASS/9 opt-in HTTP preskočenih, ločeno 2 dejanska HTTP testa; analiza 37 obstoječih info brez napak/opozoril. Vrt uporablja notranji format2 s starim bralnim vhodom; zunanja lokalna schema6/JSON4/prenosna3 in strežnik ostanejo isti. Grede imajo trajne ID-je, letne sezone in zasaditve; primerjava družin je informativna. Android **1.1.3 (6)** je aktivno objavljen na istem internem kanalu za domači (15), 8. oktobra ob22:04. Funkcionalni commit/push `10a9e03`, izrecna izdajna priprava `920a6b4`; podpisana AAB in web release gradnja sta preverjeni. Dokaze in še čakajoči fizični preizkus vodita `docs/REMOTE_REMINDERS.md` in `docs/GARDEN.md`. Uporabnik je izrecno naročil commit/push, merge na privzeti `main` ter novo interno Android izdajo; javna objava ni dovoljena s tem korakom.

Nadaljevanje 9. oktobra: po uporabnikovem posnetku sta izdelana popravek praznega centra ob označenem zvončku in izbirni pogled **Vsi**. Center in oznaka imata skupno projekcijo upravičenih obvestil; dostavljen oddaljeni opomnik ne potrebuje lokalnega alarma. Vsi združi aktivni osebni prostor ter dovoljene aktivne skupne prostore istega računa, ohrani izvor zapisa in ločene finančne pravice/valute ter ne podvoji zasebne sinhronizirane kopije. Izbira je lokalna nastavitev po računu; dodajanje zahteva dejanski prostor. Preverjeno: **677 Flutter PASS/9 opt-in HTTP preskočenih**, analiza brez napak/opozoril (37 obstoječih info), web release in Android debug gradnja. Funkcionalno preverjanje je potekalo pri **1.1.3+6**; shema/strežnik/SDK/odvisnosti so nespremenjeni. Uporabnik je nato izrecno naročil commit/push in novo Android interno izdajo: funkcionalni commit `8c33716`, izdajna priprava `c6e4e95` na `codex/all-spaces-inbox`. Android **1.1.4 (7)** je aktivno objavljen za domači (15), 9. oktobra ob 06:21; podpis, 16 KiB knjižnice in Firebase so preverjeni. Dokaze in čakajoči fizični preizkus vodi `docs/ALL_SPACES_AND_INBOX.md`.

## Način dela

Uporabnik je 9. oktobra zahteval, da so člani, povabila in njihovo upravljanje zbrani v **Nastavitvah prostora**, ne kot stalni gumbi na delovnih zaslonih Danes, Načrti, Finance, Nakupi itd. Naziv izbranega prostora prikazuje zgornji izbor; na organizacijskem delovnem zaslonu ga ne podvajaj. Razlaga članstva sodi v Začetek uporabe. Dodajanje projekta v organizacijo naj bo kontekstno ob projektih. Pri Vsi/lokalnem načinu nastavitve zahtevajo izrecno izbiro skupnega prostora, nikoli tiho prvega na seznamu. Dejanske dokaze izvedbe in izdaje vodi `docs/UPGRADE_IMPLEMENTATION.md`.

Nadaljevanje 9. oktobra po Android preizkusu: sistemski Nazaj vrača področja/podglede, najprej zapre dialog/meni; začetni zaslon Android telefona zahteva drugi pritisk za izhod v dveh sekundah. Zgodovina ne preživi menjave računa, vračanje Vsi → vir → Vsi preverja identiteto in generacijo navigacije. Že vidni taski v Vsi uporabljajo lokalni dialog ter omejeno osvežitev prostora v ozadju, brez celotnega sync računa; finančne tarče in zunanja obvestila ohranijo prejšnje preverjanje. Lokalni editor uporablja naložene ID-je, zasebno lastništvo ozki SQLite SELECT. **715 Flutter PASS / 9 opt-in HTTP preskočenih**, analiza 37 obstoječih info brez napak/opozoril, Android debug in web release uspešna. Funkcionalni commit/push `22ff222` na `codex/navigation-task-opening`; po izrecnem naročilu izdaje je pripravljena **1.1.5+8** (`0c2e332`, končni build `b04c768`). Android **1.1.5 (8)** je aktivno objavljen na istem internem kanalu za domači (15), 9. oktobra ob 07:32. Podpis, manifest/callback, 16 KiB in Firebase so preverjeni; fizični preizkus še sledi. Dokaze in meje vodi `docs/NAVIGATION_AND_TASK_OPENING.md`.

Dopolnitev po uporabniškem pregledu 8. oktobra izrecno odobri šest preostalih vrzeli: telefonski levi meni, finančno povezavo do opravila, uporabno oceno trajanja faz iz razpoložljivosti, začetno vidnost projekta, osebne finančne račune/filtre ter odložitev opomnikov. Izdelane so in preverjene s 544 Flutter PASS/8 opt-in HTTP preskočenimi; analiza ima 37 obstoječih info brez napak/opozoril. Odložitev je napravna nastavitev v local_meta, brez spremembe rokov ali oddaljene dostave in brez prenosa v kopijo. Strežnik/schema/paketi so nespremenjeni; funkcionalni commit/push je `cbcb29d`, izdajna priprava `e9d676f`. Android 1.1.1 (4) je aktivno objavljen na istem internem kanalu za domači (15), dokaz je v `build/qa/jivie-followup/play-internal-1.1.1-4-active.jpg`. Aktualno stanje vodi `docs/UPGRADE_IMPLEMENTATION.md`.

Nadgradnja 8. oktobra je izdelana in lokalno preverjena: organizacije z izrecnimi projektnimi članstvi, en trajni projektni koren, obnovljivo arhiviranje, osebe brez računa, faze/mejniki/koledar/časovnik, atomarni par opravilo–strošek in mesečni finančni načrt. Izvor FamilyHub je 0.7.0/schema11, record3/finance2 in deletion policy2; lokalna schema6, JSON4 in prenosna kopija3 ohranijo stare formate ter vrtove. Izvirni ID-ji/hashi starega čakajočega dela se ohranijo z verzioniranim mostom. Končni izvorni dokazi so 502 Flutter PASS in 987 PHP kontrol na treh bazah; gostovana namestitev FamilyHub 0.7.0/schema11 in aktivna Android interna izdaja 1.1.0+3 sta ločeno potrjeni v `docs/UPGRADE_IMPLEMENTATION.md`. `docs/release/OWNER_NEXT_STEPS.md` je kratek seznam za lastnika.

Prejšnji izid 8. oktobra: popravki `54f3061`, nadgradnje `e73cd1c` in izdajna priprava `b99760d` so poslani na `origin/codex/vsakdan-foundation`. Android **1.1.0 (3)** je aktiven na istem internem kanalu, izbran je samo seznam `domači` (15). Nova fizična namestitev še potrebuje uporabnikov preizkus. Testni strežnik je po izolirani obnovi 79 tabel/98 vrstic/27 zasebnih datotek nadgrajen na FamilyHub 0.7.0/schema11; identitete/gesla/config/cron ohranjeni, FCM izključen. iOS nadaljuje s svežo 1.1.0 (3) gradnjo po Xcode dostopu, ne s starim razvojnim arhivom 2. Javna produkcija in ločen javni repo vtičnika ostaneta nedotaknjena. Dokaze vodi `docs/UPGRADE_IMPLEMENTATION.md`.

Prejšnji usklajeni izdajni korak: glavni commit/push prenove s sporočilom natanko `popolna predelava aplikacije` je pred izrecnim dvigom na `1.0.1+2`. Android te verzije je na internem kanalu, popravljena iOS distribucija še ni potrjena. Zaradi dejanske Apple 90683 zavrnitve uporablja projekt podprti CocoaPods način in samo dokumentni file_picker; SDK/Dart paketi, identitete/baze ter stari artefakti ostanejo ohranjeni. Vrstni red in aktualne meje vodi `docs/release/NOTIFICATION_RELEASE_RUN.md`, odprte korake `docs/release/OWNER_ACTIONS.md`. Uporabnik je 8. oktobra izrecno dovolil začetek Android testiranja brez čakanja na iOS: obstoječi seznam `domači` s 14 člani je izbran in shranjen, Play kanal kaže `Aktivno` za 1.0.1 (2). Isti dan je na uporabnikovo zahtevo dodan še njegov razvijalski račun; seznam ima zdaj 15 članov. iOS testni dostop uredi po uspešni oddaji; naslovov ne ugibaj in ne širi upravljavskih privilegijev. Ločen javni repo vtičnika ostaja nedotaknjen. Ko je lastnik odsoten, izvedi dovoljene rutinske odločitve, obveznih pravnih/dostopnih/napravnih korakov ne obidi; zapiši jih za nadaljevanje.

- Z uporabnikom komuniciraj v slovenščini. Imena razredov, datotek in API metod naj sledijo obstoječim angleškim konvencijam.
- Pred spremembami preglej `git status` in navodila za zadevni del projekta. Ohrani uporabnikove lokalne spremembe; različice aplikacije ne zvišuj kot stranski učinek druge naloge.
- Izvedi dogovorjeni obseg. Za običajne lokalne popravke znotraj tega obsega ne uvajaj dodatnih potrditev. Raziskava gostovanja ni dovoljenje za posege v produkcijske podatke ali namestitev.
- Loči ugotovitve iz kode, rezultate dejanskih preizkusov in predloge. Ne sklepaj o različici živega strežnika iz različice, zapisane v odjemalcu.
- Ohranjaj spremembe pregledne in povezane z nalogo. Izogibaj se hkratnemu prepisovanju aplikacije, menjavi ogrodij in nepovezanemu preoblikovanju kode.

## Kaj ohranjamo in kako razdeljujemo kodo

- O ponovni uporabi povezave s Kanboardom, modelov in finančnih izračunov odloči po pregledu njihove pravilnosti in novega namena. Lokalizacija in čisti izračuni so kandidati za ponovno uporabo, ne obveznost ohranitve starega podatkovnega modela. Nadomestitev posameznega dela utemelji s konkretno omejitvijo.
- Flutter zasloni naj skrbijo predvsem za prikaz in interakcije. Nalaganje, zapisovanje, preverjanje podatkov in poslovna pravila postopoma prestavljaj v ločene, preizkusljive enote.
- Uporabljaj obstoječi Riverpod in GoRouter, dokler ni dogovorjen razlog za spremembo. Nove domenske logike ne dodajaj v že velike datoteke zaslonov.
- Strežniške pogodbe in pretvorbe podatkov sodijo v podatkovno plast, ne v gradnjo widgetov. Finančni izračuni naj ostanejo neodvisni od UI in omrežja.
- Uporabniška besedila dodajaj v `lib/l10n/app_sl.arb` in `lib/l10n/app_en.arb`. Datoteke `app_localizations*.dart` generiraj z `flutter gen-l10n`; ne urejaj jih ročno.
- Platformno kodo izoliraj. Prisotnost mape za platformo ne dokazuje, da aplikacija na njej deluje. Pri spremembah UI preveri dogovorjene mobilne in namizne širine.

## Strežnik in Kanboardovi vtičniki

Uporabnik je 7. oktobra 2026 izrecno dovolil neposredno nastavitev na prijavljenem cPanel gostovanju, vključno z novo testno poddomeno, svežim Kanboardom in nastavitvami self-hosted možnosti. Prvi poseg uporablja ločeno `jivie-test.triparna.si` z lastno bazo, brez prenosa starih podatkov. To ni dovoljenje za izbris obstoječih produkcijskih podatkov. Dejanske namestitvene dokaze vodi `docs/server/CPANEL_SETUP.md`.

Trenutno gostovanje je cPanel. Pregled 4. oktobra 2026 je pokazal Kanboard 1.2.54 v evidenci Softaculous, PHP 8.4 v nastavitvah računa, prazno mapo `plugins`, cron z možnostjo minutnega intervala in spletni terminal z odprtim pozivom lupine. Oddaljeni SSH, dejanska baza in SMTP niso preverjeni. PHP nastavitve računa onemogočajo `mail()` in izvajanje sistemskih procesov. Podrobnosti in meje tega pregleda so v README. Izolirani razvojni okolji Docker s Kanboardom 1.2.54, SQLite oziroma MySQL ter vtičnikom FamilyHub sta v `server/`; navodila v `docs/server/README.md`.

Poznejši dejanski zajem varnostne kopije istega dne je potrdil `DB_DRIVER=mysql`, datoteke v `data/files` in prazno mapo vtičnikov. Glava izvoza poroča podatkovni strežnik 10.11.19 in PHP 8.4.25. Kopija baze je bila uspešno obnovljena v omrežno izoliranem lokalnem MySQL 8.4.11; to dokazuje obnovo kopije, ne enakega pogona/različice kot na gostovanju. Zasebne varnostne kopije, konfiguracije in podatkovni izvozi ostanejo zunaj repozitorija in zunaj mape, ki jo ponuja arhivski brskalnik.

- Kot izhodišče preverjaj razširitev prek vtičnikov in obstoječih Kanboardovih modelov. Jedra ne spreminjaj brez konkretno dokazane potrebe in dogovorjene smeri.
- Kanboard obravnavaj kot kandidata za izbirno strežniško sodelovanje in povezavo z obstoječimi podatki. Lokalno ustvarjanje, branje in urejanje ne smejo zahtevati njegove dosegljivosti ali njegovih identifikatorjev. Nova sinhronizacija uporablja lastne tabele vtičnika. Spremembe iz Kanboardovega spletnega vmesnika zajemi le za objekte, ki jih bo izrecno dovoljeno urejati tudi tam; novih skupnih tabel trenutno ne ureja.
- Rešitev za produkcijo naj bo izvedljiva brez SSH, Dockerja na strežniku ali stalno delujočega procesa. Odvisnosti in namestitveni paket pripravi lokalno; omejitve gostovanja preveri pred izbiro mehanizma.
- Nove podatkovne module umesti v lastne tabele z migracijami za dejansko podprte baze. Ne razširjaj shranjevanja kompleksnih skupnih podatkov v razrezane projektne metapodatke.
- Določi različico pogodbe API in način preverjanja zmožnosti vtičnika. Stara aplikacija in nov strežnik ter obratno morata imeti opredeljeno vedenje.
- Za vsako novo metodo preveri identiteto, vlogo in dostop do konkretnega objekta na strežniku. Kanboardov spletni ACL in API ACL sta ločena; registracija metode sama po sebi ne zagotovi pravilnih pravic.
- Stara razvojna povabila za Kanboardove projekte in novi Native API sta v namestitvenem paketu privzeto izključena z ločenima nastavitvama. Novi obsegi, članstva in zapisi so v lastnih tabelah FamilyHub; ne vključujejo starih projektov ali finančnih metapodatkov. Starih povabil ne vključuj za resnične projekte, dokler zasebnost njihovih finančnih metapodatkov ni urejena.
- Testno okolje naj posnema potrjene različice in bazo gostovanja. Za migracije predvidi varnostno kopijo, preverjanje uvoza in postopek povrnitve. Obstoječih zapisov ne briši pred uspešno preverjenim prenosom.

## Računi, gospodinjstva in deljenje

- Uporabnik je 10. oktobra 2026 izrecno popravil tok povabil: pošiljatelj vnese **e-poštni naslov**, strežnik pošlje povabilo, novi uporabnik si v aplikaciji izbere uporabniško ime/geslo, obstoječi se prijavi. Nato oba **ločeno sprejmeta čakajoče povabilo**, kar odpre prostor; registracija sama ne podeli članstva. Preverjaj potrjeno e-poštno identiteto, ohrani povabilo skozi registracijo/prijavo in jasno pokaži uspeh. Stara povabila na username so združljivost, ne novi glavni tok. Izvedbo in dejanske dokaze vodi [povabila po e-pošti](docs/EMAIL_INVITATIONS.md); ne predstavljaj izvedbe v teku kot že nameščene.
- Prijava obstoječega uporabnika, ustvarjanje računa in sprejem povabila so različni postopki. Cilj je, da jih uporabnik opravi v aplikaciji.
- Uporabniški izbris računa je v tej fazi namenjen samo samostojnemu gostovanju (self-hosted). Odstrani dejanski uporabniški račun Kanboarda in njegove podatke po strežniškem predogledu, ne le povezave v aplikaciji. Pravila prihodnjega upravljanega gostovanja in njegove hrambe so ločena, še nedoločena faza. Podpora izbrisu je strežniška zmožnost; odjemalčev preklop je ne more vključiti. Potrebni so svež predogled, ponovna overitev, izrecne odločitve za lastništvo/skupne strukture ter preverljiv izid po izgubljenem odgovoru. Ne briši produkcijskih uporabnikov za preizkus. Meje starega Kanboardovega spletnega vmesnika in ohranjenih urejanj tujih zapisov opiši; ne razglašaj popolnega odstranjevanja vseh kopij ali potrjene skladnosti trgovin.
- Ne vključuj globalnega Kanboardovega `jsonrpc` ključa ali skrbniškega gesla v odjemalca. Ne uvajaj samodejnega prehoda z uporabniške identitete na privilegirano identiteto.
- Nova prijavna pot je FamilyHub Native API v1: lokalno geslo in TOTP, omejevanje poskusov, preklicljive napravne seje ter časovno omejena povabila. Pogodba je v `docs/server/native-api-contract.md`. FamilyHub 0.5.0 doda prvi račun z upraviteljsko enkratno kodo, preverjanje e-pošte in obnovo gesla prek ločene šifrirane SMTP vrste; pogodba je v `docs/server/account-api-contract.md`. Na novi testni namestitvi `jivie-test.triparna.si` je 7. oktobra 2026 SMTP nastavljen in TLS/prijava preverjena. Uporabnik je 8. oktobra potrdil dejanski prejem potrditvene e-pošte in uspešno uporabo kode na Androidu; manjkajoča sporočila o uspehu registracije/preverjanja naslova so zapisana v načrtu prenove. Obnova gesla in običajna e-poštna obvestila ostajajo ločeni nepreverjeni tokovi. Stari produkcijski strežnik ostaja ločen. Zunanji prijavni ponudniki niso podprti; ne obidi njihove avtentikacije.
- Deljenje projekta ne pomeni deljenja računa. QR oziroma povezava za povabilo ne sme vsebovati trajnega gesla ali osebnega API ključa.
- Osebni prostor, gospodinjstvo in deljeni projekt so ločeni pojmi. Njihov končni podatkovni model uskladimo z uporabnikom; članstva ne enači s samodejnim dostopom do vseh modulov.
- Finance se smejo deliti v istem domu ali izrecno tako zasnovanem projektu; osebne finance niso trajna produktna omejitev. Pred finančno izvedbo določi skupni finančni obseg in pravice do branja/urejanja. Članstvo zunanjega sodelavca v projektu ne odpre zasebnih financ doma. FamilyHub 0.3.0 uporablja ločeno finance pogodbo; finančnih zapisov ne dodajaj v splošni sync2.
- Pravice do opravil in do zasebnih financ preverjaj ločeno, tudi pri izvozu, priponkah, obvestilih in AI kontekstu. Skrivanje zavihka ni nadzor dostopa.
- Preklic članstva mora ustaviti nadaljnji strežniški dostop. Preveri tudi skupinske pravice in ravnanje z že prenesenimi lokalnimi podatki.

## Podatki in zanesljivost

- Za local-first načrtuj trajno lokalno bazo in podatkovno plast, iz katere bere UI. Lokalni zapis in evidenco spremembe za vključeno sinhronizacijo shrani atomarno; izpad povezave ali ponovni zagon ne smeta izgubiti čakajočih sprememb. Predpomnilnik prenesenih odgovorov te zahteve ne izpolni.
- Prvotna osebna shramba Hive ostane ohranjen vir selitve v per-record SQLite (lokalna schema 4). Selitev shrani vse zapise in oznako uspeha atomarno; poškodovanega ali novejšega formata ne ponastavljaj. Osebna projekcija ima omejitev 10 MiB/50.000 zapisov. Revizijo preverjaj skupaj z identiteto prostora; testi dveh naprav niso dokaz usklajenega prikaza v več procesih iste namestitve.
- Vrt uporablja lokalno schema 5 in `device_gardens`, brez računa/sinhronizacije. JSON v3 in prenosna kopija v2 vključujeta vrtove; stare kopije jih ohranijo. Trajne revizijske meje po izbrisu preprečujejo ponovno veljavnost starega urejevalnika po obnovi istega ID-ja. Obseg in dokazi so v `docs/GARDEN.md`.
- Nadaljevanje 5. oktobra 2026 zajema prvi vstop, izbirno zasebno sinhronizacijo ter šifrirane kopije/obnovo; Google Play Console je odložen. Izvedbo in aktualne dokaze vodi `docs/PERSONAL_SYNC_AND_RECOVERY.md`. Osebni strežniški prostor je izključno lastnikov, prijava ne pomeni soglasja za prenos podatkov. Tudi nadaljnji lokalni zapisi po odjavi ali obnovi potrebujejo izrecen prenos. Osebne finance uporabljajo `personalFinanceEntry` v ločeni finančni pogodbi, ne splošnega sync2.
- Osebni in skupni podatki uporabljajo skupno SQLite/Drift povezavo z ločenimi prostori ter transakcijami nad zapisi, odhodnimi operacijami, konflikti in kazalci. Odpiranje baze ni odvisno od poverilnic. Lokalni račun loči po normaliziranem strežniku, trajnem `serverId` in `accountId`; številčni ID uporabnika ni dovolj. Zahteve in odprte urejevalnike pripni identiteti, ki jih je začela, ter zavrni pozne odgovore/zapise po menjavi. Spletna shramba ne sme tiho pasti na pomnilnik ali nekoordiniran IndexedDB. Kopija v prostor drugih članov se deli samo izrecno, z novimi ID-ji in brez financ.
- Prenosne kopije `.vsakdan` uporabljajo overjeno šifriranje in omejeno izpeljavo ključa. Ne vsebujejo sej ali skrivnosti dostave in ne potrjujejo pravic. Obnovljeno skupno/zasebno strežniško delo ostane šifrirano v območju za obnovo, nadaljevanje pa potrebuje isto identiteto, sveže pravice in izrecno dovoljenje. Ohrani izvirne ID-je nespremenljivih operacij in lokalne preslikave; zgodovinskega `conflict.remote` ne postavi nad sveži kanonični zapis. SQL podatke in dnevnik nastavitev obnovi atomarno, SharedPreferences nato ponovljivo. Dodatno šifriranje aktivne baze s tem ni rešeno.
- Identiteta lokalnega zapisa mora nastati brez strežnika; povezavo s Kanboardovim ID vodi ločeno. Sinhronizacija potrebuje pravila za sočasne spremembe, izbrise in ponavljanje zahtev. Pri spornih finančnih spremembah ne uporabljaj tihega prepisovanja zadnje različice.
- Poverilnice in API ključe hrani v varni shrambi. Ne uvajaj rezervnega shranjevanja skrivnosti v `SharedPreferences`; obstoječa problematična mesta so opisana v README.
- Za produkcijske povezave uporabljaj HTTPS. Avtentikacijskih podatkov ne posreduj na drug izvor ali na HTTP ob preusmeritvi.
- V dnevnike ne zapisuj gesel, žetonov, QR vsebine, zasebnih finančnih podatkov ali teles uporabniških zahtev in odgovorov.
- Lokalno shrambo, vključno s predpomnilnikom in AI pogovori, loči po lokalnem profilu oziroma strežniku in uporabniku; pri novih prostorih tudi po ustreznem obsegu. Odjava in menjava računa morata imeti določeno čiščenje, brez tihega izbrisa osebnih lokalnih ali še neusklajenih podatkov.
- Predvidi izvoz, varnostno kopiranje in obnovo lokalnih podatkov brez odvisnosti od strežnika. Sinhronizacija sama ni varnostna kopija. Določi varovanje lokalne baze in priponk ter razpoložljivost priponk brez povezave.
- Arhiv starega sistema loči od uvoza v novi organizator. Ohrani izvirne izvožene zapise, nepoznana polja, metapodatke, povezave in priponke; model `fromJson/toJson` ni dokaz brezizgubnega izvoza. Arhivski brskalnik mora delovati brez starega strežnika. Nepopoln izvoz mora ostati označen kot nepopoln; upokojitev je mogoča šele po preverjenem zajemu, obnovi in dogovorjenem končnem preklopu.
- Preklica dostopa ni mogoče takoj uveljaviti na nepovezani napravi ali z njim zagotoviti izbrisa že pridobljene kopije. Ob ponovni povezavi preveri pravice; zavrnjenih sprememb ne izgubi tiho in jih ne pošiljaj pod drugo identiteto.
- Finančne zneske obravnavaj v najmanjših denarnih enotah skupaj z valuto. Različnih valut ne seštevaj brez izrecnega pravila pretvorbe.
- Potrjena finančna zasnova loči plačnika/prejemnika, finančni račun in avtorja vnosa. Skupna tabela omogoči pregled po članu/računu in sled sprememb. Prenos med računi ni nov prihodek ali strošek v skupnem seštevku; osebna vsebina se ne deli samodejno.
- Pri skupnem urejanju uporabljaj posamezne zapise, strežniško preverjanje revizije in jasno obravnavo konflikta. Ponovitev zahteve ne sme podvojiti stroška, povabila ali drugega pomembnega zapisa.
- Obvestila in opomniki v aplikaciji so izrecna obvezna zahteva uporabnika. Finančna prenova jih ne sme odložiti na nedoločen čas. Loči »dodano opravilo v skupnem prostoru« od »dodeljeno tebi«: tudi nedodeljeni člani dobijo obvestila o skupnem dogajanju, osebno naslovljeni prejemnik pa jasno oznako. Nakupovalni dodatki/seznami so vidni in se lahko združijo; posamezni artikli privzeto ne pošiljajo e-pošte. Prebrano obvestilo ne pomeni zaključenega opravila ali plačanega računa. Podrobnosti vodi `docs/RENOVATION_PLAN.md`.
- Center obvestil in telefonska obvestila naj odprejo konkretni zapis oziroma nabor zapisov iz združenega obvestila v pravem računu in prostoru, z novim preverjanjem pravic. Isti dogodek istemu prejemniku ne ustvari podvojenega splošnega in osebnega opozorila. Dnevni pregled gospodinjstva in projektna časovnica vključita izvajalce ter termine samo za skupno vidno vsebino; izvedbo in dokaze dodelitev, skupnega dneva ter časovnice vodi `docs/FAMILY_UPGRADE.md`.
- Lokalna finančna politika ima revizijo in generacijo dostopa. Sprememba politike takoj razveljavi popolnost prenesene projekcije; zakasneli uspešen odgovor po znani zavrnitvi ne sme obnoviti dostopa. Audit in izvoz po čakanju ponovno preverita trenutne pravice. Čakajoče zavrnjeno delo ohrani, vendar ga ne vključi v vidne seštevke.
- Uporabnik je 5. oktobra 2026 izbral Firebase Cloud Messaging s paketom Spark. Pripravo vodi `docs/FIREBASE_PREPARATION.md`, konfiguracijo `docs/NOTIFICATION_SETUP.md`. Projekt `jivie-e928a` in obe registraciji `si.triparna.jivie` so 7. oktobra dejansko ustvarjeni; lokalna konfiguracija je vključena v gradnjo in ignorirana v Gitu. HTTP v1 API je omogočen. Strežniška FCM identiteta je 8. oktobra nameščena na testni cPanel; OAuth in FCM validacija brez dostave (HTTP 200) sta preverjeni, javni API oglašuje externalPush in pravi projekt. Uporabnik je nato potrdil prejem testnega opomnika na zaklenjenem Samsungu S25 in klik do pravega opravila. Minutni push cron je dodan; APNs še manjka. Ta preizkus ne potrjuje novega UI za ustvarjanje oddaljenih razporejenih opomnikov; njegovo izvedbo in ločeno preverjanje vodi `docs/REMOTE_REMINDERS.md`. Dokaze in povrnitev vodi `docs/server/CPANEL_SETUP.md`, razdelek 13. FCM je izbirni Android/iOS kanal, brez Firebase Auth, Firestore, Analytics ali Cloud Functions. Strežniški ključ in APNs `.p8` ostaneta zunaj odjemalca/repozitorija. Brez konfiguracije se kanal ne aktivira. Ne označi uspešne registracije pri FamilyHub ali nadomestnega transporta kot dokaz dejanske dostave.
- Push naj bo dostavni kanal za shranjeno obvestilo. Predvidi ponovne poskuse, preprečevanje podvajanja, časovne pasove in preverjanje pravic ob odprtju. Razporejanje mora delovati z dejansko razpoložljivim cronom oziroma dogovorjenim nadomestilom.
- Lokalne opomnike za podatke na napravi loči od obvestil o oddaljenih spremembah. E-pošta in oddaljena dostava potrebujeta povezavo; lokalno shranjevanje ne sme čakati nanju. Usklajevanje ne sme podvajati opomnikov ali pošiljati zastarelih obvestil za vsako vmesno spremembo.
- AI naj bo neobvezen; osnovne funkcije morajo delovati brez njega. Posreduj le podatke, do katerih ima uporabnik pravico in za katere je omogočil takšno uporabo.

## Preverjanje sprememb

- Za spremembe Dart kode formatiraj spremenjene datoteke in izvedi `flutter analyze` ter teste, ki preverjajo prizadeto vedenje. Za spremembe prevodov izvedi tudi `flutter gen-l10n`.
- Po menjavi Flutter SDK najprej uskladi odvisnosti z `flutter pub get` in preglej spremembe `pubspec.lock`. Napake zaradi starega `.dart_tool` loči od napak aplikacije; SDK ali odvisnosti ne nadgrajuj nepovezano z nalogo.
- Prednost imajo testi finančnih izračunov, pravic med različnimi uporabniki, sočasnega urejanja, migracij, odjave in prijave. En test začetnega zaslona ne potrjuje celotne aplikacije.
- Local-first preveri z zagonom brez računa in povezave, ustvarjanjem in urejanjem, ponovnim zagonom ter izvozom in obnovo. Za sinhronizacijo preveri dve napravi, sočasne spremembe, ponovljene zahteve, izbrise, konflikte in preklic pravic.
- Pri strežniških spremembah preveri tako dovoljene kot zavrnjene dostope ter združljivost z dogovorjeno različico Kanboarda. Za to uporabljaj testne račune in podatke.
- Za dokumentacijske spremembe preveri dejstva, povezave, primere ukazov in `git diff --check`; aplikacijskih testov brez razloga ne ponavljaj.
- Ob predaji povej, kaj je spremenjeno, kaj je bilo preverjeno in katere omejitve ostajajo. README posodobi, kadar se spremeni dejansko stanje ali dogovorjena smer.
