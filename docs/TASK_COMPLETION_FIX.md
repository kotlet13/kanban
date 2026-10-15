# Zaključevanje opravil — popravek15.oktobra2026

Uporabnik na Androidu v Dom → Planer → Opravila ni mogel zaključiti opravila »Preizkus push«. Po vključitvi podprojektov je ta zaslon uporabljal skupni pregled: krogec v `AllSpacesRowTile` je bil samo `Icon`, podrobnosti so prikazovale samo besedilni status, obrazec opravila pa ni imel polja za zaključek.

## Popravek

- Krogec v skupnem pregledu je dejanski preklop. Zaključeno opravilo se premakne v »Opravljeno«; tam ga je mogoče ponovno odpreti. Enako velja za opravila znotraj razširjenih projektov/oseb.
- Podrobnosti imajo možnost »Opravljeno«. Pri urejanju obstoječega opravila je enaka možnost del osnutka; shrani se z ostalimi spremembami, preklic pa je ne zapiše.
- Operacija uporablja izvorni prostor in ID opravila. V pogledu vseh prostorov ne spremeni izbranega prostora in ne zadene enakega ID-ja drugega prostora. Za lokalni neizbrani prostor in zasebno sinhroniziran osebni prostor uporablja točno določeno shrambo, obstoječo transakcijsko kontrolo identitete/pravic in odhodno vrsto.
- Bralci, arhivirani projekti ali prostori ter blokirani oziroma izbrisani prostori nimajo aktivnega preklopa. Med shranjevanjem dodatni dotiki ne odprejo podrobnosti in ne sprožijo druge spremembe. Ključi izvornih vrstic ohranijo stanje med razvrščanjem.

## Preverjanje in meja izdaje

**65 ciljnih preverjanj PASS:**30 UI za skupni pregled/izvor/privatni prostor/preurejanje ter obstoječe ozke320/390 in široke1280 postavitve,6 UI za podrobnosti/urejevalnik/status/preklic/bralca/arhiv/menjavo računa in ohranitev povezanega stroška ter29 SQLite testov za prostore/življenjski cikel/točen zapis/odhodno vrsto/rollback ob pozni menjavi identitete. Analiza spremenjenih datotek brez ugotovitev; celotna analiza ima samo10 prejšnjih info v izdajnih pripomočkih, brez opozoril ali napak. Format in diff-check PASS.

Preverjeno s sintetičnimi podatki, brez spremembe strežniške kode/sheme ali uporabnikovih zapisov. Fizični prikaz na telefonu in nova Android gradnja nista potrjena. Popravek je lokalno izveden in poslan v Git; ni nameščen v aplikaciji na telefonu.

Uporabnik je izrecno določil, da naslednjo izdajo v Google Play oddamo **šele po njegovi novi potrditvi**. Ta popravek ni v prej zamrznjenem/oddanem AAB1.9.1(29). Njegovega paketa ne spreminjamo, nove izdaje ne oddajamo in internega kanala ne uporabljamo. Verzije, podpisne konfiguracije, SDK, locks in dovoljenja ostanejo isti.
