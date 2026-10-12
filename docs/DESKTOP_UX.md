# Jivie za macOS, Windows in Linux

12. oktober 2026 — uporabnik je naročil namizni UX z macOS kot prvo oblikovno
podlago in isto uporabno razporeditvijo za Windows/Linux. Izvedba je v skupnem
Flutter odjemalcu, s platformnimi prilagoditvami prikaza. Podagenti Sol6.1/high
so pripravili urejevalnike, vsebinske prikaze in menije; glavni agent je povezal
okvir, navigacijo, iskanje, prevode in preverjanje.

## Namizna uporaba

- Leva navigacija vsebuje izbor prostora, Utrip, obvestila, razširljiv Planer
  (Opravila/Koledar/Idejnik) in Prostor s področji izbrane vrste prostora.
  Račun, nastavitve prostora, kopije in nastavitve so neposredno med pripomočki;
  Več ni glavni namizni zavihek. Mobilni štirje zavihki ostanejo isti.
- Iskanje uporablja dovoljena lokalna in deljena bralna prikaza ter shranjene
  ideje. Rezultat ohrani konkretni izvor in ID; pozni odgovor drugega računa
  se ne uporabi. Finančne omejitve in preklicane pravice niso obite.
- Novo odpre izbiro vrste zapisa; v Vsi zahteva konkreten prostor. Obstoječi
  obrazci in kontrolerji ostanejo odgovorni za zapis, pravice in strežniška pravila.
- Urejanje opravil, dogodkov, projektov, financ in sorodnih CRUD zapisov se
  odpre ob vsebini. Svoj Navigator zapre urejevalnik, ne aplikacije. Finančni
  podatki, povezave, prijave in sprejem pravil uporabljajo iste tokove.
  Obrazci računov, povabil ter potrditev ostanejo modalni.
- Navigacija med področji ohrani odprti obrazec. Nova vrstica ne zamenja njegovega
  osnutka; Novo je med urejanjem izklopljen. Menjava prostora zahteva Shrani ali
  Prekliči. Ob dejanskem preklicu pravic/menjavi identitete obstoječi varovalni
  gradnik zapre samo podrobnosti. Pred Shrani ni zapisa.
- Stranska navigacija in podrobnosti imata prilagodljivo širino. Pri manjšem
  oknu se navigacija skrči, podrobnosti pa uporabijo osrednjo površino. Isti
  obrazec z isto vsebino ostane živ pri prehodu nazaj v široko okno.
- Utrip uporablja stolpce in največ pet dejanskih zapisov na sklop. Projekti
  imajo kompakten izbor in prilagodljive podrobnosti; finance razvrstljive
  tabele, dostopne s tipkovnico. Razvrščanje zneskov loči valute in ne izmišlja
  seštevkov; desni klik izvede samo trenutno dovoljeno obstoječe dejanje.
- Idejnik ima na širokem namizju orodja/podatke ob veliki risalni površini.
  Pan/zoom, undo/redo, fotografije, osnutki ter stanje platna preživijo spremembo
  širine; manjše okno uporablja iste elemente in isto tablo.

## Platforme

macOS uporablja Flutter `PlatformMenuBar` z domačimi meniji aplikacije, urejanja,
prikaza in okna ter ⌘ bližnjicami. Sistemski Quit/Hide/Minimize/Zoom/Full Screen
ostanejo domača dejanja. Windows in Linux uporabljata menije v oknu in Ctrl
bližnjice. Nova dejanja so Novo, Iskanje, Nastavitve in vrnitev; urejanje besedila
deluje prek dejansko osredotočenih Flutter dejanj. Urejevalnik besedila in
Idejnikov undo/redo imata prednost pred splošnimi bližnjicami. Ukazi ne odprejo
novega obrazca ali navigacije za že odprtim modalnim dialogom.

Ohranjena so sistemska okna/krmilniki ter namizne identitete. Izhodišče novega
okna je1280×800, minimum640×480; shranjene veljavne velikosti ostanejo uporabljene.
Na Windows minimum sledi DPI; Linux ohrani obstoječi GTK/GNOME header oziroma
naslovno vrstico upravljavca oken. Namizni način se določi po platformi in ostane
namizni tudi po zmanjšanju okna; širok Android/iOS uporablja dosedanji tablični prikaz.

Podlaga: [Apple macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/),
[Apple sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars/),
[Windows navigation](https://learn.microsoft.com/en-us/windows/apps/design/basics/navigation-basics)
in [GNOME navigation](https://developer.gnome.org/hig/guidelines/navigation.html).
To ni potrdilo o popolni skladnosti ali trgovinski odobritvi.

## Dokazi in meje

- **695 skupnih UI/projekcija/tema testov PASS /1 opt-in preskok** vključuje
  44 novih namiznih preizkusov ter obstoječe mobilne in finančne/regresijske tokove.
- Dodatni preizkus **640×480 pri2× besedilu PASS**: koledar, finance, Novo ter
  izrecen Prekliči. Končnih6 shell preizkusov PASS.
- Analiza celotnega projekta: **No issues found**. Dart format in diff check PASS.
- **Native macOS Debug build PASS** s svežim izoliranim Xcode DerivedData in
  `CODE_SIGNING_ALLOWED=NO`. Bundle ostaja `com.example.kanban`,1.7.0(25).
  Običajni `flutter build macos` je naletel na stari modulni predpomnilnik
  `firebase_core_objc`; sveža gradnja istega izvora je uspešna brez spremembe
  SDK, odvisnosti ali projektnih podpisnih nastavitev.
- **Windows/Linux izvorni gradnji in fizična namizna uporaba niso preverjeni**:
  gostitelj je Mac. Testi preverjajo platformne postavitve/menije in dejanske
  lokalne zapise, ne zagona Windows/Linux binarnih paketov.
- Devet widget prikazov v `build/qa/desktop-ux/` pokaže Utrip, odprti urejevalnik
  in finance za tri platforme. Uporabljajo izolirane vzorčne podatke; niso
  posnetki fizičnih oken. Mac font je naložen iz sistema, Windows prikaz uporablja
  testno nadomestno pisavo. Bralniki zaslona in sistemski meniji med fizično
  uporabo imajo še ločen preizkus.

Android/iOS gradnja, javna objava, spletna stran, FamilyHub, gostovanje, sheme,
kopije, poverilnice, podatki in dovoljenja niso spremenjeni. Različica izvora
ostane1.7.0+25; aktivni interni AAB25 še naprej vsebuje predhodni izvor50fd551/
metadatafa809b8. Namizna razvojna gradnja ni nova podpisana distribucija ali
namestitev na uporabnikov profil.

Preverjevalni dnevniki in pregled hashov so v `build/qa/desktop-ux/`.

```sh
flutter test --no-pub test/organizer/ui test/organizer/data/utrip_projection_test.dart test/jivie_design_theme_test.dart
flutter analyze --no-pub
JIVIE_UI_CAPTURE=1 flutter test --no-pub test/organizer/ui/desktop_shell_test.dart
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/qa/desktop-ux/macos-derived \
  CODE_SIGNING_ALLOWED=NO build
```
