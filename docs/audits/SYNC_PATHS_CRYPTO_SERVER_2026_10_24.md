# Izvorni pregled sync poti: crypto in strežnik — 24. oktober 2026

Stanje po r6, samo izvor in že zajeti metapodatki. Ta pregled ne izvaja kode,
testov, buildov, HTTP, Dockerja, naprav ali native aplikacij. Ne spreminja
implementacije. Native request-limit poskus 3 ostaja FAIL/STOP3; četrti poskus ni
predlagan. Fragment je podlaga za skupni pregled vseh modulov, ne dokaz odprave
napake ali celotne kriptografske pravilnosti.

Oznake: **R** je oddaljeno branje poslovnega stanja; **L** je lokalno preverjanje,
projekcija ali journal; **W** je oddaljena mutacija. R lahko zapisuje lokalne
preverjene dokaze. Strežniški read allowlist ni dokaz odsotnosti SQL stranskih
učinkov: konkretne izjeme so spodaj. Namig in transportni snapshot nikoli nista
kriptografska avtoriteta.

## Glavna ugotovitev: observation dogodek razširi access namige

**P1, potrjena izvorna povezava; native obseg vpliva ni izmerjen.** En nov
scope-observation dogodek lahko spremembo enega prostora razširi na content in
finance drugih dostopnih prostorov. Trenutni namig ne loči premika podpisanega
account loga od spremembe naprav/identitete/dostopa.

1. `CryptoBusinessSession._pullVerified` po pullu objavi checkpoint in ob
   reusable checkpointu kliče `CryptoScopeObservations.observe`:
   [crypto_business_router.dart:1726](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:1726).
2. Observation sestavi bundle s preverjeno glavo, člani, lifecycle in checkpoint
   proof hashi. Če točnega hasha še ni v verificiranih opažanjih, izvede
   `scopeObservation.put` **W** in `account.observeScope` **W**:
   [crypto_scope_observations.dart:66](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_scope_observations.dart:66),
   [crypto_scope_observations.dart:176](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_scope_observations.dart:176),
   [account_crypto_v2_workflow.dart:405](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_crypto_v2_workflow.dart:405).
3. `crypto2.account.scopeObserve` se v isti transakciji vključi v account log in
   izvede `directory.append`. Append poveča `generation` in spremeni `head_hash`;
   reduce tega dogodka sam po sebi ne menja naprav ali korenskih ključev:
   [NativeCryptoV2Service.php:302](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoV2Service.php:302),
   [NativeCryptoDirectoryV2.php:135](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoDirectoryV2.php:135),
   [NativeCryptoDirectoryV2.php:357](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoDirectoryV2.php:357).
4. `account.changes` v members stamp vsakega dostopnega prostora vključi
   `directory_state.generation` in `head_hash` za njegove membership vrstice.
   Members query vsebuje tudi neaktivne vrstice; spremembo `active` mora zaznati,
   vendar zato ni omejen le na trenutne žive člane. Isti računov dogodek se
   odrazi še v account `directory` stampu:
   [NativeAccountChanges.php:123](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:123),
   [NativeAccountChanges.php:140](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:140),
   [NativeAccountChanges.php:146](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:146).
5. Client `accountDomains.directory` izbere splošno access/metadata osvežitev;
   scope `access` pa izbere **obe** domeni content in finance. Tako dobijo dodatno
   delo dostopni prostori, katerih members stamp vsebuje spremenjeni račun:
   [collaboration_account_changes.dart:12](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_account_changes.dart:12),
   [collaboration_account_changes.dart:20](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_account_changes.dart:20),
   [collaboration_sync_actions.dart:467](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:467),
   [collaboration_sync_actions.dart:611](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:611).

