# Pregled neuporabljene kode — 26. oktober 2026

## Izhodišče in obseg

Pred začetkom pregleda je bil celoten dotedanji razvoj shranjen v commit
`65373c0c2550525392676b7ed7226c2ba6b1ed24` in potisnjen na `origin/main`.
Oddaljeni hash je preverjeno enak lokalnemu. Aplikacija in strežnik sta v
istem repozitoriju; strežniška koda je že vključena v predhodni commit
`1694c42`, zato v novem commitu ni umetnih strežniških sprememb.

Uporabnik naroča pregled kode in dokumentiranje ugotovitev. Kode ne brišemo.
Računalnik je zaklenjen: ni GUI testov, novih gradenj, namestitev, posegov v
telefone, testne strežnike ali produkcijo. Podagenti GPT‑6.1 Sol/high pregledujejo
UI, jedro in strežnik; glavni agent preverja dokaze in združuje ugotovitve.

Razredi ugotovitev:

- **Potrjen ostanek:** ni produkcijske poti ali klicatelja; naveden je tudi
  morebitni testni klicatelj. Pred odstranitvijo je potrebna ciljna kontrola.
- **Kandidat:** ni najden klic, vendar javni API, dinamični klic ali alternativna
  vstopna točka še zahtevajo preverjanje.
- **Ohrani:** migracije, obnova, združljivost starih odjemalcev, pogojni uvozi
  ter CLI/testna orodja niso mrtva koda zgolj zato, ker jih običajni UI ne kliče.

## Opravljene statične kontrole

- `dart analyze --format machine lib`: 0 napak, 0 opozoril, 513 informacij.
  Od teh je 509 slogovnih `curly_braces_in_flow_control_structures`; preostale
  so `prefer_initializing_formals` (1), `library_private_types_in_public_api`
  (1), `depend_on_referenced_packages` (2). Ni diagnoz unused/dead/unreachable.
  To ne dokazuje uporabe javnih simbolov ali vseh datotek.
- Leksikalni graf `import`/`export`/`part`, vključno z vsemi pogojnimi vejami:
  564 Dart datotek v `lib`, 555 dosegljivih iz `lib/main.dart`, 9 brez te poti.
  Popravljen vzorec je zasidran na direktive na začetku vrstice; ni nerazrešenih
  lokalnih povezav. To je graf datotek, ne popolna analiza klicev ali odsevov.
- Diagnostična izhoda sta v ignorirani mapi
  `build/qa/dead-code-audit-20261026/`; testi se niso izvajali.

## Povzetek ugotovitev

Pregled je zaključen: 5 UI ostankov, 11 ugotovitev v jedru in 5 na strežniku.
To je 21 mest za nadaljnjo presojo, ne 21 avtomatično dovoljenih izbrisov.
Spodnje poti in vrstice veljajo za `65373c0`. Glavni agent je neodvisno preveril
reference UI/jedrnih kandidatov, strežniške metode in pogoje obeh vej.

### UI in testi, ki še uporabljajo stari UI

| ID | Datoteka in simbol | Dokaz, nadomestna pot in ravnanje |
|---|---|---|
| U1 | `lib/organizer/presentation/recovery/crypto_public_card_dialog.dart:4`, `showCryptoPublicCardDialog` | Celotnih66 vrstic nima produkcijskega uvoza. Edini zunanji klic je `test/organizer/presentation/recovery/crypto_public_card_dialog_test.dart:46`. Aktivna pot je `ContactIdentityVerificationPage` iz `sharing_members.dart:303/316`, definicija `account_devices_page.dart:257`. Visoka gotovost ostanka; odstraniti le stari dialog/namenski test, ne preverjanja identitet. |
| U2 | `lib/organizer/presentation/planning/device_reminder_settings.dart:8`, `DeviceReminderSettings` | Celotnih120 vrstic nima produkcijskega uvoza. Konstruira ga test `notification_coordinator_test.dart:395`. Aktivna pot: `settings_page.dart:101` → `showInboxPreferences` v `inbox/inbox_preferences.dart:17`. Pred odstranitvijo prenesti koristno kontrolo življenjske dobe koordinatorja na dejanske nastavitve. |
| U3 | `lib/organizer/presentation/planning/shared_today_overview.dart:10`, `SharedTodayOverview` | Celotnih106 vrstic nima produkcijskega uvoza. Klic le v `archived_agenda_test.dart:60`. Aktivna sta `OrganizerUtripOverview` in `SharedAgendaPage`, npr. `all_spaces_page.dart:164` in `sharing_workspace.dart:657`. Ohraniti kontrolo filtriranja arhiviranih zapisov na dejanski poti; testne datoteke ne izbrisati cele, ker pokriva tudi aktivni koledar. |
| U4 | `lib/organizer/presentation/recovery/account_crypto_startup.dart:28`, `matchesStartupAcknowledgment` | Pomočnik28–41 ima le tri klice v `account_crypto_startup_test.dart:20/30/40`. Dejanski zagon na vrstici81 kliče `AccountProtectionReady.assessStartupReview`. Visoka gotovost zastarelega pomočnika; njegovi testi sami ne dokazujejo varnosti trenutnega zagona. Obstoječe teste aktualne ocene ohraniti ter prenesti še smiselne stare primere. |
| U5 | `lib/organizer/presentation/shared/content_moderation.dart:295`, `ContentReportButton` | Razred295–318 se v produkciji ne konstruira. Testna konstrukcija `content_moderation_ui_test.dart:366`; drugi test `content_actions_menu_ui_test.dart:280` celo pričakuje njegovo odsotnost. Aktivni `SharedContentActionsMenu` kliče `showContentReport` na `content_actions_menu.dart:81`. Odstranljiv je ovoj, ne celotna datoteka ali prijava vsebin; prilagoditi testni vstop. |

