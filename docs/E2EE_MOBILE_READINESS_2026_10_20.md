# Priprava mobilnega nadaljevanja — 20. oktober 2026

**Poznejša skupna seja je že začeta:** dejanske namestitve, popravek
Androidove registracije dodatkov in mobilna odobritev dostopa so zapisani v
[aktualnem nadaljevanju](E2EE_MOBILE_SESSION_2026_10_20.md). Spodnji opis
je dokaz predhodne priprave, ne trenutni status naprav.

Uporabnik je naročil pripravo za skupno testiranje po vrnitvi domov.
Ta korak pripravlja pakete, testni strežnik in diagnostiko; ne izvaja
namestitev na telefona ali uporabniških testnih scenarijev.

**Aktualni izid po uporabnikovem dodatnem naročilu popravka: Android,
iOS in testni strežnik so pripravljeni.** iOS podpisovanje je popravljeno
in novi podpisani paket preverjen. Telefona in njuni podatki niso bili
spremenjeni; namestitev in skupni test počakata na uporabnikovo vrnitev.
Prejšnji blokirani korak in njegovi trije poskusi so ohranjeni spodaj.

## Osnova in izolacija

Zamrznjeni izvor je `cf97e2df81c5411fdf05bf0d8cb59ad840db2055`.
Manifest `build/qa/jivie-mobile-readiness-20261020/source-freeze.json`
veže 1.560 vhodov z aggregate SHA-256
`7756cdb9c992d3db398318d2022fb5ffa44fc15df1d7aeb408b7873fc245935a`.
Ločena Android in iOS staging imenika vsebujeta samo pregledane QA razlike.
Gradnji potekata zaporedno z obstoječim SDK in zaklenjenimi odvisnostmi.

Nadaljujemo stanje iz
[mobilnega runbooka](E2EE_MOBILE_TWO_USER_TEST_2026_10_18.md):

- S25, A, lastnik: `si.triparna.jivie.e2eetest.android20261018`.
- iPhone 11, B, prejemnik: `si.triparna.jivie.e2eetest.ios20261018`.
- Obe aplikaciji imata ime **Jivie Test**. Shrambe, podpisi in identitete
  varne hrambe ostanejo isti; prava trgovinska Jivie se ne spreminja.
- Ista dva testna računa, lokalni vnosi, računski obnovitveni datoteki,
  projekt in eno že sprejeto povabilo ostanejo. Sprejem čaka lastnikove
  ključe; registracije, FILE čarovnika ali novega povabila ne ponavljamo.
- Mobilni Docker uporablja `https://192.168.132.29:18801/`; ne uporabljamo
  Mac deljenja na 18811 ali benchmarka na 59776. Zaupanje ostane omejeno
  na isti namenski CA in točen HTTPS cilj.

CA poteče **21. oktobra 2026 ob 12:25:42 UTC (14:25:42 po lokalnem času)**.
Za nadaljevanje po tem času je treba najprej obnoviti testno TLS pripravo;
preverjanja certifikata se ne izklopi. Dostopnost LAN in veljavnost
certifikata preverimo še ob dejanskem začetku, ker se lahko IP spremeni.

## Začetek skupnega testiranja

Spodnji skupni tok počaka na uporabnikovo vrnitev. Oba paketa sta pripravljena;
pred namestitvijo ponovno preverimo napravi in dosegljivost testnega gostovanja.

1. Uporabnik priključi in odklene S25 ter iPhone 11. Oba sta na istem Wi-Fi
   kot Mac. Potrdimo prepoznani napravi in izključno testna ID-ja.
2. Pred zamenjavo preverimo trenutni testni paket, stanje in ustrezno kopijo
   podatkov. Namestimo pripravljeno posodobitev čez isto testno aplikacijo,
   brez odstranitve, brisanja podatkov ali spreminjanja Keychain/Keystore.
3. Zajem dnevnikov pripravimo **pred prvim zagonom in dejanjem**. Zajema
   točen paket/proces, metode, čas, status in omejene diagnostične kode;
   brez vsebine, ključev, datotek FILE, gesel ali tokenov.
4. Najprej preverimo zagon istega stanja ter en zaključen običajni sync.
   Nato nadaljujemo isto sprejeto povabilo z lastnikovo odobritvijo dostopa
   po novem poenostavljenem toku, brez obvezne primerjave kartic.
