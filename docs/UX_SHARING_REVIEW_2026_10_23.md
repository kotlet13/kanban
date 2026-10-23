# Deljenje med dvema aktualnima Mac instancama

23. oktober 2026. Uporabnik je naročil raziskovalni pregled deljenja, odvečnih klikov in poti iz projekta do njegovega članstva. Glavni agent upravlja GUI; GPT 6.1 Sol/high podagenta preverita aktualnost okolja, izvorne poti in pasivne strežniške dokaze. V tej nalogi ni sprememb programske logike. Telefoni in produkcija niso vključeni.

## Okolje in meje

- Share A uporablja r16, Share B je pred pregledom enkrat zgrajen in posodobljen iz r13 v r17. Obe vsebujeta aktualno logiko commita `1bbc4fdd5564e6f5ebd1aa4c5516b824d51dfd68` in ločeni obstoječi QA identiteti. B ima 588 pripetih izvornih vhodov in osem identitetnih/TLS prilagoditev; stara diagnostična koda je odstranjena.
- AOT A: `97c91a9affeb9ab9ab8019550a7b30aba3cde466f9e584aed6f9fbcf98dbde3f`; AOT B: `f393f6b6cb703c1019804b98b5d73a5ee058f5d4faacecf2ba33e08e21af261a`. B artifact manifest: `df776982704af67eac572f49f03f13b2e54a43f62b86862ba847d4d03fb4f02b`. Analiza B: 0 errors/warnings, 95 obstoječih info.
- Isti lokalni Docker strežnik `https://127.0.0.1:18811/`; programska oprema strežnika ni spremenjena. SMTP je vezan na lokalni Mailpit brez posredovanja navzven. Uporabljeno je povabilo obstoječemu sintetičnemu uporabniškemu imenu, brez zunanjega e-poštnega sporočila.
- Oba računa sta ostala prijavljena. Podpis, Keychain nastavitve, QA CA in identiteta B vsebnika so ohranjeni. Bajtna enakost vault datotek ni preverjena zaradi TCC; obvoda ni bilo. Namestitev ne odstranjuje ali ponastavlja podatkov.
- Staro B-jevo odvzeto članstvo, čakajoči osnutek in blokirana sprememba ostanejo. Starih povabil, odvzemov, obnov, finance CRUD ali že uspešnih kontrol nismo ponavljali. Novo deljenje uporablja **UX26 Projekt A – deljenje**, ustvarjen pod obstoječo testno organizacijo. Nova vsebina je samo **UX26 deljenje – dokaz A v B**.

## Dejanski izidi GUI

| Novi korak | Izid | Opomba |
| --- | --- | --- |
| Ustvari projekt pod organizacijo | PASS, prvi poskus | Potrditveni dialog ponudi »Open project« in »Members« |
| Open project | Odpre seznam z edinim projektom | Potreben še klik kartice do podrobnosti |
| Podrobnosti → … → Edit project → Members | FAIL, en poskus | Prazni projekt dobi opozorilo o zunanjih finančnih/drugih povezavah; ne odpre članstva |
| Space settings → Invite someone → Send | PASS, prvi poskus | Obrazec navede točen novi projekt in izrecno izključi članstvo v nadrejenem prostoru |
| B: Account → Join project → Join space | PASS, prvi poskus | Povabilo sprejeto, nato čakanje na lastnika; ni ročnega preverjanja identitetnih kartic |
| A: Refresh members → ključ → Confirm access | PASS, prvi poskus | Pregled pokaže isti projekt in ciljno uporabniško ime; članstvo aktivirano |
| B: Check access | PASS, prvi poskus | Odpre Utrip z imenom novega projekta; njegove nastavitve kažejo vlogo Member |
| A: novo opravilo v istem projektu | PASS | Shranjeno enkrat; oblaček ob 12:47 lokalno kaže Synced in 0/0/0 |
| B: prenos tega novega opravila | FAIL/STOP po enem ročnem syncu | Projekt ostane 0/0, brez opravila; ob 12:47 »Too many attempts« |

Povabilo, sprejem in odobritev so torej dejansko uspeli. **Celotnega prenosa nove vsebine med instancama ne označujemo PASS.** B-jev stari pending=1/blocked=1 je znano ohranjeno stanje; nova napaka je omejitev zahtevkov. Ne ponavljaj uspešnih faz povabila zaradi nadaljevanja tega podkoraka.

Pri A je prvi AX klik praznega »Add task« pustil zaslon nespremenjen; klik vidnega plusa je odprl obrazec. To je zabeležena interakcijska nejasnost, ne dokazana programska napaka gumba. Opravilo je shranjeno samo enkrat.

## Pot in število klikov

Štejemo navigacijske in potrditvene klike, brez vnosa besedila, osredotočenja polja, pomikanja, preklopa med aplikacijama in raziskovalnih obvozov. Začetek: A že gleda podrobnosti novega projekta, B je na drugem zaslonu računa/aplikacije.

| Dejanje | Kliki |
| --- | ---: |
| A: Space settings → Invite someone → Send | 3 |
| B: Account → Join project → Join space | 3 |
| A: Refresh members → ključ → Confirm access | 3 |
| B: Check access | 1 |
| **Skupaj izbrana delujoča pot** | **10** |

To ni dokaz globalno najkrajše poti: zgornja ikona za deljenje lahko skrajša dostop do obrazca, vendar v tej novi uspešni poti ni bila uporabljena. B je imel Account odprt že pred povabilom; v izvedenem pregledu je bil potreben še odhod na Utrip in vrnitev, da se je kartica pojavila. Minimalni prikazani seštevek predpostavi običajno prvo odprtje Account po prispetju povabila. Dejanski odhod/vrnitev doda en navigacijski klik. Po ustvarjanju je »Open project → kartica projekta« dodaten potrjen vmesni korak.