To velja za lasten account event in za dogodek drugega računa v skupnih
membership vrsticah. Ni dokaz neskončne zanke: publisher ob točnem reusable
checkpointu vrne pred novo objavo
([crypto_domain_checkpoint_publisher.dart:15](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart:15));
observe vrne, če je točen bundle hash že v preverjenem account prefixu
([crypto_scope_observations.dart:178](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_scope_observations.dart:178));
account attestation dodatno išče točen že vključen dogodek
([account_crypto_v2_workflow.dart:480](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_crypto_v2_workflow.dart:480)).
Nov checkpoint/glava/lifecycle pa lahko ustvari nov bundle in nov premik loga.
Tudi stabilna pot pred early return že preveri glavo, checkpoint certifikate in
observation history. Early return zato ne pomeni nič HTTP ali nič CPU.

**Predlagana meja za naslednji načrt, brez izvedbe:** ločiti varnostno relevantno
spremembo naprave/root/roster/lifecycle od premika recovery/observation loga.
Podpisani log in njegova svežina se še vedno preverjata; samo namig za izbor
poslovnih domen naj ne enači vsakega log append z access spremembo. Najprej
popisati vse account event vrste, tudi keyring, recovery, revoke/rebind,
protectionReady, schedule-use/deletion/relocation companions. Ne odstraniti
generation/head iz varnostnih preverjanj in ne prestaviti cursorja na poljuben
poznejši snapshot: to bi lahko preskočilo sočasno tujo mutacijo. Pričakovani
prihranek zahtev iz trenutnih metapodatkov ni izračunljiv.

## Mapa centralnih poti in povezava z moduli

