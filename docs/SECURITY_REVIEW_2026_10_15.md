# Varnost FamilyHub in Jivie za shranjevanje kontaktov

Pregled 15. oktobra 2026. Izvor `4a63a6d`, Jivie 1.9.1+29 in FamilyHub 0.14.1. Namen je oceniti običajne kontakte in občutljive zapiske, ne izdati potrdila o varnosti ali skladnosti.

**Za običajna imena, telefonske številke in e-naslove je uporaba pogojno razumna, če zaupaš svoji napravi, gostovanju in članom izbranega prostora. Za zelo občutljive podatke trenutne izvedbe še ne priporočam.** Vsebina aktivne baze ni dodatno šifrirana, sinhronizacija nima šifriranja od naprave do naprave, pravila sistemskega kopiranja na Androidu niso določena, redno produkcijsko kopiranje pa v zadnjih dokazilih ostaja odprto.

Primeren začetni obseg so običajni kontakti v osebnem prostoru, brez občutljivih opomb. Gesla, obnovitvene kode, PIN-i, kopije osebnih dokumentov in podrobni zdravstveni zapiski potrebujejo drugačno raven varovanja. Tudi sam kontakt je lahko zelo občutljiv, če že povezava z določeno osebo razkriva zdravstvene, družinske ali druge zaupne okoliščine.

## Najpomembnejše ugotovitve

Stopnja opisuje posledice za navedeni scenarij. Arhitekturnih omejitev ne enačimo s potrjenim oddaljenim vdorom. V pregledanih poteh ni bil potrjen obhod prijave, pravic med uporabniki ali SQL injection.

### 1 Visoko za zelo občutljive podatke — aktivna lokalna vsebina je berljiva brez ključa

`openCollaborationDatabase` odpre običajno datoteko SQLite v aplikacijskem imeniku brez šifrirnega ključa. `personal_records.payload` vsebuje JSON; enaka baza hrani tudi prenesene skupne zapise in čakajoče operacije. Zaščita je zato odvisna od izolacije aplikacije, zaklepa in zaščite diska operacijskega sistema.

**Vpliv:** kdor pridobi berljivo kopijo datoteke baze, lahko prebere kontakte in zapiske brez gesla računa ali gesla prenosne kopije. To ne pomeni, da lahko bazo na pravilno zaščitenem telefonu bere katerakoli običajna aplikacija.

Dokaz: [collaboration_database_native.dart](../lib/organizer/data/collaboration_database_native.dart), vrstice 6–12; [collaboration_database.dart](../lib/organizer/data/collaboration_database.dart), vrstice 114–125 in 163; [sqlite_organizer_storage.dart](../lib/organizer/data/sqlite_organizer_storage.dart), vrstici 607 in 965. Dejanski sintetični preizkus prek `SqliteOrganizerStorage.write` je vnesel izmišljeno osebo, zaprl bazo, našel ime in zapiske v surovih bajtih ter jo ponovno odprl brez ključa. [Rezultat](../build/qa/security-review-20261015/plaintext-storage-proof.json), [preizkus](../build/qa/security-review-20261015/plaintext_storage_proof_test.dart).

Za občutljiv način uporabe je potrebna zasnova šifriranja baze in priponk s ključem v varni shrambi ter zaklepanjem aplikacije. Ob tem je treba zajeti tudi stare Hive podatke, SQLite dnevnike, začasne izvoze in preference. Zgolj dodan zaslon za PIN datoteke baze ne šifrira. Obstoječe brezpovezavno delo in obnovitev morata ostati podprta.

### 2 Visoko pri kompromitiranem gostovanju — strežnik lahko bere sinhronizirano vsebino

FamilyHub shrani vsebino neposredno kot JSON v `familyhub_records.payload`; slike hrani kot navadne datoteke. HTTPS ščiti prenos, ne vsebine pred skrbnikom strežnika, dostopom do baze ali prevzemom gostovanja. Osebni strežniški prostor je zaseben pred drugimi običajnimi uporabniki, vendar nima šifriranja, ki bi vsebino skrilo pred upravljavcem strežnika.

