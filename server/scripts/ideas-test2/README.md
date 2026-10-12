# Test2-only Idejnik upgrade (0.12.0/schema16 → 0.13.0/schema17)

These are guarded, one-time CLI helpers for `/home/tripar13/jivie-test2.triparna.si`, private base `/home/tripar13/private/jivie-test2`, serverId `f48b41ae-c6bb-4f2d-ae13-0aa7fa255993`, the existing pinned private configuration and exact 91→96-file source manifests. They contain no credentials. Hosting operations are performed separately by the root agent; preparing or testing these files is not deployment evidence.

Keep the directory `/home/tripar13/private/jivie-test2/upgrade-0.13.0` at mode700 and all uploaded inputs at mode600. Upload `backup-test2.php` and `source-manifests.json` first. Both helpers positively encode/decode PNG/JPEG through GD and refuse a missing codec, a different configuration, another server identity, another schema or mismatched source.

Create the **fresh schema16 full backup** with:

```sh
php /home/tripar13/private/jivie-test2/upgrade-0.13.0/backup-test2.php --check
php /home/tripar13/private/jivie-test2/upgrade-0.13.0/backup-test2.php --export
```

Export includes every InnoDB table, exact CREATE definitions, all rows, the private configuration, root configuration/HTTPS file, enabled marker and the complete private DATA tree, including empty directories. Read locks and matching source/copied inventories reject concurrent changes. No application/worker is bootstrapped; no SQL rows, marker, cron, SMTP or FCM settings are changed. The archive lives in a fresh private `backups/ideas-preupgrade-20261012-...` directory. It uses `test2-ideas-preupgrade-backup-v1` and refuses schema15 or schema17; earlier helpers/proofs cannot substitute for this export.

Download the reported archive privately and verify its reported SHA. Restore it using `restore-verify.py` into a **fresh MariaDB10.11.19 container with network=none, no ports, no host bind mounts and only its anonymous MySQL volume**. The verifier refuses a nonempty database server, unsafe archive members, wrong schema/identity and any row/CREATE/file/config/marker hash mismatch. It starts no PHP application or delivery worker. It produces the fresh schema16-only `test2-ideas-preupgrade-restore-proof-v1` proof.

Then upload `upgrade-test2.php`, `FamilyHub-0.13.0-source.zip` (frozen SHA `00df4cec3baebb66d4e67adad20c235149529b2ee9853b614b0a74ef85cfbe52`) and that exact `restore-proof.json`. Run `--check`; run `--stage` with the exact private archive path and SHA. Staging requires every current row/file to match the actually restored backup, which must be less than six hours old. `--pause SHA` retains the existing native marker privately; wait **at least 65 actual seconds** before `--apply SHA`. The helper adds precisely two empty asset tables, preserves every old row/definition/identity/config/data/core file, updates only FamilyHub's schema version16→17, and retains both original code copies. `--verify SHA` must succeed while still paused before `--release SHA` restores the exact enabled marker. After release these one-time upgrade/backup helpers are not schema17 backup utilities and must not be rerun or weakened.

The helper does not call crontab. Capture/compare the actual hosted crontab hash separately. Preserve all private inputs, backups, proof, state, original code, checkpoints and paused marker if any operation fails; do not release or retry blindly.

`mock-upgrade-test.py` exercises an actual nonempty complete Kanboard/MariaDB10.11.19 fixture, full export/isolated restore and guarded upgrade/source swap. Only fixture configuration SHA pins are substituted; the production paths, package/manifest/identity pins and guards are unchanged. The fixture tests premature apply before advancing its **fixture-only paused timestamp**; hosting still needs the actual 65-second wait. Eleven negative guards cover unavailable GD, old schema15, another serverId, old15 restore proof, corrupt package, wrong restored archive, changed live row, wrong backup SHA, early apply and rerun after release. Evidence remains in `build/qa/jivie-ideas-test2-upgrade`; private fixture archives remain outside the repository. No existing backup containers are stopped.
