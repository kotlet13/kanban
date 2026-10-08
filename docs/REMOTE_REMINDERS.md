# Oddaljeni razporejeni opomniki

Mejnik 8. oktobra 2026: po uporabnikovi potrjeni dostavi na zaklenjeni Samsung S25 je obstoječa strežniška pogodba povezana z aplikacijo. Izvedba in končno lokalno preverjanje sta zaključena; Android izdaja je v pripravi; fizični preizkus novega obrazca uporabnik opravi naslednji dan.

## Uporabniški tok

Pri skupnem opravilu, dogodku oziroma načrtovanem finančnem zapisu je zvonček za ustvarjanje, spremembo ali preklic opomnika. Obrazec izbere datum in uro ter pokaže stanje strežniške potrditve. Opomnik pripada prijavljenemu računu; ne pošlje ga samodejno vsem članom ali izvajalcem opravila. Za finance veljajo dodatne finančne pravice. Lokalni osebni zapisi ohranijo obstoječe lokalno razporejanje.

Ustvarjanje oziroma sprememba zahtevata pravico urejanja prostora. Bralec lahko prekliče svoj obstoječi opomnik. Zaključenega opravila, knjiženega finančnega zapisa ali nedostopnega cilja ni mogoče na novo razporediti. Urejevalnik je vezan na izvorni račun, napravo in prostor; pozna potrditev po preklopu ne sme pisati pod drugo identiteto.

Shranjeno brez povezave pomeni trajno čakajočo zahtevo, ne potrjene dostave. Strežnik mora prejeti razpored; telefon za prejem oddaljenega obvestila potrebuje povezavo. Datum in ura sta prikazana lokalno ter poslana v UTC. Minutni cron, ponudnik in telefon lahko dodajo zamik. Stanje »obvestilo ustvarjeno« potrjuje strežniški inbox, ne fizičnega prikaza na telefonu.

Nastavitve imajo ločeni odločitvi: registracijo naprave ter kanale po kategoriji in prostoru. Povzetek izbranega prostora pokaže vključene kategorije oziroma opozori, da ni vključena nobena. Opomniki so prvi v seznamu, urejevalnik pa odpre nastavitve pravega prostora. Nobena kategorija ali e-pošta se ne vključi samodejno.

## Zanesljivost

- Lokalni zapis in nespremenljiva zahteva se shranita skupaj. Ponovitev po izgubljenem odgovoru uporablja isto identiteto zahteve.
- Lokalna revizija osnutka je ločena od pričakovane strežniške revizije. Zavrnjen osnutek ostane jasno označen; ni uspešno razporejen opomnik.
- Cilja in prostora obstoječega opomnika ni mogoče zamenjati. Preklic preveri shranjeni zapis, ne le argumentov odprtega obrazca.
- Sprememba relevantnega datuma, zaključitev ali izbris cilja razveljavi stari razpored; upoštevan je tudi finančni `plannedAt`. Preimenovanje samo po sebi ni nov rok.
- Oddaljenega razporeda odjemalec ne pretvarja še v lokalni alarm. Pri istem cilju tudi samodejni lokalni opomnik umakne, da oba kanala ne opozarjata za isti razpored. To ne zagotavlja enkratne dostave ponudnika pri dvoumnem omrežnem izidu.
- Arhiviran prostor ne dobi novega razporeda; preklic dostopa ustavi pošiljanje in odpiranje. Finančne pravice se preverijo ločeno.

Strežniški API, shema in nameščeni FamilyHub 0.7.0 v tej dopolnitvi ostajajo isti. FCM namestitev in dovoljenja vodi [cPanel zapis](server/CPANEL_SETUP.md#13-fcm-na-testnem-strežniku-8-oktober-2026), splošne omejitve [nastavitev obvestil](NOTIFICATION_SETUP.md).

## Končno preverjanje 8. oktobra 2026

Celotni Flutter nabor: **636 PASS, 9 opt-in HTTP testov preskočenih**. Ločeno sta uspešna **2 dejanska HTTP testa** opomnikov na izoliranem localhost strežniku; ciljani nabor opomnikov ima 70 PASS. Analiza: **37 obstoječih info, brez napak/opozoril**. Dnevniki so v `build/qa/remote-reminders/flutter-test-final.log`, `flutter-analyze-final.log` in `reminder-focused-tests.log`.

Izolirani strežniški regresijski preizkusi na SQLite: 37 collaboration + 77 push + 4 archive-reminder = **118 PASS**, brez dostave na resnični telefon. Generični cPanel FCM pomočnik ima ločenih 189 sintetičnih kontrol; zasebne poverilnice niso v repozitoriju. Backend in shema opomnikov ostajata nespremenjena.

Vrt dodatno preverijo dejanska SQLite hramba, ponovno odprtje, kopije/obnova, arhiviranje, razveljavitev po zasaditvi in stare zelo majhne grede. 11 podatkovnih testov je uspešnih tudi v `America/Sao_Paulo`; UI koledarski datum z letnico je preverjen v `America/Los_Angeles`. Prikazi 320/390/1280 px, svetla/temna tema in geste so preverjeni. Glavni agent je pregledal dejanske Flutter zajeme v `build/qa/jivie-garden-season/`.

Fizični preizkus novega obrazca opomnikov in prenovljenega Vrta še čaka uporabnika. Uspešne stare dostave na Samsung ne pripisujemo novi gradnji.

## Preizkus na telefonu po posodobitvi

1. V prostoru **preizkus obvestil** odpri opravilo in prek njegovega zvončka nastavi termin nekaj minut v prihodnosti. Počakaj na potrditev strežnika.
2. V nastavitvah tega prostora preveri kategorijo **Opomniki → Oddaljena sistemska obvestila**. Registracija naprave sama ni vključena kategorija.
3. Pošlji aplikacijo v ozadje in zakleni telefon. Klik prejetega obvestila mora odpreti isti zapis v pravem prostoru; preveri tudi odsotnost drugega lokalnega opozorila.
4. Ustvari drug opomnik, spremeni njegov čas, nato ga prekliči in počakaj na potrditev preklica. Ob prvotnem in novem terminu ne sme priti preklicano obvestilo.
5. Preveri še shranjevanje brez povezave in ponovni zagon: do sinhronizacije mora biti jasno, da strežnik termina še ni potrdil. Za običajen preizkus izberi dovolj oddaljen čas, da se povezava obnovi prej.

Ta preizkus še ni opravljen. APNs/iPhone, običajna e-poštna obvestila in resnična sprememba drugega člana ostajajo ločeni preizkusi.