**Ni utemeljeno vseh deset klikov razglasiti za odvečne.** Izbira prejemnika, pregled obsega in zavestna odobritev so smiselni. Očitno nepotrebna sta prisilno ročno osveževanje stanja čakanja in dodatna lista za že izbrani projekt. Dvojno poimenovanje pridružitve je mogoče poenostaviti z enim jasnim pregledom in enim potrditvenim gumbom.

## Ugotovitve po pomembnosti

### 1. Člani iz samega projekta ne delujejo zanesljivo

Pri novem praznem projektnem prostoru **… → Edit project → Members** po treh klikih prikaže »Share project only« in trdi, da projekt vsebuje zunanje povezave. To ni dokaz takih povezav: [collaboration_actions.dart](../lib/organizer/presentation/shared/collaboration_actions.dart:251) prikaže isto razlago že ob neusklajenem `projectRootId` in vrsti prostora, pred preverjanjem grafa.

Izvorni kandidat je jasen: [crypto_business_router.dart](../lib/organizer/data/e2ee/crypto_business_router.dart:763) pri svežem šifriranem prostoru ne doda `projectRootId`; ustvarjanje ločeno objavi korenski projekt. Neobstoječi podatek se v modelu bere kot null. **Točna vrednost v živi bazi ni prebrana**, zato null ostaja izvorno podprt vzrok, ne neposredni native podatek. Alternativni Space settings pravilno odpre člane istega projekta in je omogočil uspešno deljenje.

Predlog: neposreden viden **»Deljenje in člani«** v glavi projekta, z jasnim imenom ciljnega projekta. Popraviti identifikacijo korenskega projekta; ne obiti kriptografskih ali dostopnih preverjanj in ne uporabljati napačnega pojasnila o financah za splošno navigacijsko zavrnitev.

### 2. Osebe na seznamu izgubijo ime

A po odobritvi vidi B kot **Jivie / Jivie · Member**; B vidi A kot **Jivie / Jivie · Owner**. Enaka generična oznaka je tudi pri izbiri izvajalca opravila. Lastni profil je pravilen: Preizkus A oziroma Preizkus B. [members()](../lib/organizer/data/e2ee/crypto_business_router.dart:916) vzame preverjene account ID/vloge, oznake drugih pa samo iz lokalnega predpomnilnika članov; manjkajoče nadomesti z »Jivie«.

To ni dokaz dostopa napačne osebe, je pa resna ovira pri preverjanju in upravljanju članstva. Predlog: preverljivo povezano uporabniško ime oziroma ime; če ni na voljo, izrecno »Ime še ni pridobljeno« z razlikovalno oznako. Vseh ne poimenovati enako.

### 3. Prejemnik pred sprejemom ne vidi imena projekta

Kartica Account dvakrat napiše **Invitation to Encrypted space**, nato gumb **Join project** odpre pregled **Confirm access** brez imena projekta in z gumbom **Join space**. Backend preview namenoma nima dešifriranega naslova ([NativeCryptoInvitationV2.php](../server/plugins/FamilyHub/Model/NativeCryptoInvitationV2.php:233)); UI ga ne dopolni z zaščitenim naslovom, naslov kartice pa podvoji [SharingInvitationDetails](../lib/organizer/presentation/shared/sharing_invitation_details.dart:20).

Predlog: enoten pregled »Povabilo v projekt …«, jasno kdo vabi, cilj, vloga, obseg financ in gostitelj. Naslov je treba prenesti v zaščiteni vsebini povabila ali ga varno pridobiti v dovoljenem koraku; zaradi lepšega UI ga ne objaviti nešifriranega na strežniku. Dosledno uporabljati »projekt« za projektno povabilo.

### 4. Čakanje je skrito, osveževanje ročno

Po B-jevem sprejemu A-jev že odprti seznam ostane na prvotnem povabilu. **Refresh members** doda samo ikono ključa; podnaslov še vedno kaže Member in datum poteka, ne »Čaka tvojo potrditev«. Ikona je pod seznamom članov, v tem oknu zahteva pomik. B po uspehu A še vedno vidi čakanje, dokler ne klikne **Check access**. [sharing_members.dart](../lib/organizer/presentation/shared/sharing_members.dart:473) uporablja `pendingKeys` za ikono, ne jasen status.

Predlog: vidno stanje **»B je sprejel povabilo — potrdi dostop«**, opisni gumb in posodobitev ob vrnitvi v aplikacijo oziroma ta zaslon. Odobritve ne odstranjevati zgolj zaradi zmanjšanja števila klikov; njeno samodejno izvedbo bi bilo treba posebej varno načrtovati. Firebase za ta pregled ni potreben.

### 5. Projektni meniji in kontekst se podvajajo

- Meni kartice ima Edit project / Archive / Delete. Meni podrobnosti ponovi te možnosti in doda Attachments / Report content. Nobeden nima neposrednega članstva.
- Novo izbrani projekt ima seznam, ki vsebuje samega sebe; ime se ponovi v izbiri prostora, podnapisu seznama, kartici, naslovu in podnapisu podrobnosti. »Open project« ni neposreden prehod v podrobnosti.
- Pri lokalnem obstoječem projektu »Members« odpre pot objave kopije. V tem pregledu je ta pot preusmerila ozadje na Account, urejevalnik pa je ostal čez njega; šele Cancel razkrije Account. Nismo ustvarili kopije. Izvorne predpogoje glej [sharing_copy.dart](../lib/organizer/presentation/shared/sharing_copy.dart:23) in [organizer_shell.dart](../lib/organizer/presentation/organizer_shell.dart:631). Točen sproženi predpogoj ni native diagnosticiran.
- **Samo izvorna ugotovitev:** zgornji Share space uporablja izbrani prostor, ne nujno odprtega projekta znotraj gospodinjstva. Obrazec sicer pokaže dejanski cilj. To je nevarnost napačnega razumevanja obsega, ne dokaz napačno poslanih pravic v tej nalogi.