5. Zaključimo še odprte mobilne poti: branje skupnega opravila, dvosmerna
   sprememba, ohranitev lokalnega zasebnega vnosa, finančne pravice in
   saldo, offline/ponovna povezava ter mobilni odvzem kot zadnji poseg.
   Že uspešnih Mac scenarijev in že izvedenega Mac odvzema ne ponavljamo.
6. Sveža obnova in stara → nova fizična nadgradnja sta ločeni naslednji
   vaji z zaščiteno kopijo ter vnaprej določenim računom/ciljem. Ne brišemo
   teh dveh aktivnih testnih namestitev za pripravo svežega testa.

Ob napaki se najprej zabeležijo prva izjema oziroma stabilna koda, faza,
čas in pending/conflicting/blocked stanje. Največ trije poskusi na težavo;
potem dokaz in SKIP/BLOCKED, brez novega računa ali fixture za ponastavitev
števca. Dejanja, ki so že uspela na strežniku, se ne pošiljajo znova.

## Znane odprte meje

- Opozorilo pri nekaterih blokiranih vrstah napačno enači razlog z odvzemom
  in potrebo po ročnem nadaljevanju. Stari Mac N7 je po treh poskusih SKIP;
  priprava ne začenja četrtega kroga.
- Sveža strežniška zavrnitev pisanja po odvzemu v zadnjem Mac scenariju
  ni bila izvedena. Mobilni tok še ni zaključil deljenja/odvzema.
- Prihranki zadnjih optimizacij so dokazani na majhnem lokalnem HTTP naboru,
  ne še na telefonih. Ocenimo tudi prehode v ozadje in ponovno povezavo.
- Fizična obnova, migracija obstoječih podatkov, neodvisni pregled celotne
  E2EE sestave in izdajna vaja ostajajo odprti. To ni produkcijska izdaja
  ali začetek 30-dnevnega roka za odstranitev starih kopij.

## Pripravljeni testni strežnik

Isto mobilno gostovanje je posodobljeno na zamrznjeni izvor. Spremenjenih je
šest datotek FamilyHub (pet PHP in README); vseh 182 datotek ciljne kode
se ujema z manifestom. Shema in inicializacijska koda sta isti, brez nove
migracije. PHP lint spremenjenih datotek je uspešen.

Pred zamenjavo so bili začasno ustavljeni samo štirje mobilni testni
vsebniki. Zasebna kopija vsebuje 212 preverjenih datotek (209 za prejšnjo
strežniško pripravo, dve v app-data in eno v mail-data), z dovoljenji 0700.
SQLite integrity je `ok` pred spremembo in po njej. Vseh 220 tabel ima
enake vrstice in število zapisov, shema je točno ista. Datoteka baze sama
ni bajtno enaka; dokaz je primerjava sheme in vseh vrstic.
Ločeni pregled istih offline kopij potrdi tudi vseh 499 objektov
`sqlite_master`, z enakimi izvirnimi in normaliziranimi definicijami.
Prvotni `schema` podatek v poročilu je zajemal samo verzije vtičnikov;
dejanska DDL primerjava je zato dodana posebej, ne zgolj sklepana iz verzij.

Javni HTTPS capabilities odgovor je HTTP200, z istim `serverId`,
authority snapshot različico 1 in invitation različicami 1–4. Isti CA,
konfiguracija in podatki zunaj šestih zamenjanih izvornih datotek so
ohranjeni. App, gateway in Mailpit so zagnani; **mail-worker ostaja
ustavljen** do skupnega nadaljevanja. Ni avtenticiranih poslovnih zahtevkov,
poštnega testa ali dejanj na telefonih.

Priprava je uspela v tretjem omejenem poskusu. Prvi je popravil primerjavo
Markdown datotek z izvorno zamrznitvijo, drugi je obstal pri odpiranju kopije
SQLite. Kopirani bazi ohranita oznako WAL, čeprav pri doslednem kopiranju ni
bilo WAL/SHM datotek; končno preverjanje uporablja immutable način samo na
zasebnih offline kopijah. Korupcija ni bila ugotovljena. Navidezna razlika
sheme je bila tuple/list razlika pri serializaciji dokazov; normalizirana
primerjava je potrdila enako shemo.

Dokazi so v `build/qa/jivie-mobile-readiness-20261020/server-preparation/`:
`verification.json`, `database-comparison.json`, `backup-evidence.json`,
`source-applied.json` in `attempts.json`. Zasebna kopija je zunaj repozitorija
v ohranjenem imeniku `JivieLocalTest/20261018-mobile-two-user`.

