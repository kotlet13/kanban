# Priprava mobilnega nadaljevanja — 20. oktober 2026

## Obnova testnega TLS — 21. oktober

Po izrecnem naročilu uporabnika sta CA in strežniški certifikat istega
mobilnega QA `https://192.168.132.29:18801/` obnovljena za 30 dni:
**21.10.2026 07:23:22 UTC–20.11.2026 07:23:22 UTC** (konec 20.11. ob
08:23:22 po lokalnem času). Ista zasebna ključa, subjekta in točen IP SAN;
originali so zasebno ohranjeni. Nov javni CA PEM SHA-256:
`b9af2a77f19f4b541fd035858d4800408239b8d32d696f6075add608afe540f5`.

[Staging](../build/qa/jivie-mobile-tls-renewal-20261021/staged-evidence.json)
potrdi osem ciljnih kontrol, tudi napačen IP/izdajatelja in iztek veljavnosti.
Staro vgrajeno CA potrdilo po svojem izteku ostane neveljavno kljub istemu
ključu, zato sta potrebna tudi nova paketa. Ni izklopa preverjanja,
spremembe sistemske ure ali dodajanja sistemskih zaupanih izdajateljev.

[Namestitev certifikata](../build/qa/jivie-mobile-tls-renewal-20261021/deployment-evidence.json)
ob 07:29:44 UTC potrdi novi streženi certifikat s svežo strogo TLS povezavo
in en javni capabilities HTTP200 istega serverId. Spremenjeni sta samo
CA/leaf datoteki; nginx config test in reload, brez ponovnega zagona
vsebnikov. Identitete, časi zagonov in stanja štirih storitev, ključi in
konfiguracije ostanejo enaki. Brez avtenticiranega ali poslovnega RPC.
Končni PASS je tretji omejeni poskus: prvi ni potrdil takojšnjega stanja
po reloadu in je vrnil datoteki; drugi je pred spremembami pokazal razliko
med naloženim novim certifikatom in vrnjenima starima datotekama. Tretji
uskladi nove datoteke, različen mtime in naloženi certifikat. Razlaga z
nginx predpomnjenjem SSL objektov ostaja sklep, ne neposredno izmerjen vzrok.

Nova paketa sta **21. oktobra popoldne nameščena čez isti Jivie Test**;
novi uporabniški preizkus še čaka. Namestitev ohrani podatke, brez
odstranitve aplikacij ali praznjenja:

- [Android APK](../build/qa/jivie-mobile-tls-renewal-20261021/android/Jivie-Test-Android-cf97e2d-TLS-20261021.apk), SHA-256 `982d6893c37ea86579d972d946c781a012f1872eaece5ae2662999802933003e`, 105.713.405 B.
- [iOS IPA](../build/qa/jivie-mobile-readiness-20261020/ios/tls-renewal-20261021/candidate/Jivie-Test-iOS-QA-TLS-20261021-development.ipa), SHA-256 `be48d130f83e47d2c4c19e892dec315be49cc015356bfabff1a89e27bcf936a2`, 16.468.271 B; pripadajoči `Runner.app` je v istoimenskem xcarchive.

Vsak paket nastane v prvem poskusu v svojem obstoječem QA imeniku. Samo
vgrajeni javni PEM je spremenjen; funkcionalni osnovi ostaneta Android
56fbc372… in iOS bbc61dc6… (vključno z iOS popravkom povabila). QA ID,
podpis, Keychain/service/group, URL, SDK in locks isti. Androidovih sedem
native knjižnic in vseh 19 DEX vsebin je enakih (štiri imena DEX se
prerazporedijo), 13 registriranih vtičnikov ostane. iOS native knjižnici
brez podpisa sta bajtno enaki, podpisi paketa/frameworkov preverjeni.
Oba dejanska paketa vsebujeta novi CA, starega PEM ne več.
Po predaji sta odstranjena samo regenerirana predpomnilnika teh gradenj:
Android 16 map/1.370.484.736 B zasedenega prostora, iOS pet map/1.188.519.936 B.
Izvori, novi in prejšnji paketi, zasebne kopije ter dokazi ostanejo.

Uporabnik od zdaj izvaja UI scenarije. Agent pripravlja okolje, diagnostiko
in popravke. Obnova TLS ni ponovitev deljenja, obnove ali drugih PASS
scenarijev; produkcija, podatki in prvotno povabilo ostanejo nedotaknjeni.

### Namestitev pred uporabnikovim ročnim testiranjem

Po izrecnem naročilu uporabnika ob priklopljenih odklenjenih telefonih je
vsak paket nameščen enkrat čez svoj QA ID. Android ohrani podpis, UID in
dataDir; štiri šifrirane datoteke (2.941.318 B) so pred/po enake. iOS
ohrani podpis/Keychain/service/group; njegove štiri šifrirane datoteke
(1.847.686 B) so pred/po enake. Sveži kopiji sta zasebni. Produkcijski
metapodatki ostanejo nespremenjeni. Android QA ni tekel; iOS stari QA
proces je normalno ustavljen pred kopijo. Po namestitvah oba zaprta,
brez našega launch/UI ukaza ali poslovnega scenarija.

