# Priprava prve izdaje Jivie

**Aktualna interna Android izdaja je 1.1.1+4.** Popravki in nadgradnje so poslani v Git, podpisani AAB je preverjen in Play potrdi aktivno izdajo. Ločeno testno gostovanje uporablja FamilyHub 0.7.0/schema11 po preverjeni kopiji in obnovi. iOS potrebuje obnovljeno Xcode prijavo in svežo gradnjo iz nadgrajene kode. [Tekoča izvedba](../UPGRADE_IMPLEMENTATION.md) in [kratek seznam zate](OWNER_NEXT_STEPS.md) imata prednost pred zgodovino spodaj.

Stanje 7. oktobra 2026: uporabnik je izbral **Jivie**, izgovorjava »dživi«. Pripravljamo novo brezplačno aplikacijo za Android/iOS z dokončno potrjenim identifikatorjem `si.triparna.jivie` in prvo različico `1.0.0+1`. Prvi podpisani Android paket je objavljen na internem testnem kanalu; testni račun še ni izbran. Aplikacija ni javno objavljena. Uporabnik je kupil domeno `jivie.app` in kot izdajatelja določil TriparNA. Nakup ni dokaz objave strani, DNS/TLS ali pravnega pregleda znamke. Pravice do imena in znamke niso pravno preverjene. Novi ločeni evidenci Jivie sta ustvarjeni v Google Play in App Store Connect; aktualno stanje podpisovanja in testnih oddaj vodi [TEST_RELEASE_STATUS](TEST_RELEASE_STATUS.md).

Kanban Connect ima svojo obstoječo Play evidenco in identifikator `com.takndev.kanbanconnect`. Jivie ne oddamo kot njegovo posodobitev in ne uporabljamo starega podpisnega vhoda kot privzetega. Nova namestitev nima avtomatičnega dostopa do lokalnih podatkov stare mobilne aplikacije. Stara aplikacija, strežnik, arhiv in podatki ostanejo ločeni. Vgrajena povezava do Kanboarda je izbirna funkcija novega odjemalca, ne preimenovanje stare evidence v trgovini.

Plačljivi dostop, naročnine ali nakupi niso predmet te izdaje. Morebitno poznejše upravljano gostovanje potrebuje ločeno zasnovo, stroške in pravila trgovin; danes ni razpoložljiva ponudba. Samostojno gostovanje zahteva združljiv strežnik in upravljanje. Ne obljubljamo gostovanja, ki bi ga razvijalec zagotavljal brezplačno za vse uporabnike.

Uporabnik je pozneje istega dne dokončno določil `si.triparna.jivie` za obe mobilni platformi. Spodnja zgodovinska preverjanja pred to spremembo imajo predhodni ID; za novi ID potrebujemo sveža dokazila v [stanju testnih izdaj](TEST_RELEASE_STATUS.md).

## Gradiva

- [Preostali koraki za lastnika](OWNER_ACTIONS.md): kratka predaja odločitev, računov in fizičnih preizkusov.

- [SL/EN besedila trgovin](STORE_LISTINGS.json): ime, App Store podnaslov/promocijsko besedilo/ključne besede, Play kratek opis in skupen daljši opis. Gre za osnutke; pred oddajo preverimo vse opisane tokove v podpisani izdaji. Ne trdijo univerzalne oddaljene dostave, javne registracije, dodatnega šifriranja aktivne baze ali popolnih kopij strežnika.
- [Javne vsebine za jivie.app](WEBSITE_CONTENT.md): praktični osnutki zasebnosti, pomoči in spletne poti izbrisa s preverjenim javnim kontaktom TriparNA; statični ZIP pripravi glavni agent, objava je ločen korak.
- [Javni izvorni paket vtičnika](../PLUGIN_OPEN_SOURCE.md): samo pregledani FamilyHub, MIT po uporabnikovem navodilu, brez Git zgodovine ali objave.
- [Zasebnost in Data safety](PRIVACY_AND_DATA_SAFETY.md): inventar iz kode, predlagana preslikava v trgovinah ter manjkajoči odgovori upravljavca.
- [Odprti pogoji in dokazila](READINESS.md): vrstni red do podpisane izdaje, izbris računa, fizični preizkusi, konzoli in pregled.
- [Platformne opombe](PLATFORM_NOTES.md): identiteta, ločen Android podpis, iOS ekipa in meje namiznih sprememb.
- [Preverjevalnik](../../tools/release/README.md): preverja izvorne identitete, ikone in javni seznam dokazil; ne objavlja, ne preverja zasebnih ključev in ne nadomesti testov.

