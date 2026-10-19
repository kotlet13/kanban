# Načrt E2EE, šifrirane lokalne shrambe in obnovitvene datoteke

17. oktober 2026. **Izvirni načrt P0–P8; pozneje naročena izvorna izvedba
je v zaključnem preverjanju.** [Izvedba](E2EE_IMPLEMENTATION.md) vodi dejanske
rezultate in še nedokončane povezane poti, [protokol](E2EE_PROTOCOL.md) pa
trenutne meje zaupanja. Migracija, sveža FILE obnova in povezani poslovni
zaključek so potrjeni; generacija B in sveža FILE/priponka sta potrjeni;
seznam/umik migriranih opomnikov use3 sta potrjena z nadaljevanjem istega stanja.
Celotni Flutter66 je razkril regresije; prizadeti ponovitvi69/70 sta jih zaključili.
Zadnja analiza ima0 error/0 warning ter510 info; to ni nov sveži celotni tek.
Točne rezultate in meje ponovitev vodi izvedbeni dokument.
Neodvisni pregled P0 in fizična/native/izdajna merila P8 ostajajo odprti;
prvi hladni prenosi imajo dokumentirano omejitev zmogljivosti. Ni dovoljenja
za živo namestitev, novo gradnjo ali trgovinsko oddajo. Spodnji prvotni obseg
načrtovanja je zgodovinski, ne nova omejitev pozneje naročenih izvornih popravkov.
Izhodišče pregleda je `4c6b35d582d4873641c6c27bb7bbfa10da821999`.
Načrt vključuje nove organizacijske finance in hierarhični izbor iz izvora,
ki ju nameščena oziroma oddana aplikacija 1.10.1 (31) še ne vsebuje.

Cilj je, da uporabnik po posodobitvi ohrani svoje podatke in običajno delo.
Ob prvem odprtju opravi en nadaljevalni čarovnik **»Dodajanje obnovitvenega
ključa«**: shrani obnovitveno datoteko, aplikacija preveri obnovljivost,
šifrira lokalno shrambo in pripravi oziroma izvede prehod povezanih prostorov
na šifriranje od konca do konca. Enaka priprava se vključi v prvo povezavo
s strežnikom. Uporabniku ni treba prepisovati dvanajstih besed.

Strežnik po končanem prehodu hrani šifrirano vsebino in dogovorjene tehnične
metapodatke. Nima zasebnih ključev za odklep vsebine. Obnovitvena datoteka
nastane in se bere na napravi; uporabnik jo shrani ali izrecno deli prek svoje
poštne aplikacije. Jiviejev SMTP je ne pošilja.

## 1 Obseg naročila in merila uspeha

To naročilo obsega načrt, povezave na izvor in merila prihodnjega preverjanja.
Ne dovoljuje spremembe podatkovnih formatov, namestitve na gostovanje, novih
gradenj ali trgovinskih oddaj. Poznejša izvedba sledi spodnjim zaporednim
izhodnim merilom, ne neposredni pretvorbi produkcije po branju dokumenta.

Obvezne lastnosti končne nadgradnje:

1. Šifrirana lokalna baza in aplikacijsko upravljane datoteke, vključno z
   osnutki, čakajočim delom, slikami, priponkami in obnovitvenimi arhivi.
2. E2EE za vsebino osebnih in skupnih prostorov, projektov, financ, preglednic
   in dokumentov; samostojno lokalni podatki ostanejo lokalni.
3. Ohranitev pravic deljenja, zgodovine in finančnih povezav; projektni član
   zaradi E2EE ne dobi dostopa do financ nadrejenega prostora.
4. Obnovitev z ohranjeno napravo ali uporabnikovo obnovitveno datoteko.
   E-poštna ponastavitev prijave sama ne odklene E2EE vsebine.
5. Potrjena e-poštna identiteta za pisanje povezanega računa ter obvestila ob
   začetku in zaključku obnove oziroma spremembah naprav.
6. Nadgradnja brez tihega praznjenja, ponovne registracije, ponovnega ustvarjanja
   prostorov, preštevilčenja zapisov ali podvajanja knjižb.
7. Prekinjen korak se varno nadaljuje. Napaka, pomanjkanje prostora, izgubljen
   ključ ali nezdružljiv format nikoli ne pomenijo »ustvari prazno bazo«.

**En čarovnik ne pomeni enega nepreklicnega posega.** Lokalno zaščito je mogoče
končati brez omrežja; skupni prostor se preklopi šele, ko so izpolnjeni pogoji
vseh potrebnih ključev, podatkov in povezanih finančnih obsegov. Vmesnik mora
pošteno ločiti »naprava zaščitena«, »čaka pripravo deljenja« in »E2EE vključeno«.

## 2 Izhodišče in zemljevid kode

Podroben seznam simbolov, povezav in obstoječih regresij je v
[zemljevidu kode](E2EE_CODE_MAP.md). Številke vrstic veljajo za zgornji commit;
pred izvedbo jih ponovno preverimo na takratnem zamrznjenem izvoru.

| Področje | Sedanje stanje | Posledica za predelavo |
| --- | --- | --- |
| Lokalna baza | Drift 2.35.1, sqlite3 3.7.0, schema10; navadna SQLite datoteka | Šifrirni pogon in varno odpiranje pred vsemi porabniki baze |
| Osebna zgodovina | Stari Hive in `migration_snapshot` sta ohranjena | Zaščititi tudi izvirnik in nepoznana polja; ne le trenutnih modelov |
| Sinhronizacija | Prijava in ozadje takoj sprožita promet | Trajna zapora vsebinskega prometa pred čarovnikom in med migracijo |
| Prenosna kopija | `.vsakdan` vsebina8, lokalna baza10, filtriranje pravic | Ohraniti branje starih kopij; ni primerna za selitev celotne namestitve |
| Finance | Finance4, zapisna pogodba3, kanonična projektna knjižba z računom starša | Prehod celotne povezane komponente in nespremenjeni ID operacij |
| Gostovanje | Zadnji dokaz: FamilyHub0.15.0/schema19 na produkciji in test1 | Pred izvedbo svež zajem; izvorna različica ni dokaz živega stanja |
| Prijava | PHP preveri prejeto geslo in izda napravni žeton | Prijavno geslo v prvi fazi ne odklepa E2EE korena |
| Strežniška opravila | Berejo vsebino in iz nje ustvarjajo učinke | Ločiti slepo dostavo od vsebinske obdelave na zaupanja vredni napravi |

## 3 Meja zaščite in podatki, ki ostanejo vidni

Model varuje pred branjem baze/datotek na gostovanju, krajo strežniške kopije
in skrbniškim spreminjanjem članstev z namenom pridobitve ključev. HTTPS,
prijava, strežniški ACL in omejitve zahtev ostanejo potrebni. Šifriranje samo
ne prepreči brisanja, zadržanja ali selektivne dostave podatkov.

Zaupanja vredna je pregledana nameščena aplikacija na uporabnikovi napravi.
Napadalec na odklenjeni napravi ali zlonamerna podpisana posodobitev lahko
prestreže odklenjeno vsebino. Gostovani spletni odjemalec, katerega JavaScript
lahko zamenja isti skrbnik, nima enake meje zaupanja. V prvem prehodu E2EE
prostorov ne odklepamo v takšnem spletnem odjemalcu; njegov obstoječi lokalni
izvor se ohrani in dobi izrecno pot izvoza oziroma poznejše migracije.

| Podatki | Predlagana vidnost strežniku |
| --- | --- |
| Besedilo, naslovi, opombe, kontakti, slike, imena in bajti dokumentov | Šifrirano |
| Zneski, začetna stanja, finančni opisi, formule in vsebina celic | Šifrirano |
| E-pošta, uporabniško ime, status preverjanja, varnostni dogodki | Potrebni za račun; niso E2EE vsebina |
| Naključni ID računov/prostorov/zapisov, članstvo, vloge in revizije | Minimalni usmerjevalni metapodatki, z overjeno vezavo na vsebino |
| Velikosti, število objektov, časi prometa in dostavne naprave | Delno opazno tudi pri E2EE; ne obljubljamo anonimnosti |
| Čas generičnega oddaljenega opomnika, ciljna naprava in opaque ID | Razkrito samo, če uporabnik uporablja strežniško razporejanje |
| Računske povezave in tipi operacij | Popisati najmanjši potreben nabor za transakcije; ne puščati opisov ali zneskov v indeksih |

Navaden hash predvidljive vsebine, denimo zneska ali kratkega naslova, ni
nadomestek šifriranja. Strežniški manifesti uporabljajo hashe šifropisov;
primerjave nešifrirane vsebine ostanejo lokalne ali zaščitene s skrivnim
ključem. Javna imena prostorov in obstoječi SQL/JSON iskalni indeksi potrebujejo
enako obravnavo kot glavni `payload`.

## 4 Hierarhija ključev

Ključev ne izpeljujemo iz e-pošte, ID uporabnika, žetona seje ali gesla, ki ga
prejme PHP. Vsi novi koreni nastanejo s kriptografsko varnim generatorjem na
napravi. Različni nameni imajo ločene ključe in kontekst izpeljave.

| Ključ oziroma identiteta | Namen in hramba |
| --- | --- |
| Lokalni ključ namestitve | Naključen ključ celotne lokalne baze; ovit v sistemski varni shrambi. Življenjski cikel je neodvisen od odjave. Izbirni oziroma izrecno potrjeni izvoz za obnovo namestitve zajame vse njene particije. |
| Koren identitete in obnove računa | Ločena podpisni in prejemni korenska ključa, vezana na `serverId/accountId`. Zasebni del je dostopen z računsko obnovitveno datoteko; rutinske naprave ne hranijo istega trajnega korenskega zasebnega ključa. |
| Napravni ključi | Ločeni podpisni in prejemni ključi vsake potrjene naprave z omejenim podpisanim pooblastilom. Preklic naprave ne spremeni ID uporabnika. |
| Ključ vsebinskega obsega | Ločen za osebni prostor/projekt/finančni obseg, kjer se razlikujejo dovoljenja; verzioniran po epohah. |
| Ključ objekta ali priponke | Naključen ključ vsebine, ovit za dovoljen obseg; omogoča upravljanje velikih dokumentov brez enega globalnega podatkovnega ključa. |
| Obnovitvena skrivnost | Naključnih 256 bitov v lokalno ustvarjeni datoteki; varuje obnovitveni paket ključev in se ne pošlje strežniku. |

