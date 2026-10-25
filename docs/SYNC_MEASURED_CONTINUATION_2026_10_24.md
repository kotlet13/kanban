# Omejena meritev prenovljene sinhronizacije — 24. oktober 2026

## Obseg in stanje

Po uporabnikovem »Ok, nadaljuj« je bil izveden prvi omejeni merjeni zagon
po prenovi. GPT‑6.1 Sol/high podagenti so pripravili aplikaciji in strežnik,
ločeni pregledovalec je pregledal podlago in rezultate, glavni agent je
upravljal GUI. To ni ponovitev starega r6 STOP3: stara evidenca in njeni
hashi ostajajo nespremenjeni.

Obe isti Mac aplikaciji **Jivie Test Sync A/B** sta posodobljeni na r7,
vsaka z eno gradnjo in eno namestitvijo. Identiteti, podpisna ekipa,
Keychain nastavitve in poti podatkov ostajajo isti. Shramb nismo
ponastavljali ali brisali; bajtna enakost shramb zaradi omejitev dostopa
ni preverjena. Telefoni, produkcija in drugi Docker projekti so nedotaknjeni.

Na istem lokalnem strežniku 18821 je bila atomarno posodobljena samo
`NativeAccountChanges.php` z že pripravljenimi semantičnimi oznakami sprememb.
Pred tem je nastala konsistentna zasebna kopija SQLite. Hashi vseh tabel in
sheme so po posodobitvi isti. Konfiguracija, TLS in identitete vsebnikov so
ohranjeni; strežnika ni bilo treba znova zagnati.

## Novi izidi

| Preverjanje | Izid in omejitev |
| --- | --- |
| Zagon iste B | En zagon; A ostane zaprta. Na zaščitnem zaslonu izbrano samo »Continue locally«, brez ponovitve zaključevanja zaščite. |
| Prihod `SHARED-A-ASSIGNED-B-24` k B | **PASS za prikaz**: naslov, avtor Sync A, izbrani dodeljeni Sync B in opomba »Author A; assigned B may update this task.« so vidni. |
| Odprtje tega opravila iz projekta | Približno **518 ms od klika do AX odgovora**, vključno z režijo orodja. Obrazec je takoj dovolil urejanje, priprava računov stroškov je tekla posebej. To ni izoliran čas izrisa in ni mobilna meritev. |
| Lastnikova dopolnitev `SHARED-B-TASK-24` | **Nepreverjena**. Klik telesa kartice v skupnem seznamu ni pokazal spremembe. Nadaljnji klik puščice prav tako ni spremenil zaslona; puščica ima drugačen namen, glej spodaj. Brez shranjevanja. |
| Nov zapis dodeljenega uporabnika in prenos k A | **Ni začet**: pogoj zanesljivega zajema notranje diagnostike ni bil izpolnjen. |
| Dokazano umirjen sync in ločena 65-sekundna idle meritev | **Ni potrjeno**. Poznejši prazen del zajema vključuje tudi čas po zaprtju aplikacije. |

Ni bilo ročnega synca, Save, novih računov, povabil, odobritev ključev ali
ponovitve že uspešnih poslovnih scenarijev. B je bila normalno zaprta prek
Cmd-Q; sveža kontrola potrdi odsotnost obeh procesov.

## Dejanski omrežni promet

Zajem je trajal približno 179,751 sekunde in vsebuje **249 HTTP zahtevkov,
vse z odgovorom 200; nič 429**. Največ je bilo **247 vseh HTTP v drsečih
60 sekundah**. Prag opozorila 350 in varovalni prag 400 nista bila dosežena;
zaščitna ustavitev gatewaya ni bila sprožena. Gateway ostaja delujoč in
nezaustavljen. Zajem vsebuje 38.030 bajtov metapodatkov, brez vsebine,
gesel ali žetonov.

Prvih 246 zahtevkov je zajetih med 18:28:33 in 18:29:07 UTC. Nato so
sledili samo `account.changes` ob **18:29:07, 18:29:37 in 18:30:07 UTC**,
brez drugih operacij v vmesnih intervalih. To potrjuje opaženi 30-sekundni
ritem lahkega preverjanja v tem zagonu. Ne dokazuje vsebine odgovora,
zaključenosti vseh vrst ali splošne odprave prejšnjega problema 949 zahtevkov;
prejšnji A+B scenarij ni primerljiva delovna obremenitev.

Najpogostejše operacije v celotnem zajemu:

| Operacija | Število |
| --- | ---: |
| `crypto2.directory.status` | 89 |
| `crypto2.scope.headGet` | 44 |
| `crypto2.authority.snapshot` | 20 |
| `crypto2.account.status` | 16 |
| `crypto2.domain.inventory` | 16 |
| `crypto2.scope.lifecycle.list` | 16 |
| `crypto2.records.pull` | 8 |
| `account.changes` | 4 |

