# Nadgradnje po javni objavi prenove Jivie

Ta seznam zbira izboljšave za faze po javni objavi velike nadgradnje z E2EE in prenovljeno sinhronizacijo. Dodajamo jih ob uporabniškem preizkušanju. Vpis na seznam sam po sebi ne pomeni naročila za izvedbo ali potrditve pripravljenosti celotne izdaje.

## Potrjeno za poznejšo fazo

### Preprosta razlaga obnovitvene datoteke ob povabilu

**Izvedeno 31. oktobra 2026:** razumljiv naslov, kratka razlaga glede na obseg datoteke in dodatna razlaga v oknu; napredek ostane. Ciljne lokalne kontrole PASS. Dejanski mobilni preizkus nove izdaje še sledi. Podrobnosti v [načrtu in izidih](INVITATION_SIMPLIFICATION_2026_10_31.md). Spodaj ostaja prvotni dogovor.

Uporabnikov primer: prejemnik povabila je prišel na zaslon »Obnova celotne
namestitve«. Besedilo na tem koraku je po uporabnikovi oceni prezapleteno in
ne pojasni dovolj preprosto, zakaj naj shrani datoteko.

**Dopolnitev 31. oktobra 2026:** na tem koraku spremeniti tudi naslov
»Obnova celotne namestitve« v bolj razumljiv naslov. Uporabnikov predlog:
**»Shrani obnovitveno datoteko«**.

Želeno osnovno besedilo:

> Ta datoteka ti bo pomagala, če izgubiš geslo in napravo. Zato jo shrani na
> varno mesto. Več si lahko prebereš tukaj.

Beseda **»tukaj«** naj bo povezava, ki odpre dodatno obrazložitev. Daljša
razlaga sodi za to povezavo; osnovni zaslon naj ostane kratek in razumljiv.
Po zaprtju razlage se uporabnik vrne na isti korak z ohranjenim stanjem.

Za dodatno obrazložitev pripraviti razumljivo pojasnilo namena datoteke,
varnega shranjevanja in uporabe ob izgubi dostopa. Pri pripravi besedila
preveriti dejanski obseg datoteke v tem toku ter pojasniti razliko med obnovo
dostopa in varnostno kopijo vsebine, da ne obljubljamo obnove vseh podatkov
samo s to datoteko. Končno daljše besedilo še ni dogovorjeno.

Merilo dokončanosti: na tem koraku po povabilu je prikazan razumljiv naslov
(predlog »Shrani obnovitveno datoteko«) in kratko besedilo;
»tukaj« odpre dodatno razlago, vrnitev pa ohrani napredek. Ta zapis naroča
dokumentiranje izboljšave, ne spremembe aplikacije ali postopka obnove.

### Razreševanje sprememb v že odprtem urejevalniku

**Posodobitev 27. oktobra:** po uporabnikovem naročilu za odpravo zbranih ugotovitev je primerjava v odprtem skupnem urejevalniku opravila izvedena lokalno: prvotno/osnutek/najnovejše, izrecna izbira spornih skupin in uporaba v osnutku. Sedem ciljnih kontrol PASS, en robni test STOP3 na testnem iskanju sporočila; mobilni pregled še sledi. Splošno združevanje drugih vrst zapisov ostaja ločen predlog. Aktualni obseg in omejitve so v [UX_FOLLOWUP_2026_10_27.md](UX_FOLLOWUP_2026_10_27.md). Spodnji dogovor opisuje prejšnje izhodišče, ne status nove izvedbe.

Dogovor 25. oktobra 2026: za trenutno izdajo uporabnik sprejme obstoječe varovalo. Če drug uporabnik spremeni isti zapis, odprti neshranjeni osnutek ostane ohranjen. Obrazec opozori na novejšo različico. Poskus shranjevanja zastarelega osnutka se ustavi; uporabnik lahko svoje besedilo skopira, odpre zadnjo različico in spremembo ponovno vnese.

Na Samsungu in iPhonu je bilo potrjeno, da prihod spremembe ohrani neshranjen osnutek in da zastarelo shranjevanje ne pošlje prepisa na strežnik. Ročno kopiranje v tej fazi ni več razlog za ustavitev preizkušanja ali samostojna ovira za objavo.

