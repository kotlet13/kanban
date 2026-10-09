# Izbris računa — FamilyHub 0.9.0, Native v1, schema13

Izvedba za **samostojno gostovanje** (self-hosted). Osnovna politika 1 iz FamilyHub 0.6.0/schema 10 je bila preverjena 7. oktobra 2026 v izoliranih bazah; 0.7.0/schema 11 doda politiko 2 za organizacije, korenske projekte, osebe in neznano začetno finančno stanje. Dokument je usklajen z izvorom 8. oktobra; aktualne lokalne dokaze vodi [izvedbeni dnevnik](../UPGRADE_IMPLEMENTATION.md). Izdajatelj Jivie je TriparNA. To ni dokaz skladnosti z Apple/Google ali splošnega izbrisa vseh vsebin; spodaj so konkretne meje. Izvor in lokalni HTTP testi ne dokazujejo namestitve 0.7.0 na gostovanju; upravljano gostovanje ni vključeno.

## Omogočanje in transport

Upravljavec nastavi obe vrednosti v zasebnem Kanboard `config.php`:

```php
define('FAMILYHUB_ENABLE_NATIVE_API', true);
define('FAMILYHUB_ACCOUNT_MODE', 'self_hosted');
```

Brez izrecnega `self_hosted` (tudi pri `managed`) je `features.accountDeletion=false`, vsi `account.deletion.*` klici pa vrnejo `503 feature_disabled`. Odjemalčev flag tega ne more obiti. Namestitveni paket ohranja Native API privzeto izključen. Trenutno podprt datotečni backend je Kanboardov lokalni `FileStorage`; druge shrambe in tretji vtičniki zahtevajo ločen pregled.

Obstoječi Native endpoint, envelope, HTTPS, preverjeni proxy in `no-store` ostanejo. Geslo, OTP in receipt token nikoli niso v URL ali dnevnikih. Preview/confirm uporabljata trenutno napravo, samo njen račun. IP budget120/min; account preview60/min, confirm10/15min in cancel-write10/15min, failed-password counters in TOTP replay prevention ostanejo trajni.

## Pogodba

- `account.deletion.preview {policyVersion?:1|2|3}` → `{serverId,accountId,policyVersion:1|2|3,previewHash,canDelete,blockers,impact,sharedScopes,ownedScopes,resolutions}`. Privzeto klient razume politiko 1; za graf, ki potrebuje 2, dobi `409 client_upgrade_required` namesto tihega preskoka novih odločitev.
- `account.deletion.confirm {operationId:UUID,receiptToken:64lowercaseHex,previewHash:64lowercaseHex,password,otp?,confirmation:'DELETE',policyVersion?:1|2|3,ownershipTransfers?:[{scopeId,successorAccountId}],ownedScopeDeletions?:[scopeId],resolutions?:[{scopeId,recordId,action:'preserveStructure'|'detachOrganization'}]}` → `{deleted:bool,cleanupPending:bool,serverId}`.
- `account.deletion.cancelPending {operationId,receiptToken}` → `{deleted,cleanupPending,cancelled,serverId}`. Če receipt še ne obstaja, zahteva aktualni bearer izvirnega računa in account budget, nato pod istim global lockom atomarno zapiše terminalni cancelled marker. Pozni confirm te operacije dobi `409 deletion_cancelled` in računa ne odstrani. Če je original že potrjen, matching receiptToken brez bearerja vrne njegov dejanski izid. Drug token obstoječega markerja ne prepiše (`idempotency_mismatch`).
- `account.deletion.status {operationId,receiptToken}` → `{deleted,cleanupPending,cancelled,serverId}`. Javno, brez bearerja; napačen/neznan token vrne `deleted:false,cleanupPending:false`, brez identitete ali druge vsebine.

