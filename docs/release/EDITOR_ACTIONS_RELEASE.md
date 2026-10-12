# Jivie 1.5.2 (22) — poravnana dejanja urejevalnikov

12. oktober 2026. Nadaljevanje naročene interne izdaje po uporabnikovi korekciji
telefonskega obrazca. Funkcionalni commit **02cbfec**, metadata **1c39057**.
Obstoječa prijava vsebine je ob naslovu; spodaj so v eni vrstici rdeča ikona
brisanja, besedilni Prekliči in ikona Shrani. Sorodni CRUD obrazci so usklajeni.
[Obseg in uporabnikova odločitev](../EDITOR_ACTIONS_LAYOUT.md).

**133 ciljnih UI testov PASS**, analiza **No issues found**, diff čist.
Preverjene so širine360/320/800/1280, SL/EN, večje besedilo, tipkovnica,
busy/izrecni callbacki in odsotnost prijave v osebnem obrazcu. Sintetični360SL
posnetek je vizualno pregledan. Brez novih funkcionalnih sprememb tega teka
med pripravo izdaje ne ponavljamo.

Podpisani paket `build/releases/Jivie-1.5.2+22-android-firebase.aab`,
**75.914.279 bajtov**, SHA256
`c6989ae89dd125aede9cbc669c73d6508441e2b2409bcf9273509dffd8c33d31`.
Paket/checksum sta read-only. **305 zamrznjenih vhodov** se ujema, agregat
`70b435c4ef9248b7680e9e53801e7f72f92224fe5e8e57c736d584ec70424d24`.

Isti upload certifikat ter Firebase native in vseh Dart ABI identiteta kot21.
`si.triparna.jivie`, min24/target36, Back callback, istih8 dovoljenj brez širokih
media/storage, share FileProvider, bundletool/CRC in PAGE_ALIGNMENT_16K vseh8
64-bitnih knjižnic ter odsotnost zasebnih podpisnih/service-account ključev PASS.
**23 izdajnih +7 Firebase kontrol** ter source checker PASS. Ena gradnja;
predhodna AAB20/21 sta nespremenjena.

**Play Console potrjuje Aktivno /1.5.2(22) od12. oktobra ob08:54**, na voljo
istim notranjim preizkuševalcem **domači(15)**. Naložen je preverjeni AAB22;
AAB21 je iz nove izdaje izključen. Ni izgubljenih ali novo podprtih naprav;
SL/en-US opombe so objavljene. Izdaja je v istem internem kanalu
`4701286726300038561`, račun TriparNA/TaknDevs `4991604398202512900`, aplikacija
`4972659047480717992`. [Povezava za
posodobitev](https://play.google.com/apps/internaltest/4701286726300038561).
QA mapa `build/qa/editor-actions-release-20261012/android/` vsebuje
`android-release-artifact-evidence.json`, `play-release-evidence.json` in
`play-internal-1.5.2-22-active.png`. Fizična nadgradnja telefona še ni potrjena.

Prejšnji AAB21 ostane ohranjen. Podatki, pravice, validacija, potrditve brisanja,
report/policy pogodba, FamilyHub/shema/gostovanje, SDK, lock in podpisna/Firebase
konfiguracija niso spremenjeni. Mac/iOS/javna izdaja niso del tega koraka;
obstoječe meje obnove in končne trgovinske deklaracije ostanejo ločene.
Nova fizična Android nadgradnja in dejanska uporaba tega prikaza še sledita.
