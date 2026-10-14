# iOS 1.7.1 (26) — povezovanje lokalnega prostora

14. oktober 2026. Uporabnik potrdi namestitev prejšnje TestFlight različice in
naroči nadgradnjo z zadnjim popravkom povezovanja prostora. Funkcionalnih tokov
na iPhonu s tem še ni potrdil.

## Izvor in preverjanje

Sveža izolirana kopija mobilnega **fa809b8** z natanko popravkom **6ae5667**
in različico **1.7.1+26**, enako javni Android26. Med333 izvornimi lib/assets/
iOS/pubspec vhodi sta v primerjavi z iOS25 spremenjena samo
`local_space_connection_panel.dart` in različica. Vseh285 skupnih javnih
runtime/pubspec vhodov se ujema z zamrznjenim Android26 manifestom. Namizne
spremembe iz main niso vključene.

Po potrditvi predogleda se odprejo obstoječa pravila izbranega strežnika;
izrecni sprejem nadaljuje isto publikacijo enkrat. Preklic ali menjava računa
ne preneseta lokalne vsebine. **7 ciljnih testov povezovanja PASS** v novem
izoliranem izvoru. Prejšnjih29 kontrol in celotne funkcionalne matrike ne
ponavljamo; [Android dokazi](SPACE_CONNECTION_RELEASE.md).

Vsi333 zamrznjeni vhodi so enaki pred/po gradnji. Oba locka, SDK, vseh48
izvornih iOS datotek, private Firebase konfiguracija in18 SDK privacy
manifestov so ohranjeni. Paket nima novih UsageDescription ključev;
Firebase autoInit ostane false. Dejanski AOT vsebuje isto izrecno iOS
Firebase identiteto. Podatkovni formati, strežniki in sheme so isti.

## Podpis in nalaganje

Sveži arhiv1.7.1(26) je zgrajen; CLI izvoz še vedno nima Accounts, zato
običajni prijavljeni Xcode Organizer podpiše z obstoječim Cloud Managed
Apple Distribution/profilom do26.9.2027. Ni novih ključev ali certifikatov.
Manage version/build in Internal only sta izključena; symbols vključeni.

Preverjeni izvoz `export/Jivie.ipa`: **27.822.145 bajtov**, SHA256
`c98d7f0ef56dee679bfdf33ee35c940666d8fc21df6e2154ff36ed32b55b2f94`.
CRC/strictdeep PASS, bundle `si.triparna.jivie`, teamCXNM99632B, iOS15+,
SDKiphoneos27.0/Xcode27A266a, productionAPS/get-task-allowfalse in Store
profil brez seznama naprav. Isti arhiv je prek Organizerja dejansko naložen
ob16:24. Hash izvoza ni trditev bajtne identičnosti ločenega cloud upload ZIPa.

Apple je pred nadaljevanjem zahteval novo Developer Program License Agreement
z datumom13.10.2026. Agent jo je odprl; **lastnik jo je sam sprejel**, nato
zahteva izgine. Agent ni sprejel pogodbe v njegovem imenu.

## Dostava in meja zaključka

Apple je obdelavo zaključil: **Complete**, build
`b4430bb0-e007-4b35-9848-ecfe2440ab53`. Šifriranje je ponovno pravilno
shranjeno kot standardno zunaj/poleg Apple OS, FranceNo; ni lažnega
NoEncryption ali novega Info.plistfalse. Gradnja26 je dejansko dodana v
obstoječo **Pred javno objavo**, vidno **Testing /1tester/2builds**. Prejšnji25
ostane ohranjen in ni expired. Kratka slovenska navodila What to Test so shranjena.

App Store osnutek je shranjen kot **1.7.1 s pripeto26**, Save disabled po
shranitvi. Odpetje25 odstrani samo povezavo v osnutku, ne arhiva/zgodovine.
Objavljeni App Privacy, opisi, galerije in Slovenija/cena se ne spreminjajo.
Pregledno geslo je zdaj **prisotno v shranjenem obrazcu** (preverjena samo
bool prisotnost, brez branja/izvoza); njegove pravilnosti s tem ne potrjujemo.

**Javna iOS oddaja ni izvedena.** Fizična namestitev26, povezovanje prostora,
foto/pan/zoom/restart/opomnik/kopija ter APNs dostava še niso potrjeni.
Pred javno oddajo je potreben kratek fizični preizkus26 in pregled dostopa
za Apple. Android26, njegov javni status in neaktivni interni kanal, splet,
gostovanja/FamilyHub ter uporabniški podatki niso spremenjeni.

Dokazi: ignorirana `build/qa/ios-connection-release-20261014/` vsebuje
source/runtime/native/Firebase/IPA evidence, ciljni testni dnevnik,
gradnjo/arhiv/izvoz, Xcode upload, encryption odgovora, `testflight-testing`
PNG/TXT in `store-build.txt` ter pogodbeni prikaz pred/po lastniku.
