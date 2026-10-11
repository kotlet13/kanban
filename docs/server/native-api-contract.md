# FamilyHub native API v1 — deljenje in sinhronizacija

**Najnovejša dopolnitev 10. oktobra 2026:** izvor FamilyHub 0.11.0/schema15 doda [deljenje prostora ali projekta, policy3 in invitations3](space-sharing-api-contract.md). Član novega prostora upravlja njegovo skupno vsebino in vse projekte; projektni član ostane omejen na svoj projekt. Obstoječe politike 1/2 imajo izrecen prehod s predogledom. Ta dopolnitev ima prednost pred starejšim opisom pravic spodaj; transport v1 in finančne pogodbe ostanejo nespremenjeni. Dokaze in meje vodi [uskladitev deljenja](../SPACE_SHARING_ALIGNMENT.md).

**Dopolnitev 10. oktobra 2026:** FamilyHub 0.10.0/schema14 doda [e-poštna povabila, pogodba2](email-invitation-api-contract.md). Nov uporabnik si izbere uporabniško ime in geslo; registracija ga prijavi, članstvo pa nastane šele ob ločenem sprejemu. Stari `auth.register`/`invitations.*` s povabilom na uporabniško ime ostanejo združljivi. Transport Native v1 se ne spremeni. Izvor, namestitev in fizični preizkus so ločeno navedeni v [dnevniku povabil](../EMAIL_INVITATIONS.md).

Spodnji osnovni opis je bil usklajen z izvorom FamilyHub **0.7.0 / schema 11** 8. oktobra 2026; za novejše pravice veljajo zgornje dopolnitve. Transport ostane Native v1; različice zapisov so ločeno `recordContractVersions:[1,2,3]` in `financeContractVersions:[1,2]`. Različice 0.3–0.6 spodaj opisujejo zgodovino razširitev. Izvor in lokalni preizkusi niso dokaz nameščene 0.7.0 na gostovanju ali fizične dostave obvestil; aktualne rezultate vodi [izvedbeni dnevnik](../UPGRADE_IMPLEMENTATION.md). Ne gre za stare `familyHub*` JSON-RPC
metode: podatki so v lastnih tabelah, brez pravic ali metapodatkov starih projektov.

## Transport

`POST <Kanboard base>/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub`

`Content-Type: application/json`, telo `{ "v": 1, "op": "sync.pull", "params": {} }`.
Uspeh `{ "v": 1, "data": { ... } }`. Napaka
`{ "v": 1, "error": { "code": "permission_revoked", "message": "permission_revoked", "details": {} } }`.
Gesla in žetoni so samo v telesu oziroma `Authorization: Bearer <device token>`, nikoli v URL.
Piškotki, Basic, globalni JSON-RPC ključ in osebni Kanboard API ključ ne nadomestijo naprave.
HTTPS je obvezen; izolirani Docker dovoljuje HTTP prek izrecne razvojne konfiguracije.
Glava X-Forwarded-Proto šteje samo za REMOTE_ADDR v izrecnem FAMILYHUB_TRUSTED_PROXY_IPS;
seznam je privzeto prazen. CPanel z neposrednim TLS uporablja PHP HTTPS spremenljivko.
Odzivi so `no-store`. Ni samodejnih preusmeritev ali prehoda na drugo identiteto.

`FAMILYHUB_ENABLE_NATIVE_API` mora biti izrecno `true`; namestitveni paket je privzeto izključen.
`FAMILYHUB_CORS_ORIGINS` je izrecen seznam celotnih HTTPS izvorov. Razvojna konfiguracija
dovoli samo `http://127.0.0.1:18770` in `http://127.0.0.1:18771`. Brez wildcarda ali
`Access-Control-Allow-Credentials`. Predhodna zahteva OPTIONS dovoli samo POST in
Authorization/Content-Type. Native API ne uporablja spletne seje za avtorizacijo.

