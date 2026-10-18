# E2EE: dva uporabnika na fizičnem Androidu in iOS — 18. oktober 2026

**Aktualni checkpoint: Save ima dokazan `record_missing` in pregledani
izvorni popravek; fizični izid novega paketa še PENDING.**
[Naravni old FAIL](../build/qa/jivie-mobile-two-user-20261018/shared-task-native-child-repro/old-failure-evidence.json)
je po dejanskem podpisanem ustvarjanju native organizacije/projekta in pullu
potrdil eno `scopeMetadata`, nič kanoničnih `project` vrstic in izjemo pri
prvem `repository.createTask`. `_record` je pravilno zahteval dejanskega
projektnega starša; preverjanja se ne preskočijo.

Trije runtime popravki v `crypto_domain_router.dart`, `crypto_business_router.dart`
in `collaboration_record_actions.dart` ustvarijo en dejanski podpisani/šifrirani
projektni koren z **istim child ID**. Obstoječi child brez korena se popravi
pred izrecnim lokalnim urejanjem, zunaj njegove SQL transakcije. Zahtevani so
sveža avtoriteta, podpisani native origin/kind/parent token, owner/lifecycle,
popoln preverjeni content inventory in običajni write/CAS. Obstoječi podatki,
phase/reference varovala in `_put` ostanejo; tombstone se ne obudi, migrirani/
relocated koren se ne nadomesti. Payload/request je trajen pred prenosom;
pri naslednjem izrecnem poskusu se uporabi preverjeni obstoječi zmagovalec,
brez prepisovanja zapečatenega zahtevka ali samodejne zanke ponovitev.

[Vezani končni dokazi](../build/qa/jivie-mobile-two-user-20261018/shared-task-native-child-repro/verification.json),
SHA256 `6bafab89da7d6587542ecac34c956db8d6be23cc372c1fd56d5dc9b214a08324`,
ločijo uspešno zaključena preverjanja fresh/root/task, obstoječega child repair/
data/idempotence in podpisanega tombstone od zadnjega negativnega primera,
ki ga je v prvem večfaznem teku prekinil `rate_limited`. Uspešnih faz ni bilo
ponovljenih. Ločeni filtered incomplete-inventory primer je v 4 s **1 PASS**:
pravi razlog `crypto_project_root_inventory_pending`, brez korena ali intenta.
Samo ta novi disposable fixture je imel capacity 600 → 60000 ob istem 60 s
oknu; živi QA limiter in glavni PHP izvor sta nespremenjena. Prizadeta
runtime in test analiza sta čisti. To **ni whole-file/broad/native write-ACK
PASS**; vsi lastni disposable vsebniki so odstranjeni.

Ločeni četrti runtime popravek vidnosti napake je opisan spodaj. [En novi release QA kandidat](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-task-save-fixed/artifact-evidence.json)
je zgrajen z istimi identitetami/sejo/shrambo, a še ni nameščen.
Trenutni telefon ima debug APK `0beb5423…`, PID **8920**, ohranjeni obrazec;
ni novega Save ali povabila. Odločilna je prihodnja shranitev istega osnutka
in običajni auto sync po pregledani posodobitvi, brez novega projekta/računa.

**Prejšnji potrjeni sync in zgodovina lokalizacije Save:** Ozki SQL popravek je ob
14:59:52.664764 UTC zamenjal samo eno QA PHP datoteko po konsistentni zasebni
kopiji. Isti PID 2050/seja je ob 17:00 lokalno (15:00 UTC) zaključil cikel z
»Usklajeno«, last success/attempt 17:00, 0 pending/conflicting/blocked in brez
napake. Do tega zajema ni bilo nove gradnje, relaunch/prijave/FILE/vnosa,
Done ali manual Sync; samo Back iz obstoječe zaščitne strani in status.
[Native dokaz](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/post-server-fix-sync-evidence.json)
ločuje terminalni AX od poznejšega PNG z naslednjim naravnim »Usklajujem …«;
uspeh naslednjega cikla ni potrjen. [Reproducer/source binding](../build/qa/jivie-mobile-two-user-20261018/account-choice-propose-repro/evidence.json)
in [QA apply](../build/qa/jivie-mobile-two-user-20261018/account-choice-propose-repro/apply-evidence.json)
potrjujeta neobstoječi `records.domain` in pregledani fail-closed query fix.
Shema, queue/protokol, drugih 180 QA virov/config/SID in produkcija so isti.

Nato sta [dva oddaljena Save](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/shared-task-one-save-checkpoint.json)
za `MOBILE-SHARED-1` / `FROM-A-20261018` in uporabnikov fizični Save pustila
omogočen obrazec odprt brez napake v začetnem pogledu ali spinnerja. [En query-only zajem](../build/qa/jivie-mobile-two-user-20261018/shared-task-one-save-readonly-existence.json)
je ob 15:05:47 UTC potrdil **nič** task vrstic v točnem child scope;
to ne izključuje lokalnega osnutka ali pending zapisa. [En nadzorovani restart](../build/qa/jivie-mobile-two-user-20261018/shared-task-controlled-restart-evidence.json)
PID 2050 → **7225**, brez namestitve/clear/prijave/FILE, je ohranil isti
račun/sejo/prostore. Običajni seznam opravil je bil prazen; isti ohranjeni
osnutek in en svež sredinski Save sta ponovno pustila omogočen obrazec brez
odziva. Nadaljnja dejanja na telefonu so ustavljena; povabilo ni ustvarjeno.
To je ločen nov blocker, prejšnji SQL/sync popravek ostaja potrjen.

[En ciljni real-editor widget test](../build/qa/jivie-mobile-two-user-20261018/shared-task-save-repro.log)
je PASS: Save enkrat pokliče mocked `controller.createTask` in zapre obrazec,
brez pre-try izjeme validatorjev ali `Form.save`. To ni native reprodukcija
ali dokaz dejanskega persistence. [En sanitizirani pregled obstoječega PID dnevnika](../build/qa/jivie-mobile-two-user-20261018/shared-task-save-static-exception-check.json)
ni našel dovoljenih kategorij izjem ali editor/Form frameov; izid je
nedoločen, brez shranjevanja surovih logov. [Thread/frame vzorec](../build/qa/jivie-mobile-two-user-20261018/shared-task-native-thread-discriminator.json)
ni dal uporabnih `top` vrstic; nespremenjeni Android gfx števci ne dokazujejo
zastoja Flutter SurfaceView. [CPU fallback](../build/qa/jivie-mobile-two-user-20261018/shared-task-cpuinfo-fallback.json)
kaže agregatnih 34 % procesa v prejšnjem intervalu, ne konkretne niti ali vzroka.

