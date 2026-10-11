# Očiščena Jivie — interna kandidatka 1.4.0 (18)

11. oktober 2026. Uporabnik je naročil nadaljevanje po odstranitvi starega vmesnika
in združitvi na main. Funkcionalni commit je `7726d76`, združitev `b6832c2`;
izdajna metadata `7fb5ed9` pripravijo **1.4.0+18** na main.
Spremenjene so samo različica in njeni metapodatki. SDK, zaklenjene odvisnosti,
platformne/podatkovne identitete in podpisna konfiguracija ostanejo nespremenjeni.
FamilyHub je obstoječi 0.11.2/schema15; strežnik ni nadgrajen ali ponastavljen.

## Podpisani paket

`build/releases/Jivie-1.4.0+18-android-firebase.aab`, **75.602.280 bajtov**, SHA256
`87c8d89a858daae4d2406f2d2d6acd33bbdf377156224615aaeace213a467215`.
AAB in kontrolna vsota sta read-only; originalni izdani AAB17 ostane ohranjen.

- 298 zamrznjenih Android/lib/assets/pubspec/l10n vhodov iz `7fb5ed9` se po gradnji
  ujemajo. Agregatni SHA256:
  `327bd703ad907fc0aad86ca7b931cec81bc2a3d602e3e6f1b917341ac04b33dd`.
- Zasebna konfiguracija je predstavljena samo s hashi, ki se ujemajo z AAB17.
  V paketu ni zasebnih podpisnih ali service-account datotek/ključev.
- `si.triparna.jivie`, 1.4.0 (18), min24/target36 in Android Back callback PASS.
- Podpis in certifikat se ujemata z izdanim AAB17; bundletool validate, ZIP CRC,
  PAGE_ALIGNMENT_16K in vseh osem 64-bitnih knjižnic pri 16 KiB PASS.
- Firebase native viri se ujemajo z AAB17, projekt v Dart AOT je potrjen za vse ABI.
- Natanko štiri široka dovoljenja so odstranjena: READ_EXTERNAL_STORAGE in
  READ_MEDIA_IMAGES/VIDEO/AUDIO. Drugih osem je ohranjenih. Stari open_filex
  FileProvider ni v manifestu, share_plus FileProvider ostaja.
- 23 izdajnih/paketnih + 7 Firebase testov in source checker PASS.
  Funkcionalni izvor ima 942 Flutter PASS / 13 opt-in preskočenih in analizo brez
  ugotovitev; [dokazi funkcionalne odstranitve](LEGACY_INTERFACE_REMOVAL.md).

Dokazi, manifest, izvorni inventar in build log so v ignorirani
`build/qa/clean-organizer-release-20261011/android/`. AGP/Kotlin opozorila o prihodnji
podpori so obstoječa; SDK ali drugi paketi niso bili nadgrajeni.

## Trgovina in fizični preizkus

**Paket je pripravljen, ni še naložen ali aktiviran.** Predviden cilj je obstoječi
interni kanal in seznam domači (15). Zadnja potrjena aktivna izdaja je 1.3.2 (17);
pred uploadom je treba preveriti živo evidenco, da build18 še ni porabljen.

Prijavljena Google računa v izbranem brskalniku nista ponudila računa TriparNA
`4991604398202512900` z evidenco Jivie `4972659047480717992`. Odprti osebni
razvijalski račun ima drug ID in drugo aplikacijo; vanj paket ni bil naložen.
Uporabnik je pozvan, naj se v odprtem Play Console prijavi v pravi račun.
Nobene nove pravice, računi ali pogodbe niso bili ustvarjeni/sprejeti.

Po objavi preveri nadgradnjo obstoječe namestitve, ohranitev prijave/prostorov/podatkov,
novi meni/Nastavitve, lokalno opravilo/strošek in ponovni zagon brez omrežja,
kopijo/obnovo ter dostavo/odpiranje obvestila drugega računa. To niso že potrjeni
fizični rezultati te kandidatke. iOS, javna izdaja, UGC in preostale podatkovne meje
ostajajo ločeni koraki.
