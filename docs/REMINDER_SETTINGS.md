# Enoten zaslon nastavitev opomnikov — 14. oktober 2026

Uporabnik je izrecno izbral **Več → Nastavitve opomnikov**. Izvedba je v
izvoru; javni Android 1.7.1 (26) tega zaslona še nima. Funkcionalni korak ni
spreminjal gostovanja ali FamilyHub. Poznejša podpisana Android1.8.0(27) je
[oddana v javni pregled](release/REMINDER_SETTINGS_RELEASE.md); odobritev še sledi.

## Vedenje

- Zgoraj **Vsi prostori**: center obvestil, zvok, obvestila na napravi (push)
  in e-pošta. Preklop spremeni samo izbrano lastnost za trenutno dostopne
  prostore, projekte in podprte vrste obvestil. Mešano stanje je prikazano
  z minusom; naslednji dotik možnost vključi povsod.
- Spodaj razširljiv seznam lokalnih prostorov in njihovih projektov ter
  sinhroniziranih prostorov/projektnih obsegov. Skupni obsegi imajo še
  posamezne vrste: opomniki, opravila, dogodki, nakupi, Idejnik, članstvo
  in finance, skladno z zmožnostmi strežnika in pravicami.
- Lokalni projekti dedujejo lastnosti prostora, dokler nimajo lastne izjeme.
  Skupni preklop odstrani samo izjeme te lastnosti v prikazanih prostorih;
  ohrani druge lastnosti in izrecne izjeme nedosegljivih računov. Novi
  lokalni prostori dedujejo nastavitev naprave. Prihodnji skupni obsegi
  uporabljajo strežniške privzete nastavitve; množični preklop ni nov
  strežniški globalni profil.
- E-pošta zahteva SMTP na izbranem strežniku. Lokalni opomniki ne zahtevajo
  računa/Firebase. Za oddaljeni push so potrebne zmožnosti strežnika,
  konfigurirana podprta naprava ter sistemsko dovoljenje in registracija.
  Vključitev push v skupnem obsegu tudi vključi registracijo te naprave;
  izklop posameznega obsega ne odjavi naprave iz drugih obsegov. Skupni
  izklop push odjavi dostavo trenutnemu računu na tej napravi.
- **Dostava na tej napravi** na istem zaslonu kaže dovoljenja in obstoječo
  registracijo/ponovni poskus. Stara lokalna in oddaljena razdelka sta
  odstranjena iz splošnih Nastavitev. Center obvestil in urejevalnik
  oddaljenega opomnika odpirata isti zaslon; vrnitev ohrani obrazec.

## Hramba in povezava z dostavo

Obstoječi lokalni opt-in in zvok se prebereta brez pisanja ali tihe vključitve.
Nove nastavitve naprave so en JSON v SharedPreferences, zapisovan zaporedno;
ključi vključujejo identiteto prostora/računa in projekta. Ne prenašajo se
prek strežnika ali šifrirane podatkovne kopije, enako kot napravno dovoljenje.
Lokalni načrtovalnik dejansko upošteva projektne izklope/zvok; projekcija
centra in oznaka neprebranega uporabljata iste izklope centra obvestil.
Izklop ne zaključi opravila in ne označi obvestila kot prebranega.

Skupna sprememba uporablja eno SQLite transakcijo za vse ciljne obsege,
spreminja svežo shranjeno vrednost in ohrani ostale tri lastnosti. Posamezne
obstoječe `inbox.preferences.set` operacije ostanejo trajno v vrsti. Neveljaven
obseg ali napaka po prvem zapisu povrneta celotno transakcijo. Identiteta je
preverjena pred pisanjem in ob poznih odgovorih; pozna napaka ne nagovarja
novega računa. Oblika API/sheme/backup se ne spreminja. Popravljena je
validacija kategorije `ideas` v odjemalcu in v že obstoječem validatorju
čakajočih operacij šifrirane kopije.

Za skupne opomnike zvok sledi nastavitvi njihovega obsega; stari drugi lokalni
zvočni preklop ga ne utiša. Posamični vklop dostave lahko preseže prejšnji
skupni izklop na tej napravi. Izrecni oddaljeni opomniki še naprej preprečujejo
podvojitev samodejnega lokalnega opomnika. Sistemska zvočna politika/DND lahko
še vedno omejita prikaz in zvok.

## Preverjeno

- **104 ciljnih Flutter testov PASS**: nastavitve, prava SQLite transakcija
  in rollback, offline vrsta/ACK, podprte kategorije in kopije, menjave
  računov, ponovni zagon hrambe, lokalno razporejanje/preklic/zvok po projektu,
  skupni zvok in preglasitev starega izklopa, center/neprebrano ter navigacija.
- 320/390/1280 široki prikazi pri 1×/2× besedilu brez prelivanja; Android/iOS
  navigacijski widget testi. Dejanski izris s pisavami pri 390×844 je pregledan:
  `build/qa/reminder-settings/settings-390.png` (samo testni podatki).
- Format in `flutter analyze --no-pub`: brez novih ugotovitev. Ostane 10
  predhodnih info v nepovezanih `tools/release` pripomočkih.
- Sveža Android debug gradnja PASS. SDK, odvisnosti/locks, podpisna
  konfiguracija, dovoljenja in Firebase konfiguracija niso spremenjeni.

Ni fizičnega preizkusa novega zaslona ali nove dostave v tem koraku. Strežnik,
produkcijski uporabniki, spletna stran in Console so ostali isti. Po uporabnikovem naslednjem naročilu je pripravljena in **oddana javna
Android1.8.0(27)**; [izdajni dokazi](release/REMINDER_SETTINGS_RELEASE.md).
Interni kanal ostane Neaktivno; odobritev in javna27 še nista potrjeni.
