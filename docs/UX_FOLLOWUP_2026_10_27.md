# Uporabniški popravki med mobilnim preizkušanjem — 27. oktober 2026

Izhodišče je `679d8e1`. Uporabnik dovoljuje odpravo zbranih ugotovitev med svojo odsotnostjo; vrt ostaja izključen. Mac je zaklenjen: preverjanje je lokalno, brez upravljanja zaslona, telefonov ali produkcije. Obstoječe testne baze, ključi in osnutki niso testne podlage tega sklopa. Podagenti GPT 6.1 Sol / high izvajajo ločene sklope, root pregleduje povezave, varovala in rezultate.

## Dogovorjeno vedenje in izvedba

### Dodajanje v trenutno izbrani prostor

Gospodinjstvo/organizacija lahko prikazujeta tudi zapise projektov, vendar dodajanje uporablja dejansko izbrani prostor. Obstoj podprojektov ne odpre dodatnega izbora cilja. Finance ohranijo svoj račun in preverjanje finančnih pravic; vsebinska umestitev novega vnosa sledi izbranemu prostoru. Pogled **Vsi** še vedno potrebuje izrecno izbiro cilja. Neveljaven ali nedostopen cilj se ne nadomesti s prvim dostopnim otrokom.

Poti: `all_spaces/all_spaces_page.dart`, `shared/sharing_workspace.dart`, `finance/shared_finance_actions.dart`. Aktualna seja, naprava, urejanje in finančna pripravljenost se še vedno preverijo pred dejanjem in pri zapisu.

### Predizbira računa stroška opravila

Spustni seznam ostane v obrazcu. Za nov strošek ima prednost edini ustrezen aktivni račun trenutnega prostora/projekta; če projekt nima svojega aktivnega računa, sledi edini ustrezen nadrejeni račun. Več ustreznih računov zahteva izbiro; projektna dvoumnost se ne reši s tihim prenosom stroška na starša. Upoštevana je valuta. Pri povsem novem praznem strošku lahko edini račun določi tudi začetno valuto; že izbrana valuta se ne zamenja samodejno.

Privzeta vrednost se nastavi tudi po dovoljenem poznem nalaganju nadrejenih računov. Ročna izbira, shranjen strošek in njegov obstoječi račun ostanejo nespremenjeni. Osebni lokalni in povezani računi se filtrirajo po obstoječem lastništvu. Izbira ne daje pravice za zapis.

Poti: `domain/task_cost_account_default.dart`, `organizer_editors.dart`, `planning/record_planning_fields.dart`. Prikaz valute in računa se ob pozni predizbiri oba osvežita.

### Nakupi, koledar in odpiranje opravil

- Podrobni prikaz nakupovalnega seznama ima samo en meni dejanj seznama in oblaček sinhronizacije. Meni prostora je od tam odstranjen, tudi kadar se edini seznam odpre samodejno. Dejanja prostora ostanejo na pregledu in v obstoječih nastavitvah; vrnitev na pregled jih znova prikaže.
- Skupni koledarski pregled dobi stalni izbiri **Koledar / Časovnica** in uporablja obstoječo mrežo koledarja. Prehod nazaj ni skrit v meniju. Datum brez dogodkov ima ustrezno dnevno prazno stanje.
- Odpiranje opravila iz običajnih seznamov, Utripa, koledarja in iskanja vodi v predogled. Jasno dejanje **Uredi opravilo** odpre obstoječi urejevalnik samo ob veljavni pravici. To ni različna politika za Android/iOS.

### Pošten prikaz sinhronizacije

Uspešno preverjanje `account.changes` ima ločena časa poskusa/uspeha, ne spreminja pa časa dejanske uskladitve podatkov. Svež zagon brez sprememb lahko prikaže **Spremembe računa preverjene**, namesto da trdi, da poskusa sploh ni bilo. Znane čakajoče operacije, napake, nepopolna dovoljena projekcija in še neobdelan izbrani prenos imajo prednost; preverjanje ne postane dokaz uspešnega prenosa ali pravic.

Ni dodatnega celotnega synca ali novega timerja. Prikaz uporablja obstoječe števce ter omejeni poizvedbi prisotnosti kriptografskih/plačilnih operacij in uskladitve dostopov; ne serializira celotne zgodovine vrst ob vsakem prikazu. Predpona računa je primerjana dobesedno, tudi kadar URL vsebuje znake `%` ali `_`. Časi ostanejo vezani na trenutno sejo in se ob menjavi ponastavijo.

### Iskanje prejemnikov povabila

Nov strežnik oglašuje zmožnost `recipientSearch`. V obrazcu povabila uporabnik vpiše najmanj dva znaka imena/uporabniškega imena, počaka kratek zamik in izbere predlog. Iskanje ima omejitev dolžine, deset rezultatov, omejitev zahtevkov in preverjanje upravljanja izbranega prostora. Ne vrača seznama e-poštnih naslovov, sej ali vsebine prostorov. Neaktivni uporabniki, trenutni uporabnik in neustrezni računi so izključeni.

Prejemnik je po izboru vezan tudi na trajni accountId; reciklirano uporabniško ime ne sme preusmeriti povabila. Pozni odgovori po spremembi besedila/seje se zavržejo. Sprejem povabila in šifrirana dodelitev ostaneta ločena obstoječa postopka. Starejši strežnik ali nedosegljivo iskanje ohrani točen vnos uporabniškega imena/e-pošte. Pogodba: [space-sharing-api-contract.md](server/space-sharing-api-contract.md).

## Ciljno lokalno preverjanje