Dokaza: [Android](../build/qa/jivie-mobile-tls-renewal-20261021/android/installation-20261021/installation-evidence.json)
in [iOS](../build/qa/jivie-mobile-readiness-20261020/ios/native-TLS-update-20261021/installation-evidence.json).
Read-only preflight strežnika ob 15:31:03 UTC potrdi isti IP, novi streženi
certifikat in en javni HTTP200, brez poslovnega RPC. Pripravljena sta
omejeni pasivni iOS zajem in 180-sekundni strežniški zajem samo metapodatkov
z avtomatsko obnovo konfiguracije; vklop neposredno pred uporabnikovim
prvim korakom. Android zajem počaka na njegov korak. Pripravljen zajem
ni dokaz povezane konzole; stari v4 zaključni zapisi niso nov PASS.

Prvi ročni korak je odprtje Jivie Test na iPhonu, ob znanem opozorilu
»Nadaljuj v lokalne podatke«, nato sporočilo o prikazanem zaslonu.
Povabila, sprejema in lastnikove odobritve ne ponavljamo.

### Prvi ročni prikaz skupne vsebine

Uporabnik odpre iOS Jivie Test in izbere »Nadaljuj v lokalne podatke«.
Glavni agent samo opazuje Device Hub, brez klikov: najprej zaslon zaščite
povezanih podatkov z opozorilom o nedokončani pripravi/čakajočem pošiljanju.
Uporabnikov Nazaj pokaže Utrip skupnega prostora, nato odpre projekt
MOBILE-PROJECT-1 in opravilo MOBILE-SHARED-1. V obrazcu »Uredi opravilo«
sta dejansko vidna isti naslov in opomba FROM-A-20261018: **PASS prikaza
obstoječe skupne vsebine na iPhonu**, ne dokaz novega synca ali pisanja.
Uporabnik oceni odpiranje opravila na približno eno sekundo; to je
opažanje brez meritve ali ugotovljenega vzroka. Ni zahteve za ponovitev.
Rdeči indikator synca in zgornje opozorilo ostaneta odprta za pregled.
Uporabnik še ni shranil spremembe.

Prvi omejeni zajem se zaključi sam: iOS prepozna QA PID1718, a sprejme
0 NET oznak (povezana konzola ni potrjena); strežnik zabeleži 254 POST200,
4 POST403 in 6 GET200 brez pripisa klientu/operaciji/vzroku. Gateway se
ob 15:37:13 UTC vrne v točno prvotno konfiguracijo, oba zajema sta OFF.
403 sam po sebi ni diagnoza trenutnega opozorila. Stari v4 PASS ni ponovno
uporabljen kot dokaz današnjega scenarija.

### Pregled opozorila v oblačku — 21. oktober

Uporabnik odpre oblaček. Dialog pokaže zadnji poskus 17:40 lokalno,
zadnjo uspešno uskladitev »Še ni potrjena« in vrste 0/0/0. Sporočilo
`cryptoConnectionPending` ni enolična diagnoza: `sharing_errors.dart:91–93`
združi `crypto_reconciliation_required`, `crypto_transport_required` in
`crypto_server_upgrade_required`. Predhodni napis na zaslonu zaščite je
v `crypto_migration_wizard.dart:542` prikazan brez pogoja; sam po sebi ni
dokaz nepripravljenega računa.

Pregled istega iOS QA izvora potrdi izgubo prvotnega razloga:
`collaboration_sync_actions.dart` pretvori `CryptoAuthorityPending` pri
članih (280), branju (650) in zunanji meji (729) v splošno napako;
`collaboration_finance_sync.dart` enako naredi pri finančnem obsegu (207)
in odvisnostih (273). Nekatere API napake so prav tako združene.
`_lastError` je pomnilniško stanje. QA omrežni dnevnik opazuje HTTP, ne
poznejšega lokalnega preverjanja podpisov. Trajna v4 diagnostika je vezana
na nadaljevanje povabila in ne zajema običajnega synca. **Točno mesto in
prvotni razlog današnje native napake še nista dokazana.**

Omejen read-only pregled treh streženih PHP datotek (`NativeService`,
`NativeCryptoV2Service`, `NativeApiController`) potrdi bajtno ujemanje s
trenutnim izvorom in QA izvorom. Oglaševane pogodbe podpirajo crypto2;
ni dokaza za razlago »strežnik potrebuje nadgradnjo«. Štirih starih POST403
ni mogoče pripisati operaciji ali računu iz zbranih metapodatkov.

Potreben naslednji diagnostični korak je en omejen zapis **prvotne**
napake običajnega synca pred pretvorbo: faza, dovoljena koda in statična
oznaka mesta, prvi vzrok ter zaključek istega poskusa. Zapis mora biti v
novem QA imeniku `Library/Caches`, brez vsebine, identifikatorjev, ključev,
žetonov ali surovega stacka; brez novih map v Documents in brez spremembe
varoval, ponovitev ali urnika. Uporabnik upravlja naslednji ročni korak;
prvotno povabilo, seji in podatki ostanejo, produkcija je nedotaknjena.

Po pregledu je v istem izoliranem iOS izvoru pripravljen samo diagnostični
dodatek: štiri obstoječe datoteke, dva nova pomočnika in en nov testni vir.
Prva opozorilna izjema se shrani pred pretvorbo, zaključek po končnem
knjiženju statusa; namenoma obravnavana odsotnost nadrejenega finančnega
prostora ostane izvzeta. Ohranijo se izvorne končne kode in obstoječe
oznake `dp_*`, kadar je napaka v preverjanju imenika. Zapis je enkraten
tudi po ponovnem zagonu, nepopoln ali preskočen poskus ni uspeh.
Pet novih ciljnih kontrol PASS v prvem teku; analiza 0 napak/0 opozoril
in 1 stara slogovna pripomba. Glavni in neodvisni pregled PASS. To preveri
diagnostiko, ne razrešitve telefonske napake.

