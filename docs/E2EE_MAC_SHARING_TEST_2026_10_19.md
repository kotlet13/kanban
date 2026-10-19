# Dve ločeni macOS namestitvi: deljenje E2EE — 19. oktober 2026

Uporabnik je odobril nadaljevanje odprtih funkcionalnih preizkusov na dveh
ločenih Mac namestitvah. Osnova je `36139e8` (poenostavitev deljenja).
Potrjeni so izolacija, začetna nastavitev A/B, sprejem povabila brez kartic,
lastnikova odobritev in odklep obstoječega podprojekta. Na istem opravilu
sta potrjena dvosmerno urejanje ter offline shranitev, ponovni zagon in
samodejni prenos po obnovi povezave. B je prebral tudi neposredno deljeni
projekt drugega prostora, brez članstva v njegovem staršu in brez prikaza
sosednjega zasebnega projekta. Zadnji scenarij odvzema je delno potrjen:
strežnik je odstranil B in aktiviral nove ključe starša ter otroka, klient
pa napačno obdela uspešni zaključek. Naslednja A sprememba ostane lokalno
čakajoča, zato zavrnitev nove vsebine pri B ni dokazana. Finančno opozorilo
in visok strošek zahtevkov ostajata ločeni omejitvi; dodatne finančne
gradnje/testi so ustavljeni. Ta krog ne potrjuje pripravljenosti za produkcijo.
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
| 3 | Sprememba istega opravila v obe smeri, brez podvojitve ali objave B lokalnega vnosa | PASS (N4): B-V2 → A in A-V3 → B; zasebni B vnos ostane lokalen |
| 4 | Kratka prekinitev povezave in ponovni zagon, nato nadaljevanje istega čakajočega dela | PASS (N5): B-OFFLINE-V4 preživi restart in se samodejno prenese v A |
| 5 | B dobi samo projekt ločenega A prostora; nadrejeni prostor in sorodni projekt ostaneta nedostopna | PASS za native prikaz (N6): ciljna vsebina vidna, starš/sosed odsotna, starš ima samo A |
| 6 | Odvzem dostopa prepreči prihodnji prenos/spreminjanje; prej prenesena kopija ni obljubljena kot izbrisana | DELNO (N7): strežniški odvzem obeh ciljev potrjen; klientov zaključek ima napako, naslednja A sprememba čaka; zavrnitev novega prenosa/pisanja še ni dokazana |

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

### Zgodovinski checkpoint: r5 diagnostika pripravljena; potreben odklep Maca

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

### Po drugem odklepu: r5 zajame natančno napako sinhronizacije

Uporabnik je Mac odklenil. B r4 je normalno zaprt ob19:03:42.822UTC.
Plan je pred gradnjo vezan na commit47e7ae3, samo polje commit je spremenjeno;
prvotni plan je ohranjen. Novi plan704364bb… še vedno vsebuje istih584
vhodov. Ena B-only r5 gradnja in dejanski pregled podpisa, entitlements ter
hashov PASS. Artifact81dd805c…/AOT6956ed2b… vsebuje samo pregledano QA
diagnostiko; poslovna koda, identiteta, Keychain, TLS, native in SDK/locks
so isti r4. Namestitev ob19:05:11.188UTC ohrani isti vsebnik in stari paket.

En pasivni zagon B ob19:05:14.448885UTC, PID55133, brez vnosov ali Save/Sync/
Join/Done/FILE. Ob19:05:18.981434UTC varni logger zajame dejanski primarni
`FormatException`, code `crypto_record_context`. Vezani
`server/n4-r5-b-passive-context-primary-metadata.json`:201HTTP, vsi200,
nič429; zadnje operacije so exports/certificates/account, osem records.pull
v oknu. To je lokalna validacijska napaka, ne dokazana HTTP zavrnitev.
Posnetek `n4-r5-b-passive-crypto-record-context.*` in omejeni safe-tags so
ohranjeni. B je normalno zaprt ob19:08:34.166UTC, A ostane zaprt.

Izvorni glavni in neodvisni pregled najdeta konkreten kandidat:
`CryptoFinanceAccountChoices.materialize` poda `legacy_revision`, medtem
ko publishRaw uporabi kriptografski `record_proof_hash`. Obstoječa sveža
projekcija ima lahko legacy_revision0 in crypto_revision>=1; par ničelne
revizije in neničelnega predhodnega hasha sproži točno zajeto varovalo.
Ozek vzročni preizkus je nato potrjen. Isti ohranjeni sintetični HTTP fixture
uporabi obstoječe račune/prostor/projekt; brez nove registracije/povabila/
granta. Testni pripravljalni vnos lokalnega kataloga je najprej naletel na
manjkajoči lokalni accounts FK, še pred objavo izbire. Dopolnjen je samo
lokalni profil obstoječe seje, brez strežniške registracije. Prva izbira se
objavi enkrat; druga potrjena izbira za isti zapis s staro kodo sproži točno
`crypto_record_context` pred drugim batch (206HTTP/2s). Isti shranjeni
certifikat in operationId po enovrstičnem popravku na `crypto_revision`
uspeta (116HTTP/1s): crypto_revision2, legacy_revision0, isti predhodni hash,
aktualni membership head, preverjeno branje in ponovitev brez dodatnega batch.

En nov ciljni HTTP preizkus, nobene ponovitve starih uspešnih zbirk. Po
mehanski odstranitvi neuporabljenih delov testnega transporta je končna
analiza obeh datotek čista (0error/0warning/0info); ni novega teka po tem
čiščenju. Kriptografski codec/protokol/shema niso spremenjeni. Glavni in
neodvisni pregled PASS. Izvor bd6b5ff7… in test e185ddce… sta vezana v
`n4-choice-refresh-source-freeze.json` SHA746211ec…. R6 za isti A/B je
zgrajen in glavno pregledan: po ena zaporedna native gradnja, dejanski
strict/deep podpis/entitlements,584 izvornih hashov ter AOT ustrezajo.
Plana A4bbafbce…/B7eed6362…, artifact Afe06cc27…/Bafd29fee…,
AOT A958b7ad6…/B4d1c06ac…. Native izvršljiva datoteka in SDK/locks ostajajo
isti. Edina poslovna sprememba je zgornja vrstica; oba uporabljata že
pregledano r5 diagnostiko. A je nameščen ob19:16:14.164UTC, B ob19:16:22.849;
isti vsebnik, Keychain, identiteta in podpis, stara paketa ohranjena.

