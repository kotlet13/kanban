# E2EE: trenutno izvedeni izvor in zaključna vrata

18. oktober 2026. Pozneje naročena izvorna nadgradnja nad
[prvotnim načrtom P0–P8](E2EE_UPGRADE_PLAN.md). Dokument opisuje delovni
izvor, **ne** namestitve, izdane aplikacije ali končno zaključenega preverjanja.
[Protokol](E2EE_PROTOCOL.md) opisuje dejanske meje zaupanja;
[zemljevid](E2EE_CODE_MAP.md) vodi do trenutnih vstopnih točk.

**19. oktober — nov dogovor za deljenje:**
[poenostavitev prvega stika](E2EE_SHARING_SIMPLIFICATION.md) nadomesti
obvezno ročno primerjanje kartic z zaupanjem imeniku izbranega gostovanja,
preverjanjem podpisov in varno zapomnjenim korenom. Neodvisna primerjava
ostane izbirna. Stare spodnje navedbe o obveznem prvem ročnem preverjanju
opisujejo prejšnji model; podatkovni, obnovitveni in izdajni pogoji ostanejo.

Prejšnji opis samo V1 temeljev je zastarel: delovni izvor zdaj vsebuje
podpisane računske dnevnike, V2 poslovne adapterje, Capture3 in atomski commit3.
Obstoječa dovoljenja za izvor/končni commit ne dovoljujejo strežniške
namestitve, nove native gradnje ali trgovinske oddaje. Že oddani Android/iOS31
te kode ne vsebujeta. Zadnji zgodovinski gostovalni dokaz ostaja
FamilyHub0.15.0/schema19; lokalna dodajalna crypto shema ni dokaz živega stanja.

## Izvedba po prvotnih fazah

| Faza | Trenutni izvor | Zaključna meja |
| --- | --- | --- |
| P0 protokol | Namenski strogi kodeki, libsodium, ločene authority/candidate meje, notranji pregledi in sintetični dokazi | **Neodvisni pregled celotne sestave ni opravljen.** Testni PASS ga ne nadomesti; pred živo aktivacijo ostaja obvezen. |
| P1 lokalna namestitev | Native sqlite3mc, varna hramba naključnega ključa, dosleden posnetek, primerjava kandidata, trajni restart/checkpointi in bootstrap pred porabniki baze | Fizična nadgradnja/backup/transfer, izdani native runtime in platformni P8 dokazi še čakajo. Web nima iste native meje zaščite. |
| P2 račun/datoteka | Lokalno ustvarjanje in ponovno preverjanje FILE, ločeni account/device ključi, podpisani directory, recovery/rebind, identity primerjava in monotoni floors | Datoteka ne predstavlja podatkovne kopije. Prijava ali reset gesla ne odklene E2EE; delno obnovljeni podatki ne pomenijo celotne obnove. |
| P3 skupna vsebina | Scope glave/epohe/aktivacije, CONTENT/FINANCE granti, closures, per-record proofs in opaque batch commitments, zgodovinsko/checkpoint preverjanje, dejanski router | Običajni provider/coordinator uporablja v2/Capture3 pod izrecnim preview varovalom. Staged genesis ni običajna authority. Zgodovinski PHP165 ne pomeni165 na najnovejšem izvoru; prizadeti invitation in generation zbirki sta naknadno PASS na treh pogonih. Zahtevane HTTP poti so potrjene z vezanimi teki/nadaljevanji; celotni Flutter66 je razkril regresije, prizadeti popravki69/70 in končna analiza so potrjeni v tabeli spodaj. |
| P4 deljenje/dokumenti/obvestila | Strukturni/access/lifecycle adapterji, invitations4 in retained native bridge, dokumenti/preglednice/Ideas, reviewed moderation, generic scheduling/delivery ter signed deletion/relocation poti | Inline31, retained36b/38/39/40/41 in relokacija43–46 imajo potrjene dokaze. B finalizacija, sveža FILE obnova9 zapisov ter običajna priponka/bajti/transport/vrste so potrjeni v61/62. Kanonični64 preveri veljavna migrirana pending/delivered opomnika; isti shranjeni rep65 potrdi izrecni popravljeni umik, sprejeti lostACK in nespremenjeno ponovitev. Ni nov celotni tek. |
| P5 finance | Finance4 model/validacija, linked payments/cash/catch-up, audit, sanirane choices, task-cost derivacija in topology/contributor popolnost | PASS zahtevane združene poti47→61: split-role migracija in sveža FILE obnova, isti prvotni READ grant, obnovitveni pregled/rotacija starša, parent popolnost pred/po izbrisu, nespremenjeni raw podatki, zadnja odstranjena povezava ter isti lostACK/request bajti z novim zaporedjem/tombstone. Gre za migracijo47 in nadaljevanja istega stanja, ne nov celotni tek. |
| P6 prehod | Javni trajni coordinator, Capture3 celoten source/file inventar, blind bindings, FILE cold poslovno preverjanje, pet controls, domain certificates, scoped activations in atomski commit3 | Združeni47 in isti rep61 sta zaključena. A supersession in hladni arhiv50 so potrjeni; B61 finalizacija z izrecnim povezanim retry/isti lostACK in ohranjeno prvotno zavrnitvijo je potrjena. Veljavni migrirani seznam64 in isti shranjeni umik65 sta potrjena; neznani/private potrebni prispevki ostajajo nepopolni. |
| P7 obnova/uporabniški tok | Account/installation FILE ločitev, blank encrypted SQL rekonstrukcija, karantena lastnih starih namer, scopes discovery/classification, protection completion z durable pause/cancel | Združeni47 je potrdil popolno svežo FILE/blankSQL obnovo in ohranil zasebne kontrolne točke; izgubljeno stanje30 ni več razlog za ponavljanje migracije. Retained36b/38/39/40/41 potrjuje admission, obnovo, izrecni pregled/rotacijo in isti prvotni zapis. Affected-fence account deletion ostaja pošteno blokiran. |
| P8 izdaja | Izvorne native/backup omejitve in predpogoji zapisani | Fizične naprave, prava gostovalna kopija/obnova, neodvisni pregled in ločeno izrecno izdajno dovoljenje ostajajo odprti. |

