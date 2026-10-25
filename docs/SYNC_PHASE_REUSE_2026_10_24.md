# Omejena ponovna uporaba preverjanj in ciljna obravnava čakajočega dela

24. oktober 2026. Nadaljevanje [izvornega načrta](/Users/anzenovsak/Git/kanban/docs/SYNC_PATHS_AUDIT_2026_10_24.md) po skupnem koordinatorju in lokalnem prikazu zaslonov.

## Obseg tega koraka

Dve omejeni spremembi, brez globalnega predpomnilnika dokazov:

1. Začetna priprava projekcijskih cursorjev lahko znotraj obstoječe faze metapodatkov uporabi že preverjeno glavo in imenike istega prostora. Izvirna petsekundna meja ostane. To pomaga ob manjkajočem začetnem markerju oziroma migraciji; pri že pripravljenem prostoru je ta korak že prej preskočen. Ne pomeni ponovne uporabe dokazov skozi celoten vsebinski ali finančni prenos.
2. Običajna čakajoča podpisana zahteva za zapise ne potrebuje nujno pregleda celotnega računa. Ciljni izbor je dovoljen samo, kadar lokalne nespremenljive zahteve, claims in obstoječe vrste nedvoumno pokažejo točno operacijo, ki jo že zna nadaljevati dosedanja pot pošiljanja. Neznane odvisnosti, nepovezana oziroma nepopolna zahteva in povezana plačila ohranijo izrecen širši fallback. Par opravilo/strošek ima posebno podpisano vezavo in v tem koraku ostaja na širši poti. Enako velja za opravila v podprostoru z nadrejenim prostorom: obstoječa pozna izpeljava finančne odvisnosti še nima v tem koraku razrešene povezave do nadrejene finančne projekcije. Tega ne ugibamo in ne razglašamo vseh opravil za optimizirana.

Receipt-first nadaljevanje, podpisana telesa, avtorstvo, preverjanje aktualnih dovoljenj in uspešna trajna obdelava pred potrditvijo account cursorja ostanejo. Namig za izbiro dela ni nov dokaz dovoljenja. Interval preverjanja ostane 30 sekund.

## Izvedba in dokazi

Izvedeno in izvorno pregledano z GPT‑6.1 Sol/high podagenti, neodvisnim pregledovalcem in glavnim agentom. Dokazi so v `build/qa/sync-phase-reuse-20261024/`; začetni manifest je zajet pred spremembami. Selektor ima dokaze v `build/qa/targeted-pending-sync-20261024/local-selection/`, priprava izvora cursorja pa v `build/qa/sync-phase-reuse-20261024/read-phase/`.

Selektor pregleda največ 64 čakajočih zahtev oziroma 1 MiB podpisanih teles. Sprejme samo podprt običajni vsebinski batch z nespremenljivim request ID/hash, lastno vezavo račun/naprava/strežnik, popolnim naborom claims ter ujemanjem trenutne lokalne operacije z obstoječim `crypto_business_requests`. Upošteva tudi upravičenost obstoječe vrste za pošiljanje. Deklarirane reference imajo točen prostor, domeno, ID, revizijo in proof hash; združijo se z oddaljenimi namigi in lokalnimi vrstami. Izbor ničesar ne podpiše ali pošlje in ni nadomestilo za kriptografski sprejem. Dosedanja pot `push` še vedno preveri in nadaljuje točno shranjeno zahtevo.

Nepodprto, nepopolno, osirotelo, preveliko ali drugače nedoločljivo delo ohrani širšo pot. Razlog se shrani kot enum v obstoječi omejeni diagnostiki, brez ključev, vsebine ali identitet. Širši fallback sam po sebi ne odpravlja že obstoječe omejitve osirotele zahteve brez običajne operacije za nadaljevanje.

Priprava izvora cursorja ima tipiziran notranji klic; javni seznam združljivih operacij se ni razširil. Faza obsega obstoječe metapodatke in isti izbor izvornih markerjev, nato se konča pred finančno pripravo, pošiljanjem in pullom. Iztek izvirnih petih sekund, zapis, sprememba identitete, nezdružljiv klic, prekrivanje ali napaka prekinejo ponovno uporabo.

