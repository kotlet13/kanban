# Test2-only moderation upgrade

The guarded CLI helper is the exact source used for the verified 0.11.2/schema15 to 0.12.0/schema16 upgrade. It is pinned to the named test2 site, config, serverId and immutable source package. See [the deployment evidence](../../../docs/release/MODERATION_RELEASE.md).

This is a completed one-time migration helper, not a generic or recurring updater. Do not rerun it on schema16, weaken its guards, or reuse a stale backup/proof. It contains no credentials or production data. Hosting inputs, original code, state and backups remain private.
