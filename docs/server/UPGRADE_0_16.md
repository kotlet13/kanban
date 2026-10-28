# FamilyHub 0.16.0 / shema 23 — produkcijska nadgradnja

28. oktober 2026. Uporabnik potrdi javno objavo Android 1.11.0 (32) in
izrecno naroči nadgradnjo `https://jivie.triparna.si/`.

## Trenutno stanje

**Produkcijska nadgradnja je zaključena.** FamilyHub 0.16.0, shema 23,
javni HTTPS API deluje. Vzdrževanje je trajalo približno 19:11–19:17 UTC;
pet obstoječih opravil je ponovno vključenih, dodano je omejeno opravilo
za varnostna e-poštna obvestila. Končni dokaz je zajet ob 19:18:26 UTC.
Pregledovalci: GPT 6.1 Sol / high, root integracija in pregled.

## Dejanski izid namestitve

- `prepare`, `pause`, polna kopija, dejanska lokalna obnova, `stage`, `apply`,
  `release-http` in `release-workers`: uspešno v prvem produkcijskem poskusu.
  `release-http` vključuje obvezno preverjanje; ločeni ponovni `verify` ni bil
  potreben. Pred kopijo je preteklo več kot 65 dejanskih sekund praznjenja.
- Sveža kopija: `backups/crypto23-preupgrade-20261028-191245-b7bd89f3/`
  `Crypto23-private-backup.zip`, 5.028.325 bajtov, 2.335 vnosov, SHA256
  `23edf1e0074ee25203806db9bf4452144791dfc3d78a5bfc0fd7b79ce77742b3`.
  Zasebni izvod ostane na gostovanju in na Macu zunaj Git repozitorija.
- Obnova v ločeni MariaDB 10.11.19 brez omrežja, vrat ali gostiteljskih
  priklopov potrdi vseh 98 tabel/684 vrstic, definicije, datoteke, prazne
  imenike, celoten izvor, konfiguracije, ključe in cron. Aplikacija ali
  opravila se med to obnovo niso zaganjala. Dokaz `restore-proof.json`.
- Migracija: 98 → 225 tabel; 127 novih tabel je bilo pred odprtjem API-ja
  praznih. Vse stare vrstice ostanejo enake, razen pričakovane metapodatkovne
  različice FamilyHub 19 → 23. Ohranjeni so trije računi in pet naprav.
- Nameščenih je vseh 200 datotek preverjenega paketa. Konfiguracije SMTP,
  FCM, ključi, identiteta strežnika in izvirna pravila HTTPS so ohranjeni.
- Dejanski anonimni javni HTTPS200 potrdi isto identiteto, šifrirna protokola
  1/2, prehod 3, povabila 4, zavrnitev povabila, iskanje prejemnikov,
  pravila zapisov in `accountChanges`. Šele nato so bili obnovljeni croni.
- Končni `release-checkpoint.json`: `phase=released`, `apiPaused=false`,
  `workerCronRestored=true`, `securityMailCronAdded=true`, ohranitev potrjena.
- Združeni zasebni dokaz `deployment-result.json`, SHA256
  `9538f4589da5d62823bb49779397325dac2cf2a1264c9994bcf4c90a15a464d5`;
  hash prenesenega izvoda je enak gostovanemu. Vidna potrditev je v
  `build/qa/production-upgrade-20261028/production-upgrade-complete.png`.

Ni novih prijav, uporabnikov, povabil ali poslovnih zapisov za preizkus
produkcije. Telefoni niso bili spreminjani. Prvi uporabnikov prehod skozi
pripravo zaščite in obnovitvene datoteke na javni različici še ni potrjen.
Naslednji korak je ponovno odpreti nadgrajeno aplikacijo in preveriti njen
prvi zaslon; odjava ali ponovna namestitev nista del postopka.

## Izhodišče in varovala

- Produkcija: `/home/tripar13/jivie.triparna.si`, baza `tripar13_jivieprod`,
  zasebni koren `/home/tripar13/private/jivie-production`.
- Identiteta ostane `ad56910f-ca2e-41ee-af0d-3f18081497cf`.
- Sveži zajem potrjuje shemo 19, MariaDB `10.11.19-MariaDB-cll-lve-log`,
  107 gostovanih datotek, natančno enakih manifestu zadnje nadgradnje 0.15.0.
