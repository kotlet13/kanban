# Prenova sinhronizacije — lokalna izvedba 24. oktobra

**V TEKU.** Izrecno naročilo uporabnika dovoljuje kodo, ciljne lokalne teste,
nov ločen strežnik in dve novi Mac aplikaciji. Telefoni, produkcija in stara
testna okolja se ne spreminjajo. Podlaga je potrjeni načrt v
`E2EE_MOBILE_SESSION_2026_10_24.md`, ne stare posamične optimizacije.

## Trenutno stanje

- Novi lokalni strežnik in ločeni Mac aplikaciji Sync A/B so pripravljeni.
  Oba nova uporabnika sta registrirana, e-pošta potrjena, obnovitvene datoteke
  shranjene in preverjene. A ima novi Sync Space A z novo politiko pravic.
- A je poslal eno povabilo, še preden je B ustvaril račun. B ga še ni sprejel:
  Mac se je zaklenil pred tem korakom. Čaka uporabnikov ročni odklep;
  sprejem, avtomatska predaja ključev in dejanski prenos vsebine še niso PASS.
- V nameščeni r3 je potrjen 30-sekundni razmik pregledov. Ločen starejši
  mirujoči interval je pokazal samo metadata zahteve brez vsebinskih prenosov.
  To še ni meritev hitrosti odpiranja ali shranjevanja dejanskih zapisov.
- Po r3 so v izvoru še popravki besedila pravic in osvežitve povabila po
  vrnitvi iz čarovnika. Izrecna obnova ob sporu z brisanjem je v integraciji;
  njene tri repository kontrole so STOP3 zaradi priprave testov/sočasno
  nedokončanega izvora, ne uspešno preverjene. Četrtega teka ni.
- Obstoječi napolnjeni prostori se ne preklapljajo samodejno na novo politiko:
  varna obravnava stare podpisane zahteve z druge offline naprave ostaja
  STOP3/NEPRIKLOPLJENA. Pretvorba inline projekta v podprostor prav tako
  ostaja izrecno čakajoča. To sta omejitvi izdaje, ne razlog za brisanje podatkov.
- Starih okolij še ne odstranjujemo. Telefoni in produkcija so nedotaknjeni.

Spodnji datirani sklopi ohranjajo potek preverjanja in vmesne ugotovitve;
njihove takratne odprte točke niso nadomestilo za zgornje trenutno stanje.

## Meje in faze

1. Metadata pregled sprememb računa, en 30-sekundni foreground koordinator,
   selektivni prenos in lokalne projekcije; opravilo odpre lokalni osnutek
   brez čakanja na finance. Stanje oblačka ne nalaga drugih modulov.
2. Ohranjeno obstoječe avtorstvo in verzionirana pravila owner/author/task
   assignee, nakupovalni checkbox ter varen kaskadni izbris. Uveljavitev ni
   samo UI. Zgodovinski podpisi in čakajoče podpisane namere ostanejo.
3. Tri različice pri konfliktu, samodejna združitev neodvisnih polj in
   vidna odločitev pri nasprotju. Finance in atomarni pari ostanejo ločeni.
4. Neodvisen pregled, ciljni lokalni preizkusi, zamrznitev izvora, novi
   Mac A/B in Docker. Nato resnični foreground sprejem povabila, deljeni
   ter zasebni zapisi, prenosi, prekinitev in nadaljevanje.
5. Poročilo in šele nato seznam nepotrebnih starih paketov/cache/okolij za
   čiščenje. Nobenih starih podatkov, ključev ali potrebnih dokazov ne brišemo.

Podagenti so GPT‑6.1 Sol/high; root pregleduje integracijo in vodi dokazila.
Največ trije poskusi na težavo; uspešne kontrole se ne ponavljajo brez novega
relevantnega popravka. Sintetični test ni dokaz dejanskega native E2EE toka.

## Sveže okolje

- Projekt Docker: `jivie-sync-redesign-20261024`.
- Samo loopback: HTTP 18820, HTTPS 18821, lokalna pošta 18822.
- Javni dokazi: `build/qa/sync-redesign-20261024/`.
- Testne poverilnice in zasebni TLS ključi: ločena zasebna mapa
  `~/Library/Application Support/JivieLocalTest/20261024-sync-redesign`.
