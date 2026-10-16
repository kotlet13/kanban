# Reviewed public FamilyHub source package

Run from repository root:

```sh
python3 -m unittest discover -s tools/plugin_release -v
python3 tools/plugin_release/package_source.py --output build/release/FamilyHub-source.zip
```

The current reviewed distribution is FamilyHub0.15.0/schema19. Its allowlist includes the five reviewed documents modules (DOCUMENTS_API.md, three document services and DocumentsSchema.php). The source-only ZIP contains a top-level `FamilyHub/` directory. It replaces the development README with the reviewed self-contained `PUBLIC_README.md` (renamed `FamilyHub/README.md`); PHP source is copied unchanged. The existing public MIT/dependency notice is preserved byte-for-byte from reviewed PUBLIC_NOTICE.md as NOTICE.md; no third-party code is added. An explicitly allowlisted public deletion contract is copied to `FamilyHub/docs/account-deletion-contract.md`; application docs are not copied recursively. Installation, configuration, native endpoint, self-hosted deletion, delivery/cron and rollback instructions do not depend on the private app repository. Extract its contents into a fresh standalone repository if later authorized. The tool does not create a repository or contact GitHub. This is not the full application's source archive or an export of this repository's history.

`source_manifest.json` explicitly lists reviewed plugin paths. Every file must match; extra files, missing files, symlinks, nonregular files, oversized files and obvious private-key/service-account/token content fail before artifact creation. It requires a confirmed MIT LICENSE and refuses draft/contributors placeholders. The output cannot be within the source tree; existing ZIP/checksum files are never overwritten. Archives are deterministic with fixed timestamps and file permissions.

Review a changed manifest and every included file before packaging. Secret heuristics cannot certify absence of all credentials, customer data or copied third-party code. Do not add production configuration, backup, SQL, logs, local credentials, test accounts, vendor code or Git history to the manifest. See [license and publication review](../../docs/PLUGIN_OPEN_SOURCE.md).
