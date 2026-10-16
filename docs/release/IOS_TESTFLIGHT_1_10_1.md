# iOS 1.10.1 (31) — Apple Complete, TestFlight Testing še ni potrjen

16. oktober 2026. Novo izrecno uporabnikovo naročilo nadaljuje prej odloženo
iOS izdajo: pregled prejšnjih pogovorov in Android/strežniških izdaj, aktualna
iOS gradnja in nalaganje za TestFlight. Javna App Store oddaja ni naročena.

**Xcode Organizer potrjuje »App upload complete: Jivie 1.10.1 (31) uploaded«,
16. oktobra ob 16:11 po slovenskem času.** Safari nato potrdi Apple obdelavo
**Complete**, gradnja `cae5d3b5-2a72-4197-98f7-c80100a57758`. Izvozna odgovora
in vključitev v skupino TestFlight še niso potrjeni. Ne ponavljaj gradnje ali
nalaganja samo zaradi nedelujočega spletnega portala.

## Izhodišče in obseg

Pregledani so pogovori »Preveri pripravljenost za izdajo (3)«, »Dodaj opombo za
prikaz gesla« in pogovor prenove povabil ter njihovi izdajni dokumenti.
Zadnja prej potrjena TestFlight Testing je bila 1.7.1 (26); 1.9.0 (28) je bila
že naložena, njena vključitev v TestFlight pa odložena.

Nova gradnja vključuje aktualni Android 1.10.1: vse nadgradnje po iOS 26,
nastavitve opomnikov, Vrt/Idejnik/projekte, privzeti zvok samo za nove ali
manjkajoče nastavitve, zaključevanje opravil, projektni meni in kontrast ikon,
poenostavljena povabila/deljenje, preglednice/priloge ter povečavo in pomoč pri
formulah. Produkcija in pregledni test1 sta po [dokazih](../server/UPGRADE_0_15.md)
že FamilyHub 0.15.0/shema19; nova strežniška nadgradnja ni izvedena.

## Zamrznjeni izvor in preverjanje

- Commit **3ce710551f2aaf0d0583afe6bab1ce55606bbbd3**, usklajen z `origin/main`.
- Različica **1.10.1+31**, identiteta `si.triparna.jivie`, team `CXNM99632B`.
- **443 javnih izdajnih vhodov in 330 skupnih runtime vhodov**, vsi bajtno
  enaki zamrznjenemu Android31; agregat SHA256
  `15cfd77ecc601019cb1f27fb776f39414a7f5c3875c573bf7c161ad685bfec38`.
- Vseh 48 izvornih iOS datotek, trije locks in konfiguracijski hashi so enaki
  prejšnji iOS28. SDK/dependencies niso nadgrajeni. Izolirana kopija in vsi
  javni/config vhodi so preverjeni pred in po gradnji.
- **23 ciljnih Flutter PASS**: Firebase konfiguracija, povečava/pomoč,
  povezovanje lokalnega prostora in izdajna meja. Prejšnja funkcionalna matrika
  ni ponovljena. Dva začetna ukaza sta imela napačno ime testne datoteke;
  končna dejanska nabora sta 16 in 7 PASS. To ni bila aplikacijska regresija.

Natanko en nov iOS arhiv je zgrajen v ločeni mapi
`build/qa/ios-testflight-1.10.1-20261016/source/build/ios/archive/Runner.xcarchive`.
CLI izvoz ima znano »No Accounts« omejitev; distribucija je uspešno opravljena
prek obstoječe prijave v Xcode Organizer. Flutter opozorilo o privzeti launch
image ostane; ni napake pri arhiviranju ali zavrnitve nalaganja.

## Distribucijski podpis in IPA

Obstoječi Cloud Managed Apple Distribution in Store profil veljata do
26. 9. 2027. Manage version/build in TestFlight internal only sta izključena,
symbols vključeni. Ni novega certifikata ali zasebnega ključa.

