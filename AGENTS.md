# Navodila za delo na projektu

## Namen in dogovorjeni obseg

Aplikacijo razvijamo v osrednje orodje za osebno in družinsko organizacijo: prosti čas, opravila, domače projekte, nabavo in finance. Uporabnik naj iz aplikacije upravlja tudi svoj račun in deljenje projektov.

Uporabnik je zahteval zasnovo local-first: osnovna osebna uporaba mora delovati brez strežnika, tudi za ustvarjanje in urejanje podatkov. Izvedbo gradimo po [načrtu prenove](docs/RENOVATION_PLAN.md). Lokalni osebni način je osnova; izbirna sinhronizacija, sodelovanje in strežniška obvestila imajo ločena merila dokončanosti.

Repozitorij vsebuje obstoječi Flutter odjemalec za Kanboard; prenova dodaja lokalni organizator in strežniški vtičnik. Dejanski napredek, preverjene funkcije in odprte omejitve vodi načrt prenove. Predlogov, vmesnih gradnikov in testnih prototipov ne predstavljaj kot dokončanih uporabniških tokov.

Uporabnik je 4. oktobra 2026 potrdil mobilno oblikovno smer, vzporedno namizno izvedbo in začetek gradnje. Zahteva podagente `gpt-6.1-sol` z razmišljanjem `high`; glavni agent razdeljuje delo, usklajuje pogodbe, vodi dokumentacijo in preverja rezultate. Podagenti naj imajo jasno lastništvo datotek in se neposredno uskladijo o skupnih vmesnikih. Spremembe ene naloge ne smejo prepisati dela druge.

Zadnja usmeritev istega dne ima prednost: uporabnik je izrecno pojasnil, da je z začetkom gradnje zadovoljen in želi graditi naprej. Pregled stare kode in dosedanjih sprememb je podlaga za boljše odločitve, ne ustavitev razvoja. Ohranitev starega vedenja in lokalnih podatkov aplikacije ni pogoj; bistveno je iz strežnika zajeti vse obstoječe podatke v preverjen lokalni arhiv z brskalnikom. Staro aplikacijo in projekte lahko nato upokojimo, ne da bi vse preselili v novo domeno. Obstoječi projekti so lahko izhodišče zahtev ali izbirnega prenosa. Finance potrebujejo ponovno zasnovo. Dosedanja lokalna osnova in FamilyHub sta razvojna gradnika, ne zavezujoča končna arhitektura. Dovoljenje za nadaljnjo gradnjo in zajem arhiva ni dovoljenje za izbris produkcijskih podatkov; lokalnih podatkov ne briši brez izvedbene potrebe.

Potrjen videz: nevtralna svetla/temna tema, grafitno besedilo, zadržan moder poudarek; bež in žajbljevo zelena nista potrjena smer. Telefon uporablja spodnje zavihke Danes, Načrti, Nakupi, Več; namizje stranski meni in več razpoložljivega prostora. Na začetku pokaži uporabnikove resnične podatke ali uporabna prazna stanja, nikoli vzorčnih družinskih članov, dogodkov ali finančnih zneskov. Delovno ime »Vsakdan« ni odločitev o končnem imenu v trgovinah.

## Način dela

- Z uporabnikom komuniciraj v slovenščini. Imena razredov, datotek in API metod naj sledijo obstoječim angleškim konvencijam.
- Pred spremembami preglej `git status` in navodila za zadevni del projekta. Ohrani uporabnikove lokalne spremembe; različice aplikacije ne zvišuj kot stranski učinek druge naloge.
- Izvedi dogovorjeni obseg. Za običajne lokalne popravke znotraj tega obsega ne uvajaj dodatnih potrditev. Raziskava gostovanja ni dovoljenje za posege v produkcijske podatke ali namestitev.
- Loči ugotovitve iz kode, rezultate dejanskih preizkusov in predloge. Ne sklepaj o različici živega strežnika iz različice, zapisane v odjemalcu.
- Ohranjaj spremembe pregledne in povezane z nalogo. Izogibaj se hkratnemu prepisovanju aplikacije, menjavi ogrodij in nepovezanemu preoblikovanju kode.

## Kaj ohranjamo in kako razdeljujemo kodo

