# Android: fotografije in Data safety

**12. oktober 2026 — dejanski Android osnutek je shranjen.** Za trenutno interno
**1.6.1 (24)** z Idejnikom in FamilyHub **0.13/schema17** je v Play Console
izpolnjenih vseh **11 vrst**, vključno s fotografijami. Po pregledu je bil uporabljen
»Shrani kot osnutek«; Console potrjuje »Sprememba je shranjena. Pošljite v pregled
v pregledu objavljanja.« Izjava **ni poslana v pregled ali javno objavljena**.

Spodnja presoja kode in uradnih navodil je bila podlaga za odgovore. Pred tem je
imel obrazec deset izbranih vrst brez fotografij in nedokončana vprašanja uporabe.
Zgodovinski `GOOGLE_PLAY_DECLARATIONS.md` pred odstranitvijo starega UI/AI ni popis
sedanje kandidatke. **Spletna zasebnost še ni objavljena:** prijava cPanel računa
`jivie` je potekla, uporabnik pa ni pri računalniku. Objavo nadaljujemo po prijavi;
račun `tripar13` ni nadomestilo. Apple je po uporabnikovi odločitvi odložen.

## Neposredni odgovori za fotografije

- **Photos: Collected Yes; Optional Yes; Ephemeral No.** Uporabnik izbere JPEG/PNG;
  shranjena tabla v sinhroniziranem prostoru prenese dejanske normalizirane bajte
  na njegov izbrani strežnik. Podatki se hranijo tudi po posamezni zahtevi.
- **Purpose: App functionality** (uredljive table, sinhronizacija in delo brez
  povezave) **ter Fraud prevention, security and compliance** (izrecna prijava
  table z njenimi fotografijami kot dokaz za uveljavljanje pravil).
- **Shared No za pregledane poti ob uporabi izjeme za uporabnikovo dejanje:**
  shranjevanje v izrecno izbranem deljenem prostoru, izrecni zasebni prenos in
  oddaja prijave po prikazu skrbnika/prejemnika. To ni trditev, da fotografije
  nikoli ne zapustijo naprave ali da jih strežniški upravljavec ne more brati.
  Razlog ni »self-hosted«, temveč konkretno pričakovano uporabnikovo dejanje.
- **Videos/Audio: No.** Foto izbirnik in decoder podpirata JPEG/PNG. Široka
  dovoljenja za medije/kamero niso potrebna za obstoječo izbirniško pot; njihova
  odsotnost ne pomeni odsotnosti zbiranja fotografij.