Poznejša izboljšava naj omogoči primerjavo izvorne različice, uporabnikovega osnutka in zadnje shranjene različice v istem postopku. Nepovezane spremembe se lahko združijo; pri nasprotujočih spremembah uporabnik izbere ali sestavi končno vsebino. Brisanje potrebuje razumljivo ločeno odločitev. Osnutek mora ostati ohranjen tudi ob novi spremembi med odločanjem ali ob neuspešnem shranjevanju.

Merilo uspeha: uporabnik lahko razreši primer brez kopiranja v drugo aplikacijo, nobena tuja sprememba pa se ne prepiše brez jasne odločitve. Obstoječe preverjanje pravic, različic in podpisanih zahtev ostane obvezno.

### Prenova uporabe vrta

Izrecen dogovor 25. oktobra 2026: prenovo vrta pustimo za poznejšo fazo, po tej izdaji. Izboljšati preglednost risanja, prehajanja med prikazi, urejanja razporeda ter izbire sezone in kultur. Trenutni sklop ne posega v ta modul.

Prvotna napaka shranjevanja sezone in kultur je medtem odpravljena; uporabnik je isti mobilni postopek potrdil kot uspešen. Tega uspešnega testa ne ponavljamo. Prenova uporabniškega poteka je ločena od že popravljenega shranjevanja.

## Predlogi za razvrstitev

### Vnos povabila: pika brez samodejnega presledka

**Izvedeno 31. oktobra 2026:** email/link vnos brez samopopravkov, predlogov, velikih začetnic in smart punctuation; lokalni widget kontroli PASS. Obnašanje konkretne sistemske tipkovnice ostaja mobilna potrditev. Prvotna ugotovitev: Pri
vpisovanju prejemnika povabila, posebej e-naslova, pika ne sme povzročiti
samodejnega presledka. Preveriti vrsto tipkovnice, samopopravke in oblikovanje
vhodnega polja na Androidu in iOS. Vnos `ime.priimek@example.com` mora ostati
točno tak, brez samodejno dodanih presledkov ali drugih sprememb. Ne spreminjati
tiho že vnesenega naslova v drug naslov. Za zdaj samo zapis za poznejši popravek.

### Potrditev e-pošte s povezavo

**Izvedeno 31. oktobra 2026:** povezava z izrecno potrditvijo v aplikaciji ali brskalniku, stara koda ostane. Varovana vezava in local/backend/HTTP seam kontrole PASS; fizični mail-to-app tok še ni preverjen. Dve kartični kontroli ostajata STOP3; glej [izide](INVITATION_SIMPLIFICATION_2026_10_31.md). Prvotni predlog: Trenutni obrazec
zahteva prenos potrditvene kode iz e-pošte v aplikacijo. Prednostni potek naj
bo povezava v sporočilu, ki odpre aplikacijo in omogoči potrditev pravega
računa; koda naj ostane rezervna možnost, zlasti pri odpiranju e-pošte na
drugi napravi. Predvideti tudi odpiranje povezave na računalniku in osvežitev
potrjenega stanja v že odprti aplikaciji brez ponovnega začetka čarovnika.

Povezava mora biti časovno omejena, enkratna in vezana na pravi račun,
strežnik ter zahtevani e-naslov. Sam predogled povezave v poštnem programu
ne sme porabiti potrditve. Potrditev e-pošte ne sme samodejno sprejeti
povabila ali prijaviti drugega računa. To je zapis predloga, ne naročilo
za spreminjanje trenutnega živega preizkusa.

### Vrstni red potrditve e-pošte in obnovitvene datoteke

**Izvedeno 31. oktobra 2026:** Potrdi e-pošto je glavno dejanje, shranjevanje datoteke se pokaže po potrjenem statusu istega računa/naprave. Potrjen naslov ne kaže ponovne potrditve. Posebna integracija čarovnika PASS2. Email povabila zdaj uporablja Član/Bralec in napoti na točne pravice, namesto splošne obljube polnega dostopa.

**Dodatna ugotovitev živega pregleda, posnetek 011:** po shranitvi datoteke
se aplikacija vrne na pregled povabila. Ta kaže »Dostop: Član«, medtem ko
je izvirno uporabnikovo deljeno besedilo istega povabila navajalo »Polni
dostop (tudi brisanje vsebine in upravljanje članov)«. Preveriti skladnost
opisov in dejansko ponujeno vlogo pred zaključkom pregleda. Za zdaj gre
za opaženo neskladje besedila; napačno dodeljene pravice niso dokazane.

