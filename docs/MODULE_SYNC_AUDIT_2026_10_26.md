# Pregled modulov in koordinacije osveževanja — 26. oktober 2026

## Obseg in vrstni red

Izhodišče: `cfb10fc` (produktna koda `65373c0`). Uporabnik naroča najprej
popis vseh modulov, nato pregled modul za modulom s podagenti GPT‑6.1 Sol/high.
Popis spodaj je pripravljen pred razdelitvijo pregleda. Pregled je izvoren:
brez GUI, novih gradenj, testov, HTTP zahtevkov, Dockerja, telefonov ali
produkcije. Ni implementacija optimizacij ali brisanje kode.

Navigacijska osnova: `organizer_navigation.dart` (`OrganizerArea` in štiri
`OrganizerDestination`), `organizer_shell.dart`, `shared/sharing_workspace.dart`
(`SharingView`), namizni in skupni pregledi. Modul je funkcionalna celota,
ne nujno ena datoteka ali gumb; finance in deljenje imajo več ločenih poti.
Lokalni, povezani osebni in skupni podatki se preverjajo ločeno.

## 1. Popis modulov pred pregledom

Poti v tabeli so relativne na `lib/organizer/`.

| ID | Modul in vključene funkcije | Glavne vstopne/podatkovne datoteke | Pregled |
|---|---|---|---|
| M01 | Prostori: osebno, gospodinjstvo, organizacija; izbor, ustvarjanje, arhiv, izbris, lokalno→povezano | `presentation/shared/{space_picker,create_space_dialog,organization_workspace,local_space_settings,scope_lifecycle_menu}.dart`; `data/collaboration_{scope_lifecycle,local_space_publication,private_actions}.dart` | mešano/namensko |
| M02 | Projekti: seznam, podrobnosti, faze, načrtovanje/kapaciteta, pripadnost prostoru | `presentation/projects_page.dart`, `planning/project_*.dart`; `data/collaboration_record_actions.dart`, `collaboration_project_sharing.dart` | usklajeno + P3 |
| M03 | Opravila: seznam, urejanje, dodelitev, časovnik, strošek opravila, konflikt | `presentation/{today_page,organizer_editors}.dart`, `shared/collaboration_actions.dart`, `inbox/visible_task_target_view.dart`; `data/collaboration_{record_actions,task_cost_actions}.dart` | mešano; P3/P4 |
| M04 | Koledar in dogodki: časovnica, mesec, filtriranje, dodajanje/urejanje | `presentation/calendar_page.dart`, `planning/{shared_agenda_page,agenda_month_calendar,project_calendar}.dart`; `data/collaboration_event_actions.dart` | usklajeno + P3 |
| M05 | Nakupi: seznami, elementi, kljukice, brisanje celote | `presentation/shopping_page.dart`, `collection_actions.dart`; `data/collaboration_record_actions.dart` | usklajeno + P3 |
| M06 | Finance: računi, stroški/prilivi, prenosi, saldo, pregled prostora/projekta, pravice | `presentation/finance_page.dart`, `finance/shared_finance_*.dart`; `data/collaboration_finance_{actions,sync,account_choices}.dart` | mešano; P4 |
| M07 | Finančno načrtovanje: proračun, planirani vnosi, ponavljanje | `presentation/finance/finance_plan*.dart`; `data/collaboration_finance_actions.dart` | usklajeno |
| M08 | Povezana plačila, terjatve in povezave med prostori | `presentation/finance/{linked_payment_forms,linked_payments_section}.dart`; `state/linked_payments_provider.dart`; `data/{linked_payments_repository,collaboration_linked_payments}.dart` | usklajeno/namensko |
| M09 | Vrt: načrt, grede, sezone, kulture in prikazi | `presentation/garden/*`; `state/garden_provider.dart`; `data/{garden_repository,collaboration_garden_actions}.dart` | usklajeno; lok. P8 |
| M10 | Idejnik: table, risanje, fotografije/datoteke, konflikt | `presentation/ideas/*`; `state/idea_provider.dart`; `data/{idea_repository,collaboration_idea_actions}.dart` | mešano; P2 |
| M11 | Osebe in kontakti: seznam, povezave z dodelitvami | `presentation/people/people_page.dart`; `data/collaboration_person_actions.dart` | usklajeno |
| M12 | Preglednice: seznam, dokument, urejevalnik, lease, osnutek | `presentation/tables/*`; `data/collaboration_document_actions.dart`, `e2ee/crypto_business_documents.dart` | mešano; P1/P2 |
| M13 | Priloge: seznam, upload/download, izvoz, brisanje | `presentation/attachments/*`, `shared/shared_documents.dart`; `data/collaboration_document_actions.dart` | mešano; P1/P2 |
| M14 | Utrip, vsi prostori, namizno iskanje/pregledi | `presentation/planning/utrip_overview.dart`, `all_spaces/*`, `desktop/*`; `state/all_spaces_provider.dart` | mešano; P3 |
| M15 | Deljenje, članstvo, povabila, vloge in pravice, potrditev dostopa | `presentation/shared/{space_settings_page,sharing_members,scope_invitation_form,invitation_wizard,sharing_pending_invitations}.dart`; `data/collaboration_{email_invitations,organization_access,project_sharing}.dart` | mešano; P6 |
| M16 | Obvestila in opomniki: inbox, prebrano, lokalni/oddaljeni opomniki, push | `presentation/inbox/*`, `planning/remote_push_device_settings.dart`; `state/inbox_*`; `data/collaboration_notification_*.dart`, `collaboration_remote_push_*.dart`; `platform/remote_push/*` | mešano; P5 |
| M17 | Račun in strežnik: prijava, email, seja, geslo, povezovanje, izbris računa | `presentation/shared/sharing_{account_page,auth}.dart`, `onboarding/*`; `data/collaboration_{account_actions,account_recovery,account_deletion,session_renewal}.dart` | namensko; P7 |
| M18 | Zaščita/E2EE: čarovnik, ključi, naprave, priprava/migracija, obnova dostopa | `presentation/recovery/*`; `state/account_crypto_provider.dart`; `data/e2ee/*` | namensko |
| M19 | Kopije, uvoz/izvoz, obnova lokalne namestitve in podatkov | `presentation/backup/*`; `state/portable_backup_provider.dart`; `data/{portable_backup_repository,collaboration_backup_actions}.dart` | lokalno/namensko |
| M20 | Nastavitve aplikacije in navigacija: jezik, tema, prikazi, zadnji prostor | `presentation/settings_page.dart`, `navigation/*`; `state/{app_preferences_provider,local_spaces_provider}.dart`; `lib/storage/*` | lokalno |
| M21 | Prijava vsebin in pravila sodelovanja | `presentation/shared/{content_moderation,content_actions_menu,hosting_disclosure}.dart`; `data/collaboration_moderation.dart` | namensko |
| X01 | Skupna infrastruktura: koordinator, urnik, status, konfliktnost, delte in osveževanje projekcij | `state/{collaboration_provider,collaboration_sync_schedule,application_sync_activity}.dart`; `data/{account_work_coordinator,collaboration_sync_actions,collaboration_account_changes,authority_reuse_controller}.dart`; `shared/sharing_status*.dart`, `sharing_sync_conflicts.dart` | pregledano; meje spodaj |