B pasivna sinhronizacija je ob19:17:20.057UTC dejansko `Synced`, zadnja
uspešna uskladitev21:16 lokalno,0pending/conflicting/blocked, brez napake.
Varni log ima samo boot, brez prejšnje FormatException. Glavni pregled
`n4-r6-b-passive-synced.png` potrdi prikaz. Ni novega Save/Sync/Join/Done/FILE;
Continue locally samo zapre ohranjeno startup stran. A nato ob19:18:00.581UTC
dejansko pokaže isto eno MAC-SHARED-1 z B-V2; glavni pregled
`n4-r6-a-received-B-V2.png` potrdi prenos že prej shranjene spremembe.

Pred A-V3 je pregled rdečega oblačka pokazal splošno opozorilo o zaščiti
(0/0/0, brez nove izjeme). Prvotna razlaga o nedokončani potrditvi še ni bila
dokazana. En običajni Done že pripravljenega čarovnika ob19:19:16.154UTC
do19:19:20.848 vrne stran s pripravljenimi ključi brez napake ali FILE/init.
`server/n4-r6-a-ready-done-pending-metadata.json`:55HTTP, vsi200, natanko en
dejanski protectionReady; nič429. Poznejši samodejni cikel še vedno prikaže
crypto_reconciliation_required, brez A-V3 vnosa. Dokaz
`n4-r6-a-gate-after-one-done.*` ob19:20:22.701.

Izvorni pregled loči dokončanje od tega opozorila: štirje notranji catchi
pri members/content/finance/predecessor razlog CryptoAuthorityPending
preslikajo v splošni crypto_reconciliation_required. Zunanji QA logger jih
ne zajame. Zato opozorilo ni dokaz neuspešne potrditve; potreben je zajem
natančnega notranjega razloga. Pripravlja se samo A r7 QA diagnostika,
brez spremembe poslovne kode. A59717 in B59642 sta normalno zaprta
ob19:22:17.443/.621UTC. B-V2 se ne shranjuje ponovno, Done/Sync se ne
ponavljata. Povratna smer N4 in N5–N7 ostajajo odprti.

### A-r7: natančen razlog je terminalni konflikt izpeljanega zapisa

R7 doda samo varni log v štiri notranje pending catche ter štiri že
filtrirane API catche, za obstoječimi identity/epoch/code varovali.
Poslovne veje ostajajo bajtno enake po odstranitvi teh logov/catch vezav.
375 točnih statičnih reason literalov (704 pojavitev/91datotek) in štiri
končne stage oznake;10 helper privacy kontrol PASS. Collector preveri
novih375×4 kombinacij ter5 negativnih primerov; starih zbirk ne ponavlja.
Manifest03418915…, helper4d639769…, sourceplan2ce5dcbc…. Glavni in
neodvisni pregled PASS. Ena A-only gradnja, dejanski podpis/entitlements,
584 izvornih hashov in točna tri QA delta PASS. Artifactc812b5c8…,
AOT8e6c18d5…; native/TLS/SDK/locks isti, B r6 nespremenjen.

En pasivni A zagon19:26:58.761068UTC/PID61749 zajame ob19:27:02.962064
`sync_finance / CryptoAuthorityPending / crypto_business_delivery_pending`.
Ni Done/Save/Sync. Ob19:27:29.051 je običajni Pulse odprt brez startup
čarovnika (`n4-r7-a-passive-finance-delivery-pending.*`); predhodni Done se
je torej ohranil. Vezani `server/n4-r7-a-finance-delivery-pending-metadata.json`:
157HTTP vsi200, nič batch/receiptGET/checkpoint/protectionReady. A je
normalno zaprt19:28:30.854, B ostane zaprt. A-V3 ni bil poskušen; opozorilo
je account-wide in samo ne dokazuje prepovedi pisanja v izbrani projekt.

Pregled prejšnjega zagona A-r6 odkrije598HTTP,597×200 in en records.batch409
ob19:17:37. Nginx requestId ni podpisani client requestId, zato povezava
samo po tej oznaki ni dovoljena. Ena dodatno omejena query-only projekcija
na testnem strežniku (znani račun A, records.batch,19:17:35–40UTC,status409)
najde natanko eno vrstico: terminalni rejected/conflict, en financeAccountChoice
zapis za znani child. RequestId SHA789ec102…; brez raw payload/ključev,
native vault branja ali mutacij. Dokaz
`server/n4-r6-prior-choice-terminal-receipt-diagnostic.json`.

`_writeRaw` po resumeUnresolved vsak state, ki ni applied, preslika v
delivery_pending; terminalni rejected se pravilno ne pošilja znova.
Izpeljana izbira pa tega konflikta ne razreši in ostaja na istem zahtevku.
Pripravlja se ozka obravnava samo za to izpeljano vrsto: točen preverjeni
terminalni conflict, svež preverjeni pull in veljavna novejša izbira;
originalni zahtevek/receipt/revision claim ostanejo. Neznani izid, druga
zavrnitev ali neveljavna trenutna izbira ne smejo postati uspeh.

### N4: isto opravilo v obe smeri in lokalna ločenost PASS

Opozorilo na ravni računa ni preprečilo zapisa v izbranem projektu. A je
ob19:37:12.992UTC enkrat shranil A-V3 na istem MAC-SHARED-1. B je ob
19:38:14.026 dejansko prikazal A-V3, zelen oblaček in eno opravilo. Glavni
pregled `n4-r7r6-b-received-A-V3.png` potrdi povratni prenos. Ob19:39:17
je B Personal/Local še vedno prikazoval LOCAL-B-PRIVATE, A AllTasks pa samo
skupno opravilo, brez zasebnega B vnosa; dokaza `n4-b-private-sentinel-local.png`
in `n4-a-all-tasks-no-private-B.png`. N4 je PASS za dvosmerno vsebino in
lokalno ločenost; A finančno opozorilo ostaja ločen odprt problem.

Oba appa sta normalno zaprta ob19:39:50UTC, z ohranjenima vsebnikoma,
sejama in podatki. N5 še ni začet: gateway ni ustavljen, offline spremembe
še ni. A-V3/B-V2, FILE, prijave in prejšnji uspešni testi se ne ponavljajo.

### R8: ozka obravnava konflikta; native potrditev še odprta

