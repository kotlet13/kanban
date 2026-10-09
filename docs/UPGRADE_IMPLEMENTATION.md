# Nadgradnje Jivie — izvedba 8. oktobra 2026

**Dopolnitev po fizičnem preizkusu 1.1.6, 9. oktober: zaprti izbor prostora.** Uporabnikov posnetek S25 je pokazal previsoko ime in puščico v glavi ter manjkajočo ikono vrste prostora. Pred popravkom geometrijski test reproducira sredino besedila 12 px nad sredino znamke. `DropdownButton` pri `itemHeight: null` ovije izbrano vsebino v skrčeno kolono; izrecna višina izbrane vsebine zdaj poravna ime, ikono in puščico s preostalimi elementi glave. Kompaktni izbor ima nevtralno ploskev, tanko obrobo, 15 px besedilo in ikono za Vsi/osebno/gospodinjstvo/projekt/organizacijo/arhiv oziroma zavrnjen dostop. Dolga imena ostanejo enovrstična, celoten naziv pa je v namigu. Cilj dotika ostane najmanj 48 px in se prilagodi povečavi besedila; odprti meni in njegove funkcije so ohranjeni.

Preverjeno: **48 ciljnih UI testov PASS** (kompaktna glava in Vsi, vključno z izbirnim Android renderiranjem), analiza brez napak/opozoril s 37 obstoječimi info, format in `git diff --check`. Geometrija zajema 320/390 px, SL/EN in 1×/2× besedilo; obstoječa širša umestitev 600/1280 px ostane preverjena. Glavni agent je pregledal dejanske svetle/temne Android renderje pri 390×844, dolgo ime pri 320 px/2× ter odprti meni v `build/qa/jivie-space-picker-closed/`. **Popravek je lokalno preverjen, še brez nove Play izdaje ali fizičnega preizkusa popravka.** Različica ostaja 1.1.6+9; sheme, SDK, paketi in strežnik so nespremenjeni.

**Dopolnitev 9. oktobra: videz izbire prostora.** Po uporabnikovem posnetku S25 je izdelan zaobljen spustni meni z ikonami vrste prostora, manjšimi oznakami gospodinjstva/projekta/organizacije, modro označeno izbiro s kljukico in ločeno akcijo »Nov prostor«. Obstoječa kompaktna glava, izbira Vsi/osebno/skupno, ustvarjanje, arhiv in zavrnjen dostop ohranijo svoje vedenje. Dodana je ločena SL/EN oznaka za menijsko akcijo; prevodi so generirani. Meni uporablja svetlo/temno temo, pomično omejeno višino, prilagodljive vrstice, semantično oznako izbire ter namig za dolga imena.

Preverjeno: **59 ciljnih UI testov PASS** (46 kompaktna glava in Vsi, 13 organizacije/osebe), `flutter analyze` brez napak/opozoril z 37 obstoječimi info, formatiranje, `flutter gen-l10n` in `git diff --check`. Preverjene so telefonske širine 320/390, tablična/namizna umestitev ter 2× povečava besedila. Glavni agent je vizualno pregledal dejanska renderja pri 390×844 v `build/qa/jivie-space-picker/menu-phone-light.png` in `menu-phone-dark.png`; testni podatki ne postanejo začetni podatki aplikacije. Nativni Flutter meni ostane zasidran ob glavo in lahko sega do desnega roba telefona. Ukaze in izhode vodi `build/qa/jivie-space-picker/verification.md`. **Android 1.1.6 (9) je aktivno objavljen za domači (15), 9. oktobra ob 11:05.** Funkcionalni commit `bfc85d5`, ločena izdajna priprava `106bbef`; [podpis, artefakt in dokaz objave](release/SPACE_PICKER_RELEASE.md). Uporabnikov poznejši preizkus je razkril težavo zaprtega izbora, popravljeno v zgornji dopolnitvi. Paketi, strežnik in podatkovne pogodbe se s tem popravkom ne spreminjajo.

