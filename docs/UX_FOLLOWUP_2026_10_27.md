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