- O ponovni uporabi povezave s Kanboardom, modelov in finančnih izračunov odloči po pregledu njihove pravilnosti in novega namena. Lokalizacija in čisti izračuni so kandidati za ponovno uporabo, ne obveznost ohranitve starega podatkovnega modela. Nadomestitev posameznega dela utemelji s konkretno omejitvijo.
- Flutter zasloni naj skrbijo predvsem za prikaz in interakcije. Nalaganje, zapisovanje, preverjanje podatkov in poslovna pravila postopoma prestavljaj v ločene, preizkusljive enote.
- Uporabljaj obstoječi Riverpod in GoRouter, dokler ni dogovorjen razlog za spremembo. Nove domenske logike ne dodajaj v že velike datoteke zaslonov.
- Strežniške pogodbe in pretvorbe podatkov sodijo v podatkovno plast, ne v gradnjo widgetov. Finančni izračuni naj ostanejo neodvisni od UI in omrežja.
- Uporabniška besedila dodajaj v `lib/l10n/app_sl.arb` in `lib/l10n/app_en.arb`. Datoteke `app_localizations*.dart` generiraj z `flutter gen-l10n`; ne urejaj jih ročno.
- Platformno kodo izoliraj. Prisotnost mape za platformo ne dokazuje, da aplikacija na njej deluje. Pri spremembah UI preveri dogovorjene mobilne in namizne širine.

## Strežnik in Kanboardovi vtičniki

Trenutno gostovanje je cPanel. Pregled 4. oktobra 2026 je pokazal Kanboard 1.2.54 v evidenci Softaculous, PHP 8.4 v nastavitvah računa, prazno mapo `plugins`, cron z možnostjo minutnega intervala in spletni terminal z odprtim pozivom lupine. Oddaljeni SSH, dejanska baza in SMTP niso preverjeni. PHP nastavitve računa onemogočajo `mail()` in izvajanje sistemskih procesov. Podrobnosti in meje tega pregleda so v README. Izolirani razvojni okolji Docker s Kanboardom 1.2.54, SQLite oziroma MySQL ter vtičnikom FamilyHub sta v `server/`; navodila v `docs/server/README.md`.

Poznejši dejanski zajem varnostne kopije istega dne je potrdil `DB_DRIVER=mysql`, datoteke v `data/files` in prazno mapo vtičnikov. Glava izvoza poroča podatkovni strežnik 10.11.19 in PHP 8.4.25. Kopija baze je bila uspešno obnovljena v omrežno izoliranem lokalnem MySQL 8.4.11; to dokazuje obnovo kopije, ne enakega pogona/različice kot na gostovanju. Zasebne varnostne kopije, konfiguracije in podatkovni izvozi ostanejo zunaj repozitorija in zunaj mape, ki jo ponuja arhivski brskalnik.

- Kot izhodišče preverjaj razširitev prek vtičnikov in obstoječih Kanboardovih modelov. Jedra ne spreminjaj brez konkretno dokazane potrebe in dogovorjene smeri.
- Kanboard obravnavaj kot kandidata za izbirno strežniško sodelovanje in povezavo z obstoječimi podatki. Lokalno ustvarjanje, branje in urejanje ne smejo zahtevati njegove dosegljivosti ali njegovih identifikatorjev. Nova sinhronizacija uporablja lastne tabele vtičnika. Spremembe iz Kanboardovega spletnega vmesnika zajemi le za objekte, ki jih bo izrecno dovoljeno urejati tudi tam; novih skupnih tabel trenutno ne ureja.
- Rešitev za produkcijo naj bo izvedljiva brez SSH, Dockerja na strežniku ali stalno delujočega procesa. Odvisnosti in namestitveni paket pripravi lokalno; omejitve gostovanja preveri pred izbiro mehanizma.
- Nove podatkovne module umesti v lastne tabele z migracijami za dejansko podprte baze. Ne razširjaj shranjevanja kompleksnih skupnih podatkov v razrezane projektne metapodatke.
- Določi različico pogodbe API in način preverjanja zmožnosti vtičnika. Stara aplikacija in nov strežnik ter obratno morata imeti opredeljeno vedenje.
- Za vsako novo metodo preveri identiteto, vlogo in dostop do konkretnega objekta na strežniku. Kanboardov spletni ACL in API ACL sta ločena; registracija metode sama po sebi ne zagotovi pravilnih pravic.
- Stara razvojna povabila za Kanboardove projekte in novi Native API sta v namestitvenem paketu privzeto izključena z ločenima nastavitvama. Novi obsegi, članstva in zapisi so v lastnih tabelah FamilyHub; ne vključujejo starih projektov ali finančnih metapodatkov. Starih povabil ne vključuj za resnične projekte, dokler zasebnost njihovih finančnih metapodatkov ni urejena.
- Testno okolje naj posnema potrjene različice in bazo gostovanja. Za migracije predvidi varnostno kopijo, preverjanje uvoza in postopek povrnitve. Obstoječih zapisov ne briši pred uspešno preverjenim prenosom.

