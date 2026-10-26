# Odstranjevanje potrjene mrtve kode — 26. oktober 2026

Izhodišče: produktna koda `65373c0`, pregleda `cfb10fc` in `ed2326d`.
Uporabnik naroča postopno brisanje, preverjanje vsakega dela brez GUI in
commit + push po vsakem uspešno preverjenem delu. ID-ji so iz
[izvornega pregleda](DEAD_CODE_REVIEW_2026_10_26.md).

Vsak spodnji sklop je ločen commit. Git zgodovina tega dokumenta pokaže
njegov commit; staro stanje je mogoče obnoviti z revert posameznega commita.
Pri vsakem koraku preverimo tudi push. PHP integracije uporabljajo dejanski
API dispatcher, sodium in svežo SQLite bazo v začasnem Docker vsebniku:
`--network none`, read-only source/config, tmpfs data, brez objavljenih portov.
To je backend integracija, ne HTTP/native end-to-end dokaz. Dart kontrole
so headless; ne zaganjajo uporabnikovih aplikacij. Obstoječe baze in produkcija
ostanejo nedotaknjene. Izidi in ukazi so v `build/qa/dead-code-cleanup-20261026/`.

## Dnevnik zaključenih sklopov

### S2 — neklican zasebni integer validator migracije povabil

- Odstranjena samo metoda `NativeCryptoMigrationInvitationStageV3::integer`.
  Aktivni validatorji, staging, frozen mail evidence in migracijska pogodba ostanejo.
- Backend: `crypto-invitation-migration-stage-v3.php`, **PASS, 61 kumulativnih kontrol**.
- Poskus1: fixture FAIL `crypto_unavailable`, ker je bil uporabljen splošni
  dev-config brez crypto preview. Poskus2 uporablja obstoječi crypto-test-config,
  PASS. Produktnega varovala nismo spreminjali. Dokaza `S2.log`, `S2-attempt2.log`.

### S1 — neklican zasebni primerjalnik inline deletion

- Odstranjen samo `NativeCryptoInlineDeletionV2::same`; vse veje in varovala ostanejo.
- Nov ciljni backend test `crypto-inline-deletion-preview-regression.php`:
  podpisan projekt+opravilo, nepovezano opravilo, natančen graf/števci,
  ponovljiv read-only preview, zavrnitev zamenjave canonical/wire ID,
  nespremenjeni zapisi in brez ustvarjenega deletion plana.
- **PASS, 43 kumulativnih kontrol** (37 fixture + 6 novih), prvi poskus, `S1.log`.

### C4-C5 — Remove unused crypto business router wrappers

Odstranjena samo managerEnsure in reminderStateFor. Aktivna ensurePersonal in notranja priprava reminder metapodatkov ostaneta. Backend crypto2-notification-integration.php: PASS 71; headless crypto_business_finance_test + crypto_business_payload_test: PASS 4. Analiza routerja: 0 napak/opozoril, 11 obstoječih slogovnih informacij. Dokazi C4-C5-*.log. To niso novi mobilni testi.

### C6-C8 — Remove unused scope verification convenience methods

Odstranjeni verifyDeletedScopeHead, verifiedCandidateDescriptor in verifyProjectRelocation; aktivni withVerifiedDeletedScope, withRecoveryCandidatePolicy in recordAuthority dispatch ostanejo. Backend crypto-scope-deletion-v2.php: PASS 94. Headless crypto_scope_forward_author_test + crypto_project_relocation_graph_test: PASS (C6-C8-dart.log). Analiza: brez napak/opozoril; samo obstoječe slogovne informacije. Nobenih sprememb shranjenih dokazov ali ključev.

### C2 — Remove unused unverified directory operation index reader

Odstranjen samo operationEntries; verifiedOperationEntries in SQL tabela ostaneta. Headless crypto_migration_own_attestation_test preveri dokazno verigo in manipuliran indeks: PASS. Backend crypto-migration-generation-prefix-v3.php: PASS 57 kumulativnih kontrol. Analiza identity store: 0 napak/opozoril, 4 obstoječe slogovne informacije. Dokazi C2-*.log; brez brisanja uporabniških tabel.

### C1 — Remove orphaned migration parity v2 implementation

