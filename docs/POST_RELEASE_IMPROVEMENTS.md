# Nadgradnje po javni objavi prenove Jivie

Ta seznam zbira izboljšave za faze po javni objavi velike nadgradnje z E2EE in prenovljeno sinhronizacijo. Dodajamo jih ob uporabniškem preizkušanju. Vpis na seznam sam po sebi ne pomeni naročila za izvedbo ali potrditve pripravljenosti celotne izdaje.

## Potrjeno za poznejšo fazo

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

### Enoten prehod od opravila do urejanja

**Izvedeno lokalno 27. oktobra:** običajne poti odprejo predogled, nato izrecno **Uredi opravilo** ob veljavni pravici. Novi ciljni widget testi PASS; fizični pregled še sledi. Spodaj ostaja opis prvotne ugotovitve.

Skupni pregled trenutno lahko odpre predogled z dodatnim gumbom Uredi opravilo, pot iz projekta pa neposredno urejevalnik. Pri mobilnem testu je bilo to razumljeno kot razlika med Androidom in iOS, čeprav pregledani poti nimata pogoja za operacijski sistem.

Izbrati enoten, jasno prepoznaven način pregledovanja in urejanja ter preveriti število klikov. Predogled ne sme ustvarjati vtisa izgubljenih pravic. To je predlog za dogovor, ne že potrjena sprememba navigacije.

### Jasnejši prikaz priprave računa ob zagonu

**Pregled 27. oktobra:** trenutna presoja začetne priprave je izvorno pregledana; nov konkreten vzrok utripanja ni izoliran. Brez spremembe varoval na slepo. To ostaja opazovanje za novo mobilno gradnjo, ne potrjena napaka trenutne kode.

Na Samsungu se je 25. oktobra pred Utripom na kratko pokazal in izginil zaslon, ki ga je uporabnik opisal kot zaslon za potrditev. Točna identiteta tega zaslona ni bila potrjena. Preveriti prehode med nalaganjem stanja računa in prikazom čarovnika, da že zaključena priprava ne povzroča zavajajočega utripanja zaslonov. Resnično potrebno soglasje mora še vedno ostati izrecno.


## Česa ta dogovor ne prestavlja

Zaščita podatkov, preprečevanje tihih prepisov in pravilno preverjanje dostopa ostanejo zahteve trenutne izdaje. Dogovor o ročnem razreševanju osnutka ne potrjuje še odprtih preizkusov obnove in nadgradnje ter ne rešuje prevzema novih pravil urejanja v starih prostorih.

Opozorilo Obnova celotne namestitve v obstoječi iOS testni namestitvi ostaja ločena ugotovitev trenutnega testiranja. Ne prestavljamo samodejno morebitne napake obnove v poznejšo izdajo.

## Dodajanje novih ugotovitev

Za novo točko zapišemo datum, uporabnikov primer, trenutno obnašanje, želeni rezultat in status: potrjeno za pozneje ali predlog. Izguba podatkov, napačen prejemnik, tih prepis in nedovoljen dostop se obravnavajo takoj v trenutni izdaji, ne kot običajna poznejša izboljšava.
