# Pregled uporabnosti aktualne Jivie na Macu

23. oktober 2026. Dejanski GUI pregled nove gradnje r14 na izvoru `e2910f9f732ac27d618558c008dc2fe3ab22f709`, s posodobljenim lokalnim testnim strežnikom. Ta pregled nadomesti sklepanje o aktualnem paketu iz [prejšnjega pregleda stare gradnje r12](UX_EXPLORATORY_REVIEW_2026_10_23.md). Stari zapis ostane zgodovinski dokaz.

Osnovni vnosi, urejanje opravila, lokalni finančni izračun, tabela s formulo in prenos majhne priloge so uspeli. Pred objavo pa ostajajo pomembne težave: novo opozorilo celotne sinhronizacije po delu z dokumenti, manjkajoča odprta opravila v iskanju ter zavajajoče razlage zaščite in stanja podatkov. Pregled ni zaključna odobritev za produkcijo. Aplikacijske kode v tej nalogi nismo popravljali.

## Preverjena različica in ohranjeno okolje

- Upravljana je bila samo `/Users/anzenovsak/Applications/Jivie Test Share A.app`, bundle `si.tripar.jivie.e2eetest.sharea20261019`, isti testni račun A in shramba. Različica v paketu ostaja 1.10.1 (31), zato sama številka ne ločuje r12 od r14.
- Nameščeni AOT SHA256 je `abe160febe8552bff267ec4f4fc69b1105f5a71982bfcab99bfe10078bf54397`. Neodvisno je preverjenih 588 izvornih vhodov; med 527 datotekami `lib` sta samo dva QA dodatka za točen lokalni TLS cilj in ločeno Keychain shrambo. `main.dart` je nespremenjen HEAD. Preostalih šest dodatkov ureja Mac identiteto, podpis, sandbox in izolacijo. Starih diagnostičnih runtime dodatkov paket nima.
- Ponovno je uporabljen obstoječi `source-a`. En release build je uspel, podpis je preverjen. Prvi poskus namestitve se je ustavil pred spremembo zaradi TCC omejitve pri branju testnega vsebnika; drugi je zamenjal samo aplikacijski paket. Namestitev ni brisala ali ponastavljala shrambe. Bajtna enakost vault datotek pred in po ni dokazana, ker je TCC preprečil branje. V GUI so ohranjeni račun in obstoječi testni vnosi.
- Docker projekt `jivie-mac-sharing-test-20261019`, HTTPS `127.0.0.1:18811`, ima zdaj 182 preverjenih vtičniških datotek istega HEAD. Zamenjanih je bilo pet datotek in dodana ena; brez spremembe sheme 20, TLS, slik ali volumes. Pred nadgradnjo je narejena konsistentna SQLite kopija. Vseh 220 hashov vsebine strežniških tabel se je čez samo nadgradnjo ohranilo. Poznejši GUI test je namenoma dodal nove testne zapise.
- Aplikacija je tekla približno od 10:54 do 11:20 po lokalnem času. Ob koncu je bila običajno zaprta; PID 74963 ni več prisoten. Druga in tretja testna instanca nista bili odprti. Telefoni, produkcijska aplikacija in produkcijski strežnik niso bili upravljani.
- Izvor, paket in strežnik so pripravljali oziroma preverjali podagenti GPT 6.1 Sol na high reasoning. Glavni agent je upravljal GUI in preveril ključne izvorne ugotovitve. Prejšnjih avtomatiziranih PASS scenarijev nismo ponavljali.

## Kaj je bilo dejansko preklikano

Novi lokalni vnosi so v že obstoječem testnem gospodinjstvu **UX pregled – lokalno 20261023**, ki je označeno kot lokalno in nesinhronizirano. Novi naslovi imajo predpono **UX26**. Starih poslovnih vnosov nismo spreminjali ali brisali.

