# Priprava prve javne iOS izdaje

13. oktober 2026 — uporabnik je odprl App Store Connect in naročil nadaljevanje
do javne izdaje na podlagi Android kandidatke. Potrdil je možnost fizičnega
preizkusa na iPhonu in zasebni kontakt za App Review. Telefonske številke in
preglednega gesla ta dokument ne vsebuje.

## Gradnja, podpis in Applova obdelava

- Mobilni izvor **fa809b8**, enak Android1.7.0(25); ločena kopija pod
  `build/qa/ios-public-20261013/source`. Vseh **283 javnih lib/assets vhodov**
  se ujema z zamrznjenim Android25 manifestom. Pubspec in CocoaPods zaklenjeni
  odvisnosti sta bajtno ohranjeni, SDK ni nadgrajen.
- Sveži razvojno podpisani arhiv **1.7.0(25)** je uspešno zgrajen. Prvi
  poskus v sveži kopiji je potreboval ustvaritev manjkajočega ephemeral
  paketa; `pub get --offline` ustvari prazen Swift paket, plugin izvedba
  ostane CocoaPods brez medijskega/glasbenega file_picker dela.
- CLI distribucijski izvoz vrne `No Accounts`; običajni Xcode UI pokaže
  obstoječi račun in **TriparNA z.o.o., Admin**. Organizer uspešno podpiše
  in izvozi z obstoječim **Cloud Managed Apple Distribution**, veljavnim
  do26.9.2027. Ni novega lokalnega ključa/CSR ali preklica certifikatov.
- Preverjeni izvoženi `export/Jivie.ipa`: **27.818.651 bajtov**, SHA256
  `7df6c483b1fa77d7096206cdb94a36ac8addb5cd00c9c86fe5006b54048e670f`.
  ZIP CRC in strict/deep podpis PASS; bundle `si.triparna.jivie`, team
  `CXNM99632B`, API iOS15+, SDKiphoneos27.0/Xcode27A266a. Store profil ima
  `aps-environment=production`, `get-task-allow=false`, brez napravnega seznama.
- Isti sveži arhiv je prek Organizerja dejansko naložen. App Store Connect
  kaže **Complete** za1.7.0(25), build ID
  `4abbd687-0a78-4a15-8896-e95d340e3ec1`,13.10. ob22:05. Ni ponovitve stare
  zavrnjene1.0.1(2). Navedeni IPA hash pripada preverjenemu izvozu; pri ločenem
  cloud podpisovanju za upload ne trdimo bajtne identičnosti obeh ZIPov.
- Končni paket ima **18 SDK privacy manifestov**. File_picker binary ohrani
  UIDocumentPicker in nima pregledanih UIImagePicker/PHPhoto/AVCapture/DKImage
  referenc. Info.plist ne dodaja kamere, široke galerije ali ATT dovoljenja.
  To ni fizični dokaz iOS izbirnika ali oddaljenih obvestil.

## Trgovinski osnutek

App ID **6820232114**, primarni jezikSL, pravi bundle/SKU `jivie-ios`.
Osnutek je posodobljen na **1.7.0** in ima pripeto obdelano gradnjo25.
SL/en-US opisa3391/3475 znakov, podnaslova, promocijski besedili, ključne besede,
support/help in marketing URL, copyright2026TriparNA ter App Review kontakt
in navodila so shranjeni. Pregledni uporabnik je `jivie_review`; **geslo še
ni vneseno**. Pred oddajo mora lastnik obstoječe pregledno geslo vnesti neposredno
v Applov zasebni obrazec, brez posredovanja v pogovor ali javni Git.

Cena **0EUR**, osnovni trgSlovenija. Edina država jeSlovenija z vidnim stanjem
**Available on App Release**;174 drugih državNot Available. Public distribucija
in samodejna izdaja po odobritvi ostaneta. Distribucija iOS paketa na Apple
Silicon Macs in Vision Pro je izključena; namizna izdaja je ločeno delo.
Obstoječa oznaka trader ostane; pogodbe, bančni/tax podatki in pravice uporabnikov
niso spremenjeni.

Starostni vprašalnik je shranjen: UGCYes, brez socialnega feeda/klepeta/oglasov,
neomejenega spletnega brskalnika, starostnega preverjanja ali starševskih kontrol.
Vgrajene občutljive vsebine/gambling/medicinske trditveNone/No. Izračun4+ je
povišan na **18+** za potrjeno ciljno skupino odraslih; starejši OS ima17+.
Content RightsYes za licencirane sestavine in dovoljeno uporabniško vsebino;
Apple standardna licenca ostane.

## Posnetki

**7 iPhone1320×2868 in7 iPad2064×2752** je dejansko naloženih in sprejetih v
Media Managerju. iPhone large galerija se za zahtevani medium prikaz uporablja
prek **Using Existing Assets**. en-US iPad podeduje primarno galerijo.
Vključeni so Utrip, Opravila, Koledar, Idejnik, Prostor, Več in odprta tabla s
fotografijo, skico, lističema ter vezanima oznakama.

