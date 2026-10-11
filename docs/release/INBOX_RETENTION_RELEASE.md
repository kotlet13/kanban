# Interna izdaja popravkov obvestil — 11. oktober 2026

Uporabnik je naročil commit/push, nadgradnjo testnega strežnika, novo Mac gradnjo
in Android interno objavo. Produkcija, javna objava, iOS ter merge na main niso
del tega koraka.

## Izvor in preverjanje

Funkcionalni commit `74aa41c`, aplikacijska različica `eafb30b` ter priprava
FamilyHub/pomočnika `8de8cc7` so na `origin/codex/email-invitations`.
App **1.3.2+17**, FamilyHub **0.11.2/schema15**. SDK, zaklenjene odvisnosti,
platformne identitete in podpisne nastavitve so ohranjeni.

[Funkcionalni dokazi](../INBOX_READ_STATE_AND_RETENTION.md): 978 Flutter PASS,
13 opt-in preskočenih, 786 PHP kontrol na treh bazah; analiza brez napak in
opozoril, 35 podedovanih info. Izdajni korak: 18 izdajnih in 7 Firebase testov,
source checker, 10 paketnih testov ter 34 filesystem/22 MariaDB kontrol pomočnika
PASS.

## Testni strežnik

Sveža kopija je dejansko obnovljena v novi izolirani MariaDB 10.11.19,
`network=none`, brez aplikacije in delavcev: **86 tabel, 273 vrstic in 5.886
zasebnih datotek**. Preverjeni računi/gesla/enrollment/serverId. Vsebnik je
ustavljen, zasebna kopija je zunaj repozitorija in spletnih map.

- Izvorni ZIP SHA256 `8108791ef3c5dd39f295395b1a5c5164ba58c2f21bc5c36722b0fe7244d857b4`.
- Kopija SHA256 `25742e0f82945203194df9cf3c938abc99e57c610099478070b2240e9828e1b7`.
- [Pomočnik in postopek](../server/INBOX_RETENTION_UPGRADE_HELPER.md).
- Aktivacija 0.11.2/schema15 in odprtje testnega strežnika sta uspešna.
  Manifest vseh 83 datotek, računi/gesla, serverId, konfiguracija, shranjeni
  izklopi obvestil in izvirni cron so ohranjeni; podatki niso ponastavljeni.

Po odprtju preverjevalnik ob 08:26 potrdi sveže redne zagone opomnikov,
pošte računov, dostave in push; vsi imajo veljavno obliko stanja ter nič napak.
Čiščenje prebranih obvestil je vrnilo 0 odstranitev (ni primernih starih zapisov).
Zadnji zagon delavca izbrisa računov je ob 08:20, pred odprtjem; njegov cron je
ohranjen, novega zagona nismo potrdili, ker je seja cPanel med čakanjem potekla
(401 ob 08:31). To ne blokira opomnikov ali objavljene izdaje.
Dokaz: `build/qa/inbox-retention-release-20261011/server/hosted-verification.json`;
obnovitveni dokaz: `server/restore-evidence.json` v isti mapi QA.

## Android

Podpisani `build/releases/Jivie-1.3.2+17-android-firebase.aab` ima 79.463.152
bajtov, SHA256 `4b2cdb69f9b8278f6f1576057f68541244d2178bcfa19b0366297826855d2528`.
331 zamrznjenih vhodov, isti podpis kot 16, `si.triparna.jivie`, min24/target36,
enaka dovoljenja, Back callback, vseh osem 64-bitnih knjižnic 16 KiB ter native/Dart
Firebase so preverjeni. Dokazi: `build/qa/inbox-retention-release-20261011/android/`.
Google Play potrjuje **Aktivno**, izdano **11. oktobra ob 08:26** za isti
seznam **domači (15)**, naslov `1.3.2 (17) — preglednejša obvestila`.
Dokaz: `build/qa/inbox-retention-release-20261011/android/play-internal-1.3.2-17-active.png`.
[Testni dostop](https://play.google.com/apps/internaltest/4701286726300038561).

## Mac

Nova podpisana **1.3.2 (17), arm64 Debug** je odprta iz
`build/qa/jivie-retention-mac-20261011/SignedProducts/Debug/Jivie.app`.
Strogi globoki podpis, isti certifikat/profil/Keychain, `com.example.kanban`,
328 vhodov in vseh 297 skupnih Android/Mac hashov PASS. Stari artefakti ostanejo.
To ni notarizirana oziroma Mac App Store distribucija.

UI potrdi račun takndev, testni URL, izbrani projekt poskus deljenja in obstoječa
obvestila. Center že prikazuje ločeni oznaki Prebrano/Neprebrano. Njihovega stanja
nismo spreminjali za dokaz; uporabnikov fizični preizkus še sledi. Med strežniškim
vzdrževanjem so bila lokalna obvestila dostopna. Po odprtju sta ponovni pregled
računa in potrjene e-pošte uspela brez napake. Prikazanih je sedem obvestil:
eno neprebrano in šest prebranih; prijava in izbira projekta sta ohranjeni.

## Fizični preizkus

Posodobi Android na 1.3.2 (17), preveri krepkejše neprebrano obvestilo, njegovo
označitev in ponovno označitev kot neprebrano. Tedenski rok je preverjen s
premikom ure v avtomatiziranih testih; sedem resničnih dni še ni preteklo.
Mac še vedno podpira center v aplikaciji, ne oddaljenega sistemskega push.