Dokazi in majhen diff so v
`build/qa/jivie-mobile-readiness-20261020/ios/sync-warning-diagnostic-20261021/`:
`manifest.json`, `diagnostic.patch`, `evidence.json`, `root-source-review.md`.
Odobren je en arhiv ob istih SDK, locks, podpisu, shrambi in obnovljenem CA;
celotna izvorna kopija ni ustvarjena. Funkcionalni popravek še ni določen.

Prvi diagnostični arhiv PASS: IPA `569b4626aca124c61075fe6a625ec7a4c3f1f17cd8847f9c9f2138de3be74317`,
16.477.059 B. Preverjeni podpis/profil/Keychain/TLS/SDK/locks isti;
sqlite3mc in sodium brez podpisa bajtno enaka prejšnjemu be48 paketu.
Enaka QA aplikacija je posodobljena enkrat ob 15:58:47 UTC, brez zagona.
Pred tem je isti QA PID1718 normalno ustavljen; sveža zasebna kopija štirih
vault datotek 1.896.838 B ima pred/po namestitvi enake hashe. Produkcijski
metapodatki so enaki, ni odjave/ponovnega povabila/FILE ali branja Keychaina.

Ob 15:58:52 UTC je potrjena odsotnost novega diagnostičnega imenika
`Library/Caches/jivie_qa_sync_warning_20261021_v1`; naslednji zapis bo zato
nov, ne zgodovinski v4. Pripravljen je `native/read-durable.py`, ki prebere
samo tri fiksne datoteke in preveri oznako gradnje, čas in dovoljene vrednosti.
Priklop omrežne konzole ni potrjen in za ta zapis ni potreben. **Čakamo
uporabnikov zagon iste Jivie Test** ter po potrebi znani Continue; orodja
aplikacije ne zaženejo. Točen izvorni razlog še ni zajet in napaka ni označena
kot odpravljena. Android in testni strežnik v tej preiskavi nista spremenjena.
Po preverjeni namestitvi odstranjenih pet regenerabilnih cache map tega
arhiva (1.224.544.256 alociranih B); izvor, diff, arhiv/IPA, dokazi in
zasebne kopije ostanejo. Hashi novega in dveh predhodnih IPA so nespremenjeni.

### Prvi sveži sync zapis in ožja diagnostika dostave

Uporabnik odpre aplikacijo in isti oblaček. Branje treh fiksnih v1 datotek
ob 16:01:29 UTC potrdi nov samodejni poskus 16:00:40–16:00:45 UTC:
`finance_choices` / `finance_authority` / `CryptoAuthorityPending` /
`crypto_business_delivery_pending`. Zaključek ima veljavno sejo in lease,
izid `failed`, končno kodo `crypto_reconciliation_required`. To je prvi
dejanski native poskus te diagnostike; ni novega Save/Sync/povabila.

Pot je izbira finančnih računov → ensure/materialize → publishRaw →
resumeUnresolved → lokalni crypto_outbox ni `applied`. Slednja koda lahko
pomeni pending, blocked ali rejected; sama ne dokazuje konflikta. En
omejen SELECT na istem testnem strežniku, mode=ro/query_only, ne najde
ohranjenih potrdil B za financeAccountChoice prvotnega podrejenega prostora.
Strežnik zavrnitve 401/403 vrne pred zapisom potrdila, zato odsotnost potrdila
ne izključuje zavrnitve. Dodatni ozki SELECT potrdi: B nima sprejetih pravil
v1 in prvotni podrejeni prostor je skupen. `uploadPolicy` bi zato ob dosegu
te meje zavrnil records.batch s `policy_acceptance_required`/403. To še ni
neposredni dokaz, da je konkretni native zahtevek dosegel mejo pošiljanja.

Pripravljena v2 diagnostika v istem QA izvoru doda samo lokalno stanje,
dovoljena polja shranjenega odgovora in prvo prestreženo napako točno
izbrane dostave (lookup/before_delivery/send). Povezovalni ID ostane le v
pomnilniku; podrobnost se zapiše šele ob isti končni pending izjemi.
Obstoječi SELECT dobi stolpec response, brez nove poizvedbe ali spremembe
ponavljanja, podpisov in teles zahtev. Nov v2 cache ohrani v1 dokaz.
Tri nove kontrole PASS v drugem teku; prvi je compile FAIL (manjkajoči
testni import in podvojena konstanta), ohranjen v dokazu. Analiza 0 issues,
glavni/neodvisni pregled PASS; zaključna dva dovoljena niza preverjena
statično in z analizo, brez ponovitve starih PASS. Funkcionalnega popravka
še ni in pravil uporabnika nismo potrdili.

Dokazi: `ios/sync-warning-detail-20261021/{manifest.json,diagnostic-v2.patch,evidence.json}`
pod istim mobilnim QA imenikom; strežniška izida sta
`build/qa/jivie-mobile-manual-20261021/server/b-choice-receipts-readonly.json`
in `b-policy-guard-readonly.json`. Native števec ostaja 1; v2 še čaka zagon.

V2 arhiv PASS v prvem poskusu; IPA
`b2ec0e0a34d43dd488e48260d3697d49019fee0481c19b1338a047e499101000`
(16.482.954 B). Dejanski podpis/profil/Keychain/shramba/obnovljeni CA
preverjeni; sqlite3mc in sodium brez podpisa bajtno isti kot v1, vseh148
datotek IPA ustreza podpisanemu arhivu. Samo tri pregledane runtime
datoteke se razlikujejo; SDK in locki ostanejo isti.