Google loči lokalno obdelavo od prenosa z naprave, zajema prenose na katerikoli
strežnik/SDK, in dopušča izjemo za pričakovano uporabnikovo deljenje. »Optional«
zahteva možnost uporabe brez zbiranja; Jivie ima lokalni način brez računa.
[Uradna razlaga Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
je znova preverjena 12. oktobra.

## Sedanja matrika

Za spodnjih **enajst** vrst je shranjeno **Collected Yes / Optional Yes /
Ephemeral No**. **Shared No** velja za opisane uporabniško začete prenose in
ustrezne dostavne obdelovalce; ni splošna izjema za vse bodoče ponudnike.
AF = App functionality, AM = Account management, SEC = Fraud prevention,
security and compliance.

| Vrsta v Console | Dejanska vsebina | Nameni |
| --- | --- | --- |
| Name | prikazno ime, imena članov in oseb; identiteta v prijavi | AF, AM, SEC |
| Email address | potrjeni naslov, povabila, varnostne kode/obnova računa | AF, AM, SEC |
| User IDs | račun, članstva, avtorstvo, identiteta prijav | AF, AM, SEC |
| Address | izrecno vpisani naslov prostora | AF |
| Contacts | ročno vpisane osebe in povezave članstva | AF; SEC za prijavljeno identiteto |
| Purchase history | evidentirani stroški/plačila/povračila; besedilo prijavljenega vnosa | AF, SEC za prijavljeno besedilo |
| Other financial info | stanja, prihodki, načrti in terjatve; besedilo prijavljenega vnosa | AF, SEC za prijavljeno besedilo |
| Calendar events | dogodki, roki in udeleženci; prijavljeni naslov/opombe dogodka | AF, SEC za prijavljeno besedilo |
| Other user-generated content | opravila, zapiski, nakupi, vrtovi, table in opis prijave | AF, SEC |
| **Photos** | normalizirane fotografije Idejnika; dokaz prijave | AF, SEC |
| Device or other IDs | napravna seja, FCM token, Firebase installation ID | AF, SEC |

SEC označuje konkretno uporabo pri pravicah/varnosti oziroma prijavah, ne
oglaševanja ali analitike. Contacts ne pomeni branja sistemskega imenika:
Googlova opredelitev vključuje tudi kontaktna imena in socialni graf/uporabniška
imena. Imena/naslovi/članstva zato niso izginili z odstranitvijo starega UI.
Za finančno/koledarsko/osebno prijavo backend izrecno ohrani omejena besedila
`title/name/notes/description`; zato SEC ni sklep samo iz prisotnosti ACL.
Finančni dokaz ne vsebuje zneskov, bankovnih identifikatorjev, povezanih računov
ali celotne plačilne mreže. Običajna raba teh podatkov ostane AF.

**Messages ostane No:** ni starega klepeta, AI transporta ali komentarnih niti.
Opis prijave je obrazec z izbranim razlogom in odprtim besedilom (Other UGC),
ne pogovor med uporabniki. Generični inbox/push in varnostna e-pošta ne pomenijo
uvoza uporabnikovih poštnih ali klepetnih vsebin.

**Files and docs ostane No za pregledano zbiranje:** JSON/.vsakdan se odpre ali
shrani prek sistemskega izbirnika; izvoz ni avtomatičen omrežni upload dokumenta
ali njegovega izvornega imena. Uvožena organizacijska vsebina je lokalno razčlenjena
in morebitna poznejša sinhronizacija zajema njene že navedene vrste. Foto bajti
sodijo v Photos. Trenutna aplikacija ne uporablja `SharePlus`/`XFile` za prenos
splošnih priponk; sama prisotnost zaklenjene odvisnosti `share_plus` ni tak tok.
Če uporabnik v sistemskem izbirniku izbere zunanji disk/ponudnika, to ni dokaz
samodejnega Jivie zbiranja celotnega dokumenta; morebitno deljenje se presoja po
konkretnem uporabnikovem dejanju.

Ni potrebe po novih Videos/Audio, Location, zdravstvenih vrstah, Crash logs,
Analytics ali oglaševanju zaradi fotografij. Slike se ponovno ustvarijo iz
dekodiranih pikslov brez vgrajenih metapodatkov; ni OCR, geolociranja ali analize
osebnih značilnosti. Evidence financ nimajo bankovnega API/posebnega polja za
številko kartice ali bančnega računa; to niso plačila prek aplikacijskega procesorja.

## Dokazi kode in dostavnih ponudnikov

- [Izbor fotografije](../../lib/organizer/presentation/ideas/idea_editor.dart#L603)
  in [izrecno Save](../../lib/organizer/presentation/ideas/idea_editor.dart#L408);
  [normalizacija](../../lib/organizer/data/idea_repository.dart#L443) odstrani
  vgrajene metapodatke, [SQLite](../../lib/organizer/data/idea_repository.dart#L372)
  ohrani bajte.
- [Fotografski upload](../../lib/organizer/data/collaboration_idea_actions.dart#L31)
  uporablja `ideas.asset.begin/chunk/complete`; [zasebna strežniška hramba](../../server/plugins/FamilyHub/Model/NativeIdeaAssetService.php#L24)
  in [prenos](../../lib/organizer/data/collaboration_idea_actions.dart#L93) sta trajna.
  [Native transport](../../lib/organizer/data/collaboration_transport.dart#L22)
  zahteva HTTPS; foto sinhronizacija ni E2EE.
- [Prijava](../../lib/organizer/data/collaboration_moderation.dart#L261)
  ima razlog/podrobnosti; [strežniški dokaz](../../server/plugins/FamilyHub/Model/NativeModerationService.php#L73)
  ohrani fotografije in [čiščenje](../../server/plugins/FamilyHub/Model/NativeModerationService.php#L103)
  podrobnosti po 180 dneh od zaključka. Odprte prijave niso kratkotrajne.
- [Osebe](../../lib/organizer/domain/household_person.dart#L4),
  [naslov prostora](../../lib/organizer/domain/local_space_models.dart#L16),
  [lokalni JSON](../../lib/organizer/presentation/backup/personal_json_export.dart#L45)
  in [izbirnik kopij](../../lib/organizer/presentation/backup/backup_file_io.dart#L19).
- `pubspec.lock` ohranja **firebase_core 4.15.0 / firebase_messaging 16.7.0**.
  [SDK meja](../../lib/organizer/platform/remote_push/firebase_push_sdk.dart#L30),
  [opt-in](../../lib/organizer/platform/remote_push/remote_push_lifecycle.dart#L243)
  in [manifest](../../android/app/src/main/AndroidManifest.xml#L9) izključujejo
  avtomatični FCM/Analytics. FCM/Firebase Installations ob vključitvi obdelujeta
  FID in tehnične metapodatke; deklaracija Device IDs zato ostane. Namen teh
  identifikatorjev je dostava/identifikacija namestitve. Ni Analytics SDK,
  Crashlytics/Performance ali klica za BigQuery delivery metrics v pregledani kodi.
  SDK provider-path se presoja ločeno kot dostavni obdelovalec, ne po foto
  izbirniški izjemi. [Aktualna uradna Firebase razkritja](https://firebase.google.com/docs/android/play-data-disclosure).
- [FCM vsebina](../../server/plugins/FamilyHub/Model/NativeFcmTransport.php#L41)
  je generična z referencami; ne prenaša fotografij, naslovov tabel ali zneskov.
  SMTP potrebuje izrecno nastavitev strežnika; naslovi/povabila/kode niso nov chat.

**Encryption in transit Yes** je utemeljen za podprti omrežni tok: vse Native
zahteve (tudi foto chunk in prijave) uporabljajo isti HTTPS transport, FCM
preverja certifikat in SMTP zahteva preverjeni SSL/TLS. HTTP izjema je omejena na
izrecni razvojni loopback, ne poljuben gostovani naslov. Izvozni sistemski
izbirnik ne spremeni tega v obljubo E2EE ali šifrirane aktivne baze. Za
independent security review ni dokazila in se ga ne označi.

## Dejanska izvedba in preostali koraki

Vseh enajst vrst ima **Collected Yes / Shared No / Optional Yes / Ephemeral No**.
Nameni so natančno navedeni v matriki zgoraj; nobena vrsta nima Analytics,
Advertising, Developer communications ali Personalization. Končni razširjeni
predogled potrdi fotografije in vseh enajst neobveznih vrst, HTTPS ter povezavi
`https://jivie.app/privacy/` in `https://jivie.app/delete-account/`. Independent
security review ni označen. Ni novega sprejema pogojev ali IARC spremembe.

Dokazi so lokalno v `build/qa/android-photos-privacy-20261012/`:
`data-safety-preview-ax.txt`, `data-safety-saved-ax.txt`,
`data-safety-saved-photos.jpg`, `play-data-safety-draft-evidence.json`,
`website-package.json` in `website-live-before.json`. Posnetek kaže fotografije,
neobveznost, oba namena in potrdilo shranjene spremembe. Nobena dejanska zasebna
fotografija ali uporabniška vsebina ni bila prenesena pri izpolnjevanju obrazca.

Pripravljen je paket **osmih HTML**
`build/releases/jivie-website-2026-10-12-photos-html.zip`, SHA256
`e175fdd8c48e38314e27ca102ffdbf271199aa8b5be5270d27b16901257ed6bc`.
Preverjeni so CRC, dovoljen seznam in bajtno ujemanje vseh osmih izvorov.
Sveži časovni žigi preprečijo ponovitev starega problema If-Modified-Since.
Paket nima `.htaccess`, PHP nastavitev, `.well-known` ali drugih datotek gostovanja.
SL/EN izvor že opisuje fotografije, prijave, hrambo ter odsotnost E2EE.

Oba javna privacy URL sta še HTTPS200 s starim besedilom 11. oktobra brez novega
odseka fotografij (hasha v `website-live-before.json`). **Objava je ustavljena pri
potekli prijavi**, brez posega v gostovanje. Po vrnitvi lastnika potrebujemo:

1. Prijavo v cPanel **jivie**, zasebno kopijo pred spremembo ter objavo preverjenih
   osmih HTML v `/home/jivie/public_html`, z ohranjenimi nastavitvami in `.well-known`.
2. HTTPS/bajtno in pogojno-cache preverjanje objavljenih SL/EN strani.
3. Ločen končni pregled in oddajo Data safety v Pregledu objavljanja. IARC in
   javna kandidatka ostaneta ločena koraka; osnutek ni javna izdaja.

Koda, Android različica **1.6.1 (24)**, istih osem dovoljenj, SDK/locks in
strežniki so nespremenjeni. Fotografije uporabljajo sistemski izbirnik brez
kamere ali širokih media/storage dovoljenj; nova gradnja za to nalogo ni potrebna.
Uporabnik je fizično potrdil popravek pan/zoom. Ni novega testnega kroga ali Apple dela.