| Pot | Dejanski read/write prehodi | Preverjanje in meja |
| --- | --- | --- |
| Računski 30s pregled | `account.changes` **R** → izbira scope/domain → ob delu metadata, outbox, pull, checkpoint, notifications **R/L/W** | [collaboration_sync_actions.dart:160](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:160); nochange brez lokalnega/recovery dela vrne na :289; cursor se shrani po uspešnem durable apply na :318, ob generation mismatch se ne potrdi. |
| Router ordinary sync | Pred crypto routanjem restore fence in zaščiteni scope floor **L**; potem metadata/content/finance/dokument/notification adapter | [crypto_domain_router.dart:142](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_router.dart:142). `account.changes` gre neposredno na host metadata pot, ne skozi business crypto adapter. Manjkajoč zaščiten router se konča s pending/error, ne s plaintext fallbackom. |
| Metadata list/members | catalog/head/lifecycle/member directories **R/L**; cold metadata lahko kliče content pull **R/L/W** | [crypto_business_router.dart:953](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:953), members :1154. Trenutni retained group velja samo za `scopes.list` in `scopes.members`, ne za celoten sync. |
| Ordinary zapisi | push **L/W**, pull **R/L**, whole-batch proof/AEAD/policy/projekcija **L** | Router push :2198, `_writeRaw` :2797, project :3938, policy projection :4055; vsi v [crypto_business_router.dart](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:2198). Projekt, task, event, shopping, household, garden in idea uporabljajo isto centralno pot; tip je del podpisanega recorda. |
| Finance in task/cost | Ločen finance read/write context; account choices, paired task intent/cost ter linked payment projection so odvisnosti, ne neodvisni plaintext zapisi | [crypto_business_router.dart:2405](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:2405), [crypto_business_payments.dart:806](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_payments.dart:806), [crypto_business_payments.dart:1082](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_payments.dart:1082). Finance role/write ostane ločen guard; viewer+financewrite ni nova podprta kombinacija. |
| Tabele/priloge/idea assets/veliki payloadi | Adapter pripravi/razširi payload, uporablja blobs **R/W**, table lease **R/W** in ordinary record proof **L/W** | [crypto_business_router.dart:348](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:348) veže dokumente+payments+choices v eno projekcijo; lease :488 in command :531 v [crypto_business_documents.dart](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_documents.dart:488). Table/attachment ne gresta v ordinary enum projekcijo; canonical proof in dokumentni adapter ostaneta obvezna. |
| Inbox/reminders | display/config **R/L**, read/preferences/reminder command **L/W**; target-open lahko kliče scoped pull **R/L/W** | [crypto_business_notifications.dart:162](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_notifications.dart:162), target pull :249/:516/:659/:864. Zato `inbox.open` po imenu ni jamstvo samo lahkega display read. Sync notifications/config ostane po content/finance fazah [collaboration_sync_actions.dart:1042](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:1042). |
| Invitation inspect/accept/resume | preview/open/directory **R/L**; accept **L/W**; resume preveri exact checkpoint/receipt, glavo, ključe in dostop **R/L/W po originalnem journalu** | [invite_crypto_repository.dart:1040](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/invite_crypto_repository.dart:1040), acceptedRecipient :1208, resumeAccepted :1486, accept :1628. Obstoječe sprejetje se ne nadomesti z novim acceptom. |
| Send/preauthorization/autoapproval | recipient discovery **R/L** → owner review → grants/head/activation **L/W**; notification samo prebudi pregled | [invite_crypto_repository.dart:541](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/invite_crypto_repository.dart:541), prepare :722/:833, [crypto_invitation_autoapproval.dart:122](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_invitation_autoapproval.dart:122). Fresh disclosure boundary :309, review :400, admit :416. Ne sodi v metadata-only context. |
| Scope review/rotation/grants | review bere record snapshot+author directories **R/L**; confirm preveri review/draft, objavi grants in aktivacijo **L/W** | [scope_crypto_manager.dart:1062](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/scope_crypto_manager.dart:1062), raw pull :1172, confirm :1406, publish :1876, grant/activate :2787. Retained prepared journal in policy/projection guard ostaneta; snapshot ne postane authority. |
| Account protection | own directory/catalog **R/L** → legacy inspect, peer freshness **R/L** → observation **W** → protectionCatalog **R** → podpisan protectionReady **W** | [account_protection_ready.dart:439](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_protection_ready.dart:439). Samo `readScopeMembers` :341 je omejena R/L faza. Legacy inspect je pred svežim preverjanjem; rotation/observe/signing/receipt so zunaj te faze. |
| Migration/FILE/recovery | discover/status **R/L**, prepare/fence/archive/stage/verify/activate **R/L/W**, točen FILE/cold verification in lokalni journal | [crypto_migration_coordinator.dart:267](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_migration_coordinator.dart:267), prepare :327, resume :369, archive :542; [crypto_migration_pipeline.dart:51](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_migration_pipeline.dart:51). `inspect` ni zgolj pomnilniški getter: odkrije/resume in shrani lokalno stanje. Ni varen alias za ordinary metadata group. |
| Device/root recovery in backup | fresh account prefix, exact saved requests, obnovitev scope ključev/opazovanj **R/L/W** | [account_crypto_v2_workflow.dart:177](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_crypto_v2_workflow.dart:177), root :760, resume :976; [crypto_scope_observations.dart:204](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_scope_observations.dart:204) in :626; upload recovery preverja binding in ne potrjuje prenosa [crypto_document_backup_recovery.dart:228](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_document_backup_recovery.dart:228). |

To je mapa skupnih vstopov in adapterjev. Posamezni migration, lifecycle,
moderation, relocation, export in scheduling protokoli imajo dodatne podpisane
semantične pogoje. Njihovo združevanje v nov universal read context ni odobreno;
allowlist endpointa ali ime metode ne dokazuje varnosti tega združevanja.

## Kje nastajajo ponovna preverjanja

**A. Nova access instanca pri običajnem dispatchu.** `accountFor` lahko vrne isti
account workflow, vendar `_dispatch` brez shared/combined contexta naredi nov
`SessionCryptoAccess`. Njegovi `_heads`, `_directories` in operation memo niso
skupni med temi instancami:
[crypto_business_router.dart:413](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:413),
[session_crypto_access.dart:1276](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:1276).
Tudi nova queue facade pri vsakem `runtime.queue` getterju ne pomeni nove
neodvisne durable vrste: skupen je partition store/serial guard. Ni pa s tem
samodejno skupen verified access context.

