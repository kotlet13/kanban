# Kontrast ikon urejevalnikov — 15. oktober 2026

V zgornji vrstici urejevalnika vrta je podedovana barva običajnih ikon prepisala barvo ikone v zapolnjenem gumbu Shrani. Dejanski widget test je pred popravkom izmeril kontrast približno 1,03 : 1 v svetli temi.

Skupni EditorSaveButton zdaj izrecno uporablja onPrimary, torej barvo ikone za primarno ozadje. To velja za vrt ter iste gumbe v urejevalnikih opravil, opomnikov, deljenja, Idejnika, gred, zasaditev in sezon. Pregled vseh treh uporab IconButton.filled/filledTonal v lib je vključil še dodajanje nakupovalnega izdelka (onPrimary) in ponastavitev pogleda Idejnika (onSecondaryContainer). Barve sledijo trenutni svetli ali temni temi; navadne ikone v zgornji vrstici ohranijo svoje barve. Onemogočanje, indikator shranjevanja, dejanja in najmanjša velikost dotika ostanejo ohranjeni.

Preverjanje: 63 ciljnih UI/tematskih testov PASS. Od tega 20 novih primerov preveri dejanske podedovane barve ikone in izrisanega Material ozadja: Shrani v zgornji vrstici in spodaj, svetla/temna tema, Android/iOS/macOS widget konfiguracija, omogočeno/onemogočeno/shranjevanje; dodatno dejanska gumba nakupov in table Idejnika. Aktivne ikone dosegajo kontrast najmanj 4,5 : 1, indikator shranjevanja najmanj 3 : 1; onemogočena dejanja ne kličejo shranjevanja. Obstoječi testi pokrivajo vrt, prizor vrta, postavitev urejevalnikov, temo in hitri vnos nakupov. Celotna analiza: istih 10 predhodnih info v nepovezanih izdajnih orodjih, brez opozoril ali napak.

Popravek je samo v izvoru; fizični prikaz novega popravka še ni preverjen. Ni nove native gradnje ali Google Play oddaje. Zamrznjeni AAB29 ostane nespremenjen in popravka ne vsebuje. Naslednja izdaja zahteva novo izrecno uporabnikovo potrditev.
