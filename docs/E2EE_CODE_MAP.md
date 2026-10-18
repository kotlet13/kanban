# Zemljevid kode za E2EE, lokalno šifriranje in obnovitveno datoteko

18. oktober 2026. Prvi razdelek vodi do **trenutnega delovnega izvora**.
Pod njim je jasno ločen zgodovinski zemljevid predhodnega izhodišča.
Stanje izvedbe in odprta vrata določata [E2EE_IMPLEMENTATION.md](E2EE_IMPLEMENTATION.md)
in [E2EE_PROTOCOL.md](E2EE_PROTOCOL.md), izhodna merila pa prvotni
[načrt P0–P8](E2EE_UPGRADE_PLAN.md). To ni potrdilo končne matrike,
neodvisnega P0 pregleda, fizičnega P8 ali nameščene aplikacije.

[Trenutni dokazi in odprte meje](E2EE_IMPLEMENTATION.md#dokazi-in-končno-preverjanje)
so zbrani v izvedbenem dokumentu: migracija, sveža FILE obnova in povezani
zaključni izbris, generacija B ter seznam/umik migriranih opomnikov use3 so
potrjeni z vezanimi teki in nadaljevanji istega stanja. Celotni Flutter66 je razkril
regresije, zaključene s prizadetima ponovitvama69/70. Točni izidi so navedeni
samo v izvedbenem dokumentu; ne gre za nov sveži celotni tek.
Zemljevid kaže vstopne točke, ne potrjuje zaključenega uporabniškega toka,
neodvisnega P0, fizičnega P8 ali hitrega prvega hladnega prenosa.

## Trenutne vstopne točke

Povezave so do datotek/simbolov, ker se vrstice med zaključevanjem spreminjajo.
Prisotnost handlerja ne nadomesti final provenance ali uporabniškega priklopa.

| Področje | Trenutni izvor in odgovornost |
| --- | --- |
| Lokalni bootstrap | [local_vault_bootstrap.dart](../lib/organizer/presentation/recovery/local_vault_bootstrap.dart), [local_vault_native.dart](../lib/organizer/data/local_vault_native.dart), [local_vault.dart](../lib/organizer/data/local_vault.dart): ena zaščitena namestitev pred porabniki baze, candidate/compare/restart brez praznega fallbacka. |
| FILE in čarovnik | [account_crypto_wizard.dart](../lib/organizer/presentation/recovery/account_crypto_wizard.dart), [account_crypto_startup.dart](../lib/organizer/presentation/recovery/account_crypto_startup.dart), [recovery_file_codec.dart](../lib/organizer/data/e2ee/recovery_file_codec.dart), [account_crypto_v2_workflow.dart](../lib/organizer/data/e2ee/account_crypto_v2_workflow.dart): lokalna datoteka/account koren, login ni odklep. |
| Directory in neodvisna sidra | [account_directory_v2.dart](../lib/organizer/data/e2ee/account_directory_v2.dart), [account_directory_repository.dart](../lib/organizer/data/e2ee/account_directory_repository.dart), [crypto_identity_store.dart](../lib/organizer/data/e2ee/crypto_identity_store.dart), [crypto_directory_consistency.dart](../lib/organizer/data/e2ee/crypto_directory_consistency.dart): replay, secure floors, known-prefix ancestry; SQL index ni completeness authority. |
| Scope authority | [session_crypto_access.dart](../lib/organizer/data/e2ee/session_crypto_access.dart), [scope_crypto_codec.dart](../lib/organizer/data/e2ee/scope_crypto_codec.dart), [scope_crypto_manager.dart](../lib/organizer/data/e2ee/scope_crypto_manager.dart): current/history/candidate ločitev, glave, granti, closures, lifecycle in sveže pravice. |
| Poslovna sestava | [crypto_business_router.dart](../lib/organizer/data/e2ee/crypto_business_router.dart), `CryptoBusinessRouter.configurePayloads`; [crypto_domain_router.dart](../lib/organizer/data/e2ee/crypto_domain_router.dart): dejanski adapterji/preparation/validation/project/history, brez legacy fallbacka aktivnega E2EE. |
| Zapisi in zgodovina | [crypto_record_proof_codec.dart](../lib/organizer/data/e2ee/crypto_record_proof_codec.dart), [crypto_sync_repository.dart](../lib/organizer/data/e2ee/crypto_sync_repository.dart), [crypto_business_group_history.dart](../lib/organizer/data/e2ee/crypto_business_group_history.dart), [crypto_domain_checkpoint.dart](../lib/organizer/data/e2ee/crypto_domain_checkpoint.dart): exact proof/batch/chain, historical-only sibling brez trenutnih učinkov. |
| Finance | [crypto_business_finance.dart](../lib/organizer/data/e2ee/crypto_business_finance.dart), [crypto_business_payments.dart](../lib/organizer/data/e2ee/crypto_business_payments.dart), [crypto_finance_policy_actions.dart](../lib/organizer/data/e2ee/crypto_finance_policy_actions.dart), [crypto_finance_uniqueness.dart](../lib/organizer/data/e2ee/crypto_finance_uniqueness.dart): model, current skupine/manifesti, signed politika, keyed BLAKE2b uniqueness. |
| Choices/topology/audit | [crypto_finance_account_choices.dart](../lib/organizer/data/e2ee/crypto_finance_account_choices.dart), [crypto_finance_choice_capture.dart](../lib/organizer/data/e2ee/crypto_finance_choice_capture.dart), [crypto_finance_topology.dart](../lib/organizer/data/e2ee/crypto_finance_topology.dart), [crypto_finance_audit_evidence.dart](../lib/organizer/data/e2ee/crypto_finance_audit_evidence.dart): saniran manifest, split roles, popolnost, originalna logical zgodovina. Capture3 minimalni `financeAccountChoicesRequest` uporablja obstoječi structure context journal; final companion zahteva preverjeno role/rawHash vezavo. |
| Dokumenti/Ideas | [crypto_business_documents.dart](../lib/organizer/data/e2ee/crypto_business_documents.dart), [crypto_document_blob.dart](../lib/organizer/data/e2ee/crypto_document_blob.dart): velika raw vsebina, preglednice, slike, priponke in exact blob/witness integriteta. |
| Javni prehod | [crypto_migration_coordinator.dart](../lib/organizer/data/e2ee/crypto_migration_coordinator.dart), [crypto_migration_pipeline.dart](../lib/organizer/data/e2ee/crypto_migration_pipeline.dart), [crypto_capture_coordinator.dart](../lib/organizer/data/e2ee/crypto_capture_coordinator.dart), [crypto_migration_cold_business.dart](../lib/organizer/data/e2ee/crypto_migration_cold_business.dart): prepare/review/fence/FILE cold/pet controls/domain cert/aktivacija/commit3. |
| Nadaljevanje prekinjene migracije A/B | [crypto_migration_generation_page.dart](../lib/organizer/presentation/recovery/crypto_migration_generation_page.dart), `CryptoMigrationGenerationPage`; [crypto_migration_coordinator.dart](../lib/organizer/data/e2ee/crypto_migration_coordinator.dart), `generation` in `adoptGenerationSuccessor`; [crypto_migration_generation.dart](../lib/organizer/data/e2ee/crypto_migration_generation.dart), `prepare/draft/seal/approve/finish/resumeAcceptedCommit`; [NativeCryptoMigrationGenerationV3.php](../server/plugins/FamilyHub/Model/NativeCryptoMigrationGenerationV3.php): A omogoča izrecno pregledan nov pripravljalni poskus samo pred prvo končno objavo, B ohrani isti objavljeni cilj/ključe/podpise in zahteva sveže potrditve. Manjkajoči prvotni podpisi ostanejo izrecno nepopolni; brez samodejnega reseta že objavljene generacije. [Meje izvedbe](E2EE_GENERATION_CONTINUATION.md). |
| Captured task odvisnost | [crypto_migration_task_dependency.dart](../lib/organizer/data/e2ee/crypto_migration_task_dependency.dart), `prepareCapturedTaskDependency` in `projectCapturedTaskDependency`; [crypto_migration_stage_verifier.dart](../lib/organizer/data/e2ee/crypto_migration_stage_verifier.dart), `verifyTaskDependency`: bralec finančnega prispevka preveri exact owner-signed CONTENT task + intent batch in njegove source/proof vezave. StagedRecords in lokalni dependency cache sta usmerjanje oziroma točno omejena referenčna dokaza, ne splošna poslovna projekcija ali novo WRITE pooblastilo. |
| Zamrznjena FILE directory meja | [session_crypto_access.dart](../lib/organizer/data/e2ee/session_crypto_access.dart), `withReadOnlyFrozenScope`, `requireReadOnlyFrozenScope` in `directoryAt`; [crypto_migration_stage_verifier.dart](../lib/organizer/data/e2ee/crypto_migration_stage_verifier.dart), `frozenCandidate`: exact scope/kandidat in FILE-pripeta lastna predpona omejita cold preverjanje. Kasnejši živ imenik ne nadomesti zajete lastne predpone; izhod iz konteksta odstrani začasne predpomnilnike, ne promovira običajne authority ali varnega scope floora. |
| Nespremenljivo čakajoče delo pred fence | [crypto_migration_pending_work.dart](../lib/organizer/data/e2ee/crypto_migration_pending_work.dart), `CryptoMigrationPendingWork.drain`; [crypto_business_settlement.dart](../lib/organizer/data/e2ee/crypto_business_settlement.dart): priprava uskladi exact obstoječe odhodne zahteve/receipts pred novim freeze. Ne uvozi karantene v živo vrsto in ne izmisli nadomestnega operationId; nedokončan upload ali potreben pregled ostane ohranjen in viden. |
| Normalni migrated reader | [crypto_migration_committed_origin.dart](../lib/organizer/data/e2ee/crypto_migration_committed_origin.dart): obvezen signed migrationOrigin, final scoped activation/contribution/cert/witness; stage/candidate ni navadna authority. |
| Povabila | [invite_crypto_repository.dart](../lib/organizer/data/e2ee/invite_crypto_repository.dart), [crypto_legacy_invitation_evidence.dart](../lib/organizer/data/e2ee/crypto_legacy_invitation_evidence.dart), [crypto_migration_invitation_producer.dart](../lib/organizer/data/e2ee/crypto_migration_invitation_producer.dart): v4 intent/admission in scoped final legacy bridge. |
| Recovery completeness | [crypto_scope_observations.dart](../lib/organizer/data/e2ee/crypto_scope_observations.dart), [crypto_migration_own_attestation.dart](../lib/organizer/data/e2ee/crypto_migration_own_attestation.dart), [crypto_migration_local_artifact_cold.dart](../lib/organizer/data/e2ee/crypto_migration_local_artifact_cold.dart): bounded discovery, signed obligations, private quarantine, honest partial restore. |
| Protection completion | [account_protection_ready.dart](../lib/organizer/data/e2ee/account_protection_ready.dart), `AccountProtectionReady.complete/close/pendingScopeAction`; [account_protection_completion.dart](../lib/organizer/presentation/recovery/account_protection_completion.dart), `finishAccountProtection`: owner recovery transition, izrecni shared pogoji, nespremenljiv job/deadline in prekinljiv lasten dialog. [account_crypto_v2_workflow.dart](../lib/organizer/data/e2ee/account_crypto_v2_workflow.dart), `recover` in `rebindLocalDevice`, ločita FILE obnovo od ponovne vezave že ohranjene potrjene naprave; pripravljeni account ključi niso dokaz popolne obnove vseh obsegov. |
| Izbris | [crypto_business_deletion.dart](../lib/organizer/data/e2ee/crypto_business_deletion.dart), [crypto_business_inline_deletion.dart](../lib/organizer/data/e2ee/crypto_business_inline_deletion.dart), [crypto_inline_deletion_evidence.dart](../lib/organizer/data/e2ee/crypto_inline_deletion_evidence.dart): signed graph/final publication, scoped read, parent topology companion. Account policy4 ostane dostopen brez FILE; affected fence je blocker. |
| Struktura/relocation | [crypto_business_structure.dart](../lib/organizer/data/e2ee/crypto_business_structure.dart), [crypto_access_coordinator.dart](../lib/organizer/data/e2ee/crypto_access_coordinator.dart), [crypto_business_project_relocation.dart](../lib/organizer/data/e2ee/crypto_business_project_relocation.dart), [crypto_project_relocation_evidence.dart](../lib/organizer/data/e2ee/crypto_project_relocation_evidence.dart): typed odobritve, exact final scoped evidence. |
| Backup in lokalni izvirniki | [portable_backup_repository.dart](../lib/organizer/data/portable_backup_repository.dart), [crypto_document_backup_recovery.dart](../lib/organizer/data/e2ee/crypto_document_backup_recovery.dart), [preserved_installation_files_page.dart](../lib/organizer/presentation/recovery/preserved_installation_files_page.dart): particijsko omejeni drafti in ločen pregled installation-wide ohranjenih datotek. |
| Strežniške meje | [NativeCryptoV2Service.php](../server/plugins/FamilyHub/Model/NativeCryptoV2Service.php), [NativeCryptoDirectoryV2.php](../server/plugins/FamilyHub/Model/NativeCryptoDirectoryV2.php), [NativeCryptoScopeV2.php](../server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php), [NativeCryptoStorageV2.php](../server/plugins/FamilyHub/Model/NativeCryptoStorageV2.php), [NativeCryptoMigrationV2.php](../server/plugins/FamilyHub/Model/NativeCryptoMigrationV2.php): signature/ACL/CAS/fence in atomski effects, brez vsebinskih DEK. |
| Account deletion/core hook | [NativeCryptoAccountDeletionV2.php](../server/plugins/FamilyHub/Model/NativeCryptoAccountDeletionV2.php), [NativeCryptoAccountTombstoneV2.php](../server/plugins/FamilyHub/Model/NativeCryptoAccountTombstoneV2.php), [FamilyHubUserModel.php](../server/plugins/FamilyHub/Model/FamilyHubUserModel.php): auth-only policy4, trajna prepoved oživitve in ohranitev potrebnih shared dokazov. |
| Končni dokazi | [Izvedbeni dokument](E2EE_IMPLEMENTATION.md#dokazi-in-končno-preverjanje) centralno veže dejanske source/log/stanje rezultate in preostale meje; zasebni QA fixture credentials niso del Gita. |

## Zgodovinski zemljevid izhodišča

Naslednji oštevilčeni razdelki so namerno ohranjen **predizvedbeni pregled**
commita `4c6b35d582d4873641c6c27bb7bbfa10da821999`. Njihovi stolpci »trenutno«
in »predvideno« ter številke vrstic veljajo za tisto izhodišče, ne za današnji
izvor. Ne uporabljaj jih kot seznam današnjih nedokončanih handlerjev ali kot
dokaz zaključene nadgradnje. Izvorna merila in razlogi ostanejo uporabna.

## 1 Zagon, zapora čarovnika in ozadje

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [main.dart:15](../lib/main.dart#L15), `main` | Inicializira Flutter, namizno okno in zažene `ProviderScope/JivieApp`. | Pred porabniki shrambe vključi trajni `LocalVaultBootstrap`; L01, L02. |
| [app.dart:53](../lib/app.dart#L53), `_JivieAppState.build` | Posluša povrnitev nastavitev, še preden uporabnik odpre nastavitve. | Replay ne sme prehiteti odklepa ali migracije; L03, L08. |
| [backup_preferences_replay.dart:6](../lib/organizer/platform/backup_preferences_replay.dart#L6), `backupPreferencesReplayProvider` | Odpre backup repository in s tem lokalno bazo. | Najprej pridobi pripravljeni vault; ne uvajaj drugega odprtja mimo zapore. |
| [app.dart:89](../lib/app.dart#L89), builder | Invitation, remote-push in local-notification koordinatorji ovijajo router. | Čarovnik samo znotraj `OrganizerShell` ne zadostuje; zapora mora pokriti tudi te koordinatorje; A02, N02. |
| [app_router.dart:9](../lib/app_router.dart#L9), `appRouter` | Edina glavna pot `/` odpre `OrganizerShell`. | Ohranjen router; migracijski zaslon nad običajno navigacijo. |
| [local_database_provider.dart:11](../lib/organizer/state/local_database_provider.dart#L11), `localDatabaseProvider` | Baza je neodvisna od računa, gesla in omrežja. | Tovarno zamenja pripravljen šifrirani executor; lokalna uporaba ostane brez računa; L04. |
| [organizer_provider.dart:35](../lib/organizer/state/organizer_provider.dart#L35), `organizerStorageProvider` | Odpiranje SQLite sproži tudi preverbo selitve Hive. | Med migracijo noben vzporeden nešifriran handle ali ponovljen uvoz; L03, L05. |
| [organizer_provider.dart:53](../lib/organizer/state/organizer_provider.dart#L53), `organizerRepositoryProvider` | Počaka prejšnji close in dokonča inicializacijo repozitorija. | Ohraniti čakanje vseh zapisov in zapiranje pred datotečnim preklopom. |
| [collaboration_provider.dart:75](../lib/organizer/state/collaboration_provider.dart#L75), `collaborationRepositoryProvider` | Odpre isto bazo, transport in varne shrambe; inicializira sejo. | Loči lokalni vault, prijavno sejo in stanje računskih ključev; A03. |
| [collaboration_provider.dart:153](../lib/organizer/state/collaboration_provider.dart#L153), `refresh` | Timer vsake tri sekunde osveži lokalno stanje; vsako četrto osvežitev sproži sync. | Trajna zapora vsebinskega prometa, ne le disabled gumb; L03, A01. |
| [collaboration_provider.dart:180](../lib/organizer/state/collaboration_provider.dart#L180), timer/resume | Zagon, resume in microtask lahko sprožijo sync brez dotika uporabnika. | Med pripravo ključev zadrži vse tri sprožilce; ob nadaljevanju preveri identiteto/generacijo. |

Čarovnik »Dodajanje obnovitvenega ključa« potrebuje svoj migration ID,
avtoritativno generacijo in preverjene trajne korake. Onboarding preference
ne sme postati dokaz šifriranja ali edino mesto migracijskega dnevnika.
Vrnitev neposredne povezave ali push mora počakati na pravi vault in račun.

## 2 Celotna lokalna shramba in platforme

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [collaboration_database_native.dart:6](../lib/organizer/data/collaboration_database_native.dart#L6), `openCollaborationDatabase` | `NativeDatabase.createInBackground` odpre navadno `organizer_shared_v1.sqlite` v application documents. | Izbran preverjeni cipher, ključ pred odprtjem, noben plaintext fallback; L04, L06. |
| [collaboration_database.dart:10](../lib/organizer/data/collaboration_database.dart#L10), `schemaVersion` | Lokalna schema10; prehod na10 je pogodbeni fence, ne nova tabela. | Šifrirne migracije ne zamenjaj s poslovno migracijo ali obnovo iz modelov. |
| [collaboration_database.dart:38](../lib/organizer/data/collaboration_database.dart#L38), `migration` | Ustvari shemo in zaporedne stare nadgradnje; neznano pot zavrne. | Ohraniti vse SQL strukture, nepoznane podatke in zavrnitev prihodnjih formatov; L05. |
| [collaboration_database.dart:108](../lib/organizer/data/collaboration_database.dart#L108), `_schema` | Accounts, scopes, records, outbox, conflicts, leases vsebujejo JSON in revizije. | Primerjaj vse vrstice in izvirna telesa, indekse, zaporedja in FK. |
| [collaboration_database.dart:131](../lib/organizer/data/collaboration_database.dart#L131), `_upgrade2` | Commands, finance outbox/conflicts, inbox/preferences/reminders delijo isto bazo. | Vključi čakajoče in blokirano delo, ne le vidnih zapisov; L05. |
| [collaboration_database.dart:158](../lib/organizer/data/collaboration_database.dart#L158), `_upgrade4` | Personal workspaces, map, `migration_snapshot`, `restored_backups`. | Ohraniti izvirnike, preslikave in šifrirano karanteno; B01. |
| [collaboration_database.dart:173](../lib/organizer/data/collaboration_database.dart#L173), `_upgrade7/8/9` | Local spaces, vrtne/Ideas povezave, linked-payment evidence, asset BLOB in drafts. | Inventar mora zajeti tudi vse neračunske podatke in binarne bajte; L05. |
| [collaboration_database.dart:102](../lib/organizer/data/collaboration_database.dart#L102), `beforeOpen` | Nastavi FK in busy timeout. | Pri cipher executorju ohraniti te nastavitve in preverjanje dejanskega pogona. |
| [collaboration_database_web.dart:5](../lib/organizer/data/collaboration_database_web.dart#L5), `openCollaborationDatabase` | Wasm trajna shramba zavrne unsafe IndexedDB/in-memory. | Native zaščite ne predstavljaj kot spletne; ohrani izvirnik in izvoz po glavnem načrtu. |
| [organizer_storage.dart:122](../lib/organizer/data/organizer_storage.dart#L122), `HiveOrganizerStorage` | Box `organizer_personal_v1`, `committed_snapshot`; `openBox` brez encryptionCipher. | Zaščiti tudi legacy izvirnik; po preverjeni šifrirani kopiji načrtuj ponovljivo odstranitev plaintexta; L08. |
| [organizer_storage.dart:138](../lib/organizer/data/organizer_storage.dart#L138), `read` | Poškodovan ali novejši okvir vrže napako; ne nadomesti ga s praznim. | Isto pravilo mora veljati za napačen/manjkajoč vault ključ; L04. |
| [sqlite_organizer_storage.dart:57](../lib/organizer/data/sqlite_organizer_storage.dart#L57), `_initialize` | Prebere Hive; marker, migration snapshot in vsak zapis zapiše atomarno. | Ne ponavljaj poslovne selitve zaradi menjave šifrirnega pogona; L02, L05. |
| [idea_repository.dart:357](../lib/organizer/data/idea_repository.dart#L357), `storeAsset` | Slike so preverjeni BLOB bajti v `idea_assets`. | Celotna baza mora zaščititi tudi bajte in metapodatke, ne samo opis elementa. |
| [collaboration_document_actions.dart:145](../lib/organizer/data/collaboration_document_actions.dart#L145), `cache/putCache` | Dokumentni cache je JSON v `local_meta`; datoteke imajo 64MiB politiko. | Ohraniti cache in njegove omejitve; preveriti vse ključe prefiksa; L05, D02. |
| [collaboration_document_actions.dart:532](../lib/organizer/data/collaboration_document_actions.dart#L532), `_draftKey` | Preglednični osnutek je vezan na particijo/prostor/tabelo. | Med odklepom ne izgubi lokalnega osnutka ali ga pošlji drugemu računu; D01. |
| [collaboration_document_actions.dart:715](../lib/organizer/data/collaboration_document_actions.dart#L715), attachment cache | Preverjena priponka je base64 v lokalni bazi ter kopija v pomnilniku. | Migracija vseh cache bajtov; ključ objekta/manifest ostane znotraj dovoljenega obsega; D02. |

Za pretvorbo celotne namestitve ni dovolj `.vsakdan` izvoz. Potreben je
dosleden SQLite posnetek z obravnavo WAL/SHM in vseh odprtih povezav/isolatov,
primerjava vseh tabel ter `sqlite_sequence`, preverjen šifrirani cilj,
ponovni odklep in šele nato preklop avtoritativne datoteke.
Izgubljen sistemski ključ ob obstoječem šifriranem viru pomeni obnovo,
nikoli ustvarjanja prazne baze ali brisanja izvirnika; L02–L07.

## 3 Preference, zunanje datoteke in sistemska obvestila

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [locale_store.dart:10](../lib/storage/locale_store.dart#L10), locale; [theme_mode_store.dart:10](../lib/storage/theme_mode_store.dart#L10), theme | Navadne UI preference. | Dokumentiran minimalni bootstrap allowlist; niso dokaz odklepa. |
| [getting_started.dart:14](../lib/organizer/presentation/onboarding/getting_started.dart#L14), `GettingStartedSeenController` | Flag začetnih možnosti v SharedPreferences. | Ohraniti izbiro; recovery setup dobi ločeno trajno stanje. |
| [first_time_guide.dart:12](../lib/organizer/presentation/onboarding/first_time_guide.dart#L12), `FirstTimeGuideSeenController` | Flag že prikazane pomoči. | Čarovnik nadgradnje se ne sme izklopiti zaradi stare pomoči; L01. |
| [main.dart:63](../lib/main.dart#L63), `_readSavedSize` | Namizna geometrija se bere pred UI. | Nenevarna nastavitev ostane dostopna pred odklepom. |
| [local_notification_adapter.dart:21](../lib/organizer/platform/local_notification_adapter.dart#L21), `_idsKey`; [ista datoteka:84](../lib/organizer/platform/local_notification_adapter.dart#L84) | ID-ji/fingerprints in usmerjanje se hranijo v preferences. | Popis občutljivih referenc, zaščitena hramba in pravilna rekonciliacija; L08, N01. |
| [remote_push_lifecycle.dart:84](../lib/organizer/platform/remote_push/remote_push_lifecycle.dart#L84), SDK identity/cleanup | Trajna SDK pripadnost in cleanup z generacijo. | Ne pošlji starega tokena ali odprtja napačnemu računu med obnovo; N02. |
| [backup_ui_preferences.dart:6](../lib/organizer/platform/backup_ui_preferences.dart#L6), `PlatformBackupUiPreferencesStore` | Prenosni allowlist locale/theme/intro izključuje seje, dostavo in OS dovoljenja. | Ohraniti omejen pomen ter ponovljiv replay po SQL commit; B01. |
| [attachment_file_io.dart:14](../lib/organizer/presentation/attachments/attachment_file_io.dart#L14), picker; [ista datoteka:52](../lib/organizer/presentation/attachments/attachment_file_io.dart#L52), exporter | Omejen uvoz in izrecni OS save; javne mape se ne polnijo samodejno. | Loči upravljane šifrirane datoteke od uporabnikovega izrecnega plaintext izvoza. |
| [AndroidManifest.xml:4](../android/app/src/main/AndroidManifest.xml#L4), application | Izvor nima izrecnih application backup/extraction pravil. | Preglej združeni manifest in določi backup/transfer baz, ključev in sej; L07. |
| [pubspec.yaml:47](../pubspec.yaml#L47), odvisnosti | Na voljo so secure storage, file picker, share_plus, cryptography in Drift. | Nobena odvisnost sama ne dokazuje varnega recovery deljenja ali cipher runtime; P0/P1. |

Pri začasnih datotekah preverimo tudi platformni FileProvider, plugin cache,
pravice in čas čiščenja po prevzemu priponke. V obstoječem `lib` ni klica
`share_plus`; nov `RecoveryShareAdapter` mora biti ločen od FamilyHub pošte.
Vrnitev iz sistemskega deljenja ni dokaz dostave; R01, R02, R08.

## 4 Ključi, seja in identitete

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [device_session_store.dart:18](../lib/organizer/data/device_session_store.dart#L18), `SecureDeviceSessionStore` | En varen zapis profila/žetona; write/delete preveri s ponovnim read. | Vzorec preverjenih zapisov uporabi za ločen `VaultKeyStore`; brez fallbacka v prefs; L04. |
| [device_session_store.dart:23](../lib/organizer/data/device_session_store.dart#L23), `read` | Neuspešna varna shramba vrne `secure_storage`, ne plaintext sej. | Loči odsoten nov ključ od nedosegljivega ključa ob starem vaultu. |
| [pending_invitation_store.dart:57](../lib/organizer/data/pending_invitation_store.dart#L57), skupna vrsta | Vse instance istega varnega ključa uporabljajo eno zaporedno vrsto. | Kriptografski koraki ne smejo obiti varovala poznih zapisov; A02, A03. |
| [remote_push_store.dart:154](../lib/organizer/data/remote_push_store.dart#L154), secure store; [account_deletion_store.dart:68](../lib/organizer/data/account_deletion_store.dart#L68) | Push skrivnosti in čakajoči izbris imajo ločene varne zapise. | Ne dodajaj jih v recovery datoteko ali podatkovno kopijo; R08, B01. |
| [collaboration_models.dart:56](../lib/organizer/domain/collaboration_models.dart#L56), `AccountSession` | `partition` združi URL, trajni serverId in accountId. | Ključni paketi in AAD morajo biti pripeti tej identiteti, ne username/userId; A03, R03. |
| [collaboration_repository.dart:683](../lib/organizer/data/collaboration_repository.dart#L683), `newSharedId` | Naključni UUID nastane lokalno brez serverja. | Ohraniti identifikatorje; sprememba šifriranja jih ne regenerira; L05, M03. |
| [collaboration_account_actions.dart:405](../lib/organizer/data/collaboration_account_actions.dart#L405), `signOut` | Odstrani izpostavljeno sejo in sproži cleanup; lokalna baza ostane. | Vault ključ ni sejni žeton; odjava ne uniči lokalne obnovljivosti. |

Trenutna aplikacija nima identitete E2EE računa, računskega keyringa,
napravnih javnih ključev ali recovery datoteke. Obstoječa kriptografija
kopije ni dokaz protokola deljenja. Nova imena storitev v glavnem načrtu
so razdelitev prihodnjih odgovornosti, ne seznam implementiranih razredov.

## 5 Prijava, registracija, e-pošta in povabila

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [sharing_auth.dart:160](../lib/organizer/presentation/shared/sharing_auth.dart#L160), `_connect`; [ista datoteka:254](../lib/organizer/presentation/shared/sharing_auth.dart#L254), `_enroll` | UI sproži prijavo/registracijo in obravnava napake ustvarjenega računa. | Nadaljevalni recovery/ključni korak z jasno identiteto; ne ponovi porabljenega enrollment kode. |
| [collaboration_account_actions.dart:249](../lib/organizer/data/collaboration_account_actions.dart#L249), `_authenticate` | Resetira trenutno sejo/generacijo, pošlje prijavne podatke, zapiše nov profil in token. | Omejena seja do e-pošte in ključev; ne ustvari novega korena ob manjkajočem lokalnem ključu; R05. |
| [collaboration_account_actions.dart:345](../lib/organizer/data/collaboration_account_actions.dart#L345), secure critical section | Shrani sejo, aktivira personal profile in prebere capabilities. | Oba dela poveži s trajnim account-crypto stanjem in zaščito po vsakem await; A03. |
| [collaboration_account_actions.dart:398](../lib/organizer/data/collaboration_account_actions.dart#L398), auth zaključek | Po `refreshLocal` takoj pokliče `syncNow`. | Tu mora biti zapora pred vsebinskim prenosom; dialog po vrnitvi `login` je prepozen. |
| [collaboration_repository.dart:151](../lib/organizer/data/collaboration_repository.dart#L151), `initialize` | Ob restartu obnovi že shranjeno sejo, zmožnosti in lokalni dostop. | Zazna manjkajoči account setup tudi brez nove prijave; L01, A01. |
| [collaboration_repository.dart:193](../lib/organizer/data/collaboration_repository.dart#L193), expiry | Potek prijave sam ne odvzame prej prenesene vsebine. | Ohraniti offline lastnosti; nedosegljivost ni preklic, izgubljen ključ ni prazen račun. |
| [collaboration_account_recovery.dart:31](../lib/organizer/data/collaboration_account_recovery.dart#L31), verification; [ista datoteka:66](../lib/organizer/data/collaboration_account_recovery.dart#L66), `confirmPasswordReset` | E-poštna pot in geslo upravljata prijavo; ne obnovita ključev. | Reset ne odklene ali zamenja E2EE korena; R04, R05, A01. |
| [invitation_wizard.dart:46](../lib/organizer/presentation/shared/invitation_wizard.dart#L46), `_InvitationStep`; [ista datoteka:112](../lib/organizer/presentation/shared/invitation_wizard.dart#L112), `_restore` | Ločen trajno obnovljiv invitation tok. | Dodaj recovery subflow brez izgube povezave ali samodejnega Join; A02. |
| [invitation_wizard.dart:228](../lib/organizer/presentation/shared/invitation_wizard.dart#L228), `_authenticate`; [ista datoteka:288](../lib/organizer/presentation/shared/invitation_wizard.dart#L288), `_join` | Registracija/prijava in sprejem sta ločena. | Po Join loči članstvo in veljaven prejeti ključ; S04. |
| [collaboration_account_actions.dart:193](../lib/organizer/data/collaboration_account_actions.dart#L193), `loginForInvitation` | Pred poverilnicami preveri pripeti izvor/serverId. | Isti origin pin za keyring, recovery in naprave; R03, A03. |
| [collaboration_provider.dart:40](../lib/organizer/state/collaboration_provider.dart#L40), pending revision | Neodvisni signal prepreči krožno invalidacijo invitation projekcije. | Ohrani ga tudi skozi kriptografski čarovnik. |

## 6 Sinhronizacija, finance4 in lokalna objava

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [collaboration_sync_actions.dart:42](../lib/organizer/data/collaboration_sync_actions.dart#L42), `syncNow` | Lease, auth preflight, scope pravice, outbox/pull ter druge vrste. | Verzionirana slepa pot s podpisanimi prejemki; ohrani lease in zapore; M01–M04. |
| [collaboration_sync_actions.dart:163](../lib/organizer/data/collaboration_sync_actions.dart#L163), izbor outbox | SQL bere JSON operacij in odvisnosti; vrstni red po sequence. | Celotna lokalna baza ostane po odklepu SQL uporabna; na serverju nove minimalne reference. |
| [collaboration_sync_actions.dart:253](../lib/organizer/data/collaboration_sync_actions.dart#L253), push | Pošlje originalno operacijo in morebitni financePair. | Šifropis stabilno shrani pred prvim pošiljanjem; ne spremeni telesa pod že uporabljenim opId; M03. |
| [collaboration_sync_actions.dart:285](../lib/organizer/data/collaboration_sync_actions.dart#L285), ACK transakcija | Uspeh atomsko posodobi kanonično evidenco in odstrani čakajočo operacijo. | Izgubljen ACK razreši s prejemkom istega ID; nikoli novo knjiženje. |
| [collaboration_repository.dart:126](../lib/organizer/data/collaboration_repository.dart#L126), `_financeNamespace` | Pogodba3 izbere `finance4`, prejšnje poti ostanejo združljive. | E2EE doda svojo capability/pogodbo; ne spreminja pomena starih wire verzij. |
| [shared_finance_models.dart:20](../lib/organizer/domain/shared_finance_models.dart#L20), `SharedFinancePolicy` | Contributor IDs, sequences in completeness so ločeni od samega canRead. | Podpisani manifesti morajo ohraniti popolnost tudi po zadnji odstranjeni povezavi; F01. |
| [organization_finance_projection.dart:72](../lib/organizer/domain/organization_finance_projection.dart#L72), projekcija | Preverja seznam contributorjev, sequence in dostop pred skupnim prikazom. | Noben saldo iz delno odklenjene komponente; F01, M02. |
| [collaboration_finance_account_choices.dart:23](../lib/organizer/data/collaboration_finance_account_choices.dart#L23), cached choices; [ista datoteka:119](../lib/organizer/data/collaboration_finance_account_choices.dart#L119), fetch | Projekt dobi ločeno sanirano projekcijo računa starša z revision/sequence. | Šifriraj to projekcijo za projektni ključ, ne deli parent finance ključa; F02. |
| [shared_finance_models.dart:201](../lib/organizer/domain/shared_finance_models.dart#L201), `SharedFinanceAccountChoice` | Strogi nabor scopeId/id/name/currency/archived, brez openingBalance. | Ohraniti minimalnost tudi znotraj ovojnic in manifestov. |
| [collaboration_finance_sync.dart:392](../lib/organizer/data/collaboration_finance_sync.dart#L392), `_pullFinanceScope` | Cursor, accessRevision, canonical in contributor dokaz zapiše skupaj. | Preveri podpis/epoho pred commitom; pozni odgovor ne povrne odvzetega dostopa; F01, A03. |
| [collaboration_finance_actions.dart:81](../lib/organizer/data/collaboration_finance_actions.dart#L81), `_storeFinancePolicy` | Sprememba contributorjev/sequence razveljavi popolnost. | Kriptografska menjava ključev ne sme izničiti istega varovala. |
| [collaboration_task_cost_actions.dart:4](../lib/organizer/data/collaboration_task_cost_actions.dart#L4), `saveTaskWithCost` | Opravilo in strošek imata povezani nespremenljivi operaciji. | Atomski podpisani batch ali noben učinek; F03. |
| [collaboration_linked_payments.dart:4](../lib/organizer/data/collaboration_linked_payments.dart#L4), `linkedPaymentCall` | Ločena pogodba povezanih plačil in projekcij. | Ohraniti zasebne računske povezave ter omejitev povračil; F04. |
| [collaboration_finance_actions.dart:890](../lib/organizer/data/collaboration_finance_actions.dart#L890), materializacija | Mesečne occurrence učinke vodi po obstoječih pravilih. | Šifriranje ne odpravi rule/month idempotentnosti; F05. |
| [collaboration_local_space_publication.dart:310](../lib/organizer/data/collaboration_local_space_publication.dart#L310), `publishLocalSpaces` | Izrecno objavi lokalni izvor in vodi preslikave; finance ohranijo povezave. | Prehod zaščite ni nova objava ali nova kopija prostora; L05, M03. |

## 7 Prenosna kopija in lokalna recovery datoteka

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [portable_backup_crypto.dart:8](../lib/organizer/data/portable_backup_crypto.dart#L8), `PortableBackupCrypto` | AES256-GCM, PBKDF2-SHA256/600000, naključni salt/nonce in overjen header. | Ohraniti stare kopije; nov recovery format in ključna hierarhija imata drug namen; B01. |
| [portable_backup_repository.dart:58](../lib/organizer/data/portable_backup_repository.dart#L58), `exclusions` | Kopija izključuje seje, dostavne skrivnosti, druge odjavljene račune in celotno server bazo. | Ni vozilo za brezizgubno pretvorbo vse namestitve; L05. |
| [portable_backup_repository.dart:115](../lib/organizer/data/portable_backup_repository.dart#L115), `exportEncryptedBackup` | Filtrira aktualne pravice, pripravi vsebino8/database10 in preveri rights stamp. | Dodaj ekspliciten manifest ključnih odvisnosti, ohrani preverbo po šifriranju. |
| [portable_backup_repository.dart:423](../lib/organizer/data/portable_backup_repository.dart#L423), `restoreEncryptedBackup` | Restore mode in expected revision; ni navadno celotno datotečno kopiranje. | Ohrani stare formate1–8 in prepreči nenamerno aktivacijo uvoženih pravic. |
| [portable_backup_repository.dart:712](../lib/organizer/data/portable_backup_repository.dart#L712), recovery archive; [ista datoteka:727](../lib/organizer/data/portable_backup_repository.dart#L727), prefs journal | Izvirna kopija in settings dnevnik sta v isti SQL transakciji. | Uporaben vzorec ponovljivega zaključka, vendar z dnevnikom dostopnim pred odprtjem vaulta. |
| [collaboration_backup_actions.dart:6](../lib/organizer/data/collaboration_backup_actions.dart#L6), `resumePortableBackup` | Isto identiteto in sveže pravice preveri pred nadaljevanjem. | Recovery ključ ne podeli članstva; stari opId/request/wire ostanejo; B01, M03. |
| [collaboration_backup_actions.dart:142](../lib/organizer/data/collaboration_backup_actions.dart#L142), duplicate body guard | Isti opId z drugačnim request je konflikt; kanonična podlaga je sveža. | Migracijski most potrebuje izrecne legacy prejemke, ne tihega prešifriranja iste zahteve. |
| [backup_file_io.dart:18](../lib/organizer/presentation/backup/backup_file_io.dart#L18), `BackupFileIo` | Bounded picker in OS save ločita saved/cancelled/downloadStarted. | Vzorec za `RecoveryFileIo`; druga končnica, strogi bounded parser in ponovni zunanji uvoz; R01–R03. |
| [sharing_recovery.dart:12](../lib/organizer/presentation/shared/sharing_recovery.dart#L12), `exportSharingDrafts`; [personal_json_export.dart:13](../lib/organizer/presentation/backup/personal_json_export.dart#L13) | Izrecna nešifrirana JSON izvoza brez sej. | Ne zamenjuj ju z obnovitveno datoteko ali dokazom popolne kopije. |

Recovery datoteka nastane/prebere se lokalno. Sistemskemu save/share sledi
ponovna izbira zunanje kopije in odklep preskusne ovojnice prave identitete.
FamilyHub endpointi, SMTP, logi in poročila napak ne smejo prejeti skrivnosti.
Podatkovna kopija ter recovery datoteka ostaneta različna artefakta; R04–R08.
Računska datoteka ne vsebuje ključa celotne fizične baze. Ločena datoteka
namestitve lahko z njeno kopijo odklene tudi druge shranjene profile, zato
zahteva izrecen predogled obsega iz §5.2 načrta; L09. Obnovitev vsebine ne
potrdi prenesene napravne identitete in ne prenese seje.

## 8 Strežniška prijava in deljenje

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [NativeAuthService.php:62](../server/plugins/FamilyHub/Model/NativeAuthService.php#L62), `login`; [ista datoteka:141](../server/plugins/FamilyHub/Model/NativeAuthService.php#L141), `issue` | Server preveri prejeto geslo/TOTP in izda bearer. | Seja ni podatkovni ključ; ločen protokol javnih ključev in potrjenih naprav; R05. |
| [NativeDatabase.php:118](../server/plugins/FamilyHub/Model/NativeDatabase.php#L118), actor; [ista datoteka:183](../server/plugins/FamilyHub/Model/NativeDatabase.php#L183), scope | Preveri aktivno napravo, račun in sveže ACL; parent pred child. | ACL ostane potreben ob podpisanih pooblastilih; server sam ne izdela veljavnega key granta; S02. |
| [NativeAccountService.php:20](../server/plugins/FamilyHub/Model/NativeAccountService.php#L20), email step-up | Obstoječa e-poštna verifikacija je ločena od login. | Pisanje povezanega računa zapri tudi na neposrednem API in starem klientu; A01. |
| [NativePasswordResetService.php:15](../server/plugins/FamilyHub/Model/NativePasswordResetService.php#L15), reset | Preveri token/email/revision; zamenja password hash in prekliče naprave/push. | Reset ne prepiše E2EE identitete; obnova potrebuje datoteko ali zaupanja vredno napravo; R04, R05. |
| [NativeAccountMailCrypto.php:6](../server/plugins/FamilyHub/Model/NativeAccountMailCrypto.php#L6); [NativePushCrypto.php:6](../server/plugins/FamilyHub/Model/NativePushCrypto.php#L6) | Server AES-GCM ključ varuje poštno vrsto oziroma token at rest. | To ni E2EE; nobena taka skrivnost ne odklepa vsebinskih obsegov. |
| [NativeOrganizationAccess.php:24](../server/plugins/FamilyHub/Model/NativeOrganizationAccess.php#L24), `decorate`; [ista datoteka:54](../server/plugins/FamilyHub/Model/NativeOrganizationAccess.php#L54), `members` | Izračuna podedovani policy3 dostop in učinkovite člane. | Ključne ovojnice sledijo podedovanim projektom, project-only član ne dobi parent ključa; S01, S03. |
| [NativeEmailInvitationService.php:57](../server/plugins/FamilyHub/Model/NativeEmailInvitationService.php#L57), accept; [ista datoteka:114](../server/plugins/FamilyHub/Model/NativeEmailInvitationService.php#L114), `register` | Sprejem poveže pravega prejemnika; registracija sama ne ustvari članstva. | Ločeni trajni membership/key-ready stanji; invitation SMTP token ne nosi DEK ali recovery skrivnosti; A02, S04. |
| [NativeEmailInvitationService.php:185](../server/plugins/FamilyHub/Model/NativeEmailInvitationService.php#L185), `previewWire` | Predogled razkrije ime prostora in pošiljatelja v plaintextu. | Določi zaščiten predogled oziroma dokumentiran minimalni metapodatek; ne pozabi te stranske poti; M05. |
| [NativeMembershipRevocation.php:7](../server/plugins/FamilyHub/Model/NativeMembershipRevocation.php#L7), `apply` | Odstrani grants, prepreči osirotelega lastnika in osveži revizije. | Zamenjava epohe in prihodnjih ovojnic; ne izbriši zadnjega dovoljenega ovoja lastnika; S03. |
| [NativeProjectSharingService.php:51](../server/plugins/FamilyHub/Model/NativeProjectSharingService.php#L51), `graph` | Server bere projekt/task/people/finance/rule/assets in preoblikuje inline projekt. | Priprava grafa na zaupanja vredni napravi, strukturni server commit in ohranjene preslikave; M03. |

## 9 Strežniška sinhronizacija in stranske kopije

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [NativeSyncService.php:28](../server/plugins/FamilyHub/Model/NativeSyncService.php#L28), push | Sveži ACL je pred replay; operacija ima opId/id/type/revision/deleted/payload. | Ohraniti ACL, CAS, tombstone in stabilen ID nad overjeno ovojnico; M01, M03. |
| [NativeDatabase.php:272](../server/plugins/FamilyHub/Model/NativeDatabase.php#L272), request hash; [ista datoteka:286](../server/plugins/FamilyHub/Model/NativeDatabase.php#L286), replay | Kanonični hash zazna drugačno telo; response cache hrani vsebino. | Za stare operacije ekspliciten most/prejemek; preglej tudi response_json, ne le records; M03, M05. |
| [NativeSyncService.php:64](../server/plugins/FamilyHub/Model/NativeSyncService.php#L64), revision/conflict | CAS napaka trajno shrani tudi poln serverRecord. | Šifrirati ali upokojiti vse zgodovinske uspešne in konfliktne odgovore; M05. |
| [NativeRecordPolicy.php:7](../server/plugins/FamilyHub/Model/NativeRecordPolicy.php#L7), `validate` | Server validira plaintext model in povezave pred zapisom JSON. | Overjeno vsebinsko validacijo prevzame odjemalec; strukturnih omejitev ne ukini tiho. |
| [NativeSyncService.php:103](../server/plugins/FamilyHub/Model/NativeSyncService.php#L103), poslovni učinki | Zapis sproži notifications, reminders in task-cost uskladitev. | Nov ekspliciten atomski ukaz/namera namesto nevidne odvisnosti od dešifriranja. |
| [NativeSyncService.php:108](../server/plugins/FamilyHub/Model/NativeSyncService.php#L108), compound sync/finance | Oba dela commit ali rollback; trajni neuspešni izid omogoča retry. | Ohraniti isti batch dokaz in rollback pri konfliktu enega dela; F03. |
| [NativeSyncService.php:147](../server/plugins/FamilyHub/Model/NativeSyncService.php#L147), pull | Cursor paginacija in pogodbeni fence. | Epoha/manifest/prejemki ter jasen upgrade_required za stare poti po commitu; M04. |
| [NativeSchema.php:39](../server/plugins/FamilyHub/Schema/NativeSchema.php#L39), records/operations; [DocumentsSchema.php:13](../server/plugins/FamilyHub/Schema/DocumentsSchema.php#L13), requests | Vsebinske kopije so tudi v operation in document receipts. | Sentinel inventar nad live/history/audit/replay/chunks/DATA/temp; M05. |

## 10 Strežniške finance, dokumenti in opravila

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [NativeOrganizationFinancePolicy.php:7](../server/plugins/FamilyHub/Model/NativeOrganizationFinancePolicy.php#L7), canonical parent | Projektni zapis uporablja en račun starša. | Prehod povezane finančne komponente, brez podvojene knjižbe; F01, M02. |
| [NativeOrganizationFinancePolicy.php:43](../server/plugins/FamilyHub/Model/NativeOrganizationFinancePolicy.php#L43), `accountChoices` | Dovoli name/currency/archived; zavrne opening balance in parent/sibling ledger. | Sanirana projekcija šifrirana za projekt; parent račun/ključ ostane zaseben; F02. |
| [NativeOrganizationFinancePolicy.php:65](../server/plugins/FamilyHub/Model/NativeOrganizationFinancePolicy.php#L65), `touchParents`; [ista datoteka:76](../server/plugins/FamilyHub/Model/NativeOrganizationFinancePolicy.php#L76), `contributionVisibility` | JSON reference določajo contributor ID/sequence; tudi izbris spremeni dokaz popolnosti. | Minimalen podpisan strukturni graf z enakim varovalom in brez uhajanja nedostopnih contributorjev; F01. |
| [NativeFinanceService.php:102](../server/plugins/FamilyHub/Model/NativeFinanceService.php#L102), audit; [ista datoteka:110](../server/plugins/FamilyHub/Model/NativeFinanceService.php#L110), pull | Audit before/after, accessRevision in completeness so ločene kopije podatkov. | Zgodovino šifrirati in preverjati, ne zgolj zamenjati glavni payload; M05. |
| [NativeFinanceService.php:136](../server/plugins/FamilyHub/Model/NativeFinanceService.php#L136), `reconcileTaskInTransaction` | Rok opravila spremeni plannedAt ali odklopi taskId; audit/sequence/notif v isti transakciji. | Eksplicitna podpisana namera z enakim atomskim rezultatom; F03, N01. |
| [NativeFinancePlanningPolicy.php:77](../server/plugins/FamilyHub/Model/NativeFinancePlanningPolicy.php#L77), task/rule omejitve; [ista datoteka:106](../server/plugins/FamilyHub/Model/NativeFinancePlanningPolicy.php#L106), `uniqueReference` | Unikatnost, mesečni učinek, valuta in children se preverjajo s SQL nad JSON. | Dogovorjen minimalni indeks/manifest in overjena klient validacija; F03–F05. |
| [NativeLinkedPaymentService.php:59](../server/plugins/FamilyHub/Model/NativeLinkedPaymentService.php#L59), `commit`; [ista datoteka:112](../server/plugins/FamilyHub/Model/NativeLinkedPaymentService.php#L112), `reimburse` | Bere kanonični strošek, znesek/valuto/plačnika; prepreči presežno povračilo. | Podpisan skupni izvorni dogodek, pregledana pravila vsote ter idempotentne noge; F04. |
| [NativeLinkedPaymentService.php:158](../server/plugins/FamilyHub/Model/NativeLinkedPaymentService.php#L158), private targets; [ista datoteka:247](../server/plugins/FamilyHub/Model/NativeLinkedPaymentService.php#L247), `writeProjection` | Odobritelj sproži posodobitev zasebnih ciljev, katerih ID sam ne prejme. | Zasebno projekcijo izpelje pooblaščena naprava plačnika; trajni pending/complete dokaz source revision; F04. |
| [NativeLinkedPaymentService.php:290](../server/plugins/FamilyHub/Model/NativeLinkedPaymentService.php#L290), `sourceRevisionChangedInTransaction` | Vsaka sprememba vira posodobi revizijo dogodka in zasebne projekcije, tudi brez novega povračila. | Overjeno dostavi novo source/payment revizijo tudi offline plačniku, brez novega denarnega učinka; F07. |
| [NativeTableService.php:8](../server/plugins/FamilyHub/Model/NativeTableService.php#L8), `execute`; [ista datoteka:101](../server/plugins/FamilyHub/Model/NativeTableService.php#L101), `derive` | Celotni dokument uporablja CAS in90s lease; HMAC žetona ni vsebinski ključ. | Ohraniti lock/expiry/renewal/CAS nad ovojnico; formule ostanejo na odjemalcu; D01. |
| [NativeTableService.php:66](../server/plugins/FamilyHub/Model/NativeTableService.php#L66), save; [ista datoteka:92](../server/plugins/FamilyHub/Model/NativeTableService.php#L92), `cells` | Naslov in celice se hranijo berljivo ter server preveri omejitve. | Šifriran manifest/celice; omejitve po odklepu in velikostni limiti šifropisa; D01. |
| [NativeAttachmentService.php:123](../server/plugins/FamilyHub/Model/NativeAttachmentService.php#L123), bytes/store; [ista datoteka:136](../server/plugins/FamilyHub/Model/NativeAttachmentService.php#L136), signature | Server hrani bajte ter preverja dejanski PDF/slikovni/Office format. | Ciphertext blokovna shramba; validacija plaintext formata pred šifriranjem/po odklepu na napravi; D02. |
| [NativeIdeaAssetService.php:66](../server/plugins/FamilyHub/Model/NativeIdeaAssetService.php#L66), path; [ista datoteka:68](../server/plugins/FamilyHub/Model/NativeIdeaAssetService.php#L68), `validateBytes` | Imena in reference uporabljajo plaintext sha256; server dekodira slike. | Opaque ID/hash šifropisa ter šifriran manifest; brez javnega plaintext hash indeksa; D02. |
| [NativeReminderService.php:64](../server/plugins/FamilyHub/Model/NativeReminderService.php#L64), `reconcile`; [ista datoteka:97](../server/plugins/FamilyHub/Model/NativeReminderService.php#L97), `runDue` | Iz vsebine izračuna rok in dostavo; target/fingerprint bereta zapis. | Podpisana minimalna namera časa/cilja, generična dostava in atomski preklic; N01. |
| [NativeNotificationWriter.php:30](../server/plugins/FamilyHub/Model/NativeNotificationWriter.php#L30), `insert`; [ista datoteka:47](../server/plugins/FamilyHub/Model/NativeNotificationWriter.php#L47), `recordChanged` | Inbox hrani reference/provenance; iz payload izpelje completion/assignee/project/list. | Ohraniti dedupe/read state in podpisane cilje; vsebinsko izpeljavo prestavi na dovoljeno napravo. |
| [NativePushWorker.php:19](../server/plugins/FamilyHub/Model/NativePushWorker.php#L19), dostava; [NativePushPresentation.php:12](../server/plugins/FamilyHub/Model/NativePushPresentation.php#L12), `topic` | Sveži ACL/preferences ostanejo pred dostavo, presentation bere ime prostora/naslov. | Generičen ping ali posebej pregledan prejemnikov šifrirani preview; N02, R08. |
| [NativeFcmTransport.php:43](../server/plugins/FamilyHub/Model/NativeFcmTransport.php#L43), payload; [NativeDeliveryService.php:66](../server/plugins/FamilyHub/Model/NativeDeliveryService.php#L66), SMTP | FCM display2 vključuje title/body; običajna inbox pošta že nima izvorne vsebine. | Preveri obe FCM poti; varnostna pošta brez skrivnosti ostane ločena od recovery datoteke; R08. |
| [NativeModerationService.php:80](../server/plugins/FamilyHub/Model/NativeModerationService.php#L80), preview | Moderatorju pripravlja berljivo dokazno vsebino. | Izrecni klientov predogled razkritja samo izbranega dokaza, ne ključa prostora; X01. |
| [NativeAccountDeletionService.php:177](../server/plugins/FamilyHub/Model/NativeAccountDeletionService.php#L177), `redact`; [ista datoteka:184](../server/plugins/FamilyHub/Model/NativeAccountDeletionService.php#L184), `applyShared` | Server redigira skupno plaintext vsebino in stare odzive. | Klientova priprava, strukturni tombstone in ohranitev skupnih finančnih dejstev/ovojnic drugih; X01. |
| [NativeScopeLifecycleService.php:94](../server/plugins/FamilyHub/Model/NativeScopeLifecycleService.php#L94), `graph`; [ista datoteka:105](../server/plugins/FamilyHub/Model/NativeScopeLifecycleService.php#L105), finance reference | Predogled izbrisa preverja tudi povezane finance/linked blockers in po commitu čisti datoteke. | Ohranjen verzioniran strukturni predogled, brez oživitve izbrisov ali izgube skupnih finančnih dejstev; X01. |

Posebej zahtevna ostaneta dva sedanja zaupanja vredna strežniška učinka:

- [NativeFinanceAccess.php:13](../server/plugins/FamilyHub/Model/NativeFinanceAccess.php#L13)
  ohranja ločene stare finance grante politik1/2. Urejevalec opravila zato
  lahko nima finance DEK, čeprav `reconcileTaskInTransaction` zdaj varno
  uskladi povezani strošek. Novi klientov batch ne sme tiho razkriti financ;
  potrebuje pregledano minimalno namero in pooblaščeno izpeljavo; F03, F06.
- [NativeReminderService.php:22](../server/plugins/FamilyHub/Model/NativeReminderService.php#L22)
  vrne samo opomnike trenutnega računa, `reconcile` pa uskladi vse čakajoče
  opomnike cilja. Drug urejevalec nima zasebnih ključev vseh prejemnikov.
  Potrebni so podpisani target-wide version/cancel podatki ali odložena
  prejemnikova izpeljava; samo premik obstoječe metode na klient ni dovolj; N03.

[reminders.php:9](../server/plugins/FamilyHub/cli/reminders.php#L9) v istem
cronu požene opomnike, moderacijski purge ter cleanup slik in prilog.
Migracijski fence mora ustaviti tudi te brisne učinke in samostojne cleanup
poti, ne samo dostavo obvestil; sicer končni inventar ni stabilen.

Strežnik brez zneskov ne more izvajati dosedanjega plaintext preverjanja vsote
povračil. Končni protokol mora določiti enakovredno preverjanje in karanteno
konkurentnih učinkov; UI ne sme predčasno pokazati popolne projekcije.

## 11 Strežniška kopija, obnova in namestitvena orodja

| Izvor in simbol | Trenutno vedenje | Predvideni poseg in merilo |
| --- | --- | --- |
| [backup.php:28](../server/scripts/upgrade-0.15.0/backup.php#L28), definicije/inventar; [ista datoteka:33](../server/scripts/upgrade-0.15.0/backup.php#L33), row hash | Zajame vse definicije in vrstice, SQL, DATA, source/config/cron/ključe ter dvojni inventar. | Novo verzionirano orodje za dejanski baseline in nove shrambe; B02. |
| [restore-verify.py:82](../server/scripts/upgrade-0.15.0/restore-verify.py#L82), izolirana obnova | Dejanski MariaDB import preveri tabele, tipe, vsako vrstico, CREATE in identitete. | Razširi na šifropise/key envelopes/blobs in čisto napravo s testno recovery datoteko. |
| [upgrade.php:70](../server/scripts/upgrade-0.15.0/upgrade.php#L70), proof guard; [ista datoteka:110](../server/scripts/upgrade-0.15.0/upgrade.php#L110), drain | Zahteva pravo restore proof, sveže ujemanje in65s praznjenje pred posegom. | E2EE priprava zahteva svoj stage/fence/CAS in preverjanje izgubljenega commit ACK; M01, B02. |
| [upgrade.php:119](../server/scripts/upgrade-0.15.0/upgrade.php#L119), release checkpoint | Loči HTTP release, workers in originalni cron. | Ohraniti točen cron in dokaz konca; brez skritih testnih dostav živim prejemnikom. |

To so zgodovinski pomagači za18→19/0.15.0 z vgrajenimi identitetami in hashi.
Niso pripravljeno orodje nove migracije in se ne uporabljajo neposredno na
produkciji. Obnova server šifropisov še ne dokaže obnove uporabniških ključev.
Stare plaintext kopije imajo ločen popis hrambe/upokojitve; M05, B02.

## 12 Obstoječe regresije za razširitev

| Testni izvor | Kaj že varuje | Nova povezava na merila |
| --- | --- | --- |
| [private_sync_repository_test.dart:70](../test/organizer/data/private_sync_repository_test.dart#L70) | Pravi Hive abort/retry/reopen, corrupt/newer input; atomarnost markerja in vrstic. | L02, L04, L05, L08; dodaj realni cipher target in vsak crash checkpoint. |
| [local_spaces_schema6_upgrade_test.dart:19](../test/organizer/data/local_spaces_schema6_upgrade_test.dart#L19) | Diskovna nadgradnja ohrani personal, gardens, private binding in immutable request. | L03, L05; dodaj vse schema10 tabele, BLOB, signed-out accounts in sequence. |
| [device_session_store_test.dart:65](../test/organizer/data/device_session_store_test.dart#L65) | Preverjen varen zapis; izgubljen write in nedosegljiv read brez plaintext fallbacka. | L04, L07; manjkajoč ključ ob ne-praznem vaultu nikoli ne resetira baze. |
| [durable_offline_access_test.dart:21](../test/organizer/data/durable_offline_access_test.dart#L21) | Trajno lokalno delo po nedosegljivem serverju. | L01, R05; obnova ne zahteva stare seje ali omrežja za lokalni vault. |
| [collaboration_documents_test.dart:346](../test/organizer/data/collaboration_documents_test.dart#L346) | Corrupt bytes in napačen target; pozni download po logout. | D01, D02, A03; dodaj block reorder/truncation/nonce/restart in draft ohranitev. |
| [organization_finance_client_test.dart:369](../test/organizer/data/organization_finance_client_test.dart#L369) | Finance4 projekcije, choices, contributor popolnost, backup in downgrade varovala. | F01, F02, M02; preveri kriptografski obseg brez parent/sibling ključev. |
| [collaboration_task_cost_actions.dart:112](../lib/organizer/data/collaboration_task_cost_actions.dart#L112) in [planning_task_cost_test.dart](../test/organizer/data/planning_task_cost_test.dart) | Točna para outbox operacij in task-cost integracija. | F03, M03; izgubljen ACK in konflikt enega dela brez novega opId. |
| [linked_payments_repository_test.dart](../test/organizer/data/linked_payments_repository_test.dart), [finance_planning_test.dart](../test/organizer/data/finance_planning_test.dart) | Povezave cash/projekcij in ponovljivi mesečni učinki. | F04, F05; konkurenca naprav brez server plaintext zneskov. |
| [portable_backup_repository_test.dart:62](../test/organizer/data/portable_backup_repository_test.dart#L62), [portable_backup_validation_test.dart](../test/organizer/data/portable_backup_validation_test.dart) | Prenosne kopije in stroga validacija. | B01; stare1–8 in eksplicitne odvisnosti ključev, brez uvoza pravic. |
| [backup_preferences_replay_ui_test.dart](../test/organizer/ui/backup_preferences_replay_ui_test.dart), [backup_ui_preferences_test.dart](../test/organizer/platform/backup_ui_preferences_test.dart) | SQL commit in kasnejši ponovljivi preference replay. | L02, L08; replay ne odpre nešifrirane baze mimo bootstrapa. |
| [invitation_wizard_test.dart](../test/organizer/ui/invitation_wizard_test.dart), [invitation_link_storage_race_test.dart](../test/organizer/platform/invitation_links/invitation_link_storage_race_test.dart) | Ločeni koraki in varna serializacija povezav. | A02, A03, S04; reset/recovery/restart z istim izvorom in izrecnim Join. |
| [backup_file_io_test.dart](../test/organizer/ui/backup_file_io_test.dart), [attachment_file_io_test.dart](../test/organizer/ui/attachment_file_io_test.dart) | Save/cancel/bounded reads platformnih adapterjev. | R01–R03, R08; nova recovery datoteka in resnični zunanji ponovni uvoz. |
| [account-integration.php:30](../server/tests/account-integration.php#L30), [email-invitation-integration.php:27](../server/tests/email-invitation-integration.php#L27) | Verification/reset stabilne identitete, TOTP, paralelni sprejem in registracija brez članstva. | A01, A02, R04/R05; recovery nikoli ne obide TOTP ali ustvari drugega accountId. |
| [organization-finance-integration.php:31](../server/tests/organization-finance-integration.php#L31) | Sanirane choices, replay, contributor fence in zadnji odstranjen contributor. | F01–F03, M02; enake meje po odklepu vseh potrebnih manifestov. |
| [linked-payments-integration.php:31](../server/tests/linked-payments-integration.php#L31) | Replay commit/refund, brez dvojnega parent stroška, over-refund zavrnitev. | F04; pravila ostanejo preverljiva pri konkurenci in odloženih zasebnih projekcijah. |
| [documents-integration.php](../server/tests/documents-integration.php), [combined-sharing-documents-integration.php](../server/tests/combined-sharing-documents-integration.php), [ideas-integration.php](../server/tests/ideas-integration.php) | Pravi lease/chunks/CAS/revoke in slikovne reference. | D01, D02; ciphertext integriteta ne sme oslabiti ciljnih ACL. |
| [relative-reminder-ideas6-integration.php:20](../server/tests/relative-reminder-ideas6-integration.php#L20) | Izpeljava roka, sprememba datuma in brez dvojne dostave. | N01, N02; nove minimalne namere ohranijo vse prejemnike in preklice. |
| [deletion-integration.php:39](../server/tests/deletion-integration.php#L39), [scope-lifecycle-integration.php:38](../server/tests/scope-lifecycle-integration.php#L38) | Skupni graf, audit/replay redakcija, trajni cleanup, replay in stale predogled. | X01, M04/M05; po E2EE poštena strukturna namesto nemogoče plaintext redakcije. |

Za prihodnjo izdajo so poleg enotskih regresij obvezni fizična posodobitev
Android31 brez odstranitve, zaklenjen/odklenjen telefon, backup/transfer in
obnova na čisti drugi napravi. Izvorni test ni dokaz izdane native knjižnice.
Strežniške kontrole potrebujejo SQLite/MariaDB/MySQL, stare odjemalce,
neznani ACK, izolirano obnovo in iskanje sentinel vsebine v vseh kopijah.
Dokument ne dovoljuje namestitve, novih gradenj ali trgovinske oddaje.