## 2. Merila za pregled vsakega modula

Za vsak ID zabeležimo sprožilce ob odprtju, shranitvi, vrnitvi v ospredje,
časovnikih in ročnem osveževanju; nato sled UI → provider → repository →
transport. Ločimo tri stvari:

1. **Koordinacija zahtevkov** (`AccountWorkCoordinator`, queue/single-flight)
   preprečuje prekrivanje; sama še ne pomeni, da ni nepotrebnih klicev.
2. **Koordinacija sprememb** (`account.changes`, selekcija domen/prostorov)
   določa, kaj se je spremenilo; neposredno branje lahko to obide tudi znotraj
   skupne vrste zahtevkov.
3. **Ponovna uporaba preverjenih pravic** zmanjšuje authority klice, vendar ne
   odpravi vsebinskih branj, lease ali obveznih preverjanj pred zapisom.

Statusi: **lokalno**, **usklajeno po viru**, **mešano**, **neposredno namensko**,
**kandidat za optimizacijo**, **nepotrjeno**. Noben statični status ne pomeni
izmerjene latence ali zagotovila nič odvečnih HTTP. Varnostna preverjanja,
podpisane zahteve, receipts, obnova in združljivost niso samodejno odvečni.

## 3. Rezultati

### X01 — skupna infrastruktura (glavni pregled)

**Potrjeno po viru, ni meritev:** `CollaborationController` ima en foreground
časovnik (`state/collaboration_provider.dart:178–214`), običajni interval30s
in backoff15/30/60s (`collaboration_sync_schedule.dart:68–84`). Ozadje prekine
časovnik in razveljavi ponovno uporabo pravic; zagon/vrnitev in dejanski lokalni
zapisi sprožijo oziroma ohranijo skupno zahtevo za delo (`:272–307`).
Sekundni prikazni časovniki niso sami po sebi sekundni HTTP.

