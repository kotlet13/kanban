# Jasna sporočila in diagnostika sinhronizacije — 31. oktober 2026

## Obseg

Uporabnik je naročil jasna sporočila, gumbe za odpravo znanih težav in
diagnostiko, s podagenti GPT-6.1 Sol/high ter lokalnimi testi. Telefoni in
produkcija ostanejo nespremenjeni. Ta sklop ne odpravlja še neznanega vzroka
napake na Samsungu A33: zajem uradne 1.11.4 ni vseboval izvorne izjeme.

## Prikaz in dejanja

Oblaček postavi razlago težave in razpoložljivo dejanje pred čase in števce.
Kadar je izvor znan, navede prizadeti prostor. Napake brez podatka o prostoru
ostanejo na ravni računa; trenutno izbrani prostor ni samodejno njihov vzrok.
Uspeh drugih prostorov ni domnevan na podlagi njihove odsotnosti s seznama.

- Potrditev e-pošte odpre obstoječo kartico istega računa.
- Znana zahteva za pregled zaščite odpre pregledni panel. Sam klik ne
  ustvarja novih ključev in ne ponavlja čarovnika.
- Pretečena prijava odpre obstoječo prijavo za isti strežnik. Ta pot prenese
  namerni prehod prek odjavljene seje med preverjanjem prijavnih podatkov.
- Povabila, pravila in sporne spremembe odprejo obstoječe postopke.
- Čakajoče odobritve se ponudijo samo pri znanem prostoru, ki ga uporabnik
  lahko upravlja. Prejemniku ne obljubljamo, da lahko sam odobri svoj dostop.
- Pri izgubljenih ključih, spremenjeni identiteti in neznanih vzrokih ni
  izmišljene rešitve s ponovnim ustvarjanjem računa ali ključev.

Dejanja preverijo trenutno sejo in stanje. Običajni postopki ohranijo svoja
pravila, potrditve, dovoljenja in zaščito pred menjavo računa. Obstoječi ročni
»Uskladi zdaj« ostane; ni novega samodejnega preverjanja ali omrežnega časovnika.

## Diagnostika

Zajem pred pretvorbo v splošno sporočilo shrani korak, izvorno dovoljeno kodo,
čas ter lokalno povezavo s prostorom. Seznam je omejen na 20 zapisov in je
v pomnilniku tekoče seje. Ob menjavi računa/naprave se odstrani. Ponovni poskusi
osvežijo dokaz za ponovno preverjene dele; navaden uspešen pregled sprememb
ne izbriše nerešene napake prenosa drugega prostora.

»Podrobnosti napake« in »Kopiraj diagnostiko« sta dostopna v običajnem
uporabniškem vmesniku; dodatna razvojna gradnja za uporabo tega prikaza ni
predvidena. Kopiranje je izrecno uporabnikovo dejanje, brez samodejnega pošiljanja.
Poročilo vsebuje samo različico formata, korak, kodo iz fiksnega dovoljenega
seznama ter čas, kadar je bil dejansko zabeležen. Ne vsebuje imen/ID-jev
prostorov, računov, strežnikov, naslovov URL, e-pošte, žetonov, ključev,
poslovnih zapisov, surovih izjem ali skladov klicev. Neznana koda je `unknown`.
Staro sporočilo brez izvora dobi neznan korak in brez izmišljenega časa.

Diagnostična napaka ne sme spremeniti izida sinhronizacije ali preprečiti
čiščenja zaklepa. Obdelani zapleti, ki se že razrešijo v obstoječem postopku,
ne smejo ustvariti novega lažnega rdečega oblačka.

## Lokalno preverjanje

Dokazi: `build/qa/sync-actionable-errors-20261031/`.

**17 različnih novih lokalnih kontrol PASS: 9 UI + 8 podatkovnih.**

- UI: e-pošta in menjava računa; zaščita brez samodejnega čarovnika;
  dejanska oddaja ponovne prijave prek začasno prazne seje z napako in nato
  uspehom; obstoječa povabila; pravila z izrecno potrditvijo; pregled konfliktov;
  neznana napaka in očiščen odložiščni izvoz; ozek zaslon s povečano pisavo;
  nerešena strukturirana napaka ne dopušča lažnega zelenega statusa.
- Podatki: dovoljena shema in nespremenljivost stanja; ista konstanta napake
  v dveh prostorih; ponovni poskus in odjava; uspešno poceni preverjanje ne
  skrije napake prenosa; neodvisna uskladitev B ne izbriše napake A; omejitev
  20 zapisov in odstranjeni zasebni podatki; koda imenika in odpoved same
  diagnostike; napaka finančnega prenosa in običajna zavrnitev pravic;
  čiščenje podatkov o članstvu šele ob dejanskem ponovnem preverjanju.

Poskusi ostajajo zabeleženi:

1. UI r1 se ni prevedel zaradi podvojene konstante v dovoljenem seznamu.
   Po odstranitvi podvojitve UI r2: vseh 9 PASS.
2. Podatkovni r1: 6 PASS, 1 FAIL. Globalna napaka testne ure je zadela tudi
   druge obstoječe uporabnike ure, zato ni izolirala želene odpovedi.
   Popravek testnega modela vbrizga odpoved samo pri branju razloga izjeme
   znotraj zajema. Samo ta kontrola je ponovno tekla in v r2 uspela.
3. Dodatna kontrola članstva r1 ni dosegla branja članov, ker je testni
   strežnik oglaševal staro različico pogodbe. Po dopolnitvi testnih
   zmogljivosti je samo ta kontrola v r2 uspela.

Uspešnih kontrol nismo ponovno zaganjali. Statična analiza spremenjenih
datotek nima napak ali opozoril; obstoječe slogovne informacije ostanejo.
Nove slogovne informacije so popravljene brez spremembe vedenja.
Neodvisni izvorni pregled je zajel še življenjsko dobo prijave, očiščenje
obdelanih konfliktov, natančnost ciljanih ponovnih preverjanj in izvoz.

Testi uporabljajo izolirano pomnilniško bazo in sintetične odzive oziroma
Flutter widget okolje. Niso nov preizkus celotnega podpisanega HTTP/E2EE
postopka ali dokaz uspeha na uporabnikovem telefonu.

## Omejitve in naslednji korak

Če spodnji sloj že vrne samo `pendingCryptoScopeIds`, je prvotni razlog
izgubljen pred tem zajemom. Takrat je znan korak metapodatkov in prostor,
razlog pa ostane splošna potrebna uskladitev. Ta sklop ne spreminja
kriptografskega protokola in ne trdi, da razloči vse interne razloge.

Spremembe so samo lokalne. Ni gradnje, namestitve, oddaje v Google Play,
strežniške spremembe ali novega poskusa na telefonu. Napaka A33 je še odprta;
po prihodnji običajni posodobitvi bomo lahko uporabili novi prikaz in kopiranje
diagnostike pri istem računu in podatkih.
