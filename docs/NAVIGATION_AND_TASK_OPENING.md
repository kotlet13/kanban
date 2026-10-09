# Vračanje na telefonu in odpiranje opravil

Uporabnik je 9. oktobra 2026 po preizkusu Android 1.1.4 (7) naročil dva popravka: sistemski Nazaj naj odpre prejšnji zaslon, na začetnem zaslonu pa zahteva ponovni pritisk za izhod; dotik opravila ne sme čakati približno tri sekunde na prikaz.

Stanje: izvedba je izdelana in lokalno preverjena na `codex/navigation-task-opening`, izhodišče `main` / `6fdd3aa`. Različica ostaja `1.1.4+7`. Nova mobilna izdaja še ni objavljena. Ta dokument loči dokaz iz kode, avtomatizirane preizkuse in še čakajoči fizični preizkus.

## Ugotovljena vzroka

- Glavni organizator spreminja področja in izbrani projekt/seznam v stanju enega zaslona na poti `/`. Usmerjevalnik zato nima prejšnje poti, na katero bi sistemski Nazaj lahko vrnil uporabnika.
- Odpiranje skupnega opravila iz pogleda Vsi uporablja pot za zunanja obvestila. Pred prikazom dialoga čaka na pogajanje o zmožnostih, seznam prostorov in sinhronizacijo računa, vključno z drugimi prostori. To je nepotrebna omrežna odvisnost za že prikazano opravilo.
- Lokalni urejevalnik opravila pred prikazom zahteva seznam lastniških ID-jev prek zaporedne vrste shrambe. V povsem lokalnem prostoru je ta podatek že v naloženi projekciji. Zasebni združeni prostor mora še naprej razlikovati lokalne in sinhronizirane zapise.

Približno tri sekunde je uporabnikova meritev na telefonu. Pregled kode potrjuje čakanje; ne predstavlja profiliranja njegove naprave.

## Dogovorjeno vedenje

Nazaj naj najprej zapre odprti urejevalnik, dialog ali levi meni. Nato naj vrača med obiskanimi področji, projektom/seznamom in povezovalnimi pogledi. Vrnitev iz vira, odprtega v pogledu Vsi, mora obnoviti dejanski izvorni pogled. Zgodovina ne sme obnoviti podatkov prejšnjega računa ali preklicanega prostora.

Na začetnem zaslonu Android telefona prvi pritisk pokaže kratko plavajoče sporočilo **Pritisni še enkrat za izhod**. Ponovni pritisk v dveh sekundah zahteva sistemski izhod. Potek okna, navigacija, odprtje dialoga ali prehod aplikacije v ozadje ponastavijo to možnost. Vračanje na drugih platformah ne sme uvesti samodejnega zapiranja aplikacije.

Že vidno opravilo v dovoljenem prostoru se prikaže iz lokalne projekcije. Obnovitev podatkov oziroma pravic teče ločeno in omejeno, brez sinhronizacije celotnega računa ob vsakem dotiku. Znana zavrnitev dostopa, menjava računa ali izbris zapisa morajo onemogočiti nadaljnji prikaz. To ni nova pot za finančne zapise ali zunanja obvestila; njihova obstoječa preverjanja ostanejo.

## Izvedba

Stanje cilja in zgodovina sta izločena v `organizer_navigation.dart`, sistemski Back pa v `organizer_back_boundary.dart`. `PopScope` vnaprej določa možnost vrnitve; opazovalec Navigatorja ponastavi izhod ob odpiranju/zapiranju drugih poti. Android manifest omogoča sodobni povratni klic. Področja in povezovalni podpogledi zapisujejo cilje, prehod med Vsi in konkretnim prostorom pa vključuje preverjanje identitete in generacije navigacije. Zakasnela obnova ne sme prepisati nove izbire.

Pogled Vsi za opravila uporablja ločen `showVisibleTaskTarget`. Dialog odpre že naložene nefinančne podatke; hiter drugi dotik ne odpre dodatnega dialoga. Preverjanje v ozadju uporabi `scopes.list` in največ eno stran sprememb iz konkretnega prostora (100 zapisov), z največ petimi sekundami čakanja na omrežje. Ne pošilja odhodnih operacij in ne premika kazalca običajne sinhronizacije. To ni zagotovilo, da pri več kot eni strani sprememb posodobi prav vsako tarčo; nadaljnjo popolnost zagotavlja običajna sinhronizacija. Čakajoči osnutki in njihovi revizijski podatki ostanejo ohranjeni.

