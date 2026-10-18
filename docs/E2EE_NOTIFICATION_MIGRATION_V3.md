# Capture3: ohranitev obvestil in strukture

Ta zapis določa pregledano izvorno pogodbo. Namestitveni del za obvestila še ni
v celoti povezan; sam codec ne omogoči končnega prehoda. Javni capability/cutover
ostaja zaprt. Nobene produkcijske vrste, pošte ali potisne dostave ne ustvarjamo.

## Lastno potrdilo obvestil

Glava ima natanko polja:

```
{version:3,serverId,migrationId,captureId,accountId,sourceInventoryRoot,
 archiveManifestHash,coldParityProofHash,authorDirectoryHeadHash,
 transformCount,sourceCounts:{reminder,inbox,preference,inboxState},transformRoot}
```

`sourceInventoryRoot` je točen podpisani SEALED Capture3 root lastnega zajema.
Vse izbrane lastne vrstice vsake vrste imajo natanko eno preslikavo; vsota štirih
števil je `transformCount`. Nepreverjeno strežniško število ni dokaz popolnosti.
`coldParityProofHash` nastane iz dejanske hladne primerjave pred potrdilom in ne
vključuje tega potrdila ali njegovega poznejšega directory eventa. Tako ni cikla.
Končni cutover pa mora vezati potrdilo in vključeni event.

Pred potrdilom `verify3` veže `selectionRoot`, ne `transformRoot`:
`SHA256('JivieNotificationSelection/v3\n' + canonical(common6) + '\n' +
sortedUniqueLeafDigestsVsakZNewline)`, kjer je `common6` natanko
`{version:3,serverId,migrationId,captureId,accountId,sourceInventoryRoot}`.
Tudi prazen izbor vsebuje header in newline. Isti točen izbor listov se pozneje
preveri pod podpisanim `transformRoot`; SQL `selection_root` ni nadomestilo za
ponovni izračun podpisanega toka. Noben leaf/use ne vsebuje certifikata,
`coldParityProofHash` ali posredne odvisnosti od njiju.

Notranja podpisana transformacija uporablja domeno
`JivieE2EE/notificationTransform/v3\n` in natanko body:

```
{version:3,operation:'crypto2.migration.notificationTransform',serverId,
 accountId,deviceId,migrationId,captureId,sourceInventoryRoot,bindingId,kind,
 canonical,authorDirectoryHeadHash,useAuthorization:null|proof}
```

Signer se razreši samo iz preverjenega lastnega celotnega directory prefixa,
vezanega na točen account/directory/device. Sveža transformacija zahteva trenutno
odobreno napravo. Zgodovinski podpis preklicane naprave je sprejemljiv le kot
točna že dokončno overjena transformacija pod lastnim cert/event/cutover dokazom;
ni nova pravica izdaje. Poljubni javni ključ klicatelja ni identity evidence.
Različne točne directory reference med resumable transformacijami so dovoljene.

`transformHash = SHA256(UTF8('JivieNotificationTransform/v3\n') +
canonical(celotna avtorizacija vključno z Ed25519 podpisom))`, šele po preverjanju
podpisa/konteksta. Ne objavimo ločenega SHA nizkoentropijskih nastavitev,
legacy payloadov ali reminder fingerprintov.

Leaf ima natanko `{bindingId,kind,transformHash,useProofHash:null|SHA}`.
`useProofHash` je dovoljen samo pri reminderju in veže podpisani recipient-free
use kontekst, exact target proof/generation/lifecycle/project barriers ter prvotno
consumed/cancel/read stanje. Leaf digest je
`SHA256('JivieNotificationTransformLeaf/v3\n' + canonical(leaf))`.

`transformRoot` je SHA256 toka
`'JivieNotificationTransforms/v3\n' + canonical(header brez transformRoot) + '\n'`
in strogo naraščajočih unikatnih lowercase leaf digestov, vsak z `\n`.
Bralnik preveri celoten točen count in root. Strani vsebujejo samo opaque digeste;
editor dobi samo potreben exact use proof in inclusion kontekst, ne zasebnih
transformacij, podpisov, odmikov, drugih prejemnikov ali arhivskih vsebin.

Token je SHA256:
`'JivieNotificationMigrationToken/v3\n' + canonical({version:3,serverId,
accountId,migrationId,captureId,sourceInventoryRoot})`.
Own `account.migrationAttest`, domain `content`, veže hash celotnega podpisanega
potrdila in ta token. Vključitev se preveri v celotnem lastnem zaupanja vrednem
prefixu; SQL status sam ne podeli avtoritete.