Dnevnik poskusov in omejitve so ohranjeni v `build/qa/` (ignorirano), trajni testi v `test/` in `server/tests/`. Ne ponavljamo starih uspešnih scenarijev; filtrirani ponovni zagoni vključijo le padle primere. Največ tri poskuse na primer.

- **Predizbira računa: 9 novih widget kontrol PASS.** 6 osnovnih primerov; dodatna kontrola poznega USD računa (med pregledom odkrit popravek prikaza valute); dodatna kontrola ročno izbrane valute in pozneje odvzete pravice. Prvi osnovni tek ni prevedel napačnega testnega API `setPhysicalSize`; drugi 6 PASS. Zadnja kontrola je najprej napačno pričakovala onemogočen dropdown, obstoječi obrazec pa ga ob izgubi pravice skrije; popravljeno pričakovanje, drugi PASS. Brez ponavljanja prejšnjih uspešnih kontrol. Dodatna povezovalna kontrola: predizbran nov strošek se ohrani ob primerjavi z neodvisno oddaljeno spremembo naslova opravila in se nato shrani skupaj z novejšim naslovom, PASS1. Dokazi: `build/qa/task-cost-default-20261027/`.
- **Navigacija: 17 aktualnih novih widget kontrol PASS.** Gospodinjstvo/organizacija × opravilo/dogodek, veljaven/zavrnjen neposredni cilj, Vsi, finančni vnos, koledarski prehod, predogledi in pravice, meniji pri 320 px in povečavi besedila. Prvi tek compile FAIL zaradi nepovezanih action interface tipov; pogodba capability vmesnika popravljena. Drugi 5 PASS/7 fixture FAIL (napačen naziv gumba); tretji samo teh 7 PASS. Dodatni štirje: prvi compile fixture FAIL zaradi nullable lokalizacije, drugi 4 PASS. Dve prvotni kontroli razlikovanja dveh menijev sta nato nadomeščeni s tremi kontrolami dokončne rešitve: odstranjen meni prostora iz podrobnosti, vrnitev na pregled in samodejno odprt edini seznam. Dve PASS1, samodejni prikaz PASS2 po odstranitvi zastarelega pričakovanja oznake; prvotni dve se ne vštevata v 17 aktualnih kontrol. Štiri stare testne poti, ki namenoma pričakujejo neposredno urejanje, so prilagojene novemu izrecnemu gumbu; niso ponovno izvajane. Dokazi: `build/qa/ux-navigation-20261027/report.json`.

### Primerjava novejših sprememb v odprtem opravilu

Odprti skupni urejevalnik opravila zdaj omogoča **Preglej novejše spremembe**. Prikaže prvotno različico, osnutek in najnovejšo. Neodvisne spremembe predlaga skupaj, ob nasprotju istega polja/skupine pa zahteva izbiro; **Uporabi v osnutku** še ni shranjevanje. Nato velja običajen Save z veljavno revizijo in vsemi pravicami. Strošek se obravnava kot nedeljiva skupina, ne združujemo zneska ene različice z računom druge. Časovnik in podatek o prejšnjem knjiženju sledita najnovejšemu potrjenemu stanju.

Preklic, še novejša sprememba med pregledom ali izguba pravice ohranijo osnutek in ne premaknejo osnove shranjevanja. Finančna vidnost/urejanje sta ločena od pravice za opravilo. Urejanje brez finančne pravice ne razkrije primerjave skritega stroška in ne zavrže spremenjenega finančnega osnutka. Tipkane vrednosti se zajamejo pred primerjavo; zgolj podatek v Form kontrolniku ni dovolj. Brisanje opravila med pregledom ustavi urejanje.

Obseg: odprti **skupni urejevalnik opravila**. To ni splošen novi združevalnik za finančni modul, tabele, dogodke ali brisanje. Ti ohranijo obstoječo varno obravnavo konfliktov. Poti: `organizer_editors.dart`, `task_draft_review.dart`, `domain/draft_three_way_merge.dart`, `shared/collaboration_actions.dart`.

### Preostali izidi preverjanja

- **Status sinhronizacije: 15 novih kontrol + 1 prilagojena kontrola pogodbe PASS.** 11 novih repository/SQLite in 4 projekcijske/UI; ena obstoječa kontrola je prilagojena namernemu dogodku statusa ob unchanged. Nevalidna identiteta: napačno pričakovanje tipa izjeme, popravljeno v tretjem poskusu; brez četrtega. Lease primer: začetni fixture vrstni red preverjanja dostopov je preprečil želeno vejo, drugi PASS. Bounded EXISTS in dobesedna predpona particije 2 PASS1. Dodaten preizkus mirnega naslednjega kroga potrdi ohranitev referenc vsebine/članov/inboxa, brez širokega lokalnega osveževanja ali prenosa. Dokazi: `build/qa/sync-status-20261027/result.json`.
- **Iskanje prejemnikov: 15 novih Dart kontrol in 18 PHP assertions PASS.** Debounce, pozni odgovori, seja, fallback starejšega strežnika, celoten obrazec, nespremenljiv kriptografski osnutek, zavrnjen/izbrisan prostor, vezava prejemnika, omejitev zahtevkov, Unicode ime, brez razkritja e-pošte ali samodejne dodelitve. Repository fixture `logout` → `signOut` in crypto fixture `extends` → `implements` sta prevajalska popravka; uspešne kontrole se niso ponavljale. PHP je pravi dispatcher na novi pomnilniški SQLite v omrežno izoliranem začasnem Dockerju, ne HTTP ali celoten podpisni cikel. Dokazi: `build/qa/recipient-search-20261027/result.json`.
- **Primerjava osnutka: 7 novih kontrol PASS, 1 STOP3.** Prvi compile fail zaradi nullable rezultata; drugi je odkril dejansko vrzel zajema tipkanega besedila. Po popravku samo padle kontrole: 3 PASS3; en primer se ustavi zaradi preširokega testnega iskanja besedila, ki se po spremembi prevoda pojavi dvakrat. Pred tem je potrdil zaprtje primerjave, nič premikov osnovne revizije in ohranjen naslov osnutka; nadaljnje ponovno odprtje najnovejše različice v tem testu ostane NEPOTRJENO. Finder popravljen, četrtega zagona ni. Dodatna kontrola finančne atomarnosti/kanoničnega časovnika PASS2 po zamenjavi neveljavnega neposrednega spreminjanja drafta s pravim tipkanjem; sprememba finančne pripravljenosti PASS1. Dokazi: `build/qa/task-draft-review-20261027/result.json`.
- Neodvisni izvorni pregledi: deljenje in navigacija, finančna predizbira ter primerjava osnutka. Med pregledom so popravljeni prikaz pozno predizbrane valute, nepopolni opisi finančnih razlik, neustrezna možnost združevanja časa in dodatni široki refresh samo zaradi statusa.

