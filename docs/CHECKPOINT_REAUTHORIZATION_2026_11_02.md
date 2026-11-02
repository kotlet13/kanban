# Zaključek zadržanih potrditev po ponovni potrditvi dostopa

## Izhodišče in obseg

Uporabnikov izvoz ob 19:25:46 UTC kaže 19 zadržanih zahtev
`crypto2.domain.checkpoint`, potrdilo `unknown`, nadaljevanje `ineligible`,
shranjen razlog `scope_reauthorization_required`. Prejem vsebine in financ v
istem poskusu ni bil zabeležen. To ni dokaz, da se vsebine nikoli ne prenašajo,
ali da shranjena ovira še vedno velja. Strežnik in telefon nista bila spreminjana.
Uporabnik je odobril lokalni popravek in novo javno Android izdajo.

## Sprememba

- Ponovni ročni poskus za checkpoint z razlogom reauthorization preveri svežo
  avtoriteto in pošlje samo nespremenjeno prvotno zahtevo iste aktivne naprave,
  če vsa obstoječa varovala dovoljujejo nadaljevanje. Najprej preveri potrdilo.
- Zastarelo izpeljano potrditev lahko nadomesti preverjeno trenutno dokazilo,
  ki je bilo preneseno s strežnika oziroma ga je podpisal drug pooblaščen član.
  Ne zahteva več lokalne odhodne vrstice za preneseno dokazilo.
- Pri višjem zaporedju je dovoljen novejši popoln popis. Pri istem zaporedju se
  morajo ujemati manifest, število in izvor zgodovine. Ostaneta preverjanje
  prednikov glave in pokritje vseh znanih zapisov/obnovitvenih sidrišč.
- Izvirna zahteva, podpis, stanje `blocked` in odgovor ostanejo nespremenjeni.
  Atomski lokalni zaznamek in revizijski dogodek določita, da je izpeljano delo
  izpolnjeno; to ni lažno strežniško potrdilo `applied`.
- Enotni SQL izbor aktivnih zahtev zahteva ujemajoče se dokazilo in revizijski
  dogodek. Če dokazilo izgine ali se zamenja, stara zahteva ponovno šteje kot
  aktivna. Nova preveritev lahko z varovano primerjavo posodobi zaznamek.
- Ni preglasitve zavrnitve/terminalnega izida, spreminjanja podpisanih zahtev,
  praznjenja vrste, ponastavitve ključev ali spremembe strežniške sheme.
- Celoten prejem vsebine in financ mora uspeti pred novo uspešno uskladitvijo;
  obstoječe varovalo generacije in največ en dodaten celoten prehod ostajata.
- Glavni prikaz združi enake zadržane zahteve in skrajša ponavljajoče razlage.
  Kopirana diagnostika ohrani vse razpoložljive vzorce in varne razloge.

## Lokalno preverjanje

Dokazi: `build/qa/checkpoint-reauthorization-20261102/`.

22 različnih novih preizkusov PASS:

- 13 jedrnih: vseh 19 zahtev, novejši popis in 11 negativnih varoval;
- 4 nadaljevanja: sveža avtoriteta, še zastarela, preklicana, druga naprava;
- 1 dokazilo drugega pooblaščenega člana s pravim podpisom in imenikom;
- 2 povezovalna: koordinator, ista SQLite baza, pravi izdajatelj dokazila,
  celoten vsebinski/finančni prehod, uspeh oziroma ohranitev zavrnitve;
- 2 UI: slovenski/angleški prikaz pri širini 390, ena skupina 19 zahtev,
  brez izgube 19 vzorcev v podrobnostih.

Kriptografski podpisi, preverjanje imenika/glav, SQLite in transakcije so pravi.
Omrežje, dostop do glave/ključev in zunanja projekcija v povezovalnem testu so
izrecni testni vmesniki. To NI dejanski telefonski ali HTTP E2E PASS. Uspeh na
uporabnikovih 19 vrsticah ostaja za preverjanje po običajni posodobitvi.

Zgodovina poskusov:

- RED1: napaka fixture pri ponovnem zapisu nespremenljivega izida; popravljena
  začetna priprava. RED2 s prvotno produktno kodo reproducira 19 aktivnih vrstic.
- Popravek core R1: manjkajoč import UUID validatorja; R2 vseh 13 PASS.
- Nadaljevanje R1: 4 PASS; UI R1: 2 PASS.
- Drugi avtor R1: neurejeni člani fixture; R2: dva lastnika fixture; R3 po
  pravilni obliki imenika (en lastnik in pooblaščen član) 1 PASS.
- Koordinator R1: dinamični klic razširitve Dart; R2: nov šifrirani kontekst
  ni uporabljal načrtovanega projekcijskega vmesnika fixture; R3 z izrecno
  sintetično zunanjo projekcijo 2 PASS. Podpisani izdajatelj je ostal pravi.
- Noben že uspešen test ni bil ponovno zagnan. Ni četrtega poskusa.
- Končna analiza 11 datotek: 0 napak, 0 opozoril, 9 predhodnih slogovnih
  informacij v crypto_sync_repository. Nove slogovne informacije odpravljene.

## Naslednji korak

Običajna posodobitev iste aplikacije in en pritisk »Uskladi zdaj«. Brez brisanja,
odjave, novega računa ali ponovnega uvoza obnovitvene datoteke. Če ostane ovira,
kopirati podrobnosti istega poskusa. Izdaja je vodena v ločenem release dokumentu.