Obnovitveni paket na strežniku je šifriran, podpisan in verzioniran ključni
obroč. Vsak nov vsebinski ključ dobi ločene ovoje za trenutne upravičene
naprave in za javni obnovitveni ključ računa. Naprava lahko doda tak ovoj
brez poznavanja zasebnega obnovitvenega ključa. Nova vsebina in novi
projekti zato ne zahtevajo pošiljanja nove obnovitvene datoteke ob vsakem vnosu.
Ob spremembi obnovitvene skrivnosti ali korenske identitete pa je treba novo
datoteko izrecno shraniti in preveriti.

Posodobitve ključnega obroča se združujejo po trajnih ID ovojih in generacijah
s CAS; naprava, ki pozna samo del ključev, ne sme prepisati celotnega obroča
s svojim delnim posnetkom. Podpisana zgodovina pooblastil določi, kdo je smel
ovoj dodati. Preklici in tombstone se ne obudijo iz stare kopije. Obnova
preveri celotno potrebno verigo pooblastil, ne le veljavnosti poljubnega
starega napravnega podpisa.

Obnovitveni ovoj novega ključa mora biti trajno shranjen pred prvo potrjeno
vsebino pod tem ključem ali atomarno skupaj z njo. To velja tudi za novo
epoho in priponko. Če vse naprave izginejo takoj po uspešnem ACK, mora
prvotna veljavna računska datoteka obnoviti tudi ta novi ključ. Lokalni
offline zapis zato skupaj hrani vsebino in potrebne obnovitvene ovoje;
še neposlana vsebina potrebuje tudi ustrezno lokalno podatkovno kopijo.

Korenski zasebni ključi se ob nastanku ali obnovi uporabijo le v omejenem
postopku, ki pooblasti nove ločene napravne ključe. Ne ostanejo trajno v
vsaki napravi. Če napadalec pridobi tudi koren oziroma obnovitveno datoteko,
običajen preklic naprave ne zadošča; potreben je pregledan prehod korena,
novih ključev in nove datoteke. Podrobna veriga delegacij/preklicev je
obvezni del protokolarnega pregleda P0, ne lastna improvizacija nad podpisi.

Ključ celotne lokalne baze ni računski E2EE ključ in se nikoli ne prenese
na strežnik ali drugemu članu prostora. Ker baza vsebuje več profilov,
kdorkoli ima njen ključ in kopijo baze lahko bere vse v njej shranjene
dešifrirane profile. Obnova posameznega računa zato uporablja ločeno
računsko datoteko in ustvari nov lokalni ključ. Obseg celotne namestitve
je izrecno drugačen izvoz, opisan v §5.2.

### 4.1 Izbira kriptografskih knjižnic

Pred izvedbo pripravimo ločen prototip in pregled odvisnosti. Za vsebino
uporabimo overjeno šifriranje z jasno strategijo enkratnih nonce vrednosti;
obstoječi AES-256-GCM je kandidat, ne dokaz dokončanega E2EE protokola.
Ponavljanje operacije uporablja že shranjeni isti šifropis; novega telesa ne
šifriramo z isto kombinacijo ključa in nonce. AAD veže različico, identiteto,
obseg, objekt, epoho in revizijo, da kopiranje šifropisa na drug objekt odpove.

Za ovojnice ključev preverimo pregledano implementacijo HPKE; za skupinsko
upravljanje preverimo MLS ali pregledan protokol za deljene šifrirane dokumente.
**HPKE samo ne določi pravic, MLS samo ne reši zgodovine dokumentov ali
preverjanja prvotne identitete.** Ne sestavimo lastnega varnostnega protokola
samo zato, ker knjižnica ponuja AES in podpisovanje. Izbira knjižnice, serijskega
formata in protokola je izhodno merilo prve faze z neodvisnim pregledom.

Trajna dokumentna zgodovina in obnova starih ključev pomenita drugačen cilj
kot izginjajoča sporočila. Ne obljubljamo popolne tajnosti celotne pretekle
vsebine po poznejši kraji obnovitvene datoteke. Preklic varuje prihodnje
epohe in dostave; že pridobljenih kopij ne izbriše.

### 4.2 Prijava in odklep sta ločena

Sedanji `auth.login`, registracija in reset pošljejo geslo strežniku. Zato je
predlagana prva izdaja naslednja: geslo/TOTP/e-pošta odprejo sejo; obstoječa
potrjena naprava ali obnovitvena datoteka odklene podatkovne ključe. Po odklepu
jih naprava varno hrani, da uporabnik datoteke ne izbira vsak dan.

To natančneje določa prejšnji pogovorni predlog »na novi napravi zadostuje
geslo«. Takšno udobje bi zahtevalo posebej pregledan prehod na protokol, kot
je OPAQUE, ali drugo skrivnost, ki je strežnik ne pozna. Staro geslo, ki ga
je strežnik že prejemal, ni primerna nova meja zaupnosti. Ta dodatna pot ni
predpogoj za izdajo z obnovitveno datoteko in se ne uvaja napol.

## 5 Obnovitvena datoteka

Predlagani format je `.jivie-recovery` z različico formata, različico
kriptografskega sklopa, naključnim recovery ID, obnovitveno skrivnostjo,
identiteto računa/vaulta in pričakovanim prstnim odtisom korenskega javnega
ključa. Prstni odtis mora izvirati iz naprave ob nastanku, ne iz strežniškega
odgovora ob obnovi. Uvoz ima strogo omejeno velikost, preverjanje celovitosti,
zavrnitev neznane različice in jasno napako pri drugem računu/strežniku.

Datoteka brez dodatnega gesla je sama **skrivni nosilec dostopa**. Naključni
bajti ali neberljiva končnica niso dodatno šifriranje. Ne zaščitimo je samo z
geslom računa, saj bi s tem onemogočili njen namen ob pozabljenem geslu.
Izbirna dodatna zaščita datoteke je lahko poznejša možnost, ne skrita zahteva.

### 5.1 Shranjevanje in pošiljanje

Privzeti korak je sistemski »Shrani datoteko«. Ločen gumb »Pošlji prek svoje
aplikacije« odpre sistemski delilni meni. Uporabnik sam izbere svojo poštno
aplikacijo, naslov in pošiljanje. SMTP/HTTP poti FamilyHuba ne smejo prejeti
datoteke, njene skrivnosti, URL z vdelanim ključem ali celotne vsebine deljenja.
`mailto:` ni zanesljiva pot za priponke; uporabimo preverjen platformni adapter.

Začasna datoteka ima zasebne pravice in omejeno življenje. Uporabniku izbrani
aplikaciji se dodeli le potreben začasen dostop. Ne izbrišemo je pred koncem
prevzema priponke, ob naslednjem varnem zagonu pa počistimo ostanke. Ne
beležimo poti, ki vsebujejo uporabnikove osebne oznake, niti vsebine datoteke.

Vrnitev iz delilnega menija **ni dokaz dostave ali shranitve**. Čarovnik pred
končnim vključevanjem obnovitve zahteva ponovno izbiro shranjene datoteke
in lokalni preizkus odklepa preskusne ovojnice. Pri izbiri e-pošte jo uporabnik
ponovno izbere iz dejansko ohranjene priponke; ne zadostuje notranja začasna
kopija. Pred tem korakom lahko postopek prekine brez izgube izvirnika.

Predlagano besedilo: »Ta datoteka omogoča obnovitev vaših šifriranih podatkov.
Shranite jo tudi zunaj tega telefona. Ne pošiljajte je podpori. Če jo hranite
v e-pošti, lahko dostop do predala omogoči tudi dostop do podatkov.«
Če uporabnikov predal upravlja isti skrbnik gostovanja, to ni neodvisno mesto
hrambe pred tem skrbnikom. Jivie ne trdi, da je uporabnikov izvoz v e-pošto E2EE.

### 5.2 Lokalni način in več računov

Obstajata dva jasno označena obsega obnove:

- **Obnova računa**: samo njegov E2EE koren in dovoljeni vsebinski ključi,
  brez ključa celotne namestitve ali drugih odjavljenih profilov. To datoteko
  uporablja čarovnik prve povezave in obnova istega računa na novi napravi.
- **Obnova te namestitve**: ključ celotne fizične baze, tudi lokalnega dela
  brez računa in še neusklajenih zapisov. Z ustrezno kopijo baze lahko odklene
  vse v njej shranjene profile. Čarovnik pred izvozom to izrecno pokaže,
  tudi za odjavljene račune; ne imenuje je »samo moji lokalni podatki«.

Predlagani najmanj invaziven način ohrani eno bazo in ti dve ločeni datoteki.
Za uporabnika brez računa zadostuje datoteka namestitve. Ob dodajanju računa
se shrani njegova računska datoteka; pri že povezanem uporabniku čarovnik
jasno vodi oba potrebna obsega. Datoteke namestitve nikoli samodejno ne
vključimo v računski izvoz ali deljenje. Zavrnitev širšega izvoza ohrani
izvirnik in stanje čarovnika; ne pomeni dovoljenja za izgubo lokalnega dela.

**Datoteka ne prikliče podatkov z izgubljenega telefona, ki niso bili kopirani.**
Datoteka namestitve potrebuje ohranjeno šifrirano kopijo baze; računska
datoteka potrebuje strežniške šifropise ali podatkovno kopijo. Za obnovo
namestitve na drugi napravi se ustvarita nova seja in nova napravna
identiteta; kopija vsebine ne prenese zaupanja stari napravi ali članstev.

Če želimo datoteko za samo lokalne podatke, ki kriptografsko ne more odpreti
drugih profilov v isti fizični bazi, moramo pred izvedbo izbrati ločene
profilne baze ali notranje profilno šifriranje. To je dodatna arhitekturna
migracija. Sam diskovni cipher ali drugo ime datoteke te izolacije ne da.
V P0/P2 preverimo razumljivost dveh obsegov in po potrebi to odločitev
spremenimo pred pisanjem migracije, ne med prvim zagonom pri uporabniku.

### 5.3 Obnova, zamenjava in izguba