Dokaz: [NativeSyncService.php](../server/plugins/FamilyHub/Model/NativeSyncService.php), vrstice 92–96; [NativeIdeaAssetService.php](../server/plugins/FamilyHub/Model/NativeIdeaAssetService.php), vrstice 59–67. Slike imajo zaščitene poti in pravice 0700/0600; to je dobra kontrola dostopa, ne šifriranje.

Po [produkcijskih dokazih](server/PRODUCTION_SETUP.md), vrstica 185, produkcija in testne namestitve uporabljajo isti cPanel račun. Ločene baze v takem računu niso ločena skrbniška varnostna meja. Prevzem ene aplikacije z možnostjo izvajanja kode kot isti sistemski uporabnik lahko ogrozi tudi druge. To ni trditev, da imajo drugi naročniki istega ponudnika avtomatično dostop.

Pred zelo občutljivo uporabo priporočam ločitev produkcije od testnih in drugih spletnih aplikacij na ravni gostovalnega računa, najmanjše potrebne pravice in zaščitene kopije. Če mora biti vsebina skrita tudi gostitelju, je potrebno pravo šifriranje od naprave do naprave. Šifriranje z istim ključem, ki je stalno dostopen aplikaciji na strežniku, tega cilja ne doseže. Šifriranja diskov gostitelja v tem pregledu nisem preverjal.

### 3 Srednje — Android nima izrecne politike sistemskih kopij

Glavni manifest in shranjeni manifest izdajnega AAB29 ne določata `allowBackup`, `fullBackupContent` ali `dataExtractionRules`. Lokalna baza in preference zato nimajo aplikacijskih izključitev iz sistemskega kopiranja/prenosa. To velja tudi za podatke, pri katerih uporabnik ni vključil FamilyHub sinhronizacije.

Dokaz: [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml), vrstice 4–8; [manifest AAB29](../build/qa/default-sound-release-20261015/android/android-release-manifest.xml). Te datoteke in ključne pregledane datoteke za shrambo, sejo, transport ter kriptografijo so bajtno enake zamrznjenemu izvoru AAB29.

