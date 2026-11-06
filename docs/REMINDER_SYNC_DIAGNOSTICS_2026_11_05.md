# Opomniki in diagnostika sinhronizacije — 5. november 2026

## Obseg in uporabnikovo opažanje

Uporabnik je pri svojem opravilu, za katero je zadolžena druga oseba, prek
zvončka nastavil opomnik. Opomnik je prejel samo ustvarjalec opomnika. Želi, da
ga prejmeta ustvarjalec opomnika in zadolžena oseba. Ob tem je posredoval
diagnostiko `version:1`, `stage:unknown`,
`reason:crypto_reconciliation_required`, prikazano število čakajočih zahtev pa
je bilo nič. Naknadno je izrecno pojasnil, da uporablja zadnjo izdajo z Google
Play, da je izbral **določen datum in čas**, ter da se je napaka pojavila
**po prejemu push obvestila, ko ga je tapnil in se je odprla aplikacija**.
Natančna nameščena številka različice ni preverjena. To usmeri nadaljnjo
reprodukcijo na absolutni opomnik in odpiranje iz push obvestila; spodnja
ugotovitev o relativnem opomniku ostaja ločen lokalni izid.

Dogovorjeni obseg je pregled in lokalna reprodukcija. Ta zapis ne predstavlja
izvedenega produktnega popravka, nove politike prejemnikov, izdaje ali dokaza o
vzroku na uporabnikovem telefonu. Produkcija in telefoni niso bili spremenjeni.

## Prejemniki: trenutno vedenje iz kode

Oddaljeni ročni opomnik trenutno pripada prijavljenemu računu, ki ga ustvari.
`lib/organizer/presentation/inbox/remote_reminder_editor.dart` to izrecno navaja
v komentarju, `remoteReminderDescription` v `lib/l10n/app_sl.arb` in
`app_en.arb` pa isto pove uporabniku. Dodelitev opravila drugi osebi ni izbor
prejemnika ročnega opomnika.

Tok je `RemoteReminderButton` → dialog →
`CollaborationController.putReminder` →
`CollaborationRepository.putReminder`. Repozitorij atomarno shrani en lokalni
`scheduled_reminders` zapis in en nespremenljiv ukaz `reminders.put` v particiji
trenutnega računa. Parametri nimajo seznama prejemnikov. Kontroler po uspešnem
lokalnem zapisu zahteva avtomatsko sinhronizacijo.

`lib/organizer/data/e2ee/crypto_business_notifications.dart` preveri cilj, doda
njegovo identiteto in potrebne podpisane dokaze ter uporabi en
`crypto2.reminders.put`. Strežniški
`server/plugins/FamilyHub/Model/NativeCryptoNotificationV2.php` v zapis shrani
`actor['user']['account_id']`; `runDue` ustvari inbox dogodek za ta isti račun.
Seznam opomnikov je prav tako filtriran po trenutnem računu.

Napraven gumb `LocalTaskReminderButton` za nepovezane podatke spremeni samo
lokalni odmik opomnika. Pri povezanem osebnem prostoru preusmeri v oddaljeni
gumb. Samodejni lokalni opomniki iz vidnih podatkov so drug tok;
`organizer_projections.dart` izrecni strežniški opomnik izloči iz lokalnega
samodejnega načrta istega cilja, da se ne podvoji.

Želeno vedenje »ustvarjalec opomnika + zadolžena oseba« v tej nalogi ni
implementirano. Trenutno pravilo je potrjeno z branjem odjemalca in strežnika;
lokalni HTTP scenarij spodaj uporablja en račun, brez druge dodeljene osebe,
zato ne predstavlja runtime preizkusa dveh prejemnikov.

## `unknown`: ločena lokalna reprodukcija prikaza

`version:1` je različica varnega diagnostičnega JSON v
`lib/organizer/domain/sync_failure_details.dart`, ne različica sync protokola.
`sharingSyncFailures` v
`lib/organizer/presentation/shared/sync_failure_panel.dart` ustvari
`stage:unknown` brez časa, kadar ima na voljo samo povzetek `lastError` ali
ločen `collaborationBackgroundErrorProvider`, brez ustreznih podrobnosti faze.

Novi test
`test/organizer/state/reminder_background_diagnostic_20261105_test.dart`
uporablja pravi `CollaborationRepository`, pravi Riverpod kontroler, SQLite v
pomnilniku ter dejanska `sharingSyncFailures` in izvoz JSON. Sintetičen
transport enkrat vrže `crypto_reconciliation_required` pri `account.changes`.
Ta začetni razlog je namenoma vbrizgan: test ne ugotavlja njegovega
kriptografskega vzroka.

Dejansko preverjeno zaporedje:

1. Prva neuspešna zahteva shrani podrobnost `accountCheck` s časom in napako v
   background provider.