Skupno: **64 aktualnih ciljnih Dart kontrol PASS** (63 novih in 1 namerno prilagojena) ter **18 backend assertions PASS**; en test STOP3, ne PASS. To ni polna regresija ali dokaz fizičnega mobilnega delovanja.

## Meje in predaja

- Uporabnik je finančno sinhronizacijo okoli **5 sekund** potrdil kot sprejemljivo. V tem sklopu je ne optimiziramo na slepo in ne ponavljamo uspešnih prenosov.
- Prenova vrta je izključena. Staro uspešno shranjevanje sezon/kultur ni ponovno testirano.
- Telefonska namestitev in dejansko upravljanje aplikacije ostaneta za uporabnikovo vrnitev. Lokalni widget/SQL testi niso dokaz hitrosti ali pravilnega izrisa na fizični napravi.
- Strežniški popravek iskanja še ni nameščen v obstoječi mobilni testni strežnik ali produkcijo; za mobilni preizkus predlogov potrebujemo posodobljena odjemalec in testni strežnik.

- Zgodovinsko kratko utripanje začetnega zaščitnega zaslona: izvorni pregled trenutne presoje in koordinatorja ni izoliral novega dokazljivega vzroka. Varovala priprave/obnove niso oslabljena; morebitno ponovitev preverimo na novi mobilni gradnji.
- Celotna statična analiza repozitorija je pokazala 20 napak in 2 opozorili v nespremenjenih starejših testnih dvojnikih in predlogi `tools/diagnostics/qa_reliable_diagnostics.dart` (predloga se kopira v drug kontekst). To ni uspešna celotna analiza. Seznam z dokazom nespremenjenih datotek: `build/qa/ux-followup-20261027/full-analysis-limitations.json`. Ločeni končni rezultat produktne kode in vseh spremenjenih testov je zabeležen spodaj.

Končna analiza `lib` in vseh takrat spremenjenih testov: **0 napak, 0 opozoril, 511 slogovnih info**, exit 0 (`analyze-final-targets.log`). Pozneje prilagojeni dve besedilni pričakovanji v `sharing_status_ui_test.dart` sta dodatno ozko analizirani; ne gre za ponovljen runtime test. `git diff --check` PASS. Obstoječi neuspehi celotne analize ostanejo izrecno ločeni od tega ciljnega rezultata.


## Namestitev po uporabnikovi vrnitvi — 27. oktober 2026

Uporabnik je priklopil oba telefona in dovolil namestitev. Produktna podlaga je
commit `cd806786b02866f8c1a06066e28c51255a29630f`. Ločena podagenta GPT 6.1
Sol/high pripravljata Android in iOS; root preverja dokaze in posodobi izključno
lokalni mobilni strežnik. To ni objava v Google Play/TestFlight ali produkcijo.

Mobilni testni strežnik `18801` je posodobljen na točno trenutno vsebino vtičnika:
pet spremenjenih datotek in nova `NativeRecipientSearchService.php`. Pred
spremembo je narejena zasebna hladna kopija podatkov, izvora, konfiguracije in
TLS. Po zagonu so vseh 225 tabel, njihove vsebine in shema bajtno/logično enake
po tabelnih primerjavah; shema ostane 23. Identiteta gostovanja, TLS in ključi
ostanejo isti. En javni HTTPS capabilities zahtevek vrne 200 in
`recipientSearch: true`; avtenticiranih poslovnih zahtevkov ni. Vse prvotne
storitve so spet zagnane z istimi ID-ji/slikami; drugi vsebniki niso spremenjeni.
Dokazi: `build/qa/mobile-ux-update-20261027/server/result.json`.

Android: ena gradnja in ena namestitev `install -r` v isti testni paket,
brez zagona aplikacije. Isti podpis, UID 10292, podatkovni imenik in native
knjižnice. Vseh 20 nepredpomnilniških datotek (128.038.724 B) je pred in po
namestitvi enakih; originalni Google Play paket in njegovi metapodatki so isti.
APK SHA-256: `bcdb3b1f74a5279dc17302e596407d508e08fd9e8b96273ff1849b64838021ef`.
Diagnostika: `jivie_qa_android_ux_20261027_v1`, oznaka
`android-ux-20261027-r1`. Branje po uporabnikovem preizkusu:
`python3 build/qa/mobile-ux-update-20261027/android/read_diagnostics.py`.