## Računi, gospodinjstva in deljenje

- Prijava obstoječega uporabnika, ustvarjanje računa in sprejem povabila so različni postopki. Cilj je, da jih uporabnik opravi v aplikaciji.
- Ne vključuj globalnega Kanboardovega `jsonrpc` ključa ali skrbniškega gesla v odjemalca. Ne uvajaj samodejnega prehoda z uporabniške identitete na privilegirano identiteto.
- Nova prijavna pot je FamilyHub Native API v1: lokalno geslo in TOTP, omejevanje poskusov, preklicljive napravne seje ter časovno omejena povabila. Pogodba je v `docs/server/native-api-contract.md`. FamilyHub 0.5.0 doda prvi račun z upraviteljsko enkratno kodo, preverjanje e-pošte in obnovo gesla prek ločene šifrirane SMTP vrste; pogodba je v `docs/server/account-api-contract.md`. Produkcijski SMTP še ni nastavljen. Zunanji prijavni ponudniki niso podprti; ne obidi njihove avtentikacije.
- Deljenje projekta ne pomeni deljenja računa. QR oziroma povezava za povabilo ne sme vsebovati trajnega gesla ali osebnega API ključa.
- Osebni prostor, gospodinjstvo in deljeni projekt so ločeni pojmi. Njihov končni podatkovni model uskladimo z uporabnikom; članstva ne enači s samodejnim dostopom do vseh modulov.
- Finance se smejo deliti v istem domu ali izrecno tako zasnovanem projektu; osebne finance niso trajna produktna omejitev. Pred finančno izvedbo določi skupni finančni obseg in pravice do branja/urejanja. Članstvo zunanjega sodelavca v projektu ne odpre zasebnih financ doma. FamilyHub 0.3.0 uporablja ločeno finance pogodbo; finančnih zapisov ne dodajaj v splošni sync2.
- Pravice do opravil in do zasebnih financ preverjaj ločeno, tudi pri izvozu, priponkah, obvestilih in AI kontekstu. Skrivanje zavihka ni nadzor dostopa.
- Preklic članstva mora ustaviti nadaljnji strežniški dostop. Preveri tudi skupinske pravice in ravnanje z že prenesenimi lokalnimi podatki.

## Podatki in zanesljivost