## Preverjeni in nepreverjeni tokovi

Doslej so bili lokalno preverjeni osebni začetek brez računa, opravila/načrti/nakupi/izdatki, SQLite selitev, zasebna in skupna sinhronizacija, pravice, lokalni opomniki, šifrirana kopija in obnova. Točne dokaze in omejitve vodijo [osebni mejnik](../PERSONAL_SYNC_AND_RECOVERY.md), [družinski mejnik](../FAMILY_UPGRADE.md) in [FCM priprava](../FIREBASE_PREPARATION.md). Prejšnje debug/simulator/spletne gradnje ne dokazujejo nove podpisane mobilne izdaje. Novih rezultatov ne pripisujemo staremu preverjanju.

Pred prvo oddajo so potrebni preverjeni izvoz–uvoz prek pravih mobilnih izbirnikov, sveža namestitev in ponovni zagon brez omrežja na fizičnem Androidu/iPhonu, izbirni strežniški tok ter (če je kanal v tej izdaji omogočen) resnična FCM/APNs dostava. Self-hosted izbris Kanboard/FamilyHub računa je lokalno preverjen tudi prek dejanskega Flutter HTTP odjemalca; končna testna dokazila in preostale meje vodi [READINESS](READINESS.md). Objavljenih strani podpore/zasebnosti/izbrisa nimamo potrjenih. Odprte pogoje navajamo kot prepreke objavi, ne kot že izvedene funkcije.

## Uradna pravila, preverjena 7. oktobra 2026