iOS: ena Release archive gradnja (78,17 s), ena namestitev v isti testni paket,
brez zagona. Štiri datoteke trezorja (10.285.446 B) so enake pred, neposredno
pred in po namestitvi. Isti podpisni certifikat/profil, team, Keychain identiteta,
CA in native kriptografski knjižnici; produkcijski metapodatki nespremenjeni.
AOT SHA-256: `58042f6ff21ca2e1863db3d65a3112d52a830a7f79e1e28fd5bc53afb58d0db5`.
Diagnostika: `jivie_qa_ios_ux_update_20261027_v1`, oznaka
`ios-ux-update-20261027-r1`. Branje po uporabnikovem preizkusu:
`python3 build/qa/mobile-ux-update-20261027/ios/read_diagnostics.py --after-user-test`.
Obstoječe opozorilo archive o PrivacyInfo iz cryptography_flutter je zabeleženo;
gradnja uspešna. Ciljni Dart analizi brez napak/opozoril. Root je dodatno potrdil
635 Android/646 iOS izvornih hashov proti trenutnemu repozitoriju; nespremenjeni.

Odstranjeni so samo obnovljivi vmesni izdelki teh gradenj: Android
1.315.201.733 B, iOS 934.484.034 B. Paketi/archive/dSYM, izvor, dokazi in zasebne
kopije ostanejo. Bralnika diagnostike sta statično preverjena proti novi shemi;
zagon aplikacij in branje novih runtime dnevnikov še nista izvedena.

Obe aplikaciji sta zaprti za uporabnikov prvi zagon. Naslednji korak: odpreti
Samsung Jivie Test, počakati približno 20 sekund in preveriti začetni zaslon;
nato ciljno nove poti (ne ponovitev starih uspešnih scenarijev).


### Prvi uporabnikov Samsung zagon nove gradnje

Uporabnik potrdi običajen uspešen zagon, vendar za približno sekundo vidi
zaslon o obnovi. Bralni zajem `diagnostic-read-20261027T161800108837Z.json`:
assessment current/reason none; ena completion code none/unresolved false/
retry false; nadaljnji krogi unchanged. To ni dokaz nove potrebe po obnovi.

Izvorna vrzel je zdaj konkretno najdena: `LocalVaultBootstrap` začne z
`_busy=true`, `_status=null`; `build` do zaključka inspect vrne `_buildRecovery`,
ta pa brez pogoja prikaže naslov in pojasnila obnove celotne namestitve.
Nalaganje zato lahko pokaže obnovitveni zaslon tudi pri zdravi bazi. To je
izvorno potrjena pot; kratki uporabnikov prikaz ni bil posnet frame-po-frame
in zgodnja lokalna inspect faza ni zajeta v trenutnem runtime dnevniku.
Predlagani ciljni popravek: pred prvim izidom lokalnega pregleda nevtralen
nalagalni prikaz, ob dejanskem recovery/setup/error pa obstoječe varovalo in
ustrezen zaslon. Brez preskoka inspect ali odpiranja baze pred potrditvijo.
V tem odgovoru samo diagnoza/zapis, brez produktne spremembe ali namestitve.


## Ciljni popravek začetnega prikaza — logotip → zadnji prostor

Uporabnik naroči izvedbo, lokalno preverjanje in posodobitev obeh Jivie Test.
`LocalVaultBootstrap` pri prvem še neznanem stanju prikaže `JivieStartupLogo`.
Aplikativni otrok, baza, usmerjevalnik in porabniki ostanejo nemontirani do
uspešnega pregleda. Ko je znan dejanski setup/recovery/cleanup/error, ostane
obstoječi zaslon z vsemi varovali. Pri že dovoljenih ohranjenih kopijah ostane
nevsiljiva oznaka. Nobena zahteva za obnovitev ni samodejno potrjena.

Shell pri prvem zagonu počaka na lokalni organizer, localSpaces in collaboration
izid, da ne pokaže osebnega prostora pred obnovljeno izbiro skupnega prostora.
Po prvem izidu ni novih blokad zaradi osveževanja ali `isSyncing`. Obstoječa
začetna destinacija je Utrip; obdelava izrecnih povabil/push povezav je ohranjena.
Preverjen izvor: `CollaborationRepository.initialize` bere lokalno sejo,
metapodatke in projekcije; `_restoreRemotePush` bere varno lokalno shrambo.
Koordinator zažene omrežni sync ločeno prek microtask/unawaited. Ni novega
timerja/HTTP poti ali spremembe kriptografskih in zapisovalnih pravic.

Šest novih bootstrap widget kontrol PASS v prvem poskusu: zakasnjen prvi
pregled → ready/retained copies/recovery/setup/cleanup in napaka pregleda.
Pred izidom nič prezgodnjih child porabnikov ali obnovitvenih gumbov; pri pravi
napaki se ne ostane v logotipu in ne odpre podatkov. Ciljna analiza teh treh
datotek brez ugotovitev. Neodvisni podagent pregleda ohranitev bootstrap varoval.
Dokazi: `build/qa/startup-logo-20261027/`.

Štiri dodatne kontrole dejanskega shell widgeta PASS v drugem poskusu: oba
vrstna reda obnovitve lokalne/skupne izbire, zadnji lokalni Utrip in kasnejši
refresh brez prekrivanja, prava napaka branja z obstoječim gumbom Poskusi znova.
Skupni Utrip se odpre ob `isSyncing=true`, zato ne čaka na omrežni zaključek.
Prvi poskus: testni `pumpAndSettle` je čakal na namenoma aktivno animacijo synca;
druga dva primera sta končne trditve dosegla, a ju je podrl timer iz testnega
vira povabil. Omejeno pumpanje in null testni vir povabil popravita fixture,
ne produktne logike. Šest že uspešnih bootstrap kontrol ni bilo ponovljenih.
Root pregleda shell spremembo: samo začetna lokalna pripravljenost, brez novih
omrežnih klicev ali spreminjanja shranjene izbire. Skupno deset novih kontrol.