Prve tri datoteke skupaj obsegajo292 vrstic; skupaj z U4/U5 je to približno330
vrstic. To ni meritev velikosti paketa ali pospešitve: nepovezano Dart kodo
lahko že odstrani prevajalnik. Največja korist je manj zmede pri vzdrževanju in
manj testov, ki dokazujejo vedenje opuščenega UI.

### Jedro, E2EE in sinhronizacija

Za spodnje javne metode je bil preverjen točen simbol v `lib`, `test` in
Dart orodjih, tudi sklici na metode brez neposrednega klica. `part` knjižnice
so vključene. Odsotnost sklicev je statični dokaz v tem repozitoriju, ne
trditev o vseh mogočih zunanjih uporabnikih knjižnice.

| ID | Datoteka in simbol | Dokaz in meja čiščenja |
|---|---|---|
| C1 | `lib/organizer/data/e2ee/crypto_migration_business_parity.dart:12`, `CryptoMigrationBusinessParity` |224-vrstični v2 codec brez uvoza ali testnega klicatelja. Aktivna pot uporablja `CryptoMigrationBusinessParityV3`, npr. `crypto_migration_cold_business.dart:498`, `crypto_migration_pipeline.dart:362`. Močan kandidat za odstranitev cele datoteke, če ni namerno ohranjen protokolarni primer. Ne odstranjujemo starih shranjenih formatov. |
| C2 | `lib/organizer/data/e2ee/crypto_identity_store.dart:322`, `operationEntries` | Samo deklaracija. Aktivni porabniki kličejo `verifiedOperationEntries:252` (`account_protection_ready.dart:631`, `crypto_migration_generation.dart:583`, `crypto_scope_observations.dart:269/763`). Stari SQL-index bralnik je neuporabljen. Tabelo `crypto_directory_event_index` in test spreminjanja nezaupanega indeksa presoditi ločeno; nobenega brisanja uporabniških tabel. |
| C3 | `lib/organizer/data/e2ee/crypto_finance_choice_capture.dart:260/421`, `buildCapturedSelection` + `verifyCapturedSelection` | Verifier nima klicatelja, njegov edini klic builderja je na432. Skupaj približno198 vrstic neuporabljene poti. Aktivni issuer uporablja `deriveSourceSelection`/`verifySourceSelection` (`crypto_migration_choice_workflow.dart:217/230`), prejemnik `verifyTargetSelection` (`crypto_migration_stage_verifier.dart:894`). Ohraniti skupne tipe in `validate`. |
| C4 | `lib/organizer/data/e2ee/crypto_business_router.dart:1576`, `managerEnsure` | Neklican ovoj `ensurePersonal`. Dejanska pot je isti file1543 in dispatch628; ohraniti manager in to pot. |
| C5 | `lib/organizer/data/e2ee/crypto_business_router.dart:2029`, `reminderStateFor` | Neklican ovoj; notranji `_reminderState` je uporabljen na3403. Odstraniti kvečjemu ovoj. |
| C6 | `lib/organizer/data/e2ee/session_crypto_access.dart:2294`, `verifyDeletedScopeHead` | Neklican ovoj `withVerifiedDeletedScope`. Slednjega aktivno kliče `crypto_business_deletion.dart:395`; dokazovanje izbrisov ostane. |
| C7 | `lib/organizer/data/e2ee/session_crypto_access.dart:2339`, `verifiedCandidateDescriptor` | Samo deklaracija. Aktivni sorodni poti sta `verifiedCandidatePolicyVersion:2261` in `withRecoveryCandidatePolicy:2369`. Pri odstranitvi ne zajeti skupnih descriptor/lifecycle preverjanj. |
| C8 | `lib/organizer/data/e2ee/session_crypto_access.dart:4487`, `verifyProjectRelocation` | Neklican ovoj. Aktivni `recordAuthority:4476` kliče `_projectRelocation.authority(record)` neposredno; dokaze premestitve ohraniti. |
| C9 | `lib/organizer/data/e2ee/crypto_migration_generation.dart:69`, `publishDraft` | Samo deklaracija. `crypto_migration_pipeline.dart:301` neposredno kliče `ScopeCryptoManager.publishMigrationGenerationDraft`. Ni razlog za odstranitev podsistema generacij. |
| C10 | `lib/organizer/data/e2ee/crypto_inherited_invitation_grants.dart:444`, `resumeAll` | Neklican množični pomočnik. Aktivni `finish` kličeta `crypto_approvals_page.dart:121` in `crypto_invitation_autoapproval.dart:380`. Ohraniti journal in nadaljevanje istega povabila; ne priklapljati starega bulk pomočnika v ozadje kot del čiščenja. |
| C11 | `lib/organizer/data/e2ee/account_crypto_repository.dart:307`, `authorizeDevice` | Samo deklaracija, tudi ni del `AccountCryptoWorkflow`. Visoka gotovost neuporabe, srednja gotovost smiselnosti izbrisa zaradi v1 podpore. Celoten v1 repository je še aktivna alternativa prek `collaboration_repository.dart:134`; njega in podpisanih čakajočih zahtev ne odstranjevati. |