Pred zapisom odgovorov se v transakciji preverita identiteta in dejansko shranjena blokada prostora. Pozni odgovor ne obnovi znanega preklica. Vmesna naložitev projekcije pokaže stanje nalaganja, ne starega zasebnega naslova ali lažnega izbrisa. Finančni prikaz in odpiranje zunanjih obvestil uporabljata prejšnjo pot.

Lokalni urejevalnik uporabi lastniške ID-je naložene projekcije. Zasebni urejevalnik ohrani lastniško preverjanje, SQLite pa za to bere samo stolpec ID iz lokalnega prostora. Ne dekodira več celotnih vsebin vseh zapisov. Validacija običajnega branja in shranjevanja ostane.

## Delitev dela

- `phone_back_navigation` — zgodovina, sistemski Nazaj, povezovalni podpogledi, lokalizacija in regresijski testi usmerjevalnika.
- `task_open_latency` — odprtje že vidnega opravila, omejena osvežitev, lokalni urejevalnik in testi počasnega omrežja.
- `inbox_visibility_fix` — neodvisen bralni pregled odpiranja, identitete in dostopa.
- Glavni agent — usklajevanje, pregled, dokumentacija in skupno preverjanje. Podagenti uporabljajo GPT-6.1 Sol / high.

## Merila preverjanja

- Dejanski sistemski Back prek GoRouter: vrstni red področij, projekt/seznam, meni/dialog in dvojni pritisk z iztekom okna.
- Vrnitev iz Vsi v vir in nazaj, varna menjava računa ter preklic dostopa.
- Odprtje opravila, ko omrežni odgovor še čaka; lokalno delo brez povezave in brez čakanja za vrsto shrambe.
- Zakasnela zavrnitev ali odgovor po zaprtju dialoga/menjavi identitete ne odpre novega dialoga in ne obnovi dostopa.
- Finančni zapisi ter odpiranje iz zunanjega obvestila ohranijo svoje ločene pravice.
- Format, lokalizacija, analiza, prizadeti in celoten Flutter nabor; gradnja prizadetih platform po integraciji.

Fokusni dokazi: **51 PASS** za odpiranje, pravice, počasno omrežje in zasebno lastništvo (`build/qa/navigation-task-opening/task-opening-focused-tests.log`); **50 PASS** za navigacijo in povezovalne regresije (`navigation-focused.log`). To sta ločena sklopa, ne seštevek celotnega nabora.

UI preizkus pokaže opravilo po prvem izrisu (simuliranih 16 ms), čeprav odgovor čaka tri sekunde ali sploh še ni zaključen. To je dokaz odstranitve čakanja v uporabniškem toku, ne meritev hitrosti na Samsungu. Sistemski Back je preverjen v 16 novih testih prek dejanskega aplikacijskega GoRouterja, `handlePopRoute` in kanala za začetek/potrditev predictive geste; fizična gesta Android predictive Back še potrebuje preizkus naprave.

## Končno preverjanje

- **715 Flutter PASS / 9 opt-in HTTP preskočenih**, brez napak; `build/qa/navigation-task-opening/flutter-test.log`.
- Analiza: **37 obstoječih info, brez napak/opozoril**; `flutter-analyze.log`. Ukaz zaradi informacijskih lintov vrne status 1. Vmesna analiza je našla odvečen uvoz v novem testu in manjkajoče zavite oklepaje; pred končno analizo sta odpravljena.
- Uspešna **Android debug** gradnja (`android-build.log`, 13,0 s Gradle) in **spletna release** gradnja (`web-build.log`, 24,8 s). Opozorila o prihodnji podprtosti Android orodij ter spletni Wasm diagnostiki niso nova potrditev podpore Wasm; SDK/paketi niso nadgrajeni.
- Generirana lokalizacija, format spremenjenih Dart datotek in `git diff --check` so preverjeni. Neodvisni pregled ni našel preostalih blokirajočih napak v novi poti odpiranja in pravic.

Strežnik, API pogodbe, sheme, odvisnosti, različica ter trenutno objavljena interna izdaja so nespremenjeni. Zasebni urejevalnik še vedno spoštuje zaporednost lastniškega branja v lokalni shrambi; optimizacija odstrani dekodiranje celotne zbirke, ne varovala konsistence. Izvorne kode pred objavo ni dovoljeno enačiti s posodobitvijo uporabnikovega telefona.

Preizkus naslednje izdaje na S25: odpri Nakupi → seznam → drugo področje, nato se vračaj z Nazaj; preveri zapiranje odprtega menija/dialoga, vrnitev Vsi → projekt → Vsi, potek dvosekundnega okna ter drugi pritisk za izhod. V Vsi večkrat odpri lokalno, zasebno in skupno opravilo, tudi brez povezave. V tem koraku nova interna izdaja še ni objavljena.
