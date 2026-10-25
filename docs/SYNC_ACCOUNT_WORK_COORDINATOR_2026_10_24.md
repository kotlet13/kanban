# Skupni nadzor računskih zahtevkov in prebujanje sinhronizacije

Drugi izvedbeni korak po pregledu poti sinhronizacije, 24. oktober 2026. Nadaljuje [semantične namige sprememb](/Users/anzenovsak/Git/kanban/docs/SYNC_SEMANTIC_HINTS_2026_10_24.md) in fazo »Pokritost koordinatorja« iz [audita](/Users/anzenovsak/Git/kanban/docs/SYNC_PATHS_AUDIT_2026_10_24.md). To ni še končna meritev odzivnosti aplikacije ali odprava vseh prejšnjih omejitev zahtevkov.

## Kaj je spremenjeno

`CollaborationRepository` uporablja en `AccountWorkCoordinator` in en ovit transport. Isti transport dobijo običajni sync, povezani kriptografski račun, čarovnik zaščite, povabila, dokumenti, migracija in obnova. Obstoječa kriptografska preverjanja ostanejo pri svojih izvajalcih; koordinator ne odloča o dovoljenjih in ne sestavlja novih podpisanih zahtev.

Neposredna opravila imajo oznake izvora. Oznaka se prenaša skozi asinhrono delo, ne drži zaklepa med uporabniškim potrjevanjem, lokalno transakcijo ali čakanjem na obstoječo kriptografsko vrsto. Neposredna nizkonivojska branja imenika imajo splošno oznako računa, če nimajo konkretnejšega nadrejenega opravila. Avtentikacija pred prijavo je ločena identiteta; nekateri takšni zahtevki ostanejo brez podrobnejše oznake opravila, vendar še vedno uporabljajo isti transportni nadzor.

Omrežna pravila:

- Največ dve sočasni branji iz izrecnega seznama 99 operacij. Čakalna vrsta ima največ 64 zahtevkov oziroma 512 KiB parametrov. Prednost imajo interaktivna branja, z vmesnim prepuščanjem ozadju, da to ne strada.
- Pisanja, podpisane zahteve in neznane operacije se ne postavljajo v to novo vrsto. Zato med končnim preverjanjem dovoljenj in pošiljanjem ne dodajamo novega čakanja. To ni globalna omejitev vseh HTTP zahtevkov na dve.
- Združita se lahko samo še tekoči, povsem enaki zahtevi `capabilities` ali `account.changes` znotraj istega izrecnega opravila, iste identitete in generacije, v prvotnem petsekundnem oknu. Ni predpomnilnika končanih odgovorov. Mutacija prekine možnost novega združevanja.
- Kriptografski dokazi, statusi imenika in receipts se med neodvisnimi postopki ne združujejo. Obstoječe preverjanje podpisov, izteka veljavnosti, pričakovanih revizij in nespremenljivih zahtev ostane.
- Strežniški odgovor `rate_limited` ustavi nadaljnje poskuse proti istemu strežniku do navedenega roka. Lokalna zavrnitev tega roka ne podaljšuje. Nova plast ne dodaja samodejnih ponovitev; obstoječi izrecni postopki čakanja ostanejo. Omrežna reža se sprosti pred njihovim čakanjem.
- Identiteta vključuje strežnik, račun, napravo, bearer in generacijo repozitorija. Zamenjana identiteta zavrne čakajoče delo in stare odgovore. Podaljšanje roka seje z istim bearerjem ne razveljavi teh zahtev. Obstoječe ozko omejene odjavne poti `auth.revoke` in `push.unregister` ohranijo možnost čiščenja stare seje.

Koordinator hrani največ 128 diagnostičnih dogodkov v pomnilniku: vrsto opravila, začasno številko opravila, ime operacije, čas, čakanje in števce vrste. Ne beleži gesel, tokenov, ključev, vsebine zapisov ali obnovitvenih datotek. To ni trajni dnevnik niti popolna meritev časa vseh lokalnih faz.

## Lokalni zapisi

Skupne ideje, vrt in povezani osebni organizer oddajo signal šele po uspešnem zunanjem commitu, v katerem je nastala dejanska operacija za pošiljanje. Več zapisov istega računa v eni transakciji da en signal. Neuspešna notranja ali zunanja transakcija ga zavrže. Navadno branje, nespremenjena vsebina, lokalni osnutek in uporaba brez računa ne oddajo signala.

Obstoječi aktivni controller signal poveže z istim urnikom sinhronizacije. Zahteva preživi že tekoči sync in čakanje v ozadju; ne odpira novega controllerja ali dodatnega timerja. Signal je v pomnilniku, operacija za pošiljanje pa je trajna v bazi. Če poslušalca ni, jo odkrije obstoječi postopek ob naslednjem zagonu oziroma nadaljevanju. Preverjanje sprememb na 30 sekund ostane.

