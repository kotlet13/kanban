# Jivie — kaj še urediš ti

Skupni vrstni red in potrditve vodi [izdajna checklista za Android in Apple](RELEASE_CHECKLIST.md). Spodaj ostane krajša predaja lastniku; zgodovinski izdajni dokazi ne pomenijo dokončanega novega kroga.

Stanje: **10. oktober 2026. Android 1.3.0 (15) je aktiven za domači (15), testni
strežnik uporablja FamilyHub 0.11.0/schema15, nova Mac aplikacija je odprta kot
takndev v Doma.** [Dokazi](SPACE_SHARING_RELEASE.md).

Za naslednji preizkus:

1. Na telefonu posodobi Jivie prek [internega kanala](https://play.google.com/apps/internaltest/4701286726300038561).
2. Kot lastnik prostora Doma odpri **Nastavitve prostora**, preglej dodatne pravice
   in potrdi prehod na novo deljenje. Nadgradnja strežnika ga ni potrdila namesto tebe.
3. Na Macu ostani prijavljen kot takndev. Preveriva, da drugi član vidi in ureja
   obstoječi ter nov projekt, opravila in finance; nato preveriva še povabilo samo
   v projekt brez dostopa do drugih delov prostora ter obvestila.

Prejšnji sprejemni koraki prostorov/financ ostajajo v
[izvedbenem dnevniku](../SPACES_UPGRADE_IMPLEMENTATION.md#sprejemni-preizkus-po-vključitvi-celotne-spremembe).
Javna Google Play priprava in njene odprte točke ostajajo ločene.

**Zdaj za Google Play:** pregledni račun/navodila in ciljna skupina **18+** so shranjeni. IARC je pripravljen kot osnutek za prvo javno kandidatko brez starega AI; končno oceno uskladimo po izvedbi dogovorjenih sprememb. Objavi usklajeni paket spletne strani na `jivie.app` ter opravi dogovorjene fizične preizkuse. Medijska dovoljenja, UGC ukrepi in dokončna izjava Varnost podatkov ostajajo odprti. Nadgradnja prostorov je avtomatizirano preverjena ter po tvojem nadaljnjem naročilu objavljena kot interna 1.2.0 (14). Javna izdaja ostaja ločen korak. [Aktualni obrazci in dokazi](GOOGLE_PLAY_PUBLIC_PREPARATION.md).

**Nova produkcija:** izbral si `jivie.triparna.si` s prazno bazo. Poddomena in HTTPS sta pripravljena; [stanje namestitve](../server/PRODUCTION_SETUP.md) loči končane korake od preostalih. V pripravljenih obrazcih določi/shrani geslo za skrbnika `jivie_admin` in klikni **Install**, nato geslo predala `jivie@triparna.si` in **Create**. Gesel ne pošiljaj v klepet. Pred prvim uporabniškim računom uredimo vtičnik, zasebno hrambo, pošto, ločeno produkcijsko FCM identiteto in kopijo/obnovo. Testni podatki ostanejo ločeni.

1. **iOS:** odkleni Mac in obnovi obstoječo prijavo v **Xcode → Settings → Accounts**, ekipa TriparNA (`CXNM99632B`). Nato lahko pripravimo svežo iOS gradnjo iz nadgrajene kode, preverimo Apple obdelavo in uredimo TestFlight. Prejšnja popravljena razvojna gradnja še ni uspešna distribucijska izdaja.
2. **Apple šifriranje:** odloči o izdajateljevi klasifikaciji šifriranja in državah distribucije. Kopije uporabljajo AES-256-GCM/PBKDF2, zato izjeme ne moremo samodejno označiti.
3. **Oddaljena obvestila:** Android kanal je na testnem strežniku nastavljen. Uporabnik je potrdil prikaz opomnika na zaklenjenem Samsungu S25 in klik do opravila **Test obvestila** v pravem prostoru. Minutni push cron je dodan. Po novi posodobitvi preveri [ustvarjanje, spremembo in preklic oddaljenega opomnika](../REMOTE_REMINDERS.md#preizkus-na-telefonu-po-posodobitvi). Nato ostane preizkus resnične spremembe drugega člana, dodelitve in združevanja. Apple APNs povezava ter fizični iPhone preizkus ostajata ločena koraka. [Dokazi in meje](../server/CPANEL_SETUP.md#13-fcm-na-testnem-strežniku-8-oktober-2026). Zasebna JSON in `.p8` ključa ne sodita v repozitorij, odjemalca ali klepet.
4. **Preizkus na telefonu:** nadgradi Android iz [internega preizkusa](https://play.google.com/apps/internaltest/4701286726300038561). Prostor izbereš v glavi ob ikoni; + Nov prostor je v spustnem seznamu. Meni odpreš zgoraj levo, ime Jivie je v njem. Preveri nove bližnjice, finančni račun/filter, povezavo strošek–opravilo, oceno faz ter Odloži15min po ponovnem zagonu. Odložitev velja samo na tej napravi in ni v kopiji; ne spremeni roka ali plačanosti. Preveri še obrazce s tipkovnico, podatke brez povezave/restart, kopijo–obnovo ter lokalne opomnike in klik ob zaprti aplikaciji. Preveri še obnovo gesla in običajno e-poštno obvestilo; potrditvena e-pošta je že preverjena.
5. **Vrt:** preveri [grede, sezone in zasaditve](../GARDEN.md#preizkus-nove-izdaje-na-telefonu), posebej shranjevanje vrta po vnosu kulture, preklop let ter ohranitev podatkov brez povezave. Nove vrtne kopije potrebujejo novo različico aplikacije; vrtovi ostanejo lokalni.
6. **Pred javno izdajo:** objavi pripravljeni paket **jivie.app**, nato preverimo HTTPS povezave za pomoč/zasebnost/izbris. Uskladimo dejanske Data safety/App Privacy izjave in trgovinsko predstavitev. Javna izdaja ostaja ločen korak.

Android seznam `domači` ima 15 članov. Za iOS namestitev ne potrebujemo širših upravljavskih pravic. Varno ohrani tudi kopijo Android podpisnega ključa in obnovitvenih podatkov.