- Sveži strežnik je zagnan. Strict TLS health in javni capabilities sta HTTP 200; accountChanges in recordPolicyVersions sta oglaševana. Ni kopiranja starih baz. Štirje lastni vsebniki tečejo, začetna primerjava drugih vsebnikov ne pokaže spremembe stanja ali slike.
- Pregledan izvor je zamrznjen v manifestu. Naknadna ozka dopolnitev zasebnosti evidence bo pred odjemalci posebej prestavljena samo v ta novi strežnik.
- Novi identiteti aplikacij, shrambi, Keychain skupini in računa A/B so
  pripravljeni. Obstoječe aplikacije niso bile predloga podatkov.

## Doslej izvedene ciljne kontrole

| Sklop | Dokaz / meja |
|---|---|
| Strežniški metadata pregled | Prvih 19 novih kontrol PASS v pomnilniški SQLite z izoliranim PHP; življenjski cikli in strošek pregleda še v pregledu. |
| Koordinator | 9 novih seam kontrol PASS v poskusu 2; poskus 1 je fixture uporabil privzeti crypto router. Fixture zdaj failclosed. Brez sprememb: en probe, nič vsebinskih dogodkov; scoped pull, pending write, receipt, partialfailure cursor, singleflight in identity/revoke. |
| Odpiranje opravila | 6 novih widget kontrol PASS v poskusu 3. Prvi dve napaki fixture: podpis override in začetni AsyncLoading. Neprekinjen finančni Completer ne blokira prvega prikaza; dirty osnutek ohrani bazo; cost-change ostane paired. |
| Obstoječa prizadeta Save/cost pot | 4 kontrole PASS v prvem teku; ena dodatna fixture teardown timer težava popravljena, samo ta kontrola PASS v poskusu 2. Ni ponovitev poslovnih mobilnih PASS. |
| Domenska obvestila | 6 novih kontrol PASS2 (prvi fixture ni podal obveznega notes); 10 datotek analiza brez težav. Finance sprožijo organizer/payments, task samo organizer; status in scope sequence nič; revoke vse potrebne domene. |
| Vidna Mac okna | Pure lifecycle PASS1, dva widget testa PASS2 po popravku fixture teardown platformoverride. Vidno nefokusirano okno lahko potrdi dostop; skrito/minimizirano ne. Telefonsko ozadje ostane nespremenjeno. |

Koordinatorjev pregled je odkril in popravil dva dodatna problema: možen
microtask loop med zunanjim ročnim syncem in podvojeno obdelavo completion,
ki bi lahko resetirala backoff. Dve novi provider kontroli PASS1. Celoten
agentov sklop prve faze ima 21 različnih kontrol; ne predstavlja 21 realnih
E2EE ali native sej. Strežniški sklop ima 57 različnih kontrol, od tega je
prvih 19 veljalo pred zamenjavo dokumentnega inventarja z durable counterjem;
končne števce/expiry konfiguracijo preverjajo novi ciljni sklopi.

## Načrt dejanskega novega scenarija A/B

1. A nova lokalna zaščitena shramba, račun A in prvi prostor/projekt A.
2. A pošlje povabilo na novi testni e-naslov B **pred vzpostavitvijo E2EE
   identitete B**. Sicer bi test izbral že preverjeno preauthorized pot za
   obstoječ račun in ne bi preveril zahtevane samodejne predaje ključev.
3. B se registrira/prijavi, zaščiti shrambo in sprejme isto povabilo. A ima
   na istem Macu vidno odprto okno; B dobi dostop brez dodatnega klika A.
   Dokazi ločijo accept, owner avtomatski grant in dejansko decrypt/read B.
4. A ustvari deljeno opravilo, dogodek, nakupovalni seznam/postavko in
   finančni račun z začetnim stanjem ter strošek. B mora videti prenose.
5. Ločeno opravilo je dodeljeno B; B ga uredi. B ustvari svoj zapis,
   ki ga A kot lastnik lahko uredi. Neavtor brez dodelitve ne ureja tujega
   zapisa; nakupovalni checkbox lahko označi. Preverimo realen denial,
   ne samo skritega gumba.
6. A ustvari nedeljeni prostor B in projekt B z zasebnimi vnosi. B kot
   prejemnik deljenega A ne dobi ne vsebine ne dostopa do zasebnega B.