### Strežniški del

| ID | Datoteka in simbol | Dokaz in ravnanje |
|---|---|---|
| S1 | `server/plugins/FamilyHub/Model/NativeCryptoInlineDeletionV2.php:9`, zasebni `same` | V lastnem razredu samo deklaracija, brez klica/callbacka. Visoka gotovost neuporabljenega primerjalnika. Razred in izbrisne poti so aktivni. |
| S2 | `server/plugins/FamilyHub/Model/NativeCryptoMigrationInvitationStageV3.php:26`, zasebni `integer` | V razredu samo deklaracija, brez reflection/magic-call mehanizma v vtičniku. Visoka gotovost. Drugi istoimenski validatorji in migracijski adapter so aktivni. |
| S3 | `server/plugins/FamilyHub/Model/NativeCryptoFileInventory.php:33`, javni `safeDescriptors` | Edina pojavitev v repozitoriju. Aktivni porabniki uporabljajo `collect`; podrazred `NativeCryptoMigrationFileExportV2` neposredno uporablja zaščitena `descriptors`/`inspect`. Kandidat za odstranitev metode; zunanji PHP porabniki niso preverjeni. |
| S4 | `server/plugins/FamilyHub/Model/NativeCryptoInlineDeletionV2.php:44`, veja `payment_dependency` | Pogoji36–42 nikoli ne izberejo tipov paymentEvent/paymentProjection/cashMovement/financeAccountChoice; vrstica43 jih preskoči pred to vejo. Trenutno nedosegljiv varovalni pogoj. Pred spremembo določiti namen varovala, ne slepo izbrisati. |
| S5 | Ista datoteka45, veja `unsupported_dependency` | Vsak tip, ki prestane izbor36–42, je že v allowlist45; negativni pogoj zato ni dosegljiv. Enaka meja kot S4. |

S4/S5 **ne pomenita**, da ni drugih varoval za finančne povezave: poznejši
pregled zunanjih referenc in finančne zgodovine na51–55 ostaja aktiven.
Ločena manjša poenostavitev: `NativeCryptoService.php:157`, `if ($identity)`
je odvečen, ker falsey identiteta že vrne odgovor na150–152. Telo, ki doda
`generationCertificate`, je živo in ga ni dovoljeno odstraniti.