Android privzeto omogoča Auto Backup; dejansko kopiranje je odvisno od naprave, nastavitev, različice sistema in omejitev velikosti. Kopije imajo lastne zaščite, v podprtih pogojih tudi šifriranje s skrivnostjo naprave. Ugotovitev zato **ni**, da so vse Google kopije javne ali nešifrirane. Manjka zavestna politika aplikacije glede tega, kaj sme zapustiti napravo in pod kakšnimi pogoji. Fizičnega backup/restore postopka nisem izvedel. [Uradna dokumentacija Android](https://developer.android.com/identity/data/autobackup).

Treba je določiti in preizkusiti pravila za oblak ter prenos med napravami, posebej za baze, priponke in varno shrambo sej. Tega ne rešujmo s tihim izklopom vseh uporabniških možnosti obnove. Tudi zgolj `allowBackup=false` po dokumentaciji ne pokrije vseh prenosov med napravami.

### 4 Srednje — naslovi opomnikov lahko razkrijejo vsebino zunaj aplikacije

Oddaljeni push vključuje naslov zapisa oziroma ime prostora. To besedilo prejme FCM in lahko postane vidno v sistemskem obvestilu. Lokalni opomniki prav tako uporabljajo naslov opravila/dogodka. Prikaz na zaklenjenem zaslonu je odvisen od sistemskih nastavitev.

Dokaz: [NativePushPresentation.php](../server/plugins/FamilyHub/Model/NativePushPresentation.php), vrstice 18 in 39–48; [NativeFcmTransport.php](../server/plugins/FamilyHub/Model/NativeFcmTransport.php), vrstice 51–64; [notification_coordinator.dart](../lib/organizer/platform/notification_coordinator.dart), vrstice 194–235. Pregledana pot ne pošilja celotnih opomb ali celotne baze v push.

Naslov/telo lokalnega opomnika se dodatno shranita kot navaden JSON v SharedPreferences: [local_notification_adapter.dart](../lib/organizer/platform/local_notification_adapter.dart), vrstice 136–143 in 243–253. Poimenovanje `fingerprint` tu ne pomeni zgoščene vrednosti. Zato šifriranje samo SQLite ne bi pokrilo vseh kopij besedila.

Koda odjave tudi ne počisti že prikazanih oddaljenih obvestil; Androidov background handler jih izriše brez primerjave s trenutno aktivno sejo. Star naslov lahko ostane v vrstici po odjavi oziroma se pokaže iz že odposlanega sporočila. [remote_push_lifecycle.dart](../lib/organizer/platform/remote_push/remote_push_lifecycle.dart), vrstica 181; [firebase_push_sdk.dart](../lib/organizer/platform/remote_push/firebase_push_sdk.dart), vrstici 14 in 150; [system_push_display.dart](../lib/organizer/platform/remote_push/system_push_display.dart), vrstice 89–107. To je ugotovitev iz kode, ne fizično reproduciran scenarij na telefonu. Odpiranje zapisa ima ločene preverbe identitete in dostopa.

Priporočilo je izbiren zasebni prikaz z generičnim besedilom, čiščenje obvestil odjavljenega računa in preverba aktivne registracije pred prikazom. Do takrat naj naslovi opomnikov ne vsebujejo občutljivih podatkov.

### 5 Srednje — običajen izbris zapisa ohrani vsebino v operacijski zgodovini

Običajen `sync` izbris nastavi trenutni `payload` na NULL. Prejšnji uspešni odgovori z vsebino zapisa pa ostanejo v `familyhub_operations.response`, ki podpira varno ponavljanje zahtev.

Dokaz: [NativeSyncService.php](../server/plugins/FamilyHub/Model/NativeSyncService.php), vrstice 92–96 in 121–124; [NativeDatabase.php](../server/plugins/FamilyHub/Model/NativeDatabase.php), vrstice 294–296. To ni samodejen dostop drugih uporabnikov do zgodovine, pomeni pa, da izbris kontakta iz UI ne odstrani vseh njegovih strežniških kopij.

Ločen izbris prostora/projekta stare odgovore redigira ([NativeScopeLifecycleService.php](../server/plugins/FamilyHub/Model/NativeScopeLifecycleService.php), vrstice 72–76); tudi izbris računa ima lastno redakcijo in odstranjevanje ([NativeAccountDeletionService.php](../server/plugins/FamilyHub/Model/NativeAccountDeletionService.php), vrstice 219, 234–237 in 338–347). Ugotovitve ne posplošujemo na te postopke. Kopije in že preneseni podatki imajo svoje življenjske cikle.

Za občutljive zapise je treba določiti hrambo zgodovine in vsebino varno redigirati ob izbrisu, pri tem pa ohraniti identifikatorje ter pravilnost ponovljenih zahtev.

## Pomembne meje uporabe

**Deljenje velja za prostor.** `householdPerson` vsebuje ime in opombe, nima pa dodatnega dovoljenja za posamezen kontakt. Po odobritvi dostopa `sync` vrne zapise prostora. Kontakta z zasebnimi opombami zato ne shranjuj v skupni prostor, če ga ne smejo videti vsi upravičeni člani. Dokaz: [NativeRecordPolicy.php](../server/plugins/FamilyHub/Model/NativeRecordPolicy.php), vrstice 18 in 33–35; [NativeSyncService.php](../server/plugins/FamilyHub/Model/NativeSyncService.php), vrstice 149–163. Osebni prostor ima dodatno strežniško preverbo lastnika. Preklic pravic ne more izbrisati že izdelane kopije druge osebe.

**Redne produkcijske kopije še niso potrjene.** Obstajajo preverjene kopije pred nadgradnjami in dokazi obnovitev. To ne potrjuje stalnega intervala, hrambe, ločene kopije ob izgubi gostovanja ali obveščanja o napakah. Zadnji operativni zapisi to še vodijo kot odprto: [PRODUCTION_PUSH.md](server/PRODUCTION_PUSH.md), vrstice 138–140; [UPGRADE_0_14.md](server/UPGRADE_0_14.md), razdelki o dejanskih obnovah. Današnje preverjanje javnega API tega ne more razjasniti. Preden je sistem edina kopija pomembnih kontaktov, je treba urediti redno zaščiteno kopiranje in poskus obnove. Sinhronizacija ni varnostna kopija.

**Prenosna kopija ni isto kot aktivna baza.** `.vsakdan` uporablja AES-256-GCM, PBKDF2-SHA256 s 600.000 iteracijami, naključno sol in nonce ter geslo z najmanj 12 znaki. To je dobra zaščita izvoza ob močnem geslu. Napredni JSON izvoz je namenoma nešifriran in ima opozorilo. Dokaz: [portable_backup_crypto.dart](../lib/organizer/data/portable_backup_crypto.dart), vrstice 7–50; [README.md](../README.md), vrstice 188–195. Za shranjeno kopijo kontaktov uporabi šifrirani format in dolgo, enkratno geslo.

## Kaj je dobro zaščiteno

- Transport aplikacije zahteva HTTPS, ne izklaplja preverjanja certifikatov in zavrne preusmeritve. HTTP je dovoljen samo ob izrecni razvojni izbiri za loopback. [collaboration_transport.dart](../lib/organizer/data/collaboration_transport.dart), vrstice 22–42, 81 in 105.
- Seja je v `FlutterSecureStorage`, brez nadomestnega shranjevanja v navadne preference. Napaka varne shrambe je napaka, ne razlog za oslabitev zaščite. [device_session_store.dart](../lib/organizer/data/device_session_store.dart), vrstice 18–61.
- Strežnik izdaja naključne 256-bitne žetone, hrani njihov hash in preverja potek, preklic, aktivnost uporabnika ter spremembe gesla/TOTP. Prijava ima omejevanje poskusov in podporo TOTP z zaščito pred ponovno uporabo. Podpora TOTP ne dokazuje, da ga ima določen uporabnik vključenega. [NativeAuthService.php](../server/plugins/FamilyHub/Model/NativeAuthService.php), vrstice 69, 105–153; [NativeDatabase.php](../server/plugins/FamilyHub/Model/NativeDatabase.php), vrstice 118–167.
- Osebni prostor, pravice pisanja, finance in slike imajo strežniške preverbe. Obnova gesla ne obide TOTP; povabila so časovno omejena in vezana na ustrezno identiteto. SQL vrednosti uporabljajo pripravljene poizvedbe. [NativeDatabase.php](../server/plugins/FamilyHub/Model/NativeDatabase.php), vrstice 24–28 in 201–204; [NativePasswordResetService.php](../server/plugins/FamilyHub/Model/NativePasswordResetService.php), vrstice 14 in 24–33; [NativeEmailInvitationService.php](../server/plugins/FamilyHub/Model/NativeEmailInvitationService.php), vrstice 48–85.
- Uvoz slik v Idejnik ponovno kodira piksle in odstrani metapodatke; format, velikost in dostop se preverjajo. Odprtje obvestila preverja identiteto in pravice, ne preklopi samodejno na drug račun. [idea_repository.dart](../lib/organizer/data/idea_repository.dart), vrstice 323, 381 in 443; [collaboration_remote_push_routing.dart](../lib/organizer/data/collaboration_remote_push_routing.dart), vrstica 98.

## Opravljeno preverjanje in njegove meje

Izvedenih je bilo **87 ciljnih Flutter testov** (35 + 51 + en nov sintetični dokaz lokalne hrambe) in **12 izoliranih PHP kontrol**, vsi uspešni. PHP preizkus uporablja dejansko implementacijo osnovnih sej/pravic z minimalno izmišljeno SQLite bazo v novem vsebniku brez omrežja, brez produkcijskih podatkov in brez pisanja v obstoječe testne baze. Pokriva veljavno/neveljavno sejo, osebnega lastnika/tuji račun, bralca proti pisanju, spremembo gesla/TOTP, potek, preklic in omejevanje poskusov. [PHP preizkus](../build/qa/security-review-20261015/native-security-probe.php) in [poreklo ter ponovitev](../build/qa/security-review-20261015/native-security-probe-evidence.txt).

Ob **16:18 UTC** je neavtenticiran preizkus `jivie.triparna.si` ob veljavnem certifikatu vrnil capabilities HTTP 200, `sync6.pull` in `ideas.asset.download` pa HTTP 401 `auth_required`. Odgovori imajo `Cache-Control: no-store` in `X-Content-Type-Options: nosniff`. Uporabljeni so bili izmišljeni ID-ji in samo bralne operacije. [Dokaz](../build/qa/security-review-20261015/public-checks.json).

Pregled vključuje izvor PHP/Dart, izdajni manifest AAB29 in obstoječa operativna dokazila. Lokalni varnostni skill nima namenskih smernic za PHP/Dart; ugotovitve zato temeljijo na konkretni kodi, preizkusih in primarnih dokumentih. OWASP izrecno obravnava zaščito lokalne občutljive hrambe ter kopij: [MASVS Storage](https://mas.owasp.org/MASVS/05-MASVS-STORAGE/), [sistemske kopije](https://mas.owasp.org/MASWE-0006/).

Uradni seznam ob pregledu navaja Kanboard 1.2.54 kot zadnjo izdajo, z več varnostnimi popravki. To ni dokaz odsotnosti ranljivosti: [izdaje](https://kanboard.org/releases.html), [popravki 1.2.54](https://kanboard.org/releases/kanboard/v1.2.54.html). Celovita revizija vseh prehodnih odvisnosti, jedra Kanboarda in nastavitev gostitelja ni bila izvedena.

Današnji javni HTTP preizkus ne preverja produkcijske prijave dveh uporabnikov, vključenosti TOTP na tvojem računu, pravic sistemskih datotek ali dejanske obnovitve telefona. Šifriranje diskov, fizični zaklep in prikaz obvestil niso bili preizkušeni na napravi. Ni bilo novih native gradenj, trgovinske oddaje, sprememb aplikacijske kode, konfiguracije gostovanja ali uporabniških zapisov.

## Priporočen vrstni red

1. Za trenutno uporabo: osebni prostor, najmanj potrebnih kontaktnih podatkov, močan zaklep naprave, enkratno geslo računa, TOTP, kjer je nastavljen, in šifrirana prenosna kopija. Občutljivo besedilo naj ne bo v naslovih opomnikov.
2. Urediti dokazljivo redno produkcijsko kopiranje ter izrecna Android pravila za kopije in prenos med napravami.
3. Dodati zasebni način obvestil in čiščenje ob menjavi računa ter omejiti nepotrebno podvajanje besedila v preferencah.
4. Pred zelo občutljivo uporabo zasnovati šifriranje lokalne vsebine, ključe, obnovitev in aplikacijski zaklep; utrditi ločitev produkcije ter pravila hrambe izbrisanih vsebin.
5. Če je cilj zaupnost tudi pred gostiteljem, posebej zasnovati šifriranje od naprave do naprave in njegove posledice za deljenje, obnovitev ter strežniške opomnike.