Kandidat spremeni samo `crypto_finance_account_choices.dart`. Predhodni
popravek fizične `crypto_revision` ostane. Ob materializaciji izpeljane
izbire prestreže samo `crypto_business_delivery_pending`, nato zahteva
točno eno lokalno terminalno zavrnjeno zahtevo. Preveri lastno svežo
identiteto, podpis originalnega batch, request/account/server/device/hash,
točen zapis/operation/scope in svež `receipt.get`. Dovoljen je samo409
`conflict` z isto podpisano avtoriteto. Znani strežniški receipt po obstoječi
pogodbi nima obveznega `outcome`; če je prisoten, mora biti `rejected`.
Neznan ali neskladen izid ne uspe. Sledita dejanski preverjeni pull in
popolna validacija aktualne izbire z višjo fizično revizijo. Originalni
zavrnjeni request/receipt/revision claim se ne brišejo, spreminjajo ali
ponovno pošiljajo. Generična vrsta zahtev, protokol in strežnik so isti.

En nov ciljni HTTP preizkus na ohranjenem sintetičnem stanju potrdi devet
negativnih kontrol (168HTTP/2s): unknown receipt, neskladen applied,
druga zavrnitev, permission denial, napačen request hash/authorization,
zastarelo ali prepovedano branje ter pravi conflict brez preverjene
aktualne projekcije. Originalni rejected journal ostane isti. Ni nobenega
od naštetih poslovnih/export/invitation/grant mutacijskih RPC; test ne
dokazuje odsotnosti vseh metadata zapisov, kot sta checkpoint/scopeObserve.

**Pozitivna HTTP razrešitev konflikta ni dokazana.** Poskus tekmujoče objave
je ugotovil, da drugi hladni klient nima preverjene finančne projekcije;
tudi njegova objava je dobila conflict, en navadni read pa ostane pending.
Širitev vaje je ustavljena: brez novih računov/prostorov, kloniranja,
resetiranja ali sproščanja claimov. Prvotni owner pending in other rejected
ostaneta. Začetni manjkajoči import je ustavil test pred izvajanjem; en
neuspešen prepis skripta je povzročil dodatni enak materialize poskus brez
pošiljanja. Ti poskusi niso predstavljeni kot uspešna obnova.

Končna analiza obeh datotek0error/0warning/0info, format/diff PASS; po
mehanskem test-only čiščenju ni nove široke ponovitve. Glavni in neodvisni
pregled izvora PASS. Freeze `n4-choice-conflict-source-freeze.json`
SHA13d555bc…, runtime5625acbf…, testef25f6da…. R8 QA helper44fc36d9…
doda samo novo statično kodo `crypto_account_choices_conflict_binding`;
ena nova collector kontrola PASS. R7 omejeni zajem se prenese tudi v B,
brez izpisa surove vsebine. Pripravljata se zaporedni r8 gradnji ob isti
identiteti/Keychain/TLS/SDK/locks in z ohranjenima starima paketoma. Prva
native potrditev bo pasivni A na njegovem dejanskem terminalnem konfliktu,
brez Save/Done/manual Sync; šele nato nadaljujemo N5–N7.

### R8 native: konflikt preverjen, zastareli certifikat razkrije manjkajoče nadaljevanje

Obe zaporedni gradnji sta pregledani: A artifact7394c046…/AOT35a65775…,
B artifact4206f0e3…/AOT7d68105b…. Dejanski strict/deep podpis, točni
entitlements/identitete ter vseh584 izvornih hashov na namestitev PASS;
native izvršljivi datoteki in SDK/locks ostanejo isti. Nameščeni sta čez
ista lastna vsebnika/Keychain, prejšnja paketa ohranjena.

A prvi pasivni zagon ob19:47:49.583597UTC/PID72515, B ostane zaprt.
Ob19:47:53.942610 zajame nov točen razlog
`sync_finance / CryptoAuthorityPending / crypto_account_choices_head_changed`.
Vezani `server/n4-r8-a-choice-head-changed-primary-metadata.json`:
169HTTP vsi200, en receiptGET in nato records.pull, nič novih batch.
To dokazuje napredovanje skozi preverjanje konflikta in sveži pull; ni
dokaz uspešne razrešitve. Native prikaz ob19:48:43.551 še kaže splošno
opozorilo in0/0/0. A je normalno zaprt ob19:49:01.576, brez Save/Done/Sync.

Izvorni pregled potrdi manjkajočo nadaljevalno vejo: `ensure` prepozna
zastarelo izbiro, a `materializeAvailable` ob starejšem certifikatu dobi
lokalni `head_changed` in prekine, še preden pride do obstoječe priprave
nove izpeljave. R8 sveži `_currentManifest` pravilno zavrne stari target head;
tega varovala ne sproščamo. R9 kandidat bo pri omejenem iskanju preskočil
samo ta razlog za navaden certifikat brez capture3Context in brez migration
candidate. Vsi drugi pending/error izidi ter capture/migration ostanejo
nespremenjeni. Glavni in neodvisni pregled predloga PASS. Najprej samo A
gradnja za native dokaz; B ostane r8. N5 še ni začet.

R9 končni izvor d066b1ab… doda šest vrstic samo v omenjeno catch vejo;
glavni in neodvisni pregled PASS. Nov test dejansko pokliče discovery
z nadzorovanim rezultatom materialize: baseline izbrane kontrole pade s
točnim head_changed, po popravku vseh5 novih kontrol PASS (naslednji
navadni certifikat, izčrpan seznam→false za obstoječi fallback, druga pending
napaka, capture3 certifikat in migration candidate). To ni polni verifier
ali native recovery dokaz. Analiza dveh datotek0/0/0, format/diff PASS;
brez HTTP/native klicev ali ponavljanja prejšnjih uspešnih zbirk. Test
2bc0b4cb…, freeze `n4-choice-discovery-source-freeze.json` SHA6304ca83….
Ni novih diagnostičnih kod ali sprememb QA zajema.

### R9 native: manjkajoč directory proof; checkpoint je izvorna hipoteza

A-only r9 artifactb9a25ed2…/AOT745a4183… je dejansko podpisno in izvorno
pregledan, nameščen čez isti lastni vsebnik; B ostane nameščen r8 in zaprt.
A pasivni zagon19:54:44.298003UTC/PID76768 ob19:54:49.181759 zajame
`sync_finance / CryptoAuthorityPending / directory_proof_pending`.
Vezani `server/n4-r9-a-directory-proof-pending-metadata.json`:197HTTP
vsi200, nič429/batch/export propose/delegate/certify. Tok preide skozi
offers/delegation/certificate/receipt ter drugi offers, nato inventory/
lifecycle/observations. Vseh12 directory.read je pred prvim offers, noben
po drugem offers. R9 torej napreduje skozi prejšnji zastoj, celotni sync pa
še ni PASS. UI/sync posnetka `n4-r9-a-directory-proof-pending*` ohranita
splošno opozorilo in0/0/0. A normalno zaprt19:55:36.088, brez Save/Done/Sync.