`syncNow` združuje sočasne zahteve (`data/collaboration_sync_actions.dart:100–129`).
`_coordinateSyncPass` bere **lokalno** podporo strežnika in nato
`account.changes` (`:201–244`). Če ni oddaljene spremembe, lokalnega outboxa ali
obnovitvenega dela, vrne odgovor brez polne sinhronizacije (`:449–465`).
Izbrani prostori/domene omejijo content/finance delo (`:814–839`); kurzor se
potrdi šele po uspešnem preverjenem delu (`:491–505`). Lokalni pending work je
vključen neodvisno od strežniškega namiga. Starejši strežnik, reset/invalid
cursor in obnova plačil lahko upravičeno uporabijo širšo pot (`:215–278`,
`:434–489`); to ni dokaz podvojene običajne sinhronizacije.

Vsi klici prek `CollaborationRepository.transport` uporabljajo
`CoordinatedCollaborationTransport` (`collaboration_repository.dart:186–190`).
`AccountWorkCoordinator` omejuje dovoljena branja na2 sočasni/64 čakajočih in
512KiB vhodnih parametrov. Podpisani zapisi in neznane operacije se po
preverjanju lastnika/cooldown pošljejo neposredno, ker ne smejo podaljšati
razmika med zadnjim dovoljenjem in zapisom. **To ni globalni cache.** Združitev
sočasnih klicev velja samo za `capabilities`/`account.changes`, isto eksplicitno
opravilo, identiteto in generacijo v5s; po zaključku odgovor ni shranjen za
poljubne naslednje zaslone (`account_work_coordinator.dart:344–413`).

Ponovna uporaba dokazov pravic je druga plast. Namigi access razveljavijo
prizadeto drevo; account/reset/metadata širše stanje, navadna vsebina pa ne
(`collaboration_sync_actions.dart:359–380`). Vsak porabnik še preverja podpis
in vezavo. Ta plast ne pomeni ponovne uporabe že prenesene vsebine.

**Meje in preostali kandidati:**

- Granularnost namiga je prostor+domena, ne posamezen UI modul: `content`
  vključuje projekte/opravila/dogodke/ideje/vrt itd.; `documents` se v odjemalcu
  vključi tudi v content (`collaboration_account_changes.dart:31–36`). Dejanski
  prenosi imajo kurzorje, zato to ni samodejno ponoven prenos vseh zapisov,
  lahko pa aktivira več preverjanj ene domene.
- `refreshLocal(scopeIds:…)` ohrani vsebino nespremenjenih prostorov, vendar
  še vedno za vsak nerevoked prostor bere lokalno finančno politiko, stanje,
  izbire računov in člane (`collaboration_repository.dart:673–701`). To je
  kandidat za zmanjšanje lokalnega SQL/rebuild dela, **ne dodaten HTTP**.
  Nadaljnji `personalChanged` je že omejen na dejansko spremenjene domene
  (`:961–968`), zato stari splošni opis »vsak signal osveži vse« ne velja več.
- Strežniški `NativeAccountChanges.php:97–146` uporablja metapodatke in
  sekvence, ne celotnega inventarja poslovnih zapisov. Odgovor vrne samo
  spremenjene domene, vendar podpisani cursor še vsebuje žige vseh prostorov
  (`:177–190`); cena/velikost zato ni konstantna glede na število prostorov.
  To je meja zasnove, ne izmerjeno ozko grlo ali razlog za takojšen nov protokol.

### M01–M21 — pregled vsakega modula

Poti so relativne na `lib/organizer/`; navedene vrstice veljajo za zgornje
izhodišče. »Skupna pot« pomeni lokalni zapis/outbox → koordinator → izbor po
`account.changes` → preverjen prenos. Ne pomeni, da je vsak pomožni klic
odvisen od namiga spremembe. Vsi moduli imajo skupni foreground/resume urnik;
spodaj so posebej navedene izjeme, uporabniški in prikazni časovniki.