Predlog: enake skupne akcije v obeh menijih, neposredna povezava do članstva točno odprtega projekta in ločeno poimenovanje »Objavi deljeno kopijo« za lokalni projekt. V projektnem prostoru odpreti podrobnosti neposredno. Obhod prek urejanja naj ne bo glavna pot deljenja.

### 6. Tehnični števci delujejo kot uporabniška vsebina

Lastnikova odobritev za prazni projekt pokaže **Content: 2 / Finances: 1**. [scope_crypto_manager.dart](../lib/organizer/data/e2ee/scope_crypto_manager.dart:1020) šteje vse preverjene zapise, tudi strukturo, [crypto_invitation_page.dart](../lib/organizer/presentation/recovery/crypto_invitation_page.dart:187) pa jih prikaže kot obstoječo vsebino. Števili sta skladni z metapodatki, korenom projekta in manifestom finančnih izbir; točne tri žive vrste niso prebrane. Ne pomenita dveh opravil in ene transakcije.

Predlog: skriti interne števce ali prikazati samo dejansko uporabniško vsebino. Povzetek dovoljenj mora ostati jasen.

## Odprti prenos in diagnostika

B-jev en ročni sync novega opravila se je ustavil na »Too many attempts«. Prikaz opravila pri B ostaja nepreverjen. Nadaljevanje mora uporabiti isti projekt, isto opravilo in istega člana; brez novega povabila, odobritve ali vnosa. Ni drugega ali tretjega slepega poskusa.

Pasivni zajem je omejen na metapodatke obstoječega dnevnika od **10:38:42 do 10:48:59 UTC**, brez vsebin zahtevkov, ključev, gesel in dodatnih HTTP poizvedb bralnika. Skupaj **3.275 odgovorov: 3.269 × 200, 4 × 429, 1 × 403 in 1 × 499**. Zajem združuje promet obeh računov in vseh njunih prostorov; ne pripisujemo vseh zahtevkov novemu projektu ali enemu kliku.

| UTC | Dejanski HTTP 429 | crypto2 zahtevki v predhodnih 60 s |
| --- | --- | ---: |
| 10:46:23 | domain.inventory | 694 |
| 10:46:31 | account.scopeObservations | 602 |
| 10:47:07 | inbox.sync | 608 |
| 10:47:33 | authority.snapshot | 602 |

[NativeCryptoV2Service.php](../server/plugins/FamilyHub/Model/NativeCryptoV2Service.php:18) uveljavlja skupno omejitev **600 crypto2 zahtevkov / 60 s / IP** pred razdelitvijo operacij. Izid je močno skladen z izčrpanjem te skupne omejitve zaradi seštevka zahtevkov obeh instanc. Zgodovinsko stanje konkretnega števca ni neposredno prebrano; prikazana drseča okna imajo sekundno natančnost gateway zaključkov, ne točnih strežniških meja. Ločeni 403 `invitations.status` ob 10:44:44 in 499 brez operacije ob 10:48:34 sta ohranjena brez nedokazane vzročne razlage.

En read-only pregled potrdi **prejemek ob 10:46:57 UTC, records.batch / 200 / applied**, vezan na edino opravilo novega prostora in njegov derivation intent, oba revizije 1. Naslov/vsebina nista dešifrirana. To podpira A-jev uspeh; B-jevega prikaza ne dokazuje. HTTP 200 sam brez pomenskega prejemka ni bil uporabljen kot dokaz uspeha.

Povzetek brez identifikatorjev ali teles: `build/qa/local-diagnostics/sharing-ux-20261023/http-summary.json`. Zasebni original `final-passive-summary.json` ima SHA256 `6d7425981a66f02d5f494710e11413957920ba8a7b6caef2f7e694f469483983`; vezava prejemka `new-project-task-receipt-readonly.json` ima SHA256 `94293dccc43de4813c836e1616cb8fad99c55e9aefb0c1a37fe7bf5bc2cf7215`. To ni hitrostni benchmark. Omejitve ne zvišujemo kot nadomestilo za diagnozo izvora ponovljenih branj.

## Zaključek in ohranjeno stanje

Obe aplikaciji sta normalno zaprti prek Quit; namestitvi, računa, ključi, baze, nov projekt, članstvo in opravilo ostanejo za nadaljevanje. Iz istega `source-b` so po pregledu odstranjeni samo štirje obnovljivi build predpomnilniki, **1.664.419.659 B**. Končni paketi, stari r13 paket, izvori in dokazni manifesti so ohranjeni; nova polna izvorna kopija ni nastala.

Zasebni dokazi: `JivieLocalTest/share-20261019/candidate-b-r17/`, `source-b-r17-plan.json` in `sharing-ux-20261023-http/`. To poročilo je zapis neposrednih CUA opažanj in ločene izvorne analize; ni celotni varnostni pregled, mobilna potrditev ali dovoljenje za produkcijsko objavo.

Prednost nadaljnjega dela: **(1)** omejitev zahtevkov na istem novem prenosu, **(2)** pot do članov iz projekta in pravilna imena oseb, **(3)** enoten pregled povabila in jasno čakanje, **(4)** poenotenje menijev ter odprava podvojenih zaslonov. Popravki v tej raziskovalni nalogi še niso izvedeni.

