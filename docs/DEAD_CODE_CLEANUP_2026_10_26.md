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

## Ohranitev in omejitve

C11 (aktivna v1 alternativa), S3 (javni PHP helper/zunanji uporabniki), S4/S5
(nedosegljivi varovalni veji z nejasnim namenom) niso avtomatično dovoljenje
za brisanje. Združljivostne kode, migracij, tabel, podpisov, receiptov in
starih formatov ne odstranjujemo. Aktivni `_syncNow` ostane.
