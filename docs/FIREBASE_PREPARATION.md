# Priprava Firebase Cloud Messaging

Uporabnik je 5. oktobra 2026 odobril pripravo FCM s paketom Spark. Firebase projekt ustvari pozneje sam. **Priprava implementirana in lokalno preverjena**; dejanska zunanja dostava še ni potrjena. Produkcija, preverjeni arhiv in različica aplikacije 1.0.12+12 ostanejo nespremenjeni.

## Izvedeno

- Izbirni Android/iOS FCM adapter: brez konfiguracije ni začetne povezave, generiranja žetona ali zahteve za dovoljenje. Osebni način, skupna sinhronizacija in lokalni opomniki ostanejo uporabni.
- Izrecen vklop na napravi, prikaz dovoljenja/pripravljenosti, menjava žetona in preklic. Registracija je pripeta dejanskemu računu in napravi, pozni odgovori po menjavi računa ne morejo spremeniti nove seje.
- Native API in trajna dostavna vrsta v FamilyHub. Prejemnik, veljavnost naprave, trenutne finančne/članske pravice in nastavitve se preverijo pred dostavo ter ob odprtju.
- FCM HTTP v1 iz našega strežnika s časovno omejenim OAuth žetonom. Spark ne potrebuje Cloud Functions, Firestore, Firebase Auth ali Analytics.
- Generično besedilo in reference do trajnega inbox dogodka; brez naslovov opravil, zneskov, prijavnih skrivnosti ali zunanjih povezav. Hladni in topli zagon vodita skozi obstoječo preverjeno navigacijo. Sporočilo v ospredju osveži inbox brez dodatnega sistemskega opozorila.
- Ločeno: konfiguracija javnega mobilnega odjemalca, strežniška storitvena poverilnica, ključ za hrambo napravnih žetonov in APNs ključ. Zasebni ključi niso del aplikacije ali repozitorija.

## Lastništvo

`kanboard_backend`: server in docs/server; `local_core`: domena, repository, stanje in podatkovni testi; `mobile_desktop_ui`: platformni adapter, UI, prevodi, Android/iOS priprava in orodje za konfiguracijo. Glavni agent usklajuje pogodbe, pripete odvisnosti, dokumentacijo ter neodvisne končne preizkuse. Izvajalci so GPT 6.1 Sol / high.

## Preverjeno vedenje

- Preverjanje nastavitev brez omrežja: manjkajoče/invalidne vrednosti ne aktivirajo kanala in ne izpišejo skrivnosti.
- Registracija, rotacija, opt-out, preklic naprave, menjava računa med čakanjem, ponovitev in trajen restart; noben žeton v običajnem izvozu.
- Vsebina brez finančnih podrobnosti, trenutni ACL in neodvisne nastavitve inApp/push; zavrnjeni in potekli cilji.
- OAuth in FCM z nadomestnim transportom, preverjanjem TLS, omejitvijo časa, obdelavo napak in ponovitvami. Sprejem pri ponudniku ni dokaz prikaza na napravi in ni obljuba exactly-once dostave.
- Flutter analyze/test in gradnje brez projektne konfiguracije; lokalni opomniki ostanejo delujoči tudi ob vključeni knjižnici Firebase.
- Resnična FCM/APNs dostava na fizični napravi bo preverjena šele po uporabnikovi konfiguraciji. Do takrat ne označimo kanala kot produkcijsko preverjenega.

## Uradni viri