**B. Glava → vsak trenutni član → imenik → lifecycle/descriptor.** `currentHead`
gre prek descriptor/migration preverjanja; brez uporabnega operation memo bere
head, preveri nasledstvo ter trenutne member directories. `currentMemberDirectory`
izvede directory.status in nato `directoryAt`/prefix/snapshot preverjanje:
[session_crypto_access.dart:1871](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:1871),
[session_crypto_access.dart:1925](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:1925),
[session_crypto_access.dart:2011](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:2011),
[session_crypto_access.dart:6241](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:6241).
Members display dodatno bere head za acceptedAccountIds; to je display projection,
ne razširitev key authority (:1885). Member labels ločeno preverijo capabilities
in endpoint, brez signed-authority pomena
([account_directory_repository.dart:111](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_directory_repository.dart:111)).

**C. Own prefix se preverja tudi med recovery/observation branjem.**
`requireFresh` kliče refresh; refresh začne z account.status in po potrebi log
stranmi. `recover` pri dohitenem observation cursorju ponovno osveži podpisani
own prefix, ker lokalni cursor ne dokazuje praznega strežniškega repa:
[account_directory_repository.dart:239](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_directory_repository.dart:239),
[account_directory_repository.dart:284](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_directory_repository.dart:284),
[account_directory_repository.dart:523](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_directory_repository.dart:523),
[crypto_scope_observations.dart:689](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_scope_observations.dart:689).
To je potrebno preverjanje svežine; vprašanje je njegova skupna meja z drugimi
bralci, ne odstranitev preverjanja.

**D. Pull ni samo records.pull.** Pot gre skozi ensureScopeReadKeys → readContext
→ durable queue pull → checkpoint completeness → publisher → observation.
Queue pred pullom preveri opazovane inventory floors; neskladni cursor zahteva
reconcile. Vsak author proof/key lahko zahteva head/directory/grant history:
[crypto_business_router.dart:740](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:740),
[crypto_business_router.dart:1726](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:1726),
[session_crypto_access.dart:5196](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:5196),
[session_crypto_access.dart:5885](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:5885).
R6 counts zato ne dovoljujejo sklepa, da 32 records.pull pomeni samo 32 readov.

**E. Checkpoint manifest se lahko bere in podpisuje v isti logični poti.**
Publisher preveri reusable status, sicer strani inventory, lokalno primerja
canonical/accepted rows, pripravi signed checkpoint, receipt-first dostavi,
invalidira authority generation ter fresh reconcile:
[crypto_domain_checkpoint_publisher.dart:15](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart:15),
[:170](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart:170),
[:189](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint_publisher.dart:189).
`CryptoDomainCheckpoint.reconcile` preverja manifest, attestation pages, znane
floors in durable inventory; unsigned cursor/hasMore ni completeness dokaz:
[crypto_domain_checkpoint.dart:118](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint.dart:118),
[:238](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint.dart:238),
[:327](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_domain_checkpoint.dart:327).
Ponovna domenska/dokumentna/finance zahteva lahko to pot znova doseže. Brez
exact selectorjev in preverjanja reusable pogojev ni dokazana podvojitev istega
inventory dela ali njen odstranljivi obseg.

## Obstoječe skupne meje in invalidacije