7. Nova ciljna konflikta: neodvisni spremembi se združita; isti polji
   ostaneta za odločitev. Posebej finance: sprejeta vsota in ohranjen predlog,
   brez podvajanja stroška. Prekinitev/nadaljevanje samo na teh novih vnosih.
8. Izmerimo odpiranje/shranjevanje in metadata-only nespremenjen pregled.
   Brez ponavljanja starih mobilnih prenosov, starih revoke/restore scenarijev
   ali povabil. Vsak novi scenarij ima največ tri poskuse in lasten izid.

Začasni dnevniki: `/tmp/kanban-editor-tests-attempt{1,2,3}.log`,
`/tmp/kanban-editor-existing-attempt1.log`,
`/tmp/kanban-editor-existing-attempt2-filtered.log`,
`/tmp/kanban-account-changes-attempt{1,2}.log`.
Pred končnim poročilom se ustrezni dnevniki prenesejo med trajne QA dokaze.

## Odprto za dejanski A/B pregled

Sprejem istega povabila in avtomatska predaja ključev, deljeni in zasebni
vnosi, uveljavljanje pravic, konflikti ter prekinitev/nadaljevanje še čakajo.
Lokalne kontrolne rezultate kode ločujemo od tega dejanskega scenarija.
Prenova še ni pripravljena za produkcijsko izdajo.

## Dopolnitve med integracijskim pregledom

- Strežniški sklop: 93 različnih kontrol na razvijajočem se izvoru; podrobne
  omejitve v `server/tests/SYNC_REDESIGN_2026_10_24.md`. Ni dokaz native toka.
- Generic merge: obstoječi dokazani izvorni podpisi/receipts ostanejo, nova
  naslednica šele po dokončno zavrnjenem izidu. Ločeni field merge in dejanski
  SQLite seam testi; realni A/B konflikt še čaka.
- Root UI: 3 nove projekcijske kontrole PASS1 za avtorja/dodeljenega/viewerja,
  ločen finančni namespace in preaktivacijsko združljivost. Vključeni meniji
  Vsi prostori, ideje, vrt in finance z originalnimi ID projekcij.
- Root dokumentni UI: 2 novi attachment widget kontroli PASS1; avtor lahko
  izbriše svojo prilogo brez pravice novega nalaganja, writer nima gumba za
  tujo prilogo. Table author acquire + izguba pravice PASS2; prvi poskus je
  imel napačen fixture tooltip `Edit` namesto `Edit table`.
- Merge notice: 2 novi kontroli PASS1 (6s lokalni ack in preklop računa),
  hidden/resume PASS3. Prva dva fixture izida sta napačno pričakovala frame
  med skrito aplikacijo; uspešni kontroli nista bili ponovljeni.
- Pregled je odkril še zastalo opozorilo po uspešnem metadata-only okrevanju
  in samostojno 10s branje odprte tabele; odpravljanje je del te prenove.
- Polna podpisana aktivacija nove politike na odjemalcu in sprejem novih
  zapisov sta še v integraciji. Do takrat novih Mac aplikacij ne gradimo.
- Pretvorba starega inline projekta v ločen podprostor po aktivaciji nove
  politike trenutno izrecno počaka (`crypto_record_policy_relocation_pending`)
  brez spremembe izvornih podatkov. Potrebuje novo atomarno podpisano objavo
  politike cilja; tega ne označujemo kot uspešno prenovljeno pot.

### Dodatni pregled pred prvo gradnjo

Odprt prikaz tabele ne bere več vsakih 10 sekund. Posluša objavljene spremembe
konkretnih dokumentov; običajna opravila in status oblačka tega ne sprožijo.
Timer ostaja samo za lokalno preverjanje in obnovo že aktivnega urejevalnega
zaklepa. Nova widget kontrola PASS1: 31s brez dodatnega branja, ena sprememba
sproži eno branje, aktivni urejevalni osnutek se ne prepiše. Tudi priloge imajo
scoped signal in odloženo osvežitev med nalaganjem. Root analiza šestih
prizadetih dokumentnih/finančnih UI datotek nima težav.

