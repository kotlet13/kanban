# Skupno pridobivanje zmogljivosti med sinhronizacijo — 20. oktober 2026

Po uporabnikovem naročilu naslednje optimizacije je običajni testni cikel
zmanjšan z69 na54 HTTP zahtevkov. Poizvedbe `capabilities` padejo s17 na2;
podpisana dokazila pravic se še naprej pridobivajo po dosedanjem postopku.
Trije GPT-6.1 Sol/high podagenti izvajajo popravek, neodvisni pregled in
meritev; glavni agent pregleduje integracijo in rezultate.

## Izvedba

Novi `CryptoCapabilityDiscovery` obstaja samo med enim klicem `syncNow()`.
Ponovno uporabi uspešen odgovor o javnih strežniških funkcijah in združi
sočasne enake poizvedbe. Vezan je na točno instanco transporta in seje;
anonimna poizvedba in poizvedba z uporabnikovim tokenom ostaneta ločeni.
Zato običajni cikel potrebuje dve poizvedbi, ne ene.

Uporaba je povezana na tri obstoječa mesta: `_negotiate`,
`accountCryptoPreview` in branje `capabilities` v
`AccountDirectoryRepository`. Ostale metode niso vključene.
Ohranjen je izvirni HTTP način posameznega klica.

Zaprtje repozitorija, sprememba epohe ali seje in neveljavna seja prekinejo
ponovno uporabo. Tudi zamenjava objekta seje ob obnovi konservativno
prepreči uporabo starega odgovora. Vsak naslednji ali vgnezdeni `syncNow()`
dobi nov kontekst; ob koncu se ta vedno zapre, tudi ob napaki.
Ločena opravila zunaj sinhronizacije ohranijo neposredne poizvedbe.

Napake in odgovori drugega strežnika ne ostanejo shranjeni. Porabniki
ohranijo svoje preverjanje odgovorov; posebej `_negotiate` še vedno
trajno označi spremenjeno identiteto strežnika in zavrne nadaljevanje.
Pozen odgovor po spremembi identitete ne ostane shranjen, obstoječa
preverjanja porabnika pa odločijo o njegovi zavrnitvi. Globoke kopije
preprečijo, da bi porabnik spremenil skupno shranjeni odgovor.

Spremenjenih je pet produkcijskih datotek. Ni združevanja dokazil pravic
med preverjenimi operacijami, novega TTL, spremembe petsekundne meje,
podpisov, strežniških kontrol, urnika ali kvot. Strežniška koda in shema
ostaneta enaki. Firebase, SDK in odvisnosti niso spremenjeni.

## Novi preizkusi

Vseh21 novih testov PASS v prvem poskusu:

- Devetnajst kontrol pomočnika: sočasnost, globoke kopije, novi cikli in
  sprememba podprtih različic, zunanja opravila, vezava na transport/sejo/
  strežnik/račun/napravo/token, neuspešni odgovori, napačen strežnik,
  vgnezdeni postopki, zaprti konteksti in pozna sprememba identitete.
  Ločeni authority snapshoti ostanejo ločeni tudi po mutaciji.
- Dva integracijska testa repozitorija: ponovna uporaba znotraj cikla in
  sveže branje v naslednjem/vgnezdenem ciklu; trajna zavrnitev spremenjene
  identitete strežnika brez poznejšega omrežnega nadaljevanja.

Ozka analiza:0 napak,0 opozoril,1 obstoječi slogovni info. Primerjalno
HTTP ogrodje ima ločeno čisto analizo. Glavni in neodvisni pregled brez
ugotovljenih težav; `git diff --check` je čist. Starih uspešnih zbirk
nismo ponavljali.

## Dejanska primerjava HTTP — obe veji prvi poskus PASS

Stara koda je zamrznjeni `2af5fb4`; nova uporablja spodaj vezani izvor.
Ponovno uporabljeno primerjalno ogrodje dobi samo možnost ločenega
imenika rezultatov. Prejšnji končani primerjavi ostaneta nespremenjeni.
Obe novi veji začneta iz enake zamrznjene kopije izvirnega testnega
odjemalca:3 finančni zapisi in62 podpisanih zahtevkov. Ni novega urejanja,
računa, povabila, obnove ali odvzema.

Vsaka veja izvede en ločen začetni in dva merjena običajna cikla.
Čas zajema celotni `syncNow()`, brez inicializacije in preverjanja izida.
Ni pacinga ali zvišanja kvote v merjenju; bajti štejejo telesa HTTP,
ne glav ali TLS. Vsak vzorec preveri nov zaključek in dejanski promet.