Na novi napravi uporabnik ponastavi prijavno geslo po e-pošti in po potrebi
opravi obstoječi TOTP oziroma njegov ločeni obnovitveni postopek. Nato izbere
datoteko lokalno. Naprava preveri identiteto, odklene koren in ključni paket,
podpiše vpis nove naprave ter prenese dovoljene šifropise. Uvoz ne nalaga
skrivnosti na strežnik in ne ustvarja drugega uporabnika ali drugega osebnega
prostora. Manjkajoč ključ pomeni zaklenjeno vsebino, ne prazen račun.

Datoteka ne nadomesti kopije podatkov. Nova naprava potrebuje še dosegljive
strežniške šifropise ali ustrezno prenosno kopijo. Uvoz stare kopije ne podeli
članstva in ne omogoči samodejnega pošiljanja starih operacij.

Ponovni izvoz iste računske obnovitvene identitete zahteva njen zasebni
obnovitveni material. Rutinska naprava z delegiranimi ključi ga nima
samodejno. Če je datoteka izgubljena, preostala naprava ohrani dostopne
podatke in sproži posebej pregledan postopek zamenjave obnovitvene identitete;
ne ustvari tiho nadomestnega korena. Postopek določi obnovljivost celotne
dovoljene zgodovine, podpisan prehod identitete ter ponovno preverjanje pri
drugih članih, kadar je potrebno.

Varnostni preklic stare datoteke je več kot novo ime ali ovoj. Nova skrivnost
in novo ovijanje istega korena ne preprečita prihodnjega dostopa imetniku
že odklenjenega starega korena. Pri sumu kraje so potrebni pregled naprav,
novi prizadeti korenski/prejemni in vsebinski ključi ter preverjeno shranjena
nova datoteka pred zaključkom prehoda. Stara datoteka lahko še vedno odklene
stare šifrirane kopije, ki jih je nekdo že shranil; teh ni mogoče preklicati.

E-poštno obvestilo nastane ob zahtevani obnovi/prijavni ponastavitvi, uspešnem
zaključku in vpisu nove naprave. Ne vsebuje skrivnosti. Poštna vrsta ima
ponovitve, omejevanje in vidno stanje dostave. Aplikacija ne more zaznati
lokalnega odklepanja ukradene kopije brez stika s strežnikom; obvestila niso
neobhodna kriptografska zaščita pred upravljavcem poštne vrste.

## 6 Čarovnik ob posodobitvi obstoječe aplikacije

Čarovnik je nad usmerjevalnikom in vsemi koordinatorji, ki odpirajo bazo ali
sprožajo sinhronizacijo. Vnos neposredne povezave, push, timer in povrnitev
nastavitev ne smejo obiti zapore. Identiteta in generacija postopka se
preverita po vsakem čakanju; odgovor stare prijave ne nadaljuje drugega računa.

| Korak | Kaj vidi uporabnik | Kaj se trajno preveri |
| --- | --- | --- |
| U1 Pregled | »Dodajanje obnovitvenega ključa« in kratko pojasnilo | Različice formatov, prosti prostor, vsi lokalni profili, osnutki, ključi, stanje prejšnjega poskusa |
| U2 Shranitev | »Shranite obnovitveno datoteko« ali uporabnikovo deljenje | Naključna identiteta, varen zapis ključa, save/cancel ločena; nič ne gre v Jivie SMTP |
| U3 Preverjanje | »Izberite shranjeno datoteko« | Prebrana zunanja kopija odklene preskusno ovojnico za pravi vault/račun |
| U4 Zaščita naprave | Napredek in možnost poznejšega nadaljevanja | Zaustavitev piscev, dosledni posnetek, šifriran cilj, celovitost in primerjava vseh podatkov |
| U5 Povezani računi | Potrditev e-pošte/priprava ključa ali uvoz že obstoječega | Brez novega korena, če račun že ima kriptografsko identiteto; brez prenosa lokalne vsebine brez soglasja |
| U6 Deljeni prostori | Seznam pripravljenih prostorov in razlogov čakanja | Ključni prejemniki, sveže pravice, celotni obsegi/finančne komponente, znane stare naprave |
| U7 Prehod | »Vzpostavljanje zaščite deljenja« | Verzioniran strežniški posnetek, čakalne operacije, šifrirani nadomestni objekti, preverjena obnova, atomski preklop |
| U8 Zaključek | Zaščita naprave in stanje E2EE po prostorih | Preizkus ponovnega odprtja, trajni potrdili; odstranjevanje starih kopij po ločenih merilih |

Ob zaprtju aplikacije se čarovnik nadaljuje pri zadnjem potrjenem koraku.
Pri U2/U5 je vedno prikazan obseg datoteke iz §5.2; več računov ne pomeni
tihega skupnega izvoza njihovih skrivnosti. Datoteka namestitve je označena
kot dostop do vse shranjene vsebine te namestitve, vključno z drugimi profili.
Prekinitev omrežja ne blokira že zaščitenega lokalnega branja in dela.
Prekinitev pred lokalnim preklopom ohrani izvirnik; po preklopu se odpre samo
preverjeni šifrirani cilj. Nezmožnost priprave skupnega prostora ne sme skriti
lokalnih osnutkov ali jih pretvoriti v novo kopijo pod drugim računom.

Če uporabnik obnovitvene datoteke še ne shrani, E2EE korena ne aktiviramo
nepovratno. Postopek lahko odloži; aplikacija ohrani dosedanje lokalne podatke
in jasno kaže nedokončano zaščito. Varnostno migracijo časovno ločimo od novih
finančnih ali podatkovnih pretvorb, da je mogoče ugotoviti vzrok napake.

## 7 Čarovnik prve prijave in povabil

Prijava obstoječega uporabnika, registracija, preverjanje e-pošte, odklep
podatkov in sprejem povabila so ločeni koraki istega nadaljevalnega toka.

1. Preveri HTTPS, `serverId`, zmožnosti in podprte kriptografske pogodbe.
2. Prijava/registracija ustvari samo omejeno overjeno sejo; običajni `syncNow`
   še ne steče. Seja brez ključev ni dokaz odklepa.
3. Preveri e-pošto za pisanje povezanega računa. Ponovna prijava, ponastavitev,
   pošiljanje kode, izvoz lastnega ohranjenega dela in odjava ostanejo možni.
4. Nov kriptografski račun: ustvarjanje ključev, shranitev datoteke, ponovni
   uvoz/preizkus in atomski vpis identitete. Obstoječi kriptografski račun:
   potrjena druga naprava ali uvoz datoteke. Odsotnost lokalnega ključa ni
   dovoljenje za prepis strežniške identitete.
5. Šele nato aktivacija vsebinske sinhronizacije. Vključitev osebne
   sinhronizacije in objava lokalnih prostorov ostaneta izrecni uporabniški
   odločitvi. Prijava sama ne prenese lokalnih podatkov.
6. Čakajoče povabilo se ohrani skozi celoten tok; po izrecnem Join sledi
   kriptografska odobritev dostopa. Članstvo brez dostavljenega veljavnega
   ključa kaže »Čaka potrditev deljenja«, ne praznega projekta.

Uporabnik je potrdil ohranitev povsem lokalne uporabe brez računa in e-pošte;
potrditev velja za vsebinske vnose povezanega računa. Znani preklic ali nepreverjen status
povezanega računa ne smeta postati obhod prek offline zapisa; varno ohranimo
obstoječe osnutke in omejimo pošiljanje do izpolnitve pogojev.

## 8 Šifriranje lokalne baze brez izgube podatkov

### 8.1 Pogon in platforme

Ohranimo Drift in njegove SQL transakcije. Glede na zaklenjena `drift:2.35.1`
in `sqlite3:3.7.0` najprej preverimo uradno pot `sqlite3mc` prek native build
hooks. SQLCipher z ustrezno native vezavo je alternativa, če prvi kandidat
ne izpolni meril. Končno izberemo en preverjen format; SQLCipher in
SQLite3MultipleCiphers nista zgolj zamenljivi imeni za isto knjižnico.

Izbrani cipher, združljivostno različico in varnostne parametre določimo
izrecno ter jih zapišemo v verzionirano pogodbo. Ne zanašamo se na privzete
nastavitve knjižnice. Cilj ustvarimo neposredno šifriran; primer s čistopisno
začasno bazo in poznejšim `rekey` ni sprejemljiva privzeta migracija.

Preizkus mora dokazati overjanje strani, zaščito WAL/journal/temp datotek,
pravilno branje JSON/BLOB, več povezav/isolatov, native knjižnico v release
paketu, Android16KiB, iOS podpis/izvoz in desktop gradnje. Pogon se preveri
tudi v release načinu, ne samo z `assert`. Napačen ključ ali navadni SQLite
namesto šifrirnega pogona pomenita varno ustavitev. Ne uporabljamo privzetega
gesla in ne zapisujemo `PRAGMA` s ključem v dnevnike.

### 8.2 Lokalni transakcijski dnevnik migracije

Zunaj podatkovne baze je potreben minimalen trajni dnevnik brez vsebine ali
neovitih ključev. Hrani naključni migration ID, različico, stanje, lokacije
upravljanih datotek, generacijo in preverljive vezi na varen ključ. Njegov
zapis in menjave datotek potrebujejo preverjeno platformno obstojnost; sam
`rename` ni dokaz, da je celotna večdatotečna transakcija zaključena. Preizkus
vključuje zaporedje flush/fsync datotek in imenikov, kjer ga platforma
podpira, ter okrevanje po izpadu med vsakim takim korakom.

| Stanje | Obvezni ukrep in ravnanje po ponovnem zagonu |
| --- | --- |
| `discovered` | Popiši dejanske baze, vse sheme/tabele, WAL, Hive in občutljive preference. Ne odpiraj nepoznanega novejšega formata za pisanje. |
| `key_prepared` | Zapiši nov ovit lokalni ključ in ga preberi nazaj. Ob napaki varen stop, brez ustvarjanja prazne baze. |
| `recovery_verified` | Shranjena datoteka je lokalno preizkušena. Uporabniška odjava ne odstrani tega ključa. |
| `writers_paused` | Ustavi UI pisce, vse sinhronizacije, schedulerje in druge isolate/procese. Počakaj na odprte transakcije. |
| `snapshot_ready` | Ustvari dosledni posnetek s podprtim SQLite backup/export postopkom; upoštevaj WAL. Navadna kopija žive `.sqlite` datoteke ni dovolj. |
| `encrypted_candidate` | Izdelaj ločen šifriran cilj; ne šifriraj edinega izvirnika na mestu. Dnevniki in začasne kopije imajo določeno zaščito. |
| `verified` | Ponovno odpri cilj s trajno shranjenim ključem in preveri spodnje invariante ter izvirni posnetek. |
| `switched` | Trajno zabeleži eno avtoritativno generacijo in preklopi pot; pri dvoumnem stanju odloči po dnevniku/celovitosti, nikoli po praznosti ali času datoteke. |
| `reopened` | Ponovni zagon dejanske aplikacije preveri vse profile in ozadje. Po novih zapisih ne sme več odpreti starega izvirnika. |
| `cleanup_pending` | Izvirnik ostane le v preverjenem zaščitenem rollback arhivu; občutljive stare Hive/prefs/temp kopije se odstranijo po dokazu ohranitve. |
| `complete` | Preveri, da ni upravljane berljive kopije. Kjer ostane fizična/OS kopija, se zaščita in njena meja izrecno dokumentirata. |