**Predlog uporabnika in živ pregled 31. oktobra 2026; še ni izvedeno.**
Na iPhonu je pred potrditvijo naslova že prikazan glavni gumb »Shrani
obnovitveno datoteko«, potrditev pa je manj poudarjena in imenovana »Potrdi
kodo iz e-pošte«. Če je potrditev pogoj za naslednji korak, naj bo najprej
glavno dejanje **Potrdi e-pošto**, shranjevanje datoteke pa naj se pokaže po
uspešni potrditvi. Upoštevati tudi načrtovano potrjevanje s povezavo.

Živi preizkus: koda je bila uspešno sprejeta, zaslon kaže »Potrjen naslov«,
vendar še vedno ponuja »Potrdi kodo iz e-pošte«. Po uspehu naj prikazuje
potrjeno stanje in jasno naslednje dejanje; ponovna potrditev ni potrebna.
Posnetka 008 in 009 sta v zbirki za končno Word poročilo. Koda ni zapisana
v dokumentacijo. Med pregledom ni bila spremenjena produktna koda.

### Enoten prehod od opravila do urejanja

**Izvedeno lokalno 27. oktobra:** običajne poti odprejo predogled, nato izrecno **Uredi opravilo** ob veljavni pravici. Novi ciljni widget testi PASS; fizični pregled še sledi. Spodaj ostaja opis prvotne ugotovitve.

Skupni pregled trenutno lahko odpre predogled z dodatnim gumbom Uredi opravilo, pot iz projekta pa neposredno urejevalnik. Pri mobilnem testu je bilo to razumljeno kot razlika med Androidom in iOS, čeprav pregledani poti nimata pogoja za operacijski sistem.

Izbrati enoten, jasno prepoznaven način pregledovanja in urejanja ter preveriti število klikov. Predogled ne sme ustvarjati vtisa izgubljenih pravic. To je predlog za dogovor, ne že potrjena sprememba navigacije.

### Jasnejši prikaz priprave računa ob zagonu

**Aktualno 31. oktobra 2026:** logotip → Utrip zadnjega prostora je bil izveden v ločenem sklopu 27. oktobra; tukaj ga ne ponavljamo. Nova email povezava počaka isti začetni pregled, da je njeno okno nad zahtevanim čarovnikom (nova lokalna kontrola PASS1). Prvotni zapis spodaj je zgodovinska ugotovitev.

**Pregled 27. oktobra:** trenutna presoja začetne priprave je izvorno pregledana; nov konkreten vzrok utripanja ni izoliran. Brez spremembe varoval na slepo. To ostaja opazovanje za novo mobilno gradnjo, ne potrjena napaka trenutne kode.

Na Samsungu se je 25. oktobra pred Utripom na kratko pokazal in izginil zaslon, ki ga je uporabnik opisal kot zaslon za potrditev. Točna identiteta tega zaslona ni bila potrjena. Preveriti prehode med nalaganjem stanja računa in prikazom čarovnika, da že zaključena priprava ne povzroča zavajajočega utripanja zaslonov. Resnično potrebno soglasje mora še vedno ostati izrecno.


## Česa ta dogovor ne prestavlja

Zaščita podatkov, preprečevanje tihih prepisov in pravilno preverjanje dostopa ostanejo zahteve trenutne izdaje. Dogovor o ročnem razreševanju osnutka ne potrjuje še odprtih preizkusov obnove in nadgradnje ter ne rešuje prevzema novih pravil urejanja v starih prostorih.

Opozorilo Obnova celotne namestitve v obstoječi iOS testni namestitvi ostaja ločena ugotovitev trenutnega testiranja. Ne prestavljamo samodejno morebitne napake obnove v poznejšo izdajo.

## Dodajanje novih ugotovitev

Za novo točko zapišemo datum, uporabnikov primer, trenutno obnašanje, želeni rezultat in status: potrjeno za pozneje ali predlog. Izguba podatkov, napačen prejemnik, tih prepis in nedovoljen dostop se obravnavajo takoj v trenutni izdaji, ne kot običajna poznejša izboljšava.