Gre za dejanske **widget izrise iz zamrznjenega mobilnega izvora**, s platformo
iOS in izoliranimi pomnilniškimi podatki. Niso novi posnetki fizičnega iPhona.
SFNS pisava zagotavlja manjkajoči sistemski fallback testnega izrisovalnika;
ni distribucije pisave ali spremembe produkcijske teme. Foto fixture ima
isti Pexels izvirnik/licenco kot Android tabla. iPad uporablja večjo dejansko
kamero viewerja, brez spremembe geometrije elementov. Zbiranje slik je2ciljna
prehoda navigacije ter po1izris editorja za vsako napravo; vsiPASS. Prejšnji
funkcionalni testni krog ni ponovljen.

Kodiranje v RGB PNG brez alpha kanala preveri, da se **vsak vidni RGB pixel in
dimenzije ohranijo**. Ni povečave, obrezovanja, dodatnih slikovnih slojev ali
AI generiranja. Orodja: `ios_store_screenshots_test.dart`,
`ios_ideas_screenshot_test.dart`, `encode_ios_store_png.dart` v `tools/release`.

## Zasebnost in šifriranje

App Privacy ima dokončanih12vrst, brez sledenja:

| Vrste | Namen | Povezane |
| --- | --- | --- |
| Name, Email, Physical Address, Contacts, Other Financial Info, Purchases, Photos/Videos, Other User Content, User ID, Device ID | App Functionality | Da |
| Other Diagnostic Data | App Functionality in Analytics | Ne |
| Other Data Types | Analytics | Ne |

Apple Calendar nima ločene vrste; dogodki soOther User Content. FCM/Firebase
Installations/GoogleDataTransport manifesti in dejanska uporaba po opt-in
utemeljijo tehnični vrsti. To ni vključitev Firebase Analytics ali Crashlytics.
Contacts zajema ročni socialni graf, ne sistemskega imenika. Photos/Videos v
Applovi skupni oznaki zajema samo dejansko podprte fotografije.
SL privacy/delete URL sta shranjena; javna politika že opisuje tehnične SDK
podatke, fotografije in izbirno deljenje na izbranem strežniku.

**Objava App Privacy še čaka izrecno potrditev lastnika.** Applov končni Publish
vključuje soglasje o točnosti, pravilih/zakonodaji in prihodnjem posodabljanju.
Pregledan konkretni obrazec je pripravljen, agent zadnjega gumba ni pritisnil.

Šifriranje je shranjeno na gradnji25: **Standard encryption algorithms outside
or in addition to Apple OS**, France **No**. AES256-GCM/PBKDF2 z Dart fallbackom
ni označen kot odsotno šifriranje ali izključno OS. Po odgovoru je gradnja
**Ready to Submit / Ready to Test**, brezMissing Compliance. Info.plist
`ITSAppUsesNonExemptEncryption` ni nastavljen na slepo. Ponovna distribucija
vFranciji potrebuje ločen pregled Applove zahteve glede dokumentacije.

Primarni viri pregledani13.10.2026:
[Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/),
[Firebase Apple razkritja](https://firebase.google.com/docs/ios/app-store-data-collection),
[Apple šifriranje](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/),
[Apple velikosti slik](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## TestFlight in natančna meja nadaljevanja

Ustvarjena interna skupina **Pred javno objavo**,
`31680638-0725-4e30-96ff-d79a6aac94e7`; gradnja25je dodana inReady to Test.
Samodejna distribucija vseh prihodnjih gradenj je izključena. **0testerjev**;
povabilo čaka uporabnikov Apple ID. Ni vabljenja drugih oseb ali novih
App Store Connect upravljavskih pravic.

Javna iOS oddaja **še ni izvedena**. Ostajajo potrditev App Privacy, izbrani
TestFlight preizkuševalec/dejanska iPhone namestitev ter pregledno geslo.
Fizično preveriti lokalni vnos/restart, foto izbirnik in pan/zoom Idejnika,
lokalni opomnik ter šifriran izvoz/predogled obnove. iOS APNs povezava/dostava
ostajata ločeno nepotrjeni; ne pripisuj Android dokaza iPhonu.
Nato zaključiti konkretne morebitne App Review validacije in oddajo.

Dokazi so v ignorirani `build/qa/ios-public-20261013/`: arhiv/izvoz,
`ipa-evidence.json`, `source-evidence.json`, SDK manifesti, upload dokaz,
TestFlightComplete, encryption odgovora, App Privacy predlog/potrditveno okno,
metadataSL, availability in dejanske shranjene galerije ter sliki formata RGB.

AndroidAAB25 po koncu ohranja SHA256
`ef909cddea12b22ac3ec9a7c3805a7ed1a55e6cbe3c00368f767799953a27447`.
Android oddaja/paket, SDK/locks/dovoljenja, nameščene aplikacije, gostovanja in
uporabniški podatki niso spremenjeni. Drugo sočasno delo na produkcijskih
strežniških pomočnikih ni del te iOS priprave.
