# Združeno pridobivanje pravic — 20. oktober 2026

## Naročilo in meja te nadgradnje

Uporabnik je naročil prvi, omejen korak: pravice pridobivati skupaj za
račun in celoten prostor z njegovimi projekti. Implementacija vključuje
odjemalca in FamilyHub; sprememba urnika sinhronizacije ni del tega koraka.
Podagenti GPT-6.1 Sol/high izvajajo strežniški in odjemalčev del ter
neodvisni pregled, glavni agent pregleduje integracijo.

Združen prenos mora ohraniti posamezne projektne vloge, ločene finančne
pravice, neposredni dostop do projekta brez dostopa do starša, preverjanje
podpisanih dokazil, preklic in vezavo na trenutno identiteto. Združen odgovor
ni dovoljenje za skupno širšo pravico. Vsako branje in pisanje na strežniku
še vedno preveri dostop. Nove dolgoročne shrambe dovoljenj ali daljšega TTL
ne uvajamo.

Obstoječi Mac A-r12/B-r13, Docker18811 in mobilni testi ostanejo ohranjeni.
Produkcije, trgovin, SDK, odvisnosti, obnovitvenih datotek ali uporabniških
podatkov ta naloga ne spreminja. Že uspešnih N0–N6 in izvedenega odvzema N7
ne ponavljamo. Za posamezno novo težavo velja največ tri poskuse; nato jo
zapišemo in nadaljujemo neodvisna preverjanja.

## Izhodiščni dokazi

[Mac zapisnik](E2EE_MAC_SHARING_TEST_2026_10_19.md) vsebuje zadnji konkretni
native rezultat: 412 HTTP zahtevkov v enem ciklu A, vsi 200. To je meritev
celotnega cikla konkretnega računa, ne število zahtevkov za same pravice
in ne splošna konstanta vseh namestitev. Prejšnja omejena optimizacija ni
dokazala bistvenega prihranka.

Vir pred to nadgradnjo načrtuje naslednji prazen cikel 60 sekund po koncu
prejšnjega. Lokalna sprememba zahteva prenos, vrnitev v aplikacijo preveri
rok, napake ali nerešeno delo imajo zamike 15/30/60 sekund in upoštevajo
strežniški Retry-After. Trisekundni lokalni pregled urnika ni polni omrežni
prenos na tri sekunde. Trenutni Firebase background handler prikazuje
obvestila in ne odpira baze ali sinhronizira vsebine.

## Možno nadaljevanje — v tej nadgradnji ni izvedeno

1. **Osvežitev ob uporabi zaslona.** Ob odprtju Financ, opravil ali drugega
   zaslona pokazati lokalne podatke in preveriti le potrebno vsebino ter njene
   odvisnosti; združiti sočasne zahteve istega zaslona/prostora.
2. **Vrnitev aplikacije v aktivno stanje.** Preveriti odprti zaslon in skupne
   spremembe dostopov; odpraviti redne polne prazne cikle v mirovanju.
3. **Petminutna omejitev ponovnega preverjanja pravic.** Uporabnikov predlog
   je omejitev ob dogodku, ne časovnik vsakih pet minut. Prvi vstop v nov
   prostor, znana sprememba pravic ali zavrnitev dostopa potrebujejo ustrezno
   sveže preverjanje. Točna pravila in varna povezava s kriptografskimi
   dokazili še potrebujejo načrt; današnja petsekundna meja ni podaljšana.
4. **Tihi push kot namig za osvežitev.** Obvestilo brez ključev in vsebine
   označi spremenjeni obseg. Prenos lahko počaka na naslednje odprtje ali
   aktivacijo. Dostava ni zagotovljena, zato mora uporaba aplikacije znati
   odkriti spremembe tudi brez obvestila. Potrebna je tudi pot za namizne
   platforme; obstoječi mobilni Firebase ni dokaz podpore na Macu.
5. **Poceni preverjanje različice in prenos samo razlik.** Če se podatki niso
   spremenili, ne prenašati in preverjati celotne vsebine znova. Zahteva
   opredeljeno popolnost, odstranitev dostopa in nadaljevanje po prekinitvi.
6. **Združena branja finančne vsebine.** Odpraviti ponovitve med glavnimi
   financami, izbiro računov in povezanimi plačili z eno preverjeno podlago.
   To je ločeno od današnjega združevanja pravic. Podvojena branja niso dokaz
   podvojenih knjižb ali napačnega salda.

Pri teh predlogih ostane takojšnje pošiljanje lastnih sprememb, trajna vrsta
in varno nadaljevanje po prekinitvi. Če ni periodičnega preverjanja ali
takojšnje obdelave pusha na odprtem zaslonu, so tuje spremembe lahko vidne
šele po naslednji aktivaciji, odprtju ali ročni osvežitvi. Že prenesenih
kopij z odvzemom pravic ni mogoče zanesljivo odstraniti z nepovezane naprave.

## Dokazi izvedbe