Najnovejša dopolnitev: [oddaljeni opomniki in aktivna interna 1.1.3+6](REMOTE_REMINDERS.md) ter [Vrt z gredami in sezonami](GARDEN.md). Celotni nabor 636 Flutter PASS; spodaj ostane zgodovina prejšnjih nadgradenj.

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
- Drugi funkcionalni commit/push: `e73cd1c80d956d35936eb2023d2eb882a6c83d90` (`popolna predelava aplikacije`) je potrjen na `origin/codex/vsakdan-foundation`; različica je bila ob njem še `1.0.1+2`.
- Nova Android gradnja in objava: **izvedeni**; Play potrdi aktivno `1.1.0 (3)` na internem kanalu. Play je neposredno preverjen: zadnja `1.0.1 (2)` je aktivna; koda 3 je prosta. Predvidena funkcionalna kandidatka je `1.1.0+3`; pred uploadom stanje ponovno preverimo.
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

## Izdajna kandidatka

Po funkcionalnem commitu je izrecno pripravljena različica **1.1.0+3**. Android release gradnja je uspela; AAB ima SHA256 `6efb71c9701f1c9261086816a72ca80231de58b1e6e94d9128cbc0bbbb65ead7` in 76.390.716 bajtov. Manifest/ID/različica/API, isti upload certifikat, bundletool, ZIP CRC, 16KiB poravnava vseh osmih 64-bitnih knjižnic in native Firebase projekt so potrjeni. Dejanski upload/aktivacija sta naslednji korak; fizična dostava FCM s tem ni potrjena.

Pomočnik staging nadgradnje ima **27 lokalnih preverjanj PASS** ter PHP/sh sintakso; zahteva zasebno polno kopijo, vse-tabelne bralne zaklepe, nespremenjeno konfiguracijo, dokaz izolirane obnove z vsemi tabelnimi hashi in pravilen vrstni red ponovne vključitve cronov. CLI PHP gostovanja ima dejansko ZIP/PDO/cURL/tokenizer, nima `exec`/`proc_open`; shell ima crontab/ps/zip. Priprava in upload vira sta potrjena, preklop še ni izveden.

Testno gostovanje je uspešno nadgrajeno na FamilyHub **0.7.0/schema11** po preverjeni izolirani obnovi 79 tabel/98 vrstic/27 zasebnih datotek. Identitete, gesla, konfiguracija in stari stolpci so preverjeno ohranjeni; izvirni cron in spletna dostopnost obnovljena. Javne zmožnosti potrjujejo nove pogodbe/funkcije, SMTP ostane, FCM je izključen. [Namestitveni dokazi](server/CPANEL_SETUP.md).

## Zaključeni izid

