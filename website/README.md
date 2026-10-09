# Jivie: statična javna stran za cPanel

Aktualni lokalni paket 9. oktobra 2026: `build/releases/jivie-website-2026-10-09.zip`. Vključuje popravljena SL/EN opisa AI prenosa in FCM. Prejšnji ZIP je ohranjen; za novo objavo uporabi novega. [Priprava Google Play](../docs/release/GOOGLE_PLAY_PUBLIC_PREPARATION.md) navaja preverjanja, hash in odprte korake pred javno mobilno oddajo.

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

## Poznejša objava prek cPanel

Objava ni del tega koraka. Ko bo uporabnik odobril objavo, v cPanel → Domains preverite dejansko mapo domene in HTTPS. Ne predpostavite, da je glavni `public_html` vedno prava mapa; domena lahko uporablja ločen document root. Najprej shranite kopijo obstoječe spletne vsebine. ZIP naložite samo v potrjeno mapo in ga razširite; zasebnih konfiguracij ali kopij ne premikajte v javno mapo. Prenosni ZIP odstranite iz javne mape po razširitvi.

Preverite `/`, `/en/`, `/privacy/`, `/help/` in `/delete-account/`, javni TLS, mobilno/namizno postavitev, SL/EN preklop, kontaktne povezave in delovanje poti tudi brez JavaScripta. Povezave do trgovin/repozitorija dodajte šele, ko dejansko obstajajo. Lokalni ZIP ne potrjuje dosegljivosti URL-jev ali objavljenosti politike.

## Izbris računa na samostojnem strežniku

Javna stran samo pomaga odpreti pot FamilyHub **na uporabnikovem strežniku**. Ne sprejema gesel, TOTP kod ali sej, ne pošilja poverilnic med izvori ter ne trdi, da lahko TriparNA izbriše tuj račun. Vnese se le HTTPS osnovni naslov Kanboarda brez uporabniških poverilnic, query ali fragmenta; pot in končno preverjanje identitete izvaja vtičnik. Preusmeritev uporablja `no-referrer`.

Dejanski izbris zahteva združljivo nameščen vtičnik in preverjene aplikacijske/strežniške tokove. Končne posledice in preostale kopije opisuje [vsebinski osnutek](../docs/release/WEBSITE_CONTENT.md). Podpisane mobilne izdaje, fizični preizkusi, pravilna trgovinska deklaracija in objavljeni HTTPS naslovi so ločena odprta dokazila v [pripravi izdaje](../docs/release/READINESS.md).
