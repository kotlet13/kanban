# En meni odprtega projekta —15.oktober2026

Na odprtem deljenem projektu je bila poleg oblačka menija ScopeLifecycleMenu še druga ikona SharedContentActionsMenu ob naslovu projekta. Prva je vsebovala arhiviranje/brisanje, druga urejanje/prijavo vsebine.

Odprti projekt v SharingWorkspace zdaj združi te možnosti v en sam meni ob naslovu; naslovni dodatek ohrani samo stanje sinhronizacije. Skupni gradnik življenjskega cikla in združeni meni uporabljata ista pravila in iste obstoječe operacije. Brisanje ohrani rdečo oznako in predogled s potrditvijo; bralec ima samo prijavo vsebine. Urejanje še vedno odpre isti urejevalnik z deljenjem in načrtovanjem. Pri starem projektu znotraj gospodinjstva brisanje cilja točen projectId, ne celotnega gospodinjstva. Ločeni naslovni nadrejeni pregled organizacijskih projektov ostane lasten kontekst.

36 ciljnih UI testov PASS: novi primeri320/390/1280, en projektni meni, ohranjene možnosti in cilji, bralec, točen inline izbris; obstoječi arhiv/obnova, predogled izbrisa, urejanje/deljenje, prijava vsebine in zaščita menija ob menjavi računa ali dostopa. Celotna analiza ima samo10 predhodnih info v nepovezanih izdajnih orodjih, brez opozoril ali napak. Format in diff-check PASS. Brez fizičnega preizkusa nove postavitve ali nove native gradnje.

Popravek je v izvornem repozitoriju. Različica, strežnik/shema, SDK/locks in dovoljenja ostanejo isti. Ni nove trgovinske oddaje; naslednja Google Play izdaja potrebuje uporabnikovo izrecno potrditev. Zamrznjeni AAB29 tega popravka ne vsebuje.