## Pripravljeni Android paket

APK je
`build/qa/jivie-mobile-readiness-20261020/android/Jivie-Test-Android-cf97e2d.apk`,
105.705.802 B, SHA-256
`7fef105a9341b5ee6378a3d4e7004e6e0b0a028f24f077b73adbcdb79f15a72b`.
Podpis je preverjen in enak obstoječemu testnemu paketu. QA ID, ime,
različica 1.10.1 (31), secure preferences in prefix ostanejo isti.
To je debug paket za poznejši priklop razhroščevalnika.

Vseh sedem native knjižnic je bajtno enakih zadnjemu ohranjenemu debug
paketu, tudi sodium, sqlite3mc in Flutter. Štiri zaklenjene konfiguracije
odvisnosti so nespremenjene. Pregledane QA razlike obsegajo pet obstoječih
datotek za izolacijo/transport in en diagnostični pomočnik; stari poslovni
diagnostični ovitki niso preneseni.

Gradnja je uspela v drugem poskusu; prvi je bil prekinjen zaradi pregleda
diagnostike. Preverjanje podpisa je po začetni težavi z izbiro Jave uspelo
z že nameščenim Android Studio JBR, brez nove Jave ali SDK. Ozka analiza
QA Dart datotek je čista. Ni bilo ADB ukazov, namestitve ali zagona.

`android/HANDOFF.md` vsebuje predvideno namestitev z `install -r` po
ponovnem preverjanju točne naprave in podpisa. Pripravljeni
`android/capture-android-metadata.py` preveri, da podani PID pripada
točnemu QA paketu, nato največ 180 sekund bere samo njegove dovoljene
diagnostične vrstice. Skript je statično preverjen, fizični zajem še ni.

## Skupna diagnostika

Android paket in pripravljeni iOS izvor imata isti pregledani transport in pomočnik
`qa_mobile_network_trace.dart`, SHA-256
`8a156ddac221e13bea6aa8d713c24dd2aad4765c0f25807281ef8c19ff34fcb6`.
Izpis dovoljuje 282 fiksnih metod in 16 fiksnih kod; nepoznane vrednosti
postanejo `other`. Zabeleži le status, trajanje in število prejetih bajtov.
V posameznem 180-sekundnem oknu je dovoljenih največ 512 dogodkov in ena
oznaka preseženega proračuna. Naslednje okno se obnovi, zato diagnostika
ni trajno porabljena že pred uporabnikovim dejanjem. Zunanja zajema sta
časovno omejena in zavržeta vse surove vrstice.

Glavni in neodvisni pregled TLS/diagnostike sta uspešna. Pomočnik je samo
v izoliranih testnih gradnjah; glavni izvor in produkcijska koda ostaneta
nespremenjena. Konzola, prvi dejanski telefonski zagon in razhroščevanje
še niso potrjeni. Android debug podpira poznejši Dart debugger. Za pripravljeni
iOS AOT kandidat sta predvidena native konzola in simboli, ne Dart VM
priklop. Uspešna gradnja ne dokazuje dejanskega priklopa konzole.

## Zgodovina: iOS blokiran po prvih treh poskusih

Pripravljen je izolirani izvor za isti QA bundle ID, service in Keychain
skupino. Obstoječi razvojni podpisnik je veljaven, profil vključuje
ohranjeni iPhone 11 in velja do 18. oktobra 2027. Zaklenjena offline priprava,
ozka Dart analiza in konfiguracijski korak so uspeli. Naprava ni bila
poizvedovana, nameščena ali zagnana.

Trije poskusi native arhiva so odpovedali pred prevajanjem:

1. Globalna ročna nastavitev profila je vsilila profil aplikacije tudi
   knjižnicam, ki profila ne podpirajo.
2. Po premiku profila v Runner je globalna točna podpisna identiteta še
   vedno povzročila konflikt pri samodejno podpisanih odvisnostih.
3. Po odstranitvi globalne identitete je v Runner konfiguracijah ostala
   podvojena nastavitev: za dodanim `CODE_SIGN_STYLE = Manual` je še vedno
   `CODE_SIGN_STYLE = Automatic`. Slednja prepiše prvo.

To je bila napaka naše priprave QA projekta, ne ugotovljena napaka aplikacije,
računa Apple ali telefona. Po tretjem poskusu je bilo delo ustavljeno brez
novega podpisanega paketa. Stari nameščeni testni paket in njegovo stanje
sta ostala nedotaknjena.