Produktni popravek je commit `36783e2143d0db31c941bb6eca987ccc2302aa29`,
push na origin/main potrjen z exact oddaljenim hashom. Root pred gradnjama
preveri 636 Android/647 iOS izvornih hashov. Nobene strežniške spremembe v tem
sklopu; lokalni mobilni strežnik ostaja cd80678.

Samsung: ena arm64 debug gradnja (32,09 s), ena install-r, brez zagona;
APK `3d79c1b3d2684dbef2f65d5a7bae18bc384fd4a33e80edb279a98366daa008a0`.
Sveža kopija in exact primerjava vseh 20 nepredpomnilniških datotek
(128.172.956 B) pred in po namestitvi. UID/podpis/imenik/CA/native knjižnice
isti; originalni Play APK in metapodatki nespremenjeni. Novi bralnik:
`build/qa/mobile-startup-logo-20261027/android/read_diagnostics.py`.
Odstranjenih 1.315.217.657 B obnovljivih build datotek; paketi, izvor in kopije
ostanejo. Runtime prikaz čaka uporabnikov zagon.


iPhone: ena Release archive gradnja (88,16 s), ena namestitev, brez zagona.
AOT `9299b5babde8c52d35e1b79a9324dc7ec772df3e6c74ee626f4f40bea8014fc2`.
Štiri datoteke trezorja (10.285.446 B) enake pred/neposredno pred/po namestitvi;
podpis/profil/team/Keychain/CA/native kriptografija ohranjeni, originalni
metapodatki nespremenjeni. Odstranjenih samo 934.495.067 B obnovljivega derived
predpomnilnika; archive/dSYM/izvor/kopije ohranjeni. Bralnik:
`python3 build/qa/mobile-startup-logo-20261027/ios/read_diagnostics.py --after-user-test`.
Obe namestitvi sta uspeli v prvem poskusu, aplikaciji ostaneta zaprti. Novi
mobilni prikaz ni še runtime potrjen. Diagnostika je pripravljena za uporabnikov
zagon; telefonov nismo dodatno klikali in uspešnih poslovnih testov ne ponavljamo.


## Uporabniško deljenje in sprejem — samo diagnoza, 27. oktober

Uporabnik potrdi novi zagon, nato poroča pošiljanje približno 15 s in sprejem
na iPhonu več kot 10 s; pozneje potrdi, da je tudi sprejem uspel. Nobeno povabilo,
Save ali sync ni bilo ponovno sproženo z naše strani. Samo oba nova bounded
bralnika in izvorni pregled, brez sprememb kode/namestitev/strežnika.

Android dnevnik `diagnostic-read-20261027T163120926589Z.json`:
`crypto2.invitations.create` HTTP200/62 ms ob16:30:12.471UTC;
resolvePreauthorization do publishPreauthorization 10.132 s (seq181–957).
V tem časovnem oknu202 fizična HTTP odgovora, vsi200; med njimi53receipt.get,
26account.status,18grants.manifest,16grants.put,12grants.list,8headGet.
Časovna vsota HTTP trajanj6.133 s ni čisti wall-clock ali celotna latenca klika.
Izvor invite_crypto_repository `_preparePreauthorization`: pripravi parent,
zaporedno otroke, vsak `_preparePreauthorizedScope` z reviewRotation +
confirmRotation, nato objavi povabilo. Dve aktivaciji/glavi v oknu sta skladni
s pripravo več prostorov; ni dokaz, da so vsi klici odveč ali pripadajo izključno
povabilu. Del so lahko sočasni opravki koordinatorja.

iOS dnevnik `diagnostic-read-20261027T163151217822Z.json`:
accept HTTP200/30 ms ob16:31:14.716UTC, status HTTP200/14 ms takoj zatem.
Do naslednjega sync completion code none/unresolvedfalse/retryfalse je33.966 s;
v oknu seq188–1219 je255HTTP odgovorov, vsi200.29authority.snapshot,
30receipt.get,28lifecycle.list; snapshoti do~840KB, posamezen do614ms.
`invitation_wizard.dart::_openEncryptedTarget` pred izbiro prostora izrecno
čaka `controller.syncNow()` celotnega računa. To je konkreten kandidat za
zožitev čakanja na preverjen ciljni prostor, preostanek pa v koordinatorju.
Zajeti so tudi owner_pending (iOS) in existing_scope_upgrade_pending(Android)
ujeti policy-baseline izidi, a končni sync je uspešen; ne trdimo, da so sami
vzrok zamude. Zgodnejši iOS invitations.status403 je pred svežim preview/accept,
ni dokaz zavrnjenega sprejema. Natančna razčlenitev brez vsebine:
`build/qa/sharing-latency-observation-20261027/summary.json`.

Predlog nadaljevanja (ne izvedba): izmerjeno združevanje/ponovna uporaba dokazov
znotraj iste priprave deljenja z ohranjenimi svežinami/podpisi; pri sprejemu
odpreti preverjeni ciljni prostor po minimalno potrebnem prenosu, ostale prostore
obdelati v ozadju. Ne predlagamo odstranitve zaščit ali lažnega uspeha pred
objavo prejemnikovih ključev. To ni iPhone-only težava.

