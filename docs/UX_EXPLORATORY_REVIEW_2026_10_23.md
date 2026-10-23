# Pregled uporabnosti Jivie na Macu

**Zgodovinski pregled stare gradnje r12.** Aktualni paket r14 in lokalni strežnik sta bila pozneje posodobljena in dejansko preklikana; glej [pregled aktualne različice](UX_LATEST_MAC_REVIEW_2026_10_23.md). Spodnji rezultati ostajajo vezani na prvotni paket.

23. oktober 2026. Prvi raziskovalni pregled ene testne instance, pred morebitnim pregledom deljenja med tremi instancami. Poudarek: enostavnost vsakodnevne uporabe, razumljiva zaščita podatkov in vidno deljenje. Popravki v tej nalogi niso izvedeni.

Glavna ugotovitev: osnovna navigacija in prazni seznami so razumljivi, razlaga zaščite in kontekst deljenja pa nista dosledna. Najprej je smiselno poenotiti prikaz »kje delam, kdo to vidi in ali moram kaj storiti«, nato poenostaviti obrazce.

## Okolje in meje pregleda

- Dejansko odprta in upravljana aplikacija: `/Users/anzenovsak/Applications/Jivie Test Share A.app`, različica 1.10.1 (31), bundle ID `si.tripar.jivie.e2eetest.sharea20261019`.
- Nameščeni paket je r12 na osnovi `eacc0a5`, starejši od trenutnega izvora `e2910f9`. Vključitve zadnjih popravkov sinhronizacije v ta paket ne trdimo. Ključna opažanja so dodatno preverjena v trenutni kodi, kjer je to spodaj navedeno.
- Ločena testna shramba, testni račun A in lokalni QA strežnik `https://127.0.0.1:18811/`. Druga in tretja instanca nista bili odprti.
- Pregledani so obstoječi skupni projekt, osebni lokalni prostor in nov prazen lokalni gospodinjski prostor **UX pregled – lokalno 20261023**. Ta zadnji je edini namerno dodani zapis; ob ustvarjanju je bilo »Sync with cloud« izključeno. V nastavitvah je nato potrjen prikaz »Household · Local · not synchronized«. Prostor ostaja za morebitno nadaljevanje pregleda.
- Obstoječih vnosov nismo urejali ali brisali. Obrazci opravila, dogodka, ideje, nakupovalnega seznama, osebe in vrta so bili zaprti brez shranjevanja. Povabil, odobritev, izvoza ključev, obnovitve kopij ali sprememb pravic nismo izvedli. Aplikacija je med običajno navigacijo lahko izvajala svoj samodejni sync; to ni dokaz bajtno nespremenjene testne baze.
- Telefonov, produkcijske aplikacije, produkcijskega strežnika in Docker konfiguracije se ta pregled ni dotikal. Brez gradnje, namestitve, objave ali ponavljanja že uspešnih avtomatiziranih scenarijev.
- Ob koncu je bila zaprta samo pregledana testna instanca; njen proces po zaprtju ni bil več prisoten. Izvorni pregled in neodvisni pregled ugotovitev sta opravila podagenta GPT 6.1 Sol z high reasoning, glavni agent je upravljal GUI in preveril ključne izvorne veje.
- Opazovanje prek dejanskih zaslonov in dostopnostnega drevesa. Drevo je občasno zaostalo za prikazom; take zamude ali neveljavni avtomatizacijski indeksi niso šteti kot napake aplikacije. To ni celovit varnostni pregled ali dokaz uspešnega mobilnega synca.

## Prednostne ugotovitve

### 1 Zaščita potrebuje en jasen in resničen prikaz stanja

**Visoka prednost.** Ob zagonu »Protect connected data« pove, da zaščita povezanega računa ni pripravljena in pošiljanje čaka. Hkrati ponuja »Done« in »Continue locally« ter za posamezne prostore ločene možnosti pregleda zaščite, priprave finančne zaščite in odobritve ključev. Uporabnik težko ugotovi, kateri korak je dejansko potreben.

V Settings kartica »Prepare account recovery« še vedno govori, da je priprava ključev namenjena testiranju in da obstoječa vsebina na strežniku ni E2EE. To je statično besedilo, ki se ne odloča glede na dejansko zaščito konkretnega prostora. Ne dokazuje odsotnosti šifriranja.

**Predlog:** en pregled »Zaščita podatkov« z ločenimi preverjenimi stanji lokalne baze, povezanih prostorov in obnovitvene datoteke. Kadar je potrebna uporabnikova poteza, naj pokaže en glavni naslednji korak. Tehnične možnosti naj bodo v podrobnostih. Zelena oznaka sinhronizacije naj ne nadomešča podatka o pripravljenosti zaščite. Ohrani vsa obstoječa kriptografska varovala.

