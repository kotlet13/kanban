# Stanje in tedenska hramba obvestil — 11. oktober 2026

## Dogovor

Uporabnikov Android posnetek izdaje 1.3.1 (16) je pokazal zavajajoče ikone:
prebrana obvestila so prikazovala ovojnico za dejanje »označi neprebrano«,
neprebrana pa kljukico za dejanje »označi prebrano«. Ikona mora prikazovati
**trenutno stanje**, opis dejanja pa ostane v namigu gumba.

Neprebrana obvestila dobijo krepkejši naslov, poudarjeno statusno ikono in blag
moder poudarek kartice; razlika ni odvisna samo od barve. Prebrana imajo
mirnejši prikaz in oznako prebranega. Enaka pravila veljajo za skupna obvestila,
lokalne in finančne opomnike.

Prebrano obvestilo se ohrani **sedem dni od označitve kot prebrano**, ne od
nastanka. Ponovna oznaka neprebrano prekliče ta rok; poznejše branje začne
nov rok. Ponovljeno označevanje že prebranega ne podaljšuje hrambe.
Neprebrana obvestila se zaradi starosti ne brišejo.

Čiščenje odstrani obvestilo, ne izvornega opravila, dogodka, članstva ali
finančnega zapisa. Na napravi, ki je izključena, lokalno čiščenje steče ob
naslednji uporabi; prikaz upošteva rok tudi brez strežnika. Minimalna evidenca
že obravnavanega lokalnega opomnika sme ostati, da se isti opomnik ne ustvari
znova iz še odprtega opravila oziroma neplačanega stroška.

## Izvedba

- Skupni prikaz `InboxReadStatusButton` kaže stanje, namig gumba pa dejanje.
  Neprebrano ima piko na ovojnici, prebrano kljukico. Enaka komponenta je
  uporabljena tudi za finančne opomnike.
- Lokalni opomniki shranijo `readAt`; stari prebrani zapisi brez datuma
  dobijo celoten sedemdnevni rok ob prvi obravnavi. Minimalni potrdili za
  lokalne in finančne opomnike ostaneta ločeni od prikaza, da se opomnik
  ne ustvari znova iz še odprtega izvora. Finančni zapis ostane ohranjen.
- Skupni predpomnilnik odstranjuje pretečeno vsebino in ohrani samo ID ter
  revizijo za zavrnitev poznega starega odgovora. Višja revizija z novim
  stanjem se lahko ponovno prikaže. Čakajoči zapisi se razrešijo ob povezavi.
- Strežniški `NativeInboxRetention` odstrani prebrana obvestila po sedmih
  dneh ter njihove čakajoče push/poštne dostave. Čiščenje uporablja obstoječi
  cron za opomnike, omejene pakete ter zaklep prejemnika. Na voljo je tudi
  ločen `cli/inbox-retention.php`. Nova SQL migracija ni potrebna.
- Brisanje poveča obstoječo `visibility_revision`, zato druge naprave ob
  naslednji sinhronizaciji obnovijo seznam. Tudi API skrije pretečeno vsebino,
  če je za čiščenje ostalo več kot en paket.
- Zastarel odhodni `inbox.read` po strežniškem izbrisu dobi
  `notification_missing`; odjemalec odstrani samo ta ukaz in obvestilo, ne
  blokira prostora. Dejanski preklic dostopa ohrani svojo ločeno obravnavo.
  Stare aplikacije te nove napake še ne poznajo; pri namestitvi je treba
  posodobiti tudi odjemalce (podrobnosti v strežniški pogodbi).

## Preverjanje in namestitev

Preverjeno na končnem izvoru:

- **978 Flutter testov PASS / 13 opt-in HTTP preskočenih**, celoten nabor
  `flutter test --no-pub --reporter expanded`.
- `flutter analyze --no-pub`: brez napak in opozoril, 35 podedovanih info
  v starem odjemalcu. `git diff --check` PASS.
- **786 PHP kontrol PASS** na SQLite 3.53.4, MySQL 8.4.11 in MariaDB 10.11.19,
  PHP 8.4.24. Na vsaki bazi: retention 29, collaboration 37, push 138,
  SMTP 17 in sočasnost SMTP 41. Preverjeni so dejanski SQL/HTTP, neodvisni
  procesi, zaostanek nad 100 vrstic ter ponovitve brez obujanja obvestil.
- 13 spremenjenih PHP datotek lint PASS; 10 testov strogega namestitvenega
  paketa PASS.
- Sintetični UI posnetki 320/360/1200 px, obe temi in besedilo 1,3×;
  ročni vizualni pregled ozkega svetlega prikaza potrdi jasni stanji brez
  prelivanja. To niso posnetki nameščene aplikacije na telefonu.

Flutter dnevniki: `build/qa/inbox-retention-20261011/`.
UI posnetki: `build/qa/inbox-read-state/`.

Po naslednjem izrecnem naročilu je testni strežnik nadgrajen na FamilyHub
0.11.2/schema15, Android 1.3.2 (17) je aktiven interno, nova Mac gradnja je
odprta. [Izdajni dokazi](release/INBOX_RETENTION_RELEASE.md). Sprememba ne briše obstoječih varnostnih
kopij; pravila arhivske hrambe niso predmet tega popravka.
