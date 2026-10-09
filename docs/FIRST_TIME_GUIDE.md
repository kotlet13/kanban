# Kratek vodič Jivie

Izvedeno 7. oktobra 2026. Kratek petstopenjski vodič dopolnjuje obstoječo izbiro načina uporabe; ne ponovi odločitev lokalno/zasebne naprave/gospodinjstvo.

Dopolnitev 9. oktobra: **Začetek uporabe** pod tremi izbirami vsebuje informativni razdelek Organizacija. Pojasni, da članstvo ne odpre vseh projektov ali financ ter da se dostop ureja za vsak projekt posebej. Ta razlaga se ne ponavlja več na organizacijskih zaslonih. Informativni razdelek ni dodatna izbira ali privolitev in ne spreminja petstopenjskega vodiča.

Na začetnem zaslonu Danes je v obstoječem začetnem namigu gumb **Kratek vodič po Jivie**. Vodič predstavi lokalno uporabo brez računa, Danes, Načrte, Nakupe ter meni in nastavitve (finance, račun, kopije). Dopolnitev 8. oktobra pojasni levi zložljivi meni na telefonu, Več na tablici in stranski meni na namizju. Preskoči ali Začnimo zapišeta `jivie_guide_seen_v1` v SharedPreferences; vodič se ne odpre samodejno ob zagonu. Ponovno je dostopen iz nastavitev tudi po končanem ogledu. Zapiranje z zunanjim klikom ne potrdi ogleda. Obstoječi setup ima svojo ločeno oznako in ostane dostopen tudi iz novega telefonskega menija.

Vodič ne ustvari zapisov, članov, dogodkov ali finančnih zneskov; ne kliče strežnika/Firebase, ne vključi sinhronizacije in ne prosi za dovoljenja. Lokalni osnovni tok ostane dostopen. Nobena razlaga ni avtomatski opt-in. Vsa uporabniška besedila so v SL/EN ARB; Dart lokalizacije so generirane.

Preverjanje: `test/organizer/ui/first_time_guide_test.dart` odpre vodič, prehodi vseh pet korakov, preveri zapis oznake in ponoven namerni ogled ter preskok. Matrika 320/390/1280 px, SL/EN in svetla/temna tema (12 testov) nima layout izjem. To so Flutter widget testi, ne dokaz fizične iOS/Android dostave ali dostopnosti s pravim bralnikom zaslona.