HTTP: 401 `auth_required`, `device_revoked`, `invalid_credentials`, `two_factor_required`;
403 `permission_revoked`; 409 `conflict`, `idempotency_mismatch`;
422 `validation_error` oziroma natančnejši domen­ski razlog;
429 `rate_limited` z `details.retryAfter` in glavo `Retry-After`;
503 `feature_disabled`. Konflikt vsebuje `details.serverRecord`, dostopen samo trenutnemu članu.

Omejitve so trajne v bazi in vrnejo čas za ponovitev. `scopes.list/members`
imata skupni budget 600 zahtev/accountId/min ter pre-auth IP envelope 2400/min;
več naprav istega računa deli account budget, več ljudi za NAT pa ne. Scope
mutations ohranijo ločeni `scopes-ip` 120/min. Login account 10/min, login IP 60/min
in invitation registration IP 10/600s ostanejo nespremenjeni. Odjemalec naj ne
ponavlja vseh member imenikov pri vsakem pollu; izrecne spremembe članstva
potrebujejo svež imenik. Preverjanje identitete in scope ACL ostane ob vsaki zahtevi.

## Račun in naprava

- `capabilities {}` (javno): različica pogodbe, omogočenost, podprti tipi in auth načini.
- `auth.login {username,password,deviceName,otp?}` (javno).
- `auth.register {token,username,password,displayName,deviceName}` (javno, samo veljavno povabilo).
- `auth.me {}` (naprava): `{serverId,user,device}`.
- `auth.renew {deviceId}` (naprava, samo trenutna): `{serverId,user,device}`. FamilyHub 0.6.1 razglasi `features.sessionRenewal`. V zadnjih sedmih dneh veljavnosti strežnik veljavno sejo podaljša na 30 dni od trenutnega časa; prej vrne nespremenjeno veljavnost. Naprava in žeton ostaneta ista, zato je izgubljen odgovor varno ponovljiv. Preklicana, potekla ali zaradi spremembe poverilnic neveljavna seja se ne obnovi.
- `auth.devices {}` (naprava): `{devices:[device]}` brez žetonov.
- `auth.revoke {deviceId}` (naprava, samo lastne): `{revoked:true}`.

Prijava/registracija vrne `{serverId,user:{id,accountId,username,displayName},device:{id,name,expiresAt},token}`.
`user.id` je celo število, `device.id` UUID, čas veljavnosti Unix sekunde. Device token
je naključen, 256-bitni, v bazi samo SHA256, z začetno veljavnostjo 30 dni. Zmožnost podaljševanja omogoča drsečo veljavnost ob redni uporabi. Preklic/iztek, sprememba
gesla ali nastavitve/skrivnosti 2FA ter deaktivacija uporabnika ga naredijo neveljavnega.
`serverId` je ob migraciji ustvarjen in trajen UUID namestitve; capabilities ga vrne
tudi pred prijavo. `accountId` je trajen UUID uporabnika, vezan na core user s FK
ON DELETE CASCADE. Izbris in ponovno ustvarjanje istega numeric ID ne podelita starega
članstva ali naprave. Lokalno particijo določa `serverId:accountId`, ne URL/username.

Prijava uporablja obstoječ aktivni lokalni Kanboard račun. Preveri geslo, izključeno
lokalno prijavo/LDAP, obstoječi lock in trajne omejitve po računu/IP. Lokalni TOTP
uporablja isto knjižnico kot pripeta različica Kanboarda, šest števk, 30 sekund in
odmik ±1. Brez kode po pravilnem geslu: `two_factor_required`; napačna ali že uporabljena
koda: generičen `invalid_credentials`. Časovni korak se porabi atomarno z izdajo naprave.
Nepodprti zunanji ponudniki vrnejo `auth_provider_unsupported`, brez nadomestnega API ključa.

Pri `auth.register` je nov račun samo povabljen: username je vezan na povabilo, novo uporabniško ime je
ASCII `[a-z0-9_.-]`, 3–64 znakov; novo geslo 12–72 bajtov brez NUL. Ne gre za preverjeno
e-pošto. Registracija ustvari običajen `app-user`, članstvo, napravo in porabi povabilo
v eni transakciji. Ob napaki ne porabi povabila. Noben javni tok ne ustvarja skrbnika.
Prvi lastnik lastne namestitve se prijavi z obstoječim uporabniškim računom ali uporabi izrecni prvi enrollment iz [pogodbe računa](account-api-contract.md), nato ustvari obseg.