Izvoz iste distribucije:
`build/qa/ios-testflight-1.10.1-20261016/ios-store-export-31/Jivie.ipa`

**28.449.881 bajtov**, SHA256
`33d7b38747727461b63f4e68db99a99504547311fddb697534191cd1f533665a`.
CRC in strict/deep codesign PASS; production APS, get-task-allow=false,
Store profil brez seznama naprav, iOS15+, iphoneos27.0/Xcode27A266a.
Vseh18 SDK privacy manifestov in UsageDescription ključi so enaki iOS26.
Firebase auto-init ostane false, dejanska AOT vsebuje izrecno iOS Firebase
identiteto. Ni podpisnih ključev ali strežniških poverilnic v IPA.
Hash lokalnega izvoza ni trditev o bajtni enakosti Applovega upload arhiva.

## Slike in spletni zaključek

Na novo je izrisanih **40 dejanskih iOS widget slik**: 10 prizorov × iPhone/iPad
× SL/EN, vključno s preglednico in novim čarovnikom povabila. Samo sintetični
pomnilniški podatki; nobenega novega računa ali strežniškega zapisa.
**16 capture scenarijev PASS**, vseh40 slik je vizualno pregledanih; mere
1320×2868/2064×2752, neprosojnost in različnost PASS. 32 nalagalnih RGB PNG-jev
ohrani vsak vidni RGB piksel. Galerija: Utrip, opravila, Idejnik, preglednica,
projekt, nakupi, Vrt in finance; koledar/povabilo sta lokalni alternativi.

Slike so v isti QA mapi (`screenshots/`, `upload/`, `screenshots-manifest.json`).
[Manifest slik](IOS_TESTFLIGHT_1_10_1_SCREENSHOTS.json) in
[SL/EN navodila za preizkus](IOS_TESTFLIGHT_1_10_1_NOTES.json) so tudi versionirani.
**V Apple še niso naložene**. Prejšnje Apple galerije/opisi/App Privacy in
osnutek 1.7.1 niso potrjeno spremenjeni.

App Store Connect je po začetni veljavni prijavi pri odpiranju Jivie in
TestFlight vračal »Sorry, something went wrong«. Poskus svežega zavihka in
običajnega brskalnika ni omogočil zaključka. Lastnik je po obnovi seje ponovno
potrdil prijavo; po njegovem naročilu nadaljujemo v že prijavljenem Safariju.
Ta pokaže Complete31/28/26/25 in obstoječo skupino Pred javno objavo z enim
testerjem ter dvema Testing gradnjama25/26. Tester ima nameščeno26. Vendar
razdelek različice31 vrne isto napako, izbira Add Build to Group za1.10.1
prikaže »No builds available«, neposredna stran31 pa onemogočen What to Test
brez nadzora za encryption ali dodajanje skupine. Osvežitev neposredne strani
in Apple osnutek prav tako ne omogočita nadaljevanja. Free Apps Agreement je
Active; novega Paid Apps Agreement ne sprejemamo. Nobena pogodba ali nova
pravica ni potrjena. Gesla in kode niso brani ali zapisani v izdajne dokaze.

Naslednje, ko bodo Applove nastavitve spet dosegljive: pravilno standardno šifriranje zunaj/poleg
Apple OS in FranceNo, shrani What to Test, dodaj31 v obstoječo skupino
**Pred javno objavo** brez novih upravljavskih pravic; nato uskladi Apple osnutek
in pripravljene galerije. **Ne izvajaj javne App Store oddaje.** Fizična
namestitev31 in APNs dostava še nista potrjeni.

Dokazi so v ignorirani `build/qa/ios-testflight-1.10.1-20261016/`: source manifest,
native parity, build/test/capture dnevniki, IPA evidence, release evidence,
Xcode upload PNG/TXT, Apple Complete PNG/TXT, pripravljene SL/EN TestFlight
opombe ter slike. IPA je ohranjena tudi kot
`build/releases/Jivie-1.10.1+31-ios-testflight.ipa`.
