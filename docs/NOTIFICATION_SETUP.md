# Nastavitev dostave obvestil

Center obvestil in lokalni opomniki delujejo brez Firebase. Uporabnik je 5. oktobra 2026 odobril pripravo Firebase Cloud Messaging (FCM) in bo projekt ustvaril pozneje. Izvedba in preverjanja te priprave se vodijo v [mejniku Firebase](FIREBASE_PREPARATION.md). Resnična dostava FCM/APNs na telefon še ni potrjena.

## Ko uporabnik ustvari projekt

1. V [Firebase konzoli](https://console.firebase.google.com/) ustvari projekt na paketu **Spark**. Za naš kanal ne potrebuje računa za obračunavanje, Cloud Functions, Firestore, Firebase Authentication ali Analytics. Analytics lahko ob ustvarjanju projekta izključi. FCM je po [uradnem ceniku](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans) brezplačna storitev; preverjeno 5. oktobra 2026.
2. Dodaj Android aplikacijo z obstoječim ID **`com.takndev.kanbanconnect`** in prenesi `google-services.json`. ID obstoječe Play aplikacije ostane enak.
3. Pred dodajanjem iOS aplikacije skupaj določimo končni bundle ID in Apple podpisno ekipo. Trenutni razvojni ID je **`com.example.kanban`**, `DEVELOPMENT_TEAM` ni nastavljen. Na Macu sta bili zaznani dve Apple ekipi; izbira ne sme biti naključna. Nato v Firebase dodaj iOS aplikacijo z izbranim ID in prenesi `GoogleService-Info.plist`.
4. Za iOS povežemo APNs ključ iz Apple Developer računa s to aplikacijo v Firebase Project settings → Cloud Messaging. Ključ `.p8`, njegov Key ID in Team ID se vnesejo neposredno v konzolo. V Xcode vključimo Push Notifications in uredimo podpisni profil za izbrano ekipo/ID. [Uradna priprava Flutter FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) opisuje APNs povezavo in platformne pogoje.
5. V FamilyHub nastavimo namensko strežniško poverilnico, šifriranje napravnih žetonov in cron. Podrobnosti so spodaj. Nato na obeh telefonih izrecno vključimo oddaljena obvestila in opravimo dejanski preizkus.

Gesel, strežniškega JSON ključa ali `.p8` ni treba pošiljati v klepet. Registracija Firebase projekta sama še ne poveže naših aplikacij in strežnika.

## Konfiguracija mobilne gradnje

Javni klientovi konfiguraciji pretvori lokalno orodje:

```sh
python3 tools/firebase/configure_client.py \
  --android /varna/lokalna/pot/google-services.json \
  --ios /varna/lokalna/pot/GoogleService-Info.plist
```

Posamezen platformni argument lahko izpustiš. Orodje preveri identifikator aplikacije ter ujemanje projekta in sender ID med platformama. Izhoda sta `.firebase/client.json` in za Android še `android/app/src/main/res/values/firebase_config.xml`. To so javni klientovi identifikatorji; strežniška storitvena poverilnica ni dovoljen vhod. Datoteke s konfiguracijo so izključene iz Gita. Natančno obnašanje in izolirani testi so v [navodilih orodja](../tools/firebase/README.md).

```sh
flutter build apk --debug --dart-define-from-file=.firebase/client.json
flutter build ios --debug --dart-define-from-file=.firebase/client.json
```

Android potrebuje tudi generirani XML: njegov sistemski sprejemnik lahko sprejme sporočilo pred zagonom Dart kode. Pri menjavi projekta je treba ponovno ustvariti oba izhoda. Gradnja brez konfiguracije ostane uporabna za local-first način, sinhronizacijo, center obvestil in lokalne opomnike; sama ne aktivira oddaljenega kanala.

Za iOS je pripravljen `ios/Runner/RemotePush.entitlements`. Vključitev v podpisano gradnjo (`CODE_SIGN_ENTITLEMENTS`) in vrednost `APNS_ENVIRONMENT` uredimo skladno z dejanskim profilom, po izbiri ekipe in bundle ID. Predloga sama ne omogoči APNs. Android/iOS uporabljata FCM; oddaljena dostava za web in namizje v tem mejniku ni vključena.

## FamilyHub in cPanel

Pošiljanje teče iz našega PHP vtičnika neposredno na FCM HTTP v1. Za cPanel ni potreben stalni proces, Docker ali Cloud Functions. Podatki, uporabniški računi, finance in trajna obvestila ostanejo pri nas. V Firebase gredo napravni dostavni žeton, generično besedilo ter reference do računa in obvestila. Naslovi opravil, finančni zneski, prijavne skrivnosti in zunanje povezave niso v sporočilu.

Za naš Firebase projekt pripravimo ločen service account z dovoljenjem za FCM pošiljanje (namenska vloga Firebase Cloud Messaging API Admin, brez splošnega Owner/Editor dostopa). FCM API mora biti omogočen. JSON zasebni ključ shranimo zunaj javne spletne mape, Kanboardovega korena in repozitorija; pot do njega ter isti projekt nastavimo samo na strežniku. Obvezni `FAMILYHUB_PUBLIC_ROOT` določi dejansko javno mapo gostovanja (npr. `/home/USER/public_html`), da jo preveri tudi cron. Pri več javnih mapah je treba lokacijo ključa preveriti za vse; konfiguracija ene mape ne dokazuje tega za vse virtualne gostitelje. Ločen naključni 32-bajtni ključ varuje shranjene napravne žetone. [Googlova navodila za FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api) pojasnjujejo avtentikacijo z omejenim OAuth žetonom.

Točne konstante, migracija, preverjanje konfiguracije brez omrežja in ukaz za cPanel cron so v [strežniških navodilih](server/README.md) in [pogodbi push](server/push-api-contract.md). Pred prvo namestitvijo naredimo novo varnostno kopijo in preverimo različico PHP, razširitvi cURL/OpenSSL ter odhodni HTTPS. Prejšnji pregled cPanela odhodnih povezav ni potrdil. Minutni cron pomeni, da dostava ni nujno takojšnja; OS in ponudnik lahko dodata zamik. Konfiguracijsko preverjanje ne dokazuje veljavnosti IAM/APNs ali dejanske dostave.

Privzeti namestitveni paket ima Native API in FCM izključena. Priprava kode ni namestitev na produkcijo. Že ponudniku sprejetega opozorila ob preklicu dostopa ni mogoče odpoklicati; vsebina se ob kliku ponovno preveri. Dvoumna potrditev ponudnika lahko povzroči ponovno telefonsko opozorilo, zato ne obljubljamo exactly-once dostave.

## Končni preizkus s pravim projektom

Uporabimo preizkusna računa in izbrani napravi:

- Android in iPhone: aplikacija v ospredju, v ozadju ter zaprta. V ospredju se osveži center brez dodatnega sistemskega opozorila. Upoštevamo tudi omejitve OS po ročni prisilni zaustavitvi aplikacije.
- Drug član dodeli opravilo oziroma doda več opravil/artiklov. Klik odpre konkretni zapis ali točen nabor v pravem računu/prostoru. Obvestilo ni dokaz zaključitve opravila.
- Preizkus dovoljenja, utišanega kanala, izklopa, rotacije žetona, odjave, menjave računa in odvzema članstva/finančnih pravic. Osebna in skupna obvestila se ne podvojijo za isti dogodek.
- Izpad povezave in ponovitev strežniškega opravila. Trajno obvestilo ostane dosegljivo neodvisno od uspeha push dostave.
- Lokalni opomnik deluje tudi brez omrežja in skupaj z vključenim FCM. Gradnja, nadomestni transport in simulator niso nadomestilo za ta fizični preizkus.

## Lokalni opomniki

Za že shranjeno opravilo ali dogodek aplikacija uporabi razporejevalnik telefona. Firebase in dosegljiv strežnik nista potrebna. Dovoljenje OS zahteva ob uporabnikovi vključitvi funkcije. Spremembe lastnih podatkov uskladijo razpored; spremembo drugega člana naprava upošteva šele, ko jo prejme.

Android uporablja razporejanje brez posebnega dovoljenja za točne alarme, zato je možen zamik. Na iOS razporedimo najbližjih 60 opomnikov. Web časovnih opomnikov ob zaprtem brskalniku nima. Dokaze za lokalni adapter vodi [družinski mejnik](FAMILY_UPGRADE.md).

## E-pošta

FamilyHub ima trajno SMTP vrsto, omejene ponovitve in preverjanje TLS. Sprejem generičnih obvestil je preizkušen z lokalnim SMTP zajemnikom; dvoumen odgovor SMTP lahko povzroči ponovno pošto. Gostovanje ima izključen PHP `mail()`, zato potrebujemo SMTP naslov, vrata, šifriranje in poverilnico samo na strežniku. Posamezni dodatki na nakupovalni seznam privzeto ne pošiljajo e-pošte. Vidnost v aplikaciji, push in e-poštna dostava imajo ločene nastavitve.

Produkcijski SMTP preizkus izvedemo z izrecno izbranim prejemnikom. Med razvojem sporočil ne pošiljamo resničnim članom. Strežniško pogodbo vodi [dokument sodelovanja](server/collaboration-api-contract.md).