## Obsegi, člani in povabila

`scope = {id:UUID,kind:"household"|"project"|"personal"|"organization",name,role:"owner"|"member"|"viewer",sequence:int,archived:bool,organizationId:UUID|null,projectRootId:UUID|null,requiredRecordContractVersion:int}`.
Gospodinjstvo in samostojen projekt sta ločena obsega; dostop se ne deduje.
Osebni podatki ostanejo lokalni, dokler uporabnik izrecno izbere deljenje.
Generic record contract1 nima financ ali dogodkov. FamilyHub0.3 razširitve (sync2/event, inbox/opomniki in ločen finance modul) so v [collaboration-api-contract.md](collaboration-api-contract.md); stari Kanboard projekti ostajajo ločeni.

- `scopes.create {id,kind,name,requestId,organizationId?}` → `{scope}`; prijavljen ustvarjalec postane owner. `kind` je household/project/organization; personal se ustvari samo prek `personal.ensure`.
- `scopes.list {includePersonal?:bool,includeOrganizations?:bool,includeArchived?:bool}` → `{scopes}`; samo trenutna aktivna članstva, vse tri izbirne vrednosti so privzeto false.
- `scopes.archive {scopeId,archived:bool,requestId}` → `{scope}`; samo owner projektnega obsega z `projectRootId`.
- `scopes.members {scopeId}` → `{members:[{userId,accountId,username,displayName,role,active:true}]}`.
- `scopes.removeMember {scopeId,userId,requestId}` → `{removed:true}`; samo owner, sebe ne odstrani.
- `invitations.create {scopeId,recipientUsername,role,requestId,expiresIn?}` → `{invitation,token}`.
- `invitations.list {scopeId}` → `{invitations}`; samo owner, brez token/hash.
- `invitations.preview {token}` (javno) → `{invitation,scope:{id,kind,name},registrationAllowed}`.
- `invitations.accept {token}` (naprava) → `{scope}`; samo imenovani uporabnik.
- `invitations.revoke {scopeId,invitationId,requestId}` → `{revoked:true}`; samo owner.

`invitation = {id,scopeId,recipientUsername,role,expiresAt,acceptedAt,revokedAt}`.
Role povabila member/viewer; nikoli owner. Veljavnost privzeto 86.400, najmanj 60,
največ 604.800 sekund. Žeton naključen 256-bitni, v bazi samo hash, enkratna poraba.
Vnovični create z istim requestId vrne isto povabilo in `token:null`; skrivnosti ne
obnavlja. Za izgubljeno povezavo owner prekliče povabilo in ustvari novo. Sprejeto
povabilo se ne prekliče kot povabilo; za preklic dostopa uporabi odstranitev člana.
Replay sprejema ne ponovno podeli odstranjenega članstva. QR sme vsebovati le server
in začasni invitation token, nikoli trajnih poverilnic ali device tokena.

## Posamezni zapisi in konflikti

Zapisna pogodba 1 podpira `project`, `task`, `shoppingList`, `shoppingItem`.
Zapisi imajo lokalno ustvarjene UUID; povezave s starimi strežniškimi ID niso del pogodbe.

`record = {id,type,revision:int>=1,deleted:bool,payload:object|null,sequence:int,updatedAt:ISO8601UTC}`.
Payload je ustrezen obstoječi lokalni model **brez** polj `id` in `revision`:

- project: `title,description,area:"personal"|"home",createdAt,updatedAt`;
- task: `title,notes,projectId:UUID|null,dueAt:ISO|null,isCompleted:bool,createdAt,updatedAt`;
- shoppingList: `title,createdAt,updatedAt`;
- shoppingItem: `listId:UUID,title,quantity,isChecked:bool,createdAt,updatedAt`.