Ena pregledana [debug QA gradnja](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-task-save-debug/artifact-evidence.json)
`0beb5423403bdf9b514ba0e6dcd77ac490e7fff12d4d8451933b7a59025f8bd6`
je nameščena v isti paket/podpis/secure preferences/shemo, **PID 8920**.
Štirje pregledani popravki in izolacija ostanejo; trije tag overlayi so
odstranjeni, brez seeding/reset ali novega runtime popravka. Dodatna debug
Vulkan knjižnica je vezana na isti SDK engine in obstoječa Gradle merged/
stripped artefakta; stare kripto/SQLite knjižnice in dovoljenja so isti.

[En Save pod breakpoint nadzorom](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-task-save-debug/save-control-flow-evidence.json)
ob 15:33:28 UTC potrdi dejanske vrstice urejevalnika 239 → 264 → 265 → 275 →
280 → 289, nato `collaboration_actions.dart:613` in
`collaboration_record_actions.dart:677 → 43 → 679`. Gumb, validacija,
`Form.save` in policy torej uspešno dosežejo dejansko repozitorijsko
transakcijo. Nato ena `CollaborationException` propagira do editor catch
na vrstici 292. Več breakpoint obvestil med propagacijo ni več ločenih
neuspešnih opravil. V tem native zajemu točna exception koda in throw lokacija nista bili
zajeti; poznejši naravni reproducer zgoraj je ločeno dokazal manjkajoči
kanonični projekt in `record_missing`.

En bralni scroll obrazca razkrije prej skrito trajno napako **»Dejanje ni
uspelo. Preveri povezavo in poskusi znova.«** Začetni »brez vidne napake«
ni pomenil odsotnosti shranjene napake. Obrazec ostaja omogočen/odprt;
opravilo in povabilo nista potrjena. Zajem se je končal v manj kot dveh minutah
od enega Save, opazovalnik je izstopil z 0, odstranil svoje breakpointe,
izvedel nadaljevanje ustavljenih isolateov in odstranil lastni USB forward.
Naprava in gostitelj sta imela preverjen loopback, avtentikacija/origin
preverjanje ostaneta; auth URI/skrivnosti/objekti niso izpisani. Edini
`getObject` je bil omejen na preverjeno statično `Script` metapodatkovno
referenco za preslikavo tokenov v vrstice, brez runtime objektov ali eval.
**To je native lokalizacija odpovedi, ne popravek ali task PASS.** Ista seja
in osnutek sta ohranjena; brez dodatnega Save/gradnje. Prejšnji release
`c7b18907…` in običajni APK `dab9bf45…` sta shranjena. A lokalni/računski
koraki in isti `MOBILE-PROJECT-1` so PASS.

Ločeni **izvorni popravek vidnosti napake** premakne isto lokalizirano
besedilo iz konca drsnega obrazca v trajni del nad Shrani/Prekliči z
`Semantics(liveRegion: true)`. [Vezani dokaz](../build/qa/jivie-mobile-two-user-20261018/editor-save-error-visibility/verification.json)
potrdi stari FAIL → en novi ciljni PASS pri mobilnem pogledu 360 × 640:
zaključena neuspešna asinhrona shranitev je vidna brez drsenja in dostopno
naznanjena, osnutek/kontrolniki/izbor/fokus ostanejo ter je izveden natanko en
klic brez samodejne ponovitve. Analiza obeh prizadetih datotek je čista.
Popravek je **samo v izvoru, še ni nameščen**; ne odpravlja ali dokazuje
uspeha ločene repozitorijske odpovedi shranjevanja.

Na iOS je navadni IPA `af730dd5…`, isti vault/identity/probe/PID 2005,
`complete`, cleanup false/residual 0 in osebni Utrip. Eno uporabnikovo lokalno
`MOBILE-LOCAL-B` je vidno kot ena unchecked vrstica. Predhodni startup
85,7 s se pri zadnji posodobitvi ni ponavljal. B račun, prvi stik/grant,
deljenje, odvzem, offline tok ter fizična FILE obnova/old→new upgrade ostajajo
odprti; to ni dvouporabniški PASS, neodvisni P0 pregled ali zaključek P8.
Začetna osnova je `de211c37808f137bd3e7b09369c71d873b9f1c34`; pregledani
PHP sync popravek je v `ff74634`. Izvirni aplikaciji/podatki/ključi, trgovini in
[macOS PASS](E2EE_MAC_TEST_2026_10_18.md) so nedotaknjeni. Spodnji starejši
checkpointi so zgodovina; aktualno stanje je zgoraj.

## Pripravljenost in meje

| Del | Trenutno znano | Še potrebno pred fizičnim tokom |
| --- | --- | --- |
| iOS | iPhone 11, iOS 27.0.1; isti vault, journal `complete`, cleanup false/residual 0; startup PASS in en vidni nedokončani MOBILE-LOCAL-B | B račun/povabilo/deljenje še niso potrjeni |
| Android | Galaxy S25 (`SM_S931B`); A/child/auto sync 17:00 PASS; trenutno debug APK 0beb5423…, PID 8920/seja, debugger odklopljen | Naravni reproducer potrdi record_missing; 3 canonical-root + UI visibility popravki pregledani. En release kandidat zgrajen, še ni nameščen; fizični task/sync in povabilo PENDING |
| Omrežje | LAN HTTPS `https://192.168.132.29:18801` dejansko uporabljen pri A enrollmentu/prijavi | B povezan tok še ni potrjen |
| Strežnik | Ločen projekt; oba ozka PHP popravka po ločenih konsistentnih kopijah; post-apply native auto sync PASS | B/grant/deljenje še ne; brez DDL/restarta/ročnega API |
| Vlogi | A = S25 lastnik, B = iPhone 11 prejemnik | Povabilo/sprejem/grant in skupne spremembe še PENDING |

Dejansko nameščena QA ID-ja sta `si.triparna.jivie.e2eetest.android20261018` in
`si.triparna.jivie.e2eetest.ios20261018`, prikazno ime `Jivie Test`.
Test se namesti poleg izvirne aplikacije. Android mora imeti lasten sandbox,
secure preferences/Keystore in FileProvider authority. iOS mora imeti svoj
vsebnik ter service `<ios-test-ID>.secure-storage` in samo skupino
`CXNM99632B.<ios-test-ID>`; ista service/group gresta tudi v Apple native
helper. Pred zagonom se pregleda dejanski podpis, profil in entitlements.