Odprta izdajska meja: druga, nepovezana naprava lahko hrani staro že podpisano
zahtevo 6/3. Nova aktivirana politika bi jo zavrnila; lokalni pregled vrste
na prvi napravi zato ni zadosten dokaz varne splošne aktivacije. Izbrana smer
je dokazano zavrnjena originalna zahteva + nova izrecno vezana naslednica,
ob ohranitvi originalnih podpisov in poslovnega predloga. Do končane podpore
se obstoječi prostori ne preklapljajo samodejno. Novo QA A/B okolje preizkuša
sveže prostore; to ni dokaz uspešne migracije vseh starih offline zahtev.

### Prvi dejanski native zagon novega okolja

Obe podpisani Mac aplikaciji sta nameščeni pod novima identitetama Sync A/B.
A gradnja PASS2 (prvi fixture ni vključil apple/JivieLegacySecrets.swift), B
gradnja PASS1. Obe sta prek GUI shranili, ponovno izbrali obnovitveno datoteko
in šifrirali svojo prazno bazo. A je ustvaril prvi račun, potrdil sintetični
e-naslov v lokalnem Mailpitu in pripravil računske ključe. B računa še nima.

Prvi integracijski FAIL: account.changes ni bil v metadata bypass seznamu,
zato je končal v content routerju še pred HTTP. Na Account je ostalo opozorilo
cryptoConnectionPending kljub protectionReady200. Odpravljanje je ciljno.

Prvo ustvarjanje Sync Space A se je zaključilo z opozorilom o nepotrjenem
ustvarjanju. Strežnik ima natanko en prostor in njegovo politiko1, celoten
postopek pa še NI PASS. Isti request/draft ostane za nadaljevanje. Nobenega
povabila, ponovljene registracije ali novega nadomestnega prostora ni bilo.

Centralna naslednica stare podpisane zahteve ostaja NEPRIKLOPLJENA / STOP3:
mešani content/finance primer ni preverjen. Obstoječi prostori se zato ne
preklapljajo samodejno. To je izdajska omejitev, ne uspešen migracijski test.

**Opravek prvotne interpretacije ustvarjanja:** poznejši prvi sveži pogled na A
pokaže Space settings → Sync Space A / Owner / član A. Nobenega ponovnega
klika ali poskusa ustvarjanja ni bilo. Izvirni klic je uspel; začasno besedilo
»Creation has not been confirmed« med izvajanjem NI dokaz napake. Prvotna
oznaka FAIL je zato umaknjena. Smiselna UX izboljšava: med delom prikazati
napredek namesto navodila za ponovni poskus. Metadata router napaka ostaja
ločeno potrjena z izvorom in novim ciljnim testom.

### Native r2 — metadata opravljeno, ugotovljena pogodba kataloga

Oba enaka QA paketa sta posodobljena z ozkimi popravki, brez odstranitve
namestitve ali sprememb Keychain/shrambe. Neposredna byte-parity kontrola
shrambe ni izvedljiva zaradi macOS TCC; varovala nismo obšli. A se je vrnil
z istim računom in prostorom. account.changes je ob 12:00:21 UTC dejansko
vrnil HTTP200. To je dokaz usmerjanja, ne še meritev celotnega nespremenjenega
30s cikla.

Check and finish za novi prostor je FAIL1: client AccountProtectionReady.catalog
strogo pričakuje 14 polj, novi strežniški descriptor pa doda tri namige politike.
Posledica je protection_catalog_shape pred zaščitnim RPC. Načrt popravka
ohrani staro obliko podpisanega kataloga in nove namige prestavi izven vsakega
descriptorja; zgolj sprejemanje poljubnih polj ne bi ohranilo združljivosti.
Isti račun/prostor/podatki ostajajo, ni slepih ponovitev.

### Skupni časovnik — odkrita podvojitev intervala

Pasivni native zapis r2 med 12:02–12:05 UTC pokaže samo account.changes200,
brez drugih endpointov. Toda vsakih 60s: periodični 30s timer pride nekaj
ms pred rokom completion+30 in preskoči celoten naslednji tick. Root je
periodični timer zamenjal z enkratnim rokom ob zaključku; backoff/retryAt,
manual completion in foreground varovala ostanejo. Nova kontrola z dejanskim
providerjem in 200ms probe zakasnitvijo PASS1: naslednji klic med 30 in 33s.
Ozka analiza 0 errors/0 warnings, 2 style info. Native r3 preverjanje še sledi.