Primerjamo vsebino vseh tabel po stabilnem ključu in surovih vrednostih,
ne samo števila vrstic ali uspeha `fromJson/toJson`. Posebej zajamemo
`sqlite_sequence`, indekse, sprožilce, `user_version`, tuje ključe, vse
particije, nepoznane JSON ključe, izvirne zahteve in wire verzije, zaporedje
vrst, konfliktne odgovore, revizijske meje, osebne preslikave, BLOB in cache.
Fizični bajti stare in šifrirane SQLite datoteke se seveda ne ujemajo;
primerjava je nad dešifriranim logičnim posnetkom in izvirnimi BLOB/JSON bajti.

Samo izvoz/uvoz `.vsakdan` bi izgubil izključene profile in stanje namestitve;
zato ni dovoljeno orodje za to migracijo. Poškodovana baza ali Hive najprej
potrebujeta ohranjen izvirnik in diagnozo. Čiščenje flash pomnilnika ne more
obljubiti forenzičnega izbrisa vseh starih fizičnih strani ali OS snapshotov.

### 8.3 Izguba ključa in sistemske kopije

Politika Android backup/device transfer in iOS/iCloud mora preprečiti
obnovitev šifrirane baze brez uporabne poti do ključev ter nenameren prenos
sej na drugo napravo. Napravni ključ se ne enači s trajno računsko identiteto.
Ponovna namestitev z ostankom Keychaina, obnovljena baza brez Keystora in
biometrična sprememba imajo vsak svoj preizkus. `secure_storage` napaka ne
sme sprožiti čiščenja ali rezervnega ključa v preferences.

Izvoz dokumenta, navaden JSON ali uporabnikova obnovitvena datoteka so
izrecni izvozi zunaj upravljane shrambe; uporabnik vidi njihovo zaščito.
Navadnih izvozov ne uvajamo kot samodejnega nadomestila ob napaki šifriranja.

## 9 Deljenje, preverjanje identitet in naprave

**Sprememba dogovora, 19. oktober:** uporabnik je odobril
[poenostavljeno deljenje](E2EE_SHARING_SIMPLIFICATION.md). Običajni prvi stik
samodejno zaupa imeniku izbranega gostovanja, po preverjanju podpisane verige
varno pripne koren in opozori ob nepojasnjeni spremembi. Obvezna ročna
primerjava kartic spodaj je prvotni strožji predlog, ne več privzeti tok.
Neodvisna primerjava ostane napredna možnost. Ostale zahteve po podpisanem
članstvu, dovoljenih ključih, obnovljivosti in ločitvi obsegov ostanejo.

Strežniški ACL ostane obvezen, vendar samo sprememba vrstice v
`familyhub_members` ne sme sprožiti izdaje ključev. Odjemalec preveri podpisano
zgodovino pooblastil in ključ prejemnika. Javni ključ iz nepreverjenega odgovora
istega strežnika ni dokaz identitete: skrbnik bi ga lahko zamenjal s svojim.

Za prvo strogo preverjeno deljenje predlagamo QR ali primerjavo prstnega
odtisa po neodvisni poti. Odobritev shrani koren identitete in se ponavlja
samo ob njegovi spremembi. Običajne nove naprave iste identitete pooblasti
že zaupanja vredna naprava ali dokaz obnovitvene skrivnosti. Alternativa je
neodvisno preverljiva infrastruktura javnih ključev; njena izbira zahteva
poseben pregled. TOFU brez preverjanja prvega stika ima šibkejšo zaščito in
se ne označi kot dokaz varovanja pred aktivnim skrbnikom pri prvem deljenju.

### 9.1 Tok povabila in trajno stanje dostopa

1. Pošiljatelj izbere prostor/projekt in obstoječo vlogo. E-poštno povabilo
   nosi le časovno omejen pristopni token, brez ključa ali občutljivega naslova.
2. Prejemnik potrdi e-pošto, pripravi lastno identiteto in datoteko, nato
   izrecno sprejme povabilo. Registracija sama ne podeli članstva.
3. Pooblaščena naprava pošiljatelja ali drugega dovoljenega upravljavca ključev
   preveri identiteto prejemnika ter podpiše njegovo upravičenost.
4. Naprava izdela ovojnice samo dovoljenih vsebinskih ključev. Dostava je
   ponovljiva in vezana na aktualno access revision, epoch in invitation ID.
5. Prejemnik preveri podpis in odklene preskusno vsebino. Stanje preide iz
   `membership_pending_keys` v `crypto_ready`; izgubljeni odgovor ne ustvari
   drugega povabila ali drugega člana.

Če pooblaščena naprava ni dosegljiva, je predaja ključev trajno čakajoča.
Strežnik je ne »dokonča« z glavnim ključem. Pred izdajo mora biti jasno,
katere naprave smejo dokončati že podpisano predajo in kako je pošiljatelj
obveščen. Odstranitev člana med čakanjem razveljavi še nedostavljene ovojnice.

### 9.2 Hierarhija in preklic

Članstvo nadrejenega prostora še naprej pomeni dostop do dovoljenih
obstoječih in prihodnjih projektov. Ustvarjalec novega projekta prejme
preverjen trenutni seznam upravičenih kriptografskih identitet in pripravi
ovoje; ne ustvarimo univerzalnega ključa organizacije, ki bi ga dobil vsak
neposredni projektni član. Član z dostopom samo do projekta nikoli ne dobi
osebnih ključev drugega uporabnika ali finančnega ključa starša.

Preklic ustavi strežniški dostop, odstrani prihodnje dostave in začne novo
epoho samo za preostale upravičence. **Za prihodnje revizije ne uporabljamo
starega objektnega ključa, ki ga odstranjeni član že pozna.** Samo ponovno
ovijanje istega znanega podatkovnega ključa ne zagotovi odvzema prihodnjega
branja. Stara vsebina ostane zgodovinsko dostopna tistemu, ki jo je že dobil.

Prenos lastništva zahteva potrditev ključne sposobnosti novega lastnika,
podpisan prenos pooblastila in preverjeno obnovitev skupnih obsegov pred
odstranitvijo starega zadnjega upravljavca. Bralec ima ključ za branje,
ne pa pravice podpisovati veljavnih zapisnih operacij; vlogo preverita tako
strežnik kot prejemni odjemalec.

### 9.3 Spreminjanje e-pošte in ponastavitev

Menjava e-pošte, reset gesla ali ponovno uporabljeno uporabniško ime ne
ustvarijo nove kriptografske identitete pod starim imenom. Obnova z datoteko
dokaže isti koren. Brez datoteke ali zaupanja vredne naprave se lahko obnovi
prijava, vsebina pa ostane zaklenjena. Če uporabnik izrecno začne z novo
identiteto, drugi člani prejmejo opozorilo in ga ponovno preverijo; nova
identiteta ne odklene zgodovine avtomatično.

## 10 Nova pogodba sinhronizacije

E2EE dobi ločeno, verzionirano pogodbo in feature negotiation. Končne številke
API, sheme in `.vsakdan` določimo po zamrznitvi izvedbe; ne uporabljamo
obstoječih finance4/sync6 operacij z nespremenjenim imenom in drugačnim pomenom.

Predlagani sklopi API, katerih natančne sheme bodo ločen izvedbeni dokument:

| Sklop | Odgovornost |
| --- | --- |
| `crypto.account` | Atomski prvi vpis, javni koreni, šifrirani ključni paket, CAS njegove generacije |
| `crypto.devices` | Podpisano dodajanje/preklic naprav, dokaz iste identitete, varnostni dogodki |
| `crypto.grants` | Podpisana upravičenja, epohe, ovojnice ključev in potrditve prevzema |
| `crypto.sync` | Overjene šifrirane operacije, transakcijski batch, CAS, cursor, tombstone, replay |
| `crypto.blobs` | Nadaljevalni prenos šifriranih blokov in končni overjeni manifest |
| `crypto.migration` | Prepare/fence/inventory/stage/verify/commit/status/abort pred commitom |
| `crypto.legacyReceipts` | Razrešitev starega opId in trajna enolična vez na novo operacijo |

Odjemalec v eni lokalni transakciji shrani poslovno spremembo, nespremenljivo
šifrirano ovojnico in njen ID. Ponovna dostava po prekinitvi uporabi iste bajte.
Ovojnica veže server/account/scope/record, tip, opId, pričakovano revizijo,
epoho, avtorja, vsebinsko pogodbo in paketno povezavo. Podpisi in AEAD se
preverijo **pred** uporabo v projekciji, obvestilu, datoteki ali finančnem
seštevku. Veljaven podpis še ne pomeni pravilnega zneska ali veljavne vloge.

Strežnik ohrani svežo avtentikacijo, ACL, podpisna pooblastila, kvote, CAS,
zaporedje, idempotentnost ter atomski zapis celotnega batcha. Vsebinsko
validacijo izvedejo odjemalci ob nastanku in prejemu. Neveljaven zapis ali
nepoznan prihodnji format ostane v karanteni z dokazom; ne izgine iz cursorja
kot uspešno obdelan in ne povzroči delnega finančnega prikaza.

Transportni cursor prevzema, status kriptografskega/vsebinskega preverjanja
in checkpoint popolne projekcije so ločeni. Trajno shranjen zavrnjen objekt
ne ustavi prenosa drugih obsegov ali njegove poznejše poprave; prizadeta
projekcija ostane nepopolna. Protokol določi podpisano popravo ali zamenjavo
neveljavne revizije, da CAS nad njo ne povzroči trajnega zastoja.