| ID | Odprtje/branje | Shranjevanje in osveževanje | Sklep in dokaz |
|---|---|---|---|
| M01 Prostori | Izbirnik/izbor uporablja lokalne projekcije. Izbor shrani lokalni metapodatek. | Povezano ustvarjanje, arhiv, izbris in objava so izrecni strežniški postopki; po potrebi sledita projekcija in skupni sync. | **Mešano, namensko.** `presentation/shared/space_picker.dart:56`, `data/collaboration_account_actions.dart:679,753,784`, `collaboration_scope_lifecycle.dart:12`. Življenjskega cikla prostora ne čakamo do naslednjega 30s preverjanja. |
| M02 Projekti | Seznam, faze in kapaciteta iz lokalnih projekcij; sekundni prikaz kapacitete je lokalni izračun. | Običajni zapisi uporabljajo skupno content pot; ustvarjanje podprostora je M01. | **Usklajeno; izjema predogled P3.** `presentation/projects_page.dart:59`, `planning/project_capacity_panel.dart:39`, `data/collaboration_record_actions.dart:852`. |
| M03 Opravila | Običajni seznam/urejevalnik iz lokalnega stanja; skupni predogled dodatno preveri strežnik. Strošek opravi pripravo finančnih izbir. | Skupni outbox; opravilo+strošek se zapišeta skupaj. Sekundni prikaz časovnika ne pošilja HTTP. | **Mešano, P3/P4.** `presentation/inbox/visible_task_target_view.dart:134`, `shared/collaboration_actions.dart:725,805`, `data/collaboration_task_cost_actions.dart:4`. |
| M04 Koledar/dogodki | Menjava meseca/filtra lokalna; seznam iz projekcije. | Dogodki uporabljajo skupni content outbox, brez lastnega omrežnega časovnika. | **Usklajeno; izjema skupni predogled P3.** `presentation/planning/shared_agenda_page.dart`, `data/collaboration_event_actions.dart:4`, `state/collaboration_provider.dart:1225`. |
| M05 Nakupi | Seznami in kljukice iz lokalnih projekcij. | Spremembe in brisanje celote zapisujejo outbox; ni lastnega preverjanja strežnika. | **Usklajeno; izjema skupni predogled P3.** `presentation/shopping_page.dart:53`, `data/collaboration_record_actions.dart:683`. Več tombstone zapisov pri brisanju celote je lahko potrebno delo. |
| M06 Finance | Pregled/saldo/filtri lokalni; projektni pregled ob mount dodatno pripravi izbire računov. Urejevalnik ima ločeno pripravo izbir. | Lokalni finančni outbox; koordinator izbere finance domene in potrebne odvisnosti. Znotraj kombiniranega branja že obstaja omejena ponovna uporaba materializiranih podatkov. | **Mešano, P4.** `presentation/finance/shared_finance_workspace.dart:23,59`, `shared_finance_actions.dart:436`, `data/collaboration_finance_sync.dart:185,354,675`. Upravljanje dovoljenj/revizija sta namenska sveža postopka. |
| M07 Finančni načrti/ponovitve | Pregled lokalen; enkrat na prikazani mesec preveri/materializira ponovitve. | Nastali zapisi gredo v finančni outbox. Ponovno odprtje lahko ponovi lokalni pregled meseca, ne nujno HTTP. | **Usklajeno.** `presentation/finance/finance_planning_panel.dart:318`, `data/collaboration_finance_actions.dart:958`. Materializacija ni brezpredmetno osveževanje: lahko ustvarja dejanske zapise. |
| M08 Povezana plačila | Provider bere SQLite in posluša domeno plačil; ročni refresh namensko bere strežnik. | Trajne namere in receipt nadaljevanje; isto namero že združuje v en tekoči prenos. Koordinator nadaljuje po uspešnem syncu. | **Usklajeno + namenski ukazi.** `state/linked_payments_provider.dart:37`, `data/linked_payments_repository.dart:57,151,229`, `collaboration_sync_actions.dart:1378`. Ponovljeni logični policy klic je že delno pokrit z reuse; prihranka HTTP še ne trdimo. |
| M09 Vrt | Lokalno branje; skupni storage filtrira spremembe po podpisu vsebine vrta. | Sezone/kulture spreminjajo zapis vrta; skupni outbox. Lasten HTTP časovnik ni najden. | **Usklajeno; lokalni kandidat P8.** `data/collaboration_garden_actions.dart:43,89,115`, `garden_repository.dart:57,148`, `state/garden_provider.dart:10`. |
| M10 Idejnik in slike | Table iz lokalnega storage, filtrirane po podpisu vsebine. 250ms debounce shranjuje lokalni osnutek. Slike preveri po hashu; manjkajoče prenese. | Table skupni content outbox; prenos medijev namenska pot, tudi prefetch ob syncu. | **Mešano, P2.** `data/collaboration_idea_actions.dart:99,288,356,378`, `presentation/ideas/idea_editor.dart:385`, `data/collaboration_sync_actions.dart:1218`. Sočasna prenosa iste slike nista izmerjena; ni izrecne per-asset single-flight mape. |
| M11 Osebe/kontakti | Lokalni seznami in povezave z opravili. To niso strežniški računi članov. | Ustvarjanje/urejanje/arhiv uporablja skupni content outbox. | **Usklajeno.** `presentation/people/people_page.dart:30,95`, `data/collaboration_person_actions.dart:4`. Na običajnem odprtju ni najden poseben HTTP. |
| M12 Preglednice | Lokalni predogled, nato sveže list/get; posluša skupni tok dokumentov prostora. | Save uporabi vrnjeni dokument. Edit pridobi lease; ob urejanju ga obnavlja na25s. Sekundni access clock je lokalni. | **Mešano, P1/P2.** `presentation/tables/spreadsheet_tables_page.dart:57,308,383,443,585`, `data/collaboration_document_actions.dart:407,646`, `e2ee/crypto_business_documents.dart:635`. Viewer lease samo prebere, ga ne pridobi. |
| M13 Priloge | Lokalni predogled, nato svež seznam; isti scope-wide dokumentni signal. | Upload/delete sta namenska; sledita list in morebiten čakajoči refresh. Prenos vsebine po kosih. | **Mešano, P1/P2.** `presentation/attachments/attachments_panel.dart:39,103,179,237,345`, `data/collaboration_document_actions.dart:984,1049`. Ni lastnega periodičnega HTTP. |
| M14 Utrip/Vsi/iskanje | Agregacija/filtriranje/iskanje lokalno, brez HTTP za vsako črko ali vrstico. | Odpiranje skupnega zapisa preide v poseben task ali generični notification predogled; spreminjanje se vrne v pravi izvorni modul. | **Mešano pri odprtju, P3.** `state/all_spaces_provider.dart:12`, `presentation/desktop/desktop_search.dart:31`, `all_spaces/all_spaces_rows.dart:573`. |
| M15 Članstvo/povabila | Mount, resume in signal zaključka lahko ponovno naložijo člane/povabila; dogodek omejen na5s in trenutni zaslon. | Send/accept/grant/revoke ostajajo namenski podpisani postopki. Samodejno dokončanje dostopa se vključuje v foreground sync. | **Mešano, P6.** `presentation/shared/sharing_members.dart:108,125,177`, `sharing_pending_invitations.dart:98,148`. Seznam ni v celoti vezan na spremembo access/invitation generacije. |
| M16 Obvestila/opomniki/push | Inbox iz lokalnega stanja; strežniški inbox namig aktivira skupni sync. | Obdelava ukazov je med dvema branjem inboxa; zatem osveži nastavitve/opomnike vseh izbranih prostorov. Push registracija je namenski lifecycle postopek. | **Mešano, P5.** `data/collaboration_sync_actions.dart:1277`, `collaboration_notification_sync.dart:175,384,449`. Lokalnih opomnikov ne štejemo kot HTTP polling. |
| M17 Račun/prijava/email | Status/prijava/povezovanje so namenske neposredne operacije. | Potrditev emaila že prebere accountStatus, UI nato zahteva še en status. | **Namensko + potrjena podvojitev P7.** `data/collaboration_account_recovery.dart:78`, `presentation/onboarding/account_email_card.dart:89`. Avtentikacijskih ukazov ne odlagamo na časovnik sprememb. |
| M18 Zaščita/E2EE | Stanje priprave, naprave in dokazi imajo ločene varnostne postopke. | Izrecna priprava/migracija/obnova ter nadaljevanje trajnega dela uporabljajo preverjene meje in receipts. | **Namensko, glej dopolnitev spodaj.** Ni utemeljitve za prisilno zamenjavo teh postopkov z navadnim branjem delte. |
| M19 Kopije/uvoz/obnova | Izbira datotek, izvoz, pregled in obnova kopij so lokalni; nadaljevanje obnovljenega povezanega dela je namensko. | Obnova spremeni trajno stanje, zato ohrani posebne kontrole in nadaljevanje. | **Lokalno/namensko, glej dopolnitev spodaj.** Ni običajen zaslon za periodični sync. |
| M20 Nastavitve/navigacija | Tema, jezik, izbran prostor in osnovni prikazi so lokalni. | Lokalno shranjevanje; povezave v nastavitvah delegirajo račun/obnovo/opomnike drugim modulom. | **Lokalno.** `presentation/settings_page.dart:86,140,168`, `state/app_preferences_provider.dart:7`. Ni lastnega HTTP časovnika. |
| M21 Moderacija/pravila | Namenski pregled pravil/prijav; ne običajno vsebinsko polling branje. | Sprejem pravil in prijava vsebine sta izrecna strežniška ukaza. | **Namensko, glej dopolnitev spodaj.** Preverjanja veljavnih pravil niso samodejno odvečna. |

