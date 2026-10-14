# Production SMTP configuration

These scripts target only the reviewed 14 October 2026 installation at
`/home/tripar13/jivie.triparna.si`, with private configuration under
`/home/tripar13/private/jivie-production`. They are not a general installer
and must not be used against test1/test2 or a different feature configuration.
The feature baseline hash is checked before any preparation writes.

`setup.py check` reads metadata/state. `setup.py prepare` preserves protected
copies of core configuration, feature configuration and the entire crontab,
generates a separate 32-byte account-mail encryption key and stages SMTP
configuration. It creates an empty protected password file; SMTP stays off.
All private directories are 0700 and files are 0600. The password is supplied
directly by the owner via a hidden terminal prompt, never via chat or Git.

`probe.php auth` uses the installed Kanboard Swift dependency and FamilyHub's
existing verified SMTP transport to authenticate against
`cp-21.controlpanel.si:465` with verified TLS as `admin@jivie.triparna.si`.
It does not bootstrap the app, alter the database or send mail. Its private
proof binds the checked configuration and password file metadata.

`setup.py activate` requires that proof, unchanged staged files and unchanged
original crontab. It adds only two minute workers, `account-mail.php` and
`delivery.php`, preserving every original cron entry. It then atomically
activates the feature configuration's SMTP include. Each worker has its own
`flock` lock and protected log. SMTP sets the canonical invitation URL to
`https://jivie.triparna.si/`. No plugin code, schema or account is changed.

`probe.php test <recipient>` sends one benign SMTP test only after activation.
Use it only for an explicitly authorized recipient. It claims a private
test marker before SMTP, so an ambiguous result cannot cause an automatic
duplicate. SMTP acceptance and actual mailbox receipt are separate evidence.

The preparation is intentionally exclusive. Existing destinations, changed
configuration/cron, or partial activation stop for manual review; never remove
markers or run another preparation to bypass guards. After a partial activation,
inspect the protected before/candidate files and current crontab before deciding
on recovery. Do not restore the entire old crontab over later independent edits.
Do not delete or regenerate the mail encryption key: pending ciphertext depends
on it. Include it, the SMTP password/configuration and current data in regular
protected server backups; preparation copies are configuration snapshots only.

Local guard verification: `python3 server/tests/production-mail-setup-test.py`.
Seven checks cover wrong baseline, existing key, staged preservation, missing
password, changed crontab/candidate and activation/replay. SMTP/provider evidence
is recorded separately in [the production mail report](../../../docs/server/PRODUCTION_MAIL.md).
