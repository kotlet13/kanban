# Privzeti zvok — Android1.9.1(29) / FamilyHub0.14.1

15. oktober 2026. Uporabnik zahteva privzeto vključen zvok in izrecno ohranitev vseh obstoječih nastavitev. Apple/TestFlight ostane odložen; Android izdaja je izključno javna.

## Vedenje in ohranitev

Nove oziroma manjkajoče lokalne in skupne nastavitve zvoka uporabijo `true`, tudi pri opomnikih in Idejniku. Skupni opomnik brez lokalno prenesene preference uporablja isti privzeti zvok. Strežnik ponovno preveri trenutno nastavitev pred dostavo.

Vsaka shranjena vrednost `sound=false` ali `sound=true` ostane nespremenjena, vključno s starimi celotnimi JSON nastavitvami, ki so materializirale stari privzeti izklop. Njihovega izvora ni mogoče zanesljivo ločiti. Ni migracije, backfilla ali prepisovanja obstoječih nastavitev. Manjkajoče polje deduje novi privzeti zvok. Lokalni opt-in, sistemska dovoljenja in nastavitev Androidovega kanala ostanejo veljavni.

## Ciljno preverjanje

- 51 Flutter testov PASS: nove/manjkajoče nastavitve, lokalne legacy/v2 in skupne shranjene vrednosti, ohranitev izklopa ob spremembi drugega kanala, načrtovalnik in dejanski native parametri ter UI brez zapisovanja ob branju.
- Analiza spremenjenih datotek brez ugotovitev; celotna analiza ima istih10 predhodnih info v nepovezanih izdajnih pripomočkih, brez napak/opozoril.
- Strežniška ciljna integracija178 kontrol PASS na MariaDB10.11.19/schema18: kategorije, shranjeni izklopi, branje brez nastajanja preference vrstic, sveže preverjanje pred dostavo, Android/APNs parametri. Sintetični podatki; brez pošiljanja uporabnikom.

## Izdajni status

Funkcionalni popravek je lokalno pripravljen. Android29, javni FamilyHub0.14.1 in namestitev code-only popravka še niso potrjeni. Shema ostane18; nobena migracija ni predvidena.

Svež read-only Google Play potrdi prejšnjo **1.9.0(28) Na voljo v Googlu Play**, datum15.okt07:58,100%,1država/regija. Prejšnji zapis »v pregledu« je zgodovina. Nova posodobitev uporablja isto galerijo in obstoječo Slovenijo; interni kanal ostane neaktiven.