Končni pregled: glavni agent preveri navedene izvorne veje in dokaze; neodvisna Sol6.1/high pregleda uporabniških poti ter okolja/HTTP poročata PASS brez ugotovitev. `git diff --check` uspešen. Pregled poročila ne vključuje novih poslovnih testov ali dodatnih strežniških poizvedb.

## Dodatek: trije popravki po pregledu, native nadaljevanje še čaka

23. oktober 2026. Po novem naročilu uporabnika so izvedeni spodnji popravki. Zgornji raziskovalni pregled, njegov **FAIL/STOP po prvem B-jevem ročnem syncu**, zgodovinski HTTP podatki in že uspešni koraki ostanejo nespremenjeni. Ta dodatek jih ne pretvarja v nove rezultate.

1. **Manj ponovljenih zahtevkov.** [CryptoAuthoritySnapshot](../lib/organizer/data/e2ee/crypto_authority_snapshot.dart) znotraj iste obstoječe preverjene operacije združi samo točne strani `account.scopeObservations` in `domain.inventory`: največ 64 vnosov oziroma 512 KiB, enaka prvotna časovna meja, preverjanje računa, pinov in življenjskega cikla, ločeni izvodi rezultatov ter brez shranjevanja napak. Zapis, neznana operacija ali podpisan ukaz konča ponovno uporabo; `pendingCapability` jo obide. [Obnova opažanj](../lib/organizer/data/e2ee/crypto_scope_observations.dart) pri dohitenem kazalcu najprej osveži podpisani lastni imenik in nato izpusti prazno stran spremljevalnih dokazov. Novi podpisani dogodek še vedno zahteva svoj dokaz; zamrznjeni bralnik ostane pri svoji točni predponi. Celotno preverjanje podpisanih glav in vključenih svežnjev ostane tudi ob izpuščeni zahtevi. Omejitev 600/60 s in varovala dostopa niso sproščena.
2. **Članstvo iz točnega projekta.** [Projekcija korena](../lib/organizer/data/e2ee/crypto_project_root_projection.dart) uporabi preverjeni projektni opis in eno aktivno lokalno projekcijo; drugačen korenski UUID zahteva popoln preverjeni inventar. Podatek kataloga sam ne določi korena. Podrobnosti projekta dobijo neposredno dejanje **Člani in deljenje**; urejevalnikov Members uporabi isto pot. Prehod ohrani preverjanje računa, prostora, prisotnosti projekta in dostopa. Če koren še ni pripravljen, besedilo pove, da je treba dokončati sinhronizacijo, in ne trdi več, da obstajajo zunanje finančne povezave.
3. **Razlikovalna imena članov.** Novi `crypto2.scope.memberLabels` vrne največ 100 zahtevanih imen v enem klicu. Strežnik preveri trenutni dostop, točno glavo in revizijo ter prisotnost prosilca in vseh zahtevanih računov v članstvu. [Odjemalčev parser](../lib/organizer/data/e2ee/crypto_member_labels.dart) veže odgovor na strežnik, račun, napravo, prostor, glavo in urejeni seznam računov ter sprejme samo prikazna polja. Vloge ostanejo iz podpisanega članstva. Imena so overjeni strežniški prikazni podatki, ne kriptografski dokaz identitete. Stari strežnik ali manjkajoče ime dobita izrecno lokalizirano oznako z razlikovalnim računom; generični Jivie ni več nadomestno ime vseh oseb.

### Novi lokalni kontrolni dnevnik

| Sklop | Nove uspešne kontrole | Poskusi in omejitve |
| --- | ---: | --- |
| Količina zahtevkov | **15** | 8 kontrol točnega predpomnjenja PASS v prvem poskusu; 5 kontrol repa opažanj PASS v prvem. Dve napaki testne priprave sta popravljeni, nato samo ti dve PASS v tretjem zunanjem poskusu; drugi je zaradi napačnega filtra izbral 0 testov. Uspešne kontrole niso ponovljene. |
| Koren, imena in neposredna pot | **30** | 8 podatkovnih, 4 widget, 15 PHP in 3 kontrole neposrednega klica/dogovora o zmožnosti, vsi v prvem poskusu. Podatkovni tek ima ohranjene dogodke `done.success` in 8 uspehov; izvorni izhodni status procesa po napaki dokaznega parserja ni shranjen. Parser je popravljen brez ponovitve testov. |

Skupaj je **45 različnih novih lokalnih kontrol PASS**. Ozki analizi imata 0 napak in 0 opozoril; v datotekah opažanj ostane 21 obstoječih info, v sklopu članstva 3. PHP lint, `gen-l10n` in `git diff --check` uspejo. Glavni in neodvisni izvorni pregled popravkov sta PASS.

Konkretni lokalni dokaz zmanjšanja: pravi bralnik kontrolne točke s SQLite in novim podpisanim dokazom izvede **2 → 1** inventarno branje, pri čemer opravi preverjanje podpisa obakrat. Trije ločeni preverjeni klici ohranijo tri ločene authority snapshot zahtevke in izvedejo **0 praznih strani opažanj**; prejšnja izvorna veja je zahtevala po eno na klic. Slednja primerjava je izvorna primerjava, ne ponovno izveden stari test. To ni meritev novega vrha zahtevkov ali dokaz odprave dejanskih 429.

Dokazi: `build/qa/local-diagnostics/request-volume-fix-20261023/summary.json` in ohranjeni poskusi; `build/qa/local-diagnostics/project-members-labels-20261023/source-freeze.json` ter dnevniki štirih sklopov. PHP uporablja dejansko kodo končne točke in SQL preverjanja v novi pomnilniški bazi s podano že preverjeno glavo; ni dokaz celotnega podpisa, prijave, HTTP ali native poti. Podatkovne in widget kontrole uporabljajo sintetične priprave; točna vrednost korena v stari živi bazi s tem ni neposredno prebrana.