Odjemalec **pred** confirm ustvari operationId in naključni32-byte receiptToken ter zasebno shrani nespremenljiv pregled in izbire. Receipt token samo preveri izid te operacije; ne ustvari seje, ne bere podatkov in ne omogoči izbrisa drugega računa. Shramba vsebuje SHA256 tokena, operationId, čas in oznako dokončanosti, brez username/accountId/userId ali telesa zahtevka. Pri izgubljenem ACK odjemalec najprej preveri status. `deleted:false,cleanupPending:false,cancelled:false` ni dokaz zavrnitve zahteve, ki morda še teče. Za varno nov pregled je treba atomarno zaključiti negotovost s `cancelPending`; samo potrjeni `cancelled:true` odklene novo operacijo. Po odjavi/menjavi računa se za nov marker ponovno prijavi izvirni račun; nikoli ne uporabi bearerja drugega računa. Existing matching receipt ostane dosegljiv brez seje. Ponovitev uporablja iste ID/hash/izbire in sveže geslo/TOTP; stale/blocked zahteva nov pregled. Po izbrisu stari bearer ni uporaben za noben Native klic.

`deleted:true` pomeni izbris SQL računa in uspešno čiščenje evidentiranih datotek. `cleanupPending:true` pomeni SQL račun že odstranjen, datoteke še čakajo v trajni vrsti; ni poziv za novo prijavo ali ponoven confirm. Status ponovi čiščenje. Napaka datotečnih pravic ostane pending; upravljavec mora zasebno preveriti shrambo/pravice in zagnati spodnji cron. Sistem takšnega stanja ne predstavlja kot uspešno zaključen izbris.

`ownedScopes = [{id,kind,name,canDeleteScope,eligibleSuccessors:[{accountId,displayName}]}]`. Lastnik prenese skupni prostor na izbranega aktivnega člana; successor postane owner, račun zapusti prostor. Prenos lastništva vključuje upravljanje tega prostora; ne ustvari se ali podeduje dostop do drugega prostora. Če ni tujih članov oziroma živih tujih podatkov, `canDeleteScope=true` omogoči ločeno izrecno izbiro `ownedScopeDeletions`; ni tihega izbrisa skupnega prostora. Payloadless tombstones in že očiščene sistemske strukture ne ujamejo zadnjega člana v trajno blokado.

`resolutions = [{scopeId,recordId,type:'shoppingList'|'financeAccount'|'project'|'householdPerson'|'organizationProjectLink',action:'preserveStructure'|'detachOrganization',name:string|null,currency?:string,openingBalanceMinor?:int|null,childScopeId?:UUID|null}]`. `recordId` je **opaque potrditveni UUID**, ne ID finančnega zapisa; uporabi natanko prejeto vrednost. Po izgubi trenutnih pravic so ime in finančna polja skrita, tudi scopeId izbire postane opaque. Zneska/valute ne razkrivamo brez trenutne finance-read pravice. Izbira mora biti izrecna za vsak objekt. Neoznačena struktura z vsebino drugih blokira confirm.

`canDelete=false` vključuje tudi rešljiv izbor naslednika/ohranitve strukture; confirm lahko uspe, ko vsebuje vse veljavne izbire. Blokade so `{code,count,scopeId?}`: `last_admin`, `shared_scope_owner`, `shared_structure_resolution`, `shared_scope_without_successor`, `personal_scope_has_other_member`, `legacy_shared_private_project`, `legacy_task_has_other_contributions`. Zadnji aktivni Kanboard skrbnik mora prej imenovati drugega. Skupni prostor brez živega naslednika in s tujo zgodovinsko vsebino potrebuje ponovno vključitev ustreznega člana oziroma ločeno razrešitev; njegovo brisanje ni avtomatski stranski učinek. Legacy blokade so opisane spodaj.

Napake: `409 deletion_blocked` z aktualnimi blokadami, `409 deletion_preview_stale`, `409 client_upgrade_required`, `409 idempotency_mismatch/deletion_cancelled`, `401 invalid_credentials/two_factor_required/device_revoked`, običajni `422 validation_error`, `429 rate_limited`. Po redakciji zgodovinskega replay odgovora lahko stara sync/finance zahteva vrne `409 operation_redacted`; njen ID in request hash ostaneta in zahteva se ne izvede znova.