Dodatno uporabnik opaža nevtralen oblaček ob novem zagonu, zelen po prvi
uskladitvi. Trenutni projection/ikonografija to potrjuje: checked uporablja
cloud_outlined, synced cloud_done; časi uspeha so session-only. To ni dokaz
izgube že prenesenih podatkov. UX možnost: ohraniti/označiti zadnjo potrjeno
uskladitev ločeno od trenutnega preverjanja, brez trditve nove svežine. Samo
zapis, brez trajnega shranjevanja statusa ali spremembe barve v tem koraku.

## Pohitritev povabil in zgodovina oblačka — lokalna izvedba, 27. oktober

Uporabnik nato naroči izvedbo vseh treh popravkov, najprej lokalno. Trije
GPT 6.1 Sol/high podagenti obdelajo pošiljanje, sprejem in oblaček; root pregleda
integracijo in varovala, podagent neodvisno pregleda sprejem in pošiljanje.
V tem sklopu ni zagona aplikacij, namestitev, posegov v telefone, obstoječe
testne baze ali strežnike. Mobilni namestitvi ostajata 36783e2, testni strežnik
cd80678; produkcija in originalna Samsung aplikacija sta nedotaknjeni.

### Pošiljanje

`invite_crypto_repository.dart` znotraj priprave preavtorizacije ponovno
uporabi točne dokaze iste omejene preverjene operacije. Vstop, vsak otrok,
potrditev rotacije in končna objava imajo svežo mejo. Obstoječa omejitev
veljavnosti dokazov, podpisi, identitete, preklic po podpisanem zapisu,
nespremenljive zahteve in receipts ostanejo. Ni splošnega predpomnilnika ali
podaljšanja veljavnosti pravic.

Pet novih kontrol PASS. Omejen lokalni primer skozi dejansko pripravo
povabila/preverjanje podpisa imenika prejemnika in sintetično ponavljanje
preverjanj pravic: 6 → 4 transportni klici. To ni meritev celotnega pošiljanja
ali dokaz zmanjšanja prej zajetih 202 HTTP zahtevkov. Potrjeni so sveža zavrnitev
kljub staremu dokazu, invalidacija po podpisanem zapisu in zavrnitev napačnega
podpisa. Rotacije/otroci/objava imajo kontroliran preizkus mehanizma meje in
izvorni pregled klicnih mest, ne celotnega omrežnega E2E preizkusa.
Poskus 1: testni prejemnik brez accountId; navidezni uspeh preširokega preverjanja
podpisa razveljavljen. Poskus 2: vseh pet pravilnih kontrol PASS. Analiza brez
ugotovitev. Dokazi: `build/qa/invitation-speed-20261027/send/result.json`.

### Oblaček

Nova zgodovina uspešne uskladitve je ločena od dokaza v trenutni seji. En
verzioniran zapis v local_meta je vezan na strežnik, račun in napravo; bere se
enkrat na sejo, piše po uspešnem zaključku brez odprtega dela. Ne spreminja
pravic, podatkovnih kurzorjev ali sheme baze. Okvara izbirnega branja/pisanja
zgodovine ne sme pokvariti dejanske sinhronizacije.

Po ponovnem zagonu siva kljukica pomeni »Prej usklajeno; trenutno stanje še ni
preverjeno«, z zadnjim časom v podrobnostih. Trenutna uspešna uskladitev je
zelena; napake, nerešeno delo in nepripravljenost imajo prednost. Svež pregled
brez prenosa je še vedno ločen status. Ob prvi nadgradnji brez shranjene zgodovine
aplikacija ne izmisli prejšnjega uspeha; zgodovina nastane po naslednji dejanski
uspešni uskladitvi.

21 novih kontrol PASS (17 podatkovnih, 4 UI/projekcija) in ena namerno
prilagojena kontrola ponovnega zagona PASS. Zadnja kontrola okvare izbirnega
branja: dva neuspeha testnega vira (ponavljajoča se napaka je zadela tudi nujno
branje; popravek vzorca nato ni zadel oblikovanega besedila), PASS v tretjem
poskusu. Brez četrtega poskusa. Ozka analiza 0 napak/opozoril, 9 obstoječih
slogovnih informacij. Dokazi: `build/qa/sync-cloud-history-20261027/result.json`.

### Sprejem in skupni pregled

Čarovnik in seznam čakajočih povabil po uspešnem kriptografskem sprejemu čakata
le na preverjen ciljni prostor. Novi `prepareAcceptedScope` uporablja obstoječi
currentHead/pullVerified, preverjeno vsebino in podpisane metapodatke cilja.
Po izbiri prostora nadaljuje običajni koordinator brez čakanja UI na druge
prostore, finance ali čakalne operacije računa. Sprejem ne potrdi celotnega
account.changes kurzorja ali lažno označi financ kot popolnih.

Zapis ostane atomaren prek obstoječega _applyRemote: lokalni kandidati,
tombstones, nespremenljive čakalne zahteve in pripadajoči stroški ostanejo.
Pred/med commitom so preverjeni identiteta/seja/potek/preklic, brisanje računa,
zapora nedokončane obnove, podpisana avtoriteta, trenutnost celotne vsebine,
stanje cilja, finančni kurzor in oznake izvora kurzorjev. Obstoječa živa lastna
lease se ohrani; tuje žive se ne prevzame. Stara navadna in nova kriptografska
zaporedja se obravnavajo po obstoječem preverjenem prehodu. Ni samodejnega
ponovnega pošiljanja blokiranih zapisov ali slepega vračanja pravic.