Nova schema potrebuje dodajalne tabele za javne identitete/naprave,
šifrirane ovoje, podpisana upravičenja, generacije migracij in preslikave
potrdil ter šifrirane zapise/datoteke. Najprej jih dodamo ob starih tabelah;
starih ne prepisujemo na mestu. Nobena nova tabela ne hrani recovery
skrivnosti ali zasebnega vsebinskega ključa v obliki, ki jo lahko odklene server.

Podpisane revizije in lokalni največji znani checkpointi zaznajo že znano
povrnitev zgodovine. Povsem nova naprava brez svežega neodvisnega checkpointa
ne more sama dokazati, da ji zlonameren strežnik ni zamolčal zadnjega dela
veljavne zgodovine. Za močnejšo zaščito pred razcepom so potrebni primerjanje
naprav oziroma neodvisni witnessi; E2EE ni obljuba razpoložljivosti ali
popolnosti pred skrbnikom, ki podatke zadržuje.

Račun in obseg imata trajno pripeto najnižjo dovoljeno kriptografsko
generacijo v zaščiteni lokalni evidenci in obnovitvenem manifestu. Po prehodu
nikoli ne pošljeta čistopisa zaradi nižjih capabilities, zamenjanega URL,
stare kopije ali server rollbacka. Ob neskladju se promet ustavi in ohrani
lokalno delo. Nova E2EE aplikacija ne sme brez izrecnega migracijskega stanja
obravnavati obnovljenega starega posnetka kot dovoljenje za legacy pisanje.

## 11 Varen prehod strežniških obsegov

### 11.1 Enota preklopa

Navaden samostojen prostor se preklopi kot celota. Če finance4, task-cost,
povezana plačila ali druge reference povezujejo več obsegov, je enota
**celotna povezana komponenta**, ne naključno prvi prostor iz UI. Načrt
komponente izhaja iz dejanskih referenc in inventarja, ne samo iz drevesa UI.

En uporabnik nima samodejno pravice brati vseh teh vsebin. Ne povečamo mu
pravic zaradi migracije. Vsak del šifrira upravičena naprava; preklop čaka,
če manjka katerikoli zahtevani del, ključ, podpis ali zgodovina. Lokalni
čarovnik enega uporabnika zato ne more obljubiti takojšnjega globalnega
E2EE vseh drugih uporabnikov.

Pred prvo javno migracijo pripravimo vse potrebne Android/iOS/desktop
odjemalce oziroma dokažemo, da jih zadevna komponenta ne potrebuje. Odjavljen
ali offline odjemalec lahko ima ohranjene spremembe; njegovo odsotnost
obravnava most za stare operacije. Nepotrjena kriptografska identiteta
upravičenega člana pa ne sme biti tiho izločena iz deljenja.

### 11.2 Strežniška stanja

| Stanje | Dokaz pred naslednjim korakom |
| --- | --- |
| `legacy` | Obstoječi način je izrecno označen; nobene trditve E2EE |
| `preparing` | Preverjene identitete in ovojnice vseh potrebnih članov, seznam komponent, odjemalcev, podatkov in odprtih vrst |
| `fenced` | Atomska prepoved legacy vsebinskih zapisov in sprememb članstva/lastništva, dokumentnih lock zapisov ter relevantnih worker učinkov za komponento; zahteve v letu so odtekle |
| `snapshot_verified` | Končni dosledni inventar po fence in preverjena kopija; pripeti cursors, revisions, access generations in worker checkpoints |
| `ciphertext_staged` | Upravičeni odjemalci pripravijo vse šifropise, datoteke, zgodovino in ključne ovoje; stage je ločen od žive vsebine |
| `verified` | Preneseni stage je lokalno odšifriran in primerjan z izvirnikom; v drugi čisti namestitvi preverjena obnova z izvoženo datoteko |
| `committed` | En atomski CAS preklopi celotno komponento ob nespremenjenih fence/revisions/membership podatkih; trajen rezultat za isti migration ID |
| `legacy_retention` | Aktivni promet je samo E2EE, stare kopije so popisane in omejene z rokom ter razlogom hrambe |
| `retired` | Znane stare berljive aktivne kopije/dnevniki/staging so odstranjeni oziroma zaščiteni po dogovorjeni politiki; ohranjeni šifrirani dokazi obnove |

Fence preveri **vsak** relevantni API in cron, tudi stari bralni endpoint po
commitu. Po preklopu stari odjemalec prejme `upgrade_required`, nikoli
dešifrirane združljivostne kopije. Tako se ne sme obiti zaščite prek audit,
izvoza, moderatorskega predogleda, attachment download ali starega sync API.

Inventar piscev vključuje tudi brisanje: reminders cron danes izvaja še
moderation purge ter idea/attachment cleanup, `runDue` pa inbox retention.
Enaka zapora velja za samostojne retention/account-deletion cleanup poti.
Ustavitev samo pošiljanja obvestil ne zagotovi nespremenjenega posnetka.

Trajanje freeze naj bo kratko: predpriprava se opravi pred fence, po njem pa
se zajame in preveri končna razlika. Če so limiti gostovanja ali čas preseženi,
se pred commitom varno odstopi, obnovi dosedanji način in ohrani stage za
diagnostiko brez skrivnosti. Po commitu je izid mogoče poizvedeti z istim ID;
prekinjen HTTP odgovor ne pomeni neuspešnega commita.

### 11.3 Popolnost inventarja

Migracija zajame sedanje kanonične zapise, zgodovinske revizije, audit
before/after, uspešne in konfliktne `familyhub_operations.response`, potrdila
dokumentov, tombstone, naslove prostorov, preference z vsebino, finančne
projekcije, reminder/inbox vsebino, slike, priloge, upload chunks, moderation
snapshot-e, staging in zasebni DATA. Česa ni mogoče prenesti v novo aktivno
projekcijo, ostane v dovoljenem šifriranem zgodovinskem arhivu; nič se ne
izgubi zato, ker trenutni model tega ne uporablja.

Migracijski podpis dokazuje, kaj je pooblaščena naprava zajela in šifrirala.
Ne ponaredi zgodovinskega avtorstva: stare nepodpisane zapise označimo kot
uvoženo zgodovino, ne kot izvirno podpisane E2EE operacije.

Šifriran aktivni sistem ne izbriše gostiteljevih starih zasebnih kopij za
nazaj. Začasne predmigracijske strežniške kopije zato sodijo v izrecen
časovno omejen načrt hrambe; arhiv šifriran z administratorjevim ključem je
še vedno berljiv administratorju. Končna trditev razlikuje zaščito novih
in preseljenih aktivnih podatkov od že prej razkritih podatkov.

### 11.4 Povrnitev

Pred commitom lahko opustimo stage in ponovno odpremo ohranjeni legacy vir,
če vsa preverjanja generacij potrdijo, da je še avtoritativen. Po commitu ali
novih E2EE zapisih ni dovolj vrniti starih PHP datotek ali prepisati baze s
staro kopijo. Potrebna je popravljena E2EE koda oziroma obnova najnovejšega
šifriranega stanja z vsemi ključi in operacijami. Poti nazaj v čistopis ne
izvajamo samodejno zaradi priročnosti.

## 12 Stare offline operacije in izgubljeni odgovori

Največje tveganje za finančno podvajanje je operacija, ki je bila na
strežniku že sprejeta, telefon pa ni dobil odgovora. Pretvorba njenega telesa
v šifropis pod istim `opId` spremeni hash in pokvari sedanje varovalo.
Brisanje vrste ali samodejna nova operacija bi lahko podvojila knjižbo.

Pred fence izpraznimo dosegljive vrste, vendar nikoli ne predpostavimo, da
so s tem izpraznjene vse offline naprave. Trajni most uporablja:

| Izid poizvedbe za stari ID | Ravnanje |
| --- | --- |
| Dokazano že sprejet | Pridobi isti semantični rezultat/revizijo, zaščiteno za upravičenca; lokalno potrdi brez ponovnega učinka |
| Trajno zavrnjen ali konflikt | Ohrani izvirni rezultat in običajni postopek razrešitve konflikta; migracija ne ponovi zavrnjenega namena pod novim ID |
| Dokazano nesprejet v popolni, zamrznjeni evidenci | Po svežem preverjanju pravic/revizije ustvari nov E2EE ID, trajno enolično povezan z izvornim legacy ID |
| Neznan ali protisloven | Ohrani izvirnik v šifrirani karanteni, pokaži razrešitev; ne ugibaj in ne knjiži ponovno |

Odsotnost ID v prirezani ali nepopolni evidenci pomeni neznan izid. Potrdilo
se veže na isto nespremenljivo izvirno zahtevo oziroma njen zaščiten digest,
ne samo na ID. Dokaz semantičnega rezultata ne zahteva ponovnega pošiljanja
starega čistopisa; novi endpoint ne postane vsebinski oracle ali obhod ACL.

Preslikava legacy→E2EE je strežniško enolična in transakcijska, vezana na
identiteto, obseg in vrsto operacije. Prvotno telo, vrstni red, wire verzija
in lokalne povezave ostanejo ohranjeni do preverjenega zaključka. Po
preklopu ne pošiljamo starega čistopisnega telesa niti samo za »preverjanje«.
Potrdila ne smejo ohranjati berljivih kopij občutljive vsebine.

Compound opravilo–strošek, prenosi in povezane finančne spremembe se
strežniško sprejmejo kot celota. Odjemalec preveri overjeno potrdilo commita
in vse dele, ki sestavljajo njegov dovoljeni prikaz; manjkajoč potreben del
pomeni nepopolnost. Ne zahteva ključev zasebne projekcije drugega prejemnika.
Povezana osebna plačila imajo izrecno določeno poznejšo idempotentno
projekcijo iz §13.3. Član z odvzetim dostopom ohrani lokalno neusklajeno delo za dovoljen
izvoz/reševanje; delo se ne preusmeri na drug račun ali prostor. Konflikt je
vidno stanje, ne izguba podatkov in ne tiho pravilo »zadnji zapis zmaga«.

## 13 Finance in povezani projekti

### 13.1 Račun starša in projektni pregled

Ohranimo finance4 pravilo: projektni strošek/priliv je en kanoničen zapis
v projektu, z referenco na račun starša. Starševski pregled sešteva dovoljene
prispevke; ne nastane druga knjižba ali drugi projektni saldo.

