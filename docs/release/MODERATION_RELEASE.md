# Pravila in prijave — test2 ter interna Android 1.5.0 (20)

**Poznejša korekcija prikaza:** uporabnik je zavrnil stalne zastavice ob vrsticah.
[Prijava v meniju ali podrobnostih](../MODERATION_AND_REPORTING.md#uporabnikova-korekcija-prikaza--12-oktober)
je sprememba izvora po tej izdaji. Spodaj navedeni zamrznjeni AAB20 je ne vsebuje;
njegovi hashi in dokaz aktivne objave ostanejo veljavni za prvotni paket.

12. oktober 2026. Po uporabnikovem nadaljnjem naročilu je dejansko nameščen
**FamilyHub0.12.0/schema16 samo na jivie-test2.triparna.si**. Google Play potrjuje
**Aktivno / 1.5.0 (20)** za isti interni kanal in isti seznam **domači (15)**,
od **07:32**. Javna izdaja, iOS, test1 in produkcija niso nadgrajeni.

## Strežnik in sveža kopija

Pred posegom je bila dejanska sveža kopija prenesena v zasebno lokalno mapo in
obnovljena v novi izolirani MariaDB10.11.19 brez omrežja, vrat ali host bindov.
**86 tabel /141 vrstic /2 zasebni datoteki /2 imenika**, vsi hashi vrstic,
definicij, configa in markerja PASS; računi, gesla in naprave so ohranjeni.
SQL/config ostajata zunaj repozitorija in javnega spletnega korena.

Uporabljena stabilna kopija: **32.901 bajtov**, SHA256
`5248b7ae77f53a452b1a8f7e6e99d81d3cc20a8adce1473385adc0c1ad0d5464`.
SQL SHA256 `7f526e2f80d99e37674eaa63b7c0a29e4140d70bb93221743f375249409ee23b`.
Prvi prav tako uspešno obnovljeni arhiv `8e4d2b6f…` je ohranjen, vendar ni bil
uporabljen kot migracijsko izhodišče: odprti Kanboard Dashboard je med pripravo
spremenil hash ene vrstice `sessions`. Ostalih85 tabel je ostalo identičnih.
Zavihek je bil zaprt brez odjave, nato je nova kopija ustrezala vsem živim vrsticam.
Varovala ujemanja podatkov niso bila obšla.

Pregledani nadgradni helper SHA256
`bda2dcd46c8afdaeedd9b52fa0846aed1c8de31cb9b6dea18bee767f2f52fe79`
je preveril fiksni test2 serverId/bazo/config ter 83 starih in 91 novih datotek.
Lokalni dejanski MariaDB preizkus migracije/zamenjave ter pet negativnih varoval
PASS. Preizkus poškodovanega ZIP je najprej razkril predpomnilnik DockerDesktop
bind datotek; ponovljen z zapisom znotraj fixture je potrdil zavrnitev. Guard je
ostal strog. Novi javni izvor ima755/644, zasebne kopije in mape700/600.

Test2 je bil začasno HTTP503 z ohranjenim originalnim API markerjem v zasebni
mapi. Po vsaj65s praznjenja prometa je bila neposredno izvedena samo migracija16
in atomarna zamenjava vtičnika. Preverjanje pred vklopom potrdi:

- **90 tabel**, samo štiri nove prazne tabele za acceptance/reports/audit/blocks.
- Vseh141 predhodnih vrstic ter definicije tabel so ohranjene; edina dovoljena
  metadata sprememba je FamilyHub plugin_schema_versions15→16.
- **1 Native račun /2 napravi**, isti serverId
  `f48b41ae-c6bb-4f2d-ae13-0aa7fa255993`.
- Zasebni podatki, config, Kanboard jedro, HTTPS pravila, SMTP/FCM in cron ostanejo.
- Originalni 83-datotečni vtičnik ter dodatna kopija so ohranjeni zasebno;
  aktivni vtičnik ima točno91 ujemajočih se paketnih datotek.

Ponovni vklop je uspešen: **HTTP200**, isti serverId, moderationContract1 in
sharedContentPolicy1, oba feature flag resnična, javna SL/EN pravila dosegljiva.
Obstoječa spletna prijava `jivie_test2_admin` dejansko odpre **FamilyHub reports**
in pokaže prazni seznam. Prijava ni obnovljena z novim geslom. Agent ni sprejel
pravil v imenu Native uporabnika ali oddal prijave/ukrepa.

Test1 je med maintenance ostal HTTP200 z ID
`95c11fe0-916c-48be-a3f6-999732846266`; njegova0.11.2/schema15 ni spremenjena.
Makova prejšnja aplikacija je bila zaprta za ustavitev sync; ni nadgrajena ali
ponovno odprta. Testni restavratorski vsebniki so ustavljeni, zasebni nosilci in
arhivi ohranjeni. Pre-upgrade helperji so vezani na schema15 in se po tej migraciji
ne uporabljajo kot dokaz nove kopije schema16; pred prihodnjimi posegi pripravimo
svežo kopijo za takratno dejansko shemo.

## Android in trgovina

Metadata commit **9275d92**, funkcionalna osnova **65429ca**; različica
**1.5.0+20**. Paket `build/releases/Jivie-1.5.0+20-android-firebase.aab`,
**75.878.468 bajtov**, SHA256
`fc59ed2d95e5f6a52915da5df1572b998d9f0274f3b1f91679ddc5b6f415edcd`.
Paket/checksum sta read-only; izvirni AAB19 ostane nespremenjen.

- 303 zamrznjeni vhodi se ujemajo; agregat
  `2b719e25acea798d394e789984dc83159527c2b4f9abff7ba73749a8b0eb4b1a`.
- Isti upload certifikat in Firebase native/Dart identiteta kot AAB19.
- `si.triparna.jivie`, min24/target36, Back callback, istih8 dovoljenj brez širokih
  media/storage, share FileProvider, bundle/CRC/16 KiB vseh8 64-bitnih knjižnic PASS.
- V paketu ni zasebnih podpisnih ali service-account ključev. SDK in zaklenjene
  odvisnosti niso spremenjeni. **23 izdajnih +7 Firebase kontrol**, source checker
  PASS. Predhodnih **1028 Flutter PASS/14 skips**, dejanski Dart/HTTP in192 PHP
  kontrol niso ponavljani brez novih funkcionalnih sprememb.

Naložen je točno preverjeni AAB20; AAB19 ni vključen v novi izdaji. Podpora napravam
je nespremenjena (0 izgubljenih/novih), opombe SL/en-US povedo zahtevo FamilyHub0.12.
Kanal `4701286726300038561`, račun TriparNA/TaknDevs `4991604398202512900`, aplikacija
`4972659047480717992`. [Povezava za
posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Dokazi: `build/qa/moderation-release-20261012/{android,server}/`, vključno z
`release-checkpoint.json`, obnovitvenim proofom, HTTPS pregledom ter posnetkoma
`admin-reports-live.png` in `play-internal-1.5.0-20-active.png`.

## Še nepotrjeno

Fizična nadgradnja telefona ter dejanski Native sprejem/preklic pravil, prijava,
admin obravnava/omejitev/odprava omejitve in delo dveh naprav še sledijo z lastnikom.
Nova Mac gradnja še ni nameščena. Na starejšem FamilyHub so skupni uploadi novega
odjemalca zadržani do nadgradnje; lokalno delo, branje in zasebna sinhronizacija
ostanejo ločeni. Posamezen upravljavec mora svoj strežnik nadgraditi in prijave
dejansko obravnavati; test2 namestitev ne nadgradi poljubnih tujih strežnikov.

SL/EN dopolnitev zasebnosti je še lokalni paket, ne objavljena na ločenem računu
jivie.app. Data safety/IARC/javni pregled ostajajo odprti; ta interna aktivacija
ne potrjuje Googlove skladnosti. Meje obnove iz server-loss preizkusa ostanejo.