| Področje | Dejanska dejanja in izid |
| --- | --- |
| Zagon in zaščita | Najprej se pokaže Utrip, nato čarovnik zaščite povezanih podatkov. Prebran pregled prostorov in opozoril; izbrano nadaljevanje lokalno. Brez novih ključev ali potrjevanja migracij. |
| Opravila | Prazen naslov pravilno zavrne shranjevanje. Ustvarjeno `UX26 – opravilo`, brez projekta in roka. Shranjena opomba, ponovno odprtje, sprememba opombe in ponovno odprtje potrjujejo obstojnost spremembe. Opravilo ni bilo zaključeno. |
| Koledar | Ustvarjen `UX26 – dogodek` za 24. oktober z opombo. Vidno v koledarju, prihajajočih dogodkih in Utripu. |
| Projekti | Ustvarjen `UX26 – projekt`, faza `UX26 – priprava` in mejnik `Pregled opravljen`. Podrobnosti projekta pokažejo shranjeno fazo in mejnik. |
| Ideje | Ustvarjena `UX26 – ideja` z navadnim besedilom. Shranjevanje in ponovno odprtje uspeta, vendar je besedilo na temnem platnu skoraj nevidno. |
| Nakupi | Ustvarjen `UX26 – nakupi`, dodani `UX26 jabolka`, količina 2. Označitev kot kupljeno premakne v razdelek Purchased (1); po razširitvi je postavka vidna in označena. |
| Osebe | Ustvarjena izmišljena `UX26 Ana Test` z opombo. Razširjena vrstica pokaže shranjeno opombo. Razlaga, da profil nima prijave ali dostopnih pravic, je jasna. |
| Vrt | Ustvarjen `UX26 – vrt`, mere 5 × 8 m, ena greda `UX26 solata`. Po shranitvi seznam kaže eno območje. Napačna dostava besedila prek avtomatizacije je odpravljena z neposrednim tipkanjem; to ni šteto kot napaka aplikacije. |
| Lokalne finance | Račun `UX26 blagajna`, začetno stanje 100 EUR, knjižen strošek `UX26 malica` 12,34 EUR. Izbrani račun pravilno pokaže napovedano stanje **87,66 EUR**. Skupni pogled kaže neto spremembo −12,34 EUR. |
| Tabele | V skupnem `MAC-SHARE-SPACE` ustvarjena `UX26 tabela`. Po izrecnem prehodu v urejanje A1 = 7 in B1 = `=A1*2` pokažeta 7 in 14. Save and finish, izhod in ponovno odprtje ohranijo vrednosti; seznam kaže revizijo 2. |
| Priloga | Tabeli dodana nova sintetična 56 B datoteka TXT. UI pokaže Available offline. Save a copy ustvari izvoženo datoteko, katere vsebina je bajtno enaka izvirniku. Pot prenosa na drugi klient ni del tega testa. |
| Obstoječi skupni projekt | Odprti projekt `MAC-CHILD-1`, staro opravilo `MAC-SHARED-1` in njegove podrobnosti brez shranjevanja, časovnica, finance ter sinhronizacijski oblaček. Ohranjen stari zapis `A-AFTER-REVOKE-V5`. |
| Deljenje in račun | Pregledani gostovanje, upravljavec, potrjen testni e-naslov, nastavitve prostora, člani in zgodovina povabil. Odprt obrazec Invite someone; prazno pošiljanje pravilno zavrne, pregledani možnosti Full access/View only, nato preklic. Novo povabilo ni bilo poslano. |
| Ostali pregledi | Utrip, obvestila in filter For me, izbira prostorov, Backups, Settings, About, nastavitve opomnikov in razširitev lokalnega prostora, globalno iskanje ter meni New. Brez spremembe dovoljenj, gesel ali nastavitev dostave. |

## Potrjene težave in prednost naslednjega dela

### 1 Celotna sinhronizacija po novih dokumentih zahteva ločeno diagnozo

**Visoka prednost, dejanski nov GUI problem.** Ob 11:17 je oblaček prikazal zadnjo uspešno sinhronizacijo ob 11:07, zadnji poskus ob 11:16, vrste 0/0/0 in napako, da odgovora strežnika ni mogoče varno uporabiti, s priporočilom preverjanja združljivosti vtičnika. Panel izrecno opisuje stanje računa in vseh prostorov, tudi ko je odprt `MAC-CHILD-1`.

Pred tem sta bila ustvarjena tabela in priponka. To je časovna povezava, ne potrjen vzrok. Noben ročni Sync now, ponovno povabilo ali ponovitev starega poslovnega testa ni bila sprožena. Tabela in priloga sta bili v svojem prikazu uporabni, kar ne dokazuje uspeha celotnega sinhronizacijskega cikla.

