# Stanje sinhronizacije ob naslovu

Uporabnik je 10. oktobra 2026 na Samsungu S25 opazil premikanje vsebine med osveževanjem. Zahteva je enaka za vse obstoječe prikaze sinhronizacije: oblaček ob naslovu, stalna velikost ter podrobnosti v prekrivnem oknu.

## Dogovorjeni prikaz

- Zelen oblak: uspešna sinhronizacija brez čakajočih sprememb, konfliktov ali blokiranih zapisov.
- Rdeča oznaka: napaka oziroma težava, ki zahteva ukrepanje.
- Prečrtan oblak: strežnik pri zadnjem poskusu ni bil dosegljiv. To ni dokaz stanja povezave Wi-Fi ali mobilnega omrežja.
- Dodatna ikona osveževanja: postopek teče. Prostor zanjo ostane rezerviran tudi v mirovanju.
- Nevtralna oziroma opozorilna oznaka: stanje še ni preverjeno, spremembe čakajo ali je zasebna sinhronizacija ustavljena/izključena. Odsotnost čakajočih zapisov sama po sebi ne dokazuje uspešne povezave.

Dotik odpre trenutno stanje, čas zadnjega poskusa in uspešne osvežitve ter ustrezna dejanja za ponovni poskus, konflikte in ohranitev čakajočega dela. Čas in splošni števci veljajo za povezani račun; niso ločena evidenca posameznega odprtega projekta. Finančnih zapisov v skupnem številu ne štejemo dvakrat.

Podatek o zadnjem poskusu/uspehu je vezan na trenutno sejo aplikacije in identiteto računa. Po ponovnem zagonu je neznan do novega preverjanja. Menjava računa ali pozni odgovor stare povezave ne smeta prenesti starega uspeha v nov račun.

## Obseg in preverjanje

Zamenjani so obstoječi prikazi v skupnih Opravilih, Projektih (tudi podrobnosti), Nakupih (tudi odprti seznam), dnevnem pregledu, časovnici, Osebah in Financah. Oblak je tudi ob naslovu Računa, zasebne sinhronizacije in Povezanih plačil. Povezana plačila imajo ločeno označene števce in upoštevajo tudi svojo napako, čakajočo vrsto ter nepopolno osvežitev.

Splošni in finančni konflikti vodijo v ustrezen pregled. Nastavitve vklopa zasebne sinhronizacije ter privolitev v prenos ostanejo vidne v nastavitvenem delu. Podatkov o nepopolnih finančnih pregledih in preverjanj pravic ta sprememba ne odstranjuje. Lokalnim zaslonom ter organizacijskim/zbirnim pogledom, ki prej niso imeli splošnega prikaza sinhronizacije, novega splošnega oblaka ne dodajamo.

Podatkovni del je preverjen z devetimi regresijami nad dejanskim repozitorijem: uspeh in poznejši izpad, prvi neuspešen poskus, delna sinhronizacija, obnova seje po zagonu, zasedena sinhronizacijska ključavnica, dokončanje povezanih plačil, napaka njihovega nadaljevanja ter pozni odgovori po odjavi/menjavi računa. Uspešen čas se ne zapiše pred zaključkom celotnega postopka. Dodatnih 32 testov obstoječe zasebne/skupne sinhronizacije in ponudnika povabil je uspešnih.

Prikaz ima stalno mesto **88 × 48 logičnih točk**, vključno z rezerviranim mestom osveževanja. Ciljni testi preverjajo tudi 320 px in 1,5-kratno velikost besedila. Meritve v dejanskem widgetu skupnih Opravil pri 390/1280 px potrjujejo enake meje naslova, oblaka, gumba in opravila med mirovanjem, osveževanjem in napako. Vizualno pregledani posnetki so v `build/qa/jivie-sync-status/`; nastali so v widget testu s sintetičnimi podatki, ne na fizičnem telefonu.

Končni skupni preizkus: **921 Flutter PASS / 12 opt-in preskočenih**. Celotna analiza nima napak ali opozoril; ostane 35 podedovanih informacijskih ugotovitev. Oblikovanje vseh 54 spremenjenih oziroma novih Dart datotek je preverjeno brez dodatnih sprememb.

Štiri nove regresije nad resničnim kontrolerjem preverjajo napake osveževanja v ozadju, menjavo identitete ter pozni uspeh/neuspeh stare povezave. Deset ciljnih testov prikaza in sedem integracijskih testov preverja še sprotno osveževanje odprtega okna, varen prikaz napak, finančne konflikte, povezane plačilne vrste ter en sam oblak v namiznem pogledu seznam–podrobnosti. Prejšnji testi so prilagojeni novemu dostopu do dejanj prek oblaka, pri čemer preverjanja pravic in uporabniških tokov ostanejo ohranjena.

Ta korak ne spreminja strežniške pogodbe, podatkovne sheme, SDK-ja, odvisnosti ali različice aplikacije. Priprava v izvoru ne pomeni nove objave v Googlu Play ali spremembe trenutno zagnane aplikacije na Macu.
