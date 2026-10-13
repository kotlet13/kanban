# Odprta tabla Idejnika na spletni strani in v Play Console

13. oktober2026 — po uporabnikovem naročilu je dodan posnetek odprte table
»Kotiček za jutranjo kavo«: resnična fotografija, nanjo vezana rdeča oznaka/puščica,
modra skica police z rastlino in dva uredljiva lističa z opombami.
**Slika je dejansko objavljena na jivie.app SL/EN in shranjena kot sedmi
telefonski posnetek v Google Play Console. Android1.7.0(25) ostane isti.**

## Prikaz iz izdane kode

Posnetek je720×1280,9:16,247.269 bajtov, SHA256
`277a5b8d504794bf444aab3cbd50da638955188ea2ecad62c4036b35ee6986e0`.
Ni obrezovanja, spreminjanja slikovnih pik ali prekrivnih marketinških napisov.

Izris uporablja izoliran izvor `fa809b8`, ki ustreza izdani AAB25, s predhodno
zaklenjenimi odvisnostmi in `--no-pub`. **283 javnih lib/assets vhodov** je
primerjanih z zamrznjenim izdajnim manifestom in vseh283 SHA PASS. Tekoča
namizna koda ni uporabljena za prikaz Androida. Ni nove aplikacijske gradnje.

Capture harness uporablja pravo pomnilniško SQLite, IdeaRepository, normalizacijo
in predpomnilnik fotografije, odpre shranjeno tablo po običajni poti IdeasPage
→ IdeaEditor in uporabi dejansko Jivie temo/font/ikone za Android. En ciljni
capture PASS preveri dekodirano sliko namesto placeholderja, uredljivost,
risarske elemente, izhodne mere in odsotnost napake izrisa. Celotnega
funkcionalnega kroga ne ponavljamo. Fotografija je javni
[Pexels vzorec](https://www.pexels.com/photo/close-up-of-coffee-cup-on-table-312418/)
Chevanon Photography; [licenca in lokalni fixture](../../tools/release/fixtures/README.md).
Vzorčni zapisi niso vstavljeni v uporabnikovo aplikacijo ali strežnik. To je
dejanski widget izris, ne fizični posnetek telefona.

## Spletna objava

V cPanel je izbran račun jivie; Domains ponovno potrdi `/home/jivie/public_html`.
Sveža zasebna kopija v `/home/jivie/private/website-ideas-board-20261013/`
dejansko primerja bajte vseh24 predhodnih datotek s tar arhivom in živo stranjo.
Objavljeni so samo `index.html`, `en/index.html` in nova
`assets/screenshots/ideas-board.png`. Slika je nameščena pred HTML povezavama.
Vseh22 drugih datotek ima enake hashe/pravice/lastništvo, med njimi zasebnost,
izbris, PHP nastavitve, `.htaccess`, `.well-known` in prejšnje slike.

Galerija dobi kartico »Od zamisli do table« oziroma »An idea taking shape« z
opisom fotografije, skice in opomb ter točnimi merami slike. Stari predogled
seznama Idejnika ostane. Vseh3 javnih datotek vrne HTTPS200 in točen hash;
dejanski spletni prikaz kartice je vizualno preverjen in shranjen.

## Play Console in meje

V privzeti slovenski objavi je dodan `07-ideas-board.png`, sedaj **7/8**. Vseh6
prejšnjih slik ostane. »Shrani kot osnutek« dejansko pokaže shranitev; po ponovnem
nalaganju je še7 slik, novi element pa kaže720×1280/9:16/naloženo13. oktober.
Preklop na en-US potrdi podedovanih istih7 slik brez dodatne lokalizirane kopije.
Besedila, ikona, feature grafika, države in izdaja niso spremenjeni.

Dokazi v `build/qa/ideas-board-promo-20261013/`: capture evidence/PNG,
website-package/deployment/live evidence, spletni prikaz kartice,
play-evidence ter shranjena galerija/podrobnosti nove slike. Paket in pomočnik
ostaneta zunaj javnega spletnega korena; varnostna kopija ostane zasebna.

Android AAB25 po koncu še vedno SHA256
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447`.
App izvor, SDK, locks, dovoljenja, gostovana FamilyHub/test1/test2 podatkovna
drevesa in nameščena Mac aplikacija niso spremenjeni. Ni javne oddaje Googlu.
Naslednje je javna izdaja iste AAB25, države in končni Pregled objavljanja.