2. Naslednji ročni uspešen `unchanged` probe očisti repozitorijev `lastError`
   ter podrobnosti prejšnjega probe. Ne ustvari novega full-sync completion.
3. Ročni `CollaborationController.syncNow` background napako posodobi le ob
   novem completion ali vrženi napaki. Stari background razlog zato ostane.
   Dejanski izvoz tedaj vsebuje samo
   `{"version":1,"syncFailures":[{"stage":"unknown","reason":"crypto_reconciliation_required"}]}`.
4. Naslednji avtomatski uspešen `unchanged` probe ima dodatno čiščenje pri
   odsotnem `lastError`; stari background razlog izgine.

Rezultat je **1 nov test PASS, prvi tek**, dokaz
`build/qa/reminder-sync-20261105/background-diagnostic-r1.log`. Ciljna analiza
novega testa je bila brez težav. To je reprodukcija poti prikaza zastarele
napake, ne dokaz, da je uporabnikova slika nastala po tej poti.

Med novim polnim poskusom obstaja tudi prehoden interval: repo že očisti
ponovno preverjane podrobnosti, stari background razlog pa ostane do rezultata
poskusa. Uspešen polni completion ga očisti. Samo odprtje dialoga ali prihod
časa opomnika v odjemalcu ne zapiše nove background napake.

## Lokalni HTTP scenarij na zasebnem klonu

Preizkus uporablja ločeno kopijo ohranjene lokalne HTTP namestitve iz
password-flow scenarija, z istim ohranjenim računom, sejo in kriptografskim
materialom znotraj kopije. Izvirna namestitev ni bila spremenjena. Identitete,
ključi, recovery datoteka, baze in poslovna vsebina niso prepisani v ta dokument.

Novi scenarij je
`test/organizer/data/e2ee/reminder_sync_diagnostic_20261105_test.dart`.
Dokazi so v `build/qa/reminder-sync-20261105/`; občutljivi podatki ostajajo v
zasebnem podimeniku. Vsaka spodnja faza je bila izvedena enkrat, na nadaljevanju
istega stanja kopije.

| Faza | HTTP zahtev | Opaženi izid |
| --- | ---: | --- |
| `discovery` | 9 | Brez nerešenega sync stanja. |
| `create_task` | 41 | Novo opravilo ustvarjeno in usklajeno. |
| `create_absolute` | 50 | Absolutni opomnik shranjen in usklajen. |
| `create_relative` | 20 | Nerešeno stanje; faza `notifications`, razlog `scheduling_consent_generation_pending`. |
| `sync_after_delivery` | 20 | Nerešeno stanje; isti predhodni relativni ukaz ustavi pot pri istem razlogu. |

Uspešen izhod diagnostičnega testa v zadnjih dveh fazah pomeni, da se je
zajem opaženega nerešenega stanja zaključil. **Ne pomeni uspešne
sinhronizacije.** Že uspešnih faz nismo ponavljali.

## Konkretni vzrok blokade relativnega opomnika v tem klonu

Novo opravilo ima preverjen podpisani zapis revizije 1, vendar v podpisanem
`reminderState` nima `consentGeneration`. Običajni zapisovalec
`CryptoBusinessSession._reminderState` v `crypto_business_router.dart` pokliče
`CryptoConsentGeneration.transition`. Ta v
`crypto_consent_generation.dart` ohrani ali zamenja že prisotno generacijo,
zaradi združljivosti pa sprejme tudi stare zapise brez nje. Pri svežem navadnem
zapisu je ne ustvari. Posebna pot `mintCanonical` za migracijsko dokazilo je
ločena.

`CryptoSchedulingUse.relative` v `crypto_scheduling_use.dart` zahteva odprt
cilj in veljaven UUID `consentGeneration`. Na dejansko preverjenem novem
opravilu ta pogoj ni izpolnjen; vrže
`CryptoAuthorityPending('scheduling_consent_generation_pending')`. Opažena
podrobna faza je `notifications`, globalni povzetek pa
`crypto_reconciliation_required`.

Relativni `crypto2.reminders.put` ni bil poslan. Lokalni ukaz ostane čakajoč,
opomnik pa `queued`; varovalo ni bilo obito in ni bilo lažnega ACK. V istem
stanju je prikazani števec sync ukazov nič, ker zajema ožji nabor kot celotna
lokalna čakalna vrsta. Nič na tem števcu torej ni dokaz odsotnosti čakajočega
ročnega opomnika.

Hipoteza o zastarelem account directory pri relativnem opomniku ni dosežena:
izvajanje se ustavi že na manjkajoči generaciji. Ta hipoteza ostaja
nepotrjena. Preverjanje na telefonu oziroma enačenje tega lokalnega razloga z
uporabnikovim dejanskim razlogom ni bilo opravljeno.

## Enkratni lokalni due worker in naslednji sync