### Native r3 in prekinitev zaradi zaklepa Maca

Scope protection po popravku kataloga PASS2 na istem prostoru. A je poslal
povabilo B natanko enkrat, pred nastankom identitete B. B je nato skozi isto
povabilo ustvaril račun, potrdil e-naslov in pripravil/izvozil/preveril lastne
ključe. Pred klikom sprejema se je Mac zaklenil. CUA zahteva ročni odklep;
read-only strežniški pregled potrdi 2 računa, isto pending povabilo in nič
sprejemnih zahtev. Avtomatski grant, deljeni in zasebni CRUD ter konfliktni
scenariji zato še niso izvedeni. Pri uporabniku čaka vprašanje za odklep.

R3 vsebuje scoped blob target in semantični HMAC za velike payload/tabele.
Enake šifrirane vrstice, zgodovina in politika na strežniku so ob ozki zamenjavi
PHP ostale bytehash-identične. Dve nespremenjeni identiteti namestitev in
Keychain ostaneta; vsebina native containerjev ni neposredno preverjena zaradi
TCC. Ločena dnevniška evidenca potrjuje 30s razmik dveh zamaknjenih probe
tokov; dnevniki ne vključujejo identitete računa, zato pripis A/B ni neposreden.

Opazovan dodatni UX problem: po uspešnem čarovniku B ostane na predogledu
povabila prejšnje opozorilo cryptoConnectionPending. Pripravlja se točen
read-only refresh ob vrnitvi na isto povabilo, brez avtomatskega sprejema.
Kopija deljenja je že prilagojena novim pravicam v izvoru, še ni v r3 paketu.

### Pregled med čakanjem na odklep — spremembe po r3

Osvežitev istega povabila po vrnitvi iz računskega čarovnika ima tri nove
widget kontrole: uspešna ponovna verifikacija počisti staro opozorilo,
neuspeh se ne ponavlja v zanki, odgovor stare identitete se zavrne. Dva
predhodna neuspeha sta bila napaki priprave testov. Sprejem ni avtomatski
in povabilo se ne pošilja ponovno. Besedilo deljenja zdaj loči avtorjeve
pravice, dodeljena opravila in ločen finančni dostop; dve novi kontroli PASS1.

Root je odkril še staro scope-wide dovoljenje v `saveTaskWithCost`, ki bi
zavrnilo veljavno urejanje lastnega stroška članu z bralno vlogo prostora in
ločenim finančnim dovoljenjem. Ozki popravek ohrani končni per-record pregled
in ločeno finančno dovoljenje. **Popravek vmesne razlage:** prvotna domneva,
da UI vedno pošlje tudi nespremenjeni strošek, je bila napačna; zunanji
`costChanged` pogoj že izbere navadni `updateTask`. Ta veja ostane. Nova
kontrola izrecno preverja, da dodeljeno opravilo s tujim nespremenjenim
stroškom ostane task-only. Končni novi UI kontroli PASS: avtor lastnega
stroška ob ločenem finančnem dovoljenju PASS1, dodeljeni uporabnik s tujim
nespremenjenim stroškom PASS2. Core SQL transakcijska kontrola je dosegla
STOP3 zaradi nepopolne priprave fixture (finančni grant, projektni root,
projectId); pravilnih varoval nismo odstranili. Fixture je izvorno popravljen,
četrtega teka ni bilo. To ni native ali uspešen core transakcijski dokaz.
Končni agentov sklop ima 81 različnih PASS; nova core/restore STOP3 sklopa
nista vključena. Ozka analiza šestih zadnjih datotek: 0 errors/0 warnings,
14 slogovnih infos.

Izrecna obnova ob sporu z brisanjem uporablja podpisano namero, trenutno
izbrisano revizijo in najbližjo preverjeno živo različico; avtor ostane isti.
Strežniških 24 novih kontrol PASS (18 + 6) preverja dejansko admission/SQL
zgodovino ter nespremenjena finančna in table-lease varovala. To ni HTTP ali
native dokaz. Trije repository poskusi ostajajo STOP3/NEPREVERJENO, brez
četrtega teka. Dve novi protokolarni kontroli odjemalca PASS1 preverita
owner/creator dovoljenje, izločitev assignee izjeme, stabilni ključ in dejanski
Ed25519 podpis pogodbe 7. Celoten zgodovinski helper ima svoj STOP3 zaradi
priprave kodiranih polj in nepopolne wire zahteve; ni izveden četrti tek in
celotna obnova še ni dokazana.