- Zajem: zasebni `capture-0.16.0-20261028-r1/capture.json`, SHA256
  `14e58ba2133c64f881de1fab5677d243f3a7a3fea5af4bc02290914e5dacaa49`.
- Produkcijski `prepare` potrdi 98 tabel, tri račune, pet naprav, dve DATA
  datoteki, odsotnost dodatnih pogledov/sprožilcev/rutin/dogodkov in vseh
  107 starih izvorov. Ciljni paket ima 200 datotek, SHA256
  `b16fb64602013d86cdac48fa220b36419cff59637aa257af22a7a0ce4f6f1bd5`.
- Zasebni WORK: `upgrade-0.16.0-20261028-190905`; vseh 17 datotek pomožnega
  namestitvenega sklopa je po prenosu preverjenih po SHA256.
- Lokalni zasebni dokazi: `~/.local/share/jivie/backups/crypto23-production-20261028-r1/`.
- Pred posegom: zaustavitev samo ciljnih delavcev in API, praznjenje, polna
  sveža kopija baze, datotek, konfiguracij, ključev, izvora in crona;
  dejanska izolirana obnova pred migracijo. Nobeno staro uspešno funkcionalno
  preverjanje se zaradi te priprave ne šteje kot novo preverjanje.

## PHP in odvisnosti

Začetni PHP 8.4.27 CLI ni imel Sodium. Uporabnik je izrecno odobril vklop
Sodium v nastavitvah celotnega računa tripar13 za PHP 8.4, ker ponudnikov
izbirnik ne ponuja vklopa samo za Jivie. Izveden je en klik na Sodium.
Različica PHP in druge aplikacije niso bile urejane.

Po vklopu sta dejanski CLI in spletni SAPI `litespeed` potrdila Sodium,
podpise, XChaCha20, generic hash, memzero, OpenSSL, cURL, PDO MySQL,
mbstring in Zip. Zasebni DATA je zapisljiv; CLI preveri podpisni in AEAD
prehod v pomnilniku. Spletni diagnostični PHP je bil takoj po preverbi
premaknjen iz javnega korena v zasebni imenik; ne vsebuje podatkov uporabnikov.
`/usr/bin/timeout` je prisoten (GNU coreutils 8.32).

Po osvežitvi izbirnika sta poleg Sodium drugače prikazana še `nd_mysqli`
in `pdo_mysql` (prej označena, potem neoznačena). Ročno je bil kliknjen samo
Sodium. Ne sklepamo, da so bili drugi moduli ročno spremenjeni; dejanska
`mysqli` in PDO MySQL delujeta, produkcijski PDO zajem je uspešen.
Pred/po prikaz izbirnika in dokaz izvajanja sta v
`build/qa/production-upgrade-20261028/`.

## Pregled migracije in obseg

Neodvisno izpeljana shema 19 → 23 v sveži izolirani MariaDB: 98 → 225 tabel,
127 novih praznih tabel. Obstoječim tabelam se dodata samo dva števca z
začetno vrednostjo 0 in trije indeksi povabil. Vsaka stara vrednost se mora
ujemati s svežo kopijo; dovoljena je migracijska metadata 19 → 23.

Nova konfiguracijska zastavica `FAMILYHUB_ENABLE_CRYPTO_PREVIEW=true` omogoči
šifrirni protokol in potrjeno e-pošto za povezane vnose. Sama nadgradnja
strežnika **ne šifrira obstoječih podatkov uporabnikov**: pripravo ključev in
prenos obstoječih vsebin opravi odjemalec. Starih podatkov ali kopij ne brišemo.
Dogovorjena hramba 30 dni začne teči šele po dokazano uspešni obnovi nove
šifrirane kopije, ne na dan te namestitve.

Pet obstoječih produkcijskih opravil ostane ohranjenih. Potreben je še šesti
omejeni `security-mail.php` za obvestila ob inicializaciji, spremembah naprav
in obnovitvi računa. Samodejni testni uporabniki, prijave ali povabila niso
del te produkcijske nadgradnje.