**Native poskus 2 istega prenosa še čaka.** Nadaljuje se isto opravilo **UX26 deljenje – dokaz A v B** v istem projektu in z istima A/B računoma. Povabila, sprejema, lastnikove odobritve, vnosa in starih PASS se ne ponavlja. Do novega neposrednega dokaza B-jevega prikaza prenos in odprava native 429 ostajata nepotrjena. Ta dodatek ne potrjuje telefonov ali produkcijske izdaje.

## Native nadaljevanje r18: isti prenos PASS v poskusu 2, neposredna pot še FAIL

**Prejšnji zapis »native poskus 2 še čaka« je zgodovina.** Glavni agent je z obema Mac r18 nadaljeval isti projekt in isto opravilo, brez ponovitve povabila, sprejema, odobritve ali vnosa. Obe aplikaciji sta se zagnali okoli **11:31 UTC**; pri obeh je bil uporabljen že znani lokalni Continue v prikazu Protect connected data, brez novih ključev ali FILE obnove.

| Neposredno opažanje glavnega agenta | Novi izid |
| --- | --- |
| B pokaže **UX26 deljenje – dokaz A v B**, števec 0/1 done | **PASS, native poskus 2 istega prenosa** |
| B samodejna sinhronizacija | Zadnji uspeh 13:32 lokalno; stari pending=1/conflict=0/blocked=1 ostane; podrobnosti napake ni |
| A samodejna sinhronizacija | Zadnji uspeh 13:32 lokalno, 0/0/0; ob odčitku je naslednji samodejni cikel 13:33 že tekel |
| Space settings → člani na A in B | **PASS**: Preizkus A / Owner ter Preizkus B / Member, z razlikovalnima testnima uporabniškima imenoma |
| Novo neposredno dejanje Sharing and members na A in B | **FAIL1 na vsaki instanci**: »Membership for this project is not ready yet« |

Pasivno označeno okno **11:31:11–11:34:20 UTC** ima **505 odgovorov, vsi HTTP 200; dejanskih 429=0 in neberljivih vrstic=0**. Zajema obe instanci in vse njune prostore. Med njimi je 1 `account.scopeObservations`, 78 `domain.inventory`, 101 `authority.snapshot`, 103 `records.pull` in 11 `scope.memberLabels`. Zbiralnik ni pošiljal HTTP zahtevkov ter ni zajemal teles, ključev ali žetonov. Javni omejeni dokaz: `build/qa/local-diagnostics/sharing-ux-20261023/same-task-r18-attempt2-public.json`; zasebna izvorna povzetka sta vezana s SHA256 v tej datoteki. Uspeh prikaza istega opravila temelji na ločenem neposrednem GUI opažanju, ne zgolj na HTTP 200.

To potrdi novi prenos in pravilna imena v tem nadaljevanju, **ne potrdi stalne odprave omejitve zahtevkov ali globalno praznih vrst**. Okno ni primerljiv hitrostni benchmark s starim daljšim zajemom. Zgodovinski prvi prenos FAIL/STOP in njegovi štirje 429 ostanejo ohranjeni; uspešni koraki deljenja in novi uspeh prenosa se ne ponavljajo.

Pri neposredni poti je izvorni pregled odkril ozko napako nove projekcije: `crypto_business_records.id` je transportni **wire UUIDv8**, ne kanonični projektni UUID. Prejšnja kontrola s sintetičnim kanoničnim ID ni preverila tega dejanskega SQL spoja. Pripravlja se popravek, ki veže transportni naslov na kanonični ID in preverjeno projekcijo; njegov lokalni pregled in native potrditev se vodita posebej. **Tukajšnji FAIL1 za neposredno pot še ni nadomeščen s PASS.**

Po odčitkih sta bili obe aplikaciji normalno zaprti in njuna procesa odsotna. Ista podatkovna shramba, računa, projekt, opravilo ter B-jevo staro čakajoče/blokirano stanje ostajajo za ozko nadaljevanje; telefoni in produkcija niso vključeni.

### Ozki popravek povezave korena po r18 FAIL1

Po zgornjem opažanju je izvorni popravek dokončan in zamrznjen za r19. Spremenjeni sta samo [lokalni nalagalnik korena](../lib/organizer/data/e2ee/crypto_project_root_projection.dart) in njegov klic iz `CryptoBusinessSession.scopes()`. En `LEFT JOIN` ohrani vse projektne vrstice ter preveri točno particijo, prostor, transportni naslov, domeno `content`, izvor `records` in tip `project`; kanonični ID mora ustrezati projekciji in ponovno izračunanemu transportnemu naslovu za isti strežnik. Nepovezana aktivna vrstica ostane kandidat z neznanim ID, zato ne more skriti dvoumnosti. Obstoječa pravila korena, popolnega inventarja in dostopa ostanejo; popravek ne doda HTTP zahtevka.

**Štiri dodatne nove kontrole PASS v prvem poskusu:** tri uporabijo dejanski SQLite spoj in naslovni adapter, ena pa dejanski `scopes()` z istimi shranjenimi transportnimi/kanoničnimi vrsticami. Slednja potrdi `projectRootId` v izhodu in zavrne dodatna vsebinska branja. Podpisana glava, življenjski cikel in lastna avtoriteta so na tej meji podani kot sintetična priprava; to še ni native potrditev. Starih 45 uspešnih kontrol nismo ponovili; lokalni seštevek je zdaj **49 različnih novih PASS**. Analiza štirih datotek ima 0 issues, `git diff --check` PASS, glavni in neodvisni pregled ozkega popravka PASS.

