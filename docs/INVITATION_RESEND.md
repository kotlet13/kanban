# Ponovno povabilo istemu e-naslovu — 15. oktober 2026

Seznam povabil pri članih prostora združi zgodovinske poskuse po e-naslovu in scopeId. Presledki okoli e-naslova in velikost črk ne ustvarijo drugega prejemnika. Po preklicu in ponovnem povabilu je vidno novo povabilo z oznako »Ponovno poslano povabilo« (EN: »Invitation sent again«), njegovo trenutno vlogo in rokom. Stara preklicana vrstica je skrita. Sprejeto, poteklo ali ponovno preklicano povabilo pokaže dejanski status, ko ni več aktivnega povabila.

Gre za prikaz že prejetih zapisov iz invitations.list, ki jih strežnik vrača po created_at,id; zgodovina, kode, vrsta e-pošte in pravice se ne spreminjajo. Različni prostori, različni e-naslovi in stara povabila z uporabniškim imenom ostanejo ločeni. Če obstaja več še veljavnih povezav za isti e-naslov, ostanejo posamezno prikazane in preklicljive, da nobena veljavna povezava ne postane skrita. Preklic vedno uporabi točni invitationId in scopeId obstoječega handlerja.

35 ciljnih UI preverjanj PASS; od tega 10 novih: ponovljena dejanska pot prekliči → obrazec novega povabila → prekliči pri 320/390/1280 ter SL/EN, normalizacija e-naslova, vloge/statusi/rok, prvi poskus brez oznake ponovitve, ločeni prejemniki/prostori/stari kontrakt in več veljavnih povezav s točnim preklicem. Ohranjeni obstoječi testi povabil in menijev članov, vključno s ponovitvijo zahteve po izgubljenem odgovoru in zaščito seje. Celotna analiza: samo 10 predhodnih info v nepovezanih izdajnih orodjih, brez opozoril ali napak.

Samo izvorni popravek; ni nove native gradnje, pošiljanja resničnega povabila, strežniške spremembe ali Google Play oddaje. Zamrznjeni AAB29 ostane isti; za naslednjo oddajo je potrebna nova izrecna uporabnikova potrditev.