Strežniški obseg: leksikalni pregled186 PHP datotek vtičnika/1399 deklaracij
metod; sklici vključujejo186 PHP testov in40 pomožnih skript. Pregledane so vse9
CLI vstopne točke, bootstrap, registracija API/krmilnikov, workerji, migracije
in paketni manifest. Noben celoten razred ni potrjen kot neuporabljen.
PHP ni bil izveden, runtime/cron ali zunanje razširitve niso bili pregledani.

## Koda, ki jo ohranimo ali najprej prestavimo

Pet drugih E2EE datotek izven grafa `main.dart` ima kompatibilnostne/testne
porabnike. To so kandidati za jasno označeno lokacijo, ne samodejni izbris:

- `crypto_migration_archive.dart` in `crypto_archive_cold_restore.dart`:
  zgodovinska arhivska/verifikacijska veriga; `archiveAndVerify` kliče cold
  restore, preverja jo `crypto_migration_archive_http_test.dart:237/490`.
  Aktivni aplikativni tok uporablja `CryptoCaptureArchive` in trenutni pipeline.
- `crypto_legacy_digest.dart`: PHP-kompatibilen stari hash oracle s testom
  `crypto_legacy_digest_test.dart`; primeren za `test/support`, če je namen le
  primerjava protokolov. To ne dovoljuje prepisovanja starih podpisanih zahtev.
- `crypto_migration_provenance.dart`: v2 commitment codec, test
  `crypto_migration_provenance_test.dart`; aktivni v3 uporablja
  `CryptoMigrationCommitmentsV3`. Ohraniti protokolarni dokaz ali prestaviti.
- `encrypted_operation_codec.dart`: stari v1 batch codec, uporabljen v
  `account_crypto_http_test.dart:519`; ohraniti skupaj s kompatibilnostnim testom.

Druge pomembne izključitve:

- Stari `_syncNow` **ni mrtev**: `syncNow` → `_coordinateSync` →
  `_coordinateSyncPass` → `_performSync` → `_syncNow`. Aktivni so moderni,
  legacy in gnezdeni `resumePayments:false` tokovi. Koordinator ne nadomešča
  samega izvedbenega workerja.
- Novi authority cache, account coordinator in njihova razveljavitev so povezani
  z dejansko sinhronizacijo. V tem pregledu ni potrjena odvečna druga sync zanka.
- `localReminderSettingsProvider` še bere stare v1 nastavitve za migracijo v2
  (`local_notification_preferences_provider.dart:22–35`). Stari UI je U2,
  shranjene nastavitve in migracija pa ostanejo.
- Flutter overrides, Riverpod, GoRouter/Navigator, PHP registracije in `new $class`
  so veljavne dinamične povezave. `familyHubPushBackground` ima native
  `@pragma('vm:entry-point')` in Firebase registracijo. Pogojne native/web/stub
  alternative niso mrtve samo zato, ker delamo na Macu.
- Stari JSON-RPC callbacki, CLI datoteke in SQL migracije1–23 so združljivostne
  oziroma framework vstopne točke; odsotnost trenutnega Dart klica ni dokaz
  njihove nepotrebnosti.
- Nekatere druge recovery metode imajo samo neposredne teste, npr.
  `rebaseRejectedBatch`/`reauthorizeRejectedPolicyBatch`; v tem omejenem pregledu
  niso promovirane v potrjene ostanke za odstranitev.

## Predlagan vrstni red nadaljevanja

1. Majhen čistilni commit: U1–U5, preprosti neklicani ovoji C4/C5/C6/C8/C9 in
   zasebna strežniška pomočnika S1/S2. Koristne stare teste preusmeriti na
   dejanske vstopne točke, ne zgolj zmanjšati njihovega števila.
2. Ločeno pregledati C1/C2/C3/C7/C10, nato po potrebi odstraniti neuporabljeno
   implementacijo; brez posegov v shranjene baze, podpise, pending zahteve ali
   zgodovinske migracije. C11/S3 zahtevata še odločitev o zunanji združljivosti.
3. S4/S5 obravnavati kot pojasnitev pravil in varoval izbrisa, ne kozmetiko.
   Morebitna sprememba vedenja potrebuje svoj ciljni test.
4. Po spremembah analiza in samo smiselne ciljne kontrole prizadetih poti.
   Brez ponavljanja vseh že uspešnih mobilnih/GUI scenarijev.

Nič od predlaganega še ni odstranjeno ali prevezano. V tem koraku sta se
spremenili samo dokumentacija in ignorirani audit izhodi. Statični pregled ni
popoln dokaz odsotnosti druge mrtve kode in ne obljublja manj HTTP zahtevkov.

