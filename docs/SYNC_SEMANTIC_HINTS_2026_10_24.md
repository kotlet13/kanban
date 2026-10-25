# Ločitev sprememb podatkov od potrjevanja sinhronizacije

Prvi izvedbeni korak po [pregledu poti sinhronizacije](/Users/anzenovsak/Git/kanban/docs/SYNC_PATHS_AUDIT_2026_10_24.md) je implementiran in ciljno lokalno preverjen. Novo potrjeno opazovanje prostora samo zaradi napredovanja dnevnika ne izbere več ponovne vsebinske in finančne obdelave drugih prostorov. To še ni meritev celotnega native prometa ali dokaz odprave vseh 429.

## Pogodba med strežnikom in klientom

Odgovor `account.changes` ohrani različico 1 in dobi dodatno oznako `directoryHintsVersion: 1`. Starejši klienti dodatno polje prezrejo in ohranijo svojo širšo obravnavo. Novi klient brez prepoznane oznake uporablja dosedanjo pot. Cursor ostane HMAC-overjen namig za izbiro dela, ne dokaz pravic.

Strežnik v prstnem odtisu članstva namesto `generation/head_hash` imenika uporabi `snapshot_hash`, `device_snapshot_hash` in `identity_epoch_id`. Celotni snapshot vključuje tudi keyring, zato zgolj hash naprav ne bi zadostoval. Vloge, aktivnost članstva in računa, finance grants, lifecycle in nadrejeni prostor ostanejo vključeni. Lastni account access vključuje tudi isto semantično stanje imenika.

Ločen account `directory` namig še vedno spremlja napredovanje dnevnika. Klient ga pri ozki poti preveri skozi obstoječi podpisani replay, monotono zgodovino in preverjanje aktivne naprave. Varnostno relevantna sprememba preverjenega stanja zahteva običajno preverjanje dostopa. Kadar se je spremenil samo dnevnik, njegov uspešen pregled ne zahteva novega kataloga, content pulla ali finančnega pregleda.

Vsi drugi namigi in lokalno čakajoče delo ostanejo veljavni. Kombinacije `directory + content`, `directory + inbox` ali dejanska sprememba dostopa se ne smejo zmanjšati na prazno delo. Account cursor se potrdi šele po uspešni trajni obdelavi in istem preverjanju generacije/identitete kot doslej; vedno se potrjuje cursor iz prvotnega odgovora, ne pozneje videnega stanja.

## Kaj ostane nespremenjeno

- Podpisani zahtevki, receipts, ključni material, domenski podatki, zgodovina in obstoječi pending postopki.
- Preverjanje svežih dovoljenj pred dostavo, meje kratkih bralnih kontekstov in pravila revizij.
- Opazovalni in obnovitveni cursorji ter dokazila zaključene zaščite. Pregled dnevnika ne pomeni zaključene obnove ali zaščite.
- Prva prijava in začetna priprava računa uporabljata obstoječo pot; ozki pregled ne uvaja avtomatskega dokončanja čarovnika.
- Noben nov avtomatski `directory.resume`, pošiljanje account mutacije ali podaljšanje intervala veljavnosti dokazov.
- Strežniška omejitev zahtevkov in 30-sekundni foreground urnik.

## Dogodki s spremljevalnimi učinki

Nespremenjen snapshot ne pomeni nujno odsotnosti poslovnih učinkov. Ti učinki imajo svoje namige in morajo ostati del izbire dela:

| Dogodek | Ohranjen vir spremembe |
| --- | --- |
| `scopeObserve`, `protectionReady`, `migrationAttest`, `recoveryStart` | Preverjen dnevnik in obstoječi postopki za opazovanja, zaščito ali obnovo; brez nove avtomatske poslovne mutacije v ozki poti. |
| `scheduleUse` | Spremljevalna sprememba opomnika posodobi revizijo konfiguracije inboxa. |
| `scopeDeletion` | Brisanje prostora spremeni dostopni nabor; brisanje zapisa v prostoru spremeni domenski cursor. |
| `projectRelocation` | Objava ciljnega prostora in prenesenih zapisov spremeni katalog oziroma domenske cursorje. |
| Naprave, korenski ključi, identitetna epoha, novi keyring vnosi | Spremenjeni semantični snapshot še vedno sproži preverjanje dostopa. |

Pri prvi primerjavi starega cursorja z novim prstnim odtisom je pričakovan en konzervativen pregled dostopa. Podatkov ali cursorjev zato ni treba brisati.

## Lokalno preverjanje in meje