Root pri pregledu ujame nevarnost sočasnega napredka finančnega kurzorja/oznake
in premika vsebine med stranmi. Nova primerjava prepreči ponastavitev novejšega
napredka. Pri drugi napaki kontrola najprej dejansko pade, nato po zajemu stanja
pred branjem metapodatkov/strani in primerjavi po branju uspe. Bere se po 100
projekcij, seznam za atomaren zapis pa je še vedno velikosti ciljnega prostora.

31 novih različnih kontrol PASS: 19 podatkovnih/SQL, 7 prek produkcijskega
ciljnega crypto helperja z že preverjenimi testnimi avtoritetami, 3 čarovnika
in 2 seznama čakajočih povabil. Vključujejo ločitev nepovezanega synca, ohranitev
lokalnega osnutka, tekmovanja kurzorjev, napačno sejo in zaporo obnove.
To niso novi celotni podpisni/HTTP/native E2E preizkusi; preverjanje podpisov
ostaja v obstoječih produkcijskih poteh, neodvisno izvorno pregledanih.

Poskusi: glavna skupina 12 kontrol najprej testna napaka pri prevajanju,
nato napačna pot testnega transporta (11 PASS, 1 timeout), nato 12 PASS.
**Odstopanje od navodila brez ponovitev:** ob popravku skupnega testnega vira
je podagent ponovil teh 11 že uspešnih novih kontrol. To ni bilo potrebno;
evidentirano je in ni skrito v številu različnih uspešnih kontrol. Starih
zgodovinskih poslovnih scenarijev nismo ponovno izvajali. UI čakajočih povabil
je imel najprej dve napaki manjkajoče testne Directory.session, nato oba PASS.
Tekmovanje vsebinskega posnetka RED1 → PASS2; vse ostale nove ločene kontrole
PASS1. Noben četrti poskus. Dokazi: `build/qa/accepted-scope-20261027-result.json`.

Skupaj 57 novih različnih uspešnih kontrol in ena prilagojena stara kontrola
novega prikaza zgodovine. Končna skupna statična analiza 25 spremenjenih/novih
Dart datotek: 0 napak, 0 opozoril, 27 obstoječih slogovnih informacij;
`build/qa/invitation-speed-20261027/combined-analysis.log`. Root pregleda
integracijo, podagent neodvisno preveri meje pošiljanja in SQL varovala sprejema.
To ni dokaz celotne regresije ali izmerjene mobilne pohitritve. Naslednji korak
je posodobitev obeh Jivie Test po naročilu uporabnika in omejena meritev novega
pošiljanja/sprejema ter oblačka; uspešnih starih CRUD testov ne ponavljati.


## Namestitev povabil in oblačka na oba telefona, 27. oktober

Po uporabnikovem naročilu sta obe isti Jivie Test posodobljeni na 27d69c3.
Android in iOS sta pripravljala ločena GPT 6.1 Sol/high podagenta; root je pred
vsako namestitvijo preveril produktne in staging hashe, pakete, podpis in kopije.
Vsaka platforma: ena gradnja, ena namestitev, nič naših zagonov aplikacije.
Strežniških sprememb ni; obstoječi lokalni mobilni strežnik cd80678 je healthy,
TLS s testnim CA preverjen, javni capabilities HTTP200. Root URL vrne404;
veljavni NativeApiController endpoint vrne200. Noben auth poslovni RPC.

Samsung: APK7f81ab38255aa19e9671114964b465bed7012f3e14a2dac116b6f5d9ac3a1c7b,
106.511.385B; gradnja26,05s.638root/641staging vhodov; 20 nepredpomnilniških
podatkovnih datotek130.273.588B exact pred/po. UID10292, dataDir, podpis,
CA/native knjižnice isti. Originalni Google Play APK/metapodatki nespremenjeni.
Ozka analiza39datotek0errors/0warnings/52styleinfos. Odstranjenih samo
1.315.369.537B lastnega obnovljivega build predpomnilnika.

iPhone: AOTfb08a53e6e2a97c067b350038b802d66df9fdbd7f54bc5ca0eef1343e252b619,
gradnja76,14s.649root/652staging vhodov; štiri datoteke trezorja13.291.910B exact
pred/neposredno pred/po. Isti bundle, cert/profil/team, Keychain service/group,
CA in unsigned sqlite3mc/sodium. Originalni produkcijski metapodatki isti.
Prvi prednamestitveni pregled ustavljen, ker se je QA med gradnjo znova odprla;
NI bilo poskusa namestitve. Normalno zaprta samo QA, zajeta sveža stabilna
kopija, enaka prvotni, nato nova preverba in ena uspešna namestitev. Nobene
obnove stare kopije ali ponovne gradnje. Ozka analiza18vhodov0errors/0warnings/
30styleinfos. Odstranjenih934.458.862B samo lastnega derived predpomnilnika.

Sveža diagnostika ima pet statičnih časovnih oznak: priprava preavtorizacije
začetek/konec, priprava ciljnega prostora začetek/konec in odprtje ciljnega
prostora. Oznake ne vsebujejo besedil, IDjev, URLjev ali ključev. HTTP trajanja,
vrste operacij in napake ostajajo v omejenih obstoječih dnevnikih. Skupni QA
instrumenter spremeni samo staging, manifesti in patchi vključujejo vse oznake;
oba bralnika sta shematsko preverjena lokalno brez branja novih mobilnih dnevnikov.

Dokazi: `build/qa/mobile-invitation-speed-20261027/{android,ios}/final-summary.json`,
`root-source-review.json`, `server-readiness.json`. Paketi/arhiv/dSYM/izvor/kopije
ostanejo. Diagnostična bralnika po uporabnikovem preizkusu:
- `python3 build/qa/mobile-invitation-speed-20261027/android/read_diagnostics.py`
- `python3 build/qa/mobile-invitation-speed-20261027/ios/read_diagnostics.py --after-user-test`

