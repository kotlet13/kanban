# Pravila deljenja in prijave — lokalna nadgradnja Jivie / FamilyHub

**Poznejši izdajni korak 12. oktobra:** test2 je dejansko nadgrajen na
FamilyHub 0.12.0/schema16 po sveži preverjeni obnovi 86/141/2, Android 1.5.0 (20) pa je
aktiven za domači (15) od 07:32. [Dokazi in meje](release/MODERATION_RELEASE.md)
imajo prednost pred spodnjim stanjem prvotne lokalne priprave.

12. oktober 2026. Uporabnik je naročil nadgradnjo odjemalca in vtičnika, z delom
lokalno ter prijavo, namestitvijo in fizičnim preizkusom po vrnitvi domov.
Portali niso bili uporabljeni. To je preverjena lokalna izvedba, ne potrditev
nameščene storitve ali Googlovega pregleda.

## Kaj je izvedeno

- Jivie ima »Prijavi vsebino« pri skupnih opravilih/projektih, dogodkih,
  nakupih, vrtovih, osebah in finančnih zapisih ter »Prijavi uporabnika« med
  člani v Nastavitvah prostora. Bralni dostop zadostuje za upravičeno prijavo;
  ne doda pravice urejanja ali branja drugih financ.
- Pred oddajo se pridobi spletni predogled točno enega upravičenega cilja.
  Obrazec pokaže skrbnika izbranega strežnika, prikazane podatke, razlog in
  pojasnilo. Prijava se ne pošilja TriparNA ali cPanel ponudniku.
- Zapiranje obrazca ne odda prijave. Poznejša menjava računa/naprave/strežnika
  zapre ali zavrne star obrazec. Izgubljeni odgovor dovoljuje izrecno ponovitev
  istega requestId in vsebine; podatki se pri ponovitvi ne zamenjajo tiho.
  Prijave nimajo skrite trajne offline čakalne vrste.
- Izrecni, privzeto neoznačeni sprejem pravil je vezan na različico pravil,
  račun in identiteto strežnika. Osnovna lokalna uporaba in zasebna osebna
  sinhronizacija sta izvzeti. Branje, prijava, sprejem povabila, preklic članstva
  in varnostna dejanja ostanejo mogoča brez sprejema novih pravil.
- Skupni lokalni osnutki, čakajoče operacije in njihovi opId, izvozi ter kopije
  ostanejo ohranjeni. Pred pošiljanjem skupnih sprememb je potreben sprejem.
  Stari vtičnik pokaže zahtevo za nadgradnjo; ne simulira oddane prijave.
- FamilyHub **0.12.0 / schema16** ima API pogodbo1, štiri dodatne tabele,
  strežniško uveljavljanje pravil in skrbniški pregled pod Nastavitve → FamilyHub
  prijave. Kanboard jedro, obstoječi serverId, računi/gesla, seje in finančna
  zgodovina se s to spremembo ne nadomeščajo.
- Admin ima pregled, rešitev ali zavrnitev z zapiskom in sledjo obravnave.
  Ukrepi preverijo revizijo in zahtevajo izrecno potrditev. Odstranitev listnega
  zapisa ustvari tombstone; pri strukturnem staršu/korenju se odstrani prijavljeno
  besedilo in ohrani graf. Finančnih evidenc ne brišemo skozi moderacijo.
- Omejitev člana velja za konkretni skupni prostor in ustrezni podedovani
  dostop. Osebni račun, originalna članstva/finančne pravice/vodenje ostanejo.
  Admin lahko omejitev odpravi; to ne obnovi posebej odstranjenega članstva.
  Dostop, finančne revizije in vidnost obvestil se uskladijo po obstoječih pravilih.
- Posnetek je omejen na prikazana besedilna polja ali vidno identiteto člana,
  brez zneskov, priponk, drugih zapisov ali zasebnega grafa osebnih plačil.
  Podrobnosti in zapiski se odstranijo 180 dni po zaključku obravnave pri
  omejenem čiščenju; odprte prijave ostanejo za obravnavo, minimalna evidenca
  ostane. Izbris računa/prostora ima izrecno prikazan vpliv na povezane prijave.

[Natančna pogodba API in hramba](server/moderation-api-contract.md) je vključena
tudi v samostojni paket vtičnika. Obstoječi reminders worker opravi omejeno
čiščenje; ni novih SMTP/FCM ključev, kronskega opravila ali centralnega gostovanja.

## Preverjeno lokalno

- **1028 Flutter PASS / 14 opt-in preskočenih**, analiza **No issues found**.
  Dodatno **dejanski Dart/HTTP → PHP PASS**: izrecni sprejem, branje/prijava brez
  sprejema, shranjen izid po izgubljenem odgovoru, stale preview in menjava računa.
  Članstvo policy3 je v tem HTTP preizkusu ločeno sintetično pripravljeno; to ni
  fizični SMTP preizkus povabila.
