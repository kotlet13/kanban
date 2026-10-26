# Postopna optimizacija koordinatorja — 26. oktober 2026

Izhodišče: `66ee218`; ugotovitve P1–P8 iz
[modulnega pregleda](MODULE_SYNC_AUDIT_2026_10_26.md).
Uporabnik naroča ločene lokalne/headless kontrole ter commit in push vsakega
smiselnega sklopa. Brez posegov v telefone, obstoječe QA podatke ali produkcijo.
Meritve spodaj so števci konkretnih testnih poti, ne mobilni časovni benchmark
ali obljuba števila fizičnih E2EE HTTP zahtevkov. Starih uspešnih scenarijev
ne ponavljamo. Največ trije poskusi neuspešnega scenarija.

## P1 — ciljni signali dokumentov in lastno branje

Izvedeno: lokalni signal preverjene projekcije nosi vrsto in canonical ID;
priloga še stari/novi cilj. En SQL commit objavi en paket. Seznam preglednic
posluša preglednice, podrobnost svoj ID, priloge svoj cilj in njegov izbris.
Neznana stara tombstone/legacy invalidacija ostane konservativno široka.
Signal nikoli ne prečka računa/prostora ali neuspešnega SQL commita.

Vsako dokumentno branje ima kontekstni query-origin, prenesen po async coni.
Samo lastna projekcija istega branja ne sproži ponovnega branja tega pogleda;
drugi pogledi in neodvisni koordinatorjevi commiti ostanejo obveščeni. To ni
cache dovoljenj in ne preskoči svežih dokazov, pravic ali samega branja.
Lease, osnutki, šifriranje, signed requesti in protokol so nespremenjeni.
Lastne mutacije še vedno objavijo signal; ne trdimo odprave vsakega možnega
ponovnega branja po uploadu ali navigaciji nazaj.

Nove kontrole, vseh **5 PASS v prvem poskusu**:
- 3 repository/gateway kontrole: query-origin razlikovanje; res oddaljen commit
  med branjem; target filter in device_revoked ob ohranjenem lokalnem osnutku.
- 1 pravi memory SQLite preizkus: nested commit, paketno dedupliciranje,
  rollback, partition/scope izolacija in neznan tombstone.
- 1 headless widget preizkus dejanske list→detail poti: list=1, detail=1;
  dve nepovezani spremembi ne dodata branj; matching remote revision doda
  natanko eno branje in je vidna. Lastni read-signal ne doda trailing branja.

Repository transport v teh kontrolah je sintetičen; to ni nov kriptografski
HTTP ali native dokaz. Izvorni pregled emitterja ohranja hash-change pogoj in
objavo šele po potrjenem SQL commitu. Ozka analiza: 0 napak/0 opozoril;
12 obstoječih slogovnih info (nov curly-braces info odpravljen). Diff check PASS.
Dokazi: `build/qa/coordinator-optimization-20261026/p1-*.log` (ignorirano).
Prvi skupni testni filter je izbral samo tri `coordinator` teste; SQL test
je zato zagnan posebej, ne ponovljen. Vseh pet kontrol ima samo en tek.

## Nadaljevanje

P2–P7 še odprto; P8 najprej zahteva meritev lokalnega SQL/CPU, ne slepega
spreminjanja. Status naslednjih sklopov dodajamo spodaj pred njihovim commitom.

## P5a — drugo branje inboxa samo po oddaljenem ukazu

Izvedeno: `_syncCommands` vrne, ali je dejansko poskusil oddaljen ukaz.
Prazna ali lokalno zavrnjena vrsta ne povzroči drugega `_syncInbox`. Po ACK,
`notification_missing` in konfliktu se drugo branje ohrani. Nadaljevanje
shranjenih ukazov, nespremenjen request, preklici in napake ostanejo isti.

4 nove headless repository kontrole PASS: prazna vrsta ima 1 inbox.sync/0
inbox.read; ACK, poteklo obvestilo in konflikt imajo 2 inbox.sync/1 inbox.read.
ACK se uporabi; missing odstrani samo obvestilo; konflikt ostane blocked;
pravica do prostora je ohranjena. Prvi tek je ustavila sintetična fixture
brez eksplicitnega legacy routerja (crypto_reconciliation_required); dodan
fail-closed router, brez izmišljenih ključev. Drugi tek 3 PASS, ACK fixture
imela star datum 11.10. in je pravilno sprožila retencijo. Tretji tek SAMO ACK
s trenutnim datumom PASS. Ni četrtega teka ali ponovitve treh PASS.
Ozka analiza 0 napak/0 opozoril, 9 obstoječih info; nov info v testu popravljen.
Dokazi `p5a-*`. Transport je sintetičen in SQLite pravi; ne HTTP/native test.
Konfiguracijski fanout (P5b) še sledi.

## P5b — oddelen namig za konfiguracijo obvestil

Strežnik v isti metadata snapshot doda `notificationHintsVersion: 1` in
`notificationConfigurationChanged`. Obstoječi accountDomains/inbox ostane
združljiv s starimi aplikacijami. Cursor ima dodatni podpisani digest že
obstoječega configuration_revision; shema in poslovni podatki se ne spreminjajo.
Stari cursor brez polja zahteva eno konfiguracijsko osvežitev in se nato umiri.
Nova aplikacija ob običajnem inbox dogodku preskoči preferences/reminders
fanout. Ob resetu, spremenjenem dostopu ali poslanem ukazu ga ohrani. Stari
ali neznani strežniški hint uporablja prejšnjo konservativno pot.

**15 novih kontrol PASS:** 8 strežniških + 7 Dart repository/parser.
Strežniški prvi tek: prvih 5 kontrol PASS; test podpisa starega cursorja FAIL,
ker fixture ni uporabila obstoječe HMAC domenske izpeljave ključa. Ta sklop
razdeljen v split/compat datoteki; drugi tek samo 3 še odprte compat kontrole
PASS (stari cursor, settle, izolacija računa). Ni ponovitve prvih 5 PASS.
To je dejanski NativeAccountChanges nad disposable memory SQLite v Dockerju
brez mreže; ni nov E2EE podpisni ali HTTP test.

Odjemalec 7 PASS v prvem teku: navadni inbox 0 preference + 0 reminder branj
za 2 prostora; config/access/legacy/unknown/command vsak ohrani 2+2. Preverjen
je tudi strog tip eksplicitnega hint polja. Uporabljen pravi repository/SQL
in sintetičen legacy transport; ne trdimo prihranka fizičnih crypto HTTP.
Analiza 0 napak/0 opozoril, 9 obstoječih info. `p5b-*` dokazi, brez deploya.

## P7 — en status po potrditvi e-pošte

Repository vrne AccountStatus iz že obstoječega account.status po uspešni
potrditvi; controller ga prenese, UI ga uporabi brez drugega status klica.
Potrditev je vezana na začetno sejo/epoch; status in UI ohranita identity guard.

5 novih kontrol PASS: repository uspeh/call count + napaka confirm + napaka
status (3 PASS1); UI uporaba vrnjenega statusa + ignoriranje poznega rezultata
po zamenjavi računa (2 PASS2 po manjkajočem importu modelov v novi fixture).
Prve tri niso ponovljene. UI ima samo začetno status branje; vrnjena potrditev
ne doda drugega. Analiza 0 napak/0 opozoril, 2 stara info; nov testni info
popravljen. Dokazi `p7-*`. Obstoječi UI fake override prilagojen vrnjenemu tipu;
stari suite ni ponovno izvajan. Ni pošiljanja prave e-pošte ali sprememb računov.
