# Nadgradnje Jivie — izvedba 8. oktobra 2026

Uporabnik je naročil: popravki → commit/push → implementacija nadgradenj → commit/push → nova Android interna izdaja za obstoječi seznam `domači`. iOS in obvestila, ki potrebujejo lastnikov dostop oziroma fizično napravo, dobijo kratek končni seznam. Ta dokument vodi tekoče delo; odprta vrstica ni dokaz izdelane funkcije.

## Izvedbeni obseg

1. Popraviti mobilne obrazce, odrezano oznako na vrhu in prikaz ob tipkovnici; jasen uspeh registracije/verifikacije ter samodejno podaljševanje aktivne seje.
2. Organizacije z več projekti, jasno izbiro prostora in ločenimi projektnimi/finančnimi pravicami.
3. Člani gospodinjstva brez računa; ločena izvajalec in oseba, na katero se opravilo nanaša.
4. Projektne faze/mejniki, koledarski intervali, ocene ur, dnevna/tedenska razpoložljivost ter Play/Pause merjenje časa.
5. Strošek pri opravilu kot isti finančni zapis; načrtovani datum sledi roku, plačilo ostane ločeno.
6. Finančni čarovnik, mesečna pravila, napoved in potrditev plače z opomnikoma pred/po vikendu.

Osnova ostane local-first. Osebni podatki se ne delijo ob prijavi ali ustvarjanju organizacije; nove pogodbe potrebujejo strežniško preverjanje in zmožnost, stare kopije morajo ostati berljive. Vrt ostane lokalen. Mobilni levi meni je možnost za primerjavo, ne potrjena privzeta zamenjava.

## Stanje in dokazi

- Pred začetkom: šest uporabnikovih dokumentacijskih sprememb je ohranjenih. Vejo vodi `codex/vsakdan-foundation`; trenutna interna različica je `1.0.1+2`.
- Faza popravkov: izdelana; lastniki `mobile_fixes`, `auth_ui`, `session_renewal` (GPT-6.1 Sol / high). Geometrijski preizkusi zajamejo oznake/gumbe pri 320/360/390 px, odprti tipkovnici in 2× povečavi; UI potrjuje ustvarjen račun/prijavo ter potrjeno e-pošto. `auth.renew` ohrani bearer in napravo, drseče podaljša aktivno sejo, spoštuje preklic in preživi izgubljen odgovor ter restart. Starejši strežnik brez zmožnosti ostane podprt brez podaljševanja.
- Podatkovni dokaz popravkov: 35 ciljnih Dart testov PASS; 20 PHP preverjanj PASS na vsaki SQLite/MySQL/MariaDB, vključno s sočasnim preklicem in obnovo gesla. Odjemalčev celoten končni nabor, analiza ter izdajna orodja so zabeleženi v `build/qa/jivie-upgrade/`. Prvi skupni zagon je našel napako novega testnega fixture; po uskladitvi začetne identitete je celoten ponovljeni nabor PASS. Fizični S25/SwiftKey preizkus in namestitev novega API na gostovanje še nista dokazani s temi testi.
- Prvi commit/push: še ni izveden.
- Funkcionalne nadgradnje: še niso izvedene.
- Drugi commit/push: še ni izveden.
- Nova Android gradnja in objava: še nista izvedeni. Kandidatko in prosti versionCode preverimo pred dvigom.
- Predaja prejšnjih klepetov za prijave/izdajo: zahtevana; ne dovoljuje sočasnih sprememb iste kode ali konzole.

Najnovejše dokaze prejšnje izdaje vodi [izdajni dnevnik](release/NOTIFICATION_RELEASE_RUN.md); vsebinske zahteve vodi [načrt prenove](RENOVATION_PLAN.md).