Omejitve obnove ostajajo izrecne, osnutek se ohrani: izbrisana tabela brez
zaklepa, novo/spremenjeno veliko nalaganje, atomarni task/cost par in obnovitev
opravila v prostoru s finančnimi ključi. Zadnja omejitev velja že pred objavo,
da pošiljatelj ne bi objavil zapisa, ki ga član brez finančnih pravic ne bi
mogel projicirati. Običajna opravila in njihovo urejanje/prenos te dodatne
odvisnosti nimajo. Obnova samostojnih finančnih zapisov še ni priklopljena.

Root je po stabilizaciji novega izvora izvedel `dart analyze lib`: 0 errors,
0 warnings, 502 informativni slogovni zadetki. `git diff --check` je čist.
To je pregled prevodljivosti izvora, ne nadomestilo za odprte funkcionalne
teste ali nameščanje v aplikaciji. Po r3 ni bilo nove gradnje/namestitve.

Končni neodvisni izvorni pregled je potrdil odpravo nalaganja pred restore
varovalom in uskladitev meje zgodovine (tombstone + 63 predhodnikov). Potrdil
je tudi obnovo notification consentGeneration iz neposredne izbrisane
revizije ter vezavo avtorja in commitments v legacy sidecarju. Končna ozka
analiza 13 izvornih/testnih datotek: 0 errors/0 warnings, 75 slogovnih infos.
Podrobni izidi in omejitve so v
`build/qa/local-diagnostics/record-restore-20261024/summary.json`.
Podpisani konflikti idej/vrta dodatno še nimajo splošne podpore za varno
arhiviranje po dokončni zavrnitvi; tudi tu ostane predlog ohranjen in čakajoč.

Do odklepa je delo shranjeno kot lokalni checkpoint brez commita/pusha.
Ustavljen je samo lastni omejeni zbiralnik konzole (preverjen PID/ukaz), ne
aplikaciji ali strežnik. Pred nadaljevanjem novega GUI koraka pripravimo svež
omejen zajem. Računa, isto povabilo in vsi ključi/datoteke ostajajo; naslednji
GUI korak je še vedno prvi sprejem B z vidno odprtim A. Starih okolij ne
brišemo pred zaključkom tega scenarija.

### Po odklepu — r4 in prvi dejanski sprejem

Uporabnik je odklenil Mac. Root je obe isti aplikaciji normalno zaprl;
podagenta sta vzporedno pripravila in namestila A/B r4, vsako v enem poskusu.
613 vhodov, 26 izvornih sprememb, preverjena podpisa in enaki identiteti
namestitev/Keychain. Brez reseta ali neposrednega branja TCC shrambe.
Štiri PHP datoteke so posodobljene samo v lastnem Dockerju; sedem preverjenih
podatkovnih tabel, vključno s povabilom, ostane hash-identičnih.

B je isto povabilo sprejel enkrat ob 14:27:31 UTC (`accept` HTTP200).
A je brez ročnega klika začel samodejni pregled, a njegov `records.pull`
ob 14:27:52 vrne 409. Koda tega prvega odziva ni bila shranjena; ne trdimo,
da je bila neposredno prebrana. Izvor dokazuje manjkajoč
`supportedRecordPolicyVersion` v `reviewRotation`; strežnik pri aktivni
politiki 1 to zavrne. Običajni sync parameter že pošilja. Tri nove kontrole
dejanske metode PASS1 preverjajo popravek pogajanja. Podrobnejši pregled
pregledne poti in vezave novih pravil avtorstva se zaključuje pred r5.
Istega sprejema/povabila/registracije ne ponavljamo. Grant še ni PASS.