Izvor daje konkreten kandidat: crypto content pull izloča štiri interne tipe, ne pa `table` in `attachment` (`crypto_business_router.dart:3376`). Običajni sync vsak vrnjen zapis pošlje v `_canonical` (`collaboration_sync_actions.dart:623`), ki tip prebere prek `SharedRecordType.values.byName` (:981), enum pa teh dveh dokumentnih tipov nima (`collaboration_models.dart:38`). Če dokument doseže to pot, lahko lokalna izjema postane splošni `invalid_response`. **Točen throw, cursor in tip zapisa tega GUI poskusa še niso zajeti.**

Prikazano besedilo združi končni kodi `invalid_response` in `redirect_rejected` (`sharing_errors.dart:205`). Full sync lahko ne-Collaboration izjemo pretvori v `invalid_response` (`collaboration_sync_actions.dart:730–732`), zato samo opozorilo ne dokazuje napake strežniškega odgovora ali zastarelega vtičnika.

Naslednji korak naj bo ozek lokalni dokaz te meje na ohranjenem stanju oziroma namenski minimalni kontroli. Pred potrditvijo vzroka ne uvajati splošnega ignoriranja neznanih zapisov, ponastavljanja vrst ali spreminjanja ključev. Besedilo napake mora ločiti lokalno interpretacijo podatkov od dejanske nezdružljivosti strežnika.

### 2 Globalno iskanje izpusti samostojna odprta opravila

**Visoka prednost, GUI in izvor.** Iskanje `UX26` iz skupnega projekta najde sedem novih lokalnih vnosov različnih vrst, ne pa shranjenega nedokončanega opravila brez projekta. Ni omejeno samo na izbrani skupni prostor.

`desktop_search.dart:60–64` zahteva `showCompleted: true`, `all_spaces_rows.dart:221–222` pa to razume kot natančen filter samo zaključenih opravil. Odprta opravila lahko pridejo v rezultat prek podrejenih zapisov projektov ali oseb, samostojna pa izpadejo. Iskanje naj zajame odprta in zaključena opravila. Vrtovi, tabele in finančni računi trenutno niso med indeksiranimi področji; njihova odsotnost v tem iskanju sama ni podatkovna napaka.

### 3 Zaščita podatkov ima nasprotujoče si razlage

**Visoka prednost, GUI in izvor.** Začetni čarovnik govori o nepripravljeni zaščiti, hkrati ponuja Done in Continue locally ter več tehničnih možnosti po prostorih. Settings pri povezanem računu še vedno trdi, da je priprava ključev za testiranje in da obstoječa vsebina na strežniku ni E2EE. To je statično besedilo, ne rezultat preverjanja zaščite trenutnega prostora. Tudi splošna razlaga o delu samo na napravi se pokaže pri izbranem skupnem projektu.

Predlog: en jasen pregled lokalne baze, povezanih prostorov in obnovitvene datoteke, z enim glavnim potrebnim naslednjim korakom. Prikaz naj izhaja iz preverjenega stanja, tehnične možnosti naj bodo v podrobnostih. Obstoječa kriptografska varovala ostanejo. Besedilo ni dokaz dejanske nešifriranosti ali obida zaščite.

Izvor: `crypto_migration_wizard.dart:526–589`, `account_crypto_startup.dart:46–161`, `account_crypto_wizard.dart:86–91`, `app_en.arb:1750`, `settings_page.dart:104`.

### 4 Ideje imajo neberljivo privzeto besedilo v temni temi

**Srednja prednost, GUI in izvor.** Tt vnese temno besedilo `#263238` na temno platno `#22242A`; enako se zgodi v kartičnem predogledu. Vsebina je po ponovnem odprtju prisotna. Privzeta barva mora upoštevati kontrast platna; ohraniti je treba namenoma izbrane barve obstoječih elementov.

Izvor: `idea_editor.dart:273,638`, `idea_canvas.dart:477,615,693`, `jivie_theme.dart:13`, `ideas_page.dart:362–366`.

### 5 Oznake prostora in neznano stanje so zavajajoči

**Srednja prednost, GUI in izvor.** Opravilo brez projekta/roka in nakupovalni seznam v lokalnem gospodinjstvu kažeta Personal. Izvor shranjevanja uporablja izbrani lokalni prostor; napačen je nadomestni naziv v prikazu, ne dokaz prenosa v osebni prostor.

Pri financah skupnega projekta sta hkrati vidna »računi še niso na voljo« in »ustvari prvi račun«. Nedosegljiv seznam ne sme biti predstavljen kot preverjeno prazen. Kartica pravil je najprej pozivala k sprejemu; odprte podrobnosti so pokazale, da so pravila že sprejeta, po vrnitvi pa je kartica popravila status. Soglasja nismo ponovno potrjevali.