Android **1.1.0 (3)** je po pregledu in potrditvi aktivno objavljen na obstoječem internem kanalu; konzola kaže »Na voljo notranjim preizkuševalcem« in 8. oktober ob 12:56. Dokaz: `build/qa/jivie-upgrade/play-internal-1.1.0-3-active.jpg`. [Povezava za namestitev](https://play.google.com/apps/internaltest/4701286726300038561). Kratek lastnikov dokument je [OWNER_NEXT_STEPS](release/OWNER_NEXT_STEPS.md). Preostali iOS, ponudniški/pravni in fizični koraki so tam; z novo gradnjo jih ne predstavljamo kot izvedene.

Po objavi je ponovno preverjen izbrani seznam **`domači` s 15 člani**; drugi trije seznami ostanejo neizbrani. Dokaz brez naslovov: `build/qa/jivie-upgrade/play-domaci-15-1.1.0-3.jpg`. Izdajna priprava je commit/push `b99760d`; stari paketi in zasebne kopije ostanejo ohranjeni.

## Dopolnitev po uporabniškem pregledu — preostale vrzeli

Uporabnik je po izdaji 1.1.0 (3) opozoril na izpuščen levi mobilni meni. Ponovni pregled zahtev in kode je našel tudi delne uporabniške tokove; prejšnja skupna oznaka »nadgradnje zaključene« je bila preširoka. **8. oktobra je izrecno naročena izvedba spodnjih dopolnitev, commit/push in naslednja Android interna izdaja.**

Dogovorjeni obseg:

1. Levi zložljivi meni z neposrednim dostopom do področij na telefonu namesto stalnih spodnjih zavihkov; tablična in namizna postavitev se preverjata ločeno.
2. Finančni pogled pokaže povezano opravilo/projekt ter omogoči odpiranje konkretnega opravila v pravilnem prostoru z ustreznim preverjanjem identitete in pravic.
3. Razpoložljivi dnevni/tedenski čas se uporabi za okvirno oceno izvedbe faz; ocena ne premika izbranih koledarskih terminov.
4. Nov organizacijski projekt pred shranjevanjem jasno pokaže organizacijo in začetno vidnost; upravljanje izrecnih članstev ostane dosegljivo.
5. Ročni osebni finančni vnos omogoči izbiro računa in filtriranje po njem; napoved istega računa vključuje tak vnos ter spoštuje valuto in lokalno/zasebno lastništvo.
6. Center opomnikov omogoči trajno odložitev na tej napravi brez spremembe roka opravila ali knjiženja plačila; ponovni zagon, sprememba/izbris izvora in preklic pravic se obravnavajo izrecno.

Stanje: **vseh šest dopolnitev je izdelanih in preverjenih; Android 1.1.1 (4) je aktivno objavljen za interne testerje.** Lastništvo: `upgrade_omissions_planning` (meni, faze, vidnost), `upgrade_omissions_finance` (finance, skupna lokalizacija), `remaining_reminders` (odložitev). Vsi uporabljajo GPT-6.1 Sol / high; glavni agent vodi dokumentacijo, integracijo in izdajo. Začetno delovno drevo je čisto, HEAD `42f3a29`. Google Play je ponovno preverjen: 1.1.0 (3) ostaja aktivna na obstoječem internem kanalu.

Lokalne odložitve so napravna nastavitev, shranjena ločeno od izvornih zapisov. Ne vključijo oddaljene dostave in se ne prenašajo v šifrirano kopijo; izvorni roki in obstoječa strežniška pravila se ne spreminjajo. Izvoz ne spreminja pogodbe prenosne kopije 3. iOS, FCM/APNs, javna objava in fizični telefonski preizkusi imajo še vedno svoja ločena merila.

Končno skupno preverjanje dopolnitev: **544 Flutter PASS / 8 opt-in HTTP preskočenih**, analiza **37 obstoječih info**, brez napak/opozoril. Datoteke z informacijskimi ugotovitvami v tej dopolnitvi niso spremenjene. `flutter gen-l10n`, format 45 spremenjenih/novih Dart datotek, `git diff --check` in izvorni izdajni preverjalnik so uspešni. Izdajna orodja imajo 18 PASS. Ciljni dokazi: načrtovanje/navigacija 83 različnih preverjanj, finance 44 + 12 geometrijskih preverjanj, odložitve 32. Končni dnevniki so v `build/qa/jivie-followup/`; izvorni ciljni dnevniki tudi v `build/qa/omissions-1.1.1/`.

Neodvisni pregled je pred zamrznitvijo odpravil nepravilno lokalno razreševanje zasebnega opravila in nepreklicane OS alarme ob napaki SQLite. Regresije preverijo dejanske preslikane ID-je, trajni ponovni zagon, finance petek/ponedeljek in potrditev iste plače, dotik Odloži v centru, zavrnjen/svež oddaljeni dostop ter ohranitev roka in prebranega stanja. Strežniška koda, API pogodbe, lokalna schema6/JSON4/prenosna3 ter SDK/paketi ostanejo nespremenjeni.

Funkcionalni commit/push dopolnitev: **`cbcb29d3e39bd5dc411e4c4199bead2b6ccbbe98`**, sporočilo `popolna predelava aplikacije`, veja `origin/codex/vsakdan-foundation`. Šele nato je izrecno pripravljena različica **1.1.1+4**; SDK/dependency lock, server in stare datoteke izdaj ostanejo nespremenjeni. Nova podpisana gradnja in Play aktivacija še sledita.

Podpisana Android gradnja 1.1.1 (4) je uspešna (42,1 s), prav tako spletna release gradnja (24,8 s). AAB `build/releases/Jivie-1.1.1+4-android-firebase.aab` ima **76.703.654 bajtov** in SHA256 **`16bc3d8013401c1c9bf24bd6354c70e1e3c710df0e71c0e25853aa4f286c5f1f`**. Izvorni commit je `cbcb29d`, izdajna priprava/build commit **`e9d676f93745d769d3b84a0e570dca9ade5f2f0d`**; oba sta pushana. Manifest potrdi `si.triparna.jivie`, 1.1.1/kodo4, minAPI24/target36. Bundletool, ZIP CRC, jarsigner, isti upload certifikat, PAGE_ALIGNMENT_16K in vseh 8 64-bitnih knjižnic so potrjeni. Native Firebase projekt je isti, client.json ni asset; fizična dostava ni dokaz gradnje. Play upload in aktivacija se potrdita po obdelavi.

### Potrjena interna objava dopolnitev

**Android 1.1.1 (4) je aktiven** na istem internem kanalu: Google Play kaže »1.1.1 (4) — dopolnitve Jivie«, »Na voljo notranjim preizkuševalcem« in **8. oktober ob 15:03**. Naloženi sveženj je potrjeno koda4/1.1.1, min24/target36; pregled konzole ne pokaže spremembe podprtih naprav. Obstoječi izbrani seznam je samo **domači (15)**; brez dodajanja naslovov ali širjenja pravic. [Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561). Dokaz: `build/qa/jivie-followup/play-internal-1.1.1-4-active.jpg`; binarni dokazi: `android-artifact-evidence.json` v isti mapi. Google opozori, da prikaz posodobitve običajno potrebuje do ene ure, občasno dlje. Fizična nova namestitev/preizkus ostaja uporabnikov naslednji korak, iOS in oddaljena dostava pa nista potrjena s to objavo.

Kratek preizkus: na telefonu odpri meni zgoraj levo → Osebe/Finance/Vrt; pri finančnem strošku odpri povezano opravilo; vnesi ročni strošek z računom in preveri isti filter/napoved; na fazi preveri oceno trajanja; pri novem projektu preveri organizacijo/vidnost; odloži opomnik za15min in ponovno zaženi aplikacijo. Rok opravila in plačanost se ne spremenita. Napravna odložitev se ne prenese v kopijo ali na drugo napravo; nov odlog oddaljenega zapisa potrebuje sveže preverjanje dostopa.

## Kompaktna glava na telefonu — uporabnikov posnetek 8. oktobra

Uporabnik po preizkusu 1.1.1 (4) zahteva premik izbire prostora v zgornjo vrstico ob ikono. Ime Jivie ostane v odprtem meniju; ločena vrstica prostora in gumb za dodajanje se odstranita s telefona. Spustni seznam dobi **+ Nov prostor**. To odstrani odvečno vrstico in odmik pred vsebino, ob ohranjeni jasno vidni izbiri prostora.

Izvedba je izdelana in preverjena; **Android 1.1.2 (5) je aktivno objavljen za interne testerje.** Telefonski kompaktni izbor uporablja isti nadzorovani prostor kot prej; akcija za ustvarjanje ni izbrani prostor in se po preklicu ne sme prikazati namesto njegovega imena. Nov prostor uporablja obstoječe gospodinjstvo/deljeni projekt ter organizacijo ob ustrezni strežniški zmožnosti. Brez računa odpre obstoječo povezovalno pot, osebno delo ostane lokalno. Tablica in namizje ohranita umestitev izbire v vsebini; nova možnost v seznamu nadomesti ločeno dodajalno tipko.

Lastnik kode in lokalizacije je `upgrade_omissions_planning` (GPT-6.1 Sol / high); glavni agent vodi integracijo, dokumentacijo in naslednjo interno izdajo. Začetni HEAD je `b174ca4`, drevo čisto. Strežnik, podatkovne pogodbe, SDK in paketi se ne spreminjajo. Končne geometrijske/vedenjske teste, render in objavo zapišemo po preverjanju.

Končni nabor kompaktne glave: **565 Flutter PASS / 8 opt-in HTTP preskočenih**, analiza **37 obstoječih info**, brez napak/opozoril. Ciljni nabor ima 64 PASS, končni test glave 21 PASS. Prvi skupni tek je našel zastarel startup test, ki je še zahteval ime v zaprti glavi; po uskladitvi iste zahteve je ponovljeni celoten nabor uspešen. Produkcijska koda med ponovitvijo ni bila spremenjena. `flutter gen-l10n`, format in `git diff --check` ter izvorni release checker so uspešni. Dnevniki so v `build/qa/jivie-compact-header/`; vizualno pregledan render **`header-mobile.png`** pokaže prazen Koledar pri 390×844, brez druge vrstice prostora. To je Flutter render, ne fizična namestitev.

Funkcionalni commit/push kompaktne glave: **`3d504c41d95de642d3d04bfd26cc19ed5fd230e2`**, sporočilo `popolna predelava aplikacije`. Šele nato je izrecno pripravljena kandidatka **1.1.2+5**. Gradnjo, podpis in Play objavo preverimo ločeno; stari paketi se ohranijo.

Izdajna priprava **`112140750c493cd8fa4c489579cc8a105939d02a`** je pushana. Android 1.1.2 (5) release je zgrajen v 40,7 s, spletni release v 25,1 s. AAB ima **76.725.428 bajtov** in SHA256 **`9c449f5363f24b3f2346b18102e3c4378b6872b27de48f419d6ef7cafe810786`**. Manifest potrdi isti `si.triparna.jivie`, 1.1.2/kodo5 in min24/target36. ZIP/bundletool/jarsigner, isti upload certifikat, 16KiB vseh 8 64-bitnih knjižnic ter isti native Firebase so potrjeni. Server, SDK/dependency lock in stari artefakti ostanejo nespremenjeni. Play je sprejel upload za obdelavo; aktivacijo potrdimo ločeno.

### Potrjena objava kompaktne glave

Google Play potrdi **Aktivno / 1.1.2 (5) — kompaktna glava**, »Na voljo notranjim preizkuševalcem«, **8. oktober ob 17:39**. Dokaz: `build/qa/jivie-compact-header/play-internal-1.1.2-5-active.jpg`. Izbran ostaja samo **domači (15)**; drugi seznami niso vključeni. Konzola potrdi sveženj koda5/1.1.2 in nespremenjeno podporo naprav. [Posodobitev aplikacije](https://play.google.com/apps/internaltest/4701286726300038561). Novi fizični prikaz na S25 uporabnik še preveri; render je vizualni lokalni dokaz, ne dokaz nove fizične namestitve. iOS/FCM/APNs imajo prejšnje ločene odprte korake.

Preizkus nove glave: prostor izberi v zgornji vrstici ob ikoni, odpri spustni seznam → + Nov prostor, izberi vrsto in ime. Po preklicu ostane izbran prvotni prostor; brez računa se odpre povezava. Ime Jivie je v odprtem levem meniju. Osebno ustvarjanje podatkov še vedno deluje brez računa in povezave.