`impact` vsebuje integer števce: `personalScopes`, `personalRecords`, `personalFinanceRecords`, `devices`, `sharedMemberships`, `kanboardAssignedTasks`, `kanboardAssignedSubtasks`, `sharedRecordsDeleted`, `sharedRecordsUpdated`, `sharedFinanceRecordsDeleted`, `sharedFinanceRecordsUpdated`, `kanboardTasksDeleted`, `kanboardCommentsDeleted`, `kanboardFilesDeleted`, `organizationProjectsDetached`. Shared številke vključujejo samo trenutno vidno vsebino; po izgubi finance pravice niso popoln inventar financ. `sharedScopes` vsebuje samo trenutno vidne obsege. PreviewHash zajame dejanski povezan graf, pravice/članstva in credential fingerprint; nepovezan prostor drugega uporabnika ne povzroči lažnega stale pregleda.

## Kaj se odstrani in kaj ostane

| Podatki | Izvedeno vedenje |
| --- | --- |
| Kanboard `users`, geslo, osebni API/public token, FamilyHub account in naprave | Dejanski DELETE, ne deaktivacija. Vsi bearerji prenehajo veljati. Kanboard web/remember-me/reset/login/profile evidence za uporabnika se odstrani; odprta web prijava je ob naslednji zahtevi zavrnjena. |
| Osebni FamilyHub prostor | Vsi generic/finance zapisi, tombstones, audit/replay, članstva, grants, inbox/opomniki in odhodne vrste; prostor se odstrani. |
| Skupni generic zapisi, `created_by` je izbrisani račun | Tombstone z novimi revision/sequence, `payload=NULL`, brez osebne atribucije. Projekti brez ohranjenega korena odvežejo `projectId` in phaseId tujih task/event otrok; drugi otroci ohranijo lastno poslovno vsebino. |
| Lastni shared shoppingList s tujimi živimi artikli | Samo po `preserveStructure`: generičen naslov `Shared shopping list`, sistemska atribucija in isti ID za tuje artikle. Lastni artikli se odstranijo. Stari osebni naslov izgine tudi iz replay kopij. |
| Lastni korenski project v projektnem scope | Politika 2 in izrecni `preserveStructure`: isti ID in fazni ID-ji ostanejo za druge člane; naslov postane `Shared project`, description/milestone se očistijo, phase title postane `Shared phase`, razpoložljivost null. Tudi scope name sledi očiščenemu naslovu. Koren se ne pretvori v izbrisan zapis, na katerega kažejo tuja opravila. |
| Lastni householdPerson s tujimi živimi task/finance referencami | Politika 2 in `preserveStructure`: isti profilni ID, ime `Shared person`, prazni notes, archived=true in sistemska atribucija. Profil ni Kanboard račun; njegovo ohranjanje ne ohrani gesla, naprave ali privilegijev izbrisanega uporabnika. |
| Organizacija z ločenimi projektnimi obsegi | Izbris organizacije zahteva ločeno `detachOrganization` odločitev za vsak ohranjen child scope. Otroku se odstrani samo organizationId; root ID, zapisi, članstva in finance grants ostanejo. Tuji nedostopni projekt ne razkrije svojega ID-ja, naslova ali financ. |
| Lastni shared financeEntry/financeTransfer | Tombstone brez payload; njihovi audit snapshots in druge replay payload kopije se odstranijo. Finančni seštevki se lahko spremenijo. |
| Lastni financeAccount s tujimi živimi financeEntry/financeTransfer | Samo po `preserveStructure`: ime `Shared financial account`, `ownerAccountId=null`, sistemska atribucija; valuta in **začetno stanje ostaneta** zaradi tujih računovodskih povezav. Vsi osebni audit/replay snapshots tega računa se odstranijo/redigirajo. |
| Zapisi drugih ustvarjalcev | Njihova title/notes/amount/category/poslovna vsebina ostane, **vključno z urejanji izbrisanega člana**. Sistem nima zgodovine avtorstva vsakega polja in je ne rekonstruira. Atribucija updatedBy, assignment, payer/recipient/owner reference na izbrisani account se odstranijo, revision/cursor se zvišata. To ni trditev izbrisa vseh UGC. |
| Finance audit | Vrstice izbrisanega actorja se izbrišejo. Za odstranjen lastni zapis in osebno očiščeno lastno strukturo se odstranijo vse snapshots. Tuje audit vrstice ob drugih ohranjenih zapisih ostanejo z redigiranimi identitetnimi UUID-ji; njihove poslovne vsebine ne brišemo zgolj zaradi reference. |
| Native replay | Lastne operation evidence se odstrani. Tuje response kopije prizadetih zapisov postanejo terminalni redigirani odgovori; request hash/ID ostaneta za preprečevanje ponovne uporabe operacije. Ostale natančne account-reference se redigirajo. |
| Povabila, account-mail, inbox, push, reminders, delivery | Lastna/na račun naslovljena povabila, seje, mail tokens/šifrirana vrsta, registracije/jobs, preferences in opomniki se izbrišejo. Obvestila drugih, vezana na odstranjen target ali actor, izginejo in visibility revision prejemnikov se spremeni. |
| Legacy Kanboard | Lastni komentarji in lastne task/file vsebine se odstranjujejo le, ko ni tujih child prispevkov. Tuje dodeljeno opravilo/podnaloga se razdodeli. Javnemu legacy projektu se odstrani owner reference; ne izbriše se celoten skupni projekt. Zasebni lastni projekt se odstrani samo brez tujih članov/UGC. Metadata `changed_by` se razveže; activities, ki vsebujejo prepoznano identiteto, se odstranijo. |
| Avatar in legacy priponke | Poti se zapišejo v trajno file-cleanup vrsto v isti SQL transakciji, bytes se odstranijo šele po commit. Neobstoječe datoteke se obravnavajo ponovljivo. SQL rollback ne odstrani datoteke. |
| Naprave, arhivi, kopije, host logi | Ta endpoint ne briše lokalnih kopij drugih naprav, uporabnikovih izvozov, upravljavčevih backupov ali že poslanih e-poštnih sporočil. Tretji vtičniki in host dnevniki niso inventar te pogodbe. |