Predlog: dosledno ime dejanskega prostora in ločena stanja nalaganje, nedostopno, napaka ter preverjeno prazno. Izvor: `organizer_widgets.dart:186–198`, `shopping_page.dart:239`, `organizer_shell.dart:2524–2549`, `shared_finance_workspace.dart:261`, `shared_finance_ledger.dart:277`, `space_settings_page.dart:237`.

### 6 Samodejni promet ostaja velik

**Meritev za pregled, brez dokazane regresije ali vzročne zveze z napako.** Od 10:54:28 do 11:03:47 je zabeleženih 1172 zahtevkov lokalnemu QA strežniku, medtem ko se je GUI uporabljal v lokalnem gospodinjstvu brez ročnega synca. Začetnemu sklopu 156 sledi osem sklopov po 127 zahtevkov; začetki so približno 69 sekund narazen, sam sklop traja 6–7 sekund. Med njimi je premor.

Tipični sklop ima 18 authority snapshot, 40 scope observations, 34 inventory in 17 records pull zahtevkov ter manjše skupine drugih operacij. To je skladno s preverjanjem približno 60 sekund po zaključku prejšnjega cikla, ne z neprekinjenim HTTP zahtevkom na tri sekunde. Po delu s tabelo promet vsebuje tudi branji/obnovo zaklepa, zato poznejšega okna ni smiselno enačiti s praznim mirovanjem.

Do končnega checkpointa je v štirih zaporednih oknih zabeleženih **2482 odgovorov HTTP 200**, brez dejanskega 429. HTTP status ne izključuje RPC ali lokalne napake in ne potrjuje čistega fullsynca. Metapodatki ne vsebujejo identitete klienta ali parametrov; to ni kontroliran benchmark ali dokaz, da so vsi enako poimenovani zahtevki podvojeni. V trenutnem pregledu povezav je bil opazen klient A, drugi testni klient ni bil odprt.

## Predlogi za enostavnejšo uporabo

1. **Pravice pri povabilu naj bodo vidne takoj.** Obrazec jasno navede prostor in posledice deljenja. Privzeti Full access in izbira View only pa sta v zaprtem Access options. Privzete politike brez dogovora ne spreminjati; prikazati izbrano pravico že v osnovnem delu obrazca.
2. **Vidno občinstvo skozi celoten vnos.** Glavna navigacija dobro kaže izbrani prostor, celozaslonska ideja/tabela pa ga ne ohranja dovolj jasno. Kratka vrstica »Lokalno na tej napravi« ali »Deljeno v …« naj ostane ob obrazcu. Tabele so dosegljive v nastavitvah in organizacijskem pregledu projektov; pot bi bila lahko očitnejša.
3. **Jasen začetek urejanja tabele.** Tudi nova tabela se odpre za ogled, formula bar pa deluje kot navadno vnosno polje. Vnos pred pridobitvijo urejanja nima učinka. Po pencil prehodu računanje in shranjevanje delujeta. Potreben je jasen gumb »Uredi tabelo« in oznaka trenutnega načina.
4. **Finančne mere naj bodo poimenovane dosledno.** All accounts kaže neto spremembo, izbrani račun saldo z začetnim stanjem. Opozorilo »ni začetnega stanja« je ob vidnem računu s 100 EUR dvoumno. Vrstica računa s 100 EUR predstavlja začetno, ne tekoče stanje. Izračun 87,66 EUR je pravilen.
5. **Lažji osnovni obrazci in dosledno shranjevanje.** Lokalno opravilo začne preprosteje kot skupno; vrt in ideja hitro pokažeta obsežen urejevalnik. Napredne možnosti je smiselno postopno razkriti. Disketa brez stalnega besedila in dvojno shranjevanje elementa ter dokumenta zahtevata več učenja.
6. **Koledar naj ima dosledno ime pogleda.** Lokalni prostor pokaže mesečno mrežo; skupni projekt pod istim menijem Calendar odpre Timeline. Pomagalo bi jasno stikalo oziroma pojasnilo vrste pogleda.
7. **Ločiti kopijo podatkov od obnovitvene datoteke za dostop.** Settings združi kopije, obnovo, podedovani nešifrirani JSON, ohranjene datoteke, obnovljeno skupno delo, neposlano delo in pripravo obnovitve računa. Običajni poti naj bosta spredaj, reševanje težav v dodatnih možnostih. V GUI nismo ustvarjali ali obnavljali uporabniške varnostne kopije.
8. **Bolj uporabna obvestila in podatek o gradnji.** Staro obvestilo »A record was updated« pove premalo. About nima različice/gradnje, zato bi bila pomoč uporabniku težja. Diagnostični podatki naj bodo brez ključev in vsebine.

