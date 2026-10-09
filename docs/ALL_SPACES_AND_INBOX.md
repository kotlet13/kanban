# Vsi prostori in skladnost centra obvestil

## Naročilo 9. oktobra 2026

Uporabnik je na Samsungu pokazal prazen center obvestil pri filtru Vsa, čeprav je zvonček označeval neprebrano vsebino. Naročil je popravek ter dodatno izbiro **Vsi** v izbirniku prostorov, s skupnim pregledom opravil, financ, dogodkov in drugih področij. Oboje je izdelano; mobilna objava in fizični preizkus sta ločena od spodnjih lokalnih dokazov.

## Prikaz obvestil

Pregled kode je potrdil različno računanje: glava je štela surove neprebrane lokalne/strežniške zapise, stran pa filtrirala vidne opomnike. Že dostavljen oddaljeni opomnik nima več lokalnega razporeda, zato ga je prejšnja stran lahko skrila. Nova skupna projekcija ohrani dostavljeno vsebino, kjer je uporabniku še dostopna, ter uporablja ista pravila upravičenosti za seznam in piko. Označitev prebranosti zajame tudi združene zapise oziroma lokalno/oddaljeno zrcalo istega opomnika.

Center ostane pregled obvestil trenutnega računa in osebne naprave. Njegovi filtri Vsa/Zame/V skupnem prostoru pomenijo vrsto prejemnika, ne preklopa podatkovnega prostora. Oznaka prebrano ni zaključitev opravila ali knjiženje finančnega vnosa. Upoštevajo se odložitev, pravice do cilja, menjava računa in finančna potrdila branja. Oddaljeni opomnik brez lokalnega razporeda ima odpiranje in prebranost; napravno odložitev ponudimo samo za veljaven lokalni razpored. Ob nalaganju ali napaki finančnih potrdil branja stanje ostane neznano, napaka se prikaže in ne ustvari neutemeljene pike.

## Pogled Vsi

- Izbirna združena projekcija osebnega prostora in vseh trenutno dostopnih aktivnih skupnih prostorov tega računa. Privzeta izbira obstoječega uporabnika ostane ista. Brez računa je vključen samo lokalni osebni prostor.
- Vsak zapis nosi izvorni prostor in identiteto. Isti osebni podatek se ne podvoji iz njegove zasebne sinhronizirane kopije. Podatki drugih računov in arhiviranih, blokiranih oziroma preklicanih prostorov niso vključeni. Izbira se shrani ločeno po računu oziroma za lokalni način, brez spremembe sheme baze.
- Odpiranje in urejanje ostaneta vezana na pravi izvor in sprotna dovoljenja. Vsi je pogled, ne nov prostor ali cilj zapisa. Dodajanje potrebuje izrecno izbran stvarni prostor.
- Opravila, dogodki, projekti in nakupi imajo skupne preglede z oznako izvora. Finančni pogled vključuje samo dovoljeno vsebino, loči valute in načrtovano od knjiženega ter opozori na nepopolne prenesene podatke. Prenosi niso nov prihodek ali strošek, povezani strošek opravila se šteje iz finančnega zapisa samo enkrat.
- Vrt ostane lokalni modul. Izbira Vsi ga ne prenese na strežnik in ne spremeni njegovih pravic.

Podatkovni del je v `all_spaces_projection.dart` in `all_spaces_provider.dart`; prikaz je ločen v `presentation/all_spaces/`. Prejšnji podatki v Riverpodovem `AsyncLoading.copyWithPrevious` so izrecno izločeni, tudi kadar `asData` še vedno vrne vrednost. Odpiranje pred in po čakanju preveri isti račun, napravo in prostor. Novi zasebni zapisi brez strežniške preslikave se še vedno odprejo lokalno, urejevalnik pa zapre meja osebnega prostora ob menjavi računa.

## Kratek preizkus po naslednji mobilni posodobitvi

1. V glavi izberi **Vsi**. Preveri osebno opravilo in opravilo iz skupnega prostora; ob vsakem mora biti naveden pravi izvor. Po ponovnem zagonu mora izbira ostati.
2. Odpri opravilo iz enega prostora, ga uredi in preveri, da se je spremenilo samo tam. Za nov zapis izberi dejanski prostor v ponudbi za dodajanje.
3. V Financah primerjaj knjižene zneske po valutah in mesecih. Načrtovan strošek sodi na načrtovani datum, knjižen pa na dejanski datum plačila oziroma vnosa. Opozorilo o nepopolnem viru pomeni, da njegovih delnih podatkov ni v seštevku.
4. V centru odpri dostavljen oddaljeni opomnik in označi **Prebrano**. Pika izgine, ko ni več drugih vidnih neprebranih obvestil; opravilo ostane nezaključeno. Filtra Zame/V skupnem prostoru lahko pokažeta prazen podseznam, medtem ko pika pravilno opozarja na neprebrano obvestilo druge vrste.

## Preverjanje in meja izdaje

Končno lokalno preverjanje 9. oktobra 2026:

- `flutter test --no-pub --reporter expanded`: **677 PASS**, 9 opt-in HTTP testov preskočenih. Strežnik in pogodbe API niso spremenjeni; živega strežnika pri tej nalogi nismo uporabili.
- `flutter analyze --no-pub`: brez napak/opozoril, **37 obstoječih info**. Običajna izhodna koda ostane 1 zaradi teh podedovanih priporočil.
- `flutter build web --release --no-pub`: uspešna JavaScript spletna gradnja. Podobno kot prej Wasm preverjanje opozori na `flutter_secure_storage_web`; podpora Wasm ni potrjena.
- `JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' flutter build apk --debug --no-pub`: uspešna Android debug gradnja. Orodje opozori na prihodnjo opustitev podpore trenutnemu Kotlinu 2.2.20; ta naloga ga ne nadgrajuje. APK ni interna Play izdaja.
- `git diff --check`: brez napak. Lokalizacija je generirana z `flutter gen-l10n`, spremenjena Dart koda formatirana.

Regresije vključujejo dostavljen oddaljeni opomnik brez lokalnega alarma, prazne/prebrane/odložene vnose in piko, finančno branje, preklic dostopa, menjavo računa ter zakasnele odgovore. Agregiranje preverja dva skupna prostora in osebni način, zasebno deduplikacijo, več valut, nepopolne finance, trajno izbiro po ponovnem zagonu in izvor pri odpiranju. Dodatne regresije pokrijejo načrtovan/dejanski finančni datum, intervale dogodkov čez mesečno mejo ter prejšnje Riverpodove podatke med nalaganjem.

Vmesnik je preverjen na 320/390/1280 px v obeh temah, obstoječi testi menija/glave pa tudi s povečanim besedilom. Berljivi prikazi iz dejanskih Flutter widgetov z izključno sintetičnimi QA podatki so v `build/qa/all-spaces-inbox/`: `all-390-light.png`, `all-390-dark.png`, `all-1280-light.png` in ustrezni `finance-*.png`. Tam so tudi dnevniki celotnih testov, analize in gradenj. To niso posnetki fizičnega Samsunga.

Različica ostaja **1.1.3+6**; shema, strežnik, SDK in zaklenjene odvisnosti so nespremenjeni. Spremembe so v delovni veji `codex/all-spaces-inbox`. Trenutna aktivna Android interna izdaja še ne vsebuje teh popravkov. Objavo in fizični preizkus je treba zabeležiti ločeno od lokalne izvedbe.
