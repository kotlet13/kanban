# Jivie1.9.0(28) — javni Android oddan, TestFlight odložen

15. oktober2026. Uporabnik naroča javniAndroid; prvotno naročeni iOSTestFlight
je po novi usmeritvi za zdaj odložen. Javne iOSoddaje ne izvajamo.
Windows/Linuxnative delo je odloženo. [Izvedba](../UPGRADE_IMPLEMENTATION.md).

## Končni izvor in paketi

Runtime **6ce59cf3958dbf5c7f5bc7b0e788049c0508b412**, main/push.
421zamrznjenih runtime/native vhodov,308skupnih; agregat
`3f403c42f2c1cf3ea4ed4d38a99119fb250c05c0a49e3879b0d94cbf7695296c`.
V primerjavi z vmesnim7af so spremenjene samo tri runtime datoteke: scheduler,
adapter in sharing_workspace. Nativekonfiguracije/3locks/SDK/Firebase isti.

- Android `build/releases/Jivie-1.9.0+28-android-firebase.aab`:80226012bajtov,
  SHA256`347d6d8b1a25c61c846a84c73d1112c8a6e41c6cd71dcb2bf36b64650fd3c61c`.
  Podpis/certifikat/bundletool/CRC/8dovoljenj/3ABIengine/Firebase/16KiBPASS.
- iOS `build/qa/upgrade-release-20261014/source/build/ios/archive/Runner.xcarchive`:
 216181591bajtov/213datotek, strictdeepsign/identiteta/Firebase/18privacyPASS.
 CLIexportNoAccounts je obit po običajnem prijavljenem Organizerju.
 Store izvoz `build/qa/upgrade-release-20261014/ios-store-export-28/Jivie.ipa`
 ima28211421bajtov/SHA256
 `1f4564d1f521182d44e89a67039797cbef02dc07caa0a971423da53dbc366780`.
 CRC/strictdeep/productionAPS/get-task-allowfalse/Storeprofile/18privacy
 in izrecna DartFirebase identiteta PASS. Obstoječi Cloud Managed Apple
 Distribution in profil do26.9.2027; brez novih ključev. Isti arhiv je
 **dejansko naložen**, Organizer pokaže »Jivie1.9.0(28)uploaded«.
 Dokaz `build/qa/upgrade-release-20261014/ios-upload-complete.jpg`.
 Apple obdelava/Complete in TestFlightTesting še nista potrjena.
- macOS `build/qa/upgrade-release-20261014/macos/DerivedData/Build/Products/Debug/Jivie.app`:
 svežiDerivedData/arm64PASS, namiznicom.example.kanbanohranjen, nepodpisan/nezagnan.

Dejansko3gradnje na platformo.8500f75 in7af sta ohranjena v rejected mapah
skupaj z izvorom/logi/razlogom; noben od prvih dveh ni bil naložen. Samo6ceje veljaven.
Dokazi v ignorirani `build/qa/upgrade-release-20261014/local-release-evidence.json`.

## Preverjanje

CelotniFlutter7af:1298PASS/15izrecnihopt-inpreskokov. Končne tri runtime
spremembe:62postavitvenih in27scheduler/adapter/coordinatorpreverjanjPASS.
Končnaanaliza6ce:10prejšnjih informacijskih ugotovitev v orodjih,0warning/error.
Sourcechecker/23izdajnih/7FirebasePASS. Žive naprave in novaOSobvestila niso
fizično potrjeni.

## Živo gostovanje

[Strežniški zapis](../server/UPGRADE_0_14.md) potrjuje **produkcijo in pregledni
test1 na FamilyHub0.14.0/schema18**. Vsak ima ločeni sveži capture, dosledno
kopijo ter resnično izolirano obnovo v MariaDB10.11.19 brez omrežja, vrat ali
host bindov. Produkcija92tabel/322vrstic/3računi/4naprave; test1
92tabel/313vrstic/3računi/8naprav. Vsi zgodovinski zapisi/definicije/gesla/
naprave/datoteke so ohranjeni. Natanko4novi stolpci,1nova prazna tabela in
101pregledanih izvornih datotek; isti serverId/config/ključi/core/HTTPS/cron.
Oba checkpointa potrdita `released`,APIpausedfalse/workerCronRestoredtrue.
Oba javna NativeAPI odgovora sta strogiHTTPS200/istiSID/enabled z novimi
kontraktnimi različicami za Vrt/Idejnik/opomnike/izbris/sync in push2.
Test2 ni del te nadgradnje. Ni bilo brisanja uporabniške vsebine za preizkus.

Prejšnja varna prekinitev14.oktobra in319vrstic kopija ostajata zgodovina.
Po odklenitvi je tudi ta arhiv resnično obnovljen kot ločeni zgodovinski dokaz;
za migracijo je uporabljena izključno nova produkcijska322vrstic kopija.

## Portala

**15. oktobra je Android1.9.0(28) dejansko oddan za javno posodobitev.**
Uporabnik je po težavah Brave izrecno zahteval Codexov vgrajeni brskalnik;
obstoječa Google seja je bila prijavljena v pravi TaknDevs račun. Običajni
filechooser je brez novega razširitvenega dovoljenja uspešno naložil isti
preverjeni AAB28. Ni nove gradnje, drugega paketa ali spremembe varnostnih
dovoljenj. Prejšnja zahteva za Brave »Allow access to file URLs« je odveč.