- Za local-first načrtuj trajno lokalno bazo in podatkovno plast, iz katere bere UI. Lokalni zapis in evidenco spremembe za vključeno sinhronizacijo shrani atomarno; izpad povezave ali ponovni zagon ne smeta izgubiti čakajočih sprememb. Predpomnilnik prenesenih odgovorov te zahteve ne izpolni.
- Prvotna osebna shramba Hive ostane ohranjen vir selitve v per-record SQLite (lokalna schema 4). Selitev shrani vse zapise in oznako uspeha atomarno; poškodovanega ali novejšega formata ne ponastavljaj. Osebna projekcija ima omejitev 10 MiB/50.000 zapisov. Revizijo preverjaj skupaj z identiteto prostora; testi dveh naprav niso dokaz usklajenega prikaza v več procesih iste namestitve.
- Nadaljevanje 5. oktobra 2026 zajema prvi vstop, izbirno zasebno sinhronizacijo ter šifrirane kopije/obnovo; Google Play Console je odložen. Izvedbo in aktualne dokaze vodi `docs/PERSONAL_SYNC_AND_RECOVERY.md`. Osebni strežniški prostor je izključno lastnikov, prijava ne pomeni soglasja za prenos podatkov. Tudi nadaljnji lokalni zapisi po odjavi ali obnovi potrebujejo izrecen prenos. Osebne finance uporabljajo `personalFinanceEntry` v ločeni finančni pogodbi, ne splošnega sync2.
- Osebni in skupni podatki uporabljajo skupno SQLite/Drift povezavo z ločenimi prostori ter transakcijami nad zapisi, odhodnimi operacijami, konflikti in kazalci. Odpiranje baze ni odvisno od poverilnic. Lokalni račun loči po normaliziranem strežniku, trajnem `serverId` in `accountId`; številčni ID uporabnika ni dovolj. Zahteve in odprte urejevalnike pripni identiteti, ki jih je začela, ter zavrni pozne odgovore/zapise po menjavi. Spletna shramba ne sme tiho pasti na pomnilnik ali nekoordiniran IndexedDB. Kopija v prostor drugih članov se deli samo izrecno, z novimi ID-ji in brez financ.
- Prenosne kopije `.vsakdan` uporabljajo overjeno šifriranje in omejeno izpeljavo ključa. Ne vsebujejo sej ali skrivnosti dostave in ne potrjujejo pravic. Obnovljeno skupno/zasebno strežniško delo ostane šifrirano v območju za obnovo, nadaljevanje pa potrebuje isto identiteto, sveže pravice in izrecno dovoljenje. Ohrani izvirne ID-je nespremenljivih operacij in lokalne preslikave; zgodovinskega `conflict.remote` ne postavi nad sveži kanonični zapis. SQL podatke in dnevnik nastavitev obnovi atomarno, SharedPreferences nato ponovljivo. Dodatno šifriranje aktivne baze s tem ni rešeno.
- Identiteta lokalnega zapisa mora nastati brez strežnika; povezavo s Kanboardovim ID vodi ločeno. Sinhronizacija potrebuje pravila za sočasne spremembe, izbrise in ponavljanje zahtev. Pri spornih finančnih spremembah ne uporabljaj tihega prepisovanja zadnje različice.
- Poverilnice in API ključe hrani v varni shrambi. Ne uvajaj rezervnega shranjevanja skrivnosti v `SharedPreferences`; obstoječa problematična mesta so opisana v README.
- Za produkcijske povezave uporabljaj HTTPS. Avtentikacijskih podatkov ne posreduj na drug izvor ali na HTTP ob preusmeritvi.
- V dnevnike ne zapisuj gesel, žetonov, QR vsebine, zasebnih finančnih podatkov ali teles uporabniških zahtev in odgovorov.
- Lokalno shrambo, vključno s predpomnilnikom in AI pogovori, loči po lokalnem profilu oziroma strežniku in uporabniku; pri novih prostorih tudi po ustreznem obsegu. Odjava in menjava računa morata imeti določeno čiščenje, brez tihega izbrisa osebnih lokalnih ali še neusklajenih podatkov.
- Predvidi izvoz, varnostno kopiranje in obnovo lokalnih podatkov brez odvisnosti od strežnika. Sinhronizacija sama ni varnostna kopija. Določi varovanje lokalne baze in priponk ter razpoložljivost priponk brez povezave.
- Arhiv starega sistema loči od uvoza v novi organizator. Ohrani izvirne izvožene zapise, nepoznana polja, metapodatke, povezave in priponke; model `fromJson/toJson` ni dokaz brezizgubnega izvoza. Arhivski brskalnik mora delovati brez starega strežnika. Nepopoln izvoz mora ostati označen kot nepopoln; upokojitev je mogoča šele po preverjenem zajemu, obnovi in dogovorjenem končnem preklopu.
- Preklica dostopa ni mogoče takoj uveljaviti na nepovezani napravi ali z njim zagotoviti izbrisa že pridobljene kopije. Ob ponovni povezavi preveri pravice; zavrnjenih sprememb ne izgubi tiho in jih ne pošiljaj pod drugo identiteto.
- Finančne zneske obravnavaj v najmanjših denarnih enotah skupaj z valuto. Različnih valut ne seštevaj brez izrecnega pravila pretvorbe.
- Potrjena finančna zasnova loči plačnika/prejemnika, finančni račun in avtorja vnosa. Skupna tabela omogoči pregled po članu/računu in sled sprememb. Prenos med računi ni nov prihodek ali strošek v skupnem seštevku; osebna vsebina se ne deli samodejno.
- Pri skupnem urejanju uporabljaj posamezne zapise, strežniško preverjanje revizije in jasno obravnavo konflikta. Ponovitev zahteve ne sme podvojiti stroška, povabila ali drugega pomembnega zapisa.
- Obvestila in opomniki v aplikaciji so izrecna obvezna zahteva uporabnika. Finančna prenova jih ne sme odložiti na nedoločen čas. Loči »dodano opravilo v skupnem prostoru« od »dodeljeno tebi«: tudi nedodeljeni člani dobijo obvestila o skupnem dogajanju, osebno naslovljeni prejemnik pa jasno oznako. Nakupovalni dodatki/seznami so vidni in se lahko združijo; posamezni artikli privzeto ne pošiljajo e-pošte. Prebrano obvestilo ne pomeni zaključenega opravila ali plačanega računa. Podrobnosti vodi `docs/RENOVATION_PLAN.md`.
- Center obvestil in telefonska obvestila naj odprejo konkretni zapis oziroma nabor zapisov iz združenega obvestila v pravem računu in prostoru, z novim preverjanjem pravic. Isti dogodek istemu prejemniku ne ustvari podvojenega splošnega in osebnega opozorila. Dnevni pregled gospodinjstva in projektna časovnica vključita izvajalce ter termine samo za skupno vidno vsebino; izvedbo in dokaze dodelitev, skupnega dneva ter časovnice vodi `docs/FAMILY_UPGRADE.md`.
- Lokalna finančna politika ima revizijo in generacijo dostopa. Sprememba politike takoj razveljavi popolnost prenesene projekcije; zakasneli uspešen odgovor po znani zavrnitvi ne sme obnoviti dostopa. Audit in izvoz po čakanju ponovno preverita trenutne pravice. Čakajoče zavrnjeno delo ohrani, vendar ga ne vključi v vidne seštevke.
- Uporabnik je 5. oktobra 2026 izbral Firebase Cloud Messaging s paketom Spark. Pripravo vodi `docs/FIREBASE_PREPARATION.md`, konfiguracijo `docs/NOTIFICATION_SETUP.md`; pravi Firebase projekt/APNs in fizični preizkus dostave še manjkajo. FCM je izbirni Android/iOS kanal, brez Firebase Auth, Firestore, Analytics ali Cloud Functions. Strežniški ključ in APNs `.p8` ostaneta zunaj odjemalca/repozitorija. Brez konfiguracije se kanal ne aktivira. Ne označi uspešne registracije pri FamilyHub ali nadomestnega transporta kot dokaz dejanske dostave.
- Push naj bo dostavni kanal za shranjeno obvestilo. Predvidi ponovne poskuse, preprečevanje podvajanja, časovne pasove in preverjanje pravic ob odprtju. Razporejanje mora delovati z dejansko razpoložljivim cronom oziroma dogovorjenim nadomestilom.
- Lokalne opomnike za podatke na napravi loči od obvestil o oddaljenih spremembah. E-pošta in oddaljena dostava potrebujeta povezavo; lokalno shranjevanje ne sme čakati nanju. Usklajevanje ne sme podvajati opomnikov ali pošiljati zastarelih obvestil za vsako vmesno spremembo.
- AI naj bo neobvezen; osnovne funkcije morajo delovati brez njega. Posreduj le podatke, do katerih ima uporabnik pravico in za katere je omogočil takšno uporabo.

