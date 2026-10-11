# Priprava prve javne izdaje brez AI — 11. oktober 2026

Nadaljnji uporabnikov korak je odstranil tudi preostali stari vmesnik in open_filex;
[zaključni dokazi](LEGACY_INTERFACE_REMOVAL.md) imajo prednost za trenutno kodo.
Spodaj ostaja dokaz prejšnjega preverjevalnega AAB pred to dokončno odstranitvijo.

Uporabnik je naročil odstranitev starega AI, nepotrebnih Android dovoljenj in
uskladitev spletne zasebnosti. Izvor je popravljen in zasebnost objavljena.
Nameščena interna 1.3.2 (17) ostaja prejšnja gradnja; trgovinska izdaja,
commit/push in zvišanje različice niso del tega koraka.

## Aplikacija in podatki

Odstranjene so nastavitve AI, projektni klepet, pomoč pri naslovu/opisu opravila,
telefonske/namizne menijske možnosti ter neposredni poti `/settings/ai` in
`/board/:projectId/ai-chat`. Odstranjenih je devet Dart knjižnic (štiri AI, dva
zaslona, tri shrambe), sedem providerjev, transport OpenAI in dve Kanboard API
metodi za AI politiko z njenimi ključi. 50 SL/EN ključev je odstranjenih, lokalizacije
so regenerirane. Telefonski test starega board menija je razkril 5 px preliv
statistične oznake; minimalni `Flexible` prepreči preliv.

Ob nadgradnji se stare lokalne zgodovine, nastavitve in ključi ne berejo za uporabo,
ne brišejo ali nalagajo. Ostane samo `legacy_account_cleanup.dart`, ki ohrani
prejšnje izrecno čiščenje zgodovine/soglasij odjavljenega starega računa, brez
drugih računov, globalne zgodovine, nastavitev ali ključev.

## Android in preverjanje

Glavni manifest s `tools:node="remove"` izključi `READ_EXTERNAL_STORAGE`,
`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` iz open_filex.
Priponke se že odpirajo iz zasebne začasne mape prek FileProvider; pregled native
`pathRequiresPermission()` potrjuje to pot brez skupnega dostopa. Odvisnosti/SDK
in izbirnik datotek so ohranjeni. Končni manifest iz dejanskega AAB potrdi odsotnost
vseh širokih storage/media dovoljenj. INTERNET, ACCESS_NETWORK_STATE,
POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK, RECEIVE_BOOT_COMPLETED, FCM RECEIVE in
zaščiteno receiver dovoljenje ostanejo. FileProvider ohrani `exported=false` in
`grantUriPermissions=true`.

Preverjevalni podpisani AAB:
`build/qa/no-ai-first-release/Jivie-no-ai-validation-1.3.2+17.aab`,
78.949.284 bajtov, SHA256
`30c6cb6f2158b1225502128032358ed594578bb0d41648c0f0afba62eb6aaa5d`.
To je lokalni dokaz pod isto različico, **ni nova Play kandidatka za oddajo**.
Originalni izdani AAB je ohranjen. 263 Dart/ARB/manifest/odvisnostnih hashov je
shranjenih ob artefaktu; omejeni inventar ni popoln izdajni manifest.
Bundletool validate in jarsigner verify PASS; jarsigner poroča pričakovani self-signed
certifikat brez javne CA verige/časovnega žiga, ne store odobritve.
Endpoint `api.openai.com` ni v nobenem zgrajenem `libapp.so`.

- Celoten sklop: 972 Flutter PASS / 13 opt-in HTTP preskočenih.
- Ciljni sklop: 31 PASS za zavrnjene stare routes pri `ai_enabled=true`, Apple/Android
  menije, normalni task create/edit prek KanboardApi/JsonRpcClient ter ohranitev
  podatkov/ključev, scoped logout in Android Nazaj.
- Končna analiza podagenta: nič napak/opozoril, 31 podedovanih info (štirje prejšnji
  info so bili v odstranjeni kodi).
- 23 Python izdajnih/paketnih testov, source checker, JS deletion-link,
  `git diff --check`, release gradnja in dekodirani manifest PASS.
- Novi `tools/release/check_android_permissions.py` zavrne široka dovoljenja,
  tudi SDK omejene/SDK23 variante, in ne sprejme nezdruženih izvornih direktiv.

## Spletna objava in preostale meje

Po uporabnikovi korekciji objavljena SL/EN politika opisuje podatkovne poti prve
izdaje; odstavek o AI in razvojnih/internih različicah je v celoti odstranjen.
`support@jivie.app` ostane; uporabnik potrdi
delujoč predal. Opisi sodelovanja, FCM, SMTP in omejitev kopij/obnove so ohranjeni.
Vseh osem javnih strani HTTPS 200 se bajtno ujema. [Dokazi objave](../../website/README.md).

Dnevniki, manifest, artefakt in posnetek so v ignorirani `build/qa/no-ai-first-release/`.
Fizični Android izbirnik, odpiranje/deljenje priponk in kopij brez širokih dovoljenj
še potrebujejo preizkus nove namestitve. Za naslednjo interno kandidatko sledijo
izrecna različica, fizični testi in oddaja. UGC, popolnost obnove/priponk, končne
trgovinske deklaracije in iOS ostajajo ločeno delo. Console in FamilyHub nista spremenjena.
