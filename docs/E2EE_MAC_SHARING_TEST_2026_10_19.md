# Dve ločeni macOS namestitvi: deljenje E2EE — 19. oktober 2026

Uporabnik je odobril nadaljevanje odprtih funkcionalnih preizkusov na dveh
ločenih Mac namestitvah. Osnova je `36139e8` (poenostavitev deljenja).
Preizkus se po uporabnikovem odklepu Maca nadaljuje. Potrjeni so
izolacija, začetna nastavitev A/B, isti A prostor/projekt, popravljena
mirovalna sinhronizacija, eno A opravilo in eno povabilo B. Registracija B,
FILE, prvi sprejem in popravljeni prikaz čakanja so uspešni. Prva odobritev
A je aktivirala krovni prostor, ob projektu pa zadela omejitev zahtevkov;
r4 popravek je uspešno nadaljeval isti shranjeni projekt. B je v dejanski
aplikaciji prebral eno prvotno opravilo z opombo A-V1. Dvosmerno urejanje,
offline nadaljevanje, neposredni projekt in odvzem
dostopa še niso potrjeni.
Nadaljevanje je na istih podatkih; ne ponavljamo registracije A ali FILE
čarovnikov. Produkcija, stare namestitve in mobilni checkpoint ostajajo isti.

## Izolacija

Pripravljeni sta novi `Jivie Test Share A` in `Jivie Test Share B`, vsaka z lastnim
bundle ID, sandbox vsebnikom, Keychain service/skupino in testnim računom.
Stare aplikacije, Mac A/B/C/D podatki, mobilni checkpoint in produkcija se
ne uporabljajo ali prepisujejo. Dva nova paketa vsebujeta isti poslovni izvor;
ločena sta samo identiteta namestitve in pregledana QA konfiguracija.

Pred gradnjo: po 581 vhodov iz `36139e8`, vključno s skupnim
`apple/JivieLegacySecrets.swift`; po 18 naštetih QA/izolacijskih sprememb.
Podagenta in glavni pregled potrjujejo ohranjene poslovne poti, omejeno
zaupanje javnemu CA samo za točen testni API, zasebno shrambo ter logger
brez surovih sporočil izjem. To je pregled izvora, ne dokaz nameščenega paketa.

Identiteti sta `si.tripar.jivie.e2eetest.sharea20261019` in
`si.tripar.jivie.e2eetest.shareb20261019`; Keychain service je vsakokrat
`<bundleId>.secure-storage`, skupina pa samo `CXNM99632B.<bundleId>`.

Oba podpisana kandidata sta bila pred namestitvijo neodvisno pregledana:
dejanski strict/deep podpis, entitlements, lastna edina Keychain skupina,
sandbox, identiteta in hashi izvršilne datoteke/AOT ustrezajo manifestoma.
Ni URL handlerjev ali produkcijskega Firebase plist; oba ciljna paketa in
vsebnika sta bila pred namestitvijo odsotna. Po ena zaporedna gradnja na
aplikacijo, nespremenjeni SDK/locks/verzija 1.10.1(31). Manifest A SHA256
`fae0f8e82f9123f41331237fed42f766531a68948d1478a9e7728bd54564e708`,
B `da1408c07a36a7b44f1b8a0335acd9e8721474e3495b861dcf7ce18391cd82a4`.
Oba sta bila nato nameščena z varovalom odsotnega cilja in preverjanjem
nameščenih hashov. A prvi zagon PID90596 ima aktivni omejeni zajem od zagona.
En native Save/re-pick nove lokalne obnovitvene datoteke ter »Encrypt local
database« odpreta običajni Personal/Pulse, brez opažene napake. Posnetek in
AX `n0-a-local-ready.*` sta v zasebnem imeniku tega teka; glavni agent je
vizualno potrdil običajni zaslon A. To še ni račun ali deljenje. B je v tej
točki nameščen, vendar še ni zagnan.

Novi Docker projekt `jivie-mac-sharing-test-20261019` uporablja lastne
podatkovne poti/omrežje in samo loopback objavljena vrata. Pošta gre v lokalni
Mailpit; ni zunanjega SMTP ali FCM/APNs. HTTPS testnega povabila uporablja
lastni testni CA, vezan samo na točen QA cilj v testnih paketih; sistemsko
zaupanje certifikatom se ne spreminja.

Strežniška pripravljenost je potrjena: API `https://127.0.0.1:18811/`,
Mailpit `http://127.0.0.1:18812/`, serverId
`de0ba2af-4d9d-4e4d-a7b6-1b8875042d4c`, schema20, pred začetkom nič Native
računov/prostorov/zapisov. Dejanski mounti so samo novi QA viri in lastni
volumni, DATA_DIR je `/private-data` zunaj webroot. Upravljavec je izrecno
»Jivie lokalni test«, zunanje potisne dostave so izključene. Docker je imel
izčrpan privzeti nabor podomrežij; samo novi projekt je dobil dve preverjeno
prosti eksplicitni podomrežji, brez posega v obstoječa omrežja/vsebnike.
Omejitve zahtevkov ostajajo izvorne. Dokaz: `server/readiness.json` in
`server/compose.yaml` v imeniku tega QA teka.

Zasebne testne poverilnice, obnovitvene datoteke in baze so zunaj Git v
namenskih zasebnih imenikih. Sanitizirani dokazi in kontrolni seznam so v
`build/qa/jivie-mac-sharing-test-20261019/`. Diagnostika teče od začetka;
beleži fazo/kodo napake/čas, ne gesel, žetonov, ključev ali teles zahtevkov.

## Zaporedje in kontrolne točke

