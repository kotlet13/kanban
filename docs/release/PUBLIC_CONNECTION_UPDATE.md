# Javna Android posodobitev1.7.1(26) in ustavljen interni kanal

14. oktober2026 — uporabnik potrdi **»Ok, zej povezovanje dela«**, nato izrecno
naroči javno objavo istega popravka in ustavitev internih objav. To je fizična
uporabnikova potrditev po interni26, ne nov agentski funkcionalni testni krog.
[Preverjeni popravek in gradnja](SPACE_CONNECTION_RELEASE.md) ostaneta osnova.

## Dejanska izvedba v Play Console

- Produkcijski kanal `4698247597354229997`, nova izdaja **2**.
- Obstoječa interna **26(1.7.1)** je promovirana prek »Uvedi izdajo v drugi
  različici → Splošna razpoložljivost«. Uporabljena je ista knjižnična AAB26,
  brez nove gradnje, ponovnega nalaganja ali vključitve25 v novo izdajo.
- Lokalni artefakt še vedno meri78.421.130bajtov; SHA256
  `ef803a085ac955219946ce7ed6143429438816173d53d4f30b6f7e1eafbf2b4d`.
- Ime **1.7.1(26) — popravek povezovanja prostorov**, iste SL/en-US opombe o
  izrecnem sprejemu pravil in ohranitvi lokalnega prostora ob preklicu.
- **100% uvajanje**, obstoječa edina ciljna država **Slovenija** dejansko
  preverjena v zavihku Države/regije. Držav in trgovinskih deklaracij/opisov
  v tem koraku nismo spreminjali.0 izgubljenih/novih podprtih naprav.
- Končni **Shrani** in nato **Pošlji1spremembo v pregled → Pošljite spremembe
  v pregled** sta dejansko potrjena. Console kaže **Spremembe v pregledu**
  in prav to javno izdajo26.
- Ob koncu še tečejo hitra samodejna preverjanja; Console izrecno pravi,
  da bodo spremembe poslane v dejanski pregled po uspešnem koncu preverjanj.
  **Oddaja je potrjena; odobritev in javna razpoložljivost26 še nista.**
  Upravljano objavljanje ostaja OFF, objava po uspešni Googlovi odobritvi.

## Interni kanal in prihodnje delo

Na kanalu `4701286726300038561` sta potrjena **Začasno zaustavi različico →
Začasno zaustavi preizkus**. Console dejansko kaže **Neaktivno** in
»Ta različica je začasno zaustavljena; preizkuševalci ne prejmejo te izdaje«.
Zgodovina/paket in seznam preizkuševalcev niso izbrisani. To je reverzibilna
ustavitev distribucije, ne izbris aplikacije, računov ali uporabniških podatkov.

**Uporabnikova nova usmeritev: prihodnje Android objave so izključno javne.**
Ne ustvarjaj novih internih izdaj in ne nadaljuj internega kanala brez njegovega
novega izrecnega naročila. Lokalni ciljni testi in preverjanje podpisanega
artefakta ostanejo običajni del priprave javne izdaje.

Javna25, aktivna od04:52, v tem koraku ni umaknjena. Do odobritve posodobitve26
ostane prej objavljena različica na voljo. Ni novih runtime/SDK/locks/
dovoljenj/FamilyHub/gostovanj/podatkov/iOS ali spletnih sprememb. Produkcijski
SMTP/FCM in redne kopije ostajajo ločeno nedokončano delo.

Dokazi v `build/qa/public-connection-release-20261014/`: `artifact-and-user-test.json`,
`countries-slovenia.png`, `public-submitted.png/.txt`, `internal-paused.png/.txt`,
`play-release-evidence.json`. Odprta stran Pregled objave ostane za naslednji
pregled izida; ni nastavljena avtomatizacija ali obljuba samodejnega spremljanja.

## Confirmed public availability - 14 October

A fresh production Console read confirms **1.7.1(26) Active / Available on
Google Play from05:48 Europe/Ljubljana**, one country/region. Google completed
the previously submitted review and automatically published the same AAB26.
No new submission, build or release change was performed. The earlier pending
review entry is historical. Evidence: `build/qa/public-connection-release-20261014/public-1.7.1-26-active.png`.

The user reports uninstalling the app while having no data and leaving the
internal test, but still sees the beta label and old images. Propagation of
that account opt-out is not physically verified. Advice: refresh only the
Play Store cache and open the ordinary public URL; do not rebuild or resubmit.