Ne delamo nove native gradnje po ugibanju. Pregled celotne sveže prepare
poti najde konkretno odvisnost: parent finance pull/reusable checkpoint
opazovanje kliče `verifyDomainCheckpoint`, ta pa išče podpisnikov točen
directory prefix s privzetim `online:false`. Prepare pozneje uporabi isti
verifier. To je izvorni kandidat, točen manjkajoči podpisnik/prefix še ni
dokazan z native zajemom. Morebitna rešitev mora izrecno omogočiti sveži
prenos po že obstoječi preverjeni poti samo pri online uporabi, ohraniti
offline privzete vrednosti ter vse pin/ancestry/authority kontrole. N5 ni
začet, gateway teče in podatki ostanejo ohranjeni.

### Omejitev finančnega stranskega preverjanja in vrnitev na N5–N7

En omejen diagnostični ensure na istem ohranjenem HTTP drugem klientu
(41RPC/1s, brez nove priprave) NI ponovil checkpoint hipoteze. Zajel je dva
`directory_proof_pending` pri choice_manager, peer/child, online=false;
končni izid je publication_required. To je diagnostični neuspeh, ne PASS.
Dokaz `n4-choice-proof-dependency-probe.log`. Izvor ostane r9 d066b1ab…;
predlagano live-proof prepletanje NI izvedeno.

Uporabnik je opozoril na vrtenje pri testih. Glavni agent prizna prevelik
finančni stranski obseg in ustavi nadaljnje finančne teste/gradnje. N4 PASS
ostane; nadaljujemo dejanske N5 offline/restart, N6 direct-child in N7 revoke
na obstoječih A-r9/B-r8. Account-wide finančno opozorilo ostane evidentirano
in samo po sebi ni razlog za ponavljanje uspešnih prenosov ali nov build.
Nov dejanski zastoj posameznega scenarija se zajame pred ponovitvijo dejanja.

### N5: sprememba brez povezave preživi ponovni zagon

Na obstoječem B-r8 je odprto isto MAC-SHARED-1 z A-V3; A-r9 je zaprt.
Ustavljen je samo točen novi gateway (isti container e9c8a9ec…,
project/service/loopback guard), od20:02:03.920091 do20:03:19.167162UTC,
75.247s. Drugi vsebniki, volumen in podatki ostanejo isti; gateway je znova
running, restorePending=false. Dokaz `server/n5-gateway-only-outage.json`.

B enkrat shrani B-OFFLINE-V4 ob20:02:28.792. Prikaz kaže server unreachable,
1pending/0conflicting/0blocked, natanko eno opravilo. Normalno zaprtje
20:02:40, ponovni zagon istega B brez povezave20:02:46.483/PID81546;
ob20:03:05.064 urejevalnik še vedno kaže B-OFFLINE-V4 na istem opravilu.
Glavni pregled `n5-b-offline-one-pending.png` in
`n5-b-offline-restart-B-OFFLINE-V4.png` potrdi lokalno shranitev in
ohranitev po restartu. Ni novega Save/manual Sync ali prijave/FILE.
Po obnovi gateway je B ob20:03:53 samodejno Synced0/0/0 brez napake,
brez ročnega Sync. A-r9 je običajno odprt ob20:03:59.312/PID83246 in ob
20:04:24.295 dejansko pokaže B-OFFLINE-V4 na istem enem MAC-SHARED-1.
Glavni pregled `n5-b-restored-auto-synced.png` in
`n5-a-received-B-OFFLINE-V4.png` potrdi prenos brez ponovnega Save ali
podvojenega opravila. **N5 offline/shranitev/restart/samodejni prenos PASS.**
A account-wide finančno opozorilo ostaja ločeno, prenosa ni preprečilo.

### N6: neposredno deljeni podprojekt brez članstva v staršu PASS

A-r9 ustvari MAC-PARENT-2 z eno oddajo20:05:42.810UTC. Zgodnje opozorilo
o še nepotrjenem ustvarjanju je običajni vmesni prikaz shranjenega osnutka,
ne ugotovljena napaka:66HTTP vsi200, poznejši UI dokončan20:07:13.364;
ni ponovne oddaje. MAC-DIRECT-ONLY je ustvarjen enkrat20:08:03.853 in eno
MAC-DIRECT-TASK z opombo N6-DIRECT-CONTENT shranjeno20:09:10. Ločeni
MAC-PRIVATE-SIBLING ima svoj zasebni kontrolni vnos; ustvarjanje20:09:43.833
se normalno konča20:10:56.869, približno73s pozneje. To je opažena
zakasnitev, ne dokaz hitrega uporabniškega toka.

Prvo branje nastavitev20:12:02 dobi429 na scopeObservations in
invitations.list. Povabilo še ni poslano. En statusni Retry20:13:24.561
po naravnem izteku omejitve uspe. A po pregledu izrecno projektnega obsega
enkrat pošlje povabilo ob20:14:13.388 obstoječemu B. B enkrat sprejme
ob20:15:26.184, brez primerjave kartic ali nove FILE, in vidi čakanje na
lastnikove ključe. Prvi Confirm20:16:19.510 dobi429 že pri branju
invitations.acceptance; v tem poskusu ni head/grant/activation mutacij.
V okoliškem ozadju so bili metadata zapisi, zato to ni trditev nič vseh
zapisov. En poznejši Retry verification20:18:02.841 in Confirm access
20:18:07.336 dokončata isto sprejeto povabilo, brez novega Send/Accept.

B-r8 po običajnem zagonu20:20:29.856 dejansko pokaže MAC-DIRECT-TASK in
N6-DIRECT-CONTENT. Izbirnik ga pokaže v Shared with me; Spaces vsebuje
samo prvotni MAC-SHARE-SPACE, brez MAC-PARENT-2. All Tasks ne prikaže
zasebnega sosednjega vnosa. A nastavitve MAC-PARENT-2 kažejo samo A owner,
brez B članstva. Glavni pregled slik `n6-b-direct-task-plaintext.png`,
`n6-b-no-parent2-or-sibling.png` in `n6-parent2-owner-only.png` potrdi
native mejo. Dodatna dokaza sta `n6-b-direct-project-picker.png` in
`n6-b-all-tasks-no-sibling.png`. To ni dodatna adversarial HTTP/API
matrika; strežniške membership poizvedbe za ta PASS nismo ponavljali.