### Dopolnitev M15–M19 in M21: kaj je namenoma zunaj običajne delte

- **M15:** sprejem povabila uporablja ohranjen poskus/grant, nato refreshLocal
  in syncNow (`data/collaboration_email_invitations.dart:493–649`). Foreground
  approval ima lastne izrecne Send/accept pogoje, ni slepo odobravanje; ob
  uspešnem dokončanju lahko prebere omejen prikazni inbox
  (`platform/remote_push/foreground_invitation_approval_coordinator.dart:125`,
  `data/collaboration_notification_routing.dart:5–103`). Prikaz članov mora
  poleg podpisanega rosterja upoštevati sveže acceptedAccountIds; pripravljeno
  povabilo še ni sprejet dostop (`data/e2ee/session_crypto_access.dart:1914`).
  Zato P6 ne pomeni odstraniti vsega metadata branja iz prikaza članov.
- **M16:** lokalni notification coordinator ima minutni timer za lokalno
  načrtovanje (`platform/notification_coordinator.dart:65,125`), ne server
  polling. Push registracija/resume uporablja trajne namere in 60s state
  guard (`data/collaboration_remote_push_actions.dart:70–113,116–230`);
  prejet veljaven push sproži skupni sync (`:340`). Dejanska OS dostava ni
  bila preizkušena. Odpiranje pravega inbox cilja mora preveriti njegov
  trenutni dostop (`collaboration_notification_routing.dart:264–319`).