| Meja | Kaj ohrani | Kdaj preneha / česa ne sme nadomestiti |
| --- | --- | --- |
| `withVerifiedOperation` | Ena access instanca, proof memo, transport snapshot, originalna ura največ 5s, pin/lifecycle/session/generation pogoji | Fresh boundary zavrže retained handle; mutate/onFailure zapre snapshot. Nova meja ne podaljša stare ure. [session_crypto_access.dart:1706](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:1706), :1747/:1765; [crypto_authority_operation_policy.dart](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_authority_operation_policy.dart). |
| Retained read operation | Isti memo in snapshot med zaporednimi porabniki | Overlap, close, napaka, potek ali pin mismatch vodi na neodvisno preverjanje; originalne signed evidence se še vedno preverjajo. [session_crypto_access.dart:373](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:373). |
| Metadata dispatch group | Samo zaporedna `scopes.list` in `scopes.members`, isti token+cel profil+account/access | Unknown op, foreign router, nested/direct entry, mutation ali napaka ga trajno zapre. [crypto_verified_dispatch_reads.dart:17](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_verified_dispatch_reads.dart:17), [crypto_business_router.dart:147](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:147), :166/:276/:396. Wrapper se konča pred projection cursor/outbox/content/finance delom [collaboration_sync_actions.dart:601](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:601). |
| Combined finance read | Verified domenski snapshot + lokalni state digest + isti originalni authority lease | Non-attesting read, zapis, druga operacija ali spremenjen SQL digest ga invalidira. Ne velja za ordinary content in ne razširi financeRole. [crypto_business_router.dart:276](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:276), :1659/:1677; [crypto_verified_finance_reads.dart:38](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_verified_finance_reads.dart:38). |
| Exact transport memo | Samo enak operation+canonical params; deepcopy; 64 entries/512KiB; singleflight znotraj istega lease | Inventory/observation pages in manjkajoča head/status selectorja; pendingCapability, napake, receipt in druge R niso univerzalno cacheane. [crypto_authority_snapshot.dart:37](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_authority_snapshot.dart:37), :239/:296. |
| Server authority snapshot | Bounded sestava originalnih endpointov pod istim read-only DB pogledom | ACL in originalni podpisi ostanejo; kapaciteta/izpuščen selector gre na exact fallback. 512 entries/256 reads/1.25MB ni velikost client exact memo. [NativeCryptoAuthoritySnapshotV2.php:8](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoAuthoritySnapshotV2.php:8), :22/:56/:155. |

Queue `beforeDelivery` najprej sinhrono zapre metadata/finance reuse, nato izvede
obstoječi `access.beforeDelivery(...freshBoundary:true)`:
[crypto_business_router.dart:457](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:457),
[:792](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_business_router.dart:792),
[session_crypto_access.dart:6291](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:6291).
Authority invalidacija poveča generation in zavrže blob window; immutable
hash-addressed historical dokazi lahko ostanejo v cacheu, ne postanejo latest
authority [session_crypto_access.dart:1260](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/session_crypto_access.dart:1260).

## Serializacija ni en globalni mrežni koordinator

| Guard | Obseg | Pomembna meja |
| --- | --- | --- |
| Collaboration sync demand/singleflight | En repository/epoch; save/resume/manual demand se združuje | Ne serializira drugih workflow objektov, wizardov ali druge native aplikacije. [collaboration_sync_actions.dart:99](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:99). |
| `AccountDirectoryRepository.exclusive` | Statična vrsta po account partitionu v istem procesu | Ločena od crypto sync queue. Nizek-level call ni samodejno v exclusive. [account_directory_repository.dart:62](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/account_directory_repository.dart:62). |
| `CryptoSyncRepository._exclusive` | Statična vrsta po store partitionu v istem procesu | Pull/enqueue/deliver so serialni skozi to vrsto; direct scope/invitation/account transport ne gre nujno skoznjo. [crypto_sync_repository.dart:185](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:185). |
| `ScopeCryptoManager._exclusive` | Partition + scope | Različni scope managerji lahko delajo neodvisno; to ni isti queue kot account ali record queue. [scope_crypto_manager.dart:75](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/scope_crypto_manager.dart:75). |
| Foreground approval runs | Partition v istem procesu, max100 exact intents | Drugi caller ne podeduje foreground capability; ni globalna zapora vsega HTTP. [crypto_invitation_autoapproval.dart:122](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_invitation_autoapproval.dart:122). |
| Invitation preparation singleflight | Exact preparation key v istem procesu | Uporablja tudi manager.serialize za posamezne podpisane korake, ne vse read poti. [invite_crypto_repository.dart:702](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/invite_crypto_repository.dart:702), :203/:1582/:1710. |
| Server transakcija/global lock | En DB/instance; običajni crypto RPC zaklene native global row, SQLite BEGIN IMMEDIATE serializira writerje | Ni client coalescing. R navadno še vedno zasede transakcijsko/lock delo; snapshot je posebna read-only izjema. [NativeDatabase.php:92](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeDatabase.php:92), [NativeCryptoV2Service.php:383](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoV2Service.php:383). |