**N6 native neposredno deljenje in prikaz meje PASS.** Omejitev429 in
foreground strošek ostajata odprta. B je po pregledu normalno zaprt.
Dokazi strežniških časovnih oken so
`server/n6-r9-a-first-parent-create-unconfirmed-metadata.json`,
`server/n6-r9-a-direct-settings-rate-limit-metadata.json` in
`server/n6-r9-direct-owner-confirm-rate-limit-metadata.json`.
AX datoteke ob skupnem screenshot klicu lahko vsebujejo samo diff/no-change;
vizualne trditve zgoraj temeljijo na dejanskih slikah, ne praznem AX izpisu.

### N7: strežniški odvzem uspe, klient pa napačno obdela zaključek

A-r9 je v prvotnem MAC-SHARE-SPACE enkrat potrdil Remove member ob
20:22:33.239UTC. Omejeni native dnevnik ob20:22:36.234847 zajame
`sharing / FormatException / crypto_membership_applied_head_missing`.
Prvi prikaz še kaže starega B člana; poznejši samodejni prikaz pokaže samo
A owner, brez novega klika ali ponovnega odvzema. Zgodovina prvotnega
sprejetega povabila ostane. Dokaza `n7-remove-first-result.png` in
`n7-remove-later-owner-only.png`; točen poznejši AX je posebej shranjen
kot `n7-remove-first-result.full.ax.txt`.

Vezano okno20:22:33–41 vsebuje196HTTP, vsi200: eno access.prepare,
dve approve, eno activate, dva headPut, štiri closeDomain, dvanajst
grants.put in44receiptGET. En read-only pregled samo prvotnega starša in
otroka ob20:25:24 potrdi oba aktivna epoch3, prisotni aktivaciji in ujemanje
trenutnih kazalcev, brez čakajočih glav. B je odsoten iz obeh shranjenih
podpisanih seznamov; nima aktivnega članstva ali grant/envelope vrstic pri
novih glavah. Točno en access intent je applied za oba cilja, pripadajoči
activate receipt pa200/applied/affected2. **Strežniški odvzem in rotacija
obeh ciljev sta zaključena; klientova obdelava uspešnega odgovora ima napako.**
To ni neuspešna child rotacija ali429. Ne ponavljamo odvzema.

Dokaza `server/n7-r9-parent-remove-primary-metadata.json` in
`server/n7-r9-parent-child-revoke-readonly-state.json` vsebujeta samo
sanitizirane metapodatke. Ni branja native vaulta, izpisa ključev ali
spreminjanja strežniškega stanja. Koda napake je v
`lib/organizer/data/e2ee/crypto_business_structure.dart:270`; popravka v
tem zaključnem koraku ne uvajamo. Preverjanje nove spremembe po odvzemu je
ločena zadnja native kontrola; starih prenesenih kopij ni mogoče priklicati
nazaj in njihov izbris ni merilo tega testa.

A na istem MAC-SHARED-1 enkrat shrani A-AFTER-REVOKE-V5 ob20:26:13.958.
Urejevalnik se normalno zapre, samodejni sync pa ostane busy z
1pending/0conflicting/0blocked, brez nove zajete kode napake. Po enem
običajnem intervalu je isti izid ohranjen na
`n7-a-post-revoke-sync-final.png` in polnem AX. A je normalno zaprt
20:27:34.527, s shranjeno lokalno spremembo in čakajočim zahtevkom.
Ni ponovnega Save ali ročnega Sync. **Dostava nove spremembe ni dokazana,
zato njen neprikaz pri B ne more biti dokaz zavrnitve po odvzemu.**
N7 ostane delno potrjen; ne začnemo novega popravka ali gradnje.

Ob enem običajnem odprtju B še prikazuje lokalno predpomnjeno MAC-CHILD-1 /
MAC-SHARED-1 z B-OFFLINE-V4; urejevalni kontrolniki so vidni, pisanja pa
NISMO poskusili. Zato ni trditve o zavrnitvi zapisa. Neodvisni
MAC-DIRECT-ONLY ostaja v izbirniku; to potrjuje ohranitev prikaza, ne novega
strežniškega branja njegove vsebine po odvzemu. Glavni vizualni pregled
`n7-b-cached-original-task.png` in `n7-b-final-cached-and-direct-picker.png`
potrdi točno ta prikaz. Polna AX dokaza in končni
`n6-n7-native-final-state.json` so v zunanjem QA imeniku.

Oba appa sta normalno zaprta: A20:27:34.527/PID87699 in
B20:29:05.334/PID88488, oba procesa zaključena. Ista vsebnika, Keychain,
seji, obnovitvene datoteke in čakajoča A sprememba ostanejo za nadaljevanje.
Novi Docker gateway je po N5 obnovljen in tem zaključku ni ustavljen.
Ni nove native gradnje ali nadaljnjih preizkusov.

## Odprti popravki po tem krogu

- Obdelava že uspešnega odvzema: odpraviti
  `crypto_membership_applied_head_missing` brez novega odstranjevanja B,
  nove rotacije ali spreminjanja že potrjenega strežniškega izida.
- Nadaljevanje že shranjenega A-AFTER-REVOKE-V5: ugotoviti vzrok njegovega
  čakajočega prenosa in nato dokončati samo manjkajoči native dokaz meje
  po odvzemu. Ne ustvariti novega opravila ali ponoviti uspešnih N4–N6.
- Ločeno account-wide finančno `directory_proof_pending` in preveliko
  število zahtevkov pri uporabniških dejanjih/429. Pri finančnem konfliktu
  so negativna varovala potrjena, pozitivna končna razrešitev pa še ne.

Ti popravki niso razlog za razglasitev celotnega teka kot PASS. Ohranjeni
aplikaciji, dnevniki in podatki omogočajo nadaljevanje točno istih primerov;
nov splošni testni krog, ponovna priprava računov ali native gradnja v tem
zaključku niso izvedeni.

## Kaj ni del tega teka

Že potrjenih Mac prijav iste namestitve, sveže FILE obnove, stare→nove
nadgradnje ter salda/mesečnega pravila ne ponavljamo. Začetna čarovnika novih
namestitev sta priprava tega dvouporabniškega testa, ne ponovitev obnove.
Ni namestitve na Android/iOS, trgovinske oddaje, produkcijske spremembe ali
zaključka neodvisnega P0 oziroma fizičnih/izdajnih meril P8. Sistemsko
shrambo ključev, datotečne izbirnike in življenjski cikel Android/iOS bo še
treba preveriti na teh platformah.

## Nadaljevanje po novem naročilu uporabnika