Tabela loči obstoj implementacije od dokaza končnega uporabniškega toka.
Namenska pending izjema zaradi manjkajočega dokaza ni uspešno dokončana
nadgradnja in se tako tudi ne sme prikazati.

Trenutne rezultate in preostale meje povzema razdelek
[Dokazi in končno preverjanje](#dokazi-in-končno-preverjanje). Teki imajo svoje
source manifeste; vmesnih delnih dokazov ne seštevamo v nov skupni PASS.

## Lokalna zaščita in uporabnikove datoteke

`LocalVaultBootstrap` pripravi eno šifrirano namestitev pred repozitoriji,
preference replayem, syncom in background koordinatorji. Napačen/manjkajoč ključ,
poškodba, pomanjkanje prostora ali novejši format ohranijo izvirnik in ponudijo
nadaljevanje/obnovo; ne ustvarijo prazne baze ali plaintext fallbacka.
Ohranijo se vse particije, Hive izvirniki, osnutki, BLOB-i, nepoznana polja,
stare zahteve, zaporedja in FK povezave.

Namestitveni ključ in računska obnovitvena datoteka sta ločena. Lokalna uporaba
ne zahteva računa ali omrežja. Računska FILE je vezana na server/account,
brez installation ključa, sej ali podatkovnega posnetka. Uporabnik jo shrani
in ponovno izbere za preverjanje; po želji jo sam deli s sistemskim orodjem.
**Jivie SMTP je ne pošilja.** Varnostni mail vsebuje samo generično dovoljeno
vrsto dogodka. Izguba datoteke in vseh potrjenih naprav se ne rešuje z geslom.

`LegacyPickerCacheArchive` varuje pozitivno prepoznane aplikacijske izvirnike,
neznanih ali prevelikih datotek pa ne izbriše. Reachable ločen installation-wide
izvoz zahteva izrecno izbiro obsega; sam dokaz, da je datoteka app-owned, ni
dokaz pripadnosti trenutnemu računu. Navadna account/space kopija zato ne
vključuje samodejno drugih particij ali neidentificiranih izvozov.

Prenosna kopija9 ohrani stare formate in particijsko omejeno private evidence,
drafte ter nespremenljive operacije v karanteni. Uvoz ne da novih strežniških
pravic in ne aktivira starih neposlanih zahtev. Dedup dvojno hranjenih upload
bajtov zahteva točen decrypt/hash/length/job dokaz; ob neuspehu ohrani izvirnik.
Optimizacija lahko zahteva svež READ: brez nje lahko velika offline kopija
preseže skupno omejitev. Ni trditve o vedno uspešnem poljubno velikem offline
izvozu ali konstantnem pomnilniku. Polna directory ancestry se ohranja in
lahko raste; velike naprave ostajajo predmet P8 fizične potrditve.

## Dejanski poslovni priklopi

`CryptoBusinessRouter.configurePayloads` sestavi dokumente, finance/payments,
zgodovino, skupinske dokaze in poslovne validatorje. `SessionCryptoAccess`
preveri trenutni račun, domeno, glavo/lifecycle, zgodovinska sidra in namen
pred uporabo ključev. Označeni migration/inline/relocation proof ne sme
postati navaden WRITE zaradi manjkajoče provenance. Kratko bralno okno se po
petih sekundah obnovi z novim preverjanjem, ne s podaljšanjem starega zaupanja.

History-only preimage dopolnjuje exact batch dokaz, ne trenutnega salda ali
projekcije. Velika raw vsebina in dokumenti se odprejo iz preverjenega šifriranega
manifesta. Audit vključuje trenutno revizijo in nato preverjene prednike;
imported physical1 baseline ne podvoji prvotne legacy revizije. Unknown JSON
vrednosti, originalni časovni nizi in before/after ostanejo ohranjeni.

FinanceAccountChoice ostaja en saniran izbor brez parent salda in brez kopije
denarnice: source READ podpiše celotno izbiro, target manager odobri isti hash,
target FINANCE WRITE materializira običajni lokalni manifest. Split-role
Capture3 varianta ne zahteva, da eden od njiju prejme zasebni arhiv drugega.
Obstoječi `.structure.context/.contexts` variant
`financeAccountChoicesRequest` dostavi minimalni target context/blind binding,
ne zasebnega parent/child arhiva ali nove authority. Issuerjev FILE selector,
obstoječi offer/certificate, target manager delegation in recipient raw7 vodijo
v final role/hash-bound companion. Split-role tok je potrjen z migracijo47 in vezanimi nadaljevanji do61;
same-account helper sam tega ne bi dokazal.

Native stara povabila/mail imajo exact captured bridge, status, ID, token in
rok brez novega pošiljanja med prehodom. Recipient dobi scoped final activation
in opaque inclusion dokaze, nato običajen svež invitations4 sprejem/admission;
stari token ne daje DEK. Restart že porabljenega email povabila preveri originalni
podpisani sprejem, overjen z lastno preverjeno verigo, tudi če je prvotna capsule imela
recipient.accountId=null. Numerični Kanboard project invitations niso native
scope povabila in ostanejo nedotaknjeni.

Izbris računa policy4 je dosegljiv pred FILE gate z obstoječim password/OTP in
trajnim receipt tokom. Tombstone trajno zapre auth/recovery/device/nov recipient
vpis, ohrani pa nujne tuje podpisane dokaze in pošteno razkrije retention.
Preostali člani opravijo pravi scope transition; noben strežniški izbris ne
ponaredi njihovega podpisa ali DEK. Prizadeti **nedokončani fence trenutno
pomeni `canDelete=false`**, ne izmišljenega readable snapshot uspeha.

Scope/inline deletion uporablja preverjeni omejeni graf, sveže pravice za vsak
prizadeti scope/domeno, purpose-tagged dokaze, final publication in atomski CAS.
Potrebni parent topology successor se zapiše v isti final transakciji.
Nevidni finance odvisnosti pomenijo generičen blocker, ne uhajanja ID-jev ali
samovoljnega cascade. Izbris aktivnih podatkov ne obljubi fizičnega izbrisa
vseh encrypted backups, shared dokazov ali zajetih legacy virov.

## Obnova brez starega lokalnega stanja

Lastna preverjena directory lineage je authority za pričakovane operation
headers; SQL event index je samo pospešek. Scope catalog je omejeno discovery
orodje, ne dokaz, da ni skritih ali izpuščenih prostorov. Own signed attestations
se razvrstijo z exact originalnim proofom; missing/ambiguous/unknown dokaz
ostane izrecno incomplete. Private local-intent artefakt se odpre po originalnem
FILE-rooted dogodku in vrne v karanteno, ne v živo vrsto.

Računski ključi so lahko pripravljeni, medtem ko so posamezni stari/odvzeti/
izbrisani prostori še nedosegljivi. UI dovoli uporabo preverjeno obnovljenih
obsegov z jasnim opozorilom; ne napiše »celotna obnova končana« zaradi praznega
strežniškega seznama. Trdna signed terminal evidence lahko pojasni zaprtje;
unsigned403 ne izbriše pričakovanega sidra.

`AccountProtectionReady` hrani exact active job/request in retry deadline.
Later prekine čakanje in ne podpiše nove rotacije; exact DialogRoute se zapre
brez popa spodnje strani. Lastnik lahko samodejno opravi obstoječi recovery
prehod le z že preverjeno zgodovino; neopažen rep zahteva obstoječi review.
Shared manager/nonmanager dobi izrecno potrebno dejanje, ne dodatnih pravic.
Izgubljen protection ACK se poravna po originalnem signed requestu.

## Dokazi in končno preverjanje

Dokazi so v `build/qa/e2ee-source-upgrade`, vsak z dejanskim source manifestom
in dnevnikom. Drift med tekom izniči ta tek; poznejši konkreten popravek zahteva
novo revizijo in ponovitev prizadetega preverjanja, ne vseh že uspešnih zbirk.

| Dokaz | Potrjeni rezultat | Preostala meja |
| --- | --- | --- |
| Zgodovinski PHP `final-matrix/aggregate-165-pairs.json` | 55 zbirk na SQLite, MariaDB in MySQL PASS;165 unikatnih parov na tam vezanih izvornih posnetkih. | Dokaz je nastal pred poznejšim produkcijskim popravkom običajnega porabljenega povabila. Ni trditve165 na najnovejšem izvoru; prekrivajočih assertov ne seštevamo, vektorji niso neodvisen SQL dokaz. |
| Poznejši invitation popravek | Prizadeta obstoječa `crypto2-invitation-integration.php` je PASS na SQLite/MariaDB/MySQL; lastni source/log hashi so v `normal-consumed-invitation49-proposal/targeted-three-drivers/summary.json`. | Poznejša proizvodna sprememba ni vključena v zgodovinski165 izvor. Prizadetih ponovitev ne prištevamo kot novih unikatnih parov ali celotnega final-source165. |
| Bralni del29 | Običajni router po shranjeni FILE obnovi preveri vsebino/finance, prvotni audit31, celotno priponko, Idea bajte in hashe. | Zgodovinski ločeni bralni del, ne dokaz zadnje odstranitve povezave. |
| Inline31 | Celoten obstoječi >32 izbris projekta, final publication, lostACK ter scoped-proof/current-read zavrnitve PASS. | Ni splošne trditve fizičnega izbrisa kopij. |
| Retained36b/38/39/40/41 | Povabilo/admission, restart, sveža lastnikova FILE obnova, izrecni pregled/rotacija, preklic čakanja in exact lostACK ter prvotni blokirani zapis z istimi bajti/request ID so pokriti. | PASS nadaljevanj istega ohranjenega stanja, **ne nov celotni tek**. Same-root, največ128 glav/16MiB v zasebni descriptor poti brez policy proof ter izrecni pregled ostajajo omejitve. |
| Relokacija43–46 | PASS nadaljevanj istega stanja: >32 graf/atomski commit/exact lostACK, revizija21/vseh21 audit vnosov/raw float, blob/topologija, target-only admission, izrecni pregled/potrditev, FILE40 CONTENT/3 FINANCE ter prejemnik40 verified/complete1 s checkpointom pri potrjeni glavi3. Prvotna blokirana zahteva ostane nespremenjena; brez podatkov starša. | Ni nov celotni tek ali performance PASS. Kanonični HTTP test je bil nato usklajen z dokazano pregledno potjo, zasebnimi trajnimi mejnimi stanji in30-minutnim opt-in rokom; brez novega svežega migracijskega začetka. |
| Združeni47: migracija in FILE | Celoten migracijski prehod s35 dodatnimi zapisi, split-role FILE/journal,44 staged zapisi,4 structure contexts,5 prispevki,4 certifikati,2 aktivaciji, commit3/isti lostACK in popolna sveža FILE/blankSQL obnova. Zasebna stanja so ohranjena. | Migracijski začetek ni ponovljen. Poslovne zaključne trditve je dopolnilo isto ohranjeno stanje v61; ni novega svežega celotnega teka. |
| Združeni47→61: isti poslovni rep | Zahtevane trditve so PASS: natančen descriptor, parent popolnost pred/po izbrisu, raw nespremenjen, zadnja odstranjena povezava, isti lostACK/request bajti in ustrezno novo zaporedje/tombstone.61: en omogočen test PASS, brez preskokov,4,514s. Vmesne ustavitve48/49/51/52/53 in kasnejša nadaljevanja so ohranjeni ločeni dokazi. | To je zaključek istega stanja47, ne nov celotni tek. Zadnji source61:1485 datotek, aggregate2aca1d899a50b38d0755e85bdb6995197e8283b14fef660e3ec984c29a301043. Točne source/log/harness/stanje vezave so v public-combined-continuation-evidence.json. |
| Generacija A in hladni arhiv50 | A supersession/adoption in isti lostACK so potrjeni.50 FILE hladno preverjanje petih kontrol, verify3, notification cert, domenske objave in scoped aktivacija so potrjeni. | To so ločene potrjene meje istega ohranjenega scenarija, ne nov celotni tek. |
| Generation prizadeta PHP zbirka | `crypto-migration-generation-prefix-v3.php` je PASS na SQLite/MariaDB/MySQL, vezano v `use3-generation-member-parity/three-driver/summary.json`. | Ločen dokaz prizadetih sprememb po zgodovinski matriki; brez trditve celotne165 matrike na najnovejšem produkcijskem PHP. |
| B61 finalizacija in sveža FILE | B je committed po izrecnem povezanem retry in uskladitvi izgubljenega ACK; prvotni zavrnjeni receipt ostane ohranjen. Sveža FILE obnova preveri9 zapisov brez karantene ter enakost task/expense payloadov. | Ni novega migracijskega začetka; poznejši kontrolni bralni rep še ni celotni use3 PASS. Ne trdimo nepodprte audit trditve brez fixture podatkov. |
| Hladni rep62 in kanonični64 | Celotni bajti/hash priponke, običajni blob transport brez migration blob read, zahtevane vrste in odsotnost karantene so PASS.64 dodatno potrdi A/B, svežo FILE9/priponko ter seznam veljavnih migriranih pending/delivered opomnikov. |62 je ustavil nepopoln kontrolni dokaz;63 je pravilno zavrnil neveljaven sintetični odmik10.64 uporablja prvotni veljavni odmik60 (rok−3600), ne na novo ustvarjenega običajnega opomnika.64 se po123,646s ustavi pred umikom, ker test ni poslal expectedRevision; produkcijski UI ga pošlje. Isti shranjeni rep65 je PASS1/brez preskokov/4,092s: izrecni novi popravljeni umik z lastnim dogodkom/istim novim ID, sprejeti lostACK in ista ponovitev, revision+1, delivered nespremenjen, brez target-read ali novega reminder put. Prvotna dokončno zavrnjena422 zahteva/bajti/hash/receipt ostane nespremenjena. Zahtevane use3 trditve so zaključene kot64→65, ne nov celotni tek. |
| Prihodnji PHP runner | Privzeti katalog zdaj vsebuje56 zbirk, tudi že ločeno preverjeni crypto-migration-generation-prefix-v3.php. | Dodatek za prihodnje regresije ne spreminja zgodovinskega55×3 dokaza in ne pomeni izvedenega56×3 ali celotnega final-source165. |
| Celotni Flutter66 | Dejanski enkratni celotni tek:1924 PASS,46 preskokov in71 FAIL. Analiza:0 errors,26 warnings,512 infos. | To ni celotni PASS. Odstranjena so bila vsa sintetična stikala JIVIE_*; nespremenjene uspešne trditve se ohranijo brez novega splošnega teka. |
| Prizadeti popravki67–69 |67 je bil ustavljen zaradi blokade testnega helperja, zato ni PASS.68: samo prvi sender320 PASS1/brez preskokov.69: prizadeti nabor244 PASS/0 preskokov/13 FAIL; analiza0 errors/0 warnings/510 infos. | Popravki sintetičnih fixture pogodb ter izolirane memory baze/seje ne izklopijo produkcijskih E2EE varoval. Prekrivajočih rezultatov ne seštevamo. Infos niso vsi stari glede na uporabnikovo izhodišče. |
| Preostali prizadeti nabor70 | Sedem prizadetih datotek:94 PASS/0 preskokov/0 FAIL,29,77s. Analiza z `--no-fatal-infos`:0 errors/0 warnings/510 infos; iste issue keys kot69. | Prizadeti PASS zaključi13 preostalih primerov po69; ni nov sveži celotni tek na istem izvoru. |

Zgodovinski PHP aggregate SHA256 je
`3a218f95fbb5c3a0a0f0794eecbdc8d79d8d519ea95506652f5ec1670437d525`;
poznejši targeted invitation summary je
`23780bc4294bcf092ed24ac279906ae8153c9d48b98b06007fae875ffe745cb6`;
generation targeted summary pa
`6e193def2199e7a220834e17e3da6305a5a9d4a9149f1ce2cd11f61bf86b2ccc`.
Retained dokaz je `retained-invitation-recovery-continuation-evidence.json`,
SHA256 `8ee5fff33e8234959c7c24418545fa386cb47ce9561be3bbb5821749b5f32e0c`;
relokacijski `project-relocation-continuation-evidence.json` je
`8edfe5a30f0ad5c0b0550107de47b2e191a2a30789d05986c7a1fd5e2cabd8b6`.
Novejše točne source/log/stanje vezave vodijo
`shared-freeze-47-public-combined-safe-evidence.json`,
`shared-freeze-{48,49,51,52,53}-combined-tail-safe-evidence.json` ter
`public-combined-continuation-evidence.json` s SHA256
`63111984dbd31fb8b264f4c52a66b136ce1104558e51e715011e9f4a58620184`,
`shared-freeze-50-use3-archive-safe-evidence.json` in
`shared-freeze-52-Bprepare-use3-safe-evidence.json` kot zgodovinska meja.
B61 in hladni rep62 vežeta `use3-B56-finalization-tail/runtime-safe-evidence.json`
(SHA256 `a9e5aedfd10ec36dceb99645aa46372e6265fbde4b068b24eedfe8705c6b83a2`)
in `use3-cold007-tail/runtime-safe-evidence.json`
(`d2aa1dc77a7bd4100a6b977af3f4c1ed1cb95eae126dee2aa9a3c6e796dbaad2`).
Njihove takratne delne meje niso samostojen celotni use3 PASS.64 potrdi veljavni migrirani seznam; use3-valid-offset/runtime-safe-evidence.json (SHA256 ddfa01c1669526641e3fd436c880acfc207acbf936c9bc9a3078a12c1bd28fa8) veže source64 s1485 datotekami/aggregate3e672ce9fe9479e939e18e1fdf5217f792a6be9ed0e6716e34ee3d3ecf04fa2d. Njegov umik je bil dokončno zavrnjen422 zaradi manjkajočega testnega expectedRevision;65 mora ohraniti prvotne zavrnjene bajte/receipt, uporabiti izrecno nov popravljen zahtevek in šele njegov sprejeti lostACK ponoviti nespremenjeno. 65 je zahtevo dejansko zaključil; use3-withdrawal64-tail/runtime-safe-evidence.json (SHA256 cc2ffb1d18511db13c1472eb075b394c75c83f28b6d33d40bb1db5b71e051dae) veže64→65, source65 s1485 datotekami/aggregateb9d71ba3ed261bd20f1d02559d9633054282ae149ce69ae50cf523ec521a47f6 in nespremenjene source/harness/vhodne kontrolne točke. Brez ponovnega začetka migracije ali trditve novega svežega celotnega teka. Celotni Flutter66 in poznejši prizadeti nabori so razločeni v zgornji tabeli. Ni javnega1001-vrstičnega dokaza ali končnega release PASS.

Zaključno Flutter preverjanje je vezano na `final-flutter-66/failures-and-outcome.json`,
`final-flutter-67-affected/summary.json`, `final-flutter-68-sender-probe/summary.json`
in `final-flutter-69-affected/summary.json`. Končni70 je vezan z `final-flutter-70-affected/actual-outcome.json`, SHA256
`58eeec71857109252392716bf7d6c6df9c952c519518882daa6684600da3ae61`,
source70 aggregate
`8e1c77ef9057ff31ec598d948a1ae49899adfa15bec389a3a06b58e9fa3de1b2`.
Celotni66 in prizadete ponovitve imajo svoje source manifeste.69/70 zaključita
odkrite regresije; poročanih PASS ne seštevamo in ne trdimo novega celotnega
teka na zadnjem izvoru.70 je izrecno izvedel vseh sedem datotek brez name
filtra in brez preskokov; sočasni reporter ne izpiše vsakega uspešnega imena.
510 infos vključuje tudi nove slogovne opombe glede na izhodišče; analiza ni
brez opomb. P0 neodvisnega pregleda ti dokazi ne nadomestijo.

Obnovitvena pot za lifecycle/policy uporablja izključno vezani pripravljalni
ključ brez objave običajne avtoritete. Prejemnikov že podpisani poznani pin
lahko napreduje le po preverjeni isti verigi/korenu do točno vezanega headu;
ni splošne izjeme za zastarelo avtoriteto ali zaupanja uvoženemu SQL.
Popolnost zahteva nov podpisan checkpoint: po FILE spremembi naprav je
`complete=0` do pregleda/rotacije pravilen tudi ob40 preverjenih zapisih.

**Omejitev zmogljivosti:** prvi hladni/prejemnikov polni prenos lahko traja
več minut in tisoče RPC. Prva nadaljevalna pot45 je dosegla480-sekundni rok
s4.800 uspešnimi klici; kasnejše branje z že preverjenimi ohranjenimi dokazi
je zaključilo svoje trditve v5,746s, prejemnik46 pa v1,399s. To ne dokazuje
hitrega prvega prenosa in ne odpravlja opisane omejitve.

P0 neodvisni pregled ter fizični/native/hosting P8 ostajajo odprti tudi po
sintetičnem PASS. Pred poznejšo namestitvijo so potrebni prava ločena kopija in
dejanska obnova vsakega gostovanja, usklajena koda/shema/PHP `ext-sodium` ter
izrecno preview varovalo. Fizična native nadgradnja, zaklep/izguba varne shrambe,
OS backup/restore in platformni dokaz niso nadomeščeni z lokalnim AOT/testom.
Nova native crypto odvisnost zahteva ponovni pregled Apple encryption izjave
pred prihodnjo iOS gradnjo/oddajo; zdaj ni plist/portal spremembe, gradnje ali
trgovinske oddaje. Ne nastajajo resnična povabila, SMTP ali FCM dostave; fixture
poverilnice ostanejo zasebno zunaj Gita.

## Hramba in poznejša namestitev

Uporabnik je potrdil **30 dni po dokumentirani dejanski uspešni obnovi nove
šifrirane kopije**. To ni30 dni od šifriranja, nalaganja ali commit3. Za vsako
kopijo/gostovanje potrebujemo ločen čas uspešne obnove in checkpoint;
neuspešna/nepotrjena obnova zadrži cleanup.

Stari berljivi strežniški backupi in upravičeni predmigracijski viri se fizično
čistijo šele v naslednji skupni namestitvi. **V tem izvornem delu se nič ne
briše.** Do tedaj so lahko stare SQL/datoteke in kopije še berljive skrbniku.
Potrebni podpisani/šifrirani zgodovinski dokazi preostalih računov se ohranijo.
Ni obljube odstranitve uporabnikovih lastnih zunanjih izvozov ali drugih kopij
ključev. Izvoz, kopija, prava obnova in produkcijski cleanup so ločena dejanja.
