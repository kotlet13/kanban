# Jivie 1.4.1 (19) — popravki sinhronizacije in kopij

11. oktober 2026. Uporabnik je naročil novo Android gradnjo s popravki in
nadaljevanje izdaje. Metadata commit `1b7e7f6` je na main/origin. Kandidatka
vključuje že preverjene funkcionalne popravke `d627bbe`, `1284ca3` in `3d91b37`:
izbor prostora po objavi, prvi prenos evidence osebnega plačila, razumljiv
predogled kopije ter izvoz čakajočega dela med neprotokolnim HTTP 5xx izpadom.
Veljavne strežniške zavrnitve pravic ostanejo strogo upoštevane.

## Preverjen paket

`build/releases/Jivie-1.4.1+19-android-firebase.aab`, **75.704.082 bajtov**, SHA256
`f85606796ee837e61e376a54b6188f4c8c3a06edf37795124e561e4c3ea46895`.
Paket in kontrolna vsota sta read-only; AAB18 ostane ohranjen.

- 300 zamrznjenih vhodov iz `1b7e7f6` se po gradnji ujema; agregat
  `b2f835ea577d31fcf731941ab0c7f1e9216d7f26cd206dc4cfc18ea0b6b283cd`.
- `si.triparna.jivie`, 1.4.1 (19), min24/target36 ter Android Back callback PASS.
- Podpisni certifikat in Firebase native/Dart identiteta so enaki AAB18.
- Istih osem dovoljenj kot AAB18, brez širokih storage/media dovoljenj;
  share FileProvider je ohranjen, stari open_filex provider odsoten.
- Bundletool validate, ZIP CRC, PAGE_ALIGNMENT_16K in osem 64-bitnih knjižnic PASS.
- V paketu ni zasebnih podpisnih ali service-account datotek/ključev.
- 23 izdajnih + 7 Firebase kontrol ter source checker PASS. Funkcionalni izvor
  je že imel **1002 Flutter PASS / 13 opt-in preskočenih** in analizo brez
  ugotovitev pri `3d91b37`; brez novih funkcionalnih sprememb celotni testni krog
  ni ponovljen. SDK, zaklenjene odvisnosti in strežniki niso nadgrajeni.

Dokazi gradnje so v ignorirani `build/qa/android-fixes-release-20261011/android/`.
Nameščeni Mac ima popravke; fizična Android nadgradnja te kandidatke še ni potrjena.

## Play Console in meja javne objave

**Play Console potrjuje Aktivno / 1.4.1 (19) od 11. oktobra ob 21:55**, na voljo
istim notranjim preizkuševalcem domači (15). Naložen je preverjeni AAB19 v isti
interni kanal `4701286726300038561` računa TriparNA/TaknDevs
`4991604398202512900`, aplikacija `4972659047480717992`. AAB18 je iz nove izdaje
izključen; SL/en-US opombe so objavljene. Podpora napravam se ni spremenila
(0 izgubljenih/novih). Dokaz: `play-internal-1.4.1-19-active.png` in
`play-release-evidence.json` v zgornji QA mapi. [Povezava za
posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).

Povezava `https://jivie.app/privacy/` je dejansko shranjena za objavo, HTTPS 200.
Varnost podatkov je shranjena kot **osnutek**, ne dokončna deklaracija: izbrane
so ime, e-pošta, ID uporabnika, naslov prostora, stiki/osebe in članstva,
zgodovina nakupov, drugi finančni podatki, koledarski dogodki, druga uporabniška
vsebina ter ID naprave. Namen, izbirnost
in obravnava posameznih vrst še potrebujejo dokončan obrazec.

Ponovno odprtje IARC osnutka pokaže neoznačen sprejem pogojev. Poskus »Naprej«
brez sprejema je zavrnjen z »Če želite nadaljevati, morate sprejeti pogoje
uporabe.« Agent novega pravnega soglasja ni označil; zahteva potrditev lastnika
ob tem dejanju po pravilih upravljanja brskalnika.

Aktualni deljeni zapisi še nimajo toka sprejema uporabniških pogojev ter prijave
vsebine in uporabnika v aplikaciji. To je dejanska odprta zahteva Googla tudi
za zaprto sodelovanje; ni ostanek odstranjenega AI/vmesnika. [Google UGC
policy](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en).
Zato ta interna izdaja ne pomeni, da je javna sodelovalna kandidatka že oddana
ali odobrena. Ni novega kroga fizičnega server-loss testa; njegove preverjene
meje ostajajo v [končnem izidu](../server/SERVER_LOSS_TEST.md#končni-izid-tega-preizkusa--11-oktober-2059).

Enkratni aktualni izvorni pregled potrdi predlog: teh deset kategorij je zbranih,
nekratkotrajnih in izbirnih glede na lokalno osnovno uporabo. Namen je delovanje
aplikacije; ime/e-pošta/uporabniški in napravni ID še upravljanje računa.
Izjeme za uporabniško sproženo deljenje ter ponudnike je treba pred končnim
odgovorom Shared preveriti za dejansko konfiguracijo. Izvor ne utemeljuje novih
deklaracij AI, medijskih datotek, lokacije ali analitike. Osnutek ne pomeni
potrjene skladnosti ali dokončanega Googlovega pregleda.