Za novo telefonsko aplikacijo Play trenutno zahteva target API **36 ali več** od 31. avgusta 2026; Jivie priprava to eksplicitno nastavi. Podpisani AAB, dejanske native knjižnice in 16 KiB združljivost preverimo na končnem artefaktu. Vira: [target API](https://developer.android.com/google/play/requirements/target-sdk) in [16 KiB strani](https://developer.android.com/guide/practices/page-sizes).

Apple od 28. aprila 2026 zahteva Xcode **26 ali novejši** ter iOS **26 SDK ali novejši**, od 9. septembra pa najmanjši cilj iOS 13 ali novejši. Projektni minimum iOS 15 temu ustreza; simulator gradnja sama ne dokazuje pravilnega oddajnega SDK, podpisa ali dovoljenj. Pred oddajo ponovno preverimo [aktualne zahteve Apple](https://developer.apple.com/news/upcoming-requirements/).

Google zahtevo 12 neprekinjeno vključenih preizkuševalcev v 14 dneh objavlja za nove **osebne** razvijalske račune (ustvarjene po 13. novembru 2023). Uporabnikov račun je zdaj organizacijski; vidna prepreka pri prenesenem Kanban Connect ni dokaz, da je enaka prepreka določena tudi za novo Jivie. Pred novo oddajo pregledamo dejansko konzolo nove evidence. [Uradno področje pravila](https://support.google.com/googleplay/android-developer/answer/14151465).

Ker aplikacija podpira ustvarjanje računa, Apple zahteva začetek izbrisa v aplikaciji, Google pa pot v aplikaciji in javno spletno pot za zahtevo izbrisa računa ter pripadajočih podatkov. Odjava ali začasna deaktivacija ne zadostujeta. Vira: [Apple](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion), [Google](https://support.google.com/googleplay/android-developer/answer/13327111).

Privatnost prijavimo za vse omogočene načine in vgrajene SDK-je; samo privzeti lokalni način ni popoln inventar. Politika mora biti javno dostopna in dosegljiva iz aplikacije. Pripravimo tudi podporo, navodila in delujoč testni dostop za pregled. Vira: [App Review](https://developer.apple.com/app-store/review/), [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469). Izjava o EU trader statusu, starostni vprašalniki in distribucijske države potrebujejo resnične podatke imetnika računa; v gradivih jih ne izmišljamo.

## Izvedeno preverjanje gradiv in orodij 7. oktobra 2026

- `python3 -m unittest discover -s tools/release -v`: **10 PASS**. Negativni primeri preverijo star ID/debug podpis, napačen API, poškodovan/nepopoln PNG, prosojnost/velikost, meje SL/EN besedil, lažne URL-je, nepopolna dokazila in zavrnitev podpisne datoteke brez branja.
- `python3 -m unittest discover -s tools/firebase -v`: **7 PASS**, z avtoritativnima Jivie ID-jema iz projekta; zavrnitev strežniške poverilnice, neusklajenega projekta in delnega prepisa ostaja preverjena.
- `python3 tools/release/check_readiness.py --code-only`: **PASS** po generiranju novih native ikon. Preverja izvorne datoteke; ni analiza podpisanega AAB/archive ali fizična namestitev.
- Polni checker z nespremenjeno javno predlogo izhodno kodo **1** vrne pravilno: manjkajoče strani, identiteta/pregled/izbris računa, podpis, artefakti in fizični dokazi niso prekriti z uspehom izvornih preverjanj.
- Lokalni dokumentacijski linki in `git diff --check`: uspešno. Orodja niso zagnala omrežja, objave ali vpogleda v podpisne/server/APNs skrivnosti.

## Skupno preverjanje nove znamke

Preverjeno 7. oktobra 2026 na Flutter 3.47.2 / Dart 3.13.2:

- **83 različnih Flutter testov uspešnih**: 42 za povabila/onboarding/kopije/obnovo/datotečni I/O in 41 za zagon, lokalni CRUD, deljenje ter mobilni/namizni UI. Druga skupina uporablja dejansko novo ikono; preverja SL/EN, svetlo/temno temo in širine 320, 390 ter 1280. To je izbran regresijski sklop prenove znamke, ne ponovitev celotnega prejšnjega strežniškega mejnika.
- `flutter analyze --no-pub --no-fatal-infos`: izhod 0, brez napak in opozoril; ostane **35 obstoječih informacijskih lintov** starega dela. To ni povsem čista analiza.
- Android debug APK, iOS release brez podpisa in iOS simulator debug: uspešne gradnje. Takratna paketa potrdita predhodni ID `com.takndev.jivie`, Jivie in `1.0.0` (1); namestitev in začetni zagon v iPhone simulatorju sta uspela. [Natančna platformna dokazila](PLATFORM_NOTES.md).
- macOS debug: uspešna gradnja `Jivie.app`; pregled izhodnega plist potrdi novo ime in različico ter ohranjen `com.example.kanban` za obstoječo namizno shrambo.
- Spletna release gradnja: uspešna; izhodni naslov/manifest sta Jivie in paket vsebuje novo ikono. JavaScript je podprt; Wasm dry-run še vedno opozarja na obstoječi `flutter_secure_storage_web` in ni potrjena ciljna platforma.
- Ikona je pregledana pri 32/48 px, v svetli/temni okolici ter s približki sistemskih mask. Android ima foreground/monochrome, iOS neprosojne rastre. [Izvori, poziv in ponovljiv izvoz](../../assets/branding/jivie/README.md) ter [interaktivni oblikovni pregled](../../assets/branding/jivie/preview.html).

Po testih in native gradnjah je bil poenostavljen samo uporabniški opis povabila v SL/EN ter ponovno generirana lokalizacija; končna spletna gradnja in analiza že vključujeta ta popravek. Dnevniki in posnetki so v ignorirani mapi `build/qa/jivie-release/`. Nobena od teh gradenj ni podpisana kandidatka za trgovino. Pred oddajo ponovno preverimo pravila, fizične tokove in pogoje na končni podpisani kandidatki.

## Javna lokalna paketa

Končna statična stran je v `build/releases/jivie-website.zip` (15 datotek,8 SL/EN strani); izvorni MIT vtičnik **FamilyHub0.6.0** je v `build/releases/FamilyHub-0.6.0-source.zip` (61 datotek, samostojen README in javna pogodba). [READINESS](READINESS.md) navaja SHA256, preverjanje manifestov in končne izolirane strežniške dokaze. `tools/release`18PASS, `tools/plugin_release`10PASS, static link-builder testPASS. Paketa sta ločena: website v documentroot domene, vtičnik samo v združljivi namestitvi Kanboarda po ločenem dogovoru. Ta odstavek beleži pripravo paketov. Pozneje je bil FamilyHub nameščen na novi testni poddomeni; dejansko stanje vodi [cPanel vodič](../server/CPANEL_SETUP.md). Statična stran in javna mobilna izdaja nista objavljeni v tej nalogi, produkcijski račun ni izbrisan.

Končna integracija izbrisa in prvega vodiča: **50 Flutter enotnih/widget testov in 2 dejanska HTTP testa uspešna**, analiza brez napak/opozoril (35 obstoječih info), uspešne web release, Android debug in iOS simulator debug gradnje. Dejanska spletna aplikacija in statična stran sta pregledani na mobilni in namizni širini. Natančne meje in fizični preizkusi ostajajo v [READINESS](READINESS.md).