## Atomska namestitev

Reminderji, inbox/read/dedupe, preference/state in že obstoječi push jobs se
preslikajo šele v končni skupni SQL transakciji. ID-ji, read/sent/delivered,
revision/sequence, odmiki in veljavne lease/dedupe lastnosti se ohranijo.
Pred commitom ni novih jobs. Stara pending/processing push opravila po prehodu
uporabijo generično crypto2 predstavitev, brez iskanja starega plaintext naslova.
Sent/consumed se ne dostavi ponovno, cancelled se ne oživi. To je podpisan
migration baseline, ne ponarejen stari `reminders.put`.

Čarovnik mora posebej prikazati nadaljnje minimalno časovno razkritje pri
oddaljenih opomnikih. Nova odpoved preklicuje baseline z exact predhodno
inclusion vezjo. Hladna obnova po preklicu naprave ne ustvari nove pravice izdaje.
Neznan povsem zamolčan novejši cancel ostaja ista meja latest-prefix protokola;
znanih cancel/revocation/lifecycle floors ni dovoljeno znižati.

## Strukturni del

Za vsak scope ima obvezna zasebno preverjena parity sekcija:

```
{version:3,scopeId,membershipHeadHash,scopeMetadataProofHash,lifecycleHash,
 sourceBindingCount,sourceCommitmentRoot,structureHash}
```

Source root pod domeno `JivieMigrationStructureSources/v3\n` veže header
`{version:3,serverId,migrationId,captureId,sourceInventoryRoot,scopeId}` + `\n`
in strogo urejene točne `{bindingId,sourceCommitment}` + `\n`.
`structureHash` pod `JivieMigrationStructure/v3\n` veže isti header, `\n` in
sekcijo brez structureHash. Ni raw javnega hasha scope vrstice, policy/grantov ali
account povezav. Vsaka izbrana aktivna strukturna vrstica mora biti razvrščena
natanko enkrat; neznana tabela ni dovoljenje za izpust.

Notranji PHP helper primerja account/user identity resolution, veljavnost
policy/grantov in trenutni podpisani effective roster/access/device snapshot ter
lifecycle CAS. ScopeMetadata mora imeti dejanskega manager avtorja. Dejansko
primerjavo dešifriranih legacy policy/parent/account povezav s transformirano
vsebino opravi hladni klient, ne strežnik brez DEK. Če zahtevan član ni
crypto-ready, komponenta čaka na tega člana; ne izpustimo ga iz rosterja.

## Staging in namestitev obvestil

Podpisani `crypto2.migration.notifications.stage` ima točno
`{migrationId,captureId,sourceInventoryRoot,transforms}`. Največ 20 elementov in
512 KiB, vsak `{authorization,previousTransformHash:null|SHA256}`. Inner
`notificationTransform` je zgornji podpisani v3 body. Izbor različice za isti
binding uporablja CAS na prejšnji transformHash; vsi stari podpisi ostanejo
nespremenljivi. Končni certifikat zamrzne izbor. Preklicana naprava ne sme
izdati novega transforma; zgodovinsko veljavnost daje samo dokončna vključitev
v certifikat, own account-log in cutover.

`canonical` ima za posamezen kind točno naslednja polja:

```
reminder: {id,scopeId,targetType,canonicalTargetId,targetId,domain,
 targetRevision,targetRecordProofHash,scheduleRevision,consentGeneration,
 scopeLifecycleHash,projectBarrier,remindAt,remindEpoch,revision,state,
 scheduleMode,offsetMinutes}
inbox (rowKind='inbox'): {rowKind,id,eventKey,scopeId,category,kind,audience,actorAccountId,targetType,
 canonicalTargetId,targetId,targetRevision,groupKey,createdAt,readAt,revision,
 sequence,inApp}
inbox (rowKind='delivery'): {rowKind,inboxId,state,attempts,nextAttempt,
 expiresAt,leaseToken,leaseUntil,sentAt}
inbox (rowKind='push'): {rowKind,inboxId,state,attempts,nextAttempt,
 expiresAt,leaseToken,leaseUntil,sentAt,deviceId,registrationRevision,tokenHash}
preference: {scopeId,category,settings}
inboxState: {sequence,visibilityRevision}
```