QA ne registrira produkcijskih `jivie`/`vsakdan` URL shem, ne vključuje
produkcijskih Firebase konfiguracij in ne vključi FCM/APNs. Povabilo se vnese
v testni aplikaciji; preizkus avtomatičnega odpiranja OS povezav/pusha ni del
tega teka. Izvirna aplikacija zaradi povabila ne sme postati cilj.

LAN načrt uporablja kratkoživo namensko CA in certifikat za točen IP. CA je
zaupana **samo QA transportu**, z normalnim preverjanjem certifikata/hostname,
točnim dovoljenim HTTPS ciljem in brez `badCertificateCallback`, globalnega
OS zaupanja ali HTTP izjeme za LAN. Zasebni ključ ni v aplikaciji. LAN gateway
izpostavi samo omejeni FamilyHub API; admin in Mailpit ostaneta na loopbacku
(`18800` app, `18802` Mailpit). Ločeni volumes/networks/serverId/secrets se ne
delijo z Mac A–D ali produkcijo. SMTP dostavlja samo v lokalni Mailpit za
`.invalid` naslove; to ni dokaz zunanje e-poštne dostave.

Dokazi priprave in poznejši checkpointi sodijo v ignorirani
[`build/qa/jivie-mobile-two-user-20261018`](../build/qa/jivie-mobile-two-user-20261018/).
Končne artifact/config manifeste dodamo, ko obstajajo; načrt ni dokaz gradnje,
namestitve ali odprtega LAN porta. Gesla, enrollment kode, povabilni tokeni,
FILE vsebina in TLS zasebni ključ ostanejo v namenski zasebni mapi zunaj Gita.
V zapis dodamo samo neobčutljivo pot/oznako dokaza in izid.

**Pregled strežnika:**
[preparation evidence](../build/qa/jivie-mobile-two-user-20261018/server/preparation-evidence.json),
[resources](../build/qa/jivie-mobile-two-user-20261018/server/resources.json),
[TLS gateway](../build/qa/jivie-mobile-two-user-20261018/server/gateway-tls.conf)
in [resolved compose](../build/qa/jivie-mobile-two-user-20261018/server/compose-tls-resolved.json)
so pregledani. Strežnik ima isti izvor, 181 preverjenih datotek, schema 20,
PHP 8.4.24/sodium 1.0.22, serverId `a1f38e6b-9092-4d22-a281-76aaa8b31eb9`.
Zabeleženih [7 TLS/API route kontrol](../build/qa/jivie-mobile-two-user-20261018/server/tls-public/tls-route-check.json)
je PASS v začasnem lastnem vsebniku brez host portov; to še ni fizična povezava.
LAN dovoljuje samo POST `/index.php` s točnimi tremi NativeApi parametri;
admin/root/Mailpit, dodatni in podvojeni parametri so zavrnjeni.
[CA dokaz](../build/qa/jivie-mobile-two-user-20261018/server/tls-public/certificate-evidence.json):
SHA256 fingerprint `BFB87F1A19B2B6FE42118791C7F78E6A3A73BC4F1DD02733AD06CACA6B10CB37`,
velja do **21. oktobra 2026 ob 12:25:42 UTC oziroma 14:25:42 lokalno
(Europe/Ljubljana)**, leaf SAN je točen IP. Po poteku
ne izklopimo preverjanja certifikata; treba je uskladiti nov QA certifikat/paket.

**Aktivacija:** [dejanski gateway/resources](../build/qa/jivie-mobile-two-user-20261018/server/resources-active.json)
in [activation evidence](../build/qa/jivie-mobile-two-user-20261018/server/tls-public/activation-evidence.json)
potrjujeta aktivacijo 18. oktobra ob 14:28 lokalno: samo točna LAN vezava,
11 zabeleženih host kontrol PASS, vključno z zavrnitvijo navadnega sistemskega
zaupanja in napačnega hostname. Takrat telefonska dosegljivost še ni bila potrjena; poznejši A enrollment
prek istega QA HTTPS je potrjen, dvouporabniški poslovni tok pa še ne. [Operator handoff](../build/qa/jivie-mobile-two-user-20261018/server/SERVER_OPERATIONS.md)
opisuje pripravo prve enkratne kode šele tik pred A enrollmentom ter zasebni
Mailpit helper. Poverilnice so v
`/Users/anzenovsak/Library/Application Support/JivieLocalTest/20261018-mobile-two-user/credentials.json`
(0700 imenik/0600 datoteka), brez njihove vsebine v tem dokumentu.