Runtime hitrost in novi oblaček še čakata uporabnikov preizkus. Prvi korak:
odpreti obe Jivie Test, počakati približno20s, za zdaj brez novega povabila ali
ročnega synca; nato preveriti stanje. Prvi zagon nove verzije še nima stare
trajne zgodovine, če po nadgradnji še ni bilo uspešne celotne uskladitve. To ni
izguba podatkov; zgodovina nastane pri naslednjem uspešnem zaključku.


## Uporabniška potrditev pohitritve in zavrnitev povabila, 27. oktober

Uporabnik po posodobitvi potrdi, da sta ustvarjanje prostora in sprejem povabila
bistveno boljša. To je uporabniška potrditev odzivnosti, ne nova izmerjena
primerjava sekund/HTTP. V tem koraku teh uspešnih dejanj ne ponavljamo.
Naroči možnost »Zavrni povabilo« na predogledu in odstranitev spodnjega
»Nadaljuj lokalno«, ker ne opisuje dejanja na povabilu.

Izvorni pregled: spodnji gumb je v CryptoInvitationPage, tudi v načinu
lastnikove potrditve. Obstoječi Back/deferLink in clearPendingInvitation sta
lokalna odložitev/odstranitev povezave, ne strežniška zavrnitev. Zato dejanske
zavrnitve ne smemo implementirati samo s preimenovanjem gumba. Za novo
pending-only recipient decline se uporabi podpisana ukazna pot z ohranjenimi
receipts; že sprejeti/porabljeni dostopi ne smejo biti preklicani.


Izvedeno: `crypto2.invitations.decline` s capability `invitationDecline`, za
pogodbo4. Podpis veže račun/napravo/strežnik ter točen prostor, povabilo,
tokenHash in creatorProofHash. Preverjen prejemnik lahko spremeni samo pending
v declined. Ponovljen podpisan ukaz uporablja isti receipt; accepted/consumed
se zavrne brez spremembe članstva. Pošiljatelj vidi »Povabilo zavrnjeno«;
čakajoča povabila in mail se umaknejo. Glave, ključi, grants, preavtorizacijske
rezervacije in SQL članstva ostanejo nespremenjeni. Decline ni preklic dostopa.
Novega vprašanja/čarovnika za potrditev ni. Stare pogodbe1–3 in strežniki brez
capability ne dobijo navideznega lokalnega gumba za zavrnitev.

Oba prejemnikova predogleda imata gumb Zavrni povabilo; lastnikov grant in že
sprejeto povabilo ga nimata. Spodnji Nadaljuj lokalno je odstranjen; AppBar Nazaj
ostane. Po potrjenem uspehu se odstrani samo ista shranjena povezava in osveži
povzetek. Pri napaki povezava ostane. Potrjena zavrnitev in poznejši neuspeh
lokalnega čiščenja ohranita možnost zaključka, brez ponovne strežniške zavrnitve
ali samodejnega nalaganja že zavrnjenega povabila. Čiščenje je vezano na prvotni
račun in povezavo. Neodvisni pregled ujame stare bridgeLegacy podpise brez polja
recipient; popravljeno z authenticated ID lookup samo pri takih/nevezanih
prejemnikih. Običajni podpisani accountId ne doda takega lookup klica; sprejem
starih migriranih povabil ostane nespremenjen.

Lokalno: 3 novi jedrni Dart testi PASS1, 16 backend assertions PASS1 prek
pravega podpisanega NativeCryptoV2Service dispatcherja/receiptov, fresh memory
SQLite, injected actor in brez rate accounting/HTTP. Preverjeni napačen podpis,
napačen uporabnik, zamenjava creator proof, izgubljeni ACK/exact replay, drugačen
isti request, sprejem-pred-zavrnitvijo, pending filter in nespremenjeni grants/
heads/reservations/membership. 9 novih UI kontrol PASS: šest v tretjem poskusu
(prvi rezultat ni bil zajet, drugi compileFAIL zastarelega testnega admit fake,
popravek in PASS3; brez četrtega teka), nova cleanup/lifecycle kontrola PASS1 in
dve novi wizard kontroli PASS1. Znanih že uspešnih testov nismo ponavljali.

Končna analiza15spremenjenih/novih Dart datotek:0errors0warnings6obstoječih
styleinfos. Prva skupna analiza je ujela štiri opozorila kopirane testne priprave;
root odstrani neuporabljena importa/parametra (isti privzeti vrednosti) in doda
izrecen mounted guard, ki je že vsebovan v _active, ter zavite oklepaje novih
pogojev. Brez semantičnega spreminjanja potrjenih poti in brez novih runtime
ponovitev. PHP lint4modelov PASS, git diffcheck PASS. Neodvisen izvorni pregled
končnega protokola in UI brez preostalih konkretnih blokad.

Dokazi: `build/qa/invitation-decline-20261027/core-result.json`,
`ui/ui-results.json`, `combined-analyze.log`; API dodatek v
`docs/server/email-invitation-api-contract.md`. Lokalni testi niso novi native,
SMTP, HTTP, MySQL ali MariaDB testi. V tem sklopu ni gradenj, namestitev,
sprememb telefonov, produkcije ali obstoječega testnega strežnika. Telefona še
27d69c3, testni strežnik še cd80678. Za novo zavrnitev je naslednji korak po
naročilu uporabnika posodobitev testnega strežnika in obeh aplikacij.