Dobro delujejo poimenovanje lokalnega prostora v nastavitvah, jasen opis upravljavca gostovanja, opozorilo, da oseba ni uporabniški račun, razlaga obsega povabila, validacija praznega naslova in razločevanje lokalnih od sinhroniziranih nastavitev opomnikov. Te prednosti je smiselno ohraniti.

## Meje in ohranjeni dokazi

To je ena namizna raziskovalna seja v angleškem vmesniku in temni temi. Ni dokaz celotne mobilne sinhronizacije, ponovne prijave, obnove ključev, nadgradnje s starimi podatki ali večuporabniškega deljenja. Nova pravila niso bila potrjena, nova povabila niso bila poslana, dostop ni bil podeljen/odvzet. Uspešne stare poslovne teste nismo ponavljali. Za opaženo novo sync napako ni bilo dodatnega ročno sproženega poskusa, diagnostičnega kroga, gradnje ali spremembe kode; običajnega samodejnega prometa med odprto aplikacijo to ne izključuje.

Dostopnostno drevo je pogosto zaostalo za sliko. Prve neuspele vnose pred načinom urejanja tabele in težave dostave besedila prek avtomatizacije ločujemo od napak aplikacije. Pri izvozu priloge je sistemski izbirnik dodal novo ime ob starega, vendar je nastala ena nova 56 B datoteka z enako vsebino; to ni razglašeno za napako izvoza.

Zunanji OS zajem je zaključil po 5,982 sekunde zaradi 2 MiB skupne meje prebranega toka in izhodnih metapodatkov. Končna datoteka z dovoljenimi metapodatki meri 1198 B; števec 911 B v zaključnem zapisu ne vključuje samega zaključnega zapisa. Poznejše sync napake zato ni zajel. Paket nima trajnega podrobnega Dart sync loggerja. Njegova odsotnost ali HTTP 200 ne pomenita odsotnosti napak.

- Izvorna pojasnila in povezave: `build/qa/mac-exploratory-latest-20261023/source-corroboration.md`.
- Strežniška nadgradnja: `build/qa/mac-exploratory-latest-20261023/server/upgrade-result.json`.
- Promet in časovna korelacija: `metadata-startup-local-crud.json`, `request-pattern-local-crud-analysis.json`, `metadata-latest-gui-final-pre-settings.json`, `metadata-latest-cloud-warning-final.json`, `metadata-gui-closed.json`, `cloud-warning-correlation.json` v podmapi `server/` iste dokazne mape.
- Priloga: `attachment-export-check.json`; SHA256 izvirnika in izvoza `4df3169560382a2ac477e77bcfa2fd1f7db54b257067b32ad94a850b00e9b8d7`.
- Paket in namestitev: zasebna `~/Library/Application Support/JivieLocalTest/share-20261019/candidate-a-r14/`; `artifact-evidence.json` SHA256 `fe16b5cc77721968eb564fa516520d153a38f2dfcfcc96dd4305df62029abed8`, namestitveni dokaz SHA256 `b89e5568b491d265ba4dada2d4fe48de6960eb9c0f81fd852db1f6e18a732289`.

Po pregledu so odstranjeni samo štirje obnovljivi predpomnilniki te gradnje, skupaj 1.664.277.212 B. Končni paketi, izvor, prejšnja gradnja, podatki in dokazi ostajajo; hash nameščenega AOT in dokaznega manifesta se ni spremenil. Zasebni `candidate-a-r14/cache-cleanup-manifest.json` ima SHA256 `17b02e8948c076be14550cad4ce32fbb5f176985b52a910d72310eb99fe3f2af`. Izvorni in strežniški podagent sta neodvisno pregledala končne trditve tega poročila.

Vsi novi testni vnosi in stara testna stanja ostanejo za nadaljevanje. Najprej je smiselno lokalno diagnosticirati novo opozorilo celotne sinhronizacije, vključno z izvorno možnostjo pri dokumentih, ter odpraviti napako iskanja; nato uskladiti besedila in vidnost deljenja. Obnovitev že uspešnih scenarijev ni začetni korak tega nadaljevanja.