Isti QA PID1727 je normalno ustavljen16:16:49UTC. Ena in-place namestitev
ob16:17:03UTC PASS, sveža kopija štirih vault datotek1.896.838B in hashi
pred/po enaki. iOS je spremenil pot vsebnika, vsebina pa je ohranjena;
produkcijski metapodatki so isti. Ni uninstall/reset/restore/prijave/FILE
ali zagona z orodji. Novi v2 cache je dokazano odsoten16:17:15UTC.
Dokazi so `candidate/artifact-evidence.json`, `native/installation-evidence.json`
in `native/readback-armed.json` pod istim v2 imenikom.

Naslednji korak je samo uporabnikov zagon Jivie Test in po potrebi znani
»Nadaljuj v lokalne podatke«. Nato agent izvede
`python3 build/qa/jivie-mobile-readiness-20261020/ios/sync-warning-detail-20261021/pipeline.py read`.
To bo native poskus2 iste diagnostike; nobenega novega poslovnega scenarija,
Sync, povabila ali ponavljanja PASS. V2 še ni funkcionalni popravek.

Po preverjeni predaji odstranjenih pet dovoljenih regenerabilnih cache map,
1.236.004.864 alociranih B; dejanski prosti prostor se poveča za1.053.630.464B.
Vsi štirje potrebni IPA (v2/v1/be48/bbc61), izvori, arhivi, diffi, dokazi in
zasebne kopije ostanejo; hashi paketov so isti. Nove polne kopije izvora ni.

### V2 native dokaz: zavrnitev zaradi nepotrjenih pravil

Uporabnik odpre isto aplikacijo in izbere »Nadaljuj v lokalne podatke«.
Bralnik ob16:19:46UTC potrdi sveži v2 samodejni cikel16:19:37–42UTC,
veljavno sejo/lease in prvo napako `finance_choices` / `finance_authority` /
`crypto_business_delivery_pending`. Natančna dostava je `pending`, brez
shranjenega odgovora; prestrežena izvorna napaka je **send /
CollaborationException / policy_acceptance_required**. Zaključek `failed`
jo spremeni v `crypto_reconciliation_required`. To je native poskus2 in
neposredna potrditev prej domnevne zavrnitve zaradi nepotrjenih pravil.

`crypto_sync_repository.dart` pri send prestreže CollaborationApiException
in nato išče potrdilo; ta policy403 pa potrdila nima. Zahteva zato ostane
pending. Obstoječi oblaček prikaže gumb za pravila samo pri izvirni kodi
`policy_acceptance_required`, zato jo pretvorba skrije. Predlagani ozek
popravek prenese to actionable napako do UI, obdrži isto čakajočo podpisano
zahtevo in ne ustvarja umetnega potrdila. Še ni implementiran; uporabnik
pravil v tem koraku ni potrdil. Nobenega novega Save/Sync/povabila ali
ponavljanja uspešnih scenarijev. Android in produkcija ostaneta nedotaknjena.
Dokaz: `ios/sync-warning-detail-20261021/native/latest-durable-result.json`
pod istim mobilnim QA imenikom. Zgornje čakanje na v2 zagon je zgodovina.

### Funkcionalni popravek pravil sodelovanja

Po izrecnem naročilu uporabnika je v glavnem izvoru popravljen samo catch
pošiljanja v `lib/organizer/data/e2ee/crypto_sync_repository.dart`: koda
`policy_acceptance_required` se ponovno vrže, vse druge API napake ohranijo
prejšnjo pot do točnega potrdila. Ista čakajoča podpisana zahteva ostane,
brez novega podpisa/ID, umetnega potrdila ali samodejnega sprejema pravil.
Obstoječa finance API in zunanja sync obravnava kodo preneseta do že
obstoječega sporočila in gumba »Pravila sodelovanja«. Uporabnik pregled in
potrditev opravi v obstoječem skupnem prostoru; osebni prostor ima ločeno
obstoječo obravnavo pravil.

GPT-6.1 Sol/high izvede popravek in tri nove ciljne kontrole, drugi podagent
in glavni agent opravita pregled PASS. Prvi tek nove prve kontrole na stari
kodi FAIL reproducira skrito izjemo; drugi tek vseh treh novih kontrol PASS:
ista izjema/nespremenjena čakajoča zahteva in claims, nadaljevanje istega
podpisa po spremembi testnega pogoja, drugi409 ohrani točno potrdilo in
zgodovinski ACK prepreči ponovno pošiljanje/preflight. Stari PASS niso
ponovljeni. Format/diff check PASS, scoped flutter analyze0error/0warning
in4stari testni style info (vrstice preverjene proti izvirniku).
Glavni runtime SHA `d884164aa56271fa2bea3014678927d93a0d4a9eb6fdc24534d06c55fe4a0e45`.
Dokaz: `ios/policy-required-fix-20261021/main-evidence` pod istim QA imenikom.

V istem QA izvoru se ohrani diagnostika v2 in doda samo štirivrstični guard
za policy napako. Drugih1762 vhodov je bajtno enakih nameščeni osnovi
b2ec0e0a…, SDK/locki/podpis/shramba/CA nespremenjeni. QA runtime SHA
`d57c269e546ddb74d876950e38d43fa0e3349e7bedc3ea201757c2a5e4e71474`.
Pipeline in overlay izrecno označita funkcionalni popravek; obstoječi v2
dnevnik ostane zgodovinski dokaz, brez novega cache/ponastavitve ali trditve
o novem uspešnem syncu. Izvedba paketa: `ios/policy-acceptance-fix-20261021`.