Strežniški `runDue` je bil nad absolutnim opomnikom izveden **enkrat**:
`examined=1`, `delivered=1`, `cancelled=0`; preverjen je natanko en pripadajoči
inbox dogodek. `externalDeliveryAttempted=false`: ni bilo prave dostave FCM,
SMTP ali dejanja na telefonu. Dokaz je `due-worker-r1.log`.

Ločena nova faza `sync_after_delivery` je izvedla en `crypto2.inbox.sync`,
nato obstala na že prej čakajočem relativnem ukazu z razlogom
`scheduling_consent_generation_pending`, še pred `reminders.list`. Zato
odjemalčeva projekcija absolutnega opomnika ostane `pending`, revizija 1,
čeprav je strežniški inbox dogodek že ustvarjen. **Absolutna dostava ni
povzročila te blokade**; relativni ukaz je obstajal pred njo. Ta faza je nov
preizkus po dogodku, ne ponovitev že uspešne faze.

## Dopolnitev: čista veja absolutnega opomnika in tap na push

Po uporabnikovi pojasnitvi je pripravljena ločena veja `absolute-tap` iz
nespremenjenega izvirnika lokalne HTTP namestitve. Uporablja isti ohranjeni
račun, podatke in ključe. Prejšnji klon z blokiranim relativnim ukazom ostaja
ohranjen in njegov strežnik ustavljen; relativni ukaz ni prenesen v novo vejo.
Ni bilo novega uporabnika, ponastavitve ali ponovitve že uspešnih starih faz.

Izvirnik v preživelih prostorih ni imel opravila, uporabnega za ta scenarij.
Zato je nova priprava ustvarila eno novo opravilo in en absolutni opomnik z
določenim datumom in časom. Nova faza `prepare_existing_absolute_tap` je v
prvem teku končala brez nerešenega sync stanja, z **69 HTTP zahtevami**. Novi
harness je ciljno analiziran brez ugotovitev.

Po naravnem čakanju na nastavljeni čas (približno 90 sekund) je bil lokalni
due worker v tej veji izveden enkrat. Potrdil je natanko eno dostavo v inbox,
brez zunanje dostave; dokaz je `absolute-tap-due-worker-r1.log`.

Nova faza `open_existing_absolute_push` je v prvem teku dejansko poklicala
produkcijsko metodo `CollaborationRepository.openRemotePushReference` z
dejanskim ID-jem dostavljenega inbox dogodka. Native/FCM referenca je bila
sintetična. Opravljenih je bilo **39 HTTP zahtev**, med njimi en
`crypto2.inbox.group`, en `crypto2.inbox.open` ter običajna notranja
sinhronizacija. Rezultat poti je bil `available`; cilj se je ujemal z
ustvarjenim opravilom in inbox dogodkom. Globalne napake ni bilo pred klicem ali po njem,
`syncFailures` je bil prazen, navadnih čakajočih ukazov in aktivnih crypto
ukazov pa je bilo pred klicem in po njem nič. Lokalni in strežniški opomnik
sta imela stanje `delivered`, revizija 1. Dokaz je
`open_existing_absolute_push-r1.log` s pripadajočim zasebnim povzetkom.

**Pojasnjena uporabnikova napaka po tapu na absolutno push obvestilo v tej
lokalni HTTP veji ni bila reproducirana.** Preverjena sta pravi repozitorijski
handler in HTTP pot enega računa; prava dostava FCM, native cold-start,
Firebase callback, telefonski UI in dodelitev drugemu uporabniku niso bili
izvedeni. Uspeh zato ni dokaz celotne native poti na uporabnikovi napravi.
Priprava in odpiranje sta dve novi ločeni fazi, vsaka izvedena enkrat;
prejšnji relativni klon ni bil ponastavljen ali ponovno preizkušen.

Pravi push referenčni podatki iz `NativeFcmTransport::message` so
`type:familyhub.inbox.v1`, `serverId`, `accountId` in niz `notificationId`.
Firebase `onMessageOpenedApp` oziroma `getInitialMessage` jih pošlje prek
`RemotePushLifecycle` v `remotePushLaunchReferenceProvider`. Pri Android
display2 lahko lokalni prikaz obvestila posreduje ovoj
`familyhub.system.v2` z isto referenco ter zastavico `summary`.

`OrganizerShell._processRemoteReference` posamezni klik preda kontrolerjevi
metodi `openRemotePushReference`, ki samo delegira repozitoriju. Repozitorij
opravi `inbox.group`, **računski `syncNow()`**, nato
`openNotificationTarget` in `inbox.open`. Šifrirni adapter cilj prebere samo
prek `pullVerified` ter preverjene lokalne projekcije. Sam neposreden
`inbox.open` zato ne nadomesti celotnega click handlerja. Tap na skupinski
povzetek ima drugo pot: odpre center obvestil in zahteva sinhronizacijo.

