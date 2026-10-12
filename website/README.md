# Jivie: statična javna stran za cPanel

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