Med dvema aplikacijama A/B ni skupnega Dart static queue. Strežniški IP rate
bucket je kljub temu skupen. Zato uspešen per-partition singleflight ne dokazuje
ustreznega skupnega request budgeta, niti dovoljenja deliti podpisane authority
objekte med računi. Za migration/protection visokonivojske celote ni razvidna ena
skupna univerzalna zapora z ordinary sync; uporabljata svoje journal/evidence in
nižjenivojske guard meje. To je popis koordinacije, ne dokaz opažene dirke.

## Receipts, pending delo in neodvisne poti

Crypto record queue vedno najprej bere exact receipt. Šele `unknown` uporabi
fresh beforeDelivery in originalne podpisane bajte. Terminal-only pot ne pošlje
unknown requesta:
[crypto_sync_repository.dart:938](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:938),
[:955](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:955),
[:984](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:984).
Scope manager ima svojo receipt-first `_send`, exact requestHash/proof binding in
receiptOnly nadaljevanje:
[scope_crypto_manager.dart:284](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/scope_crypto_manager.dart:284).
Directory resume ima ločen account journal. Noben nov skupni read context ne sme
združiti receipt odgovorov v cache ali označiti unknown kot dokončno zavrnitev.

Transport cursor se hrani neodvisno od projection cursorja; prispele vrstice
lahko ostanejo semantično pending. Whole-batch signatures, AEAD, predecessor,
reference, policy in extension projekcija so pred vidno durable projekcijo:
[crypto_sync_repository.dart:1214](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:1214),
[:1555](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:1555),
[:1736](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_sync_repository.dart:1736).
Zato prenesen page/HTTP200 ni dokaz projected/complete stanja.

Obstoječi nonempty policy successor ostaja UNWIRED/STOP3; restore testi ostajajo
delni/STOP3 in relocation pending. Ta audit ne odklepa ali na novo izdaja starih
requestov, ne spreminja claims, prej shranjenih ključev ali terminal classifierjev.
Širši context ni rešitev za te kompatibilnostne meje.

## Strežniški account.changes in read stranski učinki

`account.changes` je **metadata vector s HMAC-overjenim cursorjem**, ne nova append-only
per-account change tabela ali en sam globalni monotoni cursor. Uporabi obstoječe
monotone domenske sekvence, access/metadata revizije, documents counter in inbox
revizije, ter digeste trenutnih metapodatkov. Cursor je vezan na v1+server+account+
device, preverjen pred primerjavo; ID-ji v odgovoru izvirajo iz trenutnega ACL
queryja, ne iz dostavljenega cursorja. Null zahteva reset snapshot, ne nove
avtoritete [NativeAccountChanges.php:49](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:49),
[:68](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:68),
[:170](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:170).

Content/finance mutacije posodobijo record, position, history in domain/global
sequence znotraj istega crypto command transactiona
([NativeCryptoStorageV2.php:241](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoStorageV2.php:241));
legacy dokumentne mutacije kličejo transaction-required documents counter
([NativeDocumentService.php:9](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeDocumentService.php:9));
notifikacije imajo sequence/visibility/configuration revision
([NativeNotificationWriter.php:14](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeNotificationWriter.php:14)).
Policy activation zbudi metadata/access stamp prek `metadata_revision` bumpa,
čeprav nova policy state tabela ni neposreden člen vectorja
([NativeCryptoRecordPolicyV1.php:196](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoRecordPolicyV1.php:196)).
To so pregledani centralni hooki, ne nova dokazna matrika vseh SQL mutacij.