**Potrditev v HEAD:** `lib/organizer/presentation/recovery/account_crypto_wizard.dart:86`, `lib/l10n/app_en.arb:1750`; `crypto_migration_wizard.dart` veja `canFinish`, naslovna besedila in gumbi (526–589 ter 667–730; pot razrešena v spodnjem indeksu). Besedilo v Settings o lokalnem delu je prav tako brez pogoja na izbrani prostor: `lib/organizer/presentation/settings_page.dart:104`.

### 2 Pri povabilu mora biti obseg pravic viden takoj

**Visoka prednost.** »Invite someone« je kratek obrazec, vendar je privzeti dostop **Full access**, izbira pa je skrita v zaprtem »Access options«. Ta dostop vključuje tudi urejanje in brisanje vsebin, finance ter upravljanje članov. Razlaga posledic je prisotna, vendar glavna izbira ni dovolj vidna.

**Predlog:** prejemnik, prostor in vloga naj bodo vidni brez razpiranja. Npr. »Ana · Urejanje in upravljanje« ter jedrnat opis. O privzeti vlogi se dogovorimo posebej: ohranitev polnega dostopa je produktna odločitev, ki naj bo zavestna in vidna. Dodatna potrjevanja identitetnih kartic niso predlagana.

**Potrditev v HEAD:** `scope_invitation_form.dart:81` uporablja privzeti `member` in napredni prikaz; `sharing_forms.dart:232` izriše zaprt razdelek. `member` se v tej politiki predstavlja kot »Full access«, ne kot omejen običajni član.

### 3 Deljenje naj bo stalno vidno skupaj z občinstvom

**Visoka prednost.** V glavi je deljenje dosegljivo z ikono osebe in plusa. Besedilni »Invite someone« je jasno viden šele pri članih v nastavitvah prostora. Pri odprtem urejevalniku opravila ali dogodka manjka izrecen povzetek prostora in občinstva; pri celozaslonskih Idejah in Priponkah zunanji kontekst izgine. Samo »Save … in the selected space« ni dovolj, če imena izbranega prostora ne vidimo.

**Predlog:** v glavi prostora »Deli« in »Deljeno z …« z neposrednim prehodom do članov; v obrazcih stalna vrstica npr. »Doma → Prenova · vidno članom prostora« ali »Osebno · samo na tej napravi«. Ne zamenjuj dodeljene osebe z ljudmi, ki smejo videti vnos. Oznako prikaži tudi ob priponkah in idejah.

**Potrditev v HEAD:** `collaboration_actions.dart:398` in `:657`, `organizer_editors.dart:528`, `ideas/idea_editor.dart:880`, `shared/shared_documents.dart:165` ter `attachments/attachments_panel.dart:7`. Task/event lahko ohranita zunanjo namizno navigacijo, vendar v samem obrazcu ni izrecnega občinstva. Glavna ikona v trenutnem izvoru že ima tooltip (`organizer_shell.dart:424`); ne trdimo, da v HEAD nima dostopnega imena.

### 4 Neznano stanje ne sme izgledati kot prazni podatki ali neizvedena potrditev

**Srednja prednost, konkretni napaki predstavitve.** V financah skupnega projekta se skupaj pokažeta »Space accounts are not available yet. Connect and refresh project.« in »Create the first financial account in this space.« Prvo pomeni nedostopne oziroma še nepripravljene podatke; drugo uporabnika napoti, kot da računov ni.

Kartica pravil je najprej pozivala k sprejemu. Podrobnosti so pokazale, da so pravila že sprejeta; po vrnitvi je tudi kartica pokazala pravilen status. Ne gre za dokaz izgubljenega soglasja.

**Predlog:** ločena stanja nalaganje, nedostopno, napaka in preverjeno prazno. »Ustvari prvi račun« samo pri potrjeno praznem seznamu. Za neznan status pravil »Preverjanje pravil …«, ne »Potrdi«.

**Potrditev v HEAD:** `finance/shared_finance_workspace.dart:261` in `finance/shared_finance_ledger.dart:277`; `shared/space_settings_page.dart:237` ob `null` ne razlikuje neznanega od nesprejetega statusa, `data/collaboration_moderation.dart:132` ob odprtju podrobnosti osveži stanje.

### 5 Obrazci naj imajo preprost začetek in enoten zaključek

**Srednja prednost.** Urejevalnik opravila poleg naslova hitro pokaže prijavo vsebine, dodeljevanje, načrtovanje, ocenjeno delo, razpoložljiv čas, strošek in časovnik. Ideja takoj odpre obsežno risalno orodjarno; nov vrt velik urejevalnik z merami, sezonami in razporeditvijo. Več obrazcev uporablja za shranjevanje samo disketo, pri drugih so gumbi besedilni.

