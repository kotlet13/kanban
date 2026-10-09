# Jivie — checklista za prvo javno izdajo

Posodobljeno: **9. oktober 2026**. Najprej zaključimo Android; Apple sledi iz istega preverjenega izvora. Aplikacija je brezplačna. Upravljano gostovanje in plačila so poznejša faza.

To je skupni seznam za nadaljevanje. `[x]` pomeni preverjeno opravljeno postavko, `[ ]` odprto delo. **Izvedba** pomeni Codex, **lastnik** tvojo odločitev/prijavo ali vnos skrivnosti, **skupaj** pa fizični preizkus oziroma končni pregled. Postavko označimo šele ob njenem dejanskem izidu; dodamo datum in povezavo do dokazila.

**Nadaljnji dogovor 9. oktobra: nova interna Android izdaja je izrecno naročena in objavljena kot 1.2.0 (14).** S tem je prejšnja ustavitev pred interno gradnjo zaključena. Fizični preizkusi, priprava javne kandidatke, oddaja v pregled in javna objava ostanejo ločeni koraki.

## 0. Dogovorjena osnova in že opravljeno

- [x] Ime **Jivie**, izdajatelj **TriparNA**, mobilni ID **`si.triparna.jivie`**; stari Kanban Connect ostane ločen.
- [x] Brezplačna osnovna aplikacija, izbirna povezava na samostojni strežnik; sedanja izdaja nima naročnin ali nakupov.
- [x] Potrjena ikona ter osnovna svetla/temna podoba, slovenska in angleška lokalizacija.
- [x] Android **1.2.0 (14)** je aktivno objavljen na internem kanalu za **domači (15)**, 9. oktobra ob 20:23. To je dokaz interne izdaje, ne prihodnje javne kandidatke. [Izdajni dnevnik](NOTIFICATION_RELEASE_RUN.md#prostori-in-povezane-finance--aktivna-12014).
- [x] Google Play: shranjeni SL/EN opisi, ikona, predstavitveni grafiki in telefonski posnetki. Pred oddajo jih primerjamo z novo kandidatko. [Priprava predstavitve](GOOGLE_PLAY_PUBLIC_PREPARATION.md).
- [x] Google Play: shranjene osnovne izjave o oglasih/oglaševalskem ID, državnih, zdravstvenih in finančnih funkcijah. Pred oddajo preverimo skladnost s končnim obsegom.
- [x] Google Play: namenski pregledni račun na testnem strežniku in angleška navodila so shranjeni; pripravljena sta njegova sintetična prostora in podatki. Normalna prijava iz nove kandidatke še potrebuje preizkus.
- [x] Google Play: shranjeno ciljno občinstvo **18+**, brez dodatne izbirne blokade prenosa za mladoletne. [Dokazi shranitve](GOOGLE_PLAY_PUBLIC_PREPARATION.md).
- [x] Lastnik je za prvo javno izdajo izbral **umik starega AI klepeta**. Izvedba umika še ni potrjena.
- [x] Apple: ustvarjena sta App ID in App Store Connect evidenca **Jivie / `si.triparna.jivie`**, ekipa **TriparNA `CXNM99632B`**, z vključeno Push Notifications capability. Aktualna podpisana kandidatka in TestFlight še nista potrjena.

Naslovi imajo različne namene:

| Naslov | Namen / stanje |
| --- | --- |
| `jivie.app` | Predstavitev, pomoč, zasebnost in pot do izbrisa. Ob zadnjem preverjanju: začetna stran 403, `/privacy/` in `/delete-account/` 404. |
| `jivie-test.triparna.si` | Delujoča ločena testna namestitev in pregledni račun za Google. Po preverjeni obnovi kopije nadgrajena na FamilyHub0.9.0/schema13; pregledni račun in podatki so ohranjeni. |
| `jivie.triparna.si` | Predvidena produkcija s prazno bazo. Poddomena/HTTPS sta pripravljena; celotna namestitev še ni potrjena. |

Pregledni račun lahko ostane na testnem strežniku. Produkcija na TriparNA ni pogoj lokalne uporabe aplikacije; za pregled pa mora delovati navedeni pregledni dostop.

## 1. Android — vsebina in tehnična priprava pred novo gradnjo

- [x] **Izvedba:** nadgradnja prostorov, financ in obnove je zaključena v dogovorjenem izvornem obsegu in preverjena za interno 1.2.0 (14): 856 Flutter PASS, ločen dejanski HTTP tok, 1554 PHP kontrol, analiza brez napak/opozoril. Omejitve in čakajoči fizični preizkus so zapisani. [Izvedba](../SPACES_UPGRADE_IMPLEMENTATION.md), [dogovorjeni načrt](../SPACES_NEXT_UPGRADE_PLAN.md).
- [ ] **Izvedba:** iz javne kandidatke odstraniti dosegljivi stari AI klepet in povezave vanj. Posebej preveriti tudi pomoč pri naslovu/opisu, projektne bližnjice in neposredne poti. Če ostane generativna funkcija, ponovno uskladiti IARC, zasebnost in zahtevane ukrepe zanjo.
- [ ] **Izvedba + lastnik:** dokončno določiti pravila deljene vsebine, tudi obseg prepovedi golote/seksualno eksplicitne vsebine. Izdelati sprejem pravil, prijavo sporne vsebine/uporabnika in obravnavo prijav; blokiranje oziroma filtriranje urediti glede na dejanske funkcije in zahteve trgovine. Samo članstvo ali odstranitev člana ni dokaz vseh teh ukrepov.
- [ ] **Izvedba:** odstraniti nepotrebna široka dovoljenja za fotografije, video, zvok in starejšo zunanjo shrambo. Preveriti sistemski izbirnik, odpiranje/prenos priponk ter kopij; ne izmišljati galerijske funkcije za obrazec. [Inventar dovoljenj](GOOGLE_PLAY_DECLARATIONS.md).
- [ ] **Izvedba:** ponovno pregledati dosegljive stare Kanboard zaslone in njihove pravice. Uskladiti, kaj javna izdaja podpira, da navodila, prikaz in pregledni račun zajamejo dejanske funkcije.
- [ ] **Izvedba:** uskladiti odjemalca in končni vtičnik, zmožnosti API, migracije in vedenje ob starejšem strežniku. Različica v izvoru ni dokaz različice na gostovanju.
- [ ] **Izvedba:** opraviti primerne regresijske teste, lokalizacijo, formatiranje in analizo; odpraviti nove napake/opozorila ter dokumentirati preostale omejitve. SDK/odvisnosti spreminjati samo z izvedbenim razlogom.

## 2. Android — spletne strani in Google Play obrazci

- [ ] **Izvedba:** uskladiti besedila spletne strani in trgovine z dejansko prvo javno kandidatko: brez starega AI, brez ponudbe še neobstoječega upravljanega gostovanja, s pravilno razlago lokalnega načina in samostojnega strežnika. Pripraviti posodobljen statični ZIP.
- [ ] **Lastnik:** objaviti paket na `jivie.app` v pravilni document root.
- [ ] **Izvedba:** preveriti javne HTTPS poti `/`, `/help/`, `/privacy/`, `/delete-account/` ter angleške različice; brez 403/404, prijavnih zidov ali opozoril o certifikatu.
- [ ] **Izvedba + lastnik:** uskladiti dejansko hrambo podatkov, dnevnike in varnostne kopije ter javno politiko. Ločiti upravljavca aplikacije, upravljavca uporabnikovega strežnika in zunanje ponudnike; ne obljubiti splošnega roka ali izbrisa vseh kopij brez podlage.
- [ ] **Izvedba:** preveriti spletno pot do izbrisa na uporabnikovem združljivem self-hosted strežniku brez ponovne namestitve aplikacije. Lokalni profil, odklop računa in dejanski strežniški izbris morajo biti jasno ločeni.
- [ ] **Izvedba:** dodati delujoči URL pravilnika o zasebnosti v Console in preveriti povezavo v aplikaciji.
- [ ] **Izvedba:** dokončno uskladiti in shraniti IARC odgovore po pregledu končne kandidatke. Trenutni **osnutek** izračuna PEGI3; to še ni potrjena končna ocena in ne nadomesti ciljnega občinstva 18+.
- [ ] **Izvedba + lastnik:** dokončati **Varnost podatkov**: konkretne vrste podatkov, zbiranje/deljenje in izjeme, nameni, izbirnost, hramba, zaščita pri prenosu ter izbris. Upoštevati tudi Firebase/SDK in vse različice v zadevnem obsegu distribucije. Local-first sam ne pomeni »nič podatkov ne zapusti naprave«.
- [ ] **Izvedba:** ponovno preveriti pregledni račun z običajno prijavo in novo aplikacijo: pravilni URL, oba testna prostora, funkcije in pravice. Navodila morajo ustrezati novim oznakam menijev. Gesla ostanejo samo v zasebnem obrazcu Console.
- [ ] **Izvedba:** uskladiti vprašanje o medijskih dovoljenjih s končnim manifestom po odstranitvi nepotrebnih dovoljenj. Ne označiti vrzeli kot odpravljene samo z odgovorom v obrazcu.
- [ ] **Izvedba + lastnik:** potrditi končne SL/EN opise, resnične posnetke novega UI, ikono, grafiko, kategorijo, kontakt, podporo in ceno0. Preveriti pravice do uporabljenih gradiv.
- [ ] **Lastnik:** potrditi države/območja distribucije ter izdajateljeve zahtevane poslovne/trader in pravne podatke v Console. Že sprejetih odločitev ne zahtevati ponovno brez spremembe pogojev.

## 3. Android — obvezni preizkusi kandidatke

- [ ] **Skupaj:** sveža namestitev brez računa in omrežja, ustvarjanje/urejanje osebnih podatkov, ponovni zagon, iskanje in prvi vodič; brez vsiljenih vzorčnih podatkov.
- [ ] **Skupaj:** uspešna sinhronizacija → trajna nedosegljivost strežnika → potek seje → ponovni zagon. Preveriti lokalno branje, urejanje in opomnike, brez izbrisa ali zaklepa upravičeno prenesene vsebine. Potrjen preklic dostopa preizkusiti ločeno.
- [ ] **Skupaj:** kopija/obnova na drugi napravi brez starega strežnika, ohranitev povezav in čakajočega dela; preveriti podprte priponke. Že prenesena datoteka mora biti dejansko lokalna, nedokončan prenos pa vidno označen.
- [ ] **Skupaj:** dve napravi in dva računa: povabilo, članstva, sočasna urejanja, izgubljen odgovor/ponovitev, konflikt, odjava/menjava računa ter preklic pravic. Preveriti tudi vrnitev istega strežnika, prazno obnovo in nadomestni strežnik.
- [ ] **Skupaj:** finančne pravice gospodinjstva/organizacije/projekta, vodstveni vpogled, ločen osebni račun, povezani stroški/plačila/povračila, brez dvojnega štetja ali razkritja drugih prostorov. Različne valute morajo ostati ločene.
- [ ] **Skupaj:** Android lokalni in oddaljeni opomniki, sprememba drugega člana, dodano proti dodeljenemu opravilu, združevanje nakupov, odložitev, preklic ter klik s zaklenjenega telefona v pravi račun/prostor/zapis.
- [ ] **Skupaj:** registracija s kodo/povabilom, potrditev e-pošte, obnova gesla, podaljševanje seje in izbris **drugega namenskega testnega računa**. Stalnega preglednega računa ne izbrisati za ta preizkus.
- [ ] **Skupaj:** Samsung S25 z odprto tipkovnico, povečavo besedila, svetlo/temno temo, sistemskim Nazaj in hitrim odpiranjem opravil; še širši telefon/tablica ter Vrt, Nakupi, koledar in Finance.

## 4. Android — nova gradnja, pregled in objava

**Interna izdaja 1.2.0 (14) je izvedena po nadaljnjem izrecnem naročilu. Javnega pregleda in javne objave s tem ne izvajamo.**

- [x] **Lastnik:** izrecno naročil novo interno gradnjo, nato commit/push. Obseg je zamrznjena nadgradnja prostorov; 317 vhodnih datotek je ponovno preverjenih pred prenosom AAB.
- [x] **Izvedba:** izvor, testi, strežniški pomočniki in usklajena dokumentacija so v commitu `47f38d7`, poslanem na `origin/codex/navigation-task-opening`. Delo drugih nalog je ohranjeno; različica 1.2.0+14 je izrecni izdajni korak. Oddaljeni SHA in vseh 317 zamrznjenih vhodnih datotek sta preverjena.
- [x] **Izvedba:** podpisani interni AAB 1.2.0 (14) z istim Jivie upload ključem; preverjeni target36/min24, 16KiB, manifest/ID, različica, nespremenjena dovoljenja, certifikat, bundletool/CRC, native knjižnice, Firebase in odsotnost zasebnih ključev. SHA256 in dokazi so v izdajnem dnevniku. Pred javno oddajo ponovno preveriti zahteve za takratno končno kandidatko.
- [x] **Izvedba:** nova interna izdaja je obdelana in aktivna za domači (15), brez spremembe podpore napravam.
- [ ] **Skupaj:** preveriti dejansko posodobitev oziroma svežo namestitev 1.2.0 (14) ter fizične preizkuse iz faze3.
- [ ] **Izvedba:** primerjati končni AAB z deklaracijami, politiko, preglednim dostopom in slikami; odpraviti odprte zahteve Console ter pregledati predzagonsko poročilo in opozorila.
- [ ] **Lastnik:** posebej potrditi oddajo za javni pregled in način objave. Oddaja v pregled in javna objava sta različna dogodka; kjer uporabimo upravljano objavo, jo nastaviti pred oddajo.
- [ ] **Izvedba:** pripraviti produkcijsko izdajo v Console, ustrezne države in SL/EN opombe ter po dovoljenju poslati v pregled. Zabeležiti dejanski status, ne samo uspešnega nalaganja AAB.
- [ ] **Izvedba + lastnik:** ob zahtevi pregledovalca dopolniti pojasnila ali kandidatko; po odobritvi ločeno potrditi javno objavo in preveriti trgovinsko povezavo, namestitev ter začetni zagon.

## 5. TriparNA produkcija in samostojno gostovanje

To je ločen operativni tok. Testni pregledni račun lahko ostane na `jivie-test.triparna.si`; samostojni uporabniki lahko uporabijo svoj združljiv strežnik.

- [ ] **Lastnik:** dokončati nova gesla/namestitev Kanboarda in predala za `jivie.triparna.si`; preveriti dejansko svežo prazno bazo. Obstoječe pripravljene obrazce in paket0.7.0 pred uporabo ponovno preveriti.
- [ ] **Izvedba:** pripraviti in preveriti paket **končnega** FamilyHub ter z njim uskladiti namestitveni pomočnik. Zasebna hramba/ključi zunaj vseh spletnih korenov, migracije in preverjanje povrnitve. [Produkcijska priprava](../server/PRODUCTION_SETUP.md).
- [ ] **Izvedba + lastnik:** urediti produkcijski SMTP, preverjanje/obnovo e-pošte, ločeno FCM identiteto, vključene crone in dejansko dostavo. Testnih skrivnosti in vrst ne kopirati.
- [ ] **Izvedba:** izdelati skladno zasebno kopijo baze/datotek/ključev in preveriti obnovo z izključeno dostavo; določiti dejansko spremljanje ter hrambo kopij.
- [ ] **Skupaj:** prvi običajni račun ustvariti prek začetne kode v pravilnem vrstnem redu, nato preveriti dve napravi, pravice, sinhronizacijo in obvestila. Testnih računov/podatkov ne prenašati v novo produkcijo.
- [ ] **Izvedba:** pripraviti javna self-hosted navodila, preverjeni namestitveni paket ter ločen javni repo **FamilyHub pod MIT**, z ohranjenimi tujimi obvestili in brez skrivnosti ali zgodovine zasebnega app repozitorija. [Javni vtičnik](../PLUGIN_OPEN_SOURCE.md).
- [ ] **Izvedba:** če se pregledni strežnik pozneje zamenja, ponovno preveriti račun in posodobiti zasebna navodila v obeh trgovinah. Naslov predstavitvene strani s tem ne postane naslov API.

## 6. Apple — priprava po Android osnovi

- [ ] **Lastnik:** obnoviti obstoječo Xcode prijavo in dostop do ekipe TriparNA; preveriti aktualne App Store Connect pogodbe, poslovne podatke in vloge. Novih certifikatov/ključev ne ustvarjati brez potrebe.
- [ ] **Izvedba:** preveriti identiteto `si.triparna.jivie`, podpisno ekipo, podprte naprave in veljavne zahteve Apple SDK. Uporabiti končni dogovorjeni izvor; namiznih identitet ne preimenovati kot stranski učinek.
- [ ] **Izvedba:** ponovno preveriti popravek zgodovinske zavrnitve **90683**: dokumentni izbirnik in dejanska raba camera/photo API. Popravljeni razvojni arhiv ali stara IPA še nista uspešna trenutna distribucija.
- [ ] **Izvedba:** pregledati privacy manifeste, required-reason API razloge, zahtevane SDK manifeste/podpise in Xcode poročilo končnega arhiva. Manifest ne nadomesti App Privacy izjave.
- [ ] **Izvedba + lastnik:** dokončati **App Privacy**, javno politiko, izbris računa in ukrepe za UGC za dejansko iOS kandidatko; preizkusiti self-hosted izbris z ločenim testnim računom. Podatkovnih odgovorov ne kopirati slepo iz Googlovega obrazca.
- [ ] **Lastnik + izvedba:** določiti Apple export-compliance klasifikacijo za AES-256-GCM/PBKDF2 in uporabljene knjižnice, države ter morebitno dokumentacijo. Ne označiti »samo OS šifriranje« ali izjeme brez podlage.
- [ ] **Izvedba + lastnik:** urediti APNs/FCM povezavo s pravilno aplikacijo in ekipo, zasebno hrambo `.p8` ter preveriti dovoljenja/entitlements. Registracija naprave in capability nista dokaz dostave.
- [ ] **Izvedba + lastnik:** pripraviti SL/EN App Store podatke, ikono, podporo, kontakte, ceno0, države ter aktualne iPhone in zahtevane iPad posnetke. Mac/visionOS razpoložljivost določiti glede na dejansko podporo/preizkuse.
- [ ] **Izvedba + lastnik:** izpolniti ločen Apple starostni vprašalnik in njegovo obravnavo dogovorjene ciljne skupine18+. PEGI3 ni Apple odgovor.
- [ ] **Izvedba:** v zasebni **App Review Information** dodati preverjeni pregledni račun, strežnik, angleška navodila in pojasnilo lokalnega načina. Normalno prijavo preveriti na iOS; pregledni backend mora biti dosegljiv tudi med pregledom.

## 7. Apple — TestFlight in javna izdaja

Tudi ta faza zahteva poznejši izrecni izdajni korak. Aktualna uspešna TestFlight distribucija še ni potrjena.

- [ ] **Izvedba:** izdelati sveži podpisani arhiv/IPA, preveriti ID, team, različico, podpis/profil, `get-task-allow=false`, minimum OS in APNs ter shraniti SHA256. Ne ponovno uporabiti stare zavrnjene ali razvojne IPA.
- [ ] **Izvedba:** naložiti v App Store Connect in počakati na **uspešno obdelavo**; rešiti morebitna opozorila/zavrnitve, export compliance in Test Information.
- [ ] **Izvedba + lastnik:** urediti TestFlight dostop. Običajnim testerjem ne širiti upravljavskih pravic ASC; za zunanje testerje urediti potrebni beta pregled. Če je kandidatka namenjena zunanjemu testiranju/trgovini, je ne omejiti z načinom Internal Only.
- [ ] **Skupaj:** dejanska TestFlight namestitev na iPhone in iPad; lokalno delo/ponovni zagon/kopija/obnova, tipkovnica in povečava, dve napravi, pravice/finance ter izbirna povezava. Pri dveh platformah preveriti tudi Android ↔ iOS sodelovanje.
- [ ] **Skupaj:** resnično lokalno in oddaljeno obvestilo na zaklenjenem iPhonu, klik v pravi zapis/račun, odjava in menjava računa. Vrt ter priponke preveriti prek pravih sistemskih izbirnikov.
- [ ] **Izvedba + lastnik:** primerjati končno IPA z metapodatki in izjavami; izbrati **Manually release this version** ter po posebni potrditvi oddati v App Review.
- [ ] **Izvedba + lastnik:** obravnavati vprašanja Apple; po odobritvi ločeno potrditi **Release This Version** in preveriti javno namestitev.

## 8. Po objavi in poznejša faza

- [ ] **Izvedba:** shraniti dejanske trgovinske povezave, status, datum, commit, različico in podpisana artefakta; posodobiti spletno stran s pravimi gumbi za namestitev.
- [ ] **Skupaj:** preveriti javno svežo namestitev, posodobitev obstoječe, pregledni dostop in podporne kontakte; zabeležiti težave prvih uporabnikov.
- [ ] **Izvedba:** določiti postopek nujnega popravka, povrnitve strežniške nadgradnje in obnove kopij; spremljanje izvajati po dogovorjenem postopku.
- [ ] **Pozneje, lastnik + izvedba:** upravljano gostovanje, cena, pogoji, hramba, vloge upravljavcev in pravila plačil trgovin. To ostaja ločeno od sedanje brezplačne izdaje.

## Dokazi za vsak izdajni korak

Ob zaključku faze dodamo: datum, izvorni commit, app različico/build number, dejansko različico strežnika, SHA256 AAB/IPA/paketa, opravljene preizkuse, povezavo do dokaza Console ter odprte omejitve. Dovoljenje za build, oddajo in objavo zabeležimo ločeno. **Gesla, bearer žetoni, podpisni ključi in APNs/service-account datoteke ne sodijo v checklisto ali Git.**

Projektne podlage: [priprava Google Play](GOOGLE_PLAY_PUBLIC_PREPARATION.md), [izvorni inventar](GOOGLE_PLAY_DECLARATIONS.md), [aktualni izdajni dnevnik](NOTIFICATION_RELEASE_RUN.md), [zgodovinski Apple dokazi](TEST_RELEASE_STATUS.md), [koraki lastnika](OWNER_NEXT_STEPS.md), [produkcija](../server/PRODUCTION_SETUP.md).

Uradne podlage, preverjene ob pripravi seznama; pred bodočo oddajo zahteve ponovno preverimo:

- Google: [dostop za pregled](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en), [izbris računa in offline izjema](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en), [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en), [target SDK](https://developer.android.com/google/play/requirements/target-sdk), [16KiB](https://developer.android.com/guide/practices/page-sizes), [omejena dovoljenja](https://support.google.com/googleplay/android-developer/answer/14115180?hl=en).
- Apple: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [SDK privacy zahteve](https://developer.apple.com/support/third-party-SDK-requirements/), [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/), [screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [ročna objava](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/).