Vsa polja so obvezna; nepoznana polja se zavrnejo. Omejitve so UTF8 **bajti**:
title 300, description/notes 4096, quantity 100, celotni serializirani payload 8192;
scope name 200, displayName 100, deviceName 80. Datumi UTC z `Z`, sekunde in
izbirna decimalna natančnost 1–6 mest. Starš mora biti živ zapis istega
obsega in pravilnega tipa. Pred izbrisom starša odveži/izbriši njegove žive otroke.
`createdAt` se ob spremembi ne spremeni. Strežniški `record.updatedAt` je čas sprejema;
payload časi ohranijo izvorne uporabniške čase. Zapis ne spremeni tipa ali obsega.

`sync.push {scopeId,operation:{opId,recordId,type,expectedRevision,deleted,payload}}`
→ `{status:"applied",record,cursor,replayed:bool}`.

Create zahteva expectedRevision 0; update/delete natančno trenutno revizijo.
Delete ima payload null in ostane trajen tombstone. Tombstone se ne oživi:
izrecna lokalna kopija dobi nov UUID. Konflikt 409 vrne `details.serverRecord`
(lahko null); ni tihega zadnjega prepisovalca. Isti opId in isti kanonični zahtevek
vrneta shranjen izvirni rezultat; drug zahtevek z istim opId je idempotency_mismatch.
Rezultati, tudi konflikti ter `parent_missing`/`live_children` zavrnitve, ostanejo
shranjeni. Ti dve 422 zavrnitvi vsebujeta details.serverRecord za lasten dostopen
zapis (ali null), ne podatkov tujega starša. Rešitev konflikta dobi nov opId.
Odjemalec po push ponovno pulla in ne obravnava replay starega uspeha kot novejši zapis.

`sync.pull {scopeId,cursor:int>=0,limit?:100}` (največ 500)
→ `{records:[record],cursor,hasMore,scopeSequence}`. Stran ima tudi omejitev 512 KiB
serializiranih zapisov; tudi pri limit 500 ne preseže odjemalčeve 2 MiB meje.

Cursor je per-scope zaporedje. Vsak native write, sprememba članstva in pull zaklene
isto vrstico obsega (MySQL READ COMMITTED + FOR UPDATE; SQLite BEGIN IMMEDIATE) pred preverjanjem ACL.
Podatek, sequence in idempotentni rezultat se potrdijo atomarno; transakcije ne morejo
objaviti zaporedij v napačnem vrstnem redu. Pull bere trenutne zapise z sequence>cursor
v naraščajočem vrstnem redu. Če ni več strani, cursor doseže scopeSequence; sicer zadnji
vrnjeni sequence. Posodobitve med stranmi so ponovno vključene z novejšim sequence.
Tombstones in rezultati v1 nimajo avtomatskega čiščenja ali roka hrambe.

Vsak list/push/pull preveri aktivno napravo in aktualno članstvo. Owner/member pišeta,
viewer le bere. Odstranjeni član dobi permission_revoked, ne omrežne napake; ponovitve
in znani opId ga ne obidejo. Že prenesenih kopij na nepovezani napravi ni mogoče
izbrisati na daljavo. Odjemalec ohrani zavrnjene čakajoče spremembe za izrecno lokalno
obnovitev in jih nikoli ne pošlje pod drugim računom.

## Namestitev in preverjanje

Migraciji plugin schema 2/3 ustvarita samo familyhub_* tabele; 3 dopolni stabilne
identitete zgodnjega razvojnega schema 2, brez izbrisa razvojnih zapisov. Pred namestitvijo naredi
polno preverjeno kopijo; MySQL/MariaDB DDL ni transakcijska povrnitev. Paket nima
razvojne konfiguracije ali testnih poverilnic. CPanel ne potrebuje stalnega procesa,
SSH, Dockerja ali emaila za ta protokol. Spremembe nakupov ne pošiljajo pošte.
Kanboard core ne ureja native zapisov, zato zanj ni obljubljena spletna sinhronizacija.
SQLite/MySQL/MariaDB rezultate testov vodi dejanska predaja; ta pogodba ne trdi paritete.


Izbirna FCM priprava FamilyHub0.4: [push-api-contract.md](push-api-contract.md). Native capabilities dodajo `pushProjectId:string|null` in truthful `features.externalPush`; brez obeh enable flags/veljavne zasebne konfiguracije sta null/false. Device registration in inbox.group ne spreminjata record contracts ali pending v1/v2 byte-exact ACK pravil.