Uporabnik po zgornjem zaključku izrecno naroči popravilo zaključka odvzema
in čakajoče sinhronizacije ter dokončanje ISTEGA N7, zatem finančnega
opozorila in prevelikega števila zahtevkov. Ne ponavljamo odvzema, že
shranjene spremembe ali uspešnih testov; produkcija ostane nedotaknjena.
Uporabnik nato omeji reševanje vsakega težavnega testa na **največ tri
poskuse**. Po tretjem neuspehu se izid zapiše in nadaljuje naslednji
neodvisni test; odvisni ostanejo označeni kot blokirani/neizvedeni.

| Težava/scenarij | Poskus | Trenutni izid |
| --- | --- | --- |
| Zaključek že izvedenega odvzema | 1 | Izvorni popravek in5novih ciljnih kontrol PASS, baseline pade; A r10 nameščen, novega odvzema namenoma ni |
| Ista čakajoča A-AFTER-REVOKE-V5 | 1 | Server applied/task revizija5/epoch3; A r10 navadni cikel PASS Synced0/0/0, vrste so bile prazne že ob BEGIN; vzrok prejšnjega pending ni dokazan |
| Native meja po odvzemu | 3, zaključeno | Readonly in ohranjen1pending/0conflicting/1blocked PASS; brez task transporta. Besedilo opozorila napačno enači reconciliation z revoked/explicitresume: OPEN/SKIP po3.poskusu. Sveže server write-denial ni bilo |
| Finančno directory_proof_pending | 0 | A r10 polna finance faza brez napake; starega opozorila ne reproducira, vzročnega popravka ne zatrjujemo. Dejanska nova B target napaka se obravnava v istem N7 |
| Preveliko število zahtevkov | 1 native, 2 analiza |412HTTP/cikel ostaja OPEN, bistven prihranek ni dokazan; varna večja sprememba zahteva ločen combined-read pristop. Analiza2BLOCKED, brez novega cikla/umetnega3.poskusa |

Prvi omejeni pregled originalnega okna20:26:13–20:27:35 najde673HTTP,
672×200 in en headGet429 ob20:26:40. En batch je200 ob20:26:31, nato
sledijo preverjanja projekcije; native safe log v tem oknu nima oznak
napake in ni dosegel omejitve zapisovanja. **Naknadni en read-only pregled
točno tega računa/operation/3s okna potrdi semantični applied**, dva
podpisana zapisa istega childa in natanko eno opravilo: pričakovana revizija4,
ACK5, trenutna strežniška revizija5/epoch3, brez deleted. Dokaz
`server/n7-r9-a-future-note-receipt-readonly.json`, request digest7fa4ec6e….
Prejšnji zaključek pravilno ni trdil dostave brez tega dokaza; zdaj je
strežniška dostava potrjena, lokalni pending pa ostaja ločena napaka.

UI števec združuje navadni outbox, commands in finance_outbox, ne vključuje
crypto_outbox. Sam batch ACK tudi še ni lokalna potrditev: `_writeRaw`
pred vrnitvijo preveri pull/projekcije obeh zapisov, šele nato se zaključi
navadna outbox transakcija. Nova QA diagnostika zato beleži samo končne
oznake faz in ločena agregatna števila, brez vsebine/identifikatorjev;
oznaka lokalnega ACK nastane šele po uspešnem zaključku transakcije.

### Poskus 1: izvorni popravek zaključka odvzema

`CryptoAccessCoordinator.finish` po preverjenem podpisu, točnem intentu in
stanju applied zdaj pokliče `invalidateAuthorityOperation`. To prekine
zunanjo operacijo, ki je med pregledom hranila staro epoch2; isto velja pri
obnovi že shranjenega potrjenega odgovora. Preverjanje trenutne glave,
izvornega prednika, intentHash, članstva in rosterja se ne sprošča.
Cancellation ne zatrjuje nove aktivne glave, napačni odgovori ne uspejo.
Runtime je samo4dodane vrstice v `crypto_access_coordinator.dart`,
SHA455aac21…; ni protokolarne/strežniške/shemske spremembe.

Nov `crypto_access_activation_boundary_test.dart` (SHA7a3c8be4…) uporabi
dejanski podpis priprave/aktivacije, preverjanje lastnega zgodovinskega
directory prefixa in realni enclosing operation lease. Pet kontrol PASS:
potrjeni shranjeni rezultat prekine staro operacijo in je ne oživi;
cancellation ter napačni signature/intent/state ostanejo strogi. Zero
transport, brez novega odstranjevanja člana. En pozitivni primer proti
staremu izvoru pade zaradi ohranjene iste Zone, nato je točen popravek
obnovljen. Začetne test-fixture težave so odpravljene, niso native poskusi.
Dve datoteki analyze0issues, format/diff PASS. Obstoječi nižji currentHead
HTTP memo test ni ponovljen; novo preverjanje dokazuje klic manjkajoče
koordinatorjeve meje, ne novega celotnega HTTP odvzema.

Glavni/neodvisni pregled popravka in QA-only diagnostike PASS. A-only r10
plan SHA9489ee4c… vsebuje584 preverjenih vhodov in natanko3delta proti r9:
koordinator, finite logger ter opazovalne sync oznake/agregati. Nova testna
datoteka je vezana posebej in ni pakirana. Podatki/Keychain/identiteta/TLS/
SDK/locks ostanejo isti, B ostane nameščen r8. Pripravlja se ena A gradnja;
native rezultat še ni potrjen.

### A r10 nadaljevanje PASS; B meja poskus1 FAIL

A r10 en normalen zagon20:43:42.813UTC/PID92057, polni cikel
20:43:44.306–20:43:52.710 zaključen v8.4s. Regular/commands/finance/crypto
pending in blocked so0 že ob BEGIN in tudi END; conflicts/reconciliation0.
UI Synced0/0/0, brez napake, tudi finance faza uspešna.418HTTP vsi200,
brez batch, dva receiptGET in en checkpoint. Zato trenutna čakalna vrsta
PASS, ni pa dokaza, da je prav r10 odpravil prejšnji pending. Normalno
zaprt20:44:13.639; brez novega Save/Remove/Sync/prijave/FILE. Dokazi
`server/n7-r10-attempt1-passive-clear-transport.json`,
`server/n7-r10-attempt1-passive-clear-phases.json` in
`n7-r10-attempt1-a-synced-zero.png`. AOT381c9d74…, podpis/izolacija PASS.