## Transakcije in znane legacy omejitve

Capabilities oglašuje `accountDeletionPolicyVersions:[1,2]`. Strežnik za vsak svež pregled izračuna potrebno politiko iz dejanskega grafa; klient mora poslati vsaj to različico tudi pri confirm. Politika 1 ostane podprta za stare grafe; stari klient ne more implicitno sprejeti novih organizacijskih/osebnih odločitev. Politika 2 dopušča null začetno stanje finančnega računa in še naprej skrije finance polja brez finance-read granta. `organizationProjectsDetached` šteje odvezave v pregledu, ne njihovih finančnih podatkov.

`organizationProjectLink` uporablja opaque recordId in action `detachOrganization`. Name/childScopeId sta podana samo ob aktualnem članskem dostopu do child prostora; organizacijsko lastništvo ne podeduje tega dostopa. Odvezava je potrebna ob izrecnem izbrisu organizacije, če child ni tudi izrecno in dovoljeno izbrisan. Prenos organizacije na drugega ownerja sam po sebi ne odveže child projektov in ne prenese njihovega lastništva. Lastni korenski projekt potrebuje structural odločitev tudi pri prenosu scope lastništva, da se tuja vsebina ohrani z veljavnim staršem. Odstranjevanje lastnih task/rule zapisov odveže taskId oziroma recurrenceRuleId/occurrenceKey pri tujih finance zapisih; njihove zneske/plačilno vsebino obdrži.

SQLite uporablja `BEGIN IMMEDIATE`; MySQL/MariaDB `READ COMMITTED` in zaporedje globalni lock → trenutni actor/user/device → users → lastna legacy parent tasks → scopes. Po čakanju se ponovno preverijo identiteta, device, članstva, nasledniki, finance vidnost, odvisnosti in hash. Podatki, tombstones/revizije, reference, čistilna vrsta in receipt so atomski. Zadnji admin in successor roles so zaščiteni z users locks. Drugi Native pisci uporabljajo user→scope in po odjavi/revokaciji ne napišejo novega dela pod staro identiteto.

