# Jivie: statična javna stran za cPanel

**16. oktober 2026 — zasebnost in pomoč dejansko posodobljeni.** Štirje SL/EN
HTML opisujejo preglednice, dokumentne priloge, deljenje in ohranitev nastavitev
zvoka skladno z izvorom. Sveža zasebna kopija vseh25 datotek je dejansko
preverjena; nameščeni4 HTML, drugih21 datotek ter vse pravice in lastništvo
ohranjeni. Ločen javni zajem vseh4 strani vrne HTTPS200 in točne pregledane
SHA256. [Dokazi](../docs/release/WEBSITE_DOCUMENTS_20261016.md).

**14. oktober 2026 — javni prenos za Android.** SL/EN domači strani imata
Google Play gumb v uvodu in zaključku; vseh8 strani ima povezavo v nogi.
Besedilo in metapodatki zdaj odražajo javno dostopnost Androida v Sloveniji,
iOS ostane v pripravi. Objavljenih8 HTML po dejansko preverjeni zasebni kopiji
25 datotek;17 drugih datotek, pravice in lastništvo ohranjeni. Vseh8 HTTPS200/
izvornih hashov PASS, mobilna390/320 prikaza brez prelivanja. Dejanski klik
»Prenesi za Android« odpre pravo Jivie v Google Play. Brez nove aplikacijske
gradnje ali spremembe trgovinske objave.
[Dokazi](../docs/release/WEBSITE_GOOGLE_PLAY_LINK.md).

13. oktober 2026: SL/EN domači strani imata javni razdelek `#familyhub` s
povezavo do brezplačnega odprtokodnega vtičnika FamilyHub pod MIT, SL/EN pomoč
pa povezavo do namestitve. Štirje HTML so dejansko objavljeni po preverjeni
zasebni kopiji25 datotek;21 drugih datotek/pravice ostanejo. Vseh4 HTTPS/hash
PASS. Tudi oba Play opisa sta shranjena kot osnutek.
[Dokazi in meje](../docs/release/FAMILYHUB_WEBSITE_AND_PLAY.md).

**13. oktober — dodana odprta tabla Idejnika.** SL/EN galeriji imata novo kartico
s fotografijo, vezano oznako, skico in lističema;8 spletnih posnetkov skupaj.
Objavljeni samo2 HTML in novi PNG, vsi3 HTTPS200/hash PASS,24 starih datotek
dejansko preverjenih v sveži zasebni tar kopiji,22 drugih datotek ohranjenih.
Play ima7 telefonskih slik v shranjenem osnutku; en-US podeduje isto galerijo.
Android1.7.0(25)/AAB/izvor/SDK/dovoljenja nespremenjeni; ni javne oddaje.
[Dokazi in izvor posnetka](../docs/release/IDEAS_BOARD_SCREENSHOT.md).

**12. oktober — nova podoba in posnetki dejansko objavljeni.** SL/EN predstavitev
in pomoč sledita Utrip/Planer/Prostor/Več. Dodanih7 posnetkov iz dejanskega izrisa
vmesnika z izoliranimi vzorčnimi podatki in jasnim opisom predogleda. Android
je v internem preizkušanju; stran ne trdi, da je javna mobilna/iOS izdaja že na voljo.
Vidno besedilo zasebnosti in izbrisa je ohranjeno; skupni CSS ima nov cache token.

Račun **jivie**, document root `/home/jivie/public_html` sta ponovno potrjena
v cPanel Domains. Pred zamenjavo je ustvarjena zasebna kopija celotnega korena
`/home/jivie/private/website-unified-20261012/before-public_html.tar.gz`, SHA256
`b3bab72b7263a571c43a00318558d8de8aefa1521e853179770b26d2b00a8f89`;
vseh17 obstoječih datotek je dejansko primerjanih s kopijo. Preverjeni helper
namesti samo8HTML/CSS/7PNG in potrdi8 ostalih datotek z istimi bajti/pravicami/
lastništvom; PHP/.htaccess/.well-known in drugi assets ostanejo ohranjeni.
ZIP in helper sta zunaj javnega korena. Ni spremembe DNS/HTTPS nastavitev.

Paket `build/releases/jivie-website-2026-10-12-unified.zip`,16 datotek,
SHA256 `e76539fb45a2f071f6b6484eae2824b036e8c2876b89009fca635ebb714a48af`.
Vseh16 javnih URL vrne HTTPS200 in točen izvorni hash. Lokalni SL/EN prikazi
1440/390/320 in dejanski javni mobilni390 so brez horizontalnega prelivanja;
slike imajo alt/dimenzije, povezave in fragmenti so preverjeni.
Dokazi: `build/qa/unified-ux-release-20261012/website-{package,live-verification,
deployment-evidence}.json`, `website-published.jpg` in `website-mobile.jpg`.
Izvorni allowlist in lokalni pregled sta v `build/qa/unified-mobile-ux/`.