**Predlog:** osnovno naslov/opomba/datum, dodatne možnosti po potrebi. Ideje naj omogočijo hiter zapis in jasno pot v risanje. Vrt naj začne z imenom ter ponudi razporeditev in sezono kot naslednja koraka. Povsod vidna »Shrani« in »Prekliči« na doslednem mestu; prijava vsebine naj ostane dostopna kot sekundarno dejanje. To so predlogi hierarhije, ne odstranitev funkcij.

### 6 Koledar naj pomeni isto vrsto pogleda v vseh prostorih

**Srednja prednost.** Isti meni »Calendar« v lokalnem osebnem prostoru odpre mesečno mrežo. V pregledanem skupnem projektu pa odpre »Timeline« s seznamom. Prehod je presenetljiv, če uporabnik menja samo prostor.

**Predlog:** enotno poimenovanje in jasno stikalo »Koledar / Časovnica«. Če določena veja omogoča samo seznam, naj to pojasni. Opazovanje velja za nameščeni paket; ločen izvorni pregled te razlike ni bil izveden.

### 7 Obnova in kopije potrebujejo krajši zemljevid možnosti

**Srednja prednost.** Settings vsebuje kopijo z geslom, obnovo, stari nešifrirani JSON, ohranjene datoteke, obnovljeno skupno delo, odpiranje neposlanega dela in obnovitveno datoteko računa. Več možnosti se ponovi tudi na samostojnem zaslonu Backups. »Open unsent work« takoj odpre izbirnik datoteke; iz imena ni jasno, da je to uvoz datoteke, ne pogled trenutne čakalne vrste.

**Predlog:** jasno loči »Varnostna kopija podatkov«, »Obnovitvena datoteka za dostop« in »Reševanje težav«. Običajni uporabnik naj najprej vidi prvi dve; podedovane in diagnostične poti naj ostanejo dosegljive v naprednih možnostih. Preimenuj uvoz v »Odpri datoteko z neposlanim delom«. Besedilo o kopiji naj razloži njen namen, ločeno od aktualnega stanja šifriranja baze.

V pregledanem obrazcu kopije je dobro vidno, da geslo ni shranjeno in brez njega kopije ni mogoče odpreti. Vrstica »This does not add encryption to the active database« opisuje učinek izdelave kopije; sama ne pravi, da je baza nešifrirana.

### 8 Manjše izboljšave preglednosti

- Osebe jasno povejo, da profil nima prijave ali pravic. Vseeno ista družina ikone »oseba +« pomeni tudi povabilo. Ohraniti razlago in dosledno razlikovati »Dodaj osebo« od »Povabi člana«.
- Obvestila »A record was updated« so malo uporabna. Kjer odjemalec že varno pozna vsebino, je smiseln bolj konkreten lokalni prikaz; ne dodajati občutljive vsebine v push ali strežniške dnevnike.
- »About Jivie« v pregledanem paketu ne pokaže različice/gradnje. Kratka različica in možnost kopiranja nenevarnih diagnostičnih podatkov bi olajšali pomoč uporabnikom.
- Pri praznih osebnih financah veliko prostora zasede mesečno načrtovanje in napoved brez podatkov. En začetni korak, nato napredni pregledi, bi bil lažje razumljiv.
- Širok namizni prikaz pogosto ponavlja velik naslov v glavi in vsebini. To je manj pomembno od zgornjih vprašanj deljenja in stanj.

## Kaj je že dobro

- Seznam opravil jasno označi projekt kot »Shared«; nastavitve prostora pokažejo tip, vlogo in status.
- Izbirnik razlikuje lokalni osebni prostor, organizacije in projekte; »Shared with me« ima svoj zavihek.
- Račun jasno prikaže gostitelja, naslov strežnika in razlago zaupanja upravljalcu.
- Prazni Nakupi in Vrt ponudijo jasen naslednji korak; Vrt izrecno označi lokalno nesinhronizirano stanje.
- Lokalni prostor je mogoče ustvariti brez vklopa sinhronizacije. Nastavitve nato jasno razložijo, da se povezava vklopi posebej.
- Povabilo v projekt razloži, da ne daje članstva v nadrejenem prostoru. Obnovitvene in varnostne omejitve niso prikrite, potrebujejo pa boljšo razporeditev.

## Pregledani zasloni in omejitve pokritja

