# Jivie 1.5.1 (21) — prijave v meniju in podrobnostih

12. oktober 2026. Uporabnik je izrecno naročil novo interno objavo po odstranitvi
stalnih zastavic. Funkcionalni commit **aa1db2b**, metadata **1ba60b6**.
Nova različica ohrani prijavo vsebine v meniju »…« ali podrobnostih, prijavo
uporabnika pa v meniju ob članu. Pregledi projektov/seznamov/vrtov/agende/Vsi
ohranijo običajno odpiranje; finance imajo skupni meni dejanj. Bralna prijava,
obstoječe urejanje, zgodovina, opomniki in upravljanje članov ostanejo dosegljivi.

## Preverjanje in obseg

**201 ciljnih UI testov PASS**, analiza **No issues found** pri funkcionalnem
commitu; brez nove funkcionalne spremembe tega teka ne ponavljamo. Meniji so
preverjeni na 360/800/1280 točkah, z bralnim dostopom, preklicem brez oddaje,
izrecno oddajo in menjavo računa med odprtim menijem. Sintetična telefonska
posnetka sta vizualno pregledana; nista fizična nadgradnja telefona.

Strežnik ostaja test2 **FamilyHub0.12.0/schema16**, test1 **0.11.2/schema15**;
ta izdaja ne posega v strežnike, podatke, sheme, pravila ali pogodbo prijav.
SDK, zaklenjene odvisnosti in podpisna/Firebase identiteta ostanejo isti.
Prejšnji read-only AAB20 ostane ohranjen. iOS, Mac in javna produkcijska izdaja
niso del tega izdajnega koraka. Obstoječe meje obnove ter javne deklaracije
Data safety/IARC ostanejo ločene.

## Paket in Play Console

Podpisani paket `build/releases/Jivie-1.5.1+21-android-firebase.aab`,
**75.884.516 bajtov**, SHA256
`1242f22bc35d2a0a72cd526913594e63290df7f2f4bb25ffbbac8f1f3fef7939`.
Paket/checksum sta read-only; AAB20 je nespremenjen.

- **304 zamrznjeni vhodi** se ujemajo; agregat
  `f168bb6bba561c8a607370c42c2470643094be42e08326e032b21ac30d1297e7`.
- Isti upload certifikat in Firebase native/vseh Dart ABI identiteta kot20.
- `si.triparna.jivie`, min24/target36, Back callback, istih osem dovoljenj brez
  širokih media/storage, share FileProvider in odsotnost starih providerjev PASS.
- Bundletool validate, ZIP CRC, PAGE_ALIGNMENT_16K vseh osmih 64-bitnih knjižnic
  in odsotnost zasebnih podpisnih/service-account ključev PASS.
- **23 izdajnih +7 Firebase kontrol**, source checker PASS. Funkcionalni testi
  in analiza so že potrjeni pri aa1db2b; brez spremembe niso ponavljani.

**Play Console potrjuje Aktivno / 1.5.1 (21) od 12. oktobra ob 08:22**, na voljo
istim notranjim preizkuševalcem **domači (15)**. Naložen je točno preverjeni
AAB21; AAB20 ni vključen v novi izdaji. Ni izgubljenih ali novo podprtih naprav.
SL/en-US opombe so objavljene. Izdaja je v istem internem kanalu
`4701286726300038561`, račun TriparNA/TaknDevs `4991604398202512900`, aplikacija
`4972659047480717992`. [Povezava za
posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).
Fizična nadgradnja telefona in preizkus novega menija še nista potrjena.

Dokazi gradnje/objave so v
`build/qa/moderation-context-release-20261012/android/`, vključno z
`android-release-artifact-evidence.json`, `play-release-evidence.json` ter
`play-internal-1.5.1-21-active.png`.