Takrat dokumentiran predlog je bila zamenjava obstoječe nastavitve samo v
treh Runner konfiguracijah, brez dodajanja podvojenih ključev ali globalnega
profila za knjižnice. Pred morebitno naslednjo gradnjo je treba statično
preveriti eno učinkovito nastavitev v vsaki konfiguraciji. V prvem naročilu
četrta gradnja ni bila izvedena. Nadaljevanje spodaj sledi šele novemu
izrecnemu uporabnikovemu naročilu; testni računi in stanje ostanejo isti.

Zgodovinski dokazi: `ios/native-attempts.json`,
`ios/LATER_SESSION.md` in dnevniki vseh treh arhivov v istem imeniku
priprave. Prvotni `readiness-evidence.json` je shranjen tudi kot
`ios/signing-fix-20261020/previous-readiness-evidence.json`.

## iOS popravek po novem naročilu: paket pripravljen

Uporabnik je izrecno naročil: »Implementiraj popravek. Ce ga ne mores sam,
me pocakaj da pridem domou.« Popravek je izveden brez posega uporabnika,
naprave ali računa Apple.

Najprej so odstranjeni trije podvojeni ključi. Statični pregled in dejanski
`xcodebuild -showBuildSettings` potrdita eno nastavitev v vsaki od treh
Runner konfiguracij ter odsotnost vsiljenega profila pri 43 odvisnostih.
Prvi arhiv po novem naročilu nato razkrije dodatni vzrok: obstoječi profil
upravlja Xcode, zato ni združljiv z ročnim načinom.

Končni popravek ima v Runner konfiguracijah eno `CODE_SIGN_STYLE = Automatic`
in splošno `Apple Development`, brez izrecnega UUID profila ali certifikata.
Knjižnicam se nastavitve ne vsiljujejo. Tudi ta popravek je pred gradnjo
pregledan statično, z učinkovitimi nastavitvami in neodvisnim pregledom.
Ukaz za arhiv nima globalnih podpisnih nastavitev, `allowProvisioningUpdates`,
registracije naprav ali cilja fizične naprave.

**Drugi arhiv po novem naročilu uspe.** Xcode uporabi isti že obstoječi
lokalni profil `50458f86-da56-4cef-81e7-873a8fecef4f` in isti podpisni
certifikat. Ni ustvarjanja novih profilov, novih podpisnih pravic ali
spremembe Apple računa. Zgodovina prvih treh napak ter novega neuspelega
ročnega poskusa je ohranjena; po uspešnem arhivu ni nove gradnje.

Paket je v
`build/qa/jivie-mobile-readiness-20261020/ios/signing-fix-20261020/automatic-existing-profile/Jivie-Test-iOS-current-development.ipa`,
16.460.353 B, SHA-256
`51a42425076cad618fb96aaf8e1f71facd5b100eac72e2b372468d1216e62651`.
V istem imeniku je preverjeni arhiv z `Runner.app`.

Preverjeni so strict/deep podpis, dejanski profil z vključenim iPhonom 11,
testni bundle ID, ime Jivie Test, različica 1.10.1 (31), service in izključna
testna Keychain skupina. Ni produkcijskih URL shem, Firebase konfiguracije
ali APNs entitlements. Razvojni podpis ostane namenjen testni namestitvi.

sqlite3mc je po odstranitvi podpisa bajtno enak prejšnjemu kandidatu.
sodium ni bajtno enak: razlikuje se 16-bajtni `LC_UUID`, pri podpisanem
izdelku tudi podpisni blok. Vseh 14 sekcij kode/podatkov in izvozov se ujema;
to sta neodvisno potrdila dva pregleda. Knjižnica ni bila zamenjana ali
popravljena. SDK, zaklenjene odvisnosti in 1.760 vhodov izoliranega izvora
ostanejo vezani na manifest; glavni zamrznjeni izvor je nespremenjen.

`artifact-evidence.json`, `readiness-evidence.json`, dokazi nastavitev,
native primerjava in dnevnik uspešnega arhiva so v istem imeniku.
Vrhnja `ios/HANDOFF.md` in priprava konzole kažeta na novi preverjeni
paket. **Namestitev, zagon, telefonski scenariji in dejanski priklop konzole
niso izvedeni.** Android, testni strežnik in produkcija v tem nadaljevanju
niso spremenjeni.