Projektni član dobi **poseben podpisan in projektno šifriran imenik dovoljenih
računov**: ID, dovoljeno ime, valuta in arhiviranost. Ne dobi opening balance,
celotnega account objekta ali parent finance ključa. Posodobitev imenika je
del preverljive večobsežne operacije; odstranjen ali zastarel imenik ne sme
omogočiti nove veljavne knjižbe na nedovoljen račun.

Contributor manifest in njegove generacije ohranijo sedanjo semantiko
`organizationFinanceScopeIds/Sequences/Complete`, tudi ko izgine zadnja
povezava. Strežnik lahko vidi minimalne strukturne reference, podpisan manifest
pa je pripet na dostop in revizije. Manjkajoč projekt, ključ, epoch, veljaven
zapis ali sequence pomeni nepopoln pregled brez lažno pravilnega salda.
Skritemu projektnemu članu ne razkrijemo ID drugih prispevajočih projektov.

### 13.2 Poslovna pravila in atomske spremembe

Vsebinska pravila za zneske, valute, datume, seštevke in povezana povračila
prestavimo v preizkušljivo odjemalsko domensko plast. Strežnik še vedno
atomsko uveljavi vloge, structural reference constraints, CAS, revizije,
edinstvene reference in idempotentnost. Vsebinski prejemnik preveri vse
invariante pred vključitvijo v saldo. To je drugačna meja zaupanja kot
sedanji PHP validator; ne trdimo, da strežnik preveri skrite zneske.

Opravilo in njegov vezani strošek sta podpisan transakcijski batch. Sprememba
roka ali izbris opravila vključita potrebno spremembo `plannedAt/taskId`;
server je ne izpelje več iz skrite vsebine. Revizije obeh delov se preverijo
pred atomskim sprejemom. Nova aplikacija ne sme omogočiti stare poti, ki
potrdi opravilo, finančni učinek pa izgubi.

Poseben primer stare politike1/2: urednik opravila danes lahko nima pravice
pisanja financ, trusted PHP pa vseeno uskladi vezani strošek. Pri E2EE mu ne
smemo dati finančnega ključa samo zato, da bi posnemal PHP. Pred prehodom
izdelamo matriko teh pravic in pregledamo omejeno podpisano namero za
izpeljavo, sopodpis pooblaščenega finančnega odjemalca ali izrecno odloženo
projekcijo z vidno nepopolnostjo. Izbrana pogodba mora ohraniti uporabnikovo
pravico urejanja opravila in preprečiti tih napačen saldo; dokler to ni
dokazano, prizadeta komponenta ne preklopi. Navaden zahtevek »pošlji oba
šifrata« ni rešitev tega primera.

Mesečna pravila se v trenutnem odjemalcu že materializirajo za dvanajst
mesecev. Ohranimo ta potek in strežniško atomsko enoličnost reference
pravilo/mesec z dogovorjenim minimalnim metapodatkom ali pregledanim slepim
identifikatorjem. Dve napravi ne smeta ustvariti dveh veljavnih knjižb.
Čezobsežna mesečna pravila, ki niso izvedena v obstoječi finance4 fazi,
ne postanejo nova zahteva te migracije.

### 13.3 Povezana osebna plačila

Odobritelj povračila nima ključa zasebnih financ plačnika in ga ne sme dobiti.
Odobrena skupna finančna dejstva se podpišejo in šifrirano dostavijo
upravičenemu plačniku; njegov odjemalec iz njih ponovljivo sestavi zasebne
cash/projection zapise. ID izvornega dogodka ostane trajen, derivacija pa
idempotentna. Odobritelj ne dobi zasebnih target/account ID prejemnika.

Če je prejemnik offline, skupni dogodek ostane veljaven, njegova zasebna
projekcija pa označena kot čakajoča do uskladitve. Ne pokažemo »popolno«,
če manjka revizija. Sočasna povračila uporabljajo CAS nad izvorno dogodkovno
revizijo in odjemalsko preverjanje skupne vsote; presežek ali neveljaven
podpisan dogodek gre v karanteno. Pred izdajo je obvezen pregled, da
spremenjena meja zaupanja pri financah ne prikrije nepravilnosti.

Enaka obveznost velja pri vsaki spremembi izvornega finančnega zapisa,
tudi samo naslova ali druge vsebine brez novega povračila: današnji PHP
osveži revizijo dogodka in zasebne projekcije. Novi tok dostavi overjeno
novo izvorno revizijo in lokalno ponovi dovoljeno projekcijo brez podvajanja
denarnega učinka. Offline plačnik mora po vrnitvi dobiti isto potrjeno
revizijo vira in plačila; odsotnost nove refund vrstice ni razlog za preskok.

## 14 Preglednice, slike in priponke

Preglednica ohrani izključni 90-sekundni napravni zaklep in CAS. Lease je
dovoljenje pisanja, ne šifrirni ključ. Server vidi velikost in revizijo
šifriranega dokumenta; celice, formule, naslov in vsebinske omejitve preveri
odjemalec. Osnutek se hrani lokalno šifriran in se ne izgubi ob poteku locka.

Priloge uporabljajo naključne opaque ID-je. Ime, MIME, plaintext hash in
dimenzije so v šifriranem manifestu; strežnik preverja šifrirano velikost,
kvote, hash šifropisa in dostop. Globalni plaintext hash slike se ne sme
ohraniti kot javno ime datoteke, ker razkriva enakost znanih slik.

Izberemo pregledan pretočni AEAD format. Preverjanje mora zaznati
spremenjen/izpuščen/zamenjan/podvojen blok, napačen vrstni red, premeščanje
med datotekami in odrezan konec. Nadaljevanje prenosa uporablja isti varno
shranjeni šifrirani stage; ne ponavlja nonce za drugačno vsebino.

Sedanje serversko odpiranje PDF/Office ZIP/slik ne deluje nad šifropisom.
Preverjanje formata, velikostnih omejitev po odklepu, normalizacijo slik in
odstranjevanje metapodatkov izvedemo pred šifriranjem in po prenosu na
prejemnikovi napravi. E2EE ne zagotavlja, da je priponka zaupanja vredna;
prejemnik ne izvaja aktivne vsebine in je ne odpira samodejno.

## 15 Opomniki, obvestila, prijave vsebine in izbris

| Funkcija | Predlagano vedenje po E2EE |
| --- | --- |
| Lokalni opomniki | Naprava iz odklenjenih podatkov izračuna čas in uporabi obstoječi sistemski scheduler; občutljivih naslovov ne podvaja v navadne preference |
| Oddaljeni opomniki | Odjemalec odda podpisano minimalno namero: čas, opaque target/version, dovoljeni prejemniki; server preveri aktualne pravice in dostavi generičen ping |
| Sprememba roka/zaključek/arhiv | Sprememba vsebine in posodobitev/preklic namere sta v istem atomskem ukazu; brez starega opozorila iz zamujenega opravila |
| Push in e-pošta | Generično besedilo brez naslova, imen prostorov ali finančnih zneskov; aplikacija podrobnosti sestavi lokalno po preverjanju identitete |
| Center obvestil | Šifrirano oziroma iz preverjenih lokalnih dogodkov izpeljano besedilo; isti cilji, dedupe, read state in sveže pravice |
| Prijava vsebine | Uporabnik vidi predogled in izrecno razkrije izbran dokaz moderatorju; ne celotnega ključa prostora |
| Moderatorski poseg | Omejitev računa/dostopa ali odstranitev opaque objekta; server ne more prepisovati posamezne besede znotraj šifrata |
| Izbris računa/prostora | Predogled odjemalca in strukturni server pregled, prenos potrebnih pooblastil ter trajni tombstone; brez izgube skupnih finančnih dejstev |

Urednik opravila ne vidi zasebnih opomnikov vseh drugih članov, današnji
server pa jih ob spremembi cilja uskladi vse. Zato nova pogodba potrebuje
slepi preklic/zastaranje vseh namer po target/version in podpisane osvežitve
od upravičenih naprav. Preverimo, kateri minimalni časovni metapodatki
omogočajo pravočasno novo dostavo tudi med offline stanjem lastnika opomnika.
Če je potrebna odložena izpeljava, mora biti njena omejitev izrecno
dogovorjena in prikazana; tujega zasebnega urnika ali ključa ne razkrijemo
uredniku. Ta primer je izhodno merilo P5 pred preklopom, ne skrita izguba
sedanjega samodejnega prestavljanja opomnikov.

Prikaz podrobnosti push na zaklenjenem iOS/Android zaslonu je platformna
odločitev. Za prvi rollout zagotavljamo generično obvestilo in točno odpiranje
zapisa; vsebinskega predogleda ne obljubimo brez varnega odklepa v ozadju.
Čas namere je strežniški metapodatek. Popolno skrivanje časa bi pomenilo
drugačen model lokalnega razporejanja in ni tiha sprememba tega načrta.

Odjava ali preklic počistita pripadajoča prikazana obvestila in preprečita
prikaz starega računa iz zakasnelega push. Odpiranje po odjavi čaka odklep
prave identitete. Sinhronizacija ni odvisna od tega, ali je OS dovolil push.

Dokaz prijave vsebine se veže na podpisan zapis/revizijo, vendar je njegova
razkrita kopija namenoma dostopna moderatorju. Varnostno in uporabniško
besedilo to jasno pove; poročanje ni skrita administratorska dešifrirna pot.

Sedanji izbris računa redigira stare odgovore in skupne payload-e na serverju.
Pri E2EE to ni več mogoče brez odjemalčeve priprave. Določimo minimalne
strukturne reference za varen tombstone in politiko zgodovinskih osebnih
oznak v skupnih zapisih. Odstranitev računa prek administracije brez njegovih
ključev mora ostati možna, ne sme pa obljubiti besedilne redakcije vseh tujih
kopij. Podatkovne in pravne posledice hrambe se pregledajo pred izdajo.

## 16 Kopije in strežniška namestitev

Obstoječa `.vsakdan` kopija je šifriran podatkovni izvoz z lastnim geslom.
Nova različica ohrani branje formatov1–8, ne tiho spremeni njihovega pomena.
Dodamo ekspliciten manifest ključnih odvisnosti: kopija mora povedati, ali
je samostojno obnovljiva ali zahteva določeno obnovitveno datoteko. Privzeti
uporabniški izvoz naj bo po preverjeni zasnovi obnovljiv brez starega serverja;
ne vsebuje sej, poštnih/FCM skrivnosti ali novih pravic do tujih prostorov.

