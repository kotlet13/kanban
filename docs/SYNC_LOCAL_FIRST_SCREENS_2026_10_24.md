# Lokalni prikaz pred omrežnim osveževanjem

Tretji izvedbeni korak, 24. oktober 2026. Nadaljuje [skupni nadzor zahtevkov](/Users/anzenovsak/Git/kanban/docs/SYNC_ACCOUNT_WORK_COORDINATOR_2026_10_24.md). Obseg sta konkretni preostali čakanji pred uporabo običajnih zaslonov: izbira računov pred odprtjem finančnega obrazca in oddaljeno branje pred prikazom že shranjenih dokumentov.

## Finančni obrazec

Običajni obrazec se odpre iz lokalnega stanja. Priprava računov povezanega projekta steče enkrat po prvem prikazu. Uporabnik lahko medtem vpisuje besedilo; prihod možnosti ne nastavi samodejno novega računa in ne ponastavi kontrolnikov.

- Že znani računi so uporabni tudi med osveževanjem. Pri obstoječem vnosu ostane dosedanja izjema za nespremenjeni prvotni račun, tudi če je arhiviran ali trenutno ni med možnostmi. Končna dovoljenja še vedno preveri obstoječa pot shranjevanja.
- Nov vnos brez računa lahko uporabnik že izpolnjuje, shraniti pa ga lahko po izbiri razpoložljivega računa. Če pozneje izgine novo izbrani cilj, ostane v obrazcu jasno nedostopen izbor; ne zamenja se z drugim računom.
- Razpoložljivost izbire se ponovno preveri pred oddajo in po morebitnem potrjevanju pravil sodelovanja. Dostop, identiteta in revizija finančnih dovoljenj uporabljajo obstoječi `FinanceAccessGuard`.
- Zaprt obrazec in spremenjena identiteta zavržeta pozne rezultate. Nespremenjene možnosti ne povzročijo nove objave notifierja ob vsaki statusni objavi sinhronizacije.
- Obrazci zabeleženih stroškov opravil oziroma ponovitev, ki izbire računa sploh ne uporabljajo, je ob odprtju ne pripravljajo več.

Končni pregled je odkril in odpravil regresijo novega vrstnega reda: dosedanja priprava računov najprej osveži finančno politiko. Nova revizija politike, tudi ob nespremenjenih lastnih pravicah, ponastavi projekcijo in bi zaprla že odprt obrazec. Zato ima samo priprava možnosti odprtega finančnega vnosa ločeno preverjanje politike točnega ciljnega prostora. Če so uporabnikova dovoljenja enaka, samo preverjanje ne zapisuje politike ali ponastavlja projekcije; drugačna revizija odloži osvežitev možnosti do običajne sinhronizacije. Dejanska sprememba uporabnikovih dovoljenj, tudi iz urejanja v samo branje, pa uporabi dosedanjo zaščito in ustavi urejanje. Prejeti izbor se shrani samo ob ujemanju revizije in generacije dostopa. Kriptografska zavrnitev branja med pripravo izbire sproži največ eno ponovno preverjanje politike **ciljnega** prostora: zavrnitev dostopa do morebitnega nadrejenega prostora sama ni razlog za odvzem dostopa do projekta. Obstoječi drugi klicatelji priprave računov ohranijo privzeto osveževanje politike.

Ta popravek ne spreminja konzervativne meje že odprtega obrazca ob spremembi dovoljenj iz **običajne sinhronizacije**; ne obljubljamo ohranitve odprtega obrazca pri vsaki spremembi politike. Kriptografska pot priprave izbire lahko še vedno opravi svoje preverjanje in pripravi že dovoljeno delo; ne gre za nov globalni predpomnilnik ali obhod potrditve pri shranjevanju.

`showSharingForm` ima dodatne neobvezne prikazne priključke za spremembo možnosti in dovoljeno oddajo. Stari klicatelji ostanejo pri prejšnjem vedenju; identitete polj in besedilni kontrolniki ostanejo stabilni. Dodani sta dve kratki slovenski in angleški sporočili o pripravi oziroma neuspešni osvežitvi računov.

## Tabele in priloge

UI ima izrecno neobvezno lokalno predogledno pot. Običajni podatkovni `list/read/cachedRead` ostanejo najprej oddaljeni; nismo jih globalno spremenili v vračanje predpomnilnika.

Kadar ima isti račun že shranjeno podprto zmožnost dokumentov, se zaslon pripravi lokalno. Seznam tabel, polna shranjena tabela in metapodatki prilog se lahko prikažejo, medtem ko teče običajna osvežitev. Če lokalne vsebine ni, ostane nalaganje. Neznane ali neveljavne shranjene zmožnosti uporabijo dosedanjo svežo pripravo. Pred prvo dejansko oddaljeno operacijo se opravi obstoječe preverjanje zmožnosti; neuspešen poskus ne ostane trajno zapomnjen kot neuspešna prihodnja osvežitev.

Predogled je vezan na isti strežnik/račun/napravo/prostor in trenutno dovoljeni lokalni dostop. Znana označba izbrisa ali preverjeni lokalni tombstone preprečita prikaz starega zapisa, tudi za prilogo izbrisanega starša. Potrjen odvzem dostopa skrije že prikazano vsebino. Predogled tabele ne vsebuje dovoljenja za urejanje (`lease`); pridobitev dovoljenja, sveže branje in shranjevanje ohranijo stara preverjanja.