Zamrznjeni dokaz: `build/qa/local-diagnostics/project-members-labels-20261023/root-address-correction-source-freeze.json`, SHA256 `942a0a6fd2d22b5b9c700e3d4f1d6889b708ce2ad24dbe1766f2280010107d43`; kontrolna dnevnika sta `root-address-attempt-1.json` in `root-scopes-caller-attempt-1.json`. **R18 neposredna pot na A in B ostaja FAIL1; r19 native nadaljevanje te poti še čaka.** Že uspešnega prenosa opravila in prikaza imen se zaradi tega ne ponavlja.

## Zaključna native potrditev r19: neposredno članstvo PASS v poskusu 2

**Zgornji zapis »r19 native nadaljevanje še čaka« je zdaj zgodovina.** Po ozki posodobitvi je glavni agent okoli **11:45 UTC** odprl obe isti instanci r19 in uporabil znani lokalni Continue. Iz podrobnosti istega projekta je na **A in B en klik Sharing and members** odprl zaslon **Sharing and members · UX26 Projekt A – deljenje**. Obe novi poti sta **PASS v drugem poskusu neposredne navigacije**, po ohranjenem r18 FAIL1 na vsaki instanci.

V okviru te nove poti sta prikazana točna člana **Preizkus A / macsharing_a… / Owner** in **Preizkus B / macsharing_b… / Member** ter prvotno že sprejeto povabilo. Ni novega sprejema, povabila ali odobritve. Že uspešni prenos opravila iz r18 ni bil ponovljen; ni manual Sync ali CRUD. En klik opisuje samo ta prehod iz že odprtih podrobnosti projekta, ne celotnega postopka deljenja ali globalnega minimuma klikov.

Novi pasivni odsek **11:45:23–11:46:43 UTC** zajame **287 odgovorov, vsi HTTP 200; dejanskih 429=0 in neberljivih vrstic=0**. Vključuje oba odjemalca in vse njune prostore; ne dokazuje trajne odsotnosti 429 ali hitrosti. Javni dokaz `build/qa/local-diagnostics/sharing-ux-20261023/project-members-r19-attempt2-public.json` vsebuje omejene agregate, vezavo zasebnega povzetka s SHA256 in ločeno povzeta neposredna GUI opažanja glavnega agenta. Nobenega novega HTTP/GUI dejanja ni bilo za izdelavo tega dokaza.

A je bila normalno zaprta. Pri poskusu zaprtja B je orodje vrnilo `frontmostApplicationChanged`; glavni agent je znova prebral trenutno dostopnost in nato izvedel Quit. Odsotnost obeh procesov je potrjena. Podatki, računa, projekt, prvotno članstvo in staro B-jevo pending/blocked stanje ostanejo; tega zaključka ne označujemo kot globalno prazne vrste. Bajtna enakost vault ostaja nepreverjena zaradi TCC, brez obvoda. Po zaključku je odstranjenih osem dovoljenih obnovljivih map v obstoječih source-a/source-b, skupaj **3.397.356.145 logičnih bajtov datotek**. Vseh 591 izvornih vhodov na instanco, končni paketi, prejšnji paketi, dokazi in podatki ostanejo. Obnovitve predpomnilnikov ali ponovitve testov ni bilo.

Zahtevani trije sklopi imajo sedaj konkretne lokalne in native rezultate: isti prenos opravila PASS v r18, imena PASS v r18 in kot del nove r19 poti, neposredna pot do članov PASS v r19. **49 novih lokalnih kontrol** in vsi prejšnji FAIL/STOP ostanejo v dnevniku; uspešnih kontrol zaradi zaključka nismo ponavljali. Druga opažanja raziskovalnega pregleda — naslov Encrypted space v povabilu, dvojni Join, skrito čakanje, podvojeni meniji in seznam projekta samega sebe — v teh treh popravkih niso spremenjena. Telefoni in produkcija niso vključeni.


Končna nameščena r19 AOT: A `514eea674d8d8f374ca5f3a9aab90268548b13be7b07cc5b33e86f52e1f3d969`, B `991b3637149b55d7540f93973fedea1360408bf84a1ce26a5cb7b90b8c6e77bf`. Vsaka r18 in r19 različica je imela eno native gradnjo in eno namestitev; r19 uporablja isti izvorni imenik in samo dve dodatni spremenjeni datoteki. Testni backend je posodobljen enkrat na 183 datotek, brez spremembe sheme, konfiguracije, TLS ali zagona vsebnikov. Zaključni pregled potrdi odsotnost obeh procesov, ohranjene identitete/shrambe ter nespremenjene metapodatke drugih štirih Jivie aplikacij in Docker vsebnikov. Dokaz `JivieLocalTest/share-20261019/r19-final-environment-metadata.json` ima SHA256 `6cc82e3c83d1148bfdf1d4b12fcb40e073f9e51da53b79ef1375c0d99d497afb`; manifest čiščenja je v vsakem `candidate-*-r19` imeniku.

Končni staged pregled je odstranil le odvečni presledek v prazni vrstici novega testa `crypto_project_root_scopes_seam_test.dart`; vsebina testa in runtime sta ista, uspešnih testov nismo ponavljali. Prejšnji testni hash v manifestu ostaja zgodovinski dokaz testiranih bajtov.

## Dodatek r20: povabila, čakanje in projektni meniji — lokalno PASS, novi native izid še PENDING