B ostane r8. En normalen zagon20:44:50.965UTC/PID92256 ustavi sinhronizacijo
z `crypto_account_choices_target`; primarne napake20:44:52.717,
20:45:10.513 in20:45:43.663 so avtomatske ponovitve znotraj istega prvega
poskusa, ne trije različni popravki. Normalno zaprt20:45:52.731.162HTTP
vsi200, brez batch/receipt/propose/delegate/certify ali write probe.
Vsak konec je exports.offers→content records.pull→lokalna target napaka.
Dokazi `server/n7-r8-b-boundary-attempt1-finance-target-metadata.json`,
`server/n7-r8-b-boundary-attempt1-safe-tags.json` in
`n7-attempt1-b-sync-primary.*`. B-DENIED sprememba ni bila izvedena.

Izvor pokaže normalen direct-child-only projekt brez razkritega parentId,
ki ga optional finance refresh napačno pošlje v pripravo izbire računa iz
nedostopnega starša. To je naslednji ozek popravek, ne dovoljenje za
razkritje starša ali sproščanje podpisov/glav/članstva. Naslednji B tek
šteje kot poskus2/3; ob prvi primarni napaki se aplikacija normalno zapre.

### B poskus2: popravek pripravljen in pregledan

`CryptoFinanceAccountChoices.prepare` loči normalen project+null parent od
neveljavnega cilja: samo prvi vrne typed
`crypto_account_choices_parent_unavailable`, neproject/napačen tip ali
nekanonični nenull parent ostanejo napake. `_syncFinance` ujame samo ta
razlog neposredno ob neobveznem selector fetchu, preveri epoch in nadaljuje
linked payments. Pred tem se še vedno poskusita read/materialize; finance
policy/pull in vsa podpisna/member/head/parent-binding varovala ostanejo.
Ni shranjevanja prazne izbire ali izmišljene finance completeness.

Devet novih ciljnih kontrol PASS:5actual prepare/read-order ter4repository
sync/error/coverage/known-parent. Read-order uporablja kontroliran verified
result in ne dokazuje nove kriptoverifikacije; repository fixture ima
izrecni synthetic legacy router, zato ni dokaz native E2EE poti. Dve
fixture napaki (typed capabilities map in router setup) odpravljeni; brez
ponovitve starih uspešnih zbirk. Analyze4files0error/0warning/1stariinfo,
format/diff PASS. Glavni in neodvisni pregled PASS. Runtime SHA
choices d1970a90… ter finance_sync f37a4da0…; testa ab169b54…/7b9b99cb….
Native B poskus2 še čaka ohranjeno B-only r11 namestitev.

B-r11 en build dokončan:584 exactsnapshot vhodi/isti pathset,5delta proti
pripravljenemu r9 (tri runtime datoteke in dve QA opazovalni), dejansko
nameščeni predhodnik ostane r8 do zamenjave. Plan43f34a0b… vključuje
nespremenljive kopije runtime vhodov; evidence1adf90c9…, AOT93ed0898…,
nativeexe5f623f4a… isti. Glavni dejanski codesign strict/deep, entitlements,
lastni B ID/group/service, odsotnost URLschemes/Googleplist in oba executable
hasha PASS. SDK/locks isti. Overlay analiza0error/0warning/2braceinfo
(stari runtime in QA helper); brez ponovne gradnje zaradi sloga.

### Strošek zahtevkov: poskus1, izvorni no-work popravek

Obstoječi A-r10 cikel418HTTP ima finance fazo5.758s od skupnih8.404s.
Zaradi enosekundne ločljivosti strežniških časov je natančna atribucija
omejena:228 zahtevkov v celotnih sekundah47–51 zagotovo pripada finance;
323 je zgornja meja z mejnima sekundama, ne točno izmerjena vrednost.
Dokaz `server/request-cost-a-r10-phase-attribution.json`. Ne trdimo, da so
vsi ti zahtevki odvečni.

`reconcileTaskDerivations` je pred ugotovitvijo praznega nabora odpiral
novo currentHead preverjanje. Nov skupni SQL predikat ohrani točno stare
partition/scope/domain/type/deleted/taskId filtre iteratorja; SELECT1 LIMIT1
vrne zgodaj samo pri praznem naboru. Prejšnji queue pull, read admission,
checkpoint/observation in ne-prazni fresh authority/role/intent/CAS ostanejo.
Pozneje prispel zapis ostane trajen in ga naslednji pull spet obravnava;
odsotnost ni dokaz popolnosti in ničesar ne označi kot poravnano.

Štirje novi ciljni runtime/SQL/Zone testi prvi tek PASS;3file analiza0issues,
format/diff PASS, glavni/neodvisni pregled PASS. Testna queue/read seam sta
kontrolirana, attest:false, zato to ni nova celotna kriptoverifikacija.
Router SHA024e037a…, task_resolution207684c0…, test4b797dd8….
Native prihranek še ni izmerjen; kvota/TTL/strežnik se ne spreminjajo.

### B poskus2: sync in bralna meja PASS, lokalno urejanje še nepravilno

B-r11 navadni zagon20:58:54.880502UTC/PID95436; fullsync
20:58:56.067663–20:58:57.651255 zaključen brez napak, pending/conflicts0.
Reconciliation2 ohranja stari parent+child, ki manjkata v katalogu; sam
manjkajoči katalog ni kriptografski dokaz odvzema. Isto opravilo še kaže
B-OFFLINE-V4, nove strežniške V5 ni. Urejevalnik je kljub temu omogočen,
zato je bil prvič izveden odobren EN Save B-DENIED-AFTER-REVOKE ob
20:59:38.620. Cikel38.740–40.239 se zaključi, originalni lokalni zahtevek
pa ostane regular pending1/reconciliation2; noben batch_return/ACK.

Točno okno tega poskusa ima71HTTP vsi200, nič records.batch/receiptGET.
Celotno okno ima228HTTP:226×200, en inbox.sync409 ter en headGet403 PRED
Save. Zato ni transportiranega task zapisa, vendar tudi ni izrecno
preizkušene strežniške zavrnitve pisanja. Ne pripisuj starega403 novemu
Save. Dokaz `server/n7-b-r11-attempt2-native-boundary-metadata.json`.
Neodvisni direct projekt dejansko pokaže N6-DIRECT-CONTENT. B normalno
zaprt21:00:26.332, oba appa zaprta. Nobene ponovitve Save/Remove/Sync.

Poskus3/3 naslovi samo ostalo UX/queue napako: manjkajoča authority že
prepreči transport, vendar cached canEdit in prikaz čakalne vrste tega
ne upoštevata. Izvirni lokalni zapis ostane ohranjen; ne bomo izmišljali
revoked dokaza, brisali vrste ali na silo ponavljali pisanja. Bralna
meja/direct read sta PASS in se ne ponavljata.