Kanboard `UserModel::remove()` ni klican: avatar briše pred transakcijo, PicoDb nested transaction lahko potrdi zunanjo transakcijo, komentarje anonimizira brez izbrisa vsebine, zasebne projekte pa odstranjuje po članstvu. Jedro ni spremenjeno.

Legacy parent lock in child FK preprečita, da bi med preverjanjem in task DELETE izgubil na novo potrjen komentar/priponko/podnalogo drugega. Dejanski test zadrži parent, med čakanjem doda tuj komentar in potrdi `deletion_blocked` ter ohranitev obeh zapisov. Vendar **že avtorizirana Kanboard web zahteva za novo vsebino nima Native ponovnega preverjanja identitete po čakanju**; `tasks.creator_id`/nekateri legacy `user_id` niso FK na users. Taka stara zahteva lahko po izbrisu računa ustvari dangling legacy zapis. Triggerji/jedrne spremembe niso vključeni; to je odprta legacy omejitev, ne nastavitev za uporabniško privolitev. Zgodovinskih legacy besedil z nekdanjim imenom brez prepoznavne identity reference prav tako ni mogoče dokazano v celoti pripisati posamezniku.

Legacy task z drugimi ali neznanimi comments/files ter zasebni projekt z drugimi/neznanimi prispevki sta izrecni ozki blokadi. `user_id=0` oziroma `creator_id=0` nista dokaz lastnega avtorstva. `subtasks.user_id` je dodelitev, ne avtorstvo: vsaka podnaloga lastnega taska/zasebnega projekta potrebuje ločeno razrešitev, tudi če je dodeljena izbrisanemu članu. Ta etapa nima splošnega brezizgubnega legacy workflowa za prenos posameznega tujega komentarja na drug task. Ne predstavljaj izbrisa kot dokončan full-UGC ali store-ready tok.

## Splet brez mobilne aplikacije in čiščenje

`<Kanboard base>/index.php?controller=AccountDeletionController&action=index&plugin=FamilyHub`

Samostojen isti-origin obrazec: username/password/TOTP → pregled → izbire naslednikov/ohranitve struktur → novo geslo/svež TOTP/DELETE. Vsi writes so POST+CSRF; GET ne izbriše ničesar. HTTPS, no-store, no-referrer in CSP brez zunanjih virov. Po izgubljenem ACK ponovljen confirm preveri receipt tudi ob `device_revoked`; ne obnovi bearerja ali gesla. Po izbrisu se hrani le anonimna CSRF seja, brez prejšnje prijavljene identitete. Jivie javna spletna stran na ta uporabnikov strežnik samo usmerja; ne zbira gesel.

Minutni cPanel cron (lokalna pot namestitve je primer, ne dejstvo gostovanja):

```sh
php /home/ACCOUNT/public_html/kanboard/plugins/FamilyHub/cli/account-deletion-cleanup.php
```

Izhod vsebuje samo število complete/pending operacij, brez uporabnikov ali poti. Pri trajnem pending naj upravljavec zasebno preveri lokalni file backend in dovoljenja; nato ponovi cron/status. Kopije baze/datotek pred namestitvijo in običajni postopek povrnitve ostanejo upravljavčeva odgovornost; pravega uporabniškega izbrisa ne vračaj tiho iz stare kopije.

## Dejanski testi 7. oktobra 2026

Kanboard1.2.54: SQLite, MySQL8.4.11, MariaDB10.11.19. `deletion-integration.php`:36 preverjanj na vsakem pogonu (users/private/shared/finance/audit/replay/owner chain/finance ACL/actual avatar/pending-retry). `deletion-negative.php`:24 na vsakem (sočasni confirm, revoked-after-wait, SQL rollback pred datotekami, deterministični legacy child wait, fresh/replayed TOTP, managed mode gate, unrelated-scope hash, anonymous legacy authors/subtask provenance, cancel-first/original-first in late original, mismatched/unauthorized cancel). Dedicated svež HTTP fixture na loopback18384:16 dejanskih preverjanj (brez aplikacije, CSRF, POST-only, HTML ne vrne gesla, actual users DELETE, receipt replay/izgubljeni ACK, star core web login zavrnjen, last-admin blocker, web cancellation+late confirm, production HTTP denied).