Endpoint naredi en repeatable read snapshot; ne bere record payloadov, proofs,
blobs ali plaintexta. Trenutni read ne kliče business mutation rout in ne potrjuje
strežniškega cursorja. **Ima rate-counter zapis pred snapshotom**, tudi ob
zavrnitvi. Razpoložljivost naredi le zero-row schema query, ne full inventory.
Actor(false), serverId in HMAC binding ostanejo overjeni:
[NativeAccountChanges.php:21](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:21),
[:33](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:33).

**P2, skaliranje in granularity:** query ni konstanten O(1). Največ2048 prostorov,
člani/grants po dostopnih prostorih in starših, lifecycle MAX po zgodovini ter
največ1024 aktivnih povabil tvorijo vector; cursor je največ512KiB. Lifecycle
query in membership history lahko rasteta z uporabo, čeprav ni record scanov.
Prekoračitev eksplicitno vrne too_large, ne tihe truncacije. Povabila se berejo
le pending/accepted in še nepretečena; iztek zbudi spremembo zaradi clock queryja
tudi brez novega SQL dogodka. Odstranjen scope ID ne uide v current reply: account
access digest sproži ponovno access discovery
([NativeAccountChanges.php:96](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:96),
[:119](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:119),
[:155](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeAccountChanges.php:155)).

**P2, imena R endpointov:** navadni scope `author(...write:false)` še vedno kliče
`refreshPending`, ki lahko expire pending glavo in ponovno zapiše derived closure
flags. Authority snapshot ta del izrecno preskoči; njegov `change()` guard prepove
SQL mutacijo, optional enrichment pa lahko izpusti in pusti exact fallback:
[NativeCryptoScopeV2.php:721](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php:721),
[:754](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php:754),
[:1581](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoScopeV2.php:1581),
[NativeDatabase.php:65](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeDatabase.php:65),
[NativeCryptoAuthoritySnapshotV2.php:32](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoAuthoritySnapshotV2.php:32).
Druga izjema je `crypto2.account.scopeObservation.put`: nahaja se na read
allowlistu zato, ker nima običajnega command envelope, vendar dejansko shrani
candidate observation po current device/keyring guardu. Client snapshot ga
obravnava kot mutacijo in se zapre
([NativeCryptoV2Service.php:124](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoV2Service.php:124),
[crypto_authority_snapshot.dart:239](/Users/anzenovsak/Git/kanban/lib/organizer/data/e2ee/crypto_authority_snapshot.dart:239)).

## Omejevanje zahtev in r6 baseline

Pred auth/poslovno vejo vsak `crypto2.*` execution porabi en IP bucket hit:
600 v fiksnem60s oknu. To ni rolling window. Rate transakcija poveča števec tudi
pri zavrnitvi in ga commit-a pred business rollbackom. `retryAfter` je konec
shranjenega okna minus trenutni čas
([NativeCryptoV2Service.php:18](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeCryptoV2Service.php:18),
[NativeDatabase.php:130](/Users/anzenovsak/Git/kanban/server/plugins/FamilyHub/Model/NativeDatabase.php:130)).
Vgrajeni snapshot bere modele neposredno, ne rekurzivno `execute`, zato notranji
entries niso dodatni crypto2 bucket hits. `account.changes` ima ločen2400/60s IP
bucket; to ne zvišuje crypto2 limita. Ni predloga zvišanja omejitve.

Obstoječi zajem od byte offset879964 do1025296: 949 zahtev/946×200/3×429,
924 crypto2 +25 drugih,15:21:30–15:22:45UTC. Crypto ordinals601/602/603 so429
po600 uspešnih crypto zahtevah. Prvi burst15:21:30–38 je602 zahtev/590crypto;
15:22:06–24 dodatnih21/13crypto vključuje3zavrnitve;
15:22:30–45 dodatnih326/321crypto je200. Slednje je skladno z resetom okna;
točnega `window_start` ali DB števca ta pregled ni bral.