### B poskus3/3: readonly in natančen prikaz ohranjene vrste

Trije runtime vhodi: repository projection iz markerja izpelje blocked
scope in blocked štetje (regular/finance ter commands s scopeId); skupni
record `_requireScopeReconciled` in finance `_financeWritable` zavrneta nov
vnos z obstoječim changes_blocked. Ne zapisujemo revoked ali sticky blocked
v bazo, ne spreminjamo request/state/sequence/payload. Lokalno branje ostane,
pending total še vedno šteje ohranjeno delo; blocked je njegova podmnožica.
Zato pravilen izid za en osnutek pomeni1pending/0conflicting/1blocked,
ne izbrisa vrste. Ob ponovnem preverjenem odkritju obstoječi tok odstrani
marker, urejanje in dostava izvirnega zahtevka se obnovita.

Dva nova repository testa prvi tek PASS: isti request/record/state bajti,
odsotnost dodatnih task/finance zapisov, ohranjeno branje in drugi scope,
restoration dostavi originalni request; finance/command štetji reverzibilni.
Synthetic legacy fixture ne dokazuje novega E2EE protokola.4file analiza
0issues po odstranitvi neuporabljenega test importa (brez ponovnega teka
uspešnih testov), format/diff PASS, glavni/neodvisni pregled PASS.
Repository b3138281…, record_actions560ca06f…, finance_actions40758fa4…,
test1148a648…. Finančni obrazec lahko še pokaže cached pravico, toda skupni
mutation guard zavrne vnos; ni širše prenove finančnega UI v tej omejeni fazi.
Native tretji poskus še čaka B-only r13, novega Save ne bo.

### Strošek poskus1 native: tehnično PASS, bistvena izboljšava NI dokazana

A-only r12 plan93021b4e…/584inputs/5delta proti r10, evidence d71321f3…,
AOTf65127ed…, isti nativeexe/podpis/lastni vsebnik/Keychain/SDK/locks.
Glavni dejanski pregled paketa PASS. En navadni zagon21:05:08.728918UTC,
fullcycle21:05:09.839507–21:05:17.945721 (8.106s), vse vrste0, brez napake,
UI Synced0/0/0. Normalno zaprt21:05:55.562 pred naslednjim ciklom; brez
business branja/pisanja/Sync. Slika `cost-attempt1-a-r12-synced-zero.png`.

412HTTP vsi200, nič429. Proti A-r10/418 je razlika samo6: checkpoint−1,
receiptGET−2, account.status−1, directory.status−1, headGet−1. Inventory46,
pull23, lifecycle51+56 in observations69 so isti. Razlike checkpoint poti
preprečijo trditev vzročnega ali bistvenega prihranka. Guard za prazno delo
ostaja ciljno preverjen, **problem velikega stroška še ni rešen**. Dokaz
`server/request-cost-attempt1-a-r12-passive-metadata.json`.
Poskus2 je omejena izvorna analiza podvojenih finance/payment pullov;
novega native cikla brez konkretnega popravka ne izvajamo.

### Strošek poskus2: omejena analiza BLOCKED, brez novega teka

Znotraj uspešnega choices dispatcha je en pull, audit.currentPayload ga ne
ponovi. Pomembno podvajanje main finance in petih payment snapshotov nastane
med ločenimi dispatchi. Varna odstranitev zahteva tipizirano sestavljeno
branje z vezavo na head/cursor/checkpoint/pins, največ5s ter prekinitvijo
ob zapisu. Choices.ensure in coverage/observation poti lahko pišejo, zato
boolean alreadyPulled ali daljši skupni cache nista ustrezen popravek.
Glavni in neodvisni pregled se strinjata: ni varnega ozkega kandidata za
ta omejeni test. Brez novih izvornih sprememb, testov ali native cikla;
412request/cycle ostane OPEN. Tretjega poskusa ne izmišljamo brez novega
konkretnega pristopa; uporabnikova meja3 je maksimum, ne obvezna poraba.

### Končni B poskus3: readonly/blocked PASS, preostalo opozorilo SKIP

B-only r13 plan040161a9…/584exactinputs/5delta proti r11, evidence924e9aad…,
AOTddfe696a…, isti nativeexe5f623f4a…/lastni vsebnik/Keychain/podpis/SDK/locks.
Glavni dejanski pregled podpisa, entitlements, ID in executablehashov PASS.
En zagon21:09:42.528071UTC, fullcycle21:09:43.637949–21:09:45.158484 brez
napake. Staro opravilo je zdaj tekst/samo za branje, brez vstopa v editor
ali Addtask. Ista prej shranjena sprememba ostane1pending/0conflicting/
1blocked v UI; fizični SQLstate ostane pending, zato QAagregat blocked0
ni protislovje. Izvirni zahtevek ni odstranjen ali spremenjen.

222HTTP vsi200, nič429/batch/receiptGET; normalno zaprt21:10:42.931UTC.
Dokaz `server/n7-b-r13-attempt3-final-readonly-metadata.json` in sliki
`n7-r13-final-readonly-task.png`/`n7-r13-final-blocked-queue.png`, obe
glavni agent dejansko pregleda. Nobenega Save/Sync/Remove/directread ali
novega DB pregleda. Sveža eksplicitna strežniška zavrnitev write ni
preizkušena; potrjena je odsotnost task transporta ter lokalna meja.

**Preostala UX napaka, OPEN/SKIP po3.poskusu:** obstoječe skupno opozorilo
pravi, da je access revoked in da obnova zahteva explicit resume. Novi
reconciliation marker tega ne dokazuje, ob ponovni veljavni discovery pa
se izvirni pending zahtevek sam nadaljuje. UIcount/readonly sta pravilna,
razlaga pa potrebuje ločeno obravnavo razlogov. Brez četrtega popravka,
gradnje ali ponovitve testa. N7 se zato ne označi kot neomejen fullPASS.

Končno stanje: A-r12/B-r13 normalno zaprta, vsebnik/seji/testni podatki
ohranjeni.20novih ciljnih kontrolPASS (5activation+9childfinance+4emptywork+
2reconciliation), le relevantne scoped analize; starih uspešnih zbirk ni
bilo ponovno izvedenih. Stari finančni directory_proof_pending ni ponovno
opažen, vzročni fix zanj ni dokazan.412request/cycle ostaja OPEN. Produkcija,
stareQA/mobile, trgovini, sheme, SDK/locks in nepovezana dokumenta ostanejo
nedotaknjeni. P0/mobile/P8 ter produkcijska pripravljenost niso zaključeni.