**Izvorni client review:** [načrt devetih sprememb](../build/qa/jivie-mobile-two-user-20261018/client-isolation-review/source-plan.json)
in [izolacijski patch](../build/qa/jivie-mobile-two-user-20261018/client-isolation-review/source-isolation.patch),
SHA256 `feed46334f921983ce518ce1e8ce2ea58d5c0be69d8d0f25061514c035cc8762`,
so pregledani. Vseh devet source/base hashov in štirje lock vhodi se ujemajo;
vgrajeni javni CA PEM je bajtno enak pregledanemu strežniškemu. To je source
review pred gradnjo, ne podpisan artifact ali fizični PASS. Pred iOS gradnjo
je bil dodatno ugotovljen in pregledan QA platformni popravek: iOS za trusted
certificate zahteva en DER X509 zapis, Android različica pa ohrani PEM.
[iOS-only transport delta](../build/qa/jivie-mobile-two-user-20261018/client-isolation-review/ios-der-only-delta.patch),
SHA256 `e484eab1769e4001528cf955784cfae5e73b5ccd439e7f656b39927eef2af4e7`,
in [iOS source plan](../build/qa/jivie-mobile-two-user-20261018/client-isolation-review/ios-source-plan.json)
potrjujeta isti certifikat: dejanski vgrajeni DER SHA256 je enak gornjemu CA
fingerprintu. Drugih osem datotek in lock vhodi so isti; ločeni Android izvor
ostane nespremenjen, Android gradnje ne ponavljamo. Omrežna omejitev,
preverjanje hostname in glavni izvor ostanejo nespremenjeni.
[Dart API: iOS oblika certifikata](https://api.dart.dev/dart-io/SecurityContext/setTrustedCertificates.html).

**Android kandidat, pregledan pred namestitvijo:**
[artifact evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-artifact-evidence.json),
[source lineage](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-source-lineage.json)
in [vezani hashi](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-review-hashes.json).
Ena arm64 release/AOT gradnja s standardnim razvojnim Android Debug podpisom,
ne produkcijskim ključem; različica 1.10.1 (31), ime `Jivie Test`, točen QA ID.
APK ima 37,643,050 B, SHA256
`e07b39d7fad3b8d23b538ca59a37f46b32ab12fef7760baeabcbb90197f54091`;
dejanski `apksigner verify` in package metadata sta PASS, certifikat SHA256
`063d7a1886b38e43ae228e4cd2070a2f480af44249bc6aea9653cb09401054ff`.
Prisotni so arm64 AOT/Flutter/sodium/sqlite3mc, lastni provider authorityji,
brez produkcijskih URL registracij/Firebase konfiguracije, backup izključen.
Dodatna datastore pomožna knjižnica za dve drugi ABI ni celotna aplikacija za
ti ABI. Ujemajo se native/source/lock hashi; to še ni fizični dokaz odklepa.

[Android installation evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-installation-evidence.json)
potrjuje coinstall 18. oktobra ob 14:38 lokalno, isti APK/testni ID/verzijo,
brez zagona ob namestitvi. Pot in verzijski metapodatki izvirnega Play paketa
`si.triparna.jivie` so nespremenjeni; ni uninstall/clear, branja podatkov ali
samodejnega podeljevanja runtime pravic. A-jev čarovnik se preverja ločeno.

**iOS paket, pregledan pred namestitvijo:**
[artifact evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-artifact-evidence.json),
[source lineage](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-source-lineage.json)
in [vezani hashi](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-review-hashes.json)
potrjujejo en dejanski Release/AOT razvojni arhiv brez ponovitve matrike.
IPA ima 16,552,186 B, SHA256
`e47ef321290db39ec4c1284a39bdf94a5a953b90239b6b3e2c1c21211d4ea343`;
AOT `8e979275a6ec3318645627e7bf1e14915608c25f13fa58512ad74f4baec0dbdb`.
Dejanski strict/deep podpis in izluščeni podpisni certifikat
`7C3137352B9A7E49AC7696A8557665D7ABD38968` sta preverjena. Podpisani app-ID
je točen QA ID, Keychain ima samo lastno QA skupino, `get-task-allow=true`,
brez APS/URL/Google konfiguracije. Običajen wildcard razvojni profil
`50458f86-da56-4cef-81e7-873a8fecef4f` (`CXNM99632B.*`, do 18. oktobra 2027)
vključuje ta certifikat in povezani iPhone; app sam ni wildcard. Prisotna sta
sodium in arm64 `sqlite3mc.framework`; slednji izvozi `sqlite3_key`,
`sqlite3_key_v2`, `sqlite3_rekey` in `sqlite3mc_config`, SHA256
`8fd6a661b78bd500ef0ad74c9717684d807173c257aace29bddd786850b39780`.
To je packaging dokaz prvega paketa; poznejši fizični odklep ohranjenega
vaulta je zabeležen spodaj, ordinary startup pa še čaka odpravo padca.

Prejšnji [CLI provisioning blocker](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-provisioning-blocker-evidence.json)
»No Accounts« je zgodovina pred compile. GUI račun je bil prijavljen;
[običajni QA workspace provisioning](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-gui-provisioning-resolution.json)
je pripravil wildcard profil brez ponovne prijave ali novega certifikata.
Xcode serializer spremembi sta bili pred compile povrnjeni na pregledane
source bajte. Vseh devet source in lock hashov se ujema; poznejši popravek
izluščitve certifikata je samo verifier, brez nove gradnje. Produkcijski
profil ali izvirni app nista uporabljena.

[iOS installation evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-installation-evidence.json)
potrjuje coinstall ob 14:54 lokalno: isti pregledani paket/AOT/izvršni hash,
QA app prej odsoten, zdaj prisoten; izvirni TestFlight app ostane prisoten
z enakimi metapodatki. Brez zagona, branja njegovih podatkov ali Keychain.

## Dejanski checkpointi pred deljenjem

[Android A checkpoint](../build/qa/jivie-mobile-two-user-20261018/android-owner-checkpoint.json)
potrjuje isti 150 B installation FILE: Samsung tipkovnica je v končnico vnesla
razmak; native validator ga je zavrnil pred branjem vsebine. MyFiles je
preimenoval isto datoteko brez spremembe hash/velikosti; ponovna native izbira
in Encrypt sta uspela. En `MOBILE-LOCAL-A` ostane lokalen. A se je enkrat
registriral prek točnega QA HTTPS/first-account kode, potrdil `.invalid`
e-pošto ter shranil/ponovno izbral svoj 509 B account FILE. Pri mešanem prikazu
»ključi pripravljeni«/napake je en pregled stanja odstranil opozorilo, brez
nove inicializacije ali FILE; njegov izvor ni s tem dokazan kot popravljen.

Ena organizacija `Mobile E2EE 20261018` je ustvarjena. En poskus
`MOBILE-PROJECT-1` je obstal z `invalid_response` prikazom;
[query-only metadata](../build/qa/jivie-mobile-two-user-20261018/android-project-create-readonly-metadata.json)
potrjuje že ustvarjeni child `254c3dae-2b63-4a61-bfbc-00a3c62cfab2` in aktivno
glavo, brez child scopeMetadata/task/invite.
[Nadaljnji metapodatki](../build/qa/jivie-mobile-two-user-20261018/android-project-create-readonly-followup.json)
potrjujejo parent metadata revision 2/sequence 2 in uspešne aktivacijske receipts.
[Sanitizirano PHP opozorilo](../build/qa/jivie-mobile-two-user-20261018/android-project-create-php-warning-sanitized.json)
je vezano na napačno branje `grantManifestHash` iz zunanjega wrapperja pri
`minimalLifecycleReceipt`; pravi hash je v podpisanem inner activation.
[Ciljni dokaz](../build/qa/jivie-mobile-two-user-20261018/receipt-regression/evidence.json)
ima stari FAIL in 27 fixed PASS v sveži disposable bazi, ne celotne matrike.
Popravek ohranja minimalni lastni zgodovinski receipt in current ACL za ostale
poti. [QA apply evidence](../build/qa/jivie-mobile-two-user-20261018/receipt-regression/apply-evidence.json)
potrjuje konsistentno zasebno SQLite kopijo 2,424,832 B z `integrity_check=ok`,
0700/0600. Uporabljen je obstoječ lokalni Python image brez omrežja, samo
lastni QA volume in točna zasebna backup mapa. Volume je RW samo zaradi WAL/SHM
bookkeepinga; source povezava je `mode=ro` + `query_only=ON`, brez SQL zapisov,
`immutable`, `nolock` ali raw kopije. Prvi neuspešni RO-mount/0 B poskus je
ohranjen in ni obravnavan kot backup. Atomarno je zamenjan samo
`NativeCryptoV2Service.php` (`0b036e1b…`); drugih 180 virov, config/SID/schema,
scope/record/head metadata ostanejo isti, receipts 30 → 30. Dejanski FPM ima
opcache timestamp validation/2 s; počakane 3 s, brez restarta ali API zahtevka.
Native je nato po UI GO enkrat nadaljeval Add v ISTEM modalu z istimi ID-ji in
shranjenimi proof/ključi: »Projekt je ustvarjen«, `MOBILE-PROJECT-1 · Deljeno`.
Poznejši avtomatični sync ob 15:27 lokalno je pokazal isti generični unsafe-response
prikaz, 0 pending/conflicting/blocked, zadnji uspeh 14:58. Brez manual Sync,
novega taska/povabila ali ponovnega ustvarjanja. [Novi metapodatki](../build/qa/jivie-mobile-two-user-20261018/android-resumed-sync-readonly-metadata.json)
potrjujejo child scopeMetadata revision 1/sequence 1 in uspešen records.batch;
[parent/child checkpointi in client trace](../build/qa/jivie-mobile-two-user-20261018/android-resumed-sync-client-trace.json)
ne določijo natančnega parserja. [Vezano okno logov](../build/qa/jivie-mobile-two-user-20261018/android-resumed-sync-sanitized-log.json)
nima PHP opozoril. Receipt popravek je torej odpravil prejšnjo mejo, ne dokazuje
odprave nove sync napake; isti zapis/stanje ostajata ohranjena za ozko diagnozo.

[iOS sanitizirani journal](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-local-vault-checkpoint/sanitized-journal-evidence.json)
kaže `complete`, `pickerCleanupPending=false`, `pickerResidualFiles=1`.
Metapodatki Documents kažejo samo lastni vault, tmp je prazen. Ozki
[canonical-path dokaz](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-local-vault-checkpoint/ios-local-vault-verification.json)
ima parent-alias pred-fix FAIL, en nov post-fix PASS ter dva neposredna obstoječa
preservation guard PASS; analiza 0 error/0 warning, 21 starih info. Popravek
primerja lastni vault v isti canonical obliki kot skenirani root; ne prezre
neznanih izvozov in ne sledi symlinkom. To ni ponovitev celotne zbirke.
[Posodobljeni iOS artifact/lineage](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-vault-alias-fixed/ios-artifact-evidence.json)
vključuje samo ta runtime delta ob istih devetih izolacijah; IPA
`34ebf3675925587c331da23203de699f2b45f340a03bbfb7b60e8f0842ce7e92`,
isti signer/service/group, sodium/sqlite3mc.
[In-place install evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-vault-alias-fixed/installation-evidence.json)
potrjuje štiri bajtno enake vault/journal datoteke pred prvim zagonom; iOS je
spremenil UUID poti vsebnika, podatkov pa ni zamenjal. Ni uninstall/reset/obnove
ali branja Keychain. Prvi zagon je potrdil `complete`, cleanup false/residual 0:
canonical-path cleanup in odklep istega šifriranega vaulta sta fizično PASS.
Proces je nato izginil; Ta prvi startup ni uspel; poznejši popravljeni startup PASS je naveden spodaj,
nadaljnji B račun/deljenje ostajata PENDING.
FILE/gesla/ključi v ta zapis niso vključeni.

**iOS notification meja, ločeno od cleanup PASS.** [Sanitiziran crash](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-vault-alias-fixed/sanitized-target-launch-crash.json)
je vezan na isti launch PID 1990 (15:23:48–15:24:37) in ujemajoče App/Flutter/Runner
dSYM. SIGSEGV je v `_reconcile`, ne navadna prestrežena Dart napaka.
[Numerični fault](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-vault-alias-fixed/fault-numeric-context.json)
in [omejena AOT dataflow sled](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-vault-alias-fixed/reconcile-pre-fault-disassembly.txt)
vežeta register na `sharedState.valueOrNull`: ista prej null-checked vrednost
je pred zanko uporabljena za unconditional nested field load. Ni spremembe SDK
ali dokazila, da widget test reproducira native SIGSEGV.

[Ozki source/test dokaz](../build/qa/jivie-mobile-two-user-20261018/notification-nullable-authority/verification.json)
veže popravek `notification_coordinator.dart` SHA256
`db8771fe82be3f52692c742cda5efeb07236331ebf31bf130f77a442a834405a` ter tri nove
primere: lokalni opomniki ob AsyncError z empty/personal katalogom; resnični
async prehod skozi prijavljeno stanje in izrecno odstranitev seje; zavrnitev
odsotne/tuje/nepopolne shared authority. Final 3 PASS, scoped analiza obeh datotek
»No issues found« (pred zadnjim izključno fixture popravkom veljavnih record
referenc); nobena prejšnja zbirka ni ponovljena. Prvi lokalni invariant je bil
PASS že pred popravkom. Stari runtime je v session-clear/stale-plan in injected
absent-session poti vrgel običajen null assertion; to je ločen dokaz od native
SIGSEGV. Vmesni napačni fixture predpostavki (AsyncError odstrani prejšnjo data;
empty target records so veljavni) in njuni logi ostanejo jasno označena zgodovina.

Popravek zajame nullable authority v nespremenljive session/finance/record/prefs
vhode pred zanko in čakanjem, brez `shared!` dereferenc v kasnejših vejah.
Ohrani local/private materialization pogoje, individualne preference, lokalna
pravila ter generation in dejansko current identity varovalo po await. Shared
plan zahteva prisotno sejo, scopeId in obstoječi `target.matches(session)` za
serverUrl/serverId/accountId. Ni fake prijave ali izklopa opomnikov. Poznejši [pregledani notification kandidat](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-notification-fixed/ios-artifact-evidence.json)
ima IPA SHA256 `93a80d6aac715ea16ffb5e8085a78dc256e3d7bc7e4f44a535b83d63e0a40b68`,
AOT `13a81c4fb3f1b3696743c0fc4639ba5fee14d45eeb4faa101cec386e8ea6eb38`;
isti QA ID/signer/service/group in devet izolacij, oba reviewed runtime popravka.
[Vezana compiled AOT meja](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-notification-fixed/aot-null-boundary-evidence.json)
ima null return pred prvim shared field branjem; prvotni unconditional receiver
load ni več v reconcile zanki, session/target guard je prisoten. SDK/locks ostanejo isti.

[Dejanski iOS startup](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-notification-fixed/native-startup-evidence.json)
in [finite opazovanja](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-notification-fixed/startup-observations.json)
potrjujeta eno posodobitev iste namestitve s štirimi bajtno enakimi vault
datotekami pred zagonom ter en običajen launch PID 2001: osebni Utrip brez
čarovnika ali napake, proces živ pri 36,4/66,2/85,7 s (največja vrzel 36,4 s),
journal `complete`, cleanup false/residual 0 in isti identity/probe. Izvirni
TestFlight app je isti; brez nove FILE, migracije, prijave ali tool Keychain branja.
To potrdi to omejeno native nadaljevanje, ne dolgoročne crash-free uporabe,
B računa ali deljenja; proces ob checkpointu ostaja odprt.

**Android account-choice meja.** [En varen diagnostični tek](../build/qa/jivie-mobile-two-user-20261018/android-sync-diagnostic-proposal/capture-evidence.json)
je shranil dva allowlisted taga: `session_route / finance4.accountChoices /
FormatException` in terminalni `sync`, brez transportne napake ali uporabljenega
package stack frame. Ni login/FILE/manual Sync/novega vnosa; obstoječa prostora
ostaneta vidna. Sync pravilno kliče ta endpoint samo za project, ne organizacijo;
prazni PHP export odgovori so objekti z `items: []`, ne top-level seznam.
[Ozki parent/schema dokaz](../build/qa/jivie-mobile-two-user-20261018/account-choices-parent-fix-evidence.json)
ima old FAIL `crypto_account_choices_target` v dejanskem prepare bootstrapu in
8 novih ciljnih PASS, scoped »No issues found«. Runtime bere dejanski
`SharedScope.fromJson(...).parentSpaceId`, namesto neobstoječega JSON ključa;
scopes projekcija sprejme parent ID samo ob ujemanju z že preverjenim podpisanim
server/child/parent tokenom. Catalog/cache sta kandidata, ne authority. Parent
kind/organization alias izhajata samo iz ločeno preverjenega descriptorja istega
cikla; unknown/household ne postaneta organization. Child-only član ne potrebuje
parent ključev ali vsebine; null/neujemajoč token odstrani zastarela parent polja.
Test bootstrap se namerno ustavi pred parent finance checkpoint/export HTTP;
to ni native dokaz praznega account-choice roundtripa. Oba običajna kandidata s tem popravkom sta zdaj nameščena; native Android sync
ISTEGA stanja še ni potrjen, produkcija je nespremenjena.

**Trenutna navadna paketa in točka nadaljevanja.** [Android artifact](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-parent-fixed/artifact-evidence.json)
in [in-place namestitev](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-parent-fixed/installation-evidence.json)
vežeta APK `dab9bf45…`, isti podpis/QA ID/verzijo, manifest/native knjižnice ter
odsotno začasno diagnostiko. En zagon PID 28665, izvirni metapodatki in QA dataDir
ohranjeni; telefon je bil ob launchu zaklenjen. [Poznejši isti proces po odklepu](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-parent-fixed/unlocked-ui-checkpoint.json)
je pokazal oba committed prostora; en Done je vrnil običajni Utrip brez nove
FILE/ključev/migracijskega soglasja ali sprejema unavailable podatkov. NOV cikel
je bil aktiven ob 14:20:32 UTC in je ob 14:21:01 UTC zaključil pozornost:
last attempt 16:20 lokalno, last success ni potrjen, pending/conflicting/blocked
0/0/0, protection-pending besedilo. To ni zgolj prejšnji 16:16 prikaz.
Natančen pending razlog ostaja neznan; ni manual Sync, novega opravila ali povabila.
[iOS artifact](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-parent-choices-fixed/ios-artifact-evidence.json),
[namestitev](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-parent-choices-fixed/installation-evidence.json)
in [normal screen/continuity](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-parent-choices-fixed/native-update-continuity-evidence.json)
vežejo IPA `af730dd5…`, isti signer/profile/service/group, štiri bajtno enake
vault datoteke pred zagonom kljub preselitvi UUID poti, isti identity/probe in
`complete`, cleanup false/residual 0. En običajen PID 2005 kaže Osebno/Utrip;
85-sekundni preizkus in AOT disassembly nista ponovljena. Izvirni TestFlight app
je isti. [Lokalni B checkpoint](../build/qa/jivie-mobile-two-user-20261018/client-candidates/ios-parent-choices-fixed/native-mobile-local-b-checkpoint.json)
potrjuje uporabnikovo shranitev in natanko eno vidno, unchecked vrstico
`MOBILE-LOCAL-B` v Osebno / Planer / Opravila / Brez roka na istem PID 2005.
Agent ni ponovil save, odprl detaila ali spreminjal podatkov. B račun/povabilo/
grant/deljenje in preostali koraki spodaj so odprti.

**Predhodni reason-only diagnostični tek — zgodovina pred zadnjim queue zajemom.**
[Artifact](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-diagnostic/artifact-evidence.json),
[namestitev](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-diagnostic/installation-evidence.json)
in [capture evidence](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-diagnostic/capture-evidence.json)
vežejo en APK `547fa768…`, isti QA ID/podpis/sejo/dataDir in nespremenjene
metapodatke originala, en launch PID 31944. Pregledani overlay ostane izključno
v dveh QA datotekah (`collaboration_sync_actions.dart`, `collaboration_finance_sync.dart`),
ne v main; zajame največ prvi allowlisted pending razlog in terminalni cikel,
brez payload/ID/URL/exception text/raw stack. Običajni APK `dab9bf45…` ostane
shranjen. Main runtime od `5e5426a` ni spremenjen.

Zajem je trajal 180,01 s, timeout in 0 tagov; raw log ni shranjen. Opaženi so
zaklenjen/nebuden telefon in odsoten resumed app, ne natančen razlog ali stanje
lease/schedulerja. Isti proces ostaja ohranjen, brez novega UI dejanja, testa,
poizvedbe ali ponovne priprave. Po uporabnikovem odklepu je ločeno odobreno nadaljevanje zbiralnika na ISTEM
PID 31944 brez relaunch/UI posega v 0,17 s zajelo `first_pending stage=finance
reason=crypto_command_receipt_pending` in terminalni pending z istim razlogom.
To določi manjkajoč applied receipt, ne še dejanskega operation/state ali
blocked admission razloga. Ohranjeno stanje čaka ozko source diagnozo.

## Dokazani SQL vzrok in zadnja QA namestitev

[Zadnji queue capture](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/capture-evidence.json)
veže en odobren diagnostic build/update/launch, tri finite tage v 2,64 s na
PID 2050, brez nadaljnjih telefonskih dejanj. [Artifact](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/artifact-evidence.json)
in [installation](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/installation-evidence.json)
potrjujeta isti QA ID/podpis/sejo/dataDir in nespremenjen original. Queue tag
bere samo operation/state/top-level stored reason/code. Foreground-only
`KEEP_SCREEN_ON` se ob onPause odstrani; ne odklepa telefona ali spreminja globalnih
nastavitev. Vse to ostane samo v QA overlayu, ne main.

[Reproducer/evidence](../build/qa/jivie-mobile-two-user-20261018/account-choice-propose-repro/evidence.json)
je uporabil svežo opt-in SQLite bazo, realni `NativeService.dispatch`, nove
sintetične native org+wrapped child podpise in prazen finance checkpoint.
Old FAIL je `PDOException / HY000 / no such column: domain`, sled v
`NativeCryptoAccountChoiceExportV2.php:58`, 0 proposal receipts/0 offers.
Controller tak Throwable skrije v `server_error` 500 brez loga; client send
API napako prestreže in unknown receipt pusti pending. Prazni Docker logi zato
niso izključili tega vzroka.

Popravek z LEFT JOIN poveže `record_positions` po **scope_id in id**, ohrani
parent scope/type/live filter in vrstni red; manjkajoča ali ne-finance pozicija
je `source_set_changed`, nikoli tiha izpustitev živega računa. Vsi predhodni
podpisi/ACL/checkpoint/source-set pogoji ostanejo. [Novi ciljni test](../server/tests/crypto2-account-choice-selection-propose-regression.php)
ima uspešen prazni 200 receipt/exact retry, nonempty parent proti child filtru
ter manjkajočo/napačno-scope/napačno-domain pozicijo fail-closed; devet ozkih
assertionov PASS, oba PHP lint PASS. To ni ponovitev stare zbirke ali fizični
client export roundtrip. Precreateguard zahteva SQLite, izrecni opt-in in prazne
accounts/scopes/receipts. Vmesni fixture-only popravek je ločen od product FAIL.

[Apply evidence](../build/qa/jivie-mobile-two-user-20261018/account-choice-propose-repro/apply-evidence.json)
potrjuje novo zasebno 0700/0600 konsistentno SQLite kopijo 2,473,984 B,
`integrity_check=ok` (ne trditev dejanske obnove). Ista odobrena Connection.backup
pot ima own volume RW samo za WAL/SHM, source SQL `mode=ro`/query_only in
network none. Atomarno je zamenjan samo `NativeCryptoAccountChoiceExportV2.php`,
old `e35c0ac…` → reviewed/on-container `4c4e89ee…`; drugih 180 datotek,
config/SID/schema so isti. Dejanski FPM validate_timestamps On/2 s, počakane
3 s; brez DDL, SQL source zapisov, restarta, opcache reset ali API zahtevka.
[Post-apply native dokaz](../build/qa/jivie-mobile-two-user-20261018/client-candidates/android-pending-queue-diagnostic/post-server-fix-sync-evidence.json),
SHA256 `af8e0d1d9cb152b6bc13b5490c080282f067d31907d450fd58cb8842d65b44a8`,
veže isti PID/sejo na ta apply. AX v oknu 15:00:25–15:00:58 UTC je pokazal
»Usklajeno«, last success/attempt 17:00 lokalno, 0/0/0, brez napake; točna sekunda
AX ni zabeležena. Poznejši shranjeni PNG že kaže naslednji »Usklajujem …« poll,
ob ohranjenem uspehu 17:00, zato PNG sam ni terminalni status dokaz. Ni ponovnega
teka ali trditve, da se je zaključil tudi naslednji cikel. Do tega native sync zajema po apply ni bilo
manual Sync, Done, relaunch, auth/FILE ali novih content zapisov. To je odprava
te konkretne account-choice receipt meje; dvouporabniško deljenje še ni PASS.

## Opazovanje pred prvim fizičnim poskusom

Po izrecni uporabnikovi zahtevi pred naslednjim fizičnim QA poskusom pripravimo
in povežemo debugger oziroma navadno debug konzolo ter varen omejeni zajem.
Ponovno uporabimo obstoječi
[QA runner](../build/qa/jivie-mobile-two-user-20261018/android-task-save-debug-plan/launch-and-observe.py)
in [opazovalnik](../build/qa/jivie-mobile-two-user-20261018/android-task-save-debug-plan/observe-save.dart),
z isto izolacijo, avtentikacijo in USB/loopback omejitvijo; ne gradimo novega
splošnega diagnostičnega ogrodja. Ob prvem neuspehu ali navideznem neodzivu
pred retry/rebuild preverimo konzolo, stabilno kodo izjeme in statično throw
lokacijo. Zabeležimo samo te oznake/kontrolni tok ter viden izid; brez
payloadov, ključev, tokenov, auth URL ali surovih objektov. S tem ne trdimo,
da je novo runtime beleženje že dodano ali da trenutni runner že zajema
exception kodo/throw lokacijo: zadnji zajem je potrdil samo kategorijo in pot.

## Navodila za en omejen fizični tek

Vsak checkpoint zabeleži telefon, čas, dejanski rezultat in število vnosov;
že izvedeni deli so izrecno navedeni zgoraj, preostali so **PENDING**. Ob napaki ohranimo isto stanje,
točno napako in pending/conflict/blocked. Ne ponovimo ustvarjanja zapisa,
ponastavitve ali obnove, da bi napako skrili.

1. **Pred prvo namestitvijo.** Potrdimo testni ID/podpis obeh paketov,
   dosegljivost testnega HTTPS in vidno ime `Jivie Test`. Ne odstranjujemo ali
   posodabljamo izvirne aplikacije. Ne uporabljamo obstoječega pravega računa.
2. **Vsak telefon: samo lokalna namestitev.** Brez računa shranimo njegov
   installation FILE v izbrano zunanjo lokacijo, nato ga z native pickerjem
   ponovno izberemo in zaključimo zaščito baze. Ustvarimo eno označeno lokalno
   opravilo `MOBILE-LOCAL-A` oziroma `MOBILE-LOCAL-B`; ostane lokalno.
3. **Lastnik A: prvi račun.** Ko je A pripravljen, operator pripravi eno
   kratkoživo first-account kodo; A jo porabi na testnem HTTPS. Uporabimo
   pripravljen sintetični račun A z naslovom `.invalid`, običajno pošljemo in
   potrdimo e-poštno kodo iz lokalnega Mailpita. A shrani in ponovno izbere
   **svoj računski FILE**, nato potrdi pripravljenost ključev. Installation
   FILE, računski FILE in podatkovna kopija niso ista stvar. B registracijo
   pozneje začne iz povabila, brez administrativnega ustvarjanja računa.
4. **Lastnik A ustvari baseline.** Organizacija `Mobile E2EE 20261018`
   potrebuje child projekt za mobilna opravila: nadaljujemo isti že ustvarjeni
   `MOBILE-PROJECT-1`, ne novega. V njem eno opravilo `MOBILE-SHARED-1`,
   nedokončano, opomba `FROM-A-20261018`.
   Zabeležimo en prostor/en zapis in zaključen avtomatični sync brez napake.
5. **B sprejme povabilo, A nato potrdi ključe.** A povabi točen pripravljen
   naslov B. Povabilo odpremo/vnesemo v testnem appu; B zaključi običajno
   registracijo in preverjanje e-pošte, shrani/ponovno izbere **svoj** računski
   FILE ter preveri strežnik, uporabnika, prostor in vlogo. A v računskem
   zaščitnem čarovniku odpre **Potrjene naprave → Prikaži javno kartico za
   preverjanje → Kopiraj javno kartico**. B celotno A-jevo javno kartico dobi
   neposredno po znanem ločenem kanalu, ne iz iste povabilne povezave, in jo
   prilepi v **Primerjaj in potrdi identiteto**. Po izrecnem Join je pričakovano
   stanje »lastnik mora še potrditi vaše ključe«; samo sprejem še ne odpre vsebine.

   B po istem postopku izvozi svojo javno kartico in jo neposredno prenese A.
   A v prostoru odpre **Člani/Povabila → ikona ključa (Potrditev dostopa)**,
   primerja/prilepi B-jevo kartico in izbere **Potrdi dostop in pripravi
   ključe**. Pred potrditvijo preveri pravi račun/vlogo in pričakovano število
   dosedanjih zapisov v prikazu podatkov/financ. Nato B nadaljuje isto čakajoče
   povabilo oziroma izbere Ponovi; vidi isti en prostor/zapis/opombo, brez
   ponovnega Join ali podvojitve.

   Kartica je javni JSON za identiteto (server/account, safetyCode,
   generation/head), **ni obnovitveni FILE ali device approval request**.
   A/B si računskih FILE ne izmenjata. Pri neujemanju ali zastareli kartici
   ustavimo potrditev in pridobimo svežo kartico neposredno iz pravega appa;
   ne sprejmemo kartice, ki jo ponudi samo strežnik. To so koraki iz
   [InvitationWizard](../lib/organizer/presentation/shared/invitation_wizard.dart),
   [CryptoInvitationPage](../lib/organizer/presentation/recovery/crypto_invitation_page.dart)
   in [Approved devices](../lib/organizer/presentation/recovery/account_devices_page.dart);
   dejanski B/prenos/grant UI je še PENDING.
6. **Spremembi v obe smeri.** B dopolni isto opombo z `FROM-B-20261018`; po
   zaključenem sync jo A vidi. A zaključi isto opravilo; B vidi zaključek.
   Ne ustvarimo drugega opravila namesto preverjanja spremembe prvega.
7. **Offline in nadaljevanje.** Po praznih vrstah B začasno izključi omrežje,
   preveri že preneseno opravilo in lokalni zapis, nato na dovoljenem skupnem
   opravilu shrani eno označeno spremembo. Po vrnitvi omrežja ista sprememba
   doseže A enkrat; pending/conflict/blocked se zaključijo. Drugi telefon je
   lahko med tem v ozadju; preverimo nadaljevanje brez nove prijave/FILE.
8. **Finančna meja, če jo izbrani prostor/vloga uporablja.** Pred korakom
   zapišemo dejansko politiko `none/read/write` in pričakovano vidnost. A lahko
   ustvari en označen testni račun; B vidi ali ureja samo, kar dovoljuje ta
   politika. Projektno članstvo ne sme samo podeliti financ starša. Če UI za
   izbrani tip prostora ne omogoča načrtovane ločitve, korak označimo ločeno
   neizveden, ne razglasimo napačnega privacy PASS in ne širimo finančne matrike.
9. **Odvzem je zadnji poseg v članstvo.** Ko sta obe vrsti prazni, A odstrani
   B z običajnim potrjenim postopkom/rotacijo. Nato A zapiše nov označen podatek
   `AFTER-REVOKE-20261018`. B po vrnitvi v omrežje ne prejme nove vsebine in ne
   more veljavno zapisovati v ta prostor. Že prej prenesena zgodovina lahko
   ostane berljiva; test ne obljublja izbrisa kopij iz B-jeve naprave. B-jev
   osebni lokalni zapis ostane. Zabeležimo izid brez ponovnega povabila.
10. **Zaključek.** Zabeležimo zadnji zaključen sync, število zapisov in omejitve
    na obeh telefonih; aplikaciji normalno zapremo. Kasnejši tekoči poll ni
    dokaz zaključenega cikla. Paketa, FILE in stanje ohranimo za nadaljevanje.

## Ločeni poznejši preizkusi

**Fizični old → new upgrade** potrebuje posebej pregledan starejši testni
paket z ISTIM testnim ID/podpisom/service/group kot njegov naslednik, znani
lokalni/povezani baseline in dokazano kopijo/dejansko izolirano obnovo pred
zamenjavo. Sveža sočasna QA namestitev ni nadgradnja originalne aplikacije.
Ne prepisujemo prave trgovinske namestitve. Po lokalni šifrirni pretvorbi
starega paketa ne zaganjamo proti novejšemu stanju.

**Sveža računska FILE obnova** je drugačen korak: najprej sveža testna
namestitev z geslom potrdi prijavo, vsebina pa ostane zaklenjena; šele pravi
računski FILE oziroma odobrena naprava odklene isti dovoljen baseline.
Obnova lahko prekliče prejšnje naprave istega računa, zato jo izvedemo po
dvouporabniškem toku in z izrecno določenim računom/ciljem. Ne odstranjujemo
testnega appa in ne brišemo podatkov pred dokazom ustrezne kopije/obnove;
installation FILE sam ni kopija lokalnih podatkov. Do takrat oba koraka
ostajata PENDING. Password reset, push, trgovinska izdaja, celotna odpovedna
matrika ter neodvisni P0 pregled niso potrjeni s tem runbookom.
