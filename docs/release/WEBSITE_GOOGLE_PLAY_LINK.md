# Google Play download links — 14 October 2026

Published on [jivie.app](https://jivie.app/) and its English version at the
user's request. Both home pages have a primary Android download button in
the hero and another Google Play button in the closing section. All eight
HTML pages have a Google Play footer link. The shared generator uses:

`https://play.google.com/store/apps/details?id=si.triparna.jivie`

Availability text and home-page metadata now state that Android is publicly
available in Slovenia; iOS remains in preparation. The main content of the
six help/privacy/deletion pages is byte-identical to the previous content.

## Deployment

The existing cPanel account `jivie` and document root
`/home/jivie/public_html` were confirmed. Normal saved-password autofill was
used; no password was read or exported. Before replacement, the complete
site was backed up privately and all 25 archived files were compared with
their original hashes, permissions and ownership.

- Private directory: `/home/jivie/private/website-google-play-20261014`
- Backup: `before-public_html.tar.gz`
- Backup SHA256: `2c187c0c51bac287ad8870df0e0ad6dca2f58f73752ce65f312e6670a0daaa82`
- Reviewed deployment helper SHA256:
  `341cc3a617bcb81c2cac14bf26aac92261ca98f0971c1694f56889d241aa9642`
- Eight HTML files atomically replaced with original permissions/ownership.
- Seventeen other files preserved, including images, CSS, scripts, PHP and
  hosting configuration. DNS/HTTPS settings were not changed.
- Host-side `deployment.json` confirms publication, verified backup and
  preserved permissions/owners. Helper and backup remain outside the public root.

## Verification

All eight public HTML URLs return HTTPS200 and exactly match the regenerated
source hashes. Each home page has three Play links; each other page has one.
Slovenian 390-pixel and English 320-pixel previews have no horizontal overflow.
The live Slovenian hero was visually verified and its actual download link
clicked: it opens **Jivie**, publisher **TaknDevs**, with **Namesti** on Google
Play. The destination shows the 14 October update and version26 connection
fix notes. No installation or store/account changes were made.

Evidence under `build/qa/website-google-play-20261014/`:
`before.json`, `payload.json`, `live-verification.json`,
`deployment-terminal.png`, `website-live-sl.png`, `preview-mobile-sl.png`
and `preview-mobile-en.png`.

Android1.7.1(26)/AAB, Play Console, iOS, FamilyHub installations and user data
are unchanged. The public-only Android release policy remains in force;
the internal testing channel remains inactive.