| Področje | Dejansko odprto |
|---|---|
| Zagon in navigacija | Zaščita povezanih podatkov, Nadaljuj lokalno, izbirnik prostorov, Shared with me, meni New, pet korakov vodiča |
| Utrip in obvestila | Skupni projekt in lokalni Utrip, seznam obvestil in filtri; obvestila niso bila označena kot prebrana |
| Opravila | Seznam, obstoječe opravilo in urejevalnik; brez shranjevanja |
| Koledar | Skupna časovnica, obrazec dogodka, lokalna mesečna mreža; brez novega dogodka |
| Ideje | Prazen seznam, novo platno/orodjarna; preklic |
| Projekti | Seznam, podrobnosti, kontekstni meni, priponke; brez arhiviranja, brisanja ali nalaganja |
| Finance | Pregled skupnega projekta in lokalnega osebnega prostora; brez novih računov/vnosov |
| Deljenje | Povabilo, razširjene pravice in možnosti vlog, člani, seznam povabil, pravila sodelovanja; nič poslano ali odobreno |
| Račun | Gostovanje/zaupanje, Moje naprave kot vstopna kartica, potrjen e-naslov, opis brisanja; brez odjave ali sprememb računa |
| Gospodinjstvo | Nov lokalni prostor, Nakupi in obrazec seznama, Vrt in urejevalnik, Osebe in obrazec, lokalne nastavitve |
| Nastavitve | Tema/jezik brez spremembe, opomniki brez spreminjanja, About |
| Kopije in obnova | Backups, obrazec šifrirane kopije, vstopne kartice obnove, ohranjene datoteke, izbirnik datoteke neposlanega dela s preklicem |

To ni pregled vseh možnih dialogov ali vseh stanj obrazcev. Podrobnosti obstoječih nakupovalnih seznamov, vrtnih sezon in posajenih površin niso bile pregledane, ker je nov lokalni prostor prazen. Uvoz/izvoz, dejanska obnova, prijava na novi napravi, nov sprejem povabila, odobritve, razreševanje konfliktov, večuporabniški sync in mobilni prikaz niso bili ponovljeni. Vsebina tabel/dokumentov ni bila ustvarjena samo za razširitev tega pregleda. Zunanji spletni linki niso bili odpirani.

Ob enem odprtju »Finance access« je starejši nameščeni paket pokazal »Too many attempts. Wait a while, then try again.« Dialog je bil zaprt, brez Retry. Iz tega ne sklepamo, da zadnje optimizacije v HEAD ne delujejo; gre za opažanje starega paketa, ne novo diagnozo ali nov obremenitveni test.

## Predlagani vrstni red nadaljevanja

1. Pravilen prikaz zaščite, neznanih stanj in finančnih praznih seznamov.
2. Vidna vloga pri povabilu ter enotna oznaka prostora/občinstva v urejevalnikih.
3. Enotna gumba Shrani/Prekliči ter preprostejši prvi koraki obrazcev in obnove.
4. Po dogovoru kratek raziskovalni pregled treh instanc z aktualnim paketom: lastnik, član in prejemnik novega povabila. To ni bilo izvedeno v tem pregledu.

## Izvorni indeks

Lokacije veljajo za `e2910f9`. Krajša imena v ugotovitvah pomenijo naslednje datoteke, relativno na koren repozitorija:

| Datoteka | Pot |
|---|---|
| crypto_migration_wizard.dart | `lib/organizer/presentation/recovery/crypto_migration_wizard.dart` |
| account_crypto_wizard.dart | `lib/organizer/presentation/recovery/account_crypto_wizard.dart` |
| scope_invitation_form.dart | `lib/organizer/presentation/shared/scope_invitation_form.dart` |
| sharing_forms.dart | `lib/organizer/presentation/shared/sharing_forms.dart` |
| collaboration_actions.dart | `lib/organizer/presentation/shared/collaboration_actions.dart` |
| organizer_editors.dart | `lib/organizer/presentation/organizer_editors.dart` |
| organizer_shell.dart | `lib/organizer/presentation/organizer_shell.dart` |
| idea_editor.dart | `lib/organizer/presentation/ideas/idea_editor.dart` |
| shared_documents.dart | `lib/organizer/presentation/shared/shared_documents.dart` |
| attachments_panel.dart | `lib/organizer/presentation/attachments/attachments_panel.dart` |
| shared_finance_workspace.dart | `lib/organizer/presentation/finance/shared_finance_workspace.dart` |
| shared_finance_ledger.dart | `lib/organizer/presentation/finance/shared_finance_ledger.dart` |
| space_settings_page.dart | `lib/organizer/presentation/shared/space_settings_page.dart` |
| collaboration_moderation.dart | `lib/organizer/data/collaboration_moderation.dart` |

Izvorna preverba je dopolnilo dejanskemu klikanju starejšega paketa, ne nadomestilo GUI preverbe trenutnega paketa.