```sh
docker compose -f server/compose.yaml up -d
docker compose -f server/compose.mysql.yaml up -d
docker compose -f server/compose.mariadb.yaml up -d
docker exec kanban-familyhub-dev-kanboard-1 php /familyhub-tests/deletion-integration.php
docker exec kanban-familyhub-dev-kanboard-1 php /familyhub-tests/deletion-negative.php
docker exec kanban-familyhub-mysqltest-kanboard-1 php /familyhub-tests/deletion-integration.php
docker exec kanban-familyhub-mysqltest-kanboard-1 php /familyhub-tests/deletion-negative.php
docker exec kanban-familyhub-mariadbtest-kanboard-1 php /familyhub-tests/deletion-integration.php
docker exec kanban-familyhub-mariadbtest-kanboard-1 php /familyhub-tests/deletion-negative.php
python3 server/scripts/start-account-http-fixture.py --project kanban-familyhub-account-deletion-smoke --port 18384 --output build/qa/deletion-http/fixture.json
python3 server/scripts/test-deletion-http.py --fixture build/qa/deletion-http/fixture.json
```

Fixture je zasebna (0600), zunaj Git in source ZIP; obstoječa datoteka se ne prepiše. Naslednji zagon uporabi nov namenski project/output;18384 mora biti prost. Ni bilo dostopa do ali izbrisa produkcijskih računov.

## Dopolnitev preverjanja 8. oktobra 2026

`server/tests/organization-integration.php` uporablja samo sintetične disposable račune: staro policy1 zavrnitev pred implicitno odvezavo, opaque tuji child brez finance razkritja, izrecni detach ob izbrisu organizacije in ohranitev root/faz za drugega člana. Mobilni klient po capabilities izbere politiko 2 in hrani isti nespremenljivi preview/receipt postopek. Končno matriko in rezultate vodi [izvedbeni dnevnik](../UPGRADE_IMPLEMENTATION.md); ti dokazi ne pomenijo izbrisa produkcijskega uporabnika ali potrjene skladnosti trgovin.

Izvor FamilyHub 0.9.0 spletnega `AccountDeletionController` zahteva predogled s podporo policy3. Obrazec shrani dejansko različico svežega predogleda in jo pri potrditvi ter ponovitvi uporabi nespremenjeno; že izdani starejši obrazci brez polja ohranijo prvotno policy2 vedenje. Spletni predogled prikaže pogojno število ohranjenih/izbrisanih plačil, število potrjenih povračil in odstranitev zasebnih povezav. Dejanja `preserveStructure` oziroma `detachOrganization`, POST/CSRF zaščita, sveža ponovna overitev in javna receipt preverba ostanejo obvezni. Sintetični dejanski HTTP preizkusi so del `server/tests/linked-payments-integration.php`; gostovana namestitev ima ločene dokaze.

## Policy3: linked shared financial facts (source0.9/schema13)

A source with linked personal payment requires a fresh policy3 review. The preview adds conditional exact per-scope event/refund counts (`linkedFinancialFacts`), `privatePaymentProjectionsDeleted` and `sharedPaymentReceiptsRetained`. A `financeEntry/preserveStructure` choice retains already shared monetary facts only when the source scope is retained/transferred; author text/name/card linkage is removed. Required opaque historical actor IDs may remain; this is not full anonymization. Explicit source deletion removes its payment sidecar and marks retained downstream cash receipts `sourceRemoved`, never current. Personal projections and private card linkage are removed with the personal scope. Pending requests persist their exact original policy version and do not silently upgrade on retry. The detailed schema, counts and tests are in [linked payments contract](linked-payments-api-contract.md).
