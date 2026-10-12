# Idejnik — test2 FamilyHub 0.13 in interna Android 1.6.0 (23)

12. oktober 2026. Po izrecnem naročilu naslednjega koraka je **test2 dejansko
FamilyHub 0.13.0/schema17**, interna **Android 1.6.0 (23) pa Aktivno za domači (15)
od 11:52**. Funkcionalna osnova je `03ce0de`, izdajni metadata commit `528185a`.
[Preverjena izvedba](../IDEAS_IMPLEMENTATION.md) ostane vir funkcionalnih dokazov;
teh med izdajo brez novih funkcionalnih sprememb nismo ponavljali.

## Sveža kopija in ohranitev strežnika

CPanel prijava tripar13 je bila veljavna. Dejanski PHP8.4.26 preflight potrdi GD
JPEG/PNG encode/decode, točno obstoječo konfiguracijo, serverId, schema16 in vseh
91 datotek starega vtičnika. Odprta skrbniška stran je bila pred kopijo zaprta
brez odjave. Pomočnik zajame vse InnoDB tabele pod bralnimi ključavnicami,
polne CREATE definicije, vrstice, celoten zasebni DATA tree s praznimi imeniki,
zasebni/root config, HTTPS pravila in omogočeni marker. Ne zažene aplikacije,
dostavnih delavcev ali sprememb SQL vrstic.

Sveža kopija ima **33.954 bajtov**, SHA256
`56e5973573781874d61ebde284ae87ec7466a0fc572035e1129365d2df7aa385`;
SQL SHA256 `48c154282f0a9094110cd9722478b67915bdb8492936828f77be9a214ac6b219`.
Prenesena je zunaj Gita/javnih map v lokalno zasebno mapo0700/datoteko0600.
Dejansko obnovljena v novi **MariaDB10.11.19, network=none, brez vrat ali host
bindov, samo anonimni MySQL volume**: **90 tabel,149 vrstic,2 datoteki,2 imenika**.
Vsi hashi vrstic, definicij, podatkov, configa in markerja PASS; seje, računi,
gesla in identiteta so ohranjeni. Obnovitveni vsebnik je po preverjanju ustavljen,
volume in arhiv ostaneta. Stari varnostni vsebniki niso spremenjeni.

[Varovani pomočniki](../../server/scripts/ideas-test2/README.md) so pred uporabo
preverjeni s polnim nepraznim sintetičnim Kanboard/MariaDB fixture, dejanskim
izvozom/obnovo/zamenjavo in **11 negativnimi varovali PASS**. Nadgradni pomočnik
SHA256 `0c2747de266f29e814d0c30519e7915528feb38304b41dec32ac6457a6c06480`.
Živo staging/pre-pause preverjanje zahteva ujemanje vsake vrstice/datoteke s prav
tej dejansko obnovljeno kopijo; stara schema15 kopija/proof nista dovoljena.

Test2 je začasno vrnil HTTP503. Po najmanj65 dejanskih sekundah praznjenja prometa
je nameščena samo migracija17 in atomarno zamenjan vtičnik:

- **92 tabel**: natanko dve novi prazni tabeli asset metadata/report references.
- Vseh149 starih vrstic in njihovih definicij je ohranjenih; edina dovoljena
  metadata sprememba je FamilyHub plugin_schema_versions16→17.
- Isti serverId `f48b41ae-c6bb-4f2d-ae13-0aa7fa255993`,1 Native račun/2 napravi.
- Zasebni podatki, config, Kanboard jedro in HTTPS so nespremenjeni; prvotni
  vtičnik je ohranjen v dveh zasebnih izvornih kopijah. Aktivnih96 paketnih datotek
  se natančno ujema s preverjenim ZIP00df4cec… .
- Dejanski cron hash pred/po je isti
  `17070a1aa68e2f62c5940cfe9fc966a85a58118fa2f14125b4f4f0644e24564b7`.
  SMTP/FCM konfiguracija ni spremenjena; na test2 oba ostaneta izključena.

