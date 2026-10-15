# Sound default: guarded code-only correction

This helper installs only `Model/NativePushWorker.php`,
`Model/NativeNotificationPreferences.php` and `Plugin.php`. It changes missing
sound defaults/fallbacks to true and the plugin version to0.14.1. It does not
change a stored preference, schema, queue row, cron, HTTP configuration or key.
Existing explicit false/true values remain byte-identical. No application or
worker is bootstrapped. PHP token parsing validates every staged PHP file.

The exact old installed101-file manifest comes from
`FamilyHub-0.14.0-upgrade-20261014.zip`, SHA256
`e6fda75ac4b63c74f70cd2ac00fb6143006cbe111a96a8462e30db9a945a3743`.
It is independent of the public repository's extra NOTICE file. The new installed
manifest is exactly that baseline with only those three PHP hashes replaced;
public documentation changes are not copied into this live patch.

Only production and test1 have fixed profiles. Put `capture.php`, `common.php`
and `old-manifest.json` in a fresh private0700 directory outside document roots.
Keep output in that subdirectory, not at the private BASE root, whose existing
configuration/key files are themselves pinned. Capture requires actual
MariaDB10.11.19/schema18 and the correct serverId, old101 source, native/self_hosted
configuration, all included/root-private config/key hashes, data/core metadata,
all table counts/CREATE hashes, identity/account/device row hashes, and a raw
serialized preference-row hash. It takes short READ locks on every table; no SQL
rows or definitions are written.

Example production, after uploading those three capture files to the fixed WORK:

```sh
umask 077
/bin/crontab -l > WORK/cron.capture
/opt/alt/php84/usr/bin/php WORK/capture.php production WORK/cron.capture > WORK/capture.json
```

Use `test1` for `/home/tripar13/private/jivie-test/...`. Privately retrieve that
small hash-only capture. Prepare locally, after the root agent's Plugin version
change:

```sh
python3 server/scripts/sound-default-0.14.1/prepare.py /PRIVATE/capture.json /PRIVATE/sealed-production --host-work /home/tripar13/private/jivie-production/sound-default-0.14.1-20261015-065330
```

The output directory must be fresh0700 and outside Git. The sealer accepts only
the two reviewed false→true line changes and exact Plugin0.14.0→0.14.1 change.
It refuses different PHP edits or the wrong immutable old archive. Upload the
sealed output to its exact `hostWork`,0600 files/0700 directories, preserving
any existing capture files. Then:

```sh
sh WORK/run.sh WORK check
sh WORK/run.sh WORK apply
```

Both operations require a newly read exact original cron, fresh sealed capture,
unchanged all-table counts/CREATE, identities/passwords/devices, raw preference
bytes, data/core files and metadata, and configs/keys. A legitimate concurrent
write causes a refusal and requires a new capture; guards are not relaxed and
crons are not stopped or changed. All-table READ locks include the preference
table and remain held through the brief file replacements and post-checks.

Apply first retains an exact101-file old source copy in private
`WORK/FamilyHub.before` with0700 directories/0600 files. It stages the three
replacement files with original public modes/ownership, then replaces worker,
resolver and Plugin with individually atomic renames (Plugin last). A private
intent precedes replacements; final `patch-checkpoint.json` exists only after
new101 and all preservation guards pass. Old source, captures, backups and
checkpoints remain private. A partial failure is retained for review; do not
blindly retry, delete the intent or bypass checks. Existing production data
backups remain unchanged; this code-only operation has no DDL migration.

The previous0.11.x verifier scripts retain their version/path/schema pins and
explicit-opt-out checks; their expected missing-sound default is now true at the
user's request. They are not substitutes for this schema18 patch helper.