Produkcijski kanal4698247597354229997/release4 vsebuje28,27ni vključena v novo
izdajo. Uvajanje je100% v obstoječem ciljnem obsegu ene države/regije
(Slovenija). Predogled potrjuje **0izgubljenih in0novo podprtih naprav**,
API24+/target36/4postavitve/3ABI/1zahtevanofunkcijo. Ime in SL/en-USopombe
so iz [izdajnih besedil](UPGRADE_RELEASE_NOTES_1_9.json). Interni kanal ni
ustvarjen, nadaljevan ali spremenjen; ostaja neaktiven.

Za oba jezika je izbranih **8novih telefonskih slik** v zaporedju Utrip,
opravila, Idejnik, Vrt, projekt, nakupi, koledar, finance. Angleška galerija
ima svoje angleške prizore; prejšnje podedovane slovenske slike so zamenjane.
Angleške nalagalne kopije imajo enoličen prefiks `jivie-1.9-android-en-`,
vsi bajti in hashi pa so enaki prvotnim zajemom. Stari elementi ostanejo v
knjižnici, ikona/predstavitveni sliki ostaneta. Pregled obeh jezikov potrdi
osmerico; ohranjena sta posnetka `play-gallery-sl-review.png` in
`play-gallery-en-review.png` v izdajni QA mapi. V isti oddaji sta tudi že
pripravljena kratka in celotna opisa SL/en-US, brez sprememb njunega besedila
med tem korakom. Skupno je dokončno potrjenih **7sprememb**:1izdaja,2galeriji
in4besedila.

Po končnem »Pošljite spremembe v pregled« je dejansko viden status
**»Spremembe v pregledu«**, potrjeno ob04:44UTC/06:44CEST. Hitra Googlova
preverjanja še potekajo (prikaz do14minut); pregled/odobritev/javna dostopnost28
še niso potrjeni. Upravljano objavljanje je izklopljeno, zato objava sledi
Googlovi odobritvi. Doslej javna27ostane aktivna. Dokaza sta
[shranjeni prikaz](../../build/qa/upgrade-release-20261014/android-public-28-submitted.txt)
in [posnetek dejanske oddaje](../../build/qa/upgrade-release-20261014/android-public-28-submitted.png).
Naslednji korak je izid Googlovega pregleda, ne nova oddaja ali testna matrika.

**Uporabnik je v tem koraku izrecno odložil Apple/TestFlight in zahteval osredotočenje
na Android.** iOS28 je že podpisan/preverjen in naložen prek Organizerja,
vendar AppleComplete in TestFlightTesting28 še nista potrjena. V tem
Android koraku ni nadaljnjega Apple posega. Prihodnje nadaljevanje potrebuje
običajno spletno prijavo, potrditev obdelave/encryptionstandard+FranceNo in
vključitev28 v obstoječo Predjavnoobjavo z ohranjenima25/26. **Javne iOS oddaje
ne izvajati.** Prejšnja zahteva za takojšnjo Apple prijavo je zaradi odloga
neaktualna; geslo/kode ne sodijo v klepet.

## Novi trgovinski posnetki

15. oktobra je uporabnik izrecno naročil nove zajeme med čakanjem na
odklenitev Maca. Pripravljenih je **48 slik**: osem prizorov v slovenščini
in angleščini za Android telefon, iPhone in iPad. Prizori so Utrip, opravila,
koledar, odprta tabla Idejnika, projekt z mejniki, nakupovalni seznam z vnosom
artikla in količine, novi celozaslonski Vrt ter finance. iPad ohrani dejansko
širšo postavitev s stransko navigacijo.

Gre za izrise dejanskih gradnikov končnega runtime izvora 6ce59cf z ločenimi
vzorčnimi podatki v pomnilniku. To niso fizični zajemi naprav ali dokaz
sistemske tipkovnice/statusne vrstice. Fotografija v Idejniku je obstoječi
preverjeni slikovni vzorec. Slike niso naknadno grafično spreminjane.
Vrt uporablja pravi potisnjeni MaterialPageRoute z možnostjo vrnitve;
zajemi uporabljajo običajne sence in platformne pisave.

Vsak od treh sklopov ima šest uspešnih capture preizkusov in čisto ciljno
analizo. Vseh 48 slik je vizualno pregledanih. Validator potrdi dimenzije
720×1280, 1320×2868 in 2064×2752, popolno neprosojnost, različne slike za
vsako napravo/jezik/prizor ter vseh 421 nespremenjenih izdajnih vhodov.
Aplikacije, odvisnosti, različice in obstoječi izdajni paketi niso spremenjeni.

PNG-i so v `build/qa/upgrade-store-20261015`;
[manifest s hashi in vrstnim redom](UPGRADE_SCREENSHOTS_1_9.json) je shranjen
v repozitoriju. Paket `build/releases/Jivie-1.9.0+28-store-screenshots.zip`
ima 48 PNG-jev in manifest, CRC je preverjen. SHA256:
`a8a342e4a67c2c655f74c0b46ba147d9158e8c9b024c7fe94ee6b9aec355e4ca`.
16Android telefonskih slik je naloženih in vključenih v javno oddajo28.
Preostalih32iPhone/iPad slik ostane pripravljenih; AppStoreConnect slik
v tej nadgradnji nismo nalagali.