Pred ponovnim vklopom je ohranitev preverjena še enkrat. Preneseni dejanski
`release-checkpoint.json` potrdi fazo released. HTTPS API vrne **200**, isti ID,
record `[1,2,3,4,5]`, `recordTypesV5.idea`, **ideas/ideaAssets=true** v spletnem PHP
ter ohranjene prijave/pravila. Novi slikovni in sync5 endpoint brez prijave vrneta
**401/auth_required**. Obstoječa skrbniška prijava odpre prazen seznam prijav;
noben Native sprejem pravil, prijava vsebine ali admin ukrep ni oddan.

Test1 ostane HTTP200/isti95c1 ID in record1–4, njegova0.11.2/schema15 ni nadgrajena.
Produkcija je nespremenjena. Po prehodu pomočnika16 ne uporabljamo kot kopijo17;
naslednji poseg potrebuje novo kopijo takratne sheme z dejanskimi fotografijami.

## Android in Google Play

Ena podpisana gradnja: `build/releases/Jivie-1.6.0+23-android-firebase.aab`,
**78.404.412 bajtov**, SHA256
`b811a2cc800e41ae84cf59de3dfd6b7f814c767b4e5495cbdffb2ed39da70183`.
AAB/checksum sta read-only; AAB22 je ohranjen. **317 zamrznjenih vhodov PASS**,
agregat `fadde8089951f4a6e4b4a9d704d80cb13adabda5a690babb9a66f404fa28e3ea`;
metadata commit veže iste hashe brez nove gradnje.

Isti upload certifikat ter Firebase native in vsi Dart ABI kot22. Paket
`si.triparna.jivie`, min24/target36, Back callback, istih8 dovoljenj brez kamere
ali širokih media/storage, share FileProvider, bundletool/CRC in PAGE_ALIGNMENT_16K
vseh8 64-bitnih knjižnic PASS. Zasebnih podpisnih/service-account ključev ni.
**23 izdajnih +7 Firebase kontrol**, source checker PASS. SDK/zaklenjene različice
ostanejo; že zaklenjena image4.7.2 je zdaj runtime odvisnost.

Naložen je točno preverjeni AAB23. Predogled potrdi0 izgubljenih/novih naprav,
izključeni22 in opombe SL/en-US z zahtevo FamilyHub0.13 za sinhronizacijo Idejnika.
Po potrditvi Play Console kaže **Aktivno /1.6.0(23)** od12. oktobra **11:52**,
za isti označeni seznam **domači(15)**; drugi seznami niso vključeni. Kanal
`4701286726300038561`, račun TriparNA/TaknDevs `4991604398202512900`, aplikacija
`4972659047480717992`. [Posodobitev za interne
preizkuševalce](https://play.google.com/apps/internaltest/4701286726300038561).

Dokazi v `build/qa/ideas-release-20261012/{android,server}/`: frozen inputs,
artifact/play evidence, aktivni Play posnetek, obnovitveni proof, dejanski
checkpoint, HTTPS/GD/anonymous pregledi, cron in skrbniška stran. QA izvoz
ne vsebuje SQL, config vsebine, gesel ali fotografij uporabnika.

## Naslednji fizični korak in meje

**Fizična posodobitev telefona in preizkus novega Idejnika še nista potrjena.**
Uporabnik na test2 preveri tablo s fotografijo/oznako, ponovno odpiranje, deljenje
in obvestilo v aplikaciji. Dostava oddaljenega push/SMTP na test2 ni nov dokaz;
oba sta po prvotnem dogovoru izključena. Mac/iOS nista nadgrajena ali nameščena.
Splet jivie.app ostane nespremenjen; SL/EN zasebnost s fotografijami je pripravljena
lokalno. Data safety/IARC in javna oddaja ostajajo ločeni odprti koraki. Ne razglasi
javne izdaje ali celotnega protokola izgube strežnika za zaključena.
