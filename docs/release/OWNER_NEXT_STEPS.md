# Jivie — kaj še urediš ti

Stanje: 8. oktober 2026. **Android 1.1.0 (3) je aktivno objavljen za interne uporabnike; testni strežnik je nadgrajen na FamilyHub 0.7.0.** Podrobni dokazi in omejitve so v [izdajnem dnevniku](NOTIFICATION_RELEASE_RUN.md) in [seznamu lastnikovih korakov](OWNER_ACTIONS.md).

1. **iOS:** odkleni Mac in obnovi obstoječo prijavo v **Xcode → Settings → Accounts**, ekipa TriparNA (`CXNM99632B`). Nato lahko pripravimo svežo iOS gradnjo iz nadgrajene kode, preverimo Apple obdelavo in uredimo TestFlight. Prejšnja popravljena razvojna gradnja še ni uspešna distribucijska izdaja.
2. **Apple šifriranje:** odloči o izdajateljevi klasifikaciji šifriranja in državah distribucije. Kopije uporabljajo AES-256-GCM/PBKDF2, zato izjeme ne moremo samodejno označiti.
3. **Oddaljena obvestila:** v projektu **jivie-e928a** potrdi zahtevane Google Cloud pogoje; uredi omejeno FCM strežniško identiteto in Apple APNs povezavo. Zasebna JSON in `.p8` ključa shrani zaščiteno zunaj repozitorija/odjemalca; ne pošiljaj ju v klepet. Konfiguracijo in preizkus dostave lahko nato dokončamo. FCM/APNs dostava še ni potrjena.
4. **Preizkus na telefonu:** nadgradi Android iz [internega preizkusa](https://play.google.com/apps/internaltest/4701286726300038561). Preveri obrazce s tipkovnico, podatke brez povezave/restart, kopijo–obnovo ter lokalne opomnike in klik ob zaprti aplikaciji. Preveri še obnovo gesla in običajno e-poštno obvestilo; potrditvena e-pošta je že preverjena.
5. **Pred javno izdajo:** objavi pripravljeni paket **jivie.app**, nato preverimo HTTPS povezave za pomoč/zasebnost/izbris. Uskladimo dejanske Data safety/App Privacy izjave in trgovinsko predstavitev. Javna izdaja ostaja ločen korak.

Android seznam `domači` ima 15 članov. Za iOS namestitev ne potrebujemo širših upravljavskih pravic. Varno ohrani tudi kopijo Android podpisnega ključa in obnovitvenih podatkov.