Notranja sinhronizacija ob kliku lahko objavi globalno napako prek
completion listenerja, tudi kadar se cilj pozneje uspešno odpre. To je možnost
iz kode; v novi čisti veji globalne napake ni bilo. Napaka relativnega opomnika iz
prejšnjega klona in reproducirani zastareli prikaz `unknown` **nista potrjen
vzrok uporabnikove napake po tapu na absolutno push obvestilo**.

## Meje in nadaljevanje

Ni produktnega popravka, novih prejemnikov, gradnje aplikacije ali objave Play. Ni bilo
posega v produkcijo, uporabnikove podatke ali telefone. Ohranjenega izvirnega
lokalnega password-flow okolja nismo ponastavili. Kriptografskih varoval,
podpisanih zahtev in dokazil nismo zaobšli ali spreminjali zaradi uspešnega
rezultata.

Lokalno so ločeni trije izidi: reproduciran zastarel UI prikaz po ročnem
`unchanged` probe, dejanska HTTP blokada relativnega opomnika na novem zapisu
brez začetne consent generacije in uspešna čista HTTP pot odpiranja
dostavljenega absolutnega opomnika. Zadnja ni reproducirala uporabnikove
napake; dejanski telefonski vzrok ostaja neznan. Vedenje dveh prejemnikov je
pojasnjeno iz kode, želeni novi produktni dogovor pa ostaja neizveden.

## Končno preverjanje in ohranitev

Neodvisni pregled odjemalca in strežnika je potrdil razliko med novim zapisom
in podedovanim zapisom brez generacije. Obstoječa zaščita starih podpisanih
zapisov ostaja potrebna; popravek ne sme tiho prepisati njihove zgodovine.
`signed-target-evidence.json` poveže preverjeno revizijo 1 s točno podpisano
vsebino prek hasha, brez kopiranja vsebine ali ključev v javno dokumentacijo.

`preservation-and-queue-evidence.json` potrdi vseh osem izvirnih kopiranih
datotek z nespremenjenimi SHA-256; med njimi sta izvirni klientova in strežniška
baza, seja, ključi ter recovery datoteka. V prvem relativnem klonu ostaja en navaden čakajoč
`commands/reminders.put`; strežniškega relativnega opomnika ni. Absolutni
opomnik ima na strežniku stanje `delivered`; strežnik in odjemalec imata vsak
en inbox zapis. Push registracij in push opravil je nič. Dokazi ter klon so
ohranjeni za nadaljevanje, namenski strežnik pa po pregledu ustavljen.

`absolute-tap-final-evidence.json` ločeno potrdi tudi ustavitev drugega
namenskega strežnika in nespremenjene izvirne datoteke. V čisti veji je
navadna vrsta ukazov prazna, absolutni opomnik dostavljen in inbox po en na
strežniku ter odjemalcu; push registracij in push opravil je nič. Obe kopiji
in vsi dokazi ostanejo ohranjeni. Razširjeni tap harness ima še ločeno ciljno
analizo brez ugotovitev v `tap-test-analyze-r1.log`.

Oba nova testna izvora sta formatirana. Ciljni `flutter analyze --no-pub`:
prvi tek eno opozorilo zaradi nepotrebnega `!` v novem HTTP harnessu;
po odstranitvi drugi tek brez ugotovitev. Funkcionalnih uspešnih faz nismo
ponovili. Predhodne nepovezane lokalne spremembe so ohranjene; produktne
datoteke, različica, odvisnosti in strežniška shema niso spremenjene.

Lokalni Docker je bilo treba zagnati in ponovno pripraviti testno sliko.
Prva gradnja starega testnega Dockerfile ni uspela, ker paket
`php84-sodium=8.4.26-r0` ni bil več v repozitoriju. Samo zasebni diagnostični
Dockerfile uporablja razpoložljivi `8.4.27-r0`; druga gradnja je uspela.
Kanboardov osnovni digest je ohranjen; dejanski CLI je PHP 8.4.24 s sodium in
SQLite. To ni preverjanje identičnega produkcijskega okolja. Namenski
strežnik uporablja PHP built-in HTTP, samo loopback vrata, brez crona in
dostavnih delavcev. Notranje omrežje samo ni omogočilo objavljenih vrat,
zato je namenski vsebnik dobil še bridge povezavo. Izvor in rootfs sta samo
za branje. Pripravljalni varovali preslikave ID-ja in kopiranja PHP helperja
v read-only rootfs sta ustavili helper pred izvedbo; končni helper je tekel
prek standardnega vhoda. `runDue` je bil izveden enkrat v prvem klonu in
enkrat v ločeni čisti veji absolutnega tapa, vsakič nad svojim enim novim
opomnikom, brez premikanja rokov ali umetne potrditve dostave.
