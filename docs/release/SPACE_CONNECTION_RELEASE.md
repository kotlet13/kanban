# Android 1.7.1 (26) — povezovanje lokalnega prostora

14. oktober 2026. Funkcionalni popravek **6ae5667**.

## Napaka in popravek

Uporabnik je na Android1.7.0 potrdil osebno sinhronizacijo na produkciji,
pri povezovanju lokalnega Doma pa po potrditvi predogleda vidi le opozorilo
»Pred pošiljanjem skupnih sprememb sprejmite pravila …«. Ciljni test na
prejšnji kodi dejansko odpove: manjka obrazec za pravila. HTTP pregled iste
produkcije potrdi capabilities200/Ideas/record5/moderation1, zato ni dokaz
splošne strežniške odpovedi. SMTP/FCM na produkciji ostajata OFF; to je ločena
nedokončana konfiguracija, ne pogoj za sinhronizacijo.

`LocalSpaceConnectionPanel` po potrditvi predogleda odpre obstoječi obrazec
za pravila izbranega strežnika. Potrditveno polje je prazno; sprejem je izrecen.
Po sprejemu sam nadaljuje isto publikacijo enkrat. Že sprejeta pravila
ne zahtevajo ponovnega sprejema. Preklic ohrani izbiro in lokalne zapise;
nedosegljiva pravila ali neuspešen sprejem ne začneta prenosa. Pred prenosom
se ponovno preveri ista prijava/naprava/veljavna seja; menjava računa zapre
obrazec. Predogled ostane pred sprejemom in objavo. Pravila niso sprejeta
v imenu živega uporabnika.

## Preverjanje

- **29 ciljnih UI/podatkovnih testov PASS**, vključno z dejansko lokalno
  publikacijo, pravili, preklicem, menjavo računa, omrežno napako in ponovnim
  poskusom. Pet novih scenarijev povezovanja dopolnjuje dva obstoječa.
- **7 testov povezovanja PASS** tudi v izoliranem izvoru nove gradnje.
- Ciljna analiza in celotna analiza izoliranega mobilnega izvora: **No issues
  found**. Main ima 10 informativnih ugotovitev v prej obstoječih pripomočkih
  za posnetke trgovin; nobene napake/opozorila ali ugotovitve v popravku.
- Izdajni/Firebase preizkusi **23+7 PASS**, source checker PASS.

## Podpisana gradnja

Paket `build/releases/Jivie-1.7.1+26-android-firebase.aab`: **78.421.130 bajtov**,
SHA256 `ef803a085ac955219946ce7ed6143429438816173d53d4f30b6f7e1eafbf2b4d`.
Paket/checksum sta read-only; AAB25 je ohranjen.

Gradnja uporablja izolirani izvor **fa809b8 / AAB25** z natanko dvema spremenjenima
vhodoma: `local_space_connection_panel.dart` in različico v `pubspec.yaml`.
Vseh **320 zamrznjenih vhodov** je preverjenih pred/po gradnji; dodatne
namizne spremembe iz main niso vključene. SDK, oba locka, private konfiguracijski
hashi, upload certifikat, native/Dart Firebase identiteta in istih8 dovoljenj
ostajajo isti. Bundletool/CRC/podpis ter16KiB vseh8 64-bitnih knjižnic PASS.
Sheme, podatkovni formati, FamilyHub in živa gostovanja niso spremenjeni.

## Interna dostava

Preverjeni AAB26 je naložen samo v obstoječi interni kanal
`4701286726300038561`, isti račun4991604398202512900/aplikacija4972659047480717992.
Console dejansko potrjuje **Aktivno od14. oktobra05:24**, na voljo notranjim
preizkuševalcem. Samo AAB26 v novi izdaji,25 izključen;0 izgubljenih/novih
podprtih naprav. Lokalna gradnja in Console nista dokaz nameščene posodobitve
na telefonu. Seznam ostane **domači(15)**. [Posodobitev](https://play.google.com/apps/internaltest/4701286726300038561). Javna Android izdaja25 in iOS25 v tem koraku
nista nadomeščeni ali umaknjeni. Uporabnik je naročil najprej interno preverjanje,
šele nato obravnavo prekinitve javne objave.

Dokazi: `build/qa/space-connection-release-20261014/` (pre-fix/finalni testi,
ciljna analiza) in podmapa `android/` (izolirani izvor/manifesta/gradnja/analiza/
artifact/bundle/podpis/dovoljenja/16KiB/Console).

## Svež pregled javnega stanja — samo za branje

Nov nepredpomnjen zavihek produkcijskega kanala potrdi **1.7.0(25) Aktivno /
Na voljo v Googlu Play od14. oktobra04:52**, ena država/regija. Starejši zapis
»Spremembe v pregledu« je zgodovina; starega zavihka brez ponovnega nalaganja
ne uporabljaj kot dokaz trenutnega pregleda. Google je zaključil prej oddano
izdajo s samodejnim objavljanjem. Agent v tem koraku **ni** umaknil javne izdaje,
jo nadomestil ali spremenil držav/upravljanega objavljanja.26 je samo interna.
Po uporabnikovem fizičnem preizkusu sledi odločitev o javni posodobitvi ali
umiku že aktivne25, ne prekinitev zdaj zaključenega pregleda.

Dokaz: `android/public-aab25-active-readonly.png`; javna dostopnost je potrjena
v produkcijskem Console, ne z novo fizično namestitvijo v trgovini.

## Kratki fizični preizkus

Posodobi na1.7.1 prek istega internega Play opt-in naslova. V Račun in deljenje
izberi lokalni Dom → Poveži in sinhroniziraj → potrdi predogled → preberi in
izrecno sprejmi pravila. Povezovanje mora nadaljevati in Dom mora postati skupen
prostor. To uporabniško potrjevanje po tej objavi še sledi; brez njega ni
fizičnega dokaza uspeha popravka.