Vsi originalni own reminder/inbox ID-ji, revision/state/read/delivery/dedupe
ostanejo. Target ID postane deterministični wire UUID glede na točen tip in
kanonični target. Inbox kind dobi prefiks `crypto2.`; prikaz in transport sta
generična. `groupKey` ostane ista identiteta skupine, ne novo obvestilo.
Preference ohranijo točne štiri bool nastavitve, tudi izrecni false.
Vsaka lastna `inbox`, `delivery` in `push` source vrstica dobi svoj binding in
leaf. `sourceCounts.inbox` in `transformCount` štejeta bindings, ne samo števila
vidnih obvestil. Manjkajoč, podvojen ali zamenjan job blokira popolnost. `membership`
je samo notification routing na account UUID, nikoli namišljen business record.
Izginuli target ohrani kanonični routing hint; ta ne overi ali obnovi vsebine.

Za pending opomnik je potreben točen staged target proof in aktualna podpisana
scheduleRevision/consentGeneration/lifecycle/project ovira. Primerjava starega
targetFingerprint ostane samo prehodna legacy-side preveritev in v zasebnem
šifriranem cold witnessu; ne postane javni digest. Neaktivni zgodovinski intent
brez targeta ima targetRevision 0 in null proof/barriers; nikoli ne ustvari use
dovoljenja ali joba. scheduleRevision je vseeno naključni UUID brez časovnega
fingerprinta. Čas mora biti točno originalni remindAt/remindEpoch, state/revision
se ne popravljata potiho.

Podpisani `migration.schedulingUse` uporablja domeno
`JivieE2EE/migrationSchedulingUse/v3\n` ter običajna polja scheduling use z
`version:3`, `operation:'crypto2.migration.schedulingUse'` in dodatnimi
`migrationId,captureId,sourceInventoryRoot,bindingId,originalState`. Veže točen
staged target proof, generation/barriers in prvotni reminder ID. Za prvotno
časovno neomejeno dovoljenje je `expiresAtEpoch:null`; ne izmišljamo roka.
Namerno poteklo pending dovoljenje se zavrne pred katerimkoli učinkom. Pred
certifikatom je možna izrecna nova CAS transformacija in ponovna cold primerjava;
po nespremenljivem certifikatu je potreben izrecen nov povezan zajem, stari
reminder/source ostane ohranjen. Poteklo delivered zgodovino ohranimo kot
zgodovino brez aktivnega dovoljenja in brez nove dostave. Committed bralnik mora
ločeno preveriti končno cutover vključitev in historical signer prefix;
precommit fresh signer kontrola ni historical recovery dovoljenje.

Interni API helperja je `stage(params,actor,proof,command,
captureSourceBinding,stagedCaptureTarget)`,
`stagedCoverage(migrationId,captureId,sourceInventoryRoot,actor,captureSourceBindings)`,
`bindingArtifact(...,bindingId,actor)`, `certify(...,verifyPrerequisites)`,
`anchor(...)`, `coverage(...,captureSourceBindings)` in
`prepareInstall(exactAnchoredCoverage,actor,captureSourceBindings,
captureSourceBinding,stagedCaptureTarget)`.
Install je dovoljen samo znotraj končne zunanje globalno zaklenjene SQL
transakcije po vseh source/head/cold/cert CAS; ni dispatchable normal operation.
`prepareInstall` vrne enkratno closure. Koordinator najprej pripravi vse portions
in vse druge source CAS, šele potem izvede closures v isti transakciji/locku.
Apply več ne kliče source resolverjev. Stari reminder dobi inertni worker marker,
novi canonical row pa ohrani izvirno stanje. Inbox spremeni samo kind/wire target;
jobs/preferences/global counter vrstice ostanejo brez novega pošiljanja ali lease.
Global inbox baseline je immutable lastna opazovana vrstica iz capture.prepare;
resolver dovoljuje samo veljavne monotone live counter napredke. Namestitev jih
ne prepiše z zamrznjeno starejšo vrednostjo.
Coverage mora vrniti točen cert hash/root/count/kind counts in account-log event
vključitev. Prazen lastni nabor prav tako potrebuje podpisan certifikat.
Ti API-ji še niso povezani z dokončno namestitvijo in niso dokaz cutover parity.

Ozki helper test `crypto-notification-migration-stage-v3.php` preverja dejanski
V2 inbox dispatch, own directory/cert, rollback ter pending/delivered/cancel
baseline. Source/parity callbacks v tem testu so sintetični. Dejanski Capture3
iterator, FILE cold controls in končni component commit še zahtevajo skupen
vertikalni test. Lokalni selection/StructureSet vektorji niso ta dokaz.