- [Firebase cenovni paketi](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans): FCM je brezplačen, Spark ne zahteva plačilnega računa za brezplačne storitve.
- [Flutter FCM priprava](https://firebase.google.com/docs/cloud-messaging/flutter/get-started): platformna priprava in registracija naprave.
- [Sprejem sporočil](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages): življenjski cikel in odpiranje.
- [Pošiljanje HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api): strežniška avtentikacija.

## Regresijski dokaz na iOS

- Prvi iOS simulator build s pripetima Firebase paketoma in integracijo notification delegate je uspešen (`build/qa/firebase-preparation/ios-dependency-checkpoint.log`). To je vmesna gradnja, ne dokaz končnega FCM toka.
- Regresijski lokalni opomnik: iPhone 17 simulator / iOS 27, časovni pas Europe/Ljubljana, opravilo `Test`, 5. oktober ob 05:15. Aplikacija je bila zaprta prek app switcherja. OS je prikazal generični opomnik; klik je hladno zagnal aplikacijo in odprl točno opravilo z rokom 05:15. Dokaza: `build/qa/firebase-preparation/ios-local-reminder-cold.png` in `ios-local-reminder-open.png`. Ta preizkus potrjuje soobstoj obeh notification knjižnic, ne oddaljene FCM dostave.


## Končni preizkusi 5. oktobra 2026

- Celotni Flutter nabor: **226 PASS**, 2 opt-in HTTP testa izpuščena v običajnem zagonu. Nato sta oba dejanska HTTP preizkusa posebej **PASS** na svežih izoliranih strežnikih 18381/18382; nove skupine push referenc so preverjene tudi skozi pravi Native API.
- Nova FCM podnabora: **22 podatkovnih** in **28 platformnih/UI** testov. Vključujejo izgubljen ACK in restart, nespremenljiv CAS, rotacijo, odjavo med čakanjem, trajni preklic stare naprave, napačen račun/projekt, preklicano/izteklo prijavo, popolne skupine in zavrnitev zlonamerne paginacije. UI preverja 320/390/1280, SL/EN in svetlo/temno temo.
- Konfiguracijsko orodje: **7 Python testov PASS**. Preverja dejanske aplikacijske ID-je iz projekta, enak Firebase projekt/sender, neveljavne datoteke, zavrnitev strežniškega ključa in delnega prepisovanja obstoječe Android konfiguracije.
- `flutter analyze`: **35 podedovanih info**, brez error/warning in brez novih ugotovitev v organizatorju ali njegovih testih. Izhodna koda je zaradi teh info 1; ne predstavljamo je kot povsem čisto analizo.
- FamilyHub **0.4.0 / schema 8**: **352 preverjanj na vsaki bazi** (SQLite, MySQL 8.4.11, MariaDB 10.11.19); od tega 76 za push. Konfigurirani lokalni HTTP smoke 12/12, privzeta politika dejansko razpakiranega ZIP 8/8. Nadomestni OAuth/FCM transport in dvoprocesni preizkus rotacije ne pošiljata v Google.
- Paket `server/dist/FamilyHub-0.4.0.zip`: 39 datotek, root je neodvisno preveril CRC in ujemanje vsake datoteke z izvorom. SHA256 `569d365aa58ab719eaaf328c04515537ceeddd954c869060ab5ce2e09e518778`. Privzeto sta Native API in FCM izključena; namestitve v produkcijo ni bilo.
- Končne gradnje brez Firebase konfiguracije: **web release, Android debug APK, iOS simulator debug in macOS debug PASS**. Android ohranja obstoječi application ID; iOS simulator ne potrjuje podpisovanja ali APNs. Gradnje vsebujejo opozorila obstoječega Android orodja, prehoda nekaterih vtičnikov na Swift Package Manager in zastarelih klicev v odvisnostih; v tem obsegu nismo menjali SDK ali teh nepovezanih odvisnosti. Dnevniki: `web-build.log`, `android-build.log`, `ios-build.log`, `macos-build.log`.
- Končni iOS zagon brez računa in konfiguracije je uspešen: osebni podatki ostanejo, sistemski opomniki so vključeni, oddaljeni kanal pa je jasno označen kot še nekonfiguriran. Dokaz: `build/qa/firebase-preparation/ios-notification-settings.png`; namizni spletni prikaz: `web-notification-settings.png`.
- `git diff --check` uspešen. Aplikacijska različica je še **1.0.12+12**. Arhiv in produkcijski podatki niso bili spremenjeni. Dodatna Docker testna okolja so ustavljena brez brisanja nosilcev; razvojni 18380 ostaja FCMoff.

Končni dnevniki so v ignorirani `build/qa/firebase-preparation/`. Zasebni `isolated-*.json` fixture datoteki imata dovoljenja 0600 in sintetične prijavne podatke; celotne mape ne objavljaj. Podrobna strežniška evidenca je v [strežniških navodilih](server/README.md).

## Pomembne meje izvedbe

Registracija pri FamilyHub je potrditev vezave naprave, ne dokaz, da jo FCM/APNs že dosežeta. Ob izgubljeni registraciji aplikacija ustavi SDK in zahteva izrecen ponovni poskus s svežim žetonom. Znana zavrnitev prijave ostane veljavna tudi po restartu; star odgovor ali začasna odsotnost povezave je ne razveljavita. Preklic ne briše osebnih ali neusklajenih podatkov.

Čakajoči preklici največ 20 starih naprav so v ločeni varni shrambi. Ob napaki hrambe ali doseženi meji uporabnik dobi napako, takojšen strežniški preklic pa se vseeno poskusi. Brez povezave ni obljube takojšnjega preklica. Obnovitev seje, ki je že označena za preklic, je zavrnjena. SDK registracija za drug račun čaka na uspešno odstranitev starega SDK žetona.

Skupina za odpiranje ima največ 500 dogodkov. Offline odpiranje zahteva dokaz popolnega prej prenesenega nabora; delna skupina ne predstavlja celotnega obvestila. Finance in članstvo se preverjajo ob pridobivanju ter odpiranju. Dostavna vrsta uporablja generične reference in trenutno veljavne pravice, vendar že sprejetega opozorila ni mogoče odpoklicati.

Dispatch ima 40-sekundni proračun in omejene HTTP poskuse, čakanje na zaklepe baze lahko podaljša celoten čas. Pri SQLite držanje transakcije med pošiljanjem lahko začasno blokira urejanje. Na cPanel je treba še preveriti dejanski PHP CLI, odhodni HTTPS, lokacijo zasebnih ključev ter cron. Namestitev, IAM, APNs in fizični preizkus ostajajo naslednji ločen korak po [navodilih za nastavitev](NOTIFICATION_SETUP.md).