Arhiv PASS v prvem poskusu, IPA
`2621b85d8113bbc3de74698d1b3b5327c7cfff446cd56f0084578346f0e27bcd`
(16.483.522 B). Dejanski podpis/profil/certifikat/Keychain/shramba/CA
preverjeni; obe native knjižnici brez podpisa bajtno isti kot b2ec, vseh148
datotek IPA ustreza arhivu. Glavni pregled artefakta PASS.

QA PID1732 normalno ustavljen16:27:42UTC, sveža kopija štirih šifriranih
vault datotek1.896.838B. Ena in-place namestitev16:27:54UTC PASS; vse štiri
datoteke pred/po imajo iste hashe. iOS ponovno dodeli pot vsebnika, ne
spreminja preverjene vsebine; produkcijski metapodatki so isti. Brez
uninstall/reset/restore/prijave/FILE/novega povabila, brez zagona ali UI
dejanj z orodji. V2 cache in dokazi ostanejo zgodovinski; ni novega arm/read.

Naslednji fizični korak opravi uporabnik: odpre Jivie Test, po potrebi
znani Continue, v istem skupnem prostoru/projektu odpre oblaček in
»Pravila sodelovanja« ter jih sam pregleda in potrdi. Vidnost gumba,
sprejem pravil in poznejši uspešni sync še niso native potrjeni. Ne
ponavljamo že uspešnih scenarijev. Android/server/produkcija nespremenjeni.

Po predaji odstranjenih pet dovoljenih regenerabilnih cache map,
1.188.716.544 alociranih B (dejanski prirast prostega prostora1.005.531.136B).
Vseh pet potrebnih IPA ohrani iste hashe; izvori/arhivi/diffi/dokazi in
zasebne kopije ostanejo. Ni nove polne kopije izvora ali drugih čiščenj.

### Po uporabnikovi potrditvi pravil: nova napaka odgovora

Uporabnik sporoči sprejem pravil in ročni sync. Root samo opazuje fresh
Device Hub prikaz: MOBILE-PROJECT-1, zadnji poskus21.10.18:40lokalno,
zadnji uspeh še ni potrjen, vrste0/0/0, besedilo `sharingInvalidResponse`.
Besedilo združuje kodi `invalid_response` in `redirect_rejected`; samo
zaslon ne dokazuje natančne kode ali nezdružljivosti strežnika.

En omejen read-only/query_only SELECT16:41:12UTC na istem QA18801 potrdi
B policyv1 accepted=true in eno matching financeAccountChoice potrdilo
prvotnega childa, ustvarjeno16:39:28UTC,409/errorCode conflict, en zapis
expectedRevision1, brez appliedACK. Prejšnja policy ovira je odpravljena.
Potrdilo ni neposredno korelirano s konkretnim native requestom v zadnjem
prikazanem poskusu; konflikt še ne dokazuje vzroka novega splošnega opozorila.
Dokaz: `build/qa/jivie-mobile-manual-20261021/server/b-policy-and-choice-after-manual-sync-20261021T1640Z.json`.

Omejen izvorni pregled: materialize ob terminalnem409 preveri podpisano
zahtevo in točno potrdilo, nato pullVerified/_currentManifest/novejšo
crypto_revision. Napake ob teh korakih se lahko pretvorijo v splošno
invalid_response, obstajajo pa tudi druge poti. Stari Mac legacy_revision
popravek je že prisoten; starega vzroka zato ne prenašamo na nov primer.
Obstoječi v2 logger je one-shot in ohranja16:19 zgodovinski zapis; tudi nov
FormatException bi zabeležil kot other brez konkretne statične kode.
Trenutnega izvornega mesta/izjeme nimamo. Naslednji dokaz mora zajeti
aktualno fazo, tip in dovoljeno statično kodo napake, ne ponavljati
potrditve pravil ali starega povabila. Brez nove gradnje/resetiranja dnevnika,
samodejnih UI dejanj, novih poslovnih vnosov ali ponovitev PASS v tem koraku.
Celotni sync ostaja odprt; podatkovna izguba ni dokazana. Produkcija ista.

## Zgodovina priprave 20. oktobra

**Poznejša skupna seja je že začeta:** dejanske namestitve, popravek
Androidove registracije dodatkov in mobilna odobritev dostopa so zapisani v
[aktualnem nadaljevanju](E2EE_MOBILE_SESSION_2026_10_20.md). Spodnji opis
je dokaz predhodne priprave, ne trenutni status naprav.

Uporabnik je naročil pripravo za skupno testiranje po vrnitvi domov.
Ta korak pripravlja pakete, testni strežnik in diagnostiko; ne izvaja
namestitev na telefona ali uporabniških testnih scenarijev.

**Aktualni izid po uporabnikovem dodatnem naročilu popravka: Android,
iOS in testni strežnik so pripravljeni.** iOS podpisovanje je popravljeno
in novi podpisani paket preverjen. Telefona in njuni podatki niso bili
spremenjeni; namestitev in skupni test počakata na uporabnikovo vrnitev.
Prejšnji blokirani korak in njegovi trije poskusi so ohranjeni spodaj.

## Osnova in izolacija