## Dopolnitev 0.5 — osebni prostor in račun

[account-api-contract.md](account-api-contract.md) določa auth.enroll, email verification/reset in izrecni personal.ensure. scopes.list brez includePersonal=true ostane združljiv s starejšimi odjemalci. HTTP telo je omejeno na1MiB; obstoječe shared payload meje ostanejo, private payload do524288 bajtov in pull strani512KiB. Schema9 je additivna, obstoječih outbox zapisov ne spreminja.

## Izbris samostojnega računa

FamilyHub0.6.0/schema10 doda self-hosted `account.deletion.preview/confirm/status` in splet brez mobilne aplikacije. Pogodba, razrešitve lastništva, natančna meja izbrisa/hranjenih tujih vsebin in odprte legacy omejitve so v [account-deletion-contract.md](account-deletion-contract.md). To ni dokaz store-ready/full-UGC skladnosti.

## Dopolnitev 0.7.0 — organizacije in zapisna pogodba 3

Capabilities dodajo `features.organizations`, `householdPeople`, `richPlanning`, `taskCosts`, `financePlanning`, `projectArchiving`; podprtost ne nadomesti aktualne naprave, članstva ali finančnega granta. `scopeKinds` vključuje personal/organization; `recordTypesV3` doda `householdPerson`. Organizacija in njen projekt sta **ločena obsega z ločenimi članstvi in finančnimi pravicami**. Organizacijsko članstvo ne odpre vseh projektov, projektno članstvo pa ne odpre organizacije ali sorodnega projekta.

Projekt pod organizacijo lahko ustvari samo njen owner: `scopes.create` s `kind:"project"` in `organizationId`. V isti transakciji nastaneta scope in en korenski project zapis z `id=scope.id`, revizijo 1 ter `area:"home"`. `projectRootId` ostane tudi po poznejši izrecni odvezavi organizacije. Drugi project zapis ali izbris korena je `project_scope_single_project`; task/event morata kazati na ta koren. Sprejet popravek naslova korena atomarno posodobi `scope.name`. Organizacijski obseg ne sprejema generic project zapisov (`organization_projects_use_scopes`). Stari samostojni obsegi brez korena obdržijo dosedanjo večprojektno vsebino; niso tiho pretvorjeni.

Arhiviranje obdrži zapise, ID-je, članstva in branje, zavrne pisanje podatkov z `scope_archived`, začasno zniža finančni write na read ter zviša scope sequence/finance access revision. Owner lahko še odstrani člana ali prekliče povabilo; novega povabila ni mogoče sprejeti v arhiviran projekt. Arhivirani obsegi ne pošiljajo opomnikov, e-pošte ali push dostav. Worker izbira aktivne obsege pred omejitvijo vrste in ponovno preveri arhiv pod zaklepom. Ob ponovni aktivaciji se že zapadli pending opomniki prekličejo, da ne nastane zaostali val opozoril.

`sync3.push {scopeId,operation,operationContractVersion?:1|2|3}` in `sync3.pull {scopeId,cursor,limit?}` obdržita sync2 envelope in odgovore. Privzeta različica operacije je 3. Vsa v2 polja ostanejo, v3 doda:

- project: `phases:[{id,title,milestone,startAt:UTC|null,endAt:UTC|null}],availabilityMinutes:int|null,availabilityPeriod:"day"|"week"|null`;
- task: `phaseId:string|null,estimateMinutes:int|null,availabilityMinutes:int|null,availabilityPeriod:"day"|"week"|null,timer:{elapsedSeconds:int,runningSince:UTC|null,runId:string|null},assigneePersonId:UUID|null,subjectPersonIds:UUID[]`;
- householdPerson: `name,notes,archived:bool,createdAt,updatedAt`;
- event/shopping: v2 polja brez novih načrtovalnih polj.

