# Javni FamilyHub0.13.0 — 13. oktober2026

Po izrecnem uporabnikovem naročilu je **FamilyHub javno objavljen** v njegovem
pripravljenem repozitoriju
[kotlet13/kanban_family_hub](https://github.com/kotlet13/kanban_family_hub).
Repozitorij je bil prazen in public, dostop za objavo potrjen. Objavljena sta
`main` in označena izdaja `v0.13.0`; prvi commit je
`7571d1be1554255f6b702e6fe895af2b3b9ee81a` z **nič starši**.
Lokalni samostojni checkout: `/Users/anzenovsak/Git/kanban_family_hub`.

## Licenca in plačljivo gostovanje

Ohranjena je obstoječa **MIT** licenca s copyrightom TriparNA v popolnoma istih
bajtih. Preverjen [Kanboard1.2.54/LICENSE](https://github.com/kanboard/kanboard/blob/v1.2.54/LICENSE)
je MIT, copyright Frédéric Guillot. MIT dovoljuje komercialno uporabo,
spreminjanje, distribucijo in prodajo; pri distribuciji kopij oziroma bistvenih
delov ostaneta avtorsko in dovolilno obvestilo. [Primarno besedilo MIT](https://opensource.org/license/mit).

Priporočilo za uporabnikov namen je ohraniti MIT: zaračunavanje lastnega
gostovanja, namestitve in podpore je dovoljeno. Ista dovoljenja imajo drugi
ponudniki; licenca ne zagotavlja izključnega gostovanja in ne zahteva javne
objave lastnih sprememb. Lastna znamka/ponudba in delovanje storitve so ločeni
od dovoljenja za izvorno kodo. Ob distribuciji celotnega Kanboarda z odvisnostmi
ohrani njihove lastne licence/obvestila. V javnem FamilyHub paketu ni njegovega
jedra ali vendor knjižnic; NOTICE opisuje ločeni Kanboard/Swift Mailer dependency.
Izbira licence sama ne ustvari obračunavanja ali avtomatske vzpostavitve gostovanja.

## Čista izvorna objava

Osnova je preverjeni source-only ZIP0.13.0, SHA256
`00df4cec3baebb66d4e67adad20c235149529b2ee9853b614b0a74ef85cfbe52`,96 datotek.
Ni rekurzivnega izvoza aplikacijskega repozitorija ali prenosa njegove Git
zgodovine. **Vseh87 PHP datotek je bajtno enakih** izvoru te izdaje.

Javni repo ima105 pregledanih datotek: vtičnik/pogodbe, aktualni README,
MIT LICENSE/NOTICE, CHANGELOG, SECURITY, konfiguracijski primer brez gesel,
izrecni runtime manifest/paketor in namestitveni ZIP s checksumom. README ima
dejanski tag URL ter navodila za potrebePHP8.1+/Kanboard1.2.54/GD, HTTPS,
konfiguracijo, backup/migracijo, račune in izbirne delavce. Dve zlomljeni
povezavi na interni izvedbeni dnevnik v pogodbi sta zamenjani z jasno navedbo,
da dnevnik ni del javnega paketa. Vse lokalne dokumentacijske povezave so veljavne.

Izvoz ne vsebuje konfiguracij namestitev, poverilnic, service-account datotek,
baz/SQL, priponk, kopij, dnevnikov, testnih računov, internih gostovanih
pomočnikov, Android/iOS/Mac aplikacije ali starih commitov. Skeniranje vseh
objavljenih datotek zavrne znane poverilnice/PEM/GitHub žetone ter konkretne
interne račune, strežniške ID, baze in poti. To je omejeni pregled izvoznega
obsega, ne trditev novega popolnega varnostnega pregleda aplikacije.
Prvi commit uporablja potrjeno GitHub ID-based noreply identiteto; osebni
poštni naslov ni objavljen in globalne Git nastavitve niso spremenjene.

## Preverjanje in javni prenos

- PHP8.4.24 tokenizer PASS za vseh88 PHP datotek, vključno s konfiguracijskim
  primerom; brez zagona aplikacije ali migracije.
- Namestitveni ZIP ima **97 izrecno dovoljenih datotek** pod `FamilyHub/`;
  Git metapodatki, primer konfiguracije in orodja se ne namestijo v web root.
- SHA256 ZIP-a:
  `b90c73a7f565ae9ac766853aaf3544b9de96753a6252bb986937f630b3a514e9`.
- Dejanski anonimni
  [prenos ZIP](https://github.com/kotlet13/kanban_family_hub/raw/refs/tags/v0.13.0/dist/FamilyHub-0.13.0.zip)
  vrneHTTPS200; CRC,97 imen in vsak bajt/hash se ujema z pregledanim izvozom.
  Javni LICENSE se ujema z izvorom, API potrdi public/main/pravilen commit in tag.

Dokazi: `build/qa/familyhub-public-20261013/{upstream-export,publication-check,
publication-evidence}.json`. Javna izvorna licenca in paket sta preverjena;
prejšnjih funkcionalnih testnih matrik nismo ponavljali ob nespremenjeni kodi.

To ne spreminja nameščenih strežnikov, njihovih shem ali podatkov. AndroidAAB25,
SDK/locks/dovoljenja, namizna aplikacija, spletna stran, Play osnutek in javna
mobilna oddaja ostajajo isti. Naslednji mobilni korak ostaja ista AAB25/države/
Pregled objavljanja. Pri naslednji izdaji vtičnika posodobi pregledani samostojni
repo in ustvari nov tag/paket; obstoječega v0.13.0 ne prepiši.