| Korak | Kaj potrjujemo | Stanje |
| --- | --- | --- |
| 0 | Podpis, lastna shramba, izolirano gostovanje, pripravljeni dnevniki | Oba nameščena; oba lokalna čarovnika uspela |
| 1 | A račun, prostor/projekt/opravilo; B zaseben lokalni kontrolni vnos in poznejša registracija skozi povabilo | PASS; B e-pošta/računski FILE pripravljena, lokalni vnos ohranjen pred sprejemom |
| 2 | Eno povabilo brez kartic, vidno čakanje, lastnikova odobritev in odklep že obstoječega projekta | PASS po r3/r4 popravkih; B prebere isto opravilo/A-V1; visok strošek in429 ostajata omejitev |
| 3 | Sprememba istega opravila v obe smeri, brez podvojitve ali objave B lokalnega vnosa | Čaka |
| 4 | Kratka prekinitev povezave in ponovni zagon, nato nadaljevanje istega čakajočega dela | Čaka |
| 5 | B dobi samo projekt ločenega A prostora; nadrejeni prostor in sorodni projekt ostaneta nedostopna | Čaka |
| 6 | Odvzem dostopa prepreči prihodnji prenos/spreminjanje; prej prenesena kopija ni obljubljena kot izbrisana | Čaka |

### Začetna nastavitev — sprotni zapis

A je ob 04:48 UTC z eno oddajo »Create account« dosegel računski FILE
čarovnik, brez opažene napake. Pred oddajo je oddaljeni AX prikaz polj
zaostajal za dejansko izrisanim obrazcem; po enem čistem vnosu z ločenim
izborom polja in tipkanjem sta se prikaz in zasebna kontrola vnosov ujemala.
To je ovira avtomatizacije pred oddajo, ne potrjena napaka registracije.
Ni ponovljene registracije ali novega računa za obvoz. Prikaz gostovanja
v obrazcu vsebuje točen lokalni HTTPS cilj in »Jivie lokalni test«.

A je nato potrdil e-pošto in shranil/ponovno izbral novo računsko datoteko;
čarovnik je prikazal pripravljene ključe in končal prazni katalog. Po vrnitvi
pregled računa še prikazuje stare rezultate. Izvorni pregled potrjuje dva
ločena enkratna Future: `AccountEmailCard` za e-pošto ter
`SharingPendingInvitations` za napako prejšnjega branja povabil; vrnitev iz
čarovnika ju ne osveži. Eno statusno osveževanje je naslednji diagnostični
korak. Ločeno omejeni časovni kontroli dnevnika (92 oznak ob 04:50:01 UTC,
140 ob 04:50:56, mtime 04:50:55.787) sprva kažeta nadaljnje oznake napake.
Pregled faz in izvornega loggerja popravi interpretacijo: vseh 48 dodatnih
oznak je `stage=sharing`, ki beleži tudi ponovni izris shranjene napake.
Vseh osem dejanskih `stage=sync` oznak je pred vrstico 56, torej pred obema
kontrolama; dodatni izrisi niso dokaz aktivne napake po koncu čarovnika.
B prvi zagon PID91661 je zaključil lastni lokalni FILE čarovnik in shranil
eno `LOCAL-B-PRIVATE` opravilo v Personal, brez povezave z računom.

En »Try again« je odstranil shranjeno opozorilo, en običajni prehod
Pulse→Account pa je prikazal potrjeno e-pošto brez opozorila o zaščiti.
`n0-a-account-refreshed.*` potrjuje pripravljen račun A. FILE, registracija
in preverjanje e-pošte se niso ponovili. Osveževanje po vrnitvi iz čarovnika
ostaja potrjena UI pomanjkljivost; ozek izvorni popravek je ločen od trenutno
nameščenih testnih kandidatov.

### Delno ustvarjeni projekt in omejitev zahtevkov

A je ustvaril krovni `MAC-SHARE-SPACE` (ime v tem teku ustreza načrtovanemu
`MAC-PARENT-1`). Prvi in edini Submit za `MAC-CHILD-1` je ob 04:53:01 UTC
vrnil `rate_limited`. En read-only strežniški zajem ob 04:54:24 potrdi:
krovni prostor in otroški obseg sta aktivirana v epoch1, otrok ima metadata
in financeAccountChoice, kanoničnega project zapisa pa še nima. Tri dejanske
HTTP429, prva na `crypto2.records.batch`; 42 shranjenih crypto receiptov ima
status200. To ni uspešno dokončano ustvarjanje projekta.

Obstoječi metapodatkovni zajem pokaže 439 crypto zahtevkov v 20 sekundah
pri odprtem mirujočem obrazcu. Izvor in časovni vzorec ločita nepotrebna
status/catalog zahtevka vsake tri sekunde ob osveževanju stanja ter večje
sunke redne približno 12-sekundne sinhronizacije (ponavljajoče preverjanje
head/directory/pull/inventory/baseline). Popravek startup odvisnosti sam ne
odpravi celotnega stroška sinhronizacije; kvote ostanejo nespremenjene.

Natanko novi A PID90596 je bil ob 04:56:35.850 UTC začasno ustavljen s
SIGSTOP, z ohranjenim obrazcem in pomnilnikom. Pregled potrjuje, da isti
Submit uporabi iste createId/requestId in trajne dnevnike ter kanonični
project UUID. Odobreno je eno nadaljevanje po več kot 60 sekundah naravnega
izteka omejitve, ne nov projekt ali ponavljanje brez novega dokaza.
Dokazi so `server/n1-child-create-primary-readonly.json` in
`server/n1-traffic-amplification-existing-capture.json` v QA imeniku.

