# Nadgradnje Jivie — izvedba 8. oktobra 2026

Uporabnik je naročil: popravki → commit/push → implementacija nadgradenj → commit/push → nova Android interna izdaja za obstoječi seznam `domači`. iOS in obvestila, ki potrebujejo lastnikov dostop oziroma fizično napravo, dobijo kratek končni seznam. Ta dokument vodi tekoče delo; odprta vrstica ni dokaz izdelane funkcije.

## Izvedbeni obseg

1. Popraviti mobilne obrazce, odrezano oznako na vrhu in prikaz ob tipkovnici; jasen uspeh registracije/verifikacije ter samodejno podaljševanje aktivne seje.
2. Organizacije z več projekti, jasno izbiro prostora in ločenimi projektnimi/finančnimi pravicami.
3. Člani gospodinjstva brez računa; ločena izvajalec in oseba, na katero se opravilo nanaša.
4. Projektne faze/mejniki, koledarski intervali, ocene ur, dnevna/tedenska razpoložljivost ter Play/Pause merjenje časa.
5. Strošek pri opravilu kot isti finančni zapis; načrtovani datum sledi roku, plačilo ostane ločeno.
6. Finančni čarovnik, mesečna pravila, napoved in potrditev plače z opomnikoma pred/po vikendu.

Osnova ostane local-first. Osebni podatki se ne delijo ob prijavi ali ustvarjanju organizacije; nove pogodbe potrebujejo strežniško preverjanje in zmožnost, stare kopije morajo ostati berljive. Vrt ostane lokalen. Mobilni levi meni je možnost za primerjavo, ne potrjena privzeta zamenjava.

## Stanje in dokazi

- Pred začetkom: šest uporabnikovih dokumentacijskih sprememb je ohranjenih. Vejo vodi `codex/vsakdan-foundation`; trenutna interna različica je `1.0.1+2`.
- Faza popravkov: izdelana; lastniki `mobile_fixes`, `auth_ui`, `session_renewal` (GPT-6.1 Sol / high). Geometrijski preizkusi zajamejo oznake/gumbe pri 320/360/390 px, odprti tipkovnici in 2× povečavi; UI potrjuje ustvarjen račun/prijavo ter potrjeno e-pošto. `auth.renew` ohrani bearer in napravo, drseče podaljša aktivno sejo, spoštuje preklic in preživi izgubljen odgovor ter restart. Starejši strežnik brez zmožnosti ostane podprt brez podaljševanja.
- Podatkovni dokaz popravkov: 35 ciljnih Dart testov PASS; 20 PHP preverjanj PASS na vsaki SQLite/MySQL/MariaDB, vključno s sočasnim preklicem in obnovo gesla. Odjemalčev celoten končni nabor, analiza ter izdajna orodja so zabeleženi v `build/qa/jivie-upgrade/`. Prvi skupni zagon je našel napako novega testnega fixture; po uskladitvi začetne identitete je celoten ponovljeni nabor PASS. Fizični S25/SwiftKey preizkus in namestitev novega API na gostovanje še nista dokazani s temi testi.
- Prvi commit/push: `54f306156658dd930f57a265f2930773768ee9eb` (`popolna predelava aplikacije`) je potrjen na `origin/codex/vsakdan-foundation`. Pred njim je celoten nabor dosegel **419 PASS / 5 opt-in HTTP preskočenih**, analiza 35 starih info brez warning/error; izdajna orodja 18 PASS, paketna orodja vtičnika 10 PASS. Mobilna različica je ostala `1.0.1+2`; izvor vtičnika s podaljševanjem je `0.6.1`, brez migracije.
- Funkcionalne nadgradnje: izdelane in preverjene; aplikacijski/vtičniški izvor je zamrznjen. `mobile_fixes` vodi časovnice, časovnik, povezani strošek ter osebne modele/shrambo/kopije; `session_renewal` organizacije, osebe in Native sync3; `auth_ui` finančni čarovnik/napoved/finance2 ter lokalizacijo. Skupne datoteke imajo enega lastnika; novi deli se usklajujejo z ločenimi modeli in part datotekami.
- Drugi commit/push: še ni izveden.
- Nova Android gradnja in objava: še nista izvedeni. Play je neposredno preverjen: zadnja `1.0.1 (2)` je aktivna; koda 3 je prosta. Predvidena funkcionalna kandidatka je `1.1.0+3`; pred uploadom stanje ponovno preverimo.
- Predaja prejšnjih klepetov za prijave/izdajo: zaključena. Prijava v Play deluje tudi v koordinacijskem klepetu. Obstoječi seznam `domači` (15) in namenski Jivie upload podpis ostaneta. Javna registracija je odložena; podaljševanje je potrjeno. iOS izvoz še potrebuje Xcode prijavo; obvestila pravne/provider/napravne korake. Druga klepeta ne spreminjata virov ali konzol.
- Dostop do cPanela: osnovni naslov je sprva zahteval prijavo zaradi manjkajočega sejnega naslova. Ozko preverjanje obstoječe brskalniške seje je potrdilo veljaven File Manager in nadaljevanje brez novega vnosa poverilnic. Sejni naslovi se ne shranjujejo v dokumentacijo. Nadgradnja testnega strežnika bo izvedena šele po končnih testih, varnostni kopiji in preverjenem paketu; starega produkcijskega Kanboarda ne spreminjamo.
- Dejansko preverjen preflight testnega gostovanja: spletni terminal deluje; `/opt/alt/php84/usr/bin/php` poroča 8.4.26, PDO MySQL in ZIP sta na voljo, `exec`/`proc_open` pa nista. Cron se upravlja s potrjenim `/bin/crontab` iz lupine, ne iz PHP. Preflight je samo bralen.
- Vmesni dokazi nadgradenj: mesečni projektni koledar ima 14 UI preverjanj; načrtovanje/stroški/shramba imajo 11 podatkovnih preverjanj. Dejanski zasebni HTTP tok preveri odvezavo faz in 6 mesečnih pravil/72 vnosov brez zavrnjenih operacij. Finančni tok preveri 48 pravil/576 vnosov na dveh odjemalcih, drugačen dejanski znesek, izgubljen ACK, ponovitev brez podvojitve in šifrirano kopijo v karanteno. To so vmesni lokalni dokazi, ne končno preverjanje ali gostovana namestitev.

