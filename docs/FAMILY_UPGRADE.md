# Dodelitve, družinski pregled, obvestila in skupne finance

**Novejša nadgradnja 8. oktobra:** organizacije, osebe brez računa, faze/koledar/časovnik, atomarni strošek in finančni načrt so izdelani z record3/finance2 ter ločenimi pravicami. [Izvedbeni dnevnik](UPGRADE_IMPLEMENTATION.md) vodi aktualne dokaze, nadgradnjo gostovanja in interno izdajo; spodaj je zgodovina prve družinske etape.

Ta mejnik opisuje zaključeno družinsko nadgradnjo pred pripravo FCM. Novejšo izbirno oddaljeno dostavo, njene preizkuse in preostalo konfiguracijo vodi [priprava Firebase](FIREBASE_PREPARATION.md).
Ta dokument vodi nadgradnjo, ki jo je uporabnik odobril po prvem [mejniku deljenja](SHARING_MILESTONE.md). Stanje 4. oktobra 2026: **izdelano in lokalno preverjeno v razvojni veji**. Spodaj ločimo potrjeno delovanje od zunanje dostave in objave. Produkcijski strežnik in preverjeni arhiv ostajata zunaj testiranja.

## Uporabniški rezultat

1. Opravila imajo izvajalce, avtorstvo, načrtovani interval in rok. Gospodinjstvo vidi skupni dan, projekt pa razpored opravil in dogodkov.
2. Trajen center obvestil loči »Zame« od »V skupnem prostoru«. Nedodeljeni člani vidijo skupno dogajanje; prejemnik dodelitve ne dobi še podvojene splošne različice istega dogodka. Združevanje ohrani konkretne cilje.
3. Lokalni opomniki se razporedijo v operacijskem sistemu. Sprememba termina, zaključitev in izbris prekličejo zastarele opomnike. Prebrano obvestilo ne zaključi izvora. Telefonska dostava, odpiranje in e-pošta imajo ločene dokaze.
4. Skupne finance ločijo finančni račun, plačnika/prejemnika in avtorja vnosa; podpirajo posamezne prihodke, stroške, prenose in sled sprememb. Finančne pravice se preverjajo na vsaki poti.

## Pogodbe in meje izvedbe

- Native API ohrani ovojnico v1 in obstoječo prijavo. Razširjeni zapisi dobijo izrecno pogodbo v2 (`sync2.*`); podprte pogodbe razglasi strežnik. Stare zahteve ne smejo odstraniti novih polj. Lokalna migracija ohrani čakajoče nespremenljive operacije in njihove ID-je.
- Finance imajo ločene metode, tabele, kazalec sprememb in pravice. Splošna sinhronizacija, obvestila, konflikti ter izvoz ne smejo razkriti podatkov brez finančne pravice. Revizija preprečuje tiho prepisovanje sočasnih sprememb.
- Prva atomarna izvedba prenosa poveže dva finančna računa iste valute v istem skupnem finančnem prostoru. Račun posameznega člana in skupni račun sta lahko oba del tega prostora; njuna vsebina je tedaj deljena z upravičenimi člani. To ne vključuje zasebnega računa iz osebnega lokalnega dela. Prenos med ločenima zasebnim in skupnim prostorom potrebuje dodatno pogodbo in ne sme biti nadomeščen z nevezanim prihodkom in stroškom.
- Obvestilo se ustvari v isti transakciji kot sprejeta sprememba. Strežnik hrani reference in trenutno preveri dostop ob seznamu ter odprtju. Read-state se usklajuje, ne spreminja izvornega opravila ali finančnega vnosa.
- Nakupovalno dogajanje ostane vidno v aplikaciji. Nastavitve zvoka, e-pošte in zunanje potisne dostave so ločene od shranjenega obvestila.
- Lokalno sistemsko razporejanje uporablja `flutter_local_notifications` 22.3.1, `flutter_timezone` 5.1.0 in `timezone`; dejanske različice so v `pubspec.lock`. Spletni brskalnik nima enakovrednega časovnega razporejanja ob zaprti aplikaciji. Android brez posebnega dovoljenja za točen alarm lahko dostavo časovno odloži.
- Oddaljeni push zahteva konfiguracijo ponudnika in Apple APNs. SMTP je prav tako ločena nastavitev gostovanja. Nedelujoč ali nenastavljen kanal ne sme biti prikazan kot uspešno dostavljen.

## Lastništvo

