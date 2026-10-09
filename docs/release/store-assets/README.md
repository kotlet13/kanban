# Grafične datoteke za Google Play — Jivie

Pripravljeno 9. oktobra 2026 iz trenutne kode pri različici **1.1.5+8**, izvorni HEAD `d6601533e465e2557edfb315f1546ff94e4f49ee`. Paket je priprava za pregled strani trgovine; ne potrjuje oddaje ali javne produkcijske izdaje.

## Datoteke

Vse končne slike so v [`assets/store/google-play`](../../../assets/store/google-play/). [Manifest](../../../assets/store/google-play/manifest.json) navaja velikost, način barv in SHA-256 vsake datoteke.

| Datoteka | Velikost | Vsebina |
| --- | --- | --- |
| `icon-512.png` | 512 × 512, RGB | Nespremenjena kopija potrjene `assets/branding/jivie/google-play-512.png` |
| `feature-sl-1024x500.png` | 1024 × 500, RGB | Obstoječi znak, Jivie in »Prostor za vsakdan.« |
| `feature-en-1024x500.png` | 1024 × 500, RGB | Obstoječi znak, Jivie in »Space for everyday life.« |
| `{sl,en}/01-today.png` | 1080 × 1920 | Danes: dogodek, opravila in bližnjica nakupov |
| `{sl,en}/02-plans.png` | 1080 × 1920 | Projekti s stanjem opravil |
| `{sl,en}/03-shopping.png` | 1080 × 1920 | Lokalni osebni nakupovalni seznam s količinami |
| `{sl,en}/04-finances.png` | 1080 × 1920 | Osebni finančni račun in dejanski UI mesečnega načrta |
| `{sl,en}/05-garden.png` | 1080 × 1920 | Lokalni Vrt, letna sezona in risana razporeditev gred |
| `{sl,en}/06-finance-ledger.png` | 1080 × 1920 | Isti finančni zaslon, pomaknjen do neto spremembe in zapisov |

## Način zajema in meje

[`store_screenshots_test.dart`](../../../tools/release/store_screenshots_test.dart) neposredno zažene trenutni `KanbanApp`, njegov GoRouter, telefonski levi meni in dejanske proizvodne widgete. S tapkanjem odpre področja in Vrt. `RepaintBoundary.toImage` izriše 432 × 768 logičnih točk pri razmerju 2,5 v 1080 × 1920 pik. Platforma teme je Android, svetla tema in oba obstoječa jezika. Vse besedilo vmesnika prihaja iz trenutne aplikacije in lokalizacij.

To so **izriši dejanskih Flutter widgetov v headless testnem rendererju**, ne zajemi nameščene Android aplikacije, fizične naprave ali emulatorja. Nimajo Androidove statusne/navigacijske vrstice in ne dokazujejo platformnih dovoljenj, dostave opomnikov ali fizičnega prikaza. Niso HTML makete. Pred javno oddajo je smiselna primerjava s kandidatno Android namestitvijo in odločitev o končnem naboru slik.

Testni renderer privzeto uporablja kvadratasto pisavo Ahem, kadar kontrolnik ne določi družine pisave. Zajem naloži Flutterjeve obstoječe Roboto in Material Icons; za Cupertino družini trenutne teme uporabi Roboto kot Androidov nadomestek. Pred izrisom samo pri `RenderParagraph` brez družine obnovi Roboto, da oznake kontrolnikov ne kažejo testnih kvadratov. To je izrecna nastavitev zajemnega rendererja: ne spreminja proizvodne kode, widgetov, besedil, barv, omejitev postavitve ali ponuja novega UI. Debeline in metrika pisav zato niso dokaz natančne enakosti s fizičnim Android prikazom.

Pomnilniška shramba vsebuje samo izrecno sintetične lokalne primere za te slike: izleta/balkon, opravila, živila, tri osebne finančne zapise v EUR in štiri grede. Brez imen družinskih članov, računov, strežniških sej ali uporabnikovih podatkov. Podatki se ne dodajo v aplikacijo ali uporabnikovo bazo. Test potrdi nič zapisov v osebno shrambo. Prvi vodič je v testnih nastavitvah označen kot že pregledan; to ne vključuje sinhronizacije. Primeri datumov so vezani na dan ponovitve zajema.

[`prepare_store_graphics.py`](../../../tools/release/prepare_store_graphics.py) samo kopira obstoječo Play ikono in deterministično sestavi predstavitveni grafiki iz obstoječega prosojnega znaka ter Roboto. Ne ustvarja novega znaka. Uporabi potrjeno nevtralno ozadje `#F4F6FA`, grafit `#202329` in obstoječe modre tone znaka.

## Ponovitev

Iz korena repozitorija, z obstoječim Flutter SDK in Python/Pillow:

```sh
flutter test --no-pub tools/release/store_screenshots_test.dart
python3 tools/release/prepare_store_graphics.py --font-directory /POT/DO/flutter/bin/cache/artifacts/material_fonts
flutter analyze --no-pub
git diff --check
```

SDK/dependencies/lock datoteke niso spremenjene. Datumi se ob ponovnem zajemu prilagodijo trenutnemu dnevu; po zajemu ponovno zaženi grafični pomočnik, da se obnovijo manifest in hashi.

## Preverjanje

- 2 zajemna testa PASS: oba jezika, skupaj 12 zaslonov, izrecne dimenzije 1080 × 1920 in brez Flutter izjem med zajemom.
- Vizualno pregledanih vseh 12 zaslonov prek kontaktnih listov, več ključnih zaslonov tudi v polni velikosti, obe predstavitveni grafiki in izvorna ikona. Znak je pred zajemom izrecno naložen.
- Ikona je bajtno enaka potrjeni Play datoteki; vseh 15 PNG datotek je odprtih in popisanih v manifestu. PNG zasloni so RGBA, vsa prikazana površina je neprosojna.
- `flutter analyze --no-pub`: brez napak in opozoril; 37 obstoječih informacijskih ugotovitev. `git diff --check` brez napak. Preverjeni so hashi/dimenzije vseh 15 slik ter sintaksa grafičnega pomočnika.
- Kontaktna lista za interni pregled sta v ignoriranem `build/qa/google-play-public/contact-sl.png` in `contact-en.png`; nista sliki za nalaganje v trgovino.

Preverjanje slik ne potrjuje ostalih izdajnih meril, pravnih izjav ali dostopnosti javnih URL-jev.