| Meritev običajnega cikla | Pred spremembo | Po spremembi |
|---|---:|---:|
| HTTP zahtevki | 69 | 54 |
| `capabilities` | 17 | 2 |
| `crypto2.authority.snapshot` | 13 | 13 |
| Telesa zahtevkov | 8.165 B | 7.580 B |
| Telesa odgovorov | 717.179 B | 681.575 B |
| Čas, vzorec1 | 1.074,452 ms | 1.046,276 ms |
| Čas, vzorec2 | 1.040,906 ms | 983,985 ms |
| Povprečje dveh vzorcev | 1.057,679 ms | 1.015,131 ms |

Število zahtevkov pade za15 oziroma21,74 %. Capability odgovori se
zmanjšajo s43.044 na5.064 B. Celotni odgovori so manjši za35.604 B
(4,96 %), zahteve za585 B. Povprečje časa je nižje za približno4 %,
vendar dva lokalna vzorca ne dokazujeta zanesljivega časovnega pospeška.

Začetni cikel stare kode:80HTTP/1.638,171 ms/906.426 B odgovorov;
nove kode:62HTTP/1.450,882 ms/863.226 B. Oba sta ločena od zgornjih vzorcev.
Vsak pripravi en checkpoint; to ni nov poslovni vnos.

Strežnika med vejama ne ponastavljamo. Zaradi napredovanja checkpointa ima
nova veja2.376 B več inventory odgovorov. Vsi drugi števci metod in bajti
odgovorov, razen ciljanih capability odgovorov, so enaki. S tem ločimo
dejanski učinek popravka od napredovanja strežniških metapodatkov.

Vseh šest ciklov vrne HTTP200, brez429 ali končnih napak. Finančne vrstice
in vseh62 prvotnih podpisanih zahtevkov ostanejo točno enaki; saldo33,33EUR,
strošek12,34EUR, dva računa, dve projektni izbiri, čakalne vrste0/0/0.
Izvirni odjemalec in prejšnji rezultati so preverjeno nespremenjeni.

To je majhen lokalni loopback nabor, brez native UI. Ne dokazuje hitrosti
prek interneta ali na fizičnih napravah. Ponavljajočih13 authority snapshotov
ostaja možen naslednji cilj, ki potrebuje ločeno presojo svežine dokazil.

## Stanje in dokazi

Samo Docker59776 je bil začasno zagnan in je spet ustavljen. Produkcija,
Docker18811, stare Mac/mobilne QA namestitve in trgovini ostanejo
nedotaknjeni. Brez nove native gradnje ali namestitve; P0/mobile/P8/N7
ostajajo odprti. Nepovezana varnostni in desktop dokumenta nista spremenjena.

Priprava začasnega izvornega arhiva je potrebovala popravek uporabe
Python `tarfile` za lokalno različico; to se je zgodilo pred HTTP teki,
brez spremembe izvirnih podatkov. Noben test ni potreboval ponovitve.

Vezani SHA-256:

- `crypto_capability_discovery.dart`:
  `576f0720f7c264a58d26e2638b766c816bd742ea7f32b2e90ace1a7c4dd9543a`.
- `collaboration_sync_actions.dart`:
  `dc5f245bbff7b726a28b2ca6a92eadd30e3f2fc0d600249e7f463953ccf14c77`.
- `/tmp/jivie-capability-discovery-attempt1.log`:
  `b7e8d563eacc01b7640bd708ac3ca135ab2133973b867188925f0414e477034e`.
- `/tmp/jivie-capability-discovery-analyze.log`:
  `b7bd63d1fba188d9fc013be2a0ac6b205dd5d52c7eeafde3bcdac8d18048b286`.

Zasebni primerjalni dokazi so v
`/tmp/jivie-finance-read-reuse-20261020/capability-comparison/`:

- `baseline/result.json`:
  `d885ac443b8a9bee97c4e61aeb892b36014e5ad611c2223fca42c872d6cfba07`.
- `optimized/result.json`:
  `a7f7c82a9b35a0e776375f7260632ea2e2f6f77aa708191c2d0d1dff29caea6b`.

Manifest veže izvor, isto ogrodje, začetne kopije in dnevnike obeh vej.
Skrivnosti ostanejo zunaj repozitorija.