## Preverjanje sprememb

- Za spremembe Dart kode formatiraj spremenjene datoteke in izvedi `flutter analyze` ter teste, ki preverjajo prizadeto vedenje. Za spremembe prevodov izvedi tudi `flutter gen-l10n`.
- Po menjavi Flutter SDK najprej uskladi odvisnosti z `flutter pub get` in preglej spremembe `pubspec.lock`. Napake zaradi starega `.dart_tool` loči od napak aplikacije; SDK ali odvisnosti ne nadgrajuj nepovezano z nalogo.
- Prednost imajo testi finančnih izračunov, pravic med različnimi uporabniki, sočasnega urejanja, migracij, odjave in prijave. En test začetnega zaslona ne potrjuje celotne aplikacije.
- Local-first preveri z zagonom brez računa in povezave, ustvarjanjem in urejanjem, ponovnim zagonom ter izvozom in obnovo. Za sinhronizacijo preveri dve napravi, sočasne spremembe, ponovljene zahteve, izbrise, konflikte in preklic pravic.
- Pri strežniških spremembah preveri tako dovoljene kot zavrnjene dostope ter združljivost z dogovorjeno različico Kanboarda. Za to uporabljaj testne račune in podatke.
- Za dokumentacijske spremembe preveri dejstva, povezave, primere ukazov in `git diff --check`; aplikacijskih testov brez razloga ne ponavljaj.
- Ob predaji povej, kaj je spremenjeno, kaj je bilo preverjeno in katere omejitve ostajajo. README posodobi, kadar se spremeni dejansko stanje ali dogovorjena smer.
