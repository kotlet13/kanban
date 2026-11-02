# Delni prenos in preostale zadržane zahteve — 2. november 2026

Uporabnik po 1.11.13 sporoči preostali `preflight / crypto_command_receipt_pending`
in hkrati uspešno prejeto spremembo nakupovalnega seznama drugega člana v Domu.
To potrjuje uporabnikovo opažanje delnega prejema, ne celotne sinhronizacije.
Naroči dopolnitev diagnostike in lokalne teste. Nato izrecno prepove novo oddajo
na Google Play. V tem sklopu ni gradnje, namestitve ali objave.

## Prikaz in kopija

Zaslon ločeno pokaže število uspešno lokalno shranjenih strani in prejetih
zapisov vsebine ter financ v tem poskusu. Števec raste šele po commit-u
obstoječe transakcije in samo med sinhronizacijo iste seje. Ponovitve lahko
isti zapis štejejo večkrat; to ni števec unikatnih zapisov, dokaz vseh domen
ali potrdilo poslanih sprememb. Nič pomeni, da prejem ni zabeležen. Običajni
nov poskus števec začne znova; dodatni prehod istega koordinatorskega opravila
sešteva potrjene prenose. Odjava/menjava seje podatke počisti.

Preostale aktivne blocked zahteve imajo točno skupno število ter omejen vzorec
20 vrstic (na glavnem zaslonu prve tri). Za vsako: vrsta operacije, dejanski
zadnji izid preverjanja potrdila, ali je bilo nadaljevanje preskočeno/ustavljeno/
poskušeno, aktualna varna oznaka vzroka in posebej prej shranjen razlog, ki je
lahko zastarel. Uporabniška razlaga je SL/EN; tehnične oznake ostanejo v kopiji.
Končni običajni prenos te informacije ponovno veže le na še aktivne zahteve
istega ID-ja in hasha. Ne prenese razloga že zaključenega sosednjega zapisa.

Opazovalnik spremlja že obstoječe klice; ne dodaja HTTP zahtev. Potrjen izid se
zabeleži šele po obstoječem preverjanju vezave/ACK in lokalnem zaključku. Denied
ni unknown, unknown ni applied, stari razlog ni novo strežniško potrdilo.
Manjkajoče opazovanje se izrecno izvozi kot notChecked/notAttempted. Trenutni
strežniški razlog zavrnitve bere dejanski `response.errorCode` protokola.

Izvoz version1 ima dodatna opcijska heldCommands/transfer polja. Podrobnosti
in kopiranje uporabljajo isti zamrznjeni posnetek prikazanega stanja. Imena,
ID-ji, hashi, podpisane vsebine, tokeni, naslovi in ključi niso izvoženi.
Operacije imajo statični seznam javnih imen iz NativeCryptoV2Service; vzroki
obstoječi strogi seznam. Neznana vrednost se nadomesti z other/unknown.
SQL bere največ 20 omejenih odgovorov (4 KiB) in COUNT v eni transakciji.
Napaka opcijske diagnostike ne vpliva na dostavo/zaključek. Varovala, čakalne
vrste, ključi, shema, avtoriteta in strežniška pogodba ostanejo isti.

## Lokalno preverjanje

22 različnih novih kontrol PASS, brez ponavljanja uspešnih testov:
- 9 jedro: svež guard, denied, ineligible, send+unknown, applied/rejected,
  okvara opazovalnika, nepravilna vezava potrdila, pravi response.errorCode.
- 8 integracija: prejeti nakupi in ohranjena ovira hkrati, denied/rejected po
  končnem prehodu, rollback strani brez lažnega uspeha, okvara diagnostičnega
  branja, zaključen sosed, spremenjen hash, 65 zahtev z vzorcem20 brez lookupov.
  Prvi tek je imel samo fixture compile napako (logout namesto signOut), nato
  vseh5 prvih kontrol PASS2. Dodatne3 kontrole vsaka PASS1.
- 5 UI/izvoz: omejevanje in filtriranje skrivnosti, SL/EN mobilni prikaz,
  nespremenjen prikaz/kopija med novo uskladitvijo, razumljiva razlaga ovire.

Pravi SQLite in podpisane zahteve v jedru; sintetični transport ter izrecne
projekcijske meje v integraciji. To ni fizični telefon/HTTP E2E PASS in ne
potrjuje dejanskega vzroka uporabnikovih zadržanih zahtev. Stare že uspešne
kontrole niso ponovljene. Obstoječi projekcijski testni adapter je prilagojen
novemu opcijskemu vstopu opazovalnika, izvorni uspešni scenariji ostanejo isti.

Končna analiza: 0 napak, 0 opozoril, 30 starih slogovnih info. Novi fixture
uvozi/oklepaji so popravljeni. Diff check PASS. Dokazi in hash manifest:
`build/qa/held-diagnostics-20261102/result.json` ter pripadajoči dnevniki.

## Telefon in naslednji korak

S25 je priklopljen. Samo bralni ADB pregled potrdi SM_S931B in uradno
1.11.13 (45), minSDK24/targetSDK36. Lokalni ADB daemon je bil zagnan; brez
klikanja, logcat vsebin, branja baze, zagona/ustavitve aplikacije, sinhronizacije
ali namestitve. Produkcijski strežnik in uporabniški podatki niso spremenjeni.

Popravek je za zdaj samo v izvorni kodi. Nova objava je po zadnjem uporabnikovem
navodilu prepovedana, dokler je uporabnik ne naroči. Telefon še nima novih
polj diagnostike; dejanski vzrok preostalega zastoja ostaja odprt.

## Neposredna namestitev na S25 — preverjanje podpisa

Uporabnik nato izrecno dovoli neposredno nadgradnjo S25, če je izvedljiva, in
ponovi prepoved oddaje na Google Play. Bralno prenesen samo nameščeni base.apk
(binarna aplikacija, brez uporabniških podatkov). apksigner potrdi Googlov
podpis ABF2D9DC…957C112CD; lokalni izdajni/upload certifikat je
E431544A…17D0A92F. Podpisa sta različna; lokalna gradnja zato ni združljiva
za neposredno nadgradnjo te Play namestitve. Namestitev ni bila poskušena;
nič ni odstranjeno/ponastavljeno. Ni gradnje, objave ali spremembe strežnika.
Prvi zagon apksigner ni našel Java Runtime; z obstoječim Android Studio JBR
je preverjanje uspelo. Dokazi: s25/preflight-result.json in
s25/installed-signature.txt v istem diagnostičnem sklopu.