- 11 novih podatkovnih/provider/SQLite primerov in 15 novih UI primerov so del
  celotne zbirke; obrazci so preverjeni na telefonu, tablici in namizju,
  v SL/EN, z večjim besedilom/tipkovnico, preklicem, UTF-8 omejitvijo in ponovitvijo.
- **192 PHP kontrol (64 na vsaki od SQLite, MySQL8.4, MariaDB10.11.19)**, vključno
  z resničnim sočasnim HTTP replayem ter običajno spletno prijavo admina,
  POST/CSRF/TLS omejitvami, HTML escapingom, pravicami, ukrepi in hrambo/izbrisom.
- Na vseh treh bazah ločena migracija15→16 ohrani ne-prazne predhodne definicije,
  hashe vrstic, serverId, račune, seje, record/finance in opId/receipts. Dodane
  so le štiri tabele; ponovitev je varna. **83 PHP lint PASS**.
- Android debug gradnja uspešna. To je prevajalski dokaz, ni namestitev na telefon,
  podpisana trgovinska izdaja ali fizični preizkus novega toka.
- 10 paketnih kontrol vtičnika ter 23 izdajnih in 7 Firebase kontrol PASS.

Prvi skupni Flutter tek je odkril, da je obravnava nedosegljivega policy endpointa
ujela tudi izgubljen odgovor obnovitve seje. Popravek najprej posebej obnovi sejo;
le naslednja napaka pravil se obravnava omejeno. Nespremenjena renewal regresija
in končna celotna zbirka sta uspešni. To ni sprememba politike seje ali njenega roka.

Dokazi: `build/qa/moderation-20261012/` in
`build/qa/moderation-server-20261012/`. Izolirani testni vsebniki so ustavljeni;
njihovi dokazi in nosilci so ohranjeni, predhodni testni/backup vsebniki nedotaknjeni.

## Paketi in stanje namestitve

`build/releases/FamilyHub-0.12.0-source.zip`, SHA256
`7c6d6518570963c1eb98f5f436d6e839ffbe1c571be56a2785f84573a6f2b7c2`.
Vključuje pregledani MIT izvor, samostojni README in javne pogodbe; brez config,
gesel, baze, kopij, vendor kode ali zgodovine mobilnega repozitorija.

Lokalno je pripravljena tudi SL/EN dopolnitev zasebnosti v
`build/releases/jivie-website-2026-10-12-reporting.zip`, SHA256
`72152fe3798fad3567396015e7071de6843032e3f25cdde56f06ee9882be6648`.
Ta paket **ni objavljen**; živa stran jivie.app ostaja na besedilu11. oktobra.

Živi testni strežniki ostajajo **0.11.2/schema15**, interna Android **1.4.1 (19)**
pa še **nima** te nadgradnje. Različica aplikacije, SDK, dependency lock in podpisna
konfiguracija niso spremenjeni. Debug APK ni primeren za nadgradnjo Play namestitve.
Novo podpisano gradnjo z novo kodo različice pripravimo ob izdajnem koraku po
vrnitvi lastnika; obstoječi izdani AAB19 ostane ohranjen.

## Naslednji korak po vrnitvi

1. Obnovi prijavo v cPanel, če je potrebna; ob težavi se ustavimo.
2. Ustavi aktivno sinhronizacijo med usklajeno nadgradnjo in shrani preverjeno
   strežniško ter šifrirano klientsko kopijo. Pred namestitvijo ponovno preveri
   pravo domeno/bazo/serverId in uspešno izolirano obnovo sveže strežniške kopije.
3. Na ločenem testnem strežniku namesti pregledani vtičnik in dovoli dodatno
   migracijo16. Ohrani zasebni config/data, račune, SMTP/FCM in identitete.
   Preveri capabilities, admin stran ter originalne podatke. Stare kode ne
   vračaj samostojno: obšla bi nove omejitve; povrnitev uporablja preverjeno kopijo.
4. Pripravi/namesti novo podpisano Jivie. Z dvema testnima računoma fizično
   preveri preklic in sprejem pravil, oddajo prijave, admin obravnavo, zavrnitev
   zastarelega cilja, omejitev/odpravo omejitve ter osebno in offline delo.
5. Objavi usklajeno zasebnost in dokončaj Data safety ter IARC. Dejanska obravnava
   prijav ostane obveznost upravljavca strežnika. Ta izvedba sama ni Googlov sprejem.

Obstoječa omejitev preklica nikoli prenesenega opomnika ostane: dvoumnih starih
čakajočih create/cancel operacij ne odstranjujemo brez dokaza. Preklic že znanega
strežniškega opomnika brez novega soglasja je preverjen. Meje samostojne finančne
obnove in priponk iz [server-loss preizkusa](server/SERVER_LOSS_TEST.md) niso
spremenjene ali razglašene za zaključene.