Neodvisni zasebni scenarij A je izveden na r4: novi prostor
`a790a9d1-f773-4c02-bfe5-e58878c5d623`, Project B — private, opravilo
PRIVATE-B-TASK-24, dogodek PRIVATE-B-EVENT-24 in finančni račun/izdatek.
GUI kaže saldo 100 − 12,34 = 87,66 EUR. Strežnik ima sprejete ustrezne
šifrirane tipe in samo A kot člana; B ni član zasebnega prostora. Metapodatkovni
SQL pregled PASS2 po popravku napačno predpostavljenega stolpca domain,
brez pisanja. Preverjanje odsotnosti pri B v GUI sledi po dostopu do A.
Tudi PRIVATE-B-IDEA-24 z besedilom je shranjena in vidna na seznamu idej.
Odpiranje/shranjevanje opazovanih obrazcev je bilo hitro, ne gre za izoliran
benchmark. Začetno številčno polje 0.00 je bilo pred Save pravilno zamenjano
s 100.00; napačnega finančnega zapisa nismo oddali.

UX ugotovitev: zasebni povezani prostor ima v projektnem pregledu oznako
Shared, čeprav je član samo A. To je nejasno besedilo, ne dokazan dostop B.
Zadnji finančni audit dodatno pojasni prejšnjo sintetično kontrolo:
kombinacije scope viewer + finance write trenutna kanonična strežniška
politika ne omogoča. Finančnih grantov zato ne širimo; ti dve UI kontroli
nista dokaz nove realne finance-viewer funkcije.

### r5 — samodejna odobritev in prejemnikov dostop potrjena

R5 A/B sta posodobljena enkrat z istima identitetama in ključi. Novi
pregled politike preverja natančno že sprejeto projekcijo za content7/finance4
in spremljevalni task intent; viewer finance izjeme ni. Tri nove kontrole
pogajanja in štiri kontrole pregleda so PASS, brez ponavljanja starih PASS.

A je ob 14:50:05 UTC samodejno aktiviral isto povabilo, brez lastnikovega
klika: en scope.activate200, B aktivni član, povabilo consumed. Primerjava
stolpcev originalnega povabila/sprejema kaže spremenjeno samo state;
prvotni podpisi in ostala polja ostanejo isti. Dokaz r5-after-auto-grant.json.

Naslednji skupni zagonski sunek doseže omejitev: 602 crypto2 poskusa v
fiksnem oknu, 600 dovoljenih in 2 rate_limited429. To ni hitra polling zanka:
account.changes teče na 30s, vendar je v manj kot5s 37 authority snapshotov.
Izvor potrdi razdrobljene kontekste in podvojena preverjanja; natančna
podvojitev posameznih selektorjev v metapodatkovnem logu ni dokazljiva.
Inbox409 ni neposredno diagnosticiran; visibility_changed je izvorni kandidat.

Po normalnem zaprtju obeh B sam nadaljuje (poskus2) in dejansko prikaže
dešifrirano ime Sync Space A, medtem ko A ostane zaprt. Selektor B vsebuje
samo Personal in Sync Space A; zasebnega SpaceB ni. Sprejema/granta ne
ponavljamo. Ostal je UX problem: ob zagonu prazni obrazec povabila z
obvestilom o nepreverjenem dostopu, čeprav Back razkrije dostopen prostor.

Omejitev zahtevkov še ni odpravljena; ozka fallback memoizacija in per-scope
read faza zaščite sta v izvedbi. Ne podaljšujemo lease ali cachiramo receipts.

### Deljeni CRUD r5 in ponovljena omejitev

B je ustvaril SHARED-B-TASK-24 in potrdil pravila testnega gostovanja. Po
normalnem zaprtju B je A prejel opravilo, izvirno opombo in avtorja Sync B:
native prenos PASS1 brez ročnega synca. A je kot lastnik dodal opombo;
shranjevanje PASS, prikaz te spremembe pri B še ni preverjen.

A je ustvaril Project A — shared in SHARED-A-ASSIGNED-B-24 z dodelitvijo B.
Zapisa sta vidna lokalno; prejem pri B še ni preverjen. Pri delu z A samim
sta ob 15:03:40 in 15:04:27 UTC authority.snapshot oziroma recordPolicy.baseline
vrnila rate_limited429. Oba odjemalca sta normalno zaprta; isto čakajoče delo
ostane. Prazen obrazec dogodka je preklican brez shranjevanja.

Metapodatki od 15:00: 1923 zahtev, 1921x200 in 2x429, directory.status524,
headGet307, authority.snapshot183. To vključuje več dejanj in ni benchmark
ene transakcije. Tretji lokalni poskus omejitve sledi šele po pregledu
združevanja branj. Če še odpove, velja STOP3 brez četrtega native kroga.