Lokalni osnutek tabele se naloži pred čakanjem na oddaljeni odgovor. Pozni odgovor ne zamenja vsebine med urejanjem, po spremembi osnutka, zapuščanju zaslona ali zamenjavi njegove identitete. Predogled prilog vsebuje samo metapodatke; ne pripravlja datotečnih bajtov in ne obide preverjanj pri prenosu oziroma izvozu.

Ni novega periodičnega preverjanja. Obstoječi signali sprememb, nadaljevanje in izrecna osvežitev ostanejo. Samo branje predpomnilnika ne oddaja dogodka, ki bi znova sprožil njegovo osveževanje.

## Pregled in preverjanje

Spremembe sta pripravila GPT‑6.1 Sol/high podagenta, tretji je opravil neodvisni izvorni pregled, glavni agent pa pregled povezav in rezultatov. Pred testi so bila odpravljena tri vprašanja dokumentne priprave: zapomnjen neuspešen poskus, obravnava odvzema dostopa med prvo pripravo in združljivost z neveljavnimi starimi metapodatki zmožnosti.

Dokazi in izvorni posnetki tega koraka so v `build/qa/local-first-screens-20261024/`, razdeljeni na `finance`, `documents` in `review`. Preverjanje uporablja nove lokalne widget/sintetične scenarije z zadržanimi odgovori in pomnilniško bazo. To preveri, da prikaz ni odvisen od zaključka omrežne zahteve; ni meritev milisekund na telefonu ali poln test E2EE prenosa med napravama.

Dokumentni del: **6 novih kontrol PASS** — tri widget kontrole v prvem poskusu, tri kontrole dejanskega lokalnega gatewayja v drugem poskusu po popravku tipa mape v sintetični pripravi testa. Prvi neuspešni dnevnik je ohranjen; runtime koda se med temi testi ni spremenila. Analiza osmih datotek nima napak ali opozoril, ostaja ena predhodna slogovna pripomba. Končni hashi in podrobnosti: `documents/summary.json` ter `documents/final-source-manifest.json` v mapi dokazov.

Finančni del: **11 različnih novih kontrol PASS** v treh omejenih sklopih. Prvih osem preveri prikaz, izbiro računa, osnutek, zaprtje in identiteto; deveta preveri dejansko repozitorijsko zavrnitev izbire z drugo revizijo brez ponastavitve projekcije. Zadnji dve na končnem popravku preverita odvzem branja in spremembo iz urejanja v branje, vključno z natančno vezavo na ciljni prostor. Vsi ti testi so uspeli v prvem poskusu. Prvih devet ni bilo ponovno izvedenih po dodanem ciljnem preverjanju politike; adapter in pričakovanje dodatnega policy klica sta posodobljena izvorno, dokazi prvotnih izvajanj pa so ohranjeni. Končna pot z enakimi pravicami je zato dodatno izvorno pregledana, ne predstavljena kot ponovljen runtime PASS. Gre za pomnilniško SQLite bazo in sintetični transport/controller, ne preizkus dejanskih kriptografskih podpisov ali sočasne običajne sinhronizacije.

Skupaj **17 različnih novih uspešnih kontrol**. Root in neodvisni podagent sta pregledala končni popravek; zadnji pregled vključuje nevarnost, da bi kriptografska zavrnitev nadrejenega prostora pomotoma zaprla projekt ali da bi dejanska izguba pravice urejanja ostala skrita. Končni ozki statični pregledi nimajo napak ali opozoril. Brez ponovitev prejšnjih uspešnih testov in brez četrtega poskusa.

## Preostale ugotovitve

Izvorni pregled običajnega odpiranja projektov, dogodkov, nakupov, idej, vrta in iskanja ni našel primerljivega novega čakanja na nepovezano omrežje. Lokalna inicializacija, branje osnutka in uporabnikova odločitev o obnovljenem osnutku niso odstranjeni. Pot opravila, ki je že prikazovala lokalne podatke, ni ponovno predelovana ali testirana.

Ločena izboljšava ostaja osveževanje že odprtih drugih urejevalnikov: projekt, dogodek, nakupi, idejnik in vrt še ne uporabljajo povsod enakega razlikovanja med nespremenjenim in urejanim osnutkom. Tega ne štejemo za odpravljeno. Odpiranje cilja obvestila še vedno preverja njegov izvor in dostop; tega preverjanja ne preskočimo zaradi hitrejšega prikaza. Nadaljnja meritev lahko preveri tudi lokalne poizvedbe pri zelo dolgih seznamih dokumentov in odzivnost med materializacijo finančnih ponovitev.

Podatki, strežniška shema, podpisi, pravila sinhronizacije in interval 30 sekund ostajajo. Telefoni, produkcija, obstoječe testne aplikacije in Docker strežniki niso uporabljeni ali spremenjeni. Prejšnji PASS in STOP3 ostajajo v zgodovini; ta korak ni nova odobritev ponovitve starih scenarijev.