Najnovejše dokaze prejšnje izdaje vodi [izdajni dnevnik](release/NOTIFICATION_RELEASE_RUN.md); vsebinske zahteve vodi [načrt prenove](RENOVATION_PLAN.md).

## Zaključni integracijski pregled

Vmesni celoten Flutter nabor je po popravku starih testnih fixtures ter nepopolnega finančnega prikaza dosegel **496 PASS / 8 opt-in HTTP preskočenih**; analiza 35 podedovanih info, brez warning/error. Posebni dejanski HTTP scenariji se vodijo ločeno. Preverjena je tudi release spletna gradnja.

Dejanski brskalniški pregled na novem izoliranem lokalnem izvoru je potrdil slovenski prikaz, ustvarjanje projekta/faze/mejnika, razpoložljivost 300 minut na teden, opravilo v fazi z oceno 60 minut in povezanim stroškom ter tekoč in preostali čas. Začasno ustavljenih 14 sekund in vsi zapisi so ohranjeni po ponovnem nalaganju. Finančni čarovnik je shranil mesečno pravilo in napoved. Najdena sta podvojen element Osebe v meniju in manjkajoč prikaz načrtovanega stroška brez datuma; oba imata dodeljen popravek pred izdajo.

Končni namenski sklop finančnega odjemalca ima **34 PASS** (vključno z dejansko SQLite hrambo, stroškom brez datuma in potrditvijo istega ID-ja); organizacijski/delilni odjemalec **49 PASS** in dodaten dejanski HTTP tok dveh računov. Strežniška zaključna matrika ima **329 kontrol na vsaki** SQLite/MySQL/MariaDB, skupaj **987 PASS**: organization79, financePlanning20, collaboration37, finance40, deletion36, push77, SMTP-race36, archive4. Ločen spletni policy2 tok ima 8 sintetičnih preverjanj PASS.

Popravka brskalniškega pregleda sta potrjena v sveži gradnji: meni ima eno Osebe; finančni pregled pokaže vse načrtovane vnose, tudi brez datuma in zunaj časovnega okna, brez napačnega praznega stanja. Potrditev drugačnega dejanskega zneska posodobi isti strošek; napoved in knjiženi seštevek ga upoštevata enkrat. Dokaz: `build/qa/jivie-upgrade/finance-browser-verified.jpg`. Mobilne širine so preverjene v widget/geometrijskih testih; IAB viewport override ni spremenil dejanske širine 1280, zato ga ne štejemo kot fizični telefonski dokaz.

Končni skupni Flutter nabor po vseh popravkih: **502 PASS / 8 opt-in HTTP preskočenih**, analiza **35 podedovanih info**, brez napak/opozoril. `flutter gen-l10n`, format spremenjenih Dart datotek in `git diff --check` uspešni. Namestitvena helperja ostaneta zunaj funkcionalnega commita do ločeno preverjenega postopka. Aplikacija je pred izrecnim izdajnim dvigom še `1.0.1+2`; SDK in `pubspec.lock` sta nespremenjena.