Za Play je6 novih Android posnetkov720×1280 brez obrezovanja ali prekrivnih
napisov shranjenih v osnutek skupaj z aktualnima SL/en-US opisoma. Slike uporabljajo
vzorčne podatke; angleška objava uporabi novo privzeto galerijo. Stare slike
ostanejo v knjižnici. Javna trgovinska objava ni oddana.
[Aktivna interna Android1.7.0(25)](../docs/release/UNIFIED_UX_RELEASE.md).

**12. oktober,15:36 — objava izvedena po prijavi s shranjenim geslom.** Račun
**jivie**, domena/document root preverjena z DomainInfo: `/home/jivie/public_html`.
Paket8HTML spodaj je objavljen; vseh8 javnih URL vrača HTTPS200 in točen izvorni
hash. SL/EN privacy ob If-Modified-Since za11.oktober vrneta novo besedilo200;
HTTPprivacy se preusmeri naHTTPS. Zasebna kopija pred spremembo:
`/home/jivie/private/website-photos-20261012/before-public_html.tar.gz`, SHA256
`dd46b8737d5bee01f43805459a547523192174ce24ce7061bb1def45556253de`.
Pred zamenjavo je kopija vseh8 starihHTML dejansko primerjana z živimi datotekami.
20 drugih vnosov ima enake bajte/symlink cilje/pravice/lastništvo; PHP/.htaccess/
.well-known/assets so ohranjeni. Paket in skripta ostaneta zunaj javne mape.
Dokazi: `build/qa/android-photos-privacy-20261012/website-live-after.json`,
`website-deployment.json` ter javni/terminalski posnetek.
[Izvedba](../docs/release/ANDROID_PHOTOS_DATA_SAFETY.md#objava-po-prijavi-s-shranjenim-geslom).
Prejšnja ovira prijave je odpravljena; Data safety osnutek še ni oddan v pregled.

**12. oktober — Android zasebnost, spletna objava čaka prijavo.** Play Data safety
ima shranjen osnutek vseh 11 vrst s fotografijami; [dokazi in naslednji korak](../docs/release/ANDROID_PHOTOS_DATA_SAFETY.md).
Prijava v ločen cPanel račun **jivie** je potekla, uporabnik ni pri računalniku;
objave ni bilo. Oba javna privacy URL vračata HTTPS200 s starim besedilom 11. oktobra.
Pripravljen je preverjen paket **8 HTML**, `build/releases/jivie-website-2026-10-12-photos-html.zip`,
SHA256 `e175fdd8c48e38314e27ca102ffdbf271199aa8b5be5270d27b16901257ed6bc`.
CRC/allowlist in bajtno ujemanje z izvorom PASS; sveži časovni žigi za pogojni cache.
Po prijavi objavimo samo HTML v `/home/jivie/public_html` po zasebni kopiji,
z ohranjenimi PHP nastavitvami, `.htaccess`, `.well-known` in assets. Paket je lokalen,
ne dokaz namestitve; stare pakete ohranimo. Javna oddaja in Apple nista izvedena.

**12. oktober — Idejnik, lokalno pripravljen izvor:** predstavitev/pomoč in SL/EN
zasebnost zdaj zajemajo uredljive table, izbrane normalizirane fotografije,
izbirno deljenje in zasebno sinhronizacijo, dejanski predpomnilnik/kopije ter
prijavo celotne table s fotografijami. Generator vsebuje tudi prej ločeno
pripravljeni odsek pravil in prijav, zato ga ponovno generiranje ne izgubi.
To besedilo **ni objavljeno**; živa stran ostaja preverjeno besedilo 11. oktobra.
[Izvedba Idejnika](../docs/IDEAS_IMPLEMENTATION.md).
Lokalni paket `build/releases/jivie-website-2026-10-12-ideas.zip` ima15 datotek,
SHA256 `e33f55353c451f3eea91a49e505c5bd6cb7d3534e3c88395b4b464adfbaf72c0`;
CRC in bajtno ujemanje vseh dovoljenih izvorov sta preverjena.18 paketnih testov PASS.

**12. oktober — lokalno pripravljena dopolnitev:** SL/EN zasebnost opisuje novi
tok pravil in prijav FamilyHub0.12.0: izrecni sprejem, prejemnik na izbranem
strežniku, omejeni posnetek, hramba po zaključku in vpliv izbrisa računa. Ta
dopolnitev **ni objavljena**; živa stran še uporablja preverjeno besedilo
11. oktobra. Pripravljeni paket bo uporabljen skupaj z nadgradnjo po vrnitvi
lastnika. [Izvedba in meje](../docs/MODERATION_AND_REPORTING.md).

**Vsebinska korekcija 11. oktobra 2026:** po izrecni uporabnikovi korekciji je celoten
odstavek o AI in internih/testnih izdajah odstranjen iz obeh javnih politik. Zasebnost
opisuje podatkovne poti prve izdaje, brez razvojne zgodovine. Paket osmih HTML
`build/releases/jivie-website-2026-10-11-privacy.zip`, SHA256
`ea7eca6d18b27e7601b2f269b788159f9b4ae0f319f924af36aaff0d8b98af5e`, je objavljen.
Vseh osem javnih strani HTTPS 200 se ujema z lokalnim izhodom; oba privacy HTML
sta brez omemb AI/OpenAI ali internih različic. Dokazi so v
`build/qa/privacy-content-correction-20261011/`. Spodnji zapisi so zgodovinski;
ta popravek ima prednost pred njihovim prejšnjim besedilom o javnem AI odstavku.
Končni dvo-datotečni paket `jivie-website-2026-10-11-privacy-final.zip`, SHA256
`6b5ba8e88a779da4ef381c41134431393c0ea3b3626448ede424a4012ad75317`, ohrani isto
vsebino in uporabi sveža namestitvena časovna žiga. S tem oba URL vrneta 200 tudi
pri pogojni zahtevi s prejšnjim `If-Modified-Since`; starega besedila brskalnik ne
ohrani zaradi arhivskega datuma. Dokaz: `cache-verification.json`.

**Prva javna izdaja brez AI — 11. oktober 2026:** slovenska in angleška zasebnost
sta posodobljeni in objavljeni. Jasno ločita pripravljano izdajo brez AI od starejših
internih/testnih različic, ki AI še vsebujejo. Stari lokalni podatki se ob nadgradnji
ohranijo brez samodejnega prenosa. Uporabnik je potrdil delujoč `support@jivie.app`.
Paket osmih HTML datotek `build/releases/jivie-website-2026-10-11-no-ai.zip`, SHA256
`f45b531e3d03c1a2fb90e4ef10502a5d4640df02e737f43a257e7ef358b4458e`, je objavljen
v isti spletni mapi. Vseh osem javnih strani vrača HTTPS 200 in se bajtno ujema;
prejšnji `support.zip` ostaja zunaj spletnega korena za povrnitev. Dokazi:
`build/qa/no-ai-first-release/website-verification.json` in `privacy-live.jpg`.
[Odstranitev AI v aplikaciji in preverjanje dovoljenj](../docs/release/NO_AI_FIRST_RELEASE.md)
sta ločena od dejanske trgovinske izdaje.

**Posodobitev podpore 11. oktobra 2026:** po uporabnikovem naročilu je kontakt
na vseh osmih SL/EN straneh in vseh povezavah `mailto:` spremenjen v
`support@jivie.app`. Objavljen je paket samo osmih HTML datotek
`build/releases/jivie-website-2026-10-11-support.zip`, SHA256
`ef6833ea987a5b15797f70a612b91be515d7d5fec7e03b8753f8050397f153b4`.
Vseh osem javnih strani vrača HTTPS 200, se ujema z lokalnim izhodom in ne vsebuje
starega naslova. Dokazi so v `build/qa/jivie-support-mail-20261011/`.
Prejšnji celotni paket ostaja za povrnitev; konfiguracija gostovanja je ohranjena.
Ta korak spremeni spletni kontakt, ne ustvarja poštnega predala ali potrjuje dostave.

**Objavljeno 11. oktobra 2026:** [jivie.app](https://jivie.app/) je nameščen na
ločenem cPanel računu `jivie`, v potrjeni mapi `/home/jivie/public_html`.
Uporabnik je naročil začetek urejanja tega gostovanja in se neposredno prijavil.
Vseh osem SL/EN strani ter šest javnih sredstev vrača HTTPS 200 in se bajtno ujema
s preverjenim paketom. HTTP začetne strani in zasebnosti se preusmeri s 301 na HTTPS.
Preverjeni so namizni in mobilni prikaz 390 px, povezava do pomoči, preklop jezika,
priprava povezave za izbris ter zavrnitev HTTP naslova. Izbris računa ni bil izveden.

Paket `build/releases/jivie-website-2026-10-11-cpanel.zip` ima 15 datotek in SHA256
`81d22b3867917d267b4e4b19f2fa072c9cd550474d3370bd8ed08961abd1f30d`.
Namestitveni `.htaccess` ohrani izvirni cPanel PHP blok; `php.ini`, `.user.ini` in
`.well-known` so ohranjeni. Arhiv pred spremembo je
`/home/jivie/jivie-website-before-20261011.zip`, namestitveni ZIP pa prav tako ostane
zunaj spletnega korena. Oba javna naslova arhivov vrneta 404, dostop do konfiguracij
vrne 403. Dokazi, manifest in posnetki so v ignorirani
`build/qa/jivie-website-20261011/`. 18 paketnih/izdajnih testov, produkcijski
JS preizkus povezave in `git diff --check` PASS.

Besedilo je usklajeno z navigacijo, deljenjem, privzetimi obvestili in omejitvami
obnove v 1.3.2. Razkritje starega AI ostaja, ker je v aplikaciji še dosegljiv.
Dosegljivost strani je rešena; končna trgovinska politika/deklaracije in odstranitev
AI ostajajo ločeno delo. Ta objava ni javna mobilna izdaja ali namestitev FamilyHub.

Zgodovinski lokalni paket 9. oktobra 2026: `build/releases/jivie-website-2026-10-09.zip`. Vključuje popravljena SL/EN opisa AI prenosa in FCM. Prejšnji ZIP je ohranjen; objavljeni paket je naveden zgoraj. [Priprava Google Play](../docs/release/GOOGLE_PLAY_PUBLIC_PREPARATION.md) navaja preverjanja, hash in odprte korake pred javno mobilno oddajo.

Izvor strani je v `public/`. Gradnjo HTML vodi `build_site.py`; ZIP vsebuje samo pregledani javni izhod. Ni odjemalec Flutter, podatkovni strežnik ali storitev upravljanega gostovanja. Ne vključuje baze, prijav, gesel, sej, spletnega obrazca s poverilnicami ali objave v trgovinah.

## Lokalna priprava

```sh
python3 website/build_site.py
python3 -m unittest discover -s tools/release -v
node tools/release/test_deletion_link.mjs
python3 tools/release/package_website.py
```

Privzeti rezultat je `build/releases/jivie-website.zip` in njegov `.sha256`. `index.html` je v korenu ZIP-a, da ga lahko razširite neposredno v **document root domene jivie.app**. Paketor ne doda zunanjega `public/` imenika. Obstoječega ZIP-a ne prepiše: za novo kandidatko uporabite `--output build/releases/jivie-website-v2.zip`. Orodje ne izvaja omrežja, nalaganja, podpisovanja ali namestitve.

Dovoljeni so samo `.html`, `.css`, `.js`, `.png`, `.svg`, `.ico`, `.webp`, `.txt`, `.xml` in `.htaccess`. Simbolne povezave, skrivni imeniki, konfiguracije, skripte strežnika, `.git`, varnostne kopije in očitne zasebne poverilnice so zavrnjene. Posamezna datoteka je omejena na 10 MiB, celota na 50 MiB. Orodje ni zagotovilo odsotnosti poljubnih občutljivih podatkov; pred predajo vizualno in vsebinsko preglejte vse datoteke.

## Objava in naslednje posodobitve prek cPanel

Za vsako naslednjo posodobitev v cPanel → Domains preverite dejansko mapo domene in HTTPS. Ne predpostavite, da je glavni `public_html` vedno prava mapa; domena lahko uporablja ločen document root. Najprej shranite kopijo obstoječe spletne vsebine zunaj javne mape. ZIP naložite zunaj spletnega korena in ga razširite samo v potrjeno mapo. Ohranite morebitne cPanel direktive Apache in PHP ter `.well-known`; zasebnih konfiguracij ali kopij ne premikajte v javno mapo.

Preverite `/`, `/en/`, `/privacy/`, `/help/` in `/delete-account/`, javni TLS, mobilno/namizno postavitev, SL/EN preklop, kontaktne povezave in delovanje poti tudi brez JavaScripta. Povezave do trgovin/repozitorija dodajte šele, ko dejansko obstajajo. Lokalni ZIP ne potrjuje dosegljivosti URL-jev ali objavljenosti politike.

## Izbris računa na samostojnem strežniku

Javna stran samo pomaga odpreti pot FamilyHub **na uporabnikovem strežniku**. Ne sprejema gesel, TOTP kod ali sej, ne pošilja poverilnic med izvori ter ne trdi, da lahko TriparNA izbriše tuj račun. Vnese se le HTTPS osnovni naslov Kanboarda brez uporabniških poverilnic, query ali fragmenta; pot in končno preverjanje identitete izvaja vtičnik. Preusmeritev uporablja `no-referrer`.

Dejanski izbris zahteva združljivo nameščen vtičnik in preverjene aplikacijske/strežniške tokove. Končne posledice in preostale kopije opisuje [vsebinski osnutek](../docs/release/WEBSITE_CONTENT.md). Podpisane mobilne izdaje, fizični preizkusi, pravilna trgovinska deklaracija in objavljeni HTTPS naslovi so ločena odprta dokazila v [pripravi izdaje](../docs/release/READINESS.md).