## Pregled in lokalno preverjanje

Izvedbo so pripravili podagenti GPT‑6.1 Sol/high; glavni agent je pregledal povezave, meje svežine in identitete. Dodan je neodvisen izvorni pregled omrežnega jedra. Pri neposrednih postopkih je pregled primerjal 36 obstoječih teles metod z novimi delegati: poslovna logika ostaja enaka, dodane so oznake opravil. Ta primerjava je pomoč pri pregledu, ne formalni dokaz enakovrednosti.

Dokazi so v `build/qa/account-work-coordinator-20261024/`: `local-work/`, `core/`, `direct-work/` in končni pregled glavnega agenta. Novi testi uporabljajo pomnilniški SQLite, sintetični transport oziroma `HttpCollaborationTransport` z `MockClient`; ne vzpostavljajo povezave z obstoječim strežnikom.

Skupaj je uspešnih **22 različnih novih lokalnih scenarijev**:

| Sklop | Izid | Kaj dejansko preveri |
| --- | --- | --- |
| Prebujanje po commitu | 8 PASS | Dejanski zapisi idej, vrta in povezanega osebnega opravila; nespremenjena vsebina; lokalna uporaba brez računa; notranji/zunanji rollback; menjava računa in lokalnega prostora; obstoječi controller med tekočim syncem, v ozadju, po vrnitvi in po odstranitvi poslušalca. |
| Omrežno jedro | 9 PASS v prvem poskusu | Omejitev branj in takojšnja mutacija; dovoljeno združevanje namigov; neodvisni dokazi/receipts; ločitev faz, generacij in izteka; stare identitete; rok po 429; omejena vrsta in zaprtje; sproščena omrežna reža med izrecnim čakanjem z nespremenjenim HTTP telesom; zavrnitev ponovne uporabe starega materiala po izteku prvotne authority lease med čakanjem. |
| Identiteta dejanskega repozitorija | 2 PASS | Podaljšanje seje z istim bearerjem ne zavrne tekočega branja; odjava zavrne stari token za običajno delo in ohrani odjavno čiščenje; neuspešno trajno shranjevanje nove seje prekliče točno izdani token. |
| Neposredni postopki | 3 PASS v prvem poskusu | Dejanske vstopne metode povabila, zaščite, dokumentov, obnove FILE, migracije in starega crypto statusa uporabljajo skupno mejo in ohranijo oznake. Preizkus se ustavi na sintetičnem prvem zahtevku; ne trdi uspešne celotne obnove ali povabila. Čakanje enega postopka ne drži novega omrežnega zaklepa pred drugim. |

Pri lokalnem prebujanju prvi poskus ni prevedel testov zaradi sočasno še nedokončanega uvoza novega jedra. V drugem je lokalni primer brez računa uspel, sedem drugih pa je ustavil nepravilno tipiziran sintetični odgovor `features`. V tretjem so uspeli samo ti sedem ponovno izbrani primeri. Pri testu podaljšanja seje je prvi poskus ustavil manjkajoči sintetični `account.status`; drugi ciljni poskus je uspel. Runtime varoval za te popravke fixture nismo oslabili. Uspešni testi niso bili ponovljeni, četrtega poskusa ni bilo.

Ciljne statične analize nimajo napak ali opozoril; ostajajo obstoječe slogovne informacije. Izvorni pregledi glavnega in neodvisnih agentov niso našli blokatorjev. Preverjeni so tudi eksplicitni bralni endpointi: crypto del je podmnožica strežniških nepodpisanih poti, mutacijski `scopeObservation.put`, `table.lease` ter inbox sync/open pa so iz bralne vrste izključeni.

## Meje in naslednje delo

Ta korak poenoti omrežno mejo in izvor zahtev ter popravi manjkajoče signale po shranjevanju. Ne združuje celotnih poslovnih postopkov ali neodvisnih kriptografskih preverjanj. Zato še ne dokazuje, da je prejšnjih 949 zahtevkov ali počasno odpiranje mobilnega opravila odpravljeno.

Naslednji dogovorjeni korak so preostali zasloni, ki morajo najprej prikazati lokalne podatke in ne čakati na nepovezano omrežno delo. Audit dodatno ohranja predlog omejene ponovne uporabe preverjenih odvisnosti znotraj veljavnih faz in ciljnega nadaljevanja konkretnega čakajočega dela; ta korak tega ne razglaša za dokončano. Obstoječi STOP3 za nadgradnjo/obnovo in preostale nepreverjene scenarije ostajajo zapisani. Novi lokalni testi jih ne nadomestijo in ne dovoljujejo četrte ponovitve.

Telefoni, produkcija, obstoječe testne aplikacije, Docker strežniki in njihovi podatki niso predmet tega koraka. Ni nadgradnje strežniške sheme, novih migracij uporabniških podatkov, native gradnje, namestitve, brisanja testnih okolij ali objave.