Odstranjena nepovezana datoteka crypto_migration_business_parity.dart, brez produkcijskih/testnih uvozov. Aktivni v3 codec ostane. Dart crypto_migration_business_parity_v3_test PASS in PHP crypto-business-parity-v3-vectors PASS 23 na istih neodvisnih vektorjih. Analiza aktivnih migration callerjev brez napak/opozoril. To ne odstranjuje nobenega shranjenega formata in ni nova celotna migracija. Dokazi C1-*.log.

### C3 — Remove unused combined captured finance selection builder

Odstranjena samo buildCapturedSelection in njun edini verifier verifyCapturedSelection. Aktivni issuer deriveSourceSelection/verifySourceSelection, recipient verifyTargetSelection in skupni validate ostanejo. Analiza vseh treh aktivnih datotek: 0 issues. Backend selection propose regression na sveži SQLite: PASS 9 (pravi dispatcher, prazen/neprazen izbor, vezava izvornih pozicij/replay); headless parent projection: PASS 8. Kontrole ne predstavljajo novega celotnega migration/cutover testa. Dokazi C3-*.log.

### C9 — Remove unused migration generation publish wrapper

Odstranjen samo CryptoMigrationGeneration.publishDraft. Aktivni pipeline še neposredno kliče ScopeCryptoManager.publishMigrationGenerationDraft. Headless superseded setup regression: PASS 1; backend crypto-migration-receipts-v3.php: PASS 9; analiza generation/pipeline: 0 issues. Dokazi C9-*.log; ni spremembe receipt/generation protokola.

### C10 — STOP3; izbris razveljavljen, original ohranjen

- Poskus odstranitve resumeAll ni objavljen. Dart inherited-invitation test:
  poskus1 7 PASS/28 FAIL (zastarel fake authorityReuse); poskus2 samo28 padlih,
  FAIL (manjkajoče retained/snapshot metode). Poskus3 dopolni samo fake in
  ponovi padle: 14 PASS/14 FAIL (fake nima transport getterja). Brez četrtega teka.
- Izbris in začasne fixture spremembe sta vrnjena točno na HEAD; patch/dnevniki
  ostanejo v C10-* dokazih. Ni sprememb produkcijskih varoval zaradi testa.
- Backend notification terminal seam: poskus1 fixture autoload path FAIL,
  poskus2 po pravilnem mountu PASS6. To je memory SQL seam, ne API/signature
  dispatch test. Ni zadosten dokaz za dokončanje C10; najprej popraviti star
  testni model skladno s trenutno admission pogodbo v ločenem koraku.

### U1 — Remove obsolete public card dialog and test active contact screen

Odstranjen nepovezan crypto_public_card_dialog in njegov test. Prenesena smiselna keyboard/back/success/failure kontrola na dejanski ContactIdentityVerificationPage: PASS 6 za Android/iOS teme brez naprav. Test preverja exact scope/account/card delegacijo; kriptografski verifier ni mock testa pretvorjen v produkcijsko izjemo. Backend origin/author integration: PASS 51. Dokazi U1-*.log. Zapisan tudi STOP3 C10; ta izbris ni del commita.

### U2 — Remove legacy reminder settings and exercise current preferences

Odstranjen samo DeviceReminderSettings. Njegov uporabni test lifetime koordinatorja prevezan na dejanski InboxPreferencesScrollView: PASS1; po zaprtju nastavitve callback ostane pravilen. Lokalna v1 preference migracija ohranjena. Backend reminder archive: poskus1 fixture email_verification_required, poskus2 po dopolnitvi sintetičnega lastnika z verified email in sprejetimi pravili PASS4. Produktni guardi isti; dokazi U2-*.log.

### U3 — Remove obsolete shared today view and test current Utrip projection

Odstranjen SharedTodayOverview. Test archive/unarchive prenesen na OrganizerUtripOverview + dejanski projectAllSpaces in provider spremembe: PASS1 v poskusu2; poskus1 fixture je prezgodaj bral requireValue v AsyncLoading, popravljeno samo v testu. Obstoječi SharedAgendaPage history test ostane nespremenjen. Backend account-changes-metadata: PASS19 (memory SQL, scope selection/access/deletion hints, brez HTTP/proof verifikacije). Dokazi U3-*.log.

## Ohranitev in omejitve

C11 (aktivna v1 alternativa), S3 (javni PHP helper/zunanji uporabniki), S4/S5
(nedosegljivi varovalni veji z nejasnim namenom) niso avtomatično dovoljenje
za brisanje. Združljivostne kode, migracij, tabel, podpisov, receiptov in
starih formatov ne odstranjujemo. Aktivni `_syncNow` ostane.