Nadaljevanje: SIGCONT istega procesa ob 04:57:47.151 UTC, en isti Submit
ob približno 04:57:53. Strežnik potrdi en `records.batch` HTTP200 ter nič
novega scope.create/headPut/activate. UI ob 04:58:15 prikaže »Project created.
You can now invite collaborators or open the project.« A je nato normalno
zaprt; točen konec zajema 04:58:17.423981 UTC. Posnetek
`n1-a-child-resumed-success.*` in `server/n1-controlled-resume-http-final.json`
ločita uspešno nadaljevanje istega delnega zapisa od neuspešnega gladkega
prvega ustvarjanja. Po premoru je bilo zaznano tudi `sync_lease_lost`;
samega vzroka brez dodatnega dokaza ne določamo. V istem nadaljevanju je
601 crypto zahtevkov v 26 sekundah ponovno povzročilo en HTTP429 na
scopeObservations, zato uspešen projekt ne zaključi težave obremenitve.
Opravilo v projektu in povabilo B še nista ustvarjena. Pred nadaljevanjem
je potreben ozek popravek ponovljenih preverjanj z ohranjenimi varnostnimi
mejami, nato nadgradnja teh istih testnih namestitev.

### Izvorni popravki in meritev stroška — še brez nove native gradnje

- Osveževanje obeh povzetkov po uspešno dokončani zaščiti je vezano na
  trenutni račun/napravo in ProviderContainer: 5 novih ciljnih testov PASS,
  obseg analize čist. Ne ponovi FILE ali računskih mutacij.
- Startup preverjanje zdaj spremlja identiteto namesto vsake spremembe
  sodelovalnega stanja: 2 nova ciljna testa PASS, 0 error/0 warning ter
  7 obstoječih info. Prvi pregled in izrecna invalidacija ostaneta sveža.
- Prazen preflight finančnih odvisnosti preskoči drago preverjanje samo,
  če ni natanko ustreznih čakajočih neparnih dependency zapisov. Poznejši
  finančni prehod in task-cost predhodniki ohranijo sveže pravice/urejeno
  pošiljanje. 4 novi ciljni testi PASS in neodvisni izvorni pregled PASS.

Ločen kratkoživ Docker fixture uporablja isti strežniški izvor in nespremenjeno
omejitev 600 crypto zahtevkov/minuto. Običajna sinhronizacija nespremenjenega
krovnega prostora/projekta: osnova 283 zahtevkov/2000 ms, po samo praznem
preflight popravku 232/1665 ms (18 % manj). Oba merjena prehoda brez429 ali
lastError, vendar to še ni dovolj za stalno 12-sekundno sinhronizacijo dveh
aplikacij. Dokaza `server/sync-cost-baseline.json` in
`server/sync-cost-empty-preflight.json`. Nadaljnji popravek potrebuje omejeno
ponovno uporabo že preverjenih dokazov znotraj istega kratkega branja;
varnostne meje in predlog se pregledujejo pred implementacijo. Ni trditve,
da je native omejitev že odpravljena.

Nadaljnja meritev uporablja trajno ohranjeno zasebno sintetično stanje istega
actorja, brez ponavljanja registracije. Ustaljena osnova s praznim preflight
popravkom: 220 zahtevkov, brez checkpoint/receipt zapisov. Izrecno odjemalsko
označeni background policy-only branji (tudi pri linked payments) ohranita
sveže podpisane pravice, izpustita pa dvojni izračun aggregate coverage.
Običajni polni finance pull ostane obvezen; UI in legacy fallback ostaneta
polna. Stara preverjena coverage se ohrani samo ob enakih sedmih poljih pravic,
spremenjene/zavrnjene pravice jo razveljavijo, sočasna sprememba generacije
ostane pending. 11 novih ciljnih kontrol in neodvisni izvorni pregled PASS.
Meritev istega pripravljenega stanja: 164 prvi in 158 ustaljeni zahtevki,
brez novih checkpoint/receipt zapisov, omejitev ali napake. Dokaza
`server/sync-cost-preserved-baseline.json` in `server/sync-cost-policy-only.json`.
To je 28 % manj od ustaljene osnove, še vedno pa preveč za dve 12-sekundni
samodejni sinhronizaciji. Predlagani širši same-sync authority cache ni
implementiran; naslednji pregled je omejen na že obstoječo kratko operacijo
pri iskanju že znanih ključev. Manjkajoči ključi ohranijo sveži admission/final
meji. Native deljenje ostaja nedokončano.

Še manjši popravek začetnega iskanja že ohranjenega ključa uporabi
obstoječo, še veljavno kratko bralno operacijo. Meji za pridobivanje
manjkajočega ključa ostaneta sveži; pravi pull, ACL, vezava branja in preverjanje
zapisov ostanejo. Deset prizadetih admission kontrol PASS, od tega tri nove;
neodvisni pregled PASS. Isti ohranjeni merilni fixture po popravku:
146 prvi in **140 ustaljeni zahtevki**, brez checkpoint/receipt zapisov,
omejitev ali napake (`server/sync-cost-existing-operation.json`). Glede na
primerljivo ustaljeno osnovo 220 je to 36 % manj. Prvotnih 283 vsebuje tudi
prve verifikacijske zapise in ni enakovredna ustaljena osnova.

Dve aplikaciji pri 140 zahtevkih vsakih 12 sekund še vedno presežeta skupno
omejitev. Zato sledi pregled minimalnega urnika: lokalni prikaz se osvežuje
na tri sekunde, uspešna mirujoča omrežna sinhronizacija na približno minuto,
novo lokalno delo in uporabnikove zahteve pa ostanejo takojšnje. Napake in
strežniški čas do ponovnega poskusa ostanejo upoštevani. To je zmanjšanje
nepotrebnega mirovalnega prometa, ne dokaz poljubne zmogljivosti v ospredju.
Širši skupni cache kriptografskih pooblastil ni implementiran. Oba native
appa sta normalno zaprta z ohranjenimi podatki; novi urnik in nadaljnje
deljenje še nista native potrjena.

