# Privzeta obvestila in označevanje prebranega — 11. oktober 2026

## Dogovor

Po fizičnem preizkusu dveh računov je uporabnik potrdil obvestila pod zvončkom
na Macu in telefonu. Zahteval je skupno označevanje prebranega in privzeta push
obvestila za opravila, dogodke, nakupovalne spremembe ter podobno skupno dogajanje.
Lastne spremembe še naprej ne obveščajo avtorja.

## Obseg izvedbe

- Gumb »Označi vse kot prebrano« obravnava upravičena obvestila trenutnega pogleda
  in filtra, tudi lokalne opomnike ter finančne opomnike. Ne zaključi opravil in
  ne potrjuje plačil. Nova obvestila po začetku dejanja ostanejo neprebrana.
- Kategorije tasks, events, shopping, finance, reminders in membership imajo pri
  odsotni nastavitvi inApp=true, push=true, email=false in sound=false.
- Shranjene uporabniške nastavitve imajo prednost: izrecni izklop ostane izklop.
  Predogled nastavitev, zapis obvestila in dejanski pošiljatelj uporabljajo iste
  strežniške privzete vrednosti.
- Registracija naprave in dovoljenje operacijskega sistema ostaneta izrecna.
  Privzeti push ne ustvari naprave ali pošlje starih obvestil za nazaj.
- Nastavitve kategorij se urejajo tudi na Macu oziroma napravi brez vključene
  dostave; to ne pomeni, da ta naprava podpira oddaljeno sistemsko dostavo.
- Obstoječi dostopi, finančna vidnost, izključitev avtorja in združevanje obvestil
  ostanejo veljavni. Nova različica ne razširja starih politik članstva.

## Združljivost in meje

Lokalno predpomnjene stare privzete vrednosti se osvežijo z naslednjim uspešnim
branjem nastavitev z novega strežnika. GET ne ustvari eksplicitne strežniške
nastavitve. Čakajoča uporabnikova sprememba ima prednost. Stari strežnik še naprej
vrne svoje stare vrednosti do svoje nadgradnje.

To je sprememba izvora. Trenutno nameščeni testni strežnik in izdaja 1.3.0 (15)
še nimata te nadgradnje; nova gradnja, namestitev in fizični push preizkus imajo
ločene dokaze. Oddaljeni sistemski push za macOS še ni izveden.

## Preverjanje

- Strežnik: **582 PHP kontrol PASS** na SQLite, MySQL 8.4 in MariaDB 10.11.19
  (push 137, collaboration 37, SMTP 16, reminder/archive 4 na vsaki bazi).
  Šest spremenjenih/dodanih PHP datotek prestane lint. Novi primeri vključujejo
  dejanske sync spremembe opravil/dogodkov/nakupov, vseh šest kategorij,
  naknadni opt-out ter člana starševskega prostora brez projektne preference.
- Odjemalec: novi testi zajemajo osem primerov skupnega označevanja/providerjev
  in UI, pet dejanskih SQLite primerov, finančni UI ter privzete nastavitve.
  Preverjene so širine 320, 390 in 1280 logičnih točk, prazno stanje, filtri,
  poznejši prihodi, kolizija ID po menjavi računa, rollback in nespremenjeni
  finančni/opravilski podatki.
- Končna analiza: **0 napak, 0 opozoril, 35 podedovanih info** starega odjemalca.
- Paket: **10 testov PASS** ter dejanski reviewed source ZIP z novim helperjem;
  hash `a96a84ae98dbf83d17f7aee72c18b355008dcea54d4608848d598a023f2ed7ba`.
  Shema in različici aplikacije/vtičnika ostanejo nespremenjene; ZIP je razvojni
  dokaz pakiranja, ne nova nameščena izdaja.
- Neodvisni pregled preveri identiteto prikazanega nabora, finančne zastavice v
  bazi in varnost lokalnih zapisov čez čakanje. Delna napaka ne razglasi vseh
  obvestil za prebrana: že uspešna potrdila ostanejo, preostala so še neprebrana.

Celotna Flutter zbirka: **963 PASS / 13 opt-in preskočenih**, brez napak.
`git diff --check` in lokalni cilji dokumentacijskih povezav so preverjeni. Dnevniki so v
`build/qa/notification-defaults-20261011/`.