Izvorna kopija in obnovljeno skupno delo ostaneta v šifrirani karanteni do
preverbe iste identitete in svežih pravic. Ohranimo izvirne ID-je, wire
verzije, finančne preslikave in izrecno nadaljevanje. Nova recovery datoteka
ni nadomestilo za ta podatkovni arhiv.

Za gostovanje pripravimo **nova verzionirana orodja**; stari pomagači
`upgrade-0.15.0` so vezani na prehod18→19 in se ne uporabljajo na novi shemi.
Zaporedje pred vsako poznejšo odobreno namestitvijo:

1. Svež bralni zajem identitete, verzije, dejanske sheme, paketov,
   konfiguracije, DATA, SMTP/FCM, ključev in crona.
2. Sveža popolna zasebna kopija vseh tabel, datotek in potrebne konfiguracije.
   Kopiranje konfiguracijskih ključev ne pomeni kopiranja E2EE zasebnih
   uporabniških ključev — teh server ne sme imeti.
3. Dejanska obnova točne kopije v izolirani bazi brez omrežja, bindov in
   aktivnih workerjev; primerjava vseh CREATE/vrstic/BLOB/datotek, identitet
   in dovoljenj. ZIP CRC sam ni dokaz obnove.
4. Dodajalna namestitev sheme in koda, preverjen maintenance/fence in
   povrnitev pred commitom. PHP/cPanel ostane podprt brez stalnega procesa
   ali zahteve po novem gostovanju, če dejanske zmogljivosti zadoščajo.
5. Test1 s sintetičnimi računi, nato ločeno odobrena produkcija. Po prehodu
   obnovi točen prejšnji cron oziroma njegov izrecno pregledani novi sklop;
   ne pošlji testnih sporočil resničnim uporabnikom brez naročila.
6. Ločen preizkus popolne obnovitve šifriranega strežnika in nove naprave
   z uporabnikovo testno datoteko. Server restore brez odklepa ni celotni dokaz.

Redne kopije potrebujejo interval, hrambo, ločeno lokacijo, zaščito in
opozorilo ob napaki. Stare predmigracijske kopije ostanejo popisane do
dogovorjenega poteka; njihova hramba zadržuje zaupnost stare vsebine pred
skrbnikom. Nova zaščita se v dokumentaciji in trgovinah opiše po dejanskem
stanju, brez trditve, da nikoli ni obstajala berljiva zgodovina.

## 17 Izvedbeni sklopi in izhodna merila

| Sklop | Predvidene odgovornosti in povezave | Izhodno merilo |
| --- | --- | --- |
| P0 Zamrznitev in protokol | Ponovno preveri zemljevid kode, threat model, formate, knjižnice in odvisnosti; neodvisni kriptografski pregled | Pregledan protokol, popoln inventar in podpisana odločitev o metapodatkih/identitetah |
| P1 Lokalni vault | Nov `LocalVaultBootstrap` pred `JivieApp` porabniki baze; `EncryptedDatabaseFactory`, `LocalEncryptionMigration`, `VaultKeyStore` | Celotna namestitev ohranjena, vsi crash checkpoints in release pogon preverjeni |
| P2 Datoteka in računski ključi | `RecoveryFileCodec`, `RecoveryFileIo`, `RecoveryShareAdapter`, `AccountCryptoRepository`; brez strežniškega pošiljanja skrivnosti | Shrani/ponovno uvozi/obnovi na drugi čisti napravi, napačne datoteke zavrnjene |
| P3 Overjena slepa sinhronizacija | `EncryptedOperationCodec`, `CryptoSyncRepository`, verzionirani server endpointi/tabele, signed receipts | Zapis/pull/replay/conflict/batch deluje brez berljive vsebine na serverju |
| P4 Deljenje in naprave | `CryptoMembershipService`, per-scope/finance epohe, pregled naprav in identitet | Dve osebi/več naprav, dedovanje, projektni zunanji član, preklic in obnova brez razširitve pravic |
| P5 Poslovne funkcije | Finance4, task-cost, linked payments, tables, attachments, notifications, lifecycle/moderation | Vse sedanjo zahtevane funkcije imajo preverjeno E2EE pot in pošteno popolnost |
| P6 Migracijski most | `E2eeMigrationCoordinator`, per-component stage/fence/CAS, legacy receipts in encrypted archive | Preseljen star fixture z neznanim ACK in offline napravo brez izgube ali podvajanja |
| P7 Čarovnika | Nadgradnja in server login/invitation kot ista trajna storitev, SL/EN besedila | Happy path en razumljiv čarovnik; prekinitev nadaljuje isti postopek |
| P8 Izdajna vaja | Dejanski starejši podpisani odjemalec, dve fizični napravi, test1, cold restore, neodvisni pregled | Vsa merila spodnje matrike potrjena; šele nato predlog konkretne odobrene izdaje |

Imena novih razredov so predlog odgovornosti, ne že obstoječe datoteke.
Kriptografija, migracijsko stanje in pravice ne sodijo v obstoječe velike UI
datoteke. Ohranimo Riverpod, GoRouter, identitete in platformne adapterje.
Spremembe native knjižnic/locks so utemeljene samo za izbrani šifrirni pogon
in pregledane kot del izdaje; ne izvajamo splošne posodobitve SDK.

P1–P7 se lahko razvijajo v izoliranih sklopih, vendar **ne izdamo čarovnika,
ki preklopi realni prostor, preden P3–P6 podpirajo vse njegove uporabljene
funkcije**. Vmesna lokalna zaščita sme biti označena samo kot lokalna zaščita.
Začetni kriptografski pilot uporablja testne račune, ne resničnih uporabniških
financ. Natančne roke ocenimo po prototipu native pogona in protokola.

## 18 Merila preverjanja pred izdajo

Spodnja matrika je naročilo za prihodnje teste, **ne seznam že opravljenih
testov**. Obstoječe regresije in izvorne povezave so v zemljevidu kode.

| ID | Primer | Zahtevan rezultat |
| --- | --- | --- |
| L01 | Dejanska nadgradnja Android31 z istim applicationId/podpisom | Ni odstranitve aplikacije, brisanja podatkov ali nove prazne baze; čarovnik se pojavi enkrat |
| L02 | Prekinitev pred/po vsakem trajnem migracijskem zapisu in zamenjavi datoteke | Isti migration ID in avtoritativna generacija; ponovljiv zaključek |
| L03 | WAL-only zapis, več povezav/isolatov, background timer in odprt editor | Nobena izgubljena transakcija ali zapis med kopiranjem |
| L04 | Poln disk, permission error, nedosegljiv Keystore, napačen/manjkajoč ključ | Varen stop z ohranjenim virom; brez fallbacka na plaintext ali prazno bazo |
| L05 | Več računov, odjavljeni računi, Hive, neznana polja/tabele, BLOB/cache | Logični inventar vseh vrstic, bytes, zaporedij in povezav enak |
| L06 | Navaden SQLite, wrong key in release paket z napačno knjižnico | Dešifriranje zavrnjeno; release runtime zazna napačen pogon |
| L07 | Android backup/transfer, iOS restore, reinstall/Keychain ostanek | Definirana obnova ključa, brez prenosa stare seje ali tihe izgube lokalnih zapisov |
| L08 | I/O cleanup napaka, legacy Hive in notification preferences | Jasno nedokončano čiščenje; ni lažne trditve popolne lokalne zaščite |
| L09 | Obnova namestitve z več profili ter ločena obnova računa | Izrecen obseg vseh particij pri installation datoteki; računska ne odklene tujih profilov; ni prenosa seje/zaupanja napravi |
| R01 | Save/share preklic ali samo odprt delilni meni | Čarovnik ne trdi, da je datoteka varno shranjena |
| R02 | Ponovni uvoz datoteke iz zunanje lokacije | Pravilna identiteta in uspešno lokalno odklepanje |
| R03 | Napačna/stara/poškodovana/prevelika/prihodnja datoteka, zamenjan serverId | Varna zavrnitev; ne prepiše obstoječe identitete ali podatkov |
| R04 | Izgubljene vse naprave in geslo, ohranjen e-predal in prava datoteka | Reset prijave, odklep na novi napravi, enaki zapisi/ključni obseg; TOTP ni obiden |
| R05 | Reset brez datoteke ali zaupanja vredne naprave | Račun dosegljiv, vsebina zaklenjena; ne nov prazen E2EE koren |
| R06 | Dodan projekt/nov scope po izvozu datoteke | Prvotna veljavna datoteka obnovi posodobljeni ključni obroč |
| R07 | Zamenjava recovery skrivnosti in kraja stare kopije | Novi postopki uporabljajo novo datoteko; poštena omejitev glede starih že prenesenih kopij |
| R08 | Pregled omrežja, SMTP vrste, logov in crash poročil | Brez recovery skrivnosti, zasebnih ključev in čistopisne vsebine |
| R09 | A ustvari projekt, B hkrati novo epoho; obe napravi izgubljeni takoj po ACK | Prvotna računska datoteka obnovi oba dovoljena ključa; ni prepisanega delnega keyringa |
| A01 | Nepotrjena e-pošta, stari klient, neposreden API in offline vrsta | Pisanje povezanega računa zavrnjeno na serverju; povsem lokalna uporaba ostane |
| A02 | Invitation skozi login/reset/recovery/restart | Ohranjen pravi token/izvor, en izrecni Join, brez samodejnega članstva |
| A03 | Pozni odgovor po menjavi računa/strežnika ali odjavi | Ne zapisuje v napačno particijo in ne nadaljuje starega čarovnika |
| S01 | Deljenje med dvema računoma in Android/iOS napravama | Enaka dovoljena vsebina, noben parent key pri project-only članu |
| S02 | Zlonamerna zamenjava javnega ključa ali server dodajanje člana | Prejemnik ne dobi ključa brez veljavne kriptografske odobritve |
| S03 | Dodajanje podedovanega projekta, prenos lastnika, odstranitev člana/naprave | Pravilne ovojnice in nova epoha; prihodnje revizije niso berljive staremu članu |
| S04 | Offline pošiljatelj/prejemnik in preklic med predajo | Trajno čakajoče ali preklicano stanje, brez izgube povabila ali napačnega ključa |
| S05 | Preklic naprave, ki pozna svoje stare DEK/delegacije | Ne odklene novih epoh, ne podpiše veljavnega ponovnega vpisa; root kompromitacija zahteva ločen postopek |
| M01 | Prekinitev vsake strežniške faze in izgubljen commit ACK | Status po istem ID razreši izid, brez dvojnega preklopa |
| M02 | Nedostopen finančni contributor ali še ne pripravljen član | Komponenta ne preklopi delno; lokalni podatki ostanejo |
| M03 | Stara offline operacija: sprejeta/nesprejeta/neznana | Točen most ID in nič podvojenih opravil, knjižb ali povračil |
| M04 | Stari sync/audit/attachment/moderation API po commitu | Vsebina nedosegljiva v plaintextu; jasen upgrade_required |
| M05 | Čistopisni sentinel v live/history/audit/replay/chunks/DATA/temp | Nobena aktivna nezaščitena kopija zasebne vsebine; izjema samo izrecno razkrit moderacijski dokaz in dogovorjeni metapodatki; stare kopije po retention inventarju |
| M06 | Nižji capabilities, star server snapshot ali obnovljena legacy kopija | Noben preklop nazaj v čistopis; trajna minimalna crypto generacija |
| M07 | Conflict receipt, odrezana evidenca in napačen digest istega opId | Konflikt ohranjen, nepopolnost v karanteni; nič samodejnih novih finančnih učinkov |
| M08 | Neveljaven šifrat in poznejša podpisana poprava | Drugi prenosi napredujejo, prizadeti saldo ostane nepopoln do veljavne poprave |
| F01 | Finance4 skupni račun in projektni filter, več valut, zadnji odstranjeni prispevek | En kanoničen zapis, pravilen saldo samo pri dokazani popolnosti |
| F02 | Projektni član z imenom/valuto računa starša | Brez opening balance, parent ledgerja, zasebnih osebnih ključev ali sibling podatkov |
| F03 | Task-cost batch, izgubljen ACK, conflict enega dela | Atomski sprejem, pravilna dovoljena projekcija; lokalno ne izgine noben izvirni zahtevek |
| F04 | Linked payment, dve sočasni povračili, offline plačnik | Brez presežka v veljavni projekciji, brez dvojnega cash movement in brez zasebnih ID pri odobritelju |
| F05 | Dve napravi materializirata isti mesec | En veljaven rule/month učinek, ohranjena idempotentnost |
| F06 | Urednik opravila brez finance pravic v stari politiki1/2 | Brez razširitve pravic, izgubljenega opravila ali tiho zastarelega stroška |
| F07 | Popravek naslova izvornega stroška, plačnik offline | Po povezavi enake source/payment revizije in brez novega cash movement |
| D01 | Spreadsheet lock/refresh/expiry, offline draft in stale save | Osnutek ohranjen, stale zapis zavrnjen, formule enake |
| D02 | Zamenjani/poškodovani/odrezani šifrirani bloki in preklic dostopa | Priloga se ne odpre, delni prenos nadaljuje varno, tuj obseg zavrnjen |
| N01 | Rok/zaključek/arhiv sprememba in dve dostavni poti | Opomniki ostanejo pravočasni po dogovorjenem modelu, brez starih/podvojenih dostav |
| N02 | Zaklenjen telefon, odjava, star push, klik v pravi račun | Brez vsebinskega puščanja in brez odprtja napačnega računa |
| N03 | Drug urednik prestavi cilj s tujimi osebnimi opomniki | Brez razkritja zasebnih urnikov; pravilna razveljavitev/osvežitev po potrjeni pogodbi |
| X01 | Prijava vsebine in izbris računa z drugimi člani | Le izrecno razkrit dokaz; skupne strukture/finance in ključi drugih ostanejo |
| B01 | `.vsakdan`1–8, novi izvoz, offline obnova z datotekami | Original ohranjen, znana nepopolnost označena, pravice niso uvožene |
| B02 | Sveža strežniška kopija in prava izolirana obnova + čista nova naprava | Vse tabele/datoteke/identitete ter dešifrirana vsebina preverjeno obnovljivi |