- **M17:** obnova seje je že single-flight po epochu, pred pragom zadnjih
  sedmih dni je no-op (`data/collaboration_session_renewal.dart:20–47`).
  Prijava po shranjeni seji uporabi skupni sync
  (`collaboration_account_actions.dart:317–335,411`). Reset gesla in izbris
  računa/receipt nadaljevanje imata namenske korake tudi brez veljavne seje
  (`collaboration_account_recovery.dart:83`, `collaboration_account_deletion.dart:167`).
- **M18:** account preview provider je vezan na partition/device in se ne
  ustvarja znova ob vsakem syncu (`state/account_crypto_provider.dart:6–18`).
  To je cache workflow objekta, ne splošen cache statusa. Čarovnik bere status
  ob začetku in po izrecnih akcijah; `AccountCryptoV2Workflow.status` uporablja
  account work job (`data/e2ee/account_crypto_v2_workflow.dart:38`). Seznam
  naprav začne z lokalnim preverjenim directoryjem
  (`presentation/recovery/account_devices_page.dart:25`). Migracija ima
  eksplicitne migration jobs (`data/e2ee/crypto_migration_coordinator.dart:179,275,383`).
  Obnova pred potrditvijo znova preveri evidenco
  (`crypto_restore_reconciler.dart:139,1381`); tega ni dovoljeno razglasiti
  za odvečno samo zato, ker je uporabnik prej videl preview. V vodilnih UI
  poteh ni najden lastni polling; vseh globokih recovery vej nismo formalno dokazali.
- **M19:** `PortableBackupRepository.export/inspect/restore/list`
  (`data/portable_backup_repository.dart:189,570,903,929`) uporablja SQL,
  šifriranje in datoteke, brez transporta. Šele izrecni Resume obnovljenega
  povezanega dela (`:1069`, `collaboration_backup_actions.dart:6–31,65–147`)
  preveri izvorni account/server/partition, opravi sync in potrebne finance
  kontrole ter pod lease obnovi trajne operacije. To ni avtomatski upload po
  vsakem importu in ne razlog za odstranitev svežih kontrol.
- **M21:** sprejeta lokalna policy lahko preskoči ponoven dialog
  (`presentation/shared/content_moderation.dart:20`). Izrecni pregled/sprejem
  pravil, report preview in report submit imajo capabilities/policyStatus,
  previewHash in requestId meje (`data/collaboration_moderation.dart:88–155,170–310`).
  Preverjanje pred uploadom ni lastni periodični polling (`:361–378`). Ožja
  ponovna uporaba capabilities znotraj istega postopka je morebitna nadaljnja
  raziskava, ne dokazana odvečna kontrola ali dovoljenje za pošiljanje dokazov
  na podlagi starega soglasja.

## 4. Konkretne najdbe in predlagan vrstni red

### P1 — dokumentni signal in ponovno branje lastnega rezultata (najprej)

**Potrjena pot v kodi; pogostost še ni izmerjena.**
`data/collaboration_database.dart:80–93` objavlja dokumentno spremembo za
partition+scope, brez tipa/ID/targeta. `e2ee/crypto_business_router.dart:4481`
jo pošlje ob dejanski spremembi proof hasha preglednice/priloge. Aktivni
seznam in detajl preglednice (kadar ni v urejanju/z neshranjenim osnutkom)
ter seznami prilog potem berejo omrežno. Sprememba
priloge enega zapisa lahko tako osveži nepovezan dokument istega prostora.

Če lastni pull objavi ta signal med `_reading`, preglednice nastavijo
`_readAgain` in v finally ponovno naložijo (`spreadsheet_tables_page.dart:72,113,320,376`).
Priloge uporabljajo podoben `_refreshPending`; upload/delete ima še izrecni
post-refresh (`attachments_panel.dart:44,152,179,237,345`). To dokazuje
**pogoj za dodatno branje**, ne neskončne zanke ali dvojnega HTTP pri vsakem
odprtju. Skrit seznam preglednic že odloži delo do vrnitve.