Izvorni urnik je zdaj izveden in pregledan: zadnja dejanska uspešna prazna
sinhronizacija določi naslednji prehod čez 60 sekund; osveževanje lokalnega
prikaza ostane na tri sekunde. Preklop med oknoma ohrani še veljavni rok,
novi vnosi sprožijo takojšnjo dostavo. Vsi dejanski polni začetki in zaključki
imajo ločena obvestila, tudi pri neposrednem klicu repozitorija. Preskočeni
in delni prehodi niso uspeh. Napaka oziroma nespremenjeno čakajoče delo
uporabi 15/30/60 sekund; veljavni Native JSON `retryAfter` (1–86400 sekund)
ima prednost za samodejno dostavo in je vezan na identiteto/generacijo seje.
Ročno osveževanje ostane izrecen takojšnji poskus. Čakajoče delo, napake in
varnostne meje se ne brišejo ali obidejo.

Zaključenih je 27 različnih ciljnih scheduler kontrol (26 v skupnem teku,
nato dve prizadeti kontroli z eno novo; ne nov svež celotni tek 27).
Skupaj ta popravek zajema 52 novih ciljnih unit/widget kontrol ter sedem
prizadetih obstoječih, brez splošne ponovitve matrike. Končna analiza 17
runtime datotek: 0 error/0 warning, 73 obstoječih info; novi scheduler obseg
čist. Neodvisni pregled je ujel in potrdil popravke ohranitve dela med tekom,
ločene identitete časa čakanja, zunanjih začetkov/zaključkov ter pravilnega
prikaza napake po neuspelem lokalnem zaključnem branju. Točni teki in meje
so v `source-test-handoff.md`, izvorni hashi v `runtime-source-freeze.json`
(SHA256 `2dc0ec05566a733c399df648b595537c6c26783de137832176f6334d9573c13d`).

En isti ohranjeni HTTP fixture je dal 146/140 zahtevkov v dveh pravih
prehodih, brez napake ali429. Po vsakem je produkcijski urnik ob 59
simuliranih preklopih fokusa pred 60. sekundo zahteval nič dodatnih prehodov;
ob roku je naslednji dovoljen. To je virtualni časovni dokaz na resničnih
rezultatih odjemalca, ne native meritev stenske ure. Dokaz
`server/sync-cost-idle-scheduler.json`. Handoff 17 runtime datotek je glavni
agent preveril po vsebini/hashih in predal za obnovo istih A/B testnih paketov.
Native deljenje še čaka posodobitev.

Vsak korak se potrdi z dejanskim UI in potrebnim ozkim dokazom sinhronizacije.
Prva napaka ustavi ta korak: zajame se njen izvor, nato se nadaljuje isto
stanje. Ponovni klik brez nove informacije, nova prijava ali novo povabilo
niso diagnostična strategija. Podatki se ne čistijo za prikrivanje napake.

## Posodobitev istih namestitev in trenutni zastoj

Dve novi zaporedni incremental macOS gradnji sta uspeli, po ena za A in B,
brez SDK/locks/verzijske spremembe. Vsak r2 izvor ima 584 preverjenih vhodov;
17 runtime datotek iz odobrenega handoffa, vsi preostali QA/native/TLS vhodi
so isti kot r1. Edini konflikt pri združevanju schedulerja z QA je bil razrešen
z istimi tremi varnimi diagnostičnimi klici v catch blokih; glavni pregled
potrdi nespremenjeno poslovno kodo. Oba dejanska kandidata imata veljaven
strict/deep podpis, iste lastne entitlements/Keychain skupine in profil,
preverjena executable/AOT hasha ter povezavo z izvorom.

- A r2 artifact SHA256:
  `a44ae0b2bf31079a905cb2bd2bbae33f8906fcf6c9e4cbe3a16705f4ceac2867`.
- B r2 artifact SHA256:
  `c0eb35ee28f0d6542a70f67950c8b80eda4730c0b804ba21a1a908a85da64988`.

Oba sta zamenjala samo svoja testna paketa, s starima paketoma ohranjenima
in istima identitetama vsebnikov. Običajni zajeti zagon A PID3403 ob
05:49:03.315 UTC in B PID3415 ob 05:49:07.786 UTC. Novi collector dodaja
čas sprejema oznake na gostitelju, ne časa nastanka dogodka; dovoljene
oznake in omejitve zasebnosti so iste. Ob prvi vezavi CUA je sistem vrnil,
da je Mac zaklenjen in zahteva ročni odklep. Noben nov klik, opravilo ali
povabilo zato ni bil izveden; varovala zaklepa niso obita.

En začetni in en zaključni pasivni pregled obstoječega gateway dnevnika:
05:49:03.315–05:50:51.053 UTC, **307 HTTP zahtevkov, vsi200, nič429 ali drugih
HTTP napak**. Prvih161 je skoncentriranih ob05:49:04–06, naslednjih146 ob
05:50:07–13. Drugi prehod se začne 61 sekund po zadnjem zahtevku prvega;
vmes ni starih12-/30-sekundnih prehodov. Povezan je samo A, B ostaja lokalen.
To potrdi dejanski mirovalni interval A, ne še skupne obremenitve dveh
povezanih računov ali deljenja. Dokaz
`server/n1-r2-passive-90s-metadata.json`.

Navadni poskus zapiranja A je prav tako ustavil zaklep CUA; ni bil dostavljen
aplikaciji. Za B enakega blokiranega poskusa nismo ponavljali. Obe novi
aplikaciji ostajata zagnani z ohranjenim zajemom, brez prisilne prekinitve ali
odjave. Zasebni `NATIVE-R2-CHECKPOINT.json` (SHA256
`e6eb60dd9513863b3527396bfbe4eb83b2349d0070844e2767e9bb578a3575db`)
veže pakete/PID/dnevnike in točno stanje nadaljevanja. Ločeni kratkoživi
merilni Docker vsebnik je po preverjanju točne identitete ustavljen in
odstranjen; njegovi zasebni lokalni klientni podatki/metrike so ohranjeni.
Native18811 strežnik/pošta/podatki in vsi drugi projekti so nedotaknjeni.