Novi ozki testi: fallback memo4PASS1; zaščitni read fazi3PASS2 (prvi neuspeh
fixture partition); obnovljeno sprejeto povabilo2PASS2 (prvi neuspeh URL
fixture). Neodvisni pregled je zahteval sveže preverjanje članov PO legacy
inspect; končni popravek to upošteva. Stare uspešne kontrole niso ponovljene.
Native zbiralnik76421 je ustavljen po preverjanju exact ukaza; ni zajel
uporabnega stacka, zato takega dokaza ne trdimo.

### r6 — omejeno združevanje preverjanj

Končni pregled root + neodvisna podagenta je potrdil ozko spremembo:
`scopes.list` in `scopes.members` iste metadata faze si delita obstoječi
preverjeni kontekst. Izvirnih pet sekund se ne podaljšuje. Menjava seje,
drug router, gnezden kontekst, napaka, sočasni klic ali zapisovanje trajno
zaprejo skupino. Projekcijski cursorji, pull, finance, nadgradnja politike in
outbox ostajajo zunaj. Podpisane zahteve in receipt-first nadaljevanje so isti.

Tri nove kontrole te skupine PASS1, analiza 0 errors / 0 warnings; obstoječi
slogovni infos niso obravnavani kot funkcionalne napake. Prihranek native
zahtevkov še ni izmerjen. R6 A/B uporablja 615 vhodov in osem novih lib
sprememb glede na r5, isti namestitveni identiteti in isti Keychain. Gradnji
potekata vzporedno, brez nove kopije vseh izvorov. Pred posodobitvijo so
shranjeni odtisi 177 tabel lastnega testnega strežnika.

### Končni lokalni rezultat r6: STOP3 za število zahtevkov

Obe gradnji/namestitvi PASS1, podpisa in bundle/Keychain identiteti preverjeni.
177 tabel je med mirovanjem čez posodobitev hash-identičnih. Neposredna byte
primerjava vsebine app containerjev ostaja nepreverjena zaradi TCC; ni obvoda.

Tretje nadaljevanje istega scenarija ni odpravilo omejitve. V zajetih 75
sekundah HTTP dnevnika je 949 zahtev, 946x200 in 3x429. Prve zavrnitve so
crypto2 zahteve št. 601, 602 in 603 po 600 uspešnih: directory.status,
authority.snapshot in account.status. Pet account.changes zahtev je 200;
metapodatki ne vsebujejo changed/cursor, zato to ni dokaz idle/no-change
načina. Novega obsega podatkov ne primerjamo odstotkovno s prejšnjim r5.

B je po Continue locally v Pulse prikazal Project A — shared. To potrjuje
prenos/prikaz imena projekta, ne vsebine dodeljenega opravila ali njegovega
urejanja. A je pri Check and finish za novi katalog dobil opozorilo v oknu
429. Prvi B generic wizard error nima zajetega točnega stacka/kode; ne
pripisujemo ga samodejno 429. Obe aplikaciji sta nato normalno zaprti.

Velja STOP3: brez četrtega testa, novega builda za isti simptom ali ponovitve
povabila. Odvisni preostali testi so označeni neizvedeni: prikaz lastnikove
spremembe pri B, urejanje dodeljenega opravila, deljeni dogodki/nakupi/finance,
konflikti/offline in širši moduli. Zasebni CRUD ter prvotni sprejem, samodejna
odobritev in B→A prenos ostajajo uspešni in jih ne ponavljamo.

Ohranjen je isti strežnik, računa, povabilo, ključi, datoteke in čakajoče delo.
Starih okolij še ne brišemo, ker sveži scenarij ni dokončan. Produkcija in
telefoni niso bili uporabljeni. Obstoječe nadgradnje politike in restore
STOP3 omejitve ostajajo odprte; različica ni pripravljena za objavo.
Naslednja smiselna naloga je ločen merjen pregled notranjih pull/checkpoint/
observation zahtevkov, ki so kandidati, ne že dokazan vzrok celotnega obsega.

Končni dokaz: `build/qa/sync-redesign-20261024/r6-continuation-final.json`,
podrobni koraki pa `native-scenario-ledger.json` v isti mapi. Ni commita/pusha.
