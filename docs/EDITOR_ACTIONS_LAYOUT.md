# Dejanja urejevalnikov — 12. oktober 2026

Uporabnikov telefonski posnetek je pokazal štiri navpično razporejena dejanja v
obrazcu opravila: prijava, brisanje, preklic in shranjevanje. Potrjena korekcija
premakne obstoječi gumb »Prijavi vsebino« ob naslov. Spodaj so v eni poravnani
vrstici rdeča ikona brisanja (kjer obstaja), besedilni Prekliči in ikona za
shranjevanje. Ikone imajo lokaliziran namig in najmanj48-točkovno območje dotika.
Prijave v običajnih pregledih še vedno ostanejo v meniju/podrobnostih; zastavice
se ne vračajo ob vrstice seznamov.

Postavitev se uskladi v skupnem organizer urejevalniku opravil, projektov,
dogodkov, seznamov/nakupov in lokalnih financ ter sorodnih obrazcih s funkcijo
Shrani. Splošni strežniški obrazci uporabljajo izrecni opt-in, zato prijava,
registracija, povabila, objava prostora, potrditve brisanja in sprejem pravil
ohranijo svojo semantiko. Vrt ohrani shranjevanje v glavi; podrejeni urejevalniki
uporabijo isto vrstico. Opomnik ohrani razliko med zaprtjem obrazca in preklicem
že ustvarjenega opomnika.

Gre za spremembo prikaza po izdaji **1.5.1 (21)**, pozneje objavljeno v interni
**1.5.2 (22)** od08:54. [Izdajni dokazi](release/EDITOR_ACTIONS_RELEASE.md).
Nova fizična namestitev na telefon še ni potrjena.
Shranjevanje, validacija, potrditve brisanja, busy stanje, session/finance guardi,
pravice, pogodba prijave in podatkovne sheme ostanejo isti. Sprememba ne posega
v FamilyHub ali gostovanje.

Preverjeno: **133 ciljnih UI testov PASS** (126 obstoječih in7 novih), analiza
**No issues found**, diff brez napak. Geometrija glave in ene vrstice je preverjena
na360SL,320SL z1.8-kratnim besedilom in tipkovnico,800EN ter1280SL. Ločeni testi
potrdijo izrecni klik prijave/shranjevanja, preprečeno dvojno shranjevanje med busy,
odsotnost prijave v osebnem obrazcu in izrecni opt-in splošnih obrazcev. Sintetični
posnetek `build/qa/editor-actions/editor-360-sl.png` je vizualno pregledan; to ni
fizičen dokaz nove namestitve.