Naslednji korak po odklepu: na istem A v `MAC-CHILD-1` ustvariti eno
`MAC-SHARED-1` z opombo `A-V1`, nato eno povabilo B. B že ima samo lokalno
`LOCAL-B-PRIVATE`; registracija B gre skozi to povabilo. Nadaljnji N2–N8
koraki iz kontrolnega seznama ostajajo odprti.

## Nadaljevanje po odklepu — isti r2 paketi

Uporabnik je Mac odklenil. Ker je med večurnim čakanjem potekla omejitev
7.200 sekund starih collectorjev, sta bili obe isti namestitvi normalno
zaprti in znova zagnani s svežim zajemom: A PID36169 ob16:06:24 UTC,
B PID36187 ob16:06:29 UTC. Brez gradnje, ponovne prijave ali začetnih FILE
čarovnikov; jedro ustreza commitu `4478236`.

A je samodejno pokazal »Protect connected data« z obema obstoječima prostoroma.
Ozek pregled izvora razloži, da prejšnje potrdilo za prvotni prazni katalog
ne ustreza pozneje razširjenemu seznamu prostorov. Dejansko prikazan »Done«
in besedilo committed pomenita, da sta obsega že preverjena kot zaščitena;
generično opozorilo »not ready« in pomožni gumbi so zavajajoč UI. En običajni
Done je do16:08:30 vrnil normalen Pulse, isti prostor/projekt in zelen oblak.
Ni bilo nove datoteke, inicializacije ali ročnega ponavljanja migracije.
B po ponovnem zagonu dejansko še kaže `LOCAL-B-PRIVATE` v lokalnem Personal.
Izvorne povezave in meja sklepanja so v
`n1-r2-protection-startup-source-finding.md`; zasebne readiness vrstice niso
bile prebrane. Ta izvorni UX problem v tem koraku ni popravljen.

**N1 PASS:** en Save ob16:09:30.474 UTC je ustvaril `MAC-SHARED-1` v istem
`MAC-CHILD-1`. Običajni ponovni prikaz urejevalnika potrdi opombo `A-V1`,
eno opravilo in zelen oblak; nato Cancel brez drugega Save. Glavni agent je
vizualno pregledal `n1-r2-shared-task-A-V1.png`. Bounded gateway zajem do
16:09:58.743:358 HTTP/200, nič429/napak, en records.batch,14 receipt.get,
pet checkpointov in nič novega scope/head/activation. To je strošek dejanskega
vnosa s sinhronizacijo, ne ustaljeni140 idle strošek. Dokaz
`server/n1-r2-task-save-metadata.json`.

**N2 v teku:** en Send ob16:10:56.059 UTC ustvari eno Member povabilo B
za krovni prostor; UI prej jasno pove dostop do sedanjih in prihodnjih
projektov. Lokalna pošta je pridobljena natanko enkrat v zasebno0600 datoteko,
brez izpisa povezave/žetona. Gateway zajem:15 HTTP/200, en invitations.create,
nič429/napak (`server/n2-r2-parent-invitation-metadata.json`). B nadaljuje
skozi to isto povabilo; sprejem in odklep še nista potrjena.

### B registracija, FILE in dejanski sprejem — popravek nadaljevanja

B je skozi isto prvotno povabilo odprl podpisan predogled z vidnim HTTPS
gostovanjem/upravljavcem, brez kartic. Ena oddaja registracije ob16:15:08.012
UTC uspe v e-poštni/FILE čarovnik; gateway potrdi en
`auth.registerInvitation4`, brez429 ali napake. En vnos kode ob16:16:14.934
potrdi e-pošto. Ena509B računska obnovitvena datoteka je shranjena in ponovno
izbrana ob16:16:50.838; ključi pripravljeni, prazni katalog Done uspe.
Običajni Back vrne isto avtenticirano povabilo z vlogo Member, pojasnilom
lokalne zasebnosti in izrecnim Join. Lokalni vnos B ni objavljen.

**Prvi sprejem je strežniško PASS, UI nadaljevanje FAIL:** en Join ob
16:17:28.216 UTC pusti isti omogočen zaslon brez obvestila do16:18:28.385.
Klik ni bil ponovljen. Bounded metadata potrdi natanko en invitations.accept
HTTP200 ob16:17:28, brez429/HTTP napak. En omejeni `query_only` read-only zajem
istega povabila/računa potrdi en accepted acceptance, istega B, shranjen
receipt HTTP200 z `pendingKeys` in nič aktivnih B članstev. Dokaza
`server/n2-r2-b-first-join-dispatch-diagnostic.json` in
`server/n2-r2-b-first-join-readonly-state.json`. UI/safe log ne pokažeta nove
napake; stari pre-FILE crypto_reconciliation_required ni vzrok tega zastoja.

Izvorna diagnoza: HTTPS parser odstrani `/index.php` in dobi naslov brez
zaključne poševnice, pending store pa hrani normaliziran naslov s poševnico.
Po uspešnem sprejemu je wizard primerjal surova niza in tiho končal pred
zapisom invitationId/prikazom čakanja. Ozek popravek v
`lib/organizer/presentation/shared/invitation_wizard.dart` uporabi obstoječi
normalizirani `_sameServer`, ohrani točen token/serverId/accountPartition
ter ponovno preveri trenutno sejo po await. Pending read/check/write je v
obstoječi skupni serializirani vrsti; obvestilo sledi uspešnemu trenutnemu
zapisu. Noben protokol ali predaja ključev se ne spremeni.