Izvedba v izvoru in novi ciljni preizkusi so zaključeni. To ni native
namestitev, sprememba gostovanja ali potrditev produkcijske pripravljenosti.

### Pogodba in izvor

`capabilities.cryptoAuthoritySnapshotVersions: [1]` oglašuje novo bralno
metodo `crypto2.authority.snapshot`. Podpira izbirni `scopeId` in
`includeChildren`, `scopeLimit` (največ 20), `afterScopeId` ter kazalce
`accountAfterGeneration`, `directoryAfterGenerations` in
`lifecycleAfterRevisions`.

Brez izbranega prostora vrne račun in omejeno stran vidnih obsegov. Izbrani
prostor združi z dovoljenimi projekti; izbor projekta lahko zajame tudi
dostopnega starša. Če starš ni dostopen, njegovih ali sosednjih pravic ne
vključi. Vsak vnos ima originalno metodo, točne parametre ter originalni
rezultat ali dovoljen javni razlog zavrnitve. Ni poljubnega pošiljanja
vgnezdenih metod in ni vsebine zapisov ali zasebnih ključev.

Odgovor veže `version`, `serverId`, `accountId` in `deviceId`. Obstoječi
preverjevalniki še vedno preverjajo podpise, zaporedje, znane korene in
pravice. Odjemalec hrani samo začasen material iste preverjene operacije,
z obstoječo največ petsekundno mejo, vezavo na identiteto, življenjski cikel,
generacijo in varne pine. Mutacije in zapis opažanja prekinejo ponovno
uporabo. Prepozen odgovor ali odgovor po menjavi identitete ni uporabljen.

Stari strežnik brez oglaševane zmožnosti uporablja posamezna branja;
neprepoznana zmožnost ne povzroči poskusa nepodprte podpisane metode.
Manjkajoče strani, zgodovinska dokazila in čakajoče zasebne zmožnosti
uporabijo obstoječe točne poti. Odjemalec ne sklepa o odvzemu iz manjkajočega
vnosa. `complete` pomeni dokončan izbor paketov, **ne** kriptografsko
popolnost vsake zgodovine; vsaka originalna stran ohrani svoje kazalce.

Meje paketa so 20 obsegov, 512 vnosov, 256 sestavljenih bralnih klicev in
1.250.000 bajtov strežniškega odgovora. Presežek je označen kot nepopoln,
manjkajoča dokazila pa ostanejo na točnih poteh. Pri velikih prostorih zato
ne obljubljamo enega neomejenega odgovora: v tej izvedbi odjemalec manjkajoče
dele lahko pridobi s posameznimi branji. Obstoječi pomožni bralniki lahko
pregledujejo daljše zgodovine; meje paketa niso trda meja vseh SQL poizvedb
ali časa procesorja.

MariaDB/MySQL ima za ta endpoint samostojno transakcijo READ ONLY / REPEATABLE
READ brez globalnega zaklepa. Prvo branje identitete določi skupen pogled;
vgnezdena branja uporabljajo isti pogled brez mešanja z novejšimi zaklenjenimi
vrsticami. Naslednja nova zahteva po potrjenem odvzemu je zavrnjena.
SQLite uporablja bralni `BEGIN`. Običajne poti ohranijo svojo prejšnjo
transakcijsko politiko.

Pregled je odkril, da ena stara bralna pot posodablja izpeljane zastavice
zaprtja kandidatov. Ta vzdrževalni zapis se preskoči samo v novem snapshotu
pri `author(write: false)`; rezultat branja ga ne uporablja, pisalne kontrole
in običajne poti ga še naprej izvajajo. Dodatki, ki zahtevajo zapis, niso
predstavljeni kot zavrnitev dostopa, ampak so iz paketa izpuščeni za običajno
preverjeno pot.

Ključne datoteke:

- `lib/organizer/data/e2ee/crypto_authority_snapshot.dart`
- `lib/organizer/data/e2ee/account_directory_repository.dart`
- `lib/organizer/data/e2ee/session_crypto_access.dart`
- `server/plugins/FamilyHub/Model/NativeCryptoAuthoritySnapshotV2.php`
- `server/plugins/FamilyHub/Model/NativeCryptoV2Service.php`
- `server/plugins/FamilyHub/Model/NativeDatabase.php`
- `server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php`
- `server/plugins/FamilyHub/Model/NativeService.php`

### Ciljni rezultati in poskusi

| Kontrola | Rezultat |
| --- | --- |
| Novi odjemalčev helper: združevanje, nespremenljiv odgovor, zavrnitev, identiteta, potek, mutacije, združljivost in velikost | 11 PASS |
| Nova sočasna čakalca: stari strežnik, potek in zaprtje ne sprožijo novega snapshot zahtevka | 1 PASS v poskusu 2; prvi je razkril podvojeno preverjanje zmožnosti, popravljeno |
| Dejanski HTTP: račun + podpisani starš/projekt + lifecycle, enaki preverjeni rezultati, ponarejen podpis zavrnjen brez spremembe pina | 1 PASS v poskusu 2 |
| SQLite: točni rezultati/zavrnitve, račun, prostor/projekt, omejitve in kazalci, neposredni projekt, odvzem, brez poljubnih zapisov | 42 novih kontrol PASS v poskusu 3 |
| MariaDB 10.11.19: dve PDO povezavi, sočasni odvzem članstva/naprave, usklajen pogled, naslednja zavrnitev, READ ONLY in povrnitev običajnih transakcij | 6 novih kontrol PASS v prvem poskusu |

