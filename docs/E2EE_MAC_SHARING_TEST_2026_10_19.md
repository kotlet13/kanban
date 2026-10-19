# Dve ločeni macOS namestitvi: deljenje E2EE — 19. oktober 2026

Uporabnik je odobril nadaljevanje odprtih funkcionalnih preizkusov na dveh
ločenih Mac namestitvah. Osnova je `36139e8` (poenostavitev deljenja).
Preizkus je delno izveden in trenutno čaka ročni odklep Maca. Potrjeni so
izolacija, začetna nastavitev A/B, isti A prostor/projekt in popravljena
mirovalna sinhronizacija. Opravilo, povabilo, prenos med računoma, offline
nadaljevanje, neposredni projekt in odvzem dostopa še niso potrjeni.
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
| 1 | A račun, prostor/projekt/opravilo; B zaseben lokalni kontrolni vnos in poznejša registracija skozi povabilo | A račun in isti projekt pripravljena, B lokalni vnos ohranjen; opravilo in B račun še čakata |
| 2 | Eno povabilo brez kartic, vidno čakanje, lastnikova odobritev in odklep že obstoječega projekta | Čaka |
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

## Kaj ni del tega teka

Že potrjenih Mac prijav iste namestitve, sveže FILE obnove, stare→nove
nadgradnje ter salda/mesečnega pravila ne ponavljamo. Začetna čarovnika novih
namestitev sta priprava tega dvouporabniškega testa, ne ponovitev obnove.
Ni namestitve na Android/iOS, trgovinske oddaje, produkcijske spremembe ali
zaključka neodvisnega P0 oziroma fizičnih/izdajnih meril P8. Sistemsko
shrambo ključev, datotečne izbirnike in življenjski cikel Android/iOS bo še
treba preveriti na teh platformah.