Sedem novih ciljnih widget kontrol PASS: dejanski HTTPS root link,
normalizirana shramba, pending prikaz in ponovni resume; drugačen host/pot/
token/server/partition in sprememba seje med await so zavrnjeni. Dve novi
kontroli dejanskega ScopeCryptoManager PASS potrdita, da isto že potrjeno
dejanje vrne ohranjen receipt pred send, brez transportnega klica; drugačen
payload je zavrnjen brez klica. Analiza runtime+2testov:0error/0warning,
pet obstoječih info. Neodvisni in glavni izvorni pregled PASS.
Runtime SHA256 `e8d2ba6b5c9f84e2a3c1003b8e8a027898349462a283b11de78bfd5df5583b2e`.
Native nadaljevanje mora posebej potrditi nič novega accept RPC.

Pred r3 sta B ob16:21:37.627 in A ob16:21:45.878 normalno zaprta, exit0;
seji/isti sprejem/FILE/podatki ohranjeni. Oba r3 izvora imata584 preverjenih
vhodov in samo en runtime popravek čarovnika s staro varno QA diagnostiko.
Vsi drugi runtime/native/TLS/SDK/locks vhodi so isti. Gradnja in native
nadaljevanje sta potrjena spodaj; ni novega povabila.

### r3: isto povabilo nadaljevano brez novega sprejema

Oba podpisana r3 paketa sta nameščena čez isti lastni vsebnik in Keychain.
Glavni pregled potrdi manifest, dejanski podpis/entitlements in omejitev na
en runtime popravek; native izvršilni datoteki ostaneta bajtno isti r2,
spremeni se AOT. Manifest A SHA256
`6403a4ce6af319ca77fed1211585d90f67c8604d121962c32d44e4237b254469`,
B `44eb1b1b7a413240c8168bfe43a1eb721c498896631ceee0302e3192454102d8`.
Pregledana predaja `runtime-r3-approved-handoff.json` SHA256
`dbbe807987a4fb1ecea815ed97e769ddd55da1f9ac5fc061be1555116d31dec4`.

Po normalnem zagonu A40382/B40397 en nadaljevalni Join ob16:29:42.561UTC
do16:29:47.534 pokaže »Invitation accepted. The owner still needs to
approve…« in Check access. Glavni agent je pregledal dejanski posnetek
`n2-r3-b-waiting-owner.png`. Vezani
`server/n2-r3-confirmed-join-continuation-metadata.json` potrdi štiri HTTP200,
nič novih `invitations.accept` RPC in nič429. To je nadaljevanje istega že
potrjenega dejanja; ni novega sprejema ali povabila.

### Prva odobritev: parent uspešen, child prekinjen in osnutek ne nadaljuje

En A Confirm access ob16:31:11.143UTC ob16:31:15.928581 zajame `rate_limited`
v fazah owner/sharing. `server/n3-r3-first-owner-grant-primary-metadata.json`
v tem oknu zabeleži434 HTTP,433status200 in en429 pri `crypto2.scope.headGet`.
Med njimi sta dva headPut, deset grants.put in ena aktivacija. To je visoki
strošek prve odobritve; uspešno zmanjšanje mirovalne sinhronizacije samo po
sebi ne dokazuje primerne zmogljivosti deljenja. Poznejši samodejni sync
vrne `crypto_scope_head_changed`; to ni dokaz izgube ali poškodbe podatkov.

En omejeni read-only zajem ob16:33:57 (`server/n3-r3-first-owner-grant-readonly-state.json`)
potrdi isti invitation/acceptance CONSUMED, parent epoch2 ACTIVE z B in
aktivnim članstvom B. Child ima še epoch1 ACTIVE brez B in epoch2 PENDING
z B, brez aktivacije. Povabila in parent odobritve ne ponavljamo. Trajni
`inherited:<invitationId>` journal je nastal pred parent aktivacijo in
usmerja obstoječi »Finish project access«.

Po naravnem izteku okna je en klik tega nadaljevanja ob16:36:26.216UTC
ob16:36:26.943818 zajel `CryptoAuthorityPending` /
`scope_rotation_reauthorization_required` v fazi approvals; UI pokaže
splošno napako shranjevanja. Natančen native stack ni zajet (logger file=none).
Dejanje ni ponovljeno. `server/n3-r3-child-finish-primary-metadata.json`
potrdi nič write/mutation RPC in nič429; poznejši `records.pull`409 ob16:36:29
nastane po primarni lokalni zavrnitvi in ni dokazan kot njen vzrok.
Izvorni pregled poveže napako s primerjavo ohranjenega rotation osnutka in
svežih podatkov o članih/pravicah. Dodaten omejeni primerjalnik potrdi, da
sta napredovala directory head tako A kot B; korenska ključa, naprave,
identity/recovery epoch, vloge, finančne pravice, manageKeys, access revision
in kanonični access basis pa se ujemajo. Prvi basis primerjalnik ni
kanoniziral vrstnega reda ključev in je označen kot inconclusive; ozek
popravni zajem `server/n3-r3-child-basis-canonical-correction.json` potrdi
ujemanje. Ti strežniški diagnostični podatki niso nadomestilo za odjemalčevo
preverjanje podpisane verige. Popravek mora ohraniti prvotni osnutek, ključe
in zahteve ter zavrniti dejanske spremembe identitete/naprav/pravic; ni
slepega prepisovanja osnutka, nove parent odobritve ali novih ključev za obvoz.

### r4 izvorni popravek in preizkus prekinitve