Testi tečejo na podprtih SQLite/MariaDB/MySQL različicah in zaklenjenem
Flutter skladu. Fizični preizkus vključuje Android posodobitev brez
odstranitve in iPhone kot drugo napravo. Sintetični fixtures pokrijejo tudi
finance4 iz izvora, čeprav build31 te funkcije še nima. Uporabniških podatkov
ne kopiramo v Git, javne dnevnike ali neizolirane testne storitve.

## 19 Odločitve pred implementacijo in zaključna merila

Dogovorjeno je: E2EE, šifrirana lokalna shramba, lokalno ustvarjena datoteka,
uporabnikovo shranjevanje/deljenje, ohranitev deljenja in podatkov ter
čarovnik ob nadgradnji/prvi povezavi. Uporabnik je dodatno potrdil, da
povsem lokalni vnosi ostanejo brez računa in potrditve e-pošte.

Pred začetkom implementacije kriptografskega jedra morajo biti konkretno
razrešene naslednje izbire:

- pregledan protokol deljenja in knjižnice, lokalni cipher/parametri in
  podprte platforme; ni dovolj izbrati samo imena algoritma;
- način preverjanja identitete pri prvem deljenju ter razumljivo opozorilo
  ob spremembi korena; brez tega je zaščita pred aktivnim skrbnikom nepopolna;
- končna oblika datotek za celotno namestitev oziroma račun in trajen model obnove
  ključnega obroča, vključno s sočasnimi spremembami več naprav;
- natančen javni seznam metapodatkov za finance, odvisnosti, opomnike in
  lifecycle; posebej brez skritih zneskov v strežniških indeksih;
- preverjena enakovrednost task-cost in linked-payment poslovnih pravil
  ter pravila karantene, brez tihega slabljenja finančne pravilnosti;
- obdobje predmigracijskih kopij, izhodno merilo njihove upokojitve in
  pravila zgodovinske hrambe ob izbrisu računa;
- operativni pragi prostora/časa, velikost migracijskih komponent in
  resnična podpora vseh naprav aktualnih članov.

To so izvedbene naloge in konkretne omejitve, ne razlog za izgubo ali
samodejno izključitev obstoječih funkcij. Če katera ostane nerazrešena,
prizadeti obseg še ne preklopi in čarovnik to jasno pokaže.

Zaključek celotne nadgradnje pomeni: uspešno fizično posodobitev brez
ponastavitve, obnovljene podatke na čisti drugi napravi, ohranjeno deljenje
in finance, dokazano odsotnost strežniku odklepljivih zasebnih E2EE ključev
ter zasebne čistopisne vsebine na strežniku. Izjemi sta dogovorjeni računski
oziroma usmerjevalni metapodatki iz §3 in izrecno razkrit moderacijski dokaz
iz §15 z določeno hrambo; nobena izjema ne sme postati glavni ključ za vsebino.
Protokol potrebuje neodvisni pregled. Šele nato se lahko pripravi
konkretna nova izdajna odobritev. Prejšnje odobritve Android31/iOS31 ne
veljajo za to prihodnjo izdajo; interni Android kanal se ne uporablja.

## 20 Primarni tehnični viri

Viri so bili preverjeni 17. oktobra 2026. Določajo izhodišča za pregled in
prototip, ne dokazujejo pravilnosti prihodnje implementacije Jivie.

- [Drift encryption](https://drift.simonbinder.eu/platforms/encryption/) — native šifrirni pogon in omejitve pretvorbe obstoječe baze; dokumentacijskega primera ne kopiramo kot celotne migracije.
- [SQLite online backup API](https://www.sqlite.org/backup.html) — dosledno kopiranje SQLite, vključno z omejitvami sočasnosti.
- [SQLite3MultipleCiphers](https://utelle.github.io/SQLite3MultipleCiphers/docs/installation/install_overview/) in [SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/) — kandidatni native pogoni, izvoz in preverjanje; izbira ter parametri še zahtevajo prototip.
- [HPKE RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html), [MLS RFC 9420](https://www.rfc-editor.org/rfc/rfc9420.html) in [MLS Architecture RFC 9750](https://www.rfc-editor.org/rfc/rfc9750.html) — ovojnice ključev, skupinske epohe in ločitev preverjanja identitete od dostave.
- [OPAQUE RFC 9807](https://www.rfc-editor.org/rfc/rfc9807.html) — kandidat za ločeno prihodnjo prijavo brez razkritja gesla strežniku; ni bližnjica za sedanji auth.login.
- [libsodium secretstream](https://doc.libsodium.org/secret-key_cryptography/secretstream) — primer pregledanega pretočnega overjenega šifriranja, ne že izbrana odvisnost projekta.
- [OWASP Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html) in [Key Management](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html) — življenjski cikel, ločitev ključev, kopije in obnova.
- [OWASP Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html) — enkratne zahteve, časovna omejitev, preprečevanje zlorab in obvestila.
- [Proton recovery file](https://proton.me/support/recovery-file) — primer uporabniškega razlikovanja obnovitvene datoteke in ponastavitve prijave; njegovega formata ne posnemamo brez lastne pogodbe.

Izvor sta iskala dva podagenta **GPT-6.1 Sol/high**, ključne povezave in
migracijsko zasnovo je analiziral **GPT-6 Astra/high**; glavni agent je načrt
združil in preveril. Zapisani testi so merila prihodnje izvedbe. V tem
naročilu so bile preverjene dokumentacijske povezave in doslednost načrta,
ne izvedena migracija ali preskus kriptografije na resničnih podatkih.

### Potrjena hramba starih berljivih kopij — 17. oktober 2026

Uporabnik je potrdil rok **30 dni po dokazani uspešni dejanski obnovi nove
šifrirane kopije**. Šifriranje, prenos ali migracijski commit sami ne začnejo
roka. Ob skupni namestitvi se za vsako gostovanje/kopijo posebej zabeležijo
dokaz obnove, njen čas in kontrolna točka; ob neuspehu ali manjkajočem dokazu
ostane čiščenje zadržano. Odstranjevanje starih berljivih kopij in drugega
upravičenega predmigracijskega čistopisa se izvede šele v tem ločenem
namestitvenem koraku, z ohranjenimi podpisanimi/šifriranimi dokazi in brez posega
v skupne vire nemigriranih komponent. Trenutno ni izvedenega brisanja ali
trditve, da skrbnik ne more več brati starih baz/datotek/strežniških kopij.