### Novi lokalni rezultati

| Sklop | Rezultat | Dejanski dokaz |
| --- | --- | --- |
| Ponovna uporaba priprave | 5 PASS v prvem poskusu | Dva sintetična porabnika opravita skupaj 2 klica namesto 4; dejansko preverjanje podpisov imenika in glave ostane pri obeh. Preverjeni so prvotni iztek, prekinitev pred zapisom, sveži receipts, zavrnitev ponarejene aktivacije po invalidaciji in meje identitete/napak/prekrivanja. |
| Ciljni izbor in nadaljevanje | 8 PASS: 7 v drugem, 1 v tretjem poskusu | Realna pomnilniška SQLite baza, strukturni izbor in obstoječa produkcijska `CryptoBusinessSession.push → _writeRaw` pot preverita shranjeno operacijo. Ciljni scenarij obdela content A/C/D, 0 finance in 0 kataloga; nedotaknjen B ima dejansko omogočen finančni dostop in lokalni ledger. Uporabi isti request ID in nespremenjeno podpisano telo. Napaka ohrani stari cursor; invalidacija prepreči potrditev starega probe. |
| Izrecni širši fallback | Vključen v zgornjih 8 | Payment scenarij obdela vse 4 content in 4 finance prostore ter katalog in zabeleži razlog `payments`. To je drugačen scenarij, ne odstotkovna primerjava hitrosti z ožjim primerom. |

Skupaj **13 različnih novih PASS**, brez ponovitev prejšnjih uspešnih testov. Prvi tek osmih selektorskih testov se je ustavil v sintetični pripravi zaradi netipiziranega `features` zemljevida. V drugem je samo eligibility matrix uporabil JSON število `1` namesto booleana `true` za arhiviran prostor; tretji je ponovil samo ta neuspešni test. Oba neuspešna dnevnika sta ohranjena. Runtime koda se med temi teki ni spreminjala. Noben četrti poskus.

Končne ozke analize nimajo napak ali opozoril; ostajajo slogovne pripombe, vključno s petimi v novi crypto testni pripravi. Glavni in neodvisni izvorni pregled sta PASS. Hashi pregledanih in preizkušenih izvorov so shranjeni ob dokazih.

### Kaj ti testi ne dokazujejo

To niso live HTTP, native ali telefonski preizkusi. Crypto priprava preverja prave podpise, vendar ima eksplicitno sintetično lifecycle/descriptor/native-origin mejo; pozitiven dokaz migracijskega publication anchorja ni na novo preizkušen. Selektorski test uporablja pravo repozitorijsko in saved-request pot, medtem ko so kriptografska dovoljenja, queue delivery in receipt odgovor eksplicitno nadomeščeni s testnimi komponentami. Ne gre za nov poln E2EE prenos ali obnovo.

Prihranek 4 → 2 velja samo za konkretno začetno pripravo manjkajočega markerja. Ožji izbor velja za opisano podmnožico čakajočih običajnih zapisov, ne za vse finance, dokumente, povezana plačila ali opravila v podprostoru. Prejšnja težava 949 zahtevkov oziroma native 429 še ni izmerjeno odpravljena. Naslednji dogovorjeni korak je omejen merjen lokalni preizkus dveh aplikacij; ne nov slepi krog starih STOP3 scenarijev.

## Meje

Ni uporabe telefonov, produkcije, obstoječih native testnih namestitev ali Docker strežnikov. Ni spremembe strežniške sheme, ključev, podpisov, izdaje, čiščenja podatkov ali ponovitve prejšnjih uspešnih testov. Prejšnji STOP3 za preveliko število zahtevkov, nadgradnjo in obnovo ostajajo zgodovina; ta korak ni četrti native poskus. Zmanjšanje celotnega prejšnjega prometa oziroma mobilna odzivnost še zahtevata poznejši dogovorjeni merjen preizkus.