Ozek popravek samo `scope_crypto_manager.dart` pri nadaljevanju podedovanega
povabila dopušča napredovanje `directoryHeadHash`, če zgodovinski zapis
ponovno preveri in je prednik sveže, v celoti preverjene podpisane verige.
Vsi drugi podatki člana, root/identity/recovery epoch, seznam naprav,
finance/access proof ter access revision/basis ostanejo nespremenjeni.
Za obstoječega člana uporabi že potrjeni child head, za novega prejemnika
preverjeni parent head; zato ne zahteva, da je osnutek že objavljen.
Prvotni body/head, DEK, key ID in zahteve ostanejo isti. Sveže preverjanje
pravic pred vsako predajo ključev in aktivacijo ostane; ni skupnega cachea,
spremembe kvote ali spremembe successor/departure poti.

Nov ločen sintetični HTTP preizkus je v enem teku potrdil isto delo skozi
dve prekinitvi: pred headPut, nato med grants po objavi. Med vsakim
nadaljevanjem sta napredovala imenika obeh računov. Končni prejemnik prek
običajnega pull/read prebere točen prvotni naslov in opis, originalni
body/head/DEK/key ID/commitment in request bytes so ohranjeni; ni drugega
sprejema povabila ali druge parent aktivacije. PASS185s,1551 HTTP za **celoten
fixture s pripravo in tremi fazami**, ne za eno odobritev. Stanje fixturea
je ohranjeno; native strežnik ni uporabljen za sintetične mutacije.

Štirinajst novih negativnih kontrol dejanskega manager guard PASS preveri
zavrnitev spremenjene naprave/preklicanega device snapshot, identitete,
recovery/root, vlog/financ/manageKeys, rostra, revision/basis/policy in
nepovezanega ali spremenjenega zgodovinskega prefixa. To so sintetične
negativne kontrole; native odvzem dostopa je še ločen odprt korak. Končna
analiza treh datotek čista, format/diff check PASS. Pred prvim HTTP tekom
sta popravljeni dve testni tipovni/podatkovni pomanjkljivosti; HTTP in vseh
14 negativnih kontrol nato uspejo ob prvem teku, brez ponovitve stare matrike.
Poznejši testni slogovni popravek ne spreminja vedenja in ni nov testni tek.

Glavni in neodvisni pregled PASS. Runtime SHA256
`f66149d2a2100866f748c83e761637cb9025a814da9c8c0c323e67b36a8e9272`;
`n3-r4-source-freeze.json` SHA256
`2aba8646af61cc0538d78eb675d0a9406d074a824f591f0cdea0527a177363ba`;
`n3-r4-interrupted-resume-test-results.json` SHA256
`ff6c639028361f70e3d7111b0187262c33a1793e2661472b799c316e43c40094`.
Predaja za r4 združi isti r3 wizard in en novi manager popravek:
`runtime-r4-approved-handoff.json` SHA256
`fd5f814328f867e5796a50bf5458228f31a0793541acfc6e301c4fccc4e08068`.
Native nadaljevanje istega pending projekta ostaja naslednji dokaz.

Oba r4 paketa sta nato zgrajena po enkrat in nameščena čez isto lastno
namestitev; predhodni r3 paketi so ohranjeni. Vsak ima584 vhodov in natanko
en runtime delta proti r3 (manager); wizard, native izvršilni datoteki,
SDK/locks/TLS ter identiteti/shrambi ostanejo isti. Glavni pregled dejanskih
podpisov/entitlements/AOT/source plan PASS. Plan A SHA256
`3aa135e44c994f1f9027a85b32c7b5f643c2f176c58f7ee1853c2b00baacca50`,
B `032e50f7763aa5c1ad17d261eecb50ee3e852a2e61967869c68dafba76c79ed8`;
artifact A `c290b2bfac1eab3bde0f88a5d809c996ab5e6fd760487545ba8a02d260b686c4`,
B `ddb6a50c67e19d12125af54af025dac7817b6700ebdc094ed2d99def0b341b58`.

A se prvi zažene ob16:57:46.105UTC, PID45426; B ostane zaprt do konca
lastnikovega koraka. S tem ne trdimo, da je sočasni foreground strošek
odpravljen. Startup prikazuje child pending ter splošno opozorilo o zaščiti.
Glavni pregled dejanskega zaslona in handlerja potrdi, da »Continue locally«
v tem stanju samo zapre stran; ne potrdi zaščite ali spremeni podatkov.
Nadaljevanje gre po tej poti do istega »Finish project access«, brez novega
FILE ali generične priprave drugega child osnutka.

En klik nadaljevanja A ob16:58:44.479UTC do16:58:51.723 pokaže »No pending
approvals«, obe prejšnji vrstici sta odstranjeni, brez napake. Glavni agent
je pregledal dejanski `n3-r4-a-no-pending-approvals.png`. Vezani
`server/n3-r4-saved-child-finish-success-metadata.json`:568 HTTP, vsi200,
šest grants.put, ena activate, nič novega accept/headPut/closeDomain.
To je uspešno native nadaljevanje istega child dela, ne še dokaz prikaza B.
Strošek568 zahtevkov ostaja dejanska odprta omejitev.

B je prvič zagnan ob16:59:09.417UTC. Startup pokaže oba scopea encrypted in
omogočen Done, en Done ob16:59:27.687 pa prikaže splošno napako. Prvi varni
oznaki reconciliation_required ob16:59:11 in sync rate_limited ob16:59:13
sta pred Done in sami ne dokazujeta njegovega vzroka. To razreši en vezani
`server/n3-r4-b-startup-done-primary-metadata.json`: startup267 zahtevkov,
prvi429 pri directory.status; v Done oknu natanko en account.status429,
nič drugih zahtevkov ali mutacij. Natančen iztek kvote iz tega loggerja ni
dokazljiv (ne beleži RetryAfter). Ni nove FILE inicializacije ali napake
kriptografskega preverjanja, dokazane s tem Done poskusom.

