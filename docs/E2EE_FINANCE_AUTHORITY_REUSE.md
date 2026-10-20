# Skupna dokazila pravic pri finančnem branju — 20. oktober 2026

Naslednji uporabnikov cilj optimizacije je izveden v izvoru. Pri običajnem
testnem ciklu število zahtevkov pade s 54 na 47, telesa odgovorov pa s
683.951 na 383.867 B. Tri naloge so opravili podagenti GPT-6.1 Sol/high:
implementacijo, neodvisni pregled s podpisanimi kontrolami in primerjalno
meritev. Glavni agent je pregledal integracijo in dokaze.

## Izvedba in varovala

Obstoječi `withFinanceRead` pri obdelavi enega prostora zdaj poveže zaporedna
dovoljena finančna branja z istim `_AuthorityOperation` in istim
`CryptoDirectoryAuthoritySnapshot`. Ohranijo se prvotna ura, generacija,
lifecycle, preverjeni podpisi in skupen nabor varnih identitetnih zapisov.
Petsekundna meja se ob naslednjem branju ne začne znova. Običajni samostojni
klici imajo še vedno svoje preverjanje.

`CryptoVerifiedReadOperation` v `session_crypto_access.dart` upravlja to
življenjsko dobo; `account_directory_repository.dart` omogoča skupno
življenjsko dobo transportnega posnetka. `crypto_business_router.dart`
poveže samo obstoječi seznam dovoljenih metod: finančno politiko, pull,
izbiro računov in plačila. Kontekst se ob zaključku vedno zapre.

Pisanje oziroma sveža preveritvena meja, nepodprt dispatch, napaka, sočasna
uporaba, pretek časa ali sprememba identitete, lifecycle oziroma varnih
zapisov trajno umaknejo ponovno uporabo. Ob umiku napreduje generacija
avtoritete, zato preneha veljati tudi prej izdana podlaga, ki je zajela
le manjši del pozneje razširjenega nabora identitetnih zapisov. Nadaljevanje
uporabi običajno sveže preverjanje. Strežniške pravice pri zapisih in
obstoječi transakcijski SQL odtis finančne vsebine ostanejo.

Pred praznim usklajevanjem stroškov opravil se zdaj preveri obstoječi
`cryptoHasTaskDerivations`. Prazna pot ne odpre nepotrebne sveže meje.
Neprazna pot še vedno odpre svežo mejo in ohrani tudi notranje preverjanje;
naknadno nastalo delo ostane trajno shranjeno za naslednjo obdelavo.

Ni novega globalnega predpomnilnika, podaljšanja TTL, spremembe protokola,
sheme, strežnika, urnika, kvot, Firebase, SDK ali odvisnosti.

## Ciljni preizkusi in pregled

- Deset novih kontrol življenjske dobe PASS v prvem poskusu. Devet preveri
  zaporednost, globoke kopije, zaprtje, napake, sveže meje, mutacijo,
  sočasnost, identiteto in generacijo. Deseta z dejanskim prehodom čez
  prvotnih pet sekund potrdi, da se ura ne ponastavi.
- Pet novih kontrol z dejanskimi podpisanimi HTTP dokazili PASS v drugem
  poskusu: razširjeni nabor varnih zapisov in stare podlage, sveža meja,
  lifecycle, menjava identitete med čakanjem ter mutacija. Mutacija je
  prestrežena pred omrežjem; skupaj je bilo 26 bralnih RPC, nič zapisov.
  Prvi poskus je ustavil testni Flutter nadomestek HTTP400. Popravljena je
  bila samo testna nastavitev HTTP, strežniško stanje je ostalo isto.
- Edini spremenjeni obstoječi primer praznega usklajevanja PASS v drugem
  poskusu. Prvi je razkril manjkajočo metodo v starem testnem nadomestku,
  dodan je bil neposreden prehod skozi telo preverjene operacije.

Skupaj 15 novih kontrol in en prizadeti obstoječi primer PASS. Uspešnih
starih zbirk nismo ponavljali. Končna ozka analiza produkcijske spremembe
ima 0 napak, 0 opozoril in 66 obstoječih slogovnih informacij; novi podpisani
test ima ločeno čisto analizo. Vmesne analizne napake in opozorilo med
urejanjem so odpravljeni. Neodvisni in glavni pregled brez blokirajočih
ugotovitev; `git diff --check` čist.

## Dejanska primerjava HTTP