Zamrznjeni izvor je `cf97e2df81c5411fdf05bf0d8cb59ad840db2055`.
Manifest `build/qa/jivie-mobile-readiness-20261020/source-freeze.json`
veže 1.560 vhodov z aggregate SHA-256
`7756cdb9c992d3db398318d2022fb5ffa44fc15df1d7aeb408b7873fc245935a`.
Ločena Android in iOS staging imenika vsebujeta samo pregledane QA razlike.
Gradnji potekata zaporedno z obstoječim SDK in zaklenjenimi odvisnostmi.

Nadaljujemo stanje iz
[mobilnega runbooka](E2EE_MOBILE_TWO_USER_TEST_2026_10_18.md):

- S25, A, lastnik: `si.triparna.jivie.e2eetest.android20261018`.
- iPhone 11, B, prejemnik: `si.triparna.jivie.e2eetest.ios20261018`.
- Obe aplikaciji imata ime **Jivie Test**. Shrambe, podpisi in identitete
  varne hrambe ostanejo isti; prava trgovinska Jivie se ne spreminja.
- Ista dva testna računa, lokalni vnosi, računski obnovitveni datoteki,
  projekt in eno že sprejeto povabilo ostanejo. Sprejem čaka lastnikove
  ključe; registracije, FILE čarovnika ali novega povabila ne ponavljamo.
- Mobilni Docker uporablja `https://192.168.132.29:18801/`; ne uporabljamo
  Mac deljenja na 18811 ali benchmarka na 59776. Zaupanje ostane omejeno
  na isti namenski CA in točen HTTPS cilj.

Takratni CA poteče **21. oktobra 2026 ob 12:25:42 UTC**; zgornja obnova
21. oktobra ga nadomesti na strežniku in v pripravljenih novih paketih.
Stari nameščeni aplikaciji potrebujeta posodobitev. Dostopnost LAN in
veljavnost certifikata preverimo še ob dejanskem začetku, ker se IP lahko spremeni.

## Začetek skupnega testiranja

Spodnji skupni tok počaka na uporabnikovo vrnitev. Oba paketa sta pripravljena;
pred namestitvijo ponovno preverimo napravi in dosegljivost testnega gostovanja.

1. Uporabnik priključi in odklene S25 ter iPhone 11. Oba sta na istem Wi-Fi
   kot Mac. Potrdimo prepoznani napravi in izključno testna ID-ja.
2. Pred zamenjavo preverimo trenutni testni paket, stanje in ustrezno kopijo
   podatkov. Namestimo pripravljeno posodobitev čez isto testno aplikacijo,
   brez odstranitve, brisanja podatkov ali spreminjanja Keychain/Keystore.
3. Zajem dnevnikov pripravimo **pred prvim zagonom in dejanjem**. Zajema
   točen paket/proces, metode, čas, status in omejene diagnostične kode;
   brez vsebine, ključev, datotek FILE, gesel ali tokenov.
4. Najprej preverimo zagon istega stanja ter en zaključen običajni sync.
   Nato nadaljujemo isto sprejeto povabilo z lastnikovo odobritvijo dostopa
   po novem poenostavljenem toku, brez obvezne primerjave kartic.
5. Zaključimo še odprte mobilne poti: branje skupnega opravila, dvosmerna
   sprememba, ohranitev lokalnega zasebnega vnosa, finančne pravice in
   saldo, offline/ponovna povezava ter mobilni odvzem kot zadnji poseg.
   Že uspešnih Mac scenarijev in že izvedenega Mac odvzema ne ponavljamo.
6. Sveža obnova in stara → nova fizična nadgradnja sta ločeni naslednji
   vaji z zaščiteno kopijo ter vnaprej določenim računom/ciljem. Ne brišemo
   teh dveh aktivnih testnih namestitev za pripravo svežega testa.

Ob napaki se najprej zabeležijo prva izjema oziroma stabilna koda, faza,
čas in pending/conflicting/blocked stanje. Največ trije poskusi na težavo;
potem dokaz in SKIP/BLOCKED, brez novega računa ali fixture za ponastavitev
števca. Dejanja, ki so že uspela na strežniku, se ne pošiljajo znova.

## Znane odprte meje

- Opozorilo pri nekaterih blokiranih vrstah napačno enači razlog z odvzemom
  in potrebo po ročnem nadaljevanju. Stari Mac N7 je po treh poskusih SKIP;
  priprava ne začenja četrtega kroga.
- Sveža strežniška zavrnitev pisanja po odvzemu v zadnjem Mac scenariju
  ni bila izvedena. Mobilni tok še ni zaključil deljenja/odvzema.
- Prihranki zadnjih optimizacij so dokazani na majhnem lokalnem HTTP naboru,
  ne še na telefonih. Ocenimo tudi prehode v ozadje in ponovno povezavo.
- Fizična obnova, migracija obstoječih podatkov, neodvisni pregled celotne
  E2EE sestave in izdajna vaja ostajajo odprti. To ni produkcijska izdaja
  ali začetek 30-dnevnega roka za odstranitev starih kopij.

## Pripravljeni testni strežnik

Isto mobilno gostovanje je posodobljeno na zamrznjeni izvor. Spremenjenih je
šest datotek FamilyHub (pet PHP in README); vseh 182 datotek ciljne kode
se ujema z manifestom. Shema in inicializacijska koda sta isti, brez nove
migracije. PHP lint spremenjenih datotek je uspešen.