Strežniški preizkus uporablja 47 obstoječih pripravljalnih kontrol za
sintetične podpisane podatke; niso štete med 42 nove kontrole. Prva dva
poskusa sta odkrila omenjeni vzdrževalni zapis v bralni poti. Četrtega teka
ni bilo. Prvi HTTP poskus nima zajetega končnega rezultata zaradi napake
testnega ogrodja; ni PASS in ne dokazuje napake aplikacije. Delno stanje
lastnika ostane ohranjeno. Drugi poskus uporablja že prej pripravljen drugi
testni račun z obstojno lokalno testno shrambo; ni ponastavitve starih QA
računov ali ponovitve njihovega odvzema.

Neodvisni in glavni pregled nista našla preostale blokirajoče vrzeli pri
avtorizaciji. PHP lint spremenjenih runtime datotek in novih ciljnih testov
je PASS. Glavni pregled je odkril še neujemanje podpisov štirih podedovanih
testnih metod po dodanem neobveznem argumentu transakcije. Trije testni
pripomočki zdaj argument sprejmejo in posredujejo; njihovi obstoječi hooki
so ohranjeni. Lint in izolirano nalaganje petih dejanskih testnih razredov
sta PASS, brez ponovitve njihovih celotnih scenarijev.
`git diff --check` je PASS. Končna celotna `flutter analyze --no-pub`
ima 0 napak, 0 opozoril in 515 informacijskih priporočil; zaradi priporočil
vrne izhodno kodo 1. Nove datoteke imajo ciljno analizo brez ugotovitev.
Ni ponovitve celotnih starih testnih zbirk.

### Izmerjeni učinek in meja trditve

Dejanska odjemalčeva pot `SessionCryptoAccess.withVerifiedOperation`,
`account.directory.requireFresh`, `currentHead` in `CryptoLifecycleEvidence`
je prek novega izoliranega HTTP strežnika preverila isti račun in dva obsega:

| Meritev | Posamezne poti | Skupni odgovor |
| --- | ---: | ---: |
| Dejanski HTTP zahtevki z odkrivanjem zmožnosti | 14 | 4 |
| Bajti dekodiranih rezultatov JSON | 32.460 | 67.991 |
| Največji skupni rezultat JSON | — | 65.366 |

Primerjava 14 vključuje en zahtevek zmožnosti in 13 originalnih branj;
izključeni snapshot je v testnem transportu zavrnjen pred omrežjem.
Štirje zahtevki vključujejo zmožnosti, skupni odgovor in dve preostali točni
branji. Zato je prihranek 71 % glede na isto nadgrajeno pot z izključenim
paketom oziroma približno 69 % glede na 13 prvotnih branj brez odkrivanja.
Bajti JSON so približno 2,09-krat večji zaradi vnaprej združenih dokazil;
to ni meritev HTTP/TLS bajtov ali dokaz prihranka pasovne širine.

Celoten native cikel 412 zahtevkov ni ponovno izmerjen. Zmogljivost velikih
prostorov, daljših zgodovin in celotne finančne sinhronizacije ostaja ločeno
nadaljnje preverjanje, ne potrjen rezultat te nadgradnje.

Zasebni lokalni dokazi: `/tmp/crypto2-authority-snapshot-attempt3.log`,
`/tmp/crypto2-authority-concurrency-attempt1.log`,
`/tmp/jivie-authority-snapshot-http-attempt2.log` (SHA-256
`fb88d5d39a8cfe97eb96b03a1ab70bc3d071b61aeb4bc142b4657c4ed53b8822`) in
`/tmp/jivie-authority-root-20261020/flutter-analyze-final.log`.
Datoteke FILE, poverilnice in sintetične baze niso v repozitoriju.
Novi HTTP vsebnik `jivie-authority-batch-20261020` je po preizkusih ustavljen,
njegovo stanje ohranjeno. Nova začasna MariaDB vsebnika sta odstranjena.
Obstoječi QA vsebniki niso ustavljeni ali spreminjani.

### Namestitev

Za uporabo združenega branja sta potrebni nova aplikacija in nova koda
FamilyHub. Ni spremembe sheme ali migracije uporabniških podatkov. Stara
aplikacija na novem strežniku uporablja obstoječe metode; nova na starem
uporablja posamezna branja. Nadgradnja gostovanja, nova native gradnja in
namestitev niso izvedene. Prejšnje odprte meje N7/P0/mobile/P8 ostanejo.