| Sklop | Rezultat | Kaj je dejansko preverjeno |
| --- | --- | --- |
| Strežniško opazovanje in ciljne spremembe | 31 novih kontrol PASS, poskus 1 | Nespremenjen račun vrne isti cursor; podpisani dogodki brez spremembe snapshota izberejo directory; task counter skupaj z observation izbere samo prizadeto content domeno; spremljevalni inbox/access namigi ostanejo. |
| Strežniška varnost in združljivost | 15 novih kontrol PASS, poskus 1 | Podpisana sprememba naprave in keyringa, revoke, aktivnost članstva, izolacija zasebnega prostora, nadrejene pravice, stari cursor in ohranjeni bajti zgodovine. |
| Klientov podpisani dnevnik in izbira dela | 3 novi scenariji PASS, poskus 3 | Pravi Sodium podpisi in obstoječi reducer/router: observation trajno preverjen brez full synca, naslednji idle samo probe; task hint prenese le prizadeto vsebino; pravilno podpisan odvzem trenutne naprave zavrne delo brez ACK. Pending account request ostane nespremenjen. |
| Klientova varovala | 4 novi scenariji PASS | Neveljaven podpis ne spremeni anchorja ali account cursorja; sočasna invalidacija ne izgubi novega pregleda; manjkajoča/prihodnja oznaka ohrani legacy katalog; omejena diagnostika in napaka njenega opazovalca ne vplivata na sync. Dva scenarija PASS v poskusu 1, druga dva v ciljnem poskusu 2. |

Prva dva poskusa treh klientovih scenarijev sta odpovedala zaradi fixture: nenamernega vključevanja širšega crypto adapterja med legacy pripravo in manjkajočega genesis anchorja. Popravljena je bila priprava testa, ne dodatna runtime varovala. Pri guard sklopu sta bili popravljeni nullable testna poizvedba po pravilni odstranitvi cursorja ter napačna testna predpostavka, da stari account directory hint sam izbere vse content domene. Uspešni primeri niso bili ponovno zagnani; ni četrtega poskusa.

Strežniška testa uporabljata izolirano SQLite v pomnilniku, v odstranljivih Docker vsebnikih brez omrežja in z read-only izvorom. Uporabljata dejansko avtorizacijo, Ed25519 preverjanje, reducer in append imenika. Task zapis in del lifecycle učinkov sta izrecno testirana prek transakcije metapodatkov/cursorjev; to ni polni `records.batch` ali migracijski protokol. Klient preveri resnično podpisano verigo; poslovni prenos opravila uporablja sintetični legacy transport. Zato teh rezultatov ne štejemo kot celovit E2EE prenos opravila med native aplikacijama.

PHP syntax preverjanje petih ciljnih datotek je uspelo. Klientova ciljana analiza nima napak ali opozoril; izpiše 20 slogovnih informacij. Ločeno je test z dvema fixture računoma izpisal Drift debug opozorilo o več instancah baze; obe sta uporabljali ločena pomnilniška executorja, ne iste datoteke ali executorja. Neodvisni izvorni pregled ni našel blokatorja.

Stari native rate-limit scenarij ostane STOP3 in ni bil ponovljen. Prav tako nismo ponavljali uspešnih starih povabil, grantov ali prenosov. Ena prejšnja strežniška testna trditev o prvi vzpostavitvi imenika je v izvoru usklajena z novim pričakovanim `directory + access`; stara zbirka ni ponovno zagnana.

Dokazi: [strežniški rezultati](/Users/anzenovsak/Git/kanban/build/qa/sync-semantic-hints-20261024/server/summary.json), [klientovi rezultati](/Users/anzenovsak/Git/kanban/build/qa/sync-semantic-hints-20261024/client/summary.json).

## Diagnostika in implementacijska mesta

Dodana diagnostika je izbirna in hrani največ 64 dogodkov v pomnilniku. Beleži probe, razlikovanje preverjenega dnevnika od semantične spremembe, začetno izbiro domen, širši obnovitveni prehod ter potrditev ali invalidacijo cursorja. Polja so omejena na enum in števce, brez imen, ID-jev, gesel, tokenov, cursorjev, podpisov ali vsebine. Ne zapisuje datotek samodejno in ne nadomešča prihodnjega HTTP traca za celoten problem zahtevkov.

- [Strežniški semantični prstni odtisi](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:124).
- [Razlikovanje hintov na klientu](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_account_changes.dart:14).
- [Preverjanje podpisanega dnevnika](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_account_directory_changes.dart:5).
- [Izbira dela in potrditev cursorja](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:248).
- [Omejena diagnostika](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_diagnostics.dart:31).
- [Novi klientovi scenariji](/Users/anzenovsak/Git/kanban/test/organizer/data/e2ee/account_directory_change_lane_test.dart).

Telefoni, produkcija, obstoječi testni strežniki in aplikacije ostanejo nedotaknjeni. Gre za prvi korak; poenotenje vseh workflowov v koordinator in dodatna prenova zaslonov sta ločeni naslednji fazi.