Pred zamenjavo so bili začasno ustavljeni samo štirje mobilni testni
vsebniki. Zasebna kopija vsebuje 212 preverjenih datotek (209 za prejšnjo
strežniško pripravo, dve v app-data in eno v mail-data), z dovoljenji 0700.
SQLite integrity je `ok` pred spremembo in po njej. Vseh 220 tabel ima
enake vrstice in število zapisov, shema je točno ista. Datoteka baze sama
ni bajtno enaka; dokaz je primerjava sheme in vseh vrstic.
Ločeni pregled istih offline kopij potrdi tudi vseh 499 objektov
`sqlite_master`, z enakimi izvirnimi in normaliziranimi definicijami.
Prvotni `schema` podatek v poročilu je zajemal samo verzije vtičnikov;
dejanska DDL primerjava je zato dodana posebej, ne zgolj sklepana iz verzij.

Javni HTTPS capabilities odgovor je HTTP200, z istim `serverId`,
authority snapshot različico 1 in invitation različicami 1–4. Isti CA,
konfiguracija in podatki zunaj šestih zamenjanih izvornih datotek so
ohranjeni. App, gateway in Mailpit so zagnani; **mail-worker ostaja
ustavljen** do skupnega nadaljevanja. Ni avtenticiranih poslovnih zahtevkov,
poštnega testa ali dejanj na telefonih.

Priprava je uspela v tretjem omejenem poskusu. Prvi je popravil primerjavo
Markdown datotek z izvorno zamrznitvijo, drugi je obstal pri odpiranju kopije
SQLite. Kopirani bazi ohranita oznako WAL, čeprav pri doslednem kopiranju ni
bilo WAL/SHM datotek; končno preverjanje uporablja immutable način samo na
zasebnih offline kopijah. Korupcija ni bila ugotovljena. Navidezna razlika
sheme je bila tuple/list razlika pri serializaciji dokazov; normalizirana
primerjava je potrdila enako shemo.

Dokazi so v `build/qa/jivie-mobile-readiness-20261020/server-preparation/`:
`verification.json`, `database-comparison.json`, `backup-evidence.json`,
`source-applied.json` in `attempts.json`. Zasebna kopija je zunaj repozitorija
v ohranjenem imeniku `JivieLocalTest/20261018-mobile-two-user`.

## Pripravljeni Android paket

APK je
`build/qa/jivie-mobile-readiness-20261020/android/Jivie-Test-Android-cf97e2d.apk`,
105.705.802 B, SHA-256
`7fef105a9341b5ee6378a3d4e7004e6e0b0a028f24f077b73adbcdb79f15a72b`.
Podpis je preverjen in enak obstoječemu testnemu paketu. QA ID, ime,
različica 1.10.1 (31), secure preferences in prefix ostanejo isti.
To je debug paket za poznejši priklop razhroščevalnika.

Vseh sedem native knjižnic je bajtno enakih zadnjemu ohranjenemu debug
paketu, tudi sodium, sqlite3mc in Flutter. Štiri zaklenjene konfiguracije
odvisnosti so nespremenjene. Pregledane QA razlike obsegajo pet obstoječih
datotek za izolacijo/transport in en diagnostični pomočnik; stari poslovni
diagnostični ovitki niso preneseni.

Gradnja je uspela v drugem poskusu; prvi je bil prekinjen zaradi pregleda
diagnostike. Preverjanje podpisa je po začetni težavi z izbiro Jave uspelo
z že nameščenim Android Studio JBR, brez nove Jave ali SDK. Ozka analiza
QA Dart datotek je čista. Ni bilo ADB ukazov, namestitve ali zagona.

`android/HANDOFF.md` vsebuje predvideno namestitev z `install -r` po
ponovnem preverjanju točne naprave in podpisa. Pripravljeni
`android/capture-android-metadata.py` preveri, da podani PID pripada
točnemu QA paketu, nato največ 180 sekund bere samo njegove dovoljene
diagnostične vrstice. Skript je statično preverjen, fizični zajem še ni.

## Skupna diagnostika

Android paket in pripravljeni iOS izvor imata isti pregledani transport in pomočnik
`qa_mobile_network_trace.dart`, SHA-256
`8a156ddac221e13bea6aa8d713c24dd2aad4765c0f25807281ef8c19ff34fcb6`.
Izpis dovoljuje 282 fiksnih metod in 16 fiksnih kod; nepoznane vrednosti
postanejo `other`. Zabeleži le status, trajanje in število prejetih bajtov.
V posameznem 180-sekundnem oknu je dovoljenih največ 512 dogodkov in ena
oznaka preseženega proračuna. Naslednje okno se obnovi, zato diagnostika
ni trajno porabljena že pred uporabnikovim dejanjem. Zunanja zajema sta
časovno omejena in zavržeta vse surove vrstice.

Glavni in neodvisni pregled TLS/diagnostike sta uspešna. Pomočnik je samo
v izoliranih testnih gradnjah; glavni izvor in produkcijska koda ostaneta
nespremenjena. Konzola, prvi dejanski telefonski zagon in razhroščevanje
še niso potrjeni. Android debug podpira poznejši Dart debugger. Za pripravljeni
iOS AOT kandidat sta predvidena native konzola in simboli, ne Dart VM
priklop. Uspešna gradnja ne dokazuje dejanskega priklopa konzole.

## Zgodovina: iOS blokiran po prvih treh poskusih