Izvorni pregled pojasni, da unavailableReview pred zaščitenim completion
korakom najprej zahteva svež account.status; wizard napako prikaže splošno.
»Continue locally« zapre startup stran in vrne isto ohranjeno povabilo,
trenutno z napako predogleda. Njegov navadni »Try again« kliče _loadPreview,
ki ob točnem token/account/invitationId uporabi resumeAccepted, brez novega
accept. Pred enim omejenim B nadaljevanjem je predvideno normalno zaprtje A,
z ohranjenimi sejami in podatki. To izolira prejemnikov korak in ne pomeni rešitve
sočasnega stroška obeh aplikacij. Dejanski B prikaz je potrjen spodaj.

### N3 native branje PASS; N4 prva sprememba in odprta sinhronizacijska napaka

A je normalno zaprt ob17:01:48.457UTC. En B Try again istega shranjenega
povabila ob17:01:53.172 odpre navadni parent do17:02:04.435. Vezani
`server/n3-r4-b-saved-invitation-resume-success-metadata.json`:182HTTP,
vsi200, nič novega accept ali drugih mutacij. Ob17:02:26.184 je v dejanskem
B viden MAC-CHILD-1, natanko eno MAC-SHARED-1 in v urejevalniku Notes A-V1.
Glavni pregled `n3-r4-b-child-task-A-V1.png` potrdi prikaz. N3 odklep in
branje obstoječega projekta/opravila sta PASS, brez kartic ali novih ključev.

B spremeni opombo istega opravila v B-V2, en Save ob17:02:53.972 odpre
prva pravila sodelovanja. En Accept ob17:03:04.909 vrne seznam z enim
opravilom; ni drugega Save. Modal sinhronizacije ob17:03:32 kaže0pending/
conflicting/blocked, nobene potrjene uspešne uskladitve in invalid_response.
Prva dejanska varna sync oznaka FormatException/codeother je že ob16:59:52.570,
pred B-V2, pozneje se ponovi. Izris sharing/invalid_response na tri sekunde
sam ni nov transportni poskus.

En vezani `server/n4-r4-b-single-edit-primary-metadata.json`: pri prvi
napaki41HTTP vsi200, med njimi exports operacije in records.pull; v oknu
Save/Accept365HTTP vsi200, natanko en records.batch ob17:03:05,12receiptGET,
4checkpoint in eno moderation.acceptPolicy. Ni429 ali druge HTTP napake.
To potrjuje eno oddajo zapisa, ne še točnega oddaljenega B-V2 ali uspešnega
parserja; A ostane zaprt in Save/Sync se ne ponavljata.

Vzrok trenutno ni znan. QA logger bere error.code/reason, FormatException
pa ima message; zato vse take napake postanejo other. Release stack ne
vsebuje pričakovanega package:file:line zapisa. Pripravlja se samo B QA
diagnostika z natančnim končnim seznamom statičnih izvornih kod; ne sme
izpisovati poljubnih message/source/stack vrednosti ali spremeniti poslovne
kode. Ostali N4/N5/N6/N7 ostanejo odprti.

### Trenutni checkpoint: r5 diagnostika pripravljena; potreben odklep Maca

QA kandidat in zunanji zajem sta neodvisno ter glavno pregledana. Nov
`_qaFormatCodes` vsebuje1559 natančnih statičnih FormatException literalov
(2480 pojavitev/152 datotek), izvorne datoteke in seznam se ujemajo.
Samo `error is FormatException` in exact membership dovolita izpis te kode;
poljubna message/source/stack vrednost ne zapusti pomnilnika. Collector
uporabi isti končni seznam in polno ujemanje vrstice, ohrani4096B/1000oznak/
7200s omejitve zapisovanja ter zavrže surove vrstice. Šest helper privacy
kontrol PASS; vseh1559 kod in14 negativnih primerov collectorja PASS.
To ni nov poslovni test ali popravek vzroka FormatException.

Kandidat SHA256 `6451cee9ef469f9b4b01fbad174b58d87a60041e71676a8f92f3736d77b8fef8`,
collector `1c0bfb9980a70dee678584226372e1b65640287409332d765f24b7cb1ef7e946`.
Ob17:09:53UTC je spremenjen samo QA helper v zunanjem source-b; vseh584
vhodov preverjenih, poslovna koda/native/TLS/SDK/locks isti r4, A vir/paket
nespremenjen. Plan B-r5 SHA256
`33b55945e1c2e53e3f33c48b5ca600da7f2a71b7322e9aa661b2c27436dece04`.
Root je dejanski delta pregledal. **R5 še ni zgrajen ali nameščen.**

Mac se je ponovno zaklenil. CUA zahteva ročni odklep; uporabnik je o tem
vprašan. A ostaja normalno zaprt, B r4 PID45559 je ohranjen na sync prikazu.
Normalno zaprtje B ni bilo izvedeno; gradilno varovalo zahteva zaprti testni
aplikaciji in se ne sprošča. Po odklepu: normalno zapri B, ena pregledana
B-only r5 gradnja, pregled podpisa/paketa, namestitev čez isti vsebnik in
en zagon z novim varnim zajemom. Počakaj na **samodejni** sync za dejansko
kodo napake; ne ponavljaj Save, Sync now, prijave, FILE, Join ali odobritve.
Ohranjen B-V2 je že enkrat poslan v batch200, pri A pa še ni preverjen.

## Kaj ni del tega teka

Že potrjenih Mac prijav iste namestitve, sveže FILE obnove, stare→nove
nadgradnje ter salda/mesečnega pravila ne ponavljamo. Začetna čarovnika novih
namestitev sta priprava tega dvouporabniškega testa, ne ponovitev obnove.
Ni namestitve na Android/iOS, trgovinske oddaje, produkcijske spremembe ali
zaključka neodvisnega P0 oziroma fizičnih/izdajnih meril P8. Sistemsko
shrambo ključev, datotečne izbirnike in življenjski cikel Android/iOS bo še
treba preveriti na teh platformah.