Osnova je zamrznjeni commit `5cca8bb`. Obe veji uporabljata isto merilno
ogrodje in ločeni kopiji istega zamrznjenega testnega odjemalca. Vsaka izvede
en začetni in dva merjena običajna cikla. Obe veji sta uspeli v prvem
poskusu; ni dodatnega urejanja, novih računov, povabil, obnove ali odvzema.
Merimo celotni `syncNow` in telesa HTTP, brez glav ali TLS.

| Običajni cikel | Prej | Potem |
|---|---:|---:|
| Vsi HTTP zahtevki | 54 | 47 |
| Authority snapshoti | 13 | 6 |
| Capability poizvedbe | 2 | 2 |
| Telesa zahtevkov | 7.580 B | 6.061 B |
| Telesa odgovorov | 683.951 B | 383.867 B |
| Odgovori authority snapshotov | 563.520 B | 261.056 B |
| Čas, prvi vzorec | 1.037,892 ms | 898,773 ms |
| Čas, drugi vzorec | 991,427 ms | 819,786 ms |
| Povprečje dveh vzorcev | 1.014,660 ms | 859,280 ms |

To pomeni 12,96 % manj zahtevkov in 43,88 % manj prenesenih teles odgovorov.
Čas je v teh dveh lokalnih vzorcih nižji za približno 15 %, kar še ni dokaz
zanesljivega pospeška na telefonu ali internetu.

Od prvotnih 13 snapshotov so bili trije zunaj finančnega dela in deset v
finančnem delu. Ostanejo trije zunanji ter trije finančni: preverjanje
starša, potreben katalog in preverjanje projekta. Posamezen finančni
dispatch ne zahteva več istega dokazila znova.

Število vseh drugih metod je v merjenih ciklih enako. Strežnika med vejama
ne ponastavljamo: zaradi novega checkpointa začetnega cikla je 12 inventory
odgovorov v novi veji večjih za 2.380 B. Prihranek samih authority odgovorov
je zato 302.464 B, skupni prihranek pa 300.084 B. To je edina druga razlika
v telesih odgovorov. Začetna cikla sta ločena od zgornje primerjave:
62 → 55 HTTP, 865.602 → 565.518 B odgovorov in 1.550,374 → 1.424,829 ms.

Vseh šest ciklov vrne samo HTTP200; brez napak, 429 ali čakajočega dela.
Vsi trije finančni zapisi in 62 predhodnih podpisanih zahtevkov ostanejo
točno enaki. Saldo je 33,33 EUR, strošek 12,34 EUR, računa in projektni
izbiri sta po dve. Izvirni odjemalec ter vseh 55 spremljanih predhodnih
dokaznih datotek ostanejo nespremenjeni.

## Meje in vezani dokazi

Docker na loopback vratih 59776 je spet ustavljen. Produkcija, Docker18811,
nameščene Mac/mobilne aplikacije, trgovini in nepovezana dokumenta ostanejo
nedotaknjeni. Ni nove native gradnje ali namestitve. P0, fizični mobilni
preizkusi, P8 in preostale meje N7 ostajajo odprti; to ni potrditev
produkcijske pripravljenosti.

Zasebni primerjalni dokazi so v
`/tmp/jivie-finance-read-reuse-20261020/authority-comparison/`.
Manifest povezuje izvor, ogrodje, začetne kopije in rezultate; skrivnosti
niso vključene v repozitorij.

SHA-256:

- `baseline/result.json`: `567128699676bdf64ac23f77f49e4c95b1144c6d3302dae73e6c7d0a119051a2`.
- `optimized/result.json`: `beb888680c6964d8952ed988e68de1b1472a313d0f3866d89d935c83a484f915`.
- `session_crypto_access.dart`: `01209e009f8517b2cec2ca5dab4bd5720b8cd7048e224e1d866427e0eb296579`.
- `account_directory_repository.dart`: `ed293a604221a66ff3191afc80f01f3fcf385248ea6cab8ed9eddc42004602ee`.
- `crypto_business_router.dart`: `9f4624c31d3a6cdf93a5d7c172da480a71737e7fd6657414a531e906823e689e`.
- `/tmp/jivie-retained-read-operation-attempt1.log`: `e54c79b1628da4905d5a63a6c901929e70f929e199f335f989a53b47d5f51819`.
- `/tmp/jivie-retained-read-expiry-attempt1.log`: `db31c4095e40a9b39c61144e93fd5fe9ef25d1530dd6ad7daf716fb7dcb01fae`.
- `/tmp/jivie-retained-authority-signed-guards-attempt2.log`: `08defd5b4aa6276a3378505e0fcec115744e37b8dc2d29f78b28daf6599b610f`.