| Operacija | Zahteve |
| --- | ---: |
| directory.status | 286 |
| scope.headGet | 152 |
| authority.snapshot | 97 |
| scope.lifecycle.list | 66 |
| domain.inventory | 64 |
| account.status | 56 |
| scope.lifecycle.baseline | 47 |
| records.pull | 32 |
| receipt.get | 28 |
| scope.recordPolicy.status / baseline | 16 /12 |
| scopes.catalog / domain.checkpoint | 14 /11 |
| capabilities / account.changes / moderation.policyStatus | 15 /5 /5 |
| Ostale operacije | Vsaka največ4; celota v JSON spodaj |

Pet `account.changes` pregledov je200,6–21ms; zajem nima `changed`, cursorja,
account/device atribucije ali selectorjev. Zato ni mogoče dokazati posameznega
nochange odgovora, dvojnega istega preverjanja ali prihranka iz memo sprememb.
Client izvor ob `!changed` in brez lokalnega/recovery dela vrne pred `_performSync`
([collaboration_sync_actions.dart:289](/Users/anzenovsak/Git/kanban/lib/organizer/data/collaboration_sync_actions.dart:289));
`schedule.checked` postavi naslednji pregled čez30s
([collaboration_sync_schedule.dart:82](/Users/anzenovsak/Git/kanban/lib/organizer/state/collaboration_sync_schedule.dart:82)).
Pet probe zahtev ni dokaz hitrega polling flooda; hkrati ni dokaz native
nochange pravilnosti. Nov child workload preprečuje primerljiv odstotek izboljšave
proti r5. 949 različnih transport request ID-jev ne dokazuje odsotnosti ponovitev
istega podpisanega command/receipt intent-a.

Dokazi: [r6-request-accounting.json](/Users/anzenovsak/Git/kanban/build/qa/sync-redesign-20261024/r6-request-accounting.json),
[r6-continuation-start.json](/Users/anzenovsak/Git/kanban/build/qa/sync-redesign-20261024/r6-continuation-start.json),
[request-metadata.ndjson](/Users/anzenovsak/Git/kanban/build/qa/sync-redesign-20261024/server/logs/request-metadata.ndjson).
JSON hrani točen byte slice hash, celoten operation breakdown in omejitve razlage.

## Predlog naslednjih varnih mej za skupni načrt

1. Najprej popraviti načrt granularity account-event → change hint → domain
   selection; P1 zgoraj lahko povzroči novo delo, še preden cache sploh pomaga.
   Potrebna je matrika security eventov proti observation/protection eventom.
2. Za vsak logical read zapisati začetek, konec in vse možne W korake. Varno
   skupno jedro je trenutna glava + trenutni imeniki + lifecycle/descriptor znotraj
   istega obstoječega5s lease, iste identitete, originalnih pinov in transport
   selectorjev. Ne podaljšati TTL, ne mešati accountov in ne držati handle čez UI
   await ali mutation. Obseg mora biti ekspliciten in zaporedni, ne globalen cache.
3. Za pull najprej popisati ločeno read/decrypt/project fazo ter checkpoint in
   observation objavo. Skupen context za vse tri kot celoto ni varen predlog:
   checkpoint/observe sta W in spremenita podpisano account/domensko stanje.
   Po W sledi fresh authority, retained read material se zavrže.
4. Migration/recovery/protection/invitation imajo ločene immutable journals in
   disclosure guard. Njihov čisti read prefix se lahko šele po exact inventarju
   obravnava za reuse; receipt lookup, sign/send, grants/activation, keyring in
   legacy simulation ne smejo postati cached read ali preskočen guard.
5. Za novo merilno zasnovo predlagati sanirane phase/operation-selector digeste,
   current authority lease ID/age, hit/miss/omitted/fallback razlog ter changed
   domain hint. Brez payloadov, ključev, podpisov ali plaintexta. Trenutni log
   zadošča za računanje bucket prometa, ne za vzročni prihranek ali podvojene
   verifierje. To je predlog instrumentacije, ne dovoljenje novega runtime kroga.

Audit ni spremenil nobene kode, podatkov, runtime okolja ali testnega izida.
Request-limit blocker ostaja odprt; nadaljnja izvedba in meritev potrebujeta nov
izrecen dogovor uporabnika.