Predlog: signal naj nosi preverjene spremenjene dokumente/cilje oziroma
njihovo generacijo. Branje označi generacijo, ki jo je že vključilo v svoj
rezultat; samo novejši dogodek zahteva naslednje branje. Ohrani ločeno
razveljavitev pravic/izbrisa in vse osnutke. Ne odstrani vseh trailing refreshov.

### P2 — prenos datoteke po kosih ponavlja pripravo vsebine

`collaboration_document_actions.dart:995` za vsak plaintext kos kliče
`attachments.get`; adapter `crypto_business_documents.dart:757–760,795–810`
vsakič vstopi v `pullVerified(content)` in odpre celoten descriptor. Slike idej
imajo podobno pot (`collaboration_idea_actions.dart:112`,
`crypto_business_documents.dart:1059`). Materializirano reuse je trenutno
omejeno na finance (`crypto_business_router.dart:1593–1608`).

**To ne pomeni ponovnega prenosa cele datoteke za vsak kos:**
`crypto_document_blob.dart:360–381` ima cache plaintexta po descriptor hashu;
na zadetku kopira že razpoložljivo vsebino. Ostanejo ponovljeni vstopi v
preverjanje/pull in lahko kopiranje cele vsebine.

Predlog: omejena seja prenosa za isti preverjeni descriptor in identiteto,
iz katere se režejo kosi; prekini jo ob ustrezni spremembi pravic/descriptorja/
lifecycle. Ne globalno podaljševanje TTL pravic. Upload in signed ukazi
ostanejo ločeni. Dejanski prihranek se meri na fizičnem transportu.

### P3 — odprtje že vidnega zapisa sproži novo pripravo

Skupni ne-task zapisi iz agregata/iskanja
(`all_spaces/all_spaces_rows.dart:599` → `inbox/notification_target_view.dart:55`)
uporabijo `collaboration_notification_routing.dart:378–392`: negotiate,
logični scopes.list in syncNow. Kasnejši syncNow je lahko poceni/no-change;
ni dokaz, da vedno sinhronizira cel račun. Toda priprava pred njim ni odvisna
od zadnjega namiga sprememb.

Task predogled je že ožji/local-first, vendar ob vsakem novem mount ponovno
preveri metadata in content cursor (`visible_task_target_view.dart:134`,
`collaboration_notification_routing.dart:125,178,214`). Združuje samo sočasne,
ne zaporednih odprtij. E2EE metadata target je lahko ožji od vseh prostorov.

Predlog: pot »odpri znan zapis iz trenutne projekcije« naj uporablja stanje
in generacijo skupnega koordinatorja ter zahteva samo manjkajočo/sumljivo
vsebino. Dejanskemu obvestilu, neznanemu zapisu, izbrisu ali spremenjenim
pravicam ostane sveža namenska pot. Ne zamenjati vseh notification poti na slepo.

### P4 — neodvisna priprava finančnih izbir

Projektni finančni pregled ob mount sproži polno pripravo izbire računov,
urejevalnik pa lahko zahteva svojo ožjo pripravo. Tudi strošek opravila ima
per-editor pripravo (`shared_finance_workspace.dart:23,59`,
`shared_finance_actions.dart:436`, `shared/collaboration_actions.dart:725,805`).
`_readPreparingWork` (`collaboration_provider.dart:682`) ni mrežni single-flight.
Provider med poslušanjem že memoizira; ne trdimo HTTP ob vsakem widget buildu.

Predlog: skupno združevanje združljivih priprav po identiteti, prostoru,
policy/head/generaciji in vrsti selectorja. Ne zamenjati ožje priprave s polno,
ki bi spremenila pripeto politiko odprtega osnutka. Kombinirano finance reuse
med syncem že obstaja; ostale razlike so predvsem pri vstopih iz UI.

### P5 — obvestila: drugo branje in široko nalaganje konfiguracije

`collaboration_sync_actions.dart:1277–1281` vedno izvede inbox → commands →
inbox → konfiguracija, ko je inbox domena izbrana. `_syncCommands`
(`collaboration_notification_sync.dart:175–184`) lahko zaključi brez ukazov,
drugi `_syncInbox` (`:384`) pa vseeno naredi nov logični prejem. Kandidat:
drugo branje samo ob dejanskem učinku poslanega ukaza oziroma novi potrebi.