Faze imajo različne ID-je, največ 200; task phase mora obstajati v njegovem živem projektu. Fazo najprej odveži iz opravil, nato odstrani iz projekta (`live_children`). Ocena je 1–10.000.000 minut; razpoložljivost je par minutes/period, največ 1.440 minut/dan oziroma 10.080 minut/teden. Timer hrani največ 315.360.000 preteklih sekund; runningSince/runId sta oba null ali oba prisotna. Časovnik ne pomeni dokončanja opravila. Osebe so zapisi istega obsega, brez gesla, računa, članstva ali samostojnih pravic; account assignees ostanejo ločeni prejemniki obvestil. Arhivirana oseba sme ostati na obstoječem opravilu, ne sme dobiti nove reference (`person_archived`). Izbris osebe z živimi task/finance referencami je blokiran.

Sync3 pull stare task/project payload dopolni s praznimi fazami, timerjem brez teka, praznimi osebami in null načrtovalnimi vrednostmi. To ne prepiše shranjenega starega payload ali njegove revizije. Sync1/2 v razširjenem obsegu zavrneta pull/nove spremembe z `client_upgrade_required`; cursor se ne premakne in polja se ne odstranjujejo.

### Nespremenljive operacije in povezani strošek

Čakajoča v1/v2 operacija sme po nadgradnji potovati prek `sync3.push` z izvirnim `operationContractVersion`. Njeni `opId`, telo in expectedRevision ostanejo nespremenjeni; bridge izračuna **izvirni** hash `sync.push` oziroma `sync2.push` brez novega transportnega polja. Znan rezultat se preveri pred omejitvijo razširjenega obsega, vendar šele po svežem ACL. Nova operacija ne more prepisati zapisa novejše pogodbe. Razrešitev uporablja nov opId; po uporabniškem izbrisu redigiran replay ostane terminalen.

`sync3.pushTaskWithCost {scopeId,operation,operationContractVersion?:1|2|3,financeOperation,financeOperationContractVersion?:2}` zahteva task operacijo in finance2 entry istega obsega. `financeOperation.type` je financeEntry ali personalFinanceEntry glede na vrsto prostora. Odgovor doda `finance:{status,record,cursor,accessRevision,replayed}`. Obe operaciji, audit, inbox, opomniki in rezultati so ena transakcija; finančna zavrnitev povrne tudi opravilo. Trenutno članstvo/write **in** finančni write grant sta obvezna. Izgubljeni ACK se ponovi z obema izvirnima telesoma; compound hash vključuje celoten prvotni zahtevek. Konflikt in zavrnitve parent/live-children/person/validation/created-at/duplicate-reference/task-cost-date/currency se trajno shranijo po rollbacku in novem preverjanju pravic; avtentikacijske ali dostopne zavrnitve ne predpomnijo finančne vsebine.

Strošek je isti finančni zapis, ne kopija zneska v opravilu. Njegov `taskId` je živ task, `plannedAt` sledi task dueAt; odvezava/izbris opravila ohrani znesek in plačilno zgodovino. Strežnik pri običajni dovoljeni spremembi opravila samo izpelje ta datum/odvezavo pod istim scope zaklepom; ne razkrije finančnega payload ali spremeni plačila. Odjemalec pošilja starejše finančne operacije pred povezanim parom, paru ohrani ID-je tudi v kopiji in spor rešuje za obe polovici skupaj. Ohranitev lokalnega para potrebuje izrecen finančni pregled; izbira strežniške različice zavrže obe povezani spremembi.

Schema 11 additivno doda organization/root/archive in zahtevano record pogodbo na scope ter finance contract različico na policy/zapis. Obstoječe identitete, seje, zapisi, denar in rezultati operacij ostanejo. Lokalna odjemalčeva schema 6, osebni JSON 4 in prenosna kopija 3 so ločeni formati, opisani v [izvedbenem dnevniku](../UPGRADE_IMPLEMENTATION.md); ne potrjujejo namestitve server schema 11. Lokalne integracije zajamejo izolirane organizacije, en koren, osebe, arhiv, compound rollback/replay, stare hash mostove in policy2 izbris. Dejansko nadgradnjo gostovanja in fizično dostavo je treba potrditi ločeno.
