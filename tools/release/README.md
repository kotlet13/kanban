# Offline Jivie release preparation checks

Run from the repository root with Python 3.9 or later (standard library only):

```sh
python3 tools/release/check_readiness.py --code-only
python3 -m unittest discover -s tools/release -v
python3 -m unittest discover -s tools/firebase -v
```

Source checks cover Android/iOS application identities and labels, localized app name, current release `1.1.3+6`, SL/EN listing length limits, Android API 36+, separate Jivie release signing input/guard, debug signing fallback, Android mipmap sizes and the iOS icon catalog. Icons must be real, complete PNGs with valid CRCs/pixels, declared dimensions and multiple colors; iOS icons must be fully opaque. The tool accepts 8-bit noninterlaced RGB/RGBA/gray/palette PNGs. It cannot verify visual quality, trademark clearance, old-icon similarity, generated native manifests or signed binaries. A source pass is not release readiness.

For the full public checklist, copy `release_inputs.example.json` outside the repo (for example into the ignored `build/qa/jivie/` directory), fill the three real public HTTPS URLs, set only genuinely verified attestations to `true`, and choose whether this build includes remote push. Never add passwords, signing values, private keys, service-account JSON, reviewer credentials or production data to that file.

```sh
python3 tools/release/check_readiness.py \
  --platform all \
  --inputs build/qa/jivie/release_inputs.json
```

`--platform android` or `--platform ios` selects platform-specific **release attestations**; source checks still cover both mobile platforms. `--root /path/to/fixture` supports isolated tests. Exit 0 means the requested source checks and supplied attestations passed, exit 1 means incomplete preparation. Unknown checklist fields are rejected and neither URL values nor parsing errors are echoed. Placeholder/example/local/credential-bearing URLs fail syntax checks; actual accessibility and ownership must be checked separately.

The checker only tests existence of `android/jivie-key.properties` and, when push is selected, the public Firebase outputs. It never opens those files, old Android signing inputs, certificates, keystores, APNs keys or server credentials. Actual Android Gradle validates the Jivie signing properties when a release build is requested. Evidence booleans are manually recorded facts, not independently verified by this script. No build, network, upload, signing or store account operation is performed.

The full checker intentionally fails until the missing product/external work is verified: account deletion, public privacy/support/deletion pages, controller/store identity, review access, screenshots, physical-device backup/local/server flows, Android signing/AAB/16 KiB checks, iOS archive/signing/SDK/privacy report and, if selected, genuine Firebase/APNs physical delivery. If remote push is disabled for a candidate, its store description/UI must say so; disabling the checklist requirement is not proof that an enabled channel works. See [readiness](../../docs/release/READINESS.md) and [privacy inventory](../../docs/release/PRIVACY_AND_DATA_SAFETY.md).

Flutter validation is coordinated separately. The prior project baseline contains 35 informational lints in legacy screens; plain `flutter analyze` therefore exits 1. Record those honestly, and additionally use `flutter analyze --no-fatal-infos` to confirm no warning/error is hidden. Do not suppress warnings/errors or call this a fully clean analysis. Source checks do not run or replace behavior tests.

## Static website package

`python3 tools/release/package_website.py` creates `build/releases/jivie-website.zip` from `website/public/`, with `index.html` in the ZIP root for cPanel. It includes only static extensions plus `.htaccess`, rejects hidden/config/backup/credential files and symlinks, bounds file/package sizes and never replaces an existing archive. Eight negative/positive package tests are included in the release unittest discovery. The source ZIP is local preparation, not publication or proof of live policy URLs. See [website workflow](../../website/README.md).

`node tools/release/test_deletion_link.mjs` exercises the production static deletion-page link builder without network. It verifies same HTTPS origin/subpath, rejection of credentials/query/fragment/HTTP/script addresses and removal of an old link when the input changes. This is not a live server deletion test.