Konfiguracija (`:449–487`) nato za vsak posredovani prostor bere preferences
in strani reminders. Strežniški inbox namig združuje sequence, visibility in
configuration revision (`server/plugins/FamilyHub/Model/NativeAccountChanges.php:154`).
Tudi navadna sprememba inboxa zato lahko prebudi vso konfiguracijo.
Predlog: ločen config hint/generacija, ohranjen prvi prejem in nadaljevanje
ukazov. Logični inbox klic lahko sproži več fizičnih E2EE zahtevkov; brez meritve
ni številčne obljube prihranka.

### P6 — člani in povabila imajo še lasten režim svežine

Seznama imata current-route/identity/busy varovala in 5s event throttle;
vsak mount/resume/zaključni signal pa ni vezan na dejansko spremembo članstva
(`sharing_members.dart:108–135,177`, `sharing_pending_invitations.dart:98,148`).
To ni 5s periodični polling. Predlog: prikaz iz lokalne preverjene projekcije
in refresh po access/invitation generaciji; namensko osveži neznano stanje
ter rezultat pošiljanja/sprejema/odvzema. Ohraniti samodejno dokončanje dostopa.

### P7 — dvojni accountStatus po potrditvi emaila

`collaboration_account_recovery.dart:78–80` po potrditvi že prebere status,
`account_email_card.dart:95–101` ga prebere ponovno. To je neposredno potrjena
podvojena logična operacija. Predlog: vrni svež rezultat potrditve/statusa UI
z istimi identity varovali. Majhen, jasno omejen popravek; ni glavni vir
stroška običajne sinhronizacije.

### P8 — manj pomembni kandidati za lokalni SQL/CPU

`collaboration_record_actions.dart:133` po običajnem zapisu pogosto kliče
unscoped refreshLocal; tudi scoped refresh še bere pomožne podatke vseh
prostorov (X01). Vrt lahko po lastnem commit ponovno prebere snapshot
(`garden_repository.dart:69–79` in subscription`:13–16`). Idejnik in agregati
imajo nekaj širših lokalnih rekalkulacij (`state/idea_provider.dart:186,263`).
To ni dokaz dodatnih HTTP. Predlog: najprej meritev lokalnih faz, nato scoped
refresh in združevanje postcommit obvestil; ohrani pre-read/CAS in own-ACK
zaščito, ki sta bila potrebna za prejšnje popravke shranjevanja.

## 5. Sklep in meje naslednjega koraka

**Koordinator je vgrajen, optimizacija pa še ni enotna čez vse module.**
Običajni content/finance zapisi uporabljajo skupno dostavo, večina pregledov
bere lokalne projekcije. Najmočnejši izvorni kandidati za dodatno delo so poti ob odprtju in
reakcije na dokumentne/konfiguracijske signale; njihovega deleža v skupnem
času ali številu zahtevkov še nismo izmerili. Ni najden zaseben periodični
HTTP poll za vsak poslovni modul. Ugotovitve ne pomenijo, da je vsako sveže
branje odveč ali da gre za novo napako z odvzemom pravic.

Za nadaljevanje predlagamo P1, P2, P3, P4, P5 in P6 v ločenih, omejenih
spremembah; P7 je majhen samostojen popravek, P8 šele po meritvi. Pred vsako
spremembo zabeležimo samo njen scenarij/fizične operacije, nato primerjamo
isti ciljni scenarij. Ne ponovno celotnega že uspešnega testnega cikla.
Ciljne prihodnje kontrole: dokument brez spremembe, sprememba drugega targeta,
lastni commit proti res novejšemu oddaljenemu zapisu, ponoven task/event open,
finance mount→editor, inbox brez/z ukazom ter večkosovni download. Vključiti
moramo spremembo pravic in ohranitev osnutka; ne izvajamo jih v tem pregledu.

Nespremenljiva varovala: podpis in exact request/receipt, identity/partition,
revizija zapisa in politike, dejanski ACL pred dostavo, šifriranje, obnova,
nepotrjene namere ter compatibility poti. `account.changes` je namig za izbor
dela, ne dokaz dovoljenja. Reuse mora biti vezan na preverjeno stanje.

**Izvedeno:** popis pred delegacijo, trije GPT‑6.1 Sol/high podagenti,
modulni pregled in neodvisno preverjanje ključnih poti. Končni dodatni
pregled združenega poročila ni našel materialnih neskladij; vse omejitve
izvorne analize ostajajo. **Ni izvedeno:**
produktni popravki, novi testi/meritve, gradnje ali posegi v aplikacije,
telefone, Docker in produkcijo. Nobena številka starih testov ni nova meritev
tega pregleda. Dokazi skupin so v ignoriranem
`build/qa/module-sync-audit-20261026/{content,data,account}.md`; ključne najdbe
in reference so ohranjene v tem verzioniranem poročilu.