HTTP 200 ni dokaz uspešnega preverjanja podpisov ali dokončanja synca na
klientu. Časi gatewaya ne vključujejo klientovega CPU, čakanja koordinatorja
ali izrisa. Začetni sveženj je še kandidat za analizo; brez notranjih dogodkov
ga ni mogoče zanesljivo razdeliti med faze in sprožilce.

## Omejitev diagnostike in poti odpiranja

OS stream je bil zagnan pred aplikacijo in je ostal živ, vendar ni bilo
nobenega veljavnega dogodka `JIVIE_SYNC_QA_EVENT` ali napake `JIVIE_SYNC_QA`.
Tudi omejeni read-only `log show` za isti proces ni vrnil teh dogodkov.
`captureProof:false` zato pomeni **nedokazan zajem**, ne »ni napak«.
Pred naslednjim novim edit scenarijem mora biti ta pogoj odpravljen.

Izvorni pregled je potrdil vgrajeni QA helper, pravilno ime metode in
kanala, oba observerja v dejansko uporabljeni konstrukciji repozitorija ter
Swift handler brez zgodnjega izhoda pred obdelavo eventa. Natančna točka
izgube dogodka iz prvega zagona ni dokazana; Dart trenutno napake klica
diagnostičnega kanala prezre, most pa nima potrditve sprejema.

Ločen majhen Swift logger je v prvem poskusu uspešno preveden in izveden
(oba exit 0). Statično sporočilo `NSLog` je vidno v njegovem stderr,
10-sekundni OS stream za točno ta diagnostični proces pa ne vrne dogodka.
S tem je prazni OS zajem reproduciran neodvisno od Jivie; ni dokazano, da
Jivie dogodkov ne oddaja. Izbrane nastavitve `OS_ACTIVITY_MODE`,
`OS_ACTIVITY_DT_MODE` in `CFLOG_FORCE_STDERR` niso nastavljene; pot procesa
ni alias. Konkretni vzrok OS zajema ostaja neznan, zato ni slepega drugega
poskusa. QA aplikaciji zaradi te kontrole nista bili zagnani, HTTP klicev
ni bilo. Dokaz je v
`build/qa/sync-measured-continuation-20261024/diagnostic-fixture/attempt1-result.json`.

Neodvisni pregled navigacije potrdi razliko:

- Skupni seznam Tasks odpre lokalni predogled prek `openAllSpacesRow` in
  preverjanj trenutnega vira/vidnosti. Konkreten razlog neodziva telesa
  kartice iz zajetih dokazov ni potrjen.
- Puščica odpre **izvorni prostor**. Pri opravilih navigacija ne izbere
  posamičnega zapisa; če smo že v istem prostoru in Tasks, je nespremenjen
  zaslon pričakovan. To ni drugi dokaz okvare odpiranja editorja.
- Projektni seznam uporablja neposredno pot v editor; ta pot je bila pri
  dodeljenem opravilu uspešna.

## Nadaljevanje brez ponovitve PASS

1. Potrditi zanesljiv prenos diagnostičnih dogodkov. Ločeni logger je
   reproduciral težavo OS zajema; naslednji predlog je omejen datotečni
   dnevnik z varnimi fazami/števci ter potrditvijo prejema diagnostičnega
   kanala. Ta nadomestni kanal še ni implementiran ali preverjen.
2. Nadaljevati samo še nepreverjeno lastnikovo dopolnitev istega B opravila;
   ob neodzivu zajeti razlog izhodnega pogoja, brez slepega ponavljanja klikov.
3. Po stabilnem začetku enkrat dopolniti obstoječe dodeljeno opravilo z B,
   preveriti pri A, nato ločeno dokazati umirjen 30-sekundni ritem.
4. Širši scenariji drugih modulov, prekinitve/konflikti in mobilni testi
   ostajajo odprti. Stari upgrade/restore STOP3 ostaja nespremenjen.

## Dokazi

- `build/qa/sync-measured-continuation-20261024/apps-prepared.json`
- `build/qa/sync-measured-continuation-20261024/root-plan.json`
- `build/qa/sync-measured-continuation-20261024/root-runtime-observations.json`
- `build/qa/sync-measured-continuation-20261024/observed-request-cadence.json`
- `build/qa/sync-measured-continuation-20261024/diagnostics/http-summary.json`
- `build/qa/sync-measured-continuation-20261024/diagnostics/capture-stop-confirmation.json`
- Strežniška posodobitev in surov omejeni zajem:
  `build/qa/sync-redesign-20261024/measured-continuation-20261024/server/`.

V tem koraku ni sprememb produkcijske Dart logike, commita, pusha ali
čiščenja. Podatki, stari zahtevki, ključi in zgodovinski dokazi ostanejo.