Pripravljen je izolirani izvor za isti QA bundle ID, service in Keychain
skupino. Obstoječi razvojni podpisnik je veljaven, profil vključuje
ohranjeni iPhone 11 in velja do 18. oktobra 2027. Zaklenjena offline priprava,
ozka Dart analiza in konfiguracijski korak so uspeli. Naprava ni bila
poizvedovana, nameščena ali zagnana.

Trije poskusi native arhiva so odpovedali pred prevajanjem:

1. Globalna ročna nastavitev profila je vsilila profil aplikacije tudi
   knjižnicam, ki profila ne podpirajo.
2. Po premiku profila v Runner je globalna točna podpisna identiteta še
   vedno povzročila konflikt pri samodejno podpisanih odvisnostih.
3. Po odstranitvi globalne identitete je v Runner konfiguracijah ostala
   podvojena nastavitev: za dodanim `CODE_SIGN_STYLE = Manual` je še vedno
   `CODE_SIGN_STYLE = Automatic`. Slednja prepiše prvo.

To je bila napaka naše priprave QA projekta, ne ugotovljena napaka aplikacije,
računa Apple ali telefona. Po tretjem poskusu je bilo delo ustavljeno brez
novega podpisanega paketa. Stari nameščeni testni paket in njegovo stanje
sta ostala nedotaknjena.

Takrat dokumentiran predlog je bila zamenjava obstoječe nastavitve samo v
treh Runner konfiguracijah, brez dodajanja podvojenih ključev ali globalnega
profila za knjižnice. Pred morebitno naslednjo gradnjo je treba statično
preveriti eno učinkovito nastavitev v vsaki konfiguraciji. V prvem naročilu
četrta gradnja ni bila izvedena. Nadaljevanje spodaj sledi šele novemu
izrecnemu uporabnikovemu naročilu; testni računi in stanje ostanejo isti.

Zgodovinski dokazi: `ios/native-attempts.json`,
`ios/LATER_SESSION.md` in dnevniki vseh treh arhivov v istem imeniku
priprave. Prvotni `readiness-evidence.json` je shranjen tudi kot
`ios/signing-fix-20261020/previous-readiness-evidence.json`.

## iOS popravek po novem naročilu: paket pripravljen

Uporabnik je izrecno naročil: »Implementiraj popravek. Ce ga ne mores sam,
me pocakaj da pridem domou.« Popravek je izveden brez posega uporabnika,
naprave ali računa Apple.

Najprej so odstranjeni trije podvojeni ključi. Statični pregled in dejanski
`xcodebuild -showBuildSettings` potrdita eno nastavitev v vsaki od treh
Runner konfiguracij ter odsotnost vsiljenega profila pri 43 odvisnostih.
Prvi arhiv po novem naročilu nato razkrije dodatni vzrok: obstoječi profil
upravlja Xcode, zato ni združljiv z ročnim načinom.

Končni popravek ima v Runner konfiguracijah eno `CODE_SIGN_STYLE = Automatic`
in splošno `Apple Development`, brez izrecnega UUID profila ali certifikata.
Knjižnicam se nastavitve ne vsiljujejo. Tudi ta popravek je pred gradnjo
pregledan statično, z učinkovitimi nastavitvami in neodvisnim pregledom.
Ukaz za arhiv nima globalnih podpisnih nastavitev, `allowProvisioningUpdates`,
registracije naprav ali cilja fizične naprave.

**Drugi arhiv po novem naročilu uspe.** Xcode uporabi isti že obstoječi
lokalni profil `50458f86-da56-4cef-81e7-873a8fecef4f` in isti podpisni
certifikat. Ni ustvarjanja novih profilov, novih podpisnih pravic ali
spremembe Apple računa. Zgodovina prvih treh napak ter novega neuspelega
ročnega poskusa je ohranjena; po uspešnem arhivu ni nove gradnje.

Paket je v
`build/qa/jivie-mobile-readiness-20261020/ios/signing-fix-20261020/automatic-existing-profile/Jivie-Test-iOS-current-development.ipa`,
16.460.353 B, SHA-256
`51a42425076cad618fb96aaf8e1f71facd5b100eac72e2b372468d1216e62651`.
V istem imeniku je preverjeni arhiv z `Runner.app`.

Preverjeni so strict/deep podpis, dejanski profil z vključenim iPhonom 11,
testni bundle ID, ime Jivie Test, različica 1.10.1 (31), service in izključna
testna Keychain skupina. Ni produkcijskih URL shem, Firebase konfiguracije
ali APNs entitlements. Razvojni podpis ostane namenjen testni namestitvi.

sqlite3mc je po odstranitvi podpisa bajtno enak prejšnjemu kandidatu.
sodium ni bajtno enak: razlikuje se 16-bajtni `LC_UUID`, pri podpisanem
izdelku tudi podpisni blok. Vseh 14 sekcij kode/podatkov in izvozov se ujema;
to sta neodvisno potrdila dva pregleda. Knjižnica ni bila zamenjana ali
popravljena. SDK, zaklenjene odvisnosti in 1.760 vhodov izoliranega izvora
ostanejo vezani na manifest; glavni zamrznjeni izvor je nespremenjen.

`artifact-evidence.json`, `readiness-evidence.json`, dokazi nastavitev,
native primerjava in dnevnik uspešnega arhiva so v istem imeniku.
Vrhnja `ios/HANDOFF.md` in priprava konzole kažeta na novi preverjeni
paket. **Namestitev, zagon, telefonski scenariji in dejanski priklop konzole
niso izvedeni.** Android, testni strežnik in produkcija v tem nadaljevanju
niso spremenjeni.