Vsi izvajalci so GPT 6.1 Sol / high. `kanboard_backend` upravlja `server/` in `docs/server/`; `local_core` domeno, lokalne migracije, sinhronizacijo in stanje; `mobile_desktop_ui` prikaz, SL/EN, navigacijo ter izoliran platformni adapter opomnikov. Glavni agent usklajuje pogodbe in odvisnosti, pregleduje izvedbo, opravi integracijska preverjanja ter vodi ta zapis. Različica aplikacije ostane `1.0.12+12`.

## Merila preverjanja

- Dva uporabnika in dve lokalni bazi: nastanek/dodelitev/poznejša dodelitev, združeni cilji, nedodeljeni član, brez opozorila za lastno dejanje in brez dvojnikov ob ponovitvi zahteve.
- Restart in izpad povezave: čakajoči zapisi in osebno prebrano stanje preživijo; spremembe se ne pošljejo pod drugim računom.
- Pravice: odstranitev člana in odvzem finančne pravice skrijeta vsebino tudi v obvestilih, starejših odgovorih, konfliktih in izvozu; odprtje nedostopnega cilja pojasni stanje.
- Dnevni pregled in časovnica: izvajalci, intervali prek polnoči, rok ter časovni pas; prazni in napolnjeni pogledi na 320/390/1280 pikah.
- Finance: točne najmanjše denarne enote, ločene valute, sočasni konflikt, nespremenljivo avtorstvo, filtri in prenos brez podvojitve skupnega prihodka/stroška.
- Opomniki: dovoljenje, zavrnitev, vnovičen zagon, sprememba/preklic izvora, izolacija računa, časovni pas in odprtje točnega cilja. Uspešna gradnja ni dokaz dostave na telefon.
- Strežnik: SQLite, MySQL in MariaDB; migracija obstoječe baze, nova namestitev, omejena in ponovljiva cron izvedba ter namestitveni ZIP.
- Skupni pregled: `flutter analyze`, prizadeti in nato celotni testi, dejanski HTTP preizkus ter gradnje platform po koncu posegov.

## Dokazi in odprto delo

Končna dokazila so v `build/qa/family-upgrade/` (lokalna, prezrta dokazila brez produkcijskih podatkov):

- Celoten Flutter nabor: **176 uspešnih, 2 namerno preskočena HTTP testa**, ki se izvajata posebej s sintetično poverilnico. Zapis `root-flutter-test.log`.
- Strežniška matrika na SQLite, MySQL 8.4.11 in MariaDB 10.11.19: **93 native + 37 sodelovanje + 40 finance + 15 SMTP + 10 omejevanje zahtev + 81 legacy = 276 preverjanj na vsaki bazi**. Vse uspešno; po zadnjem popravku so ponovljeni vsi novi sklopi, 81 legacy preverjanj ostaja iz predhodne matrike nespremenjene legacy poti. PHP lint in ZIP kontrole uspešne; FamilyHub 0.3.0, migracija 7.
- ZIP `server/dist/FamilyHub-0.3.0.zip`: 29 izvornih datotek, CRC in determinističnost, šest preverjanj varnih privzetih nastavitev. SHA256 `95e3ce93f62ab00e758a97f31944428404ef7d1fb6223217bcfd9d51c4f231b5`.
- Oba dejanska HTTP preizkusa sta ločeno uspešna (`root-http-isolated.log`): dve identiteti, restart, konflikt, povabila, preklic, inbox z več kot 100 dogodki, izgubljen read ACK, finance in zapoznele pravice. Uporabljata ločeni sintetični okolji 18381/18382, brez sprememb v brskalniškem 18380.
- Widget testi pokrijejo širine 320/390/1280, SL/EN, svetlo/temno temo, dodelitve, točen nabor treh ciljev, hladno navigacijo in menjavo računa, nastavitve kanalov, finance ter odvzem pravic med nalaganjem audita.
- Podatkovni testi vključijo dejansko migracijo SQLite 1→3 z ohranjenimi bajti čakajočih zahtev, rollback, delni prenos finančnega posnetka prek več strani in ponovni zagon, točne BigInt seštevke, stari format osebne kopije ter pozne odgovore po znanem odvzemu dostopa.
- **Dejanski brskalnik, dva člana:** zapis »Material za teraso« 45,90 EUR, plačnik drugi član in avtor lastnik, se uskladi v obeh aplikacijah. Stanje 2.387,10 EUR, prihodek 2.500 EUR in odhodek 112,90 EUR so pravilni; načrtovanih 120 EUR in prenosa 200 EUR ne prišteje v promet. Audit prikaže uporabna polja pred/po spremembi. Združena osebna dodelitev odpre natanko tri opravila z izvajalcem/termini, brez njihove zaključitve. Mobilni pogled uporablja kartice. Dokaza `web-finance-mobile.png` in `web-grouped-assignments.png`.
- **Dejanska dostava lokalnega opomnika na iOS simulatorju:** 4. oktobra ob 22:13 je iOS pri aplikaciji v ozadju dostavil generično obvestilo. Klik je odprl točno osebno opravilo »Test« z rokom 22:13, brez zaključitve opravila. Dokazi: `ios-reminder-scheduled.png`, `ios-reminder-delivered.png`, `ios-reminder-opened.png`. Firebase in prijava nista bila uporabljena. Prvi preizkus je razkril manjkajoči alias `Europe/Ljubljana`; popravek uporablja polno `latest_all` bazo in ima regresijska testa.
- **Hladni zagon lokalnega opomnika:** ob 22:40 je iOS dostavil opomnik po izrecnem zaprtju Kanbana iz preklopnika aplikacij. Klik je zagnal proces in prikazal isto opravilo »Test« z rokom 22:40. Dokaza `ios-cold-reminder-delivered.png` in `ios-cold-reminder-opened.png`. To dokazuje simulator/local notification pot; ne dokazuje oddaljenega push ali fizične naprave.
- Končne gradnje po vseh popravkih: splet release, Android debug, macOS debug in iOS simulator debug uspešne (`root-*-final.log`). `flutter analyze` ima 35 podedovanih info, brez novih opozoril ali napak. `git diff --check` je čist.