23. oktober 2026. Novo naročilo obravnava preostale UX ugotovitve zgornjega pregleda. Spodaj so novi izvorni popravki in ozke lokalne kontrole; prejšnji r18/r19 rezultati, prvotni STOP429, neposredni FAIL ter B-jevo staro pending/blocked stanje ostanejo ohranjena zgodovina. **Novi native rezultat r20 je ob tem zapisu še PENDING.** Glavni agent pripravlja isti Mac A/B; novi GUI odčitki in njihovi izidi bodo dodani ločeno. Ta dodatek ne potrjuje novega sprejema povabila, odobritve, prenosa, telefonov ali produkcije.

**Povabilo ima kratek začetni povzetek in en končni pregled.** Kartica v4 pokaže cilj oziroma pošteno oznako nedostopnega imena, pošiljatelja, vlogo in stanje; gumb je **Review invitation**. Končni zaslon pokaže prejemnika, potek, gostitelja in dovoljenja ter namerno dejanje **Join project** oziroma **Join space**. Podvojeni naslov na kartici je odstranjen. Končna vloga in finančna dovoljenja izhajajo iz preverjenega povabila oziroma predlaganega članstva; starejši prikazni model jih ne prepiše. Za v4 se ne prikazuje več razlage o starih pravilih dostopa. To spremeni oznake in razporeditev pregleda; **ne trdimo, da je celotna pot povabila krajša ali da potrebuje manj potrditvenih klikov**.

**Ime šifriranega cilja pred dostopom ostaja omejitev protokola.** Prikaz izrecno pove, da bo ime vidno po lastnikovi potrditvi dostopa. Strežnik ne dobi novega nešifriranega projektnega naslova in ta naloga ne uvaja novega ovoja za prenos naslova. Prikaz pošiljatelja uporablja omejena imena/uporabniška imena, vezana na račun ustvarjalca; manjkajoči podatki dobijo izrecen nadomestni prikaz. To so prikazni podatki gostitelja, **ne kriptografski dokaz identitete, članstva ali ključev**. Stari strežniki in stare različice povabil ohranijo svoje poti.

**Čakanje in lastnikovo dejanje sta vidna.** Lastnikov seznam pokaže **Invitation accepted — confirm access** ter opisni gumb **Confirm access** namesto samostojne drobne ikone ključa. Prejemnik vidi sprejeto povabilo in čakanje na lastnika. Pri vrnitvi iz pregleda oziroma ob obnovi vidne aplikacije se relevantni seznam ali status osveži z omejitvijo petih sekund, enim tekočim osveževanjem na zaslon ter preverjanjem trenutnega zaslona, računa in življenjskega cikla. Ni časovnega anketiranja ali samodejnega sprejema/odobritve. Že sprejeta povezava brez account-bound link checkpointa lahko preveri status s svojim trenutnim preview ID; `resumeAccepted` še vedno zahteva točno lokalno podpisano namero pred aktivacijo. Ročno preverjanje po potrebi odpre nastavitev zaščite; lifecycle osvežitev je ne odpre samodejno. Manjkajoči lokalni dokaz dobi izrecno pojasnilo za to napravo, ne tihega nedelujočega gumba.

Lastnikova odobritev ne kaže več internih **Content: 2 / Finances: 1**. Namesto njih pokaže preverjeno vlogo, dovoljenja za finance/upravljanje dostopa in razlago, da ta dovoljenja veljajo za dosedanjo vsebino ter nove spremembe. Kriptografska priprava in preverjanje inventarja ostaneta del odobritve.

**Projektne poti so poenotene.** Prostor, ki vsebuje samo svoj preverjeni korenski projekt, neposredno pokaže njegove podrobnosti; seznama z isto kartico in ponovljenega podnapisa ni več. Če obstajajo drugi projekti, izbira in seznam ostaneta. Filtri kategorije ne skrijejo podrobnosti namenskega projekta, pri prehodu nazaj v širši seznam pa se še naprej upoštevajo. Kartica in podrobnosti uporabljata skupno sestavo dovoljenih menijskih dejanj; na kartici je neposredna pot do **Sharing and members**. Lokalni urejevalnik pot objave poimenuje z obstoječo oznako za deljeno kopijo, namesto da jo predstavlja kot članstvo. Dostopna, arhivska, izbrisna in poročevalska varovala ostanejo.

| Novi lokalni sklop tega naročila | Različne uspešne kontrole | Meja dokaza |
| --- | ---: | --- |
| Prikazni metapodatki povabila | **13** | 7 Dart kontrol in 6 PHP/SQLite kontrol PASS v prvem poskusu; PHP uporablja svežo pomnilniško bazo, brez omrežja, z že podano mejo preverjanja dokazov. Ni HTTP/auth/native dokaz. |
| Projektna navigacija in meniji | **10** | Sintetične widget/navigacijske kontrole; ohranjena prva napaka kompilacijske priprave in zgodovina nadomeščene dvoumne kontrole. Pozneje se preverijo samo prizadete oziroma nove prehodne kontrole. |
| Pregled povabila, čakanje in lifecycle | **10** | Sedem PASS v prvem poskusu, dve v drugem, ena v tretjem. Štiri predhodne napake testne priprave so ohranjene: obstoječa oznaka pošiljatelja, vidno območje seznama, obstoječa oznaka vloge in neobstoječi testni ključ. |

Skupaj je **33 različnih novih lokalnih kontrol PASS** v tem naročilu. Uspešnih zgodovinskih kontrol in že uspešnih ciljnih kontrol nismo ponavljali. Analiza podatkovnega sklopa ima 0 issues; zaključna ozka analiza UI ima 0 napak, 0 opozoril in šest obstoječih info. `gen-l10n` ter `git diff --check` sta PASS. Končni ozki popravek pri v4 vrnitvi iz pregleda pred svežim nalaganjem počisti `_reloadAfterBusy`, tako da zaključek iste akcije ne zažene še drugega nalaganja. **Ta zadnji popravek združevanja je potrjen samo z izvorno presojo in analizo brez issues, ne z dodatno runtime kontrolo; ni dodatni 34. PASS.**

