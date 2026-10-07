# Jivie — zemlja, voda in zrak

Ime: **Jivie**, izgovorjeno **dživi**. Zasnova z dne 7. oktobra 2026 sledi uporabnikovi zahtevi po abstraktnem prepletu treh elementov življenja. Grafitna spodnja masa predstavlja zemljo, temnejši modri tok vodo in svetlejši odprti lok zrak. Pomen je oblikovno izhodišče, ne trije ločeni piktogrami. Sorodni modri toni ohranijo povezavo s potrjenim vmesnikom. Znak je trenutna izvedba za pregled, ne trditev o preverjeni izključnosti znamke.

Izdelano z vgrajenim orodjem **imagegen** (brez API CLI). Izvirnik ima prosojno ozadje; shranjen je kot `source-mark.png`. [Celoten ustvarjalni poziv](GENERATION_PROMPT.md). Naknadna priprava je samo determinističen izvoz velikosti, ne nova risba.

| Datoteka | Namen |
| --- | --- |
| `source-mark.png` | Izvirna generirana slika z alpha, nespremenjena |
| `icon-master.png` | 1024 × 1024 RGB, ozadje #F4F6FA, iOS/izvor standardnih ikon |
| `icon-foreground.png` | 1024 × 1024 RGBA, Android adaptive foreground |
| `icon-monochrome.png` | Isti alpha obris, bela barva, Android themed icon |
| `google-play-512.png` | 512 × 512 RGB za Play ikono |
| `preview.html` | Lokalni pregled velikosti in sistemskih mask; ni aplikacijski zaslon |

Ikona nima vrisanih zunanjih zaobljenih robov ali sence. Sistemski maski jih določita ob prikazu. Android uporabi dodaten 12-% inset; skupaj z izvirnim prosojnim robom ohrani znak v varnem krogu 66/108 dp. Spletni maskable raster uporablja neprosojni master. Majhne velikosti in svetlo/temno okolico preverimo v predogledu, končno namestitev pa na napravah.

Ponovitev iz korena repozitorija:

```sh
dart run tools/branding/export_icons.dart
dart run flutter_launcher_icons
python3 tools/release/check_readiness.py --code-only
```

Izvozi ohranijo izvirnik; nastavitve generiranja so v `pubspec.yaml`. V aplikaciji uporabljamo JivieBrandMark. Interni tehnični identifikatorji in format `.vsakdan` ostajajo zaradi združljivosti, niso javna znamka.