### Ugotovitev pri končnem preizkusu

Skupno izvajanje HTTP testov proti dolgo uporabljanemu računu je porabilo prvotni `scopes-ip` limit 120/min. Preverjanje je pokazalo tudi resničen primer: tri naprave z desetimi prostori in 12-sekundnim ciklom bi porabile 165 branj/min. Popravek loči branje (600/račun/min in širša meja 2400/IP/min) od nespremenjenih omejitev pisanja/prijave/registracije. Imenik članov se samodejno osveži največ enkrat v 60 sekundah; izrecni pregled in sprememba članstva sprožita osvežitev. Dostop do prostorov se še vedno preverja vsak cikel, strežniški ACL pa ob vsaki operaciji. Regresija preveri uro, izrecno osvežitev, nov/preklican prostor ter menjavo računa. Testni okolji sta ločeni zaradi ponovljivosti, ne z izklopom zaščit.

### Preostale meje

- Oddaljeni push še ni izveden ali nastavljen; capability je izključen. Apple Developer račun obstaja, končni iOS bundle ID in podpisna ekipa še nista izbrana. Firebase je izbirni ponudnik dostave, ne pogoj lokalne uporabe. Fizična naprava in podpisani trgovinski izdaji še niso preverjene. [Nastavitve dostave](NOTIFICATION_SETUP.md).
- SMTP je preverjen z lokalnim sprejemnikom in TLS zavrnitvami. Produkcijska poverilnica, dejanski zunanji prejemnik in cPanel cron niso nastavljeni; produkcijskih sporočil nismo pošiljali. Dvoumen SMTP odgovor lahko povzroči ponovljeno e-pošto; shranjeno obvestilo ostane idempotentno.
- Samostojna uporabniška akcija za odložitev opomnika še ni vključena; opomnik se prestavi z urejanjem roka izvora. Podatkovna pogodba podpira ločene opomnike in odložitev.
- Audit financ potrebuje povezavo. Prenosi med zasebnim osebnim delom in skupnim prostorom, med različnimi prostori ali valutami niso podprti. Ponavljajoče finance/projekcije in skupne priponke ostajajo naslednja etapa.
- Zavrženi ali zaradi pravic blokirani ukazi za prebrano stanje, nastavitve in opomnike se ohranijo v reševalnem izvozu, razen finančnih ukazov brez aktualne finančne pravice. Splošni upravljalnik za njihovo ročno zavrženje/ponovni poskus še ni izdelan; novi ukazi lahko tečejo naprej.
- Lokalna baza/izvozi še niso dodatno šifrirani. Prvi spletni zagon brez že prenesenih aplikacijskih datotek in PWA predpomnjenje nista potrjena. Web, Linux in Windows nimajo tega sistemskega razporejevalnika; Androidovi nenatančni alarmi se lahko zamaknejo.
- Produkcijski vtičnik ni nameščen, stari sistem ni upokojen, arhiv ni spremenjen. Različica aplikacije ostane 1.0.12+12.