Dokazi tega dodatka so ločeni od starih r18/r19 zajemov:

- `build/qa/local-diagnostics/sharing-followup-20261023/invitation-display/summary.json` in pripadajoči podatkovni/PHP dnevniki;
- `build/qa/local-diagnostics/project-navigation-ux-20261023/final/result.json`, ohranjeni `attempt-1`, `attempt-2`, `attempt-3` ter `category-transition-attempt-1`;
- `build/qa/local-diagnostics/sharing-ux-fixes-20261023/invitation-ui/result.json`, vsi ohranjeni uspešni/neuspešni dnevniki in `source-manifest.json`, SHA256 **817633137f18619c2d1955aff41591ac5625d64c8f2045f299a62ae2131eaa1f**;
- končni neodvisni izvorni pregled UI **PASS**: `build/qa/local-diagnostics/project-navigation-ux-20261023/final/invitation-ui-independent-review.json`, SHA256 **85051864461b07f854fccd886454fd55830c28405b3754a8525eed69cc1d9c96**, vključno z zadnjim izvorno pregledanim združevanjem nalaganja. Glavni pregled je ugotovitve vključil pred zamrznitvijo izvora.

Ti lokalni dokazi ne nadomestijo novega neposrednega native odčitka. Načrtovani ozki r20 pregled istega Mac A/B obsega spremenjeno projektno navigacijo in menije; **nov native izid, HTTP agregati in morebitne nove omejitve ob pisanju tega dodatka še niso potrjeni**. Starih uspešnih povabil, odobritev in prenosa se zaradi tega dodatka ne ponavlja.

### Zaključek r20: novi projektni prikaz na obeh Mac instancah PASS

**Zgornji native PENDING je zdaj zgodovina.** Obe isti testni namestitvi sta posodobljeni v enem build/install poskusu na instanco, brez odstranitve aplikacije, spremembe identitete, Keychaina ali podatkovne shrambe. Glavni agent je po znanem **Continue locally** na A in B enkrat odprl **Projects** v že izbranem prostoru **UX26 Projekt A – deljenje**. Oba prikaza neposredno odpreta podrobnosti pravega projekta, brez vmesnega seznama z isto kartico. Vidni gumb **Sharing and members** je en sam; njegove že uspešne poti do članov nismo ponovno klikali.

Novi pregled menija na A pokaže **Attachments / Edit project / Archive / Delete / Report content**, na B pa **Attachments / Edit project / Archive / Report content**. Akcij nismo izvedli. Obstoječe opravilo je vidno kot del podrobnosti; to ni ponovitev testa prenosa. Prvi poskus klika na A je orodje zavrnilo zaradi zastarelega AX elementa, ker se je medtem prikazalo znano začetno opozorilo. Klik ni bil dostavljen; svež odčitek in Continue sta omogočila opisani prvi dejanski pregled. To ni zabeležena napaka aplikacije ali nov krog funkcionalnega testa.

Pasivni odsek **12:20:51–12:22:33 UTC** ima **224 odgovorov HTTP 200, 0 dejanskih 429 in 0 neberljivih vrstic**. Zajema promet obeh aplikacij in vseh njunih prostorov, vključno z običajno samodejno sinhronizacijo. Ni hitrostni benchmark ali jamstvo trajne odsotnosti 429. Noben nov ročni Sync, CRUD, povabilo, sprejem ali lastnikova odobritev ni bil sprožen. Novi GUI dokaz in omejeni HTTP agregati: `build/qa/local-diagnostics/sharing-followup-20261023/r20-native-project-ux.json`, SHA256 `415d060b2a2e54a3bf8fecfd87f0f4f514395d7b47a24fe83e82277456251603`.

Obe aplikaciji sta normalno zaprti in procesa odsotna. Ohranjenih je vseh **592 izvornih vhodov na instanco**, osem obstoječih QA prilagoditev, isti SDK/locks in podpisi. Končni AOT je A `40a7ad52b737cc757da6b8011fb05e9320738607b3fddbc5c1b2fe7b97bfa2cb`, B `c8a4d3310cda5face3d63b748cfd7d940a332b7fd8b01def7c5aa9d3f4729174`. Lokalni backend je dobil samo eno prikazno PHP spremembo; ostaja 183 datotek, schema20, isti TLS, konfiguracija in vsebniki. Končni svež pregled potrdi nespremenjene metapodatke drugih štirih Jivie aplikacij in Docker vsebnikov. Bajtna enakost vault ostaja **UNVERIFIED zaradi TCC**, brez obvoda. Staro B-jevo pending/blocked stanje ni bilo čiščeno in ne trdimo globalno praznih vrst.

Po pregledu je odstranjenih osem obnovljivih build cache map, **3.328.540.209 logičnih bajtov datotek**. Končni in predhodni paketi, izvor, podatki, ključi ter dokazi ostanejo. Končni zasebni dokaz `share-20261019/r20-final-environment-metadata.json` ima SHA256 `e7400ecfe1dd9f7de625ba38c1550a5561c8677f6855403f61361031cf9682e9`. Telefoni in produkcija so nedotaknjeni. Povabilni UI ima opisane lokalne kontrolne in izvorne dokaze; **novega celotnega native sprejema/odobritve povabila v tej nalogi ni bilo**. Te spremembe ostajajo del skupne neobjavljene nadgradnje.
