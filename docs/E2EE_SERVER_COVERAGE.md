# Strežniška pokritost E2EE

Stanje izvora: **18. oktober 2026**. Matrika opisuje povezane strežniške in
odjemalske poti. Ni dovoljenje za namestitev, dokaz javne izdaje ali trditev, da
je vsa trenutna koda že prestala zaključni odjemalski del. Žive konfiguracije niso vključene
s tem dokumentom. P0 neodvisni kriptografski pregled in P8 namestitev/fizično
preverjanje ostajata ločena odprta koraka.

»Izvorno povezano« pomeni, da običajna aplikacijska pot doseže navedeni adapter
in handler. Čakanje na resnično manjkajoč prispevek, izrecno preverjanje identitete,
odobritev drugega upravljavca ali obnovitveni dokaz je varnostno stanje te poti.
Ni nadomestilo za dejanski preizkus uspešnega zaključka. Predhodni HTTP in PHP
rezultati spodaj ne potrjujejo samodejno poznejših sprememb izvora.

Zaključeni PHP del ima **55 PASS zbirk na vsaki SQLite, MariaDB in MySQL**.
`final-matrix/aggregate-165-pairs.json` hrani 165 unikatnih parov z exact log in
source hashi; ne seštevamo prekrivajočih assertov in čistih vektorjev ne
predstavljamo kot SQL dokaz na treh pogonih. Inline31 je PASS, retained povabilo
in zaščita obnovljenega lastnika sta potrjena z nadaljevanji istega stanja
36b/38/39/40/41. Relokacija43–46, združeni47→61 in use3/generacija64→65
imajo zaključene zahtevane trditve prek vezanih nadaljevanj istega stanja, ne
novega svežega celotnega teka. Celotni Flutter66 je razkril regresije, zaključene s prizadetima ponovitvama69/70;
analiza ima0 error/0 warning in510 info. Točne source vezave in preostala vrata vodi
[izvedba](E2EE_IMPLEMENTATION.md#dokazi-in-končno-preverjanje). Poznejši
invitation in generation PHP popravki imajo ločen prizadeti tristranski dokaz;
ni trditve vseh165 parov na zadnjem izvoru.

## Povezane uporabniške poti

| Pot | Strežniška meja / trajni dokazi | Odjemalski priklop v izvoru | Izvajalni dokaz in preostala meja |
| --- | --- | --- | --- |
| Inicializacija, naprave, FILE obnova, izgubljena datoteka | `NativeCryptoV2Service`, `NativeCryptoDirectoryV2`; podpisan append-only imenik, izpeljani snapshot in ovoji ključev | `AccountCryptoV2Workflow`, preverjeni imenik, ProtectionReady/obnovitveni UI; nova tuja identiteta zahteva neodvisno preverjanje | Retained36b/38/39/40/41 pokrije required povabilo/restart/admission, novo lastnikovo FILE obnovo in izrecni zaščitni prehod; to je dokaz nadaljevanj istega stanja, ne nov celoten tek. |
| Nov prostor in osebni kanonični prostor | `NativeCryptoScopeCreationV2`, `scope_origins`; splošni SQL metapodatki in podpisan prazen NEW izvor | Trajen creation intent → genesis → vsi ovoji → šifrirani `scopeMetadata`; star osebni prostor zahteva migracijo | Creation/key-contribution zbirke in predhodni HTTP. Pripravljalni legacy kandidat ne postane običajna READ/WRITE avtoriteta. |
| Nov otrok in finančna topologija starša | `NativeCryptoFinanceTopologyCreationV3`; isti aktivacijski SQL commit preveri normalen podpisan parent metadata successor. Javno shranjena notranja aktivacija vsebuje samo hash zasebnega companion bundle | `CryptoFinanceTopologyCreation`, `ScopeCryptoManager` in običajni create router; šifrirani `financeTopology` ima generation/previousRoot/opaque child tokens | Izvorno povezano. Brez nezaščitenega vmesnega stanja po nastanku otroka in brez parent UUID/proof razkritja bralcu samo otroka. Končna matrika/representativna integracija še ni zaključna trditev. |
| Članstvo, lastništvo, ključi in neodvisni financer | `NativeCryptoScopeV2`, `NativeCryptoKeyContributionV2`, `NativeCryptoFinanceContributionV2`; kandidati, zaprtja, ovoji, neodvisni podpisi iste osnove | `ScopeCryptoManager`, key/finance contribution strani in preverjanje identitet; prihodnji lastnik/financer pripravi lastni novi DEK | Predhodni tristranski HTTP je preveril, da stari upravljavec nima novih DEK. Zaključena PHP matrika je PASS; odjemalski zaključni dokazi ostanejo ločeni. |
| Odstranitev člana | `NativeCryptoAccessV2` typed `memberRemove`; celoten prizadeti komponent, exact accountId, nova glava/ključi vsakega upravljavca | `CryptoBusinessStructure` → `CryptoAccessCoordinator`; trajen reviewed action, individualne odobritve in resume/finish v routerju | Predhodni dejanski removal/lost-ACK → poznejši ordinary successor → restart/exact retry je uspel. Končni izid se preveri na izvirnem aktiviranem predniku, brez vračanja starega rosterja. |
| Lastni odhod člana | `NativeCryptoLeaveV2`; podpisan trajen leave request, cancel in končni CAS povezane manager closure. Lastnik mora prej prenesti lastništvo | Request/pending/cancel/outcome prek structural adapterja in odobritev preostalega upravljavca; minimalen lasten izid ostane dosegljiv po izgubi READ | Predhodni removal/self-leave HTTP. Odhod ni prikazan kot takojšen izbris pred dejansko izključitvijo. Star request ne odstrani člana po izstopu in ponovnem vstopu. |
| Vodje in politika dostopa | `NativeCryptoAccessV2`: prepare → omejene strani prizadetih delov → podpisan scopeConsent/glave → approve → atomska aktivacija. Resulting descriptor vsebuje učinkovite vodje samo za organizacijo; policy3 ne oživi dormant leader vrstic | `CryptoBusinessAccessActions` podpira `scopes.setLeader`, `accessMigrationPreview/Apply`; settings/recovery Approvals pokaže prihodnja pravila, roster, ključe in zaključek istega action ID | Policy/access PHP zbirke v zaključeni matriki so PASS. Obstoječi structure-successor helper je izbiren, brez dodatnega obveznega teka v zamrznjenem katalogu. Wrapper je izvorno povezan. |
| Posledice policy3 za povabila | Podpisan prepare requestId veže complete scoped invitation consequence count/digest; child consent veže lastno posledico; final CAS preveri isti logical set pred preklicem | Root in child approver preverita dovoljene lastne typed ID-je proti scope tokenu/digestu; tuji deli ostanejo opaque. Novi/spremenjeni set zahteva nov pregled | Izvorno povezano. Installed legacy bridge šteje samo skozi dejansko trenutno canonical povabilo; consumed/revoked se ne prekliče znova. |
| Ime in opis prostora | Navaden podpisan content record CAS za šifrirani `scopeMetadata`; SQL ime ostane splošno | Obstoječi metadata action v `CryptoBusinessSession` ohrani canonical ID/revizijo in preverjeno lokalno projekcijo | Source-ready; običajni content editor nima management obvoda. Zajeto v normalnem sync in končni matriki. |
| Archive/unarchive, tudi tuj otrok | `NativeCryptoLifecycleV2`; podpisan prepare, child observations/consents in atomski final z intent hashom; lastni/podedovani archive sta ločena | `CryptoBusinessLifecycle`; skupna Approvals pot dejansko kliče pending/approveParent in pokaže preverjeni scoped pregled | Lifecycle PHP in predhodni cold testi. Zunanji child approver UI je priključen; manjkajoča resnična odobritev ostane vidno čakanje, ne izpuščen otrok. |
| Običajni sync, zgodovina in compound finance/task-cost | `NativeCryptoStorageV2`; record proof + batch commitment, exact reference tuples, current ACL/head CAS, scoped atomic projection groups | `CryptoSyncRepository`, `CryptoBusinessSession`, history/lineage preverjanje, dešifrirane domenske projekcije; opuščena vrstica ali notice ne promovira floora | Predhodni storage/task-cost/payment HTTP, vključno z accepted-lost-ACK/source advance/FILE obnovo. Zadnji združeni Capture3 predstavnik trenutno še nima zaključnega rezultata. |
| Kanonični ID in logical revision | `NativeCryptoRecordAddressV2`; signed identity in AEAD format2; neodvisne stare tabele imajo ločene wire ID-je | Enaka canonical identity v producerju/prejemniku; migracijski/relokacijski revision offset pride samo iz preverjene purpose provenance, nikoli iz obnovljenega SQL | Medjezikovni vektorji in predhodne projekcijske zbirke. Navaden NEW crypto revision1 ostane ločen od certificiranega starega baseline. |
| Finance policy enable/grant | `NativeCryptoFinancePolicyV2`; typed intent, policy/grant stream hash in revision CAS, atomski prehod s ključi; structural consent veže resulting policy | `CryptoFinancePolicyActions`, manager/contributor review, Session delivery guard in production router | Predhodni production repository HTTP je preveril policy3 effective role, izgubljen activation ACK in poznejšo glavo. Celoten raw dormant grant stream se ohrani; hash baseline ne pomeni normalizacije. |
| Finance4 projektne izbire računov | `NativeCryptoExportV2`, `NativeCryptoAccountChoiceExportV2`; izrecni complete-selection offer, manager endorsement in target writer materialization | `CryptoFinanceAccountChoices`, skupni Approvals review/finish; source finance READ issuer, target-only/owner-NONE manager in target FINANCE WRITE materializer imajo ločene naloge | Izvorno povezano. Združeni split-role Capture3 predstavnik še teče/čaka rezultat; helper ali stare per-account export zbirke tega ne nadomestijo. Manager brez finance READ vidi fingerprint/count/hash, ne skritega salda ali seznama imen. |
| Povezana zasebna plačila | Podpisani payment source/export in lastni private account/cash proofi; source in zasebni učinek nista podvojeni knjižbi | Payment adapter/catch-up/factory, isti originalni namen ob refund/source advance/lost ACK; zasebni cilji ne dodajo parent/source identitet v javne reference | Predhodni dejanski FILE/new-login/blank-SQL payment catch-up je uspel z zgodovinskim opaženim checkpointom in sibling dokazom. Končna matrika ostaja ločena. |
| Zgodovinski export signer | `crypto2.exports.evidence.directory`; samo exact referenced cert/delegation/bridge prefix ob trenutnem target finance READ | Scoped history verifier primerja originalni proof/closure; brez globalnega peer pina ali poljubnega latest directory taila | Predhodne tri-DB export evidence zbirke. Referenced prefix dokazuje vključitev, ne odsotnosti nevidnega poznejšega preklica. |
| Preglednice | `NativeCryptoTableV2`, 90 s lease in normalen batch s privatnim lease dokazom | Document adapter, trajen lokalni osnutek/konflikt, šifrirani večji payload in običajen delete lifecycle | Storage/table zbirke in predhodne dokumentne poti; zaključni odjemalski dokaz ni nadomeščen s PHP matriko. |
| Priloge in slike Idejnika | Blob begin/chunk/complete/get/abort, kvote in ciphertext manifest; source/migration/relocation purpose so ločeni | `CryptoBusinessDocuments`: nadaljevanje prenosa, hash/MIME/dimenzije/decoded image preverjanje; embedded assets so unikatni po SHA z enakim descriptorjem | Predhodni dejanski attachment/Idea FILE cold in moderation image HTTP. Zadnji združeni predstavnik ponovno preverja navaden committed blob/Idea dostop. |
| Projektno deljenje inline → own-child | `NativeCryptoProjectRelocationV2` in ločeni graph/staging/publication/audit/notification helperji; celoten dovoljen legacy graf, dvoprehodno preverjanje, atomski source tombstones + target physical1 + live parent topology companion | `CryptoBusinessProjectRelocation` povezuje obstoječi preview/apply; target setup, dokumenti, audit, opomniki, normalni Session/bootstrap in logical lineage so priključeni | Relocation43 je potrdil >32 graf, final commit/exact lostACK, strošek21, vseh21 audit vnosov/raw float, celotni attachment SHA in parent topologijo. Target-only Join/admission je opravljen; skupni rok je prekinil prvi target CONTENT pull, zato bralni/FILE zaključek še ni PASS. |
| Relokacijska avtoriteta in ohranjena finančna zgodovina | Obe scoped publikaciji vežeta exact proposal/activation proof, record/audit/notification roots in dedicated own `account.projectRelocation` dogodek. Target genesis marker je podpisan, navaden batch purpose tag zavrne | Opaque finalized genesis capability, scoped signer prefixes in target-only invitation admission; target audit jasno označi manager-attested relocated history, ne originalnega avtorjevega podpisa | Relocation43 je preveril strošek/logical revizijo21, vseh21 audit vnosov z actor/time in neznanimi raw vrednostmi ter blob/topologijo. Originalni signed audit ostane pri source; target-only bralni/FILE zaključek istega predstavnika še čaka. |
| Celoten izbris prostora | `NativeCryptoScopeDeletionV2`; private graph certificate, minimalen signed public header, own scoped leaves/digest stream in isti own companion event. Parent topology successor je zaseben atomski companion, kjer je potreben | `CryptoBusinessDeletion`, normalni deletion preview/confirm/router ter retained head/directory/evidence preverjanje po izbrisu | Predhodni dejanski production route: accepted-lost-ACK → new login/blank SQL/original FILE po izbrisu, brez secure scope floora, trenutne projekcije ali globalnega pina. Končna aktualna matrika še sledi. |
| Inline izbris projekta | `NativeCryptoInlineDeletionV2`; prepare/stage ≤32 proofov/final; ALL graph/proof validation pred učinki, final scoped publication + own event, mandatory `inlineDeletion` tag | `CryptoBusinessInlineDeletion` in normalni deletion router; final verifier/projection/history propagacija je priključena | Inline31: celoten 36-record/two-batch/final/lostACK/scoped-proof/current-read predstavnik PASS. Ta izid ne obljubi fizičnega izbrisa vseh kopij. |
| Odstranitev računa brez E2EE ključev, tudi Kanboard admin | Policy4 `NativeCryptoAccountDeletionV2`, `NativeCryptoAccountTombstoneV2`, pseudonymous FK carrier; Native auth/database in core user-delete hooki ohranijo javno signed provenance drugih članov | Login-only password/OTP step-up preview/confirm, trajen operationId/receipt; lost-key UI je pred crypto startup gate. Preserved-readonly ni lažen owner podpis ali obljuba cryptoerase | Predhodni izolirani FK/sekvenčni deletion testi in dejanski no-key delete → normalni surviving-reader Dart read/history so uspeli. Prizadet aktivni migration fence ostaja iskreno `canDelete=false`; novega snapshot/invalidation podsistema ni. |
| Opomnik: nova consent/use/cancel pot | `NativeCryptoNotificationV2`, `NativeCryptoSchedulingUseV2`; exact put/use + own account.scheduleUse sta atomska. Raw-due preview fallback je odstranjen | `CryptoBusinessNotifications`, `CryptoSchedulingUse`, normalni router/outbox; date disclosure samo iz preverjene tarče, latest complete own prefix in lifecycle/consent-generation ovir | Producer in receiver sta izvorno povezana. Običajni opomniški HTTP/PHP dokazi obstajajo; zadnji use3/routing predstavnik še čaka rezultat. Dostava ne izdela novega soglasja ali ponovne dostave. |
| Migrirani in relokacijski opomniki | Notification cert3 + own attestation + exact scoped final control; relokacija doda manager-signed routing transformation, originalni put/use in state/lease/dedupe ostanejo nespremenjeni | `CryptoMigrationNotificationRead` in `CryptoProjectRelocationNotificationRead`; normalni list/read, historical signer, exact consent reuse in own withdrawal. Withdrawal uporablja own proof/own prefix brez target READ ali nove vsebinske/floor avtoritete | Use3 pending/delivered + FILE read + minimal cancellation/lost-ACK probe je pripravljen, še brez runtime PASS. Predhodni installer helper uporablja sintetične source/parity callbacke; ni final Capture3 vertikala. |
| Utrip, read/preference, generični push/mail | `crypto2.inbox.*`, canonical inbox/jobs in post-lock worker gates; migracija ohrani pending/processing/sent/read/dedupe/lease/attempt. Omejena discovery ne strada za fenced opravili | Običajni Utrip adapter; članstvo ima typed routing brez izmišljenega recorda, odsotna tarča ima retained unavailable prikaz; naslov se vzame samo iz preverjenega lokalnega plaintexta | Predhodni zajemni worker/inbox testi brez pravega SMTP/FCM. Globalni inbox counters se združijo samo z izrecnim monotone max pravilom; druge komponente/read flags se ne prepišejo. |
| Recovery/reset varnostna pošta | `NativeSecurityMailQueue`; allowlisted generično obvestilo na ob dogodku preverjen naslov, tudi po naslednjem email identity revision | Obstoječi email/recovery tok; aktivni user/tombstone, starost/attempt/dedupe varovala ostanejo | Ozki synthetic capture testi brez SMTP. Obvestilo ne vsebuje ključa, tokena, novega naslova ali vsebine. |
| Nova in ohranjena legacy povabila | `NativeCryptoInvitationV2`, invitation/mail helperji; fhi4 admission in cert3 bridge za native legacy invitation/mail. Old token odpre le metadata envelope, ne ključev ali SQL članstva; canonical mail continuation ohrani isti job/state/lease | Obstoječi wizard/registration/acceptance, exact signed original acceptance za consumed restart, retained bridge evidence in neodvisna creator/manager identiteta | Retained36b/38/39/40/41 pokrije prvotna zahtevana merila s checkpoint nadaljevanji; ni novega celotnega teka. Zasebna same-root descriptor pot ostaja omejena na128 glav/16MiB in prednike brez policy proof; manjkajoča zgodovina zahteva izrecni pregled. Numeric Kanboard project invitations so ločena legacy pot in niso izmišljeno preslikana v E2EE UUID. |
| Prijava vsebine | `NativeCryptoModerationV2`, `NativeCryptoModerationDisclosureV2`; pregledano minimalno razkritje, exact source CAS in točno pet digest-receipt write operacij | `CollaborationRepository` preview/submit → `CryptoBusinessModeration` → strict queue/Session/card matcher; exact accepted receipt se poravna pred ponovnim asset/target branjem | Predhodni actual task + embedded-image report/lost-ACK/read-loss retry je uspel brez novega prenosa/razkritja. Card je samo dokaz lastnega izida, ne podpisna ali vsebinska avtoriteta. |
| Moderacijska razpoložljivost in blokada člana | `NativeCryptoModerationAvailabilityV2`; exact CURRENT proof CAS, ohranjena signed history, notice in zaprti evidence-only izjemi; finance removal je zavrnjen | Prejemnik ohrani unavailable/pending in preveri reference/predecessor chain; notice ali cursor ne zaključi check-pointa. Block zahteva resnično fresh head/DEK rotacijo pred novimi zapisi | Predhodne tri-DB availability/tombstone zbirke. Clean successor ali signed tombstone lahko potrebuje blocked predecessor samo za preverjanje; blokirana vsebina s tem ne postane prikazana/current. |

## Capture3 in zaključek migracije

| Korak | Povezani izvor in avtoriteta | Izvajalni status |
| --- | --- | --- |
| Discovery/capture/fence/raw archive/datoteke | `NativeCryptoMigrationV2`, file exporter, account-private captures in exact typed rows. Capture3 binding/root je blinded; fizični file binding je ločen od uporabe iste datoteke v več elementih | Predhodni dejanski large task/physical attachment/posted-cost in global inbox advance cold preizkusi. Nova kombinirana trenutna koda še potrebuje zaključni rezultat. |
| Struktura in minimalni parent/scope context | `NativeCryptoMigrationStructureV3`, `NativeCryptoMigrationStructureContextV3`, FILE `ScopeBaseline`/`StructureControl`, source certificate in own anchor, card + contributor countersign | Lastni CONTENT ima celoten policy/grant/leader baseline; nonowner dobi samo podpisan minimalni kontekst. Parent source proof je neodvisen od full verify3, zato ni parent/child/finance cikla. Predhodni owner-NONE/nonmanager-READ in child-only dokazi; zadnji production multiowner wizard je izvorno povezan. |
| Canonical stage, audit, receipt/local intents, notifications, invitations | Canonical in companion proofs imajo mandatory signed `metadata.migrationOrigin`; ordinary batch tag zavrne. Pet cold kontrol preveri celoten pripadajoči binding set; lokalni stari zahtevki ostanejo karantenski dokazi | `CryptoMigrationPipeline` in običajni wizard povezujeta dejanske producerje, FILE cold business primerjavo, verify3 ter cert/own anchor. Prejšnji full FILE verify3 in cert/domain mejniki so uspeli; ne trdimo, da vsak poznejši izvor že ima isti PASS. |
| Domain contributions in final scoped activation | Podpisane complete assignments, contributor roots/control links, manager domain certs in own anchors; signed activation veže exact content/finance cert in pet scoped control vrst | Owner-NONE manager vidi opaque finance prispevke, ne private cert header/source counts ali tuje arhive. Pričet zadnji združeni frozen predstavnik še ni končni dokaz. |
| Atomic commit in navaden postcommit reader | `commit3` ponovno preveri complete source/graph/receipt/target/head/lifecycle CAS in vse fresh contributor/manager meje; prepare-all/one-shot installer, SQL ciphertext kopije in trajni scoped origin proofs | Združeni30 s 35 dodatnimi zapisi potrdi commit/exact lostACK in popolno svežo FILE/blankSQL obnovo; ločeni bralni29 potrdi ordinary audit/blob/Idea. Končni celotni združeni35 ter Flutter/analiza še čakajo. |
| Menjava naprave pred končno objavo — A | `NativeCryptoMigrationGenerationV3`: fresh draft-only genesis/ključi, podpisan complete context in own-log approvals; atomska zamenjava pripravljalne generacije ohrani vse stare vrstice/podpise/ključe/zahtevke | `CryptoMigrationWizard` → `CryptoMigrationGenerationPage` → coordinator.generation/adoptGenerationSuccessor → exact saved-proposal pipeline publish. Source-reviewed; dogovorjeni dejanski A/B probe še čaka izvajanje. |
| Menjava naprave po končni objavi — B | Isti stari head/epoch/ključi/source/targets/activation bytes; vse zahtevane fresh current-DS approvals. Historical-key izjema obstaja le za exact indexed proofs v zaklenjenem final commit contextu, z `finally` resetom | `resumeAcceptedCommit` nadaljuje popoln že podpisan publication set. Manjkajoč prvotni podpis/endpoint ali izgubljeno potrebno gradivo pomeni izrecno nepopolno/read-only stanje; nič se ne ponareja ali reseala. [Točna meja](E2EE_GENERATION_CONTINUATION.md). Runtime še čaka. |
| Odstranitev starega readable izvora/kopij | Dogovorjena hramba: **30 dni po dokazano uspešni dejanski obnovi nove šifrirane kopije**. Upload, sama identity FILE, aktivacija ali neuspešna obnova ne zaženejo roka | Fizično odstranjevanje šele ob ločenem skupnem deployment koraku. Zdaj ni naročila/izvedbe brisanja starih produkcijskih virov ali zunanjih kopij. Final provenance mora ostati preverljiva tudi po dovoljenem umiku pripravljalnih indeksov. |

Minimalni parent/scope card je izrecna podpisana izjava pristojnega upravljavca o
omejenih dejstvih zamrznjenega izvora. Ni kriptografski selektivni dokaz nevidnega
SQL plaintexta. Parent-access card ne razkrije parent rosterja izven potrebnega
podedovanja, imen, financ ali DEK. Finance baseline vsebuje
`{enabled,revision,requiredContractVersion,policyHash,grantCount}`; celotni raw
inactive/dormant grant stream ostane lastniški zasebni vir in se ne normalizira.

## Skupne meje preverjanja

- Pripravljena crypto glava v preparing/fenced/verified ni običajna READ/WRITE
  avtoriteta. Precommit candidate capability ostane ločena od finalized
  migration/relocation bootstrap in od običajnih floors.
- Migration, inline deletion in relocation purpose tagi ne morejo pasti nazaj na
  navadno WRITE preverjanje. Exact record closure hash se ne nadomesti s purpose
  hashom. Target fizična revizija 1 ne izmisli novega poslovnega nastanka/audita.
- `domain.inventory` exact historical checkpoint selector potrebuje neodvisen
  own-observation anchor in preverjen complete count/root. Hash-only
  `historyGet` je samo kandidat za manjkajoč opaque sibling; provenance in
  celotno skupino prejemnik še vedno neodvisno preveri.
- Scoped foreign issuer directory dostop je omejen na exact referenced prefixes.
  Known secure anchor mora vsebovati zahtevani starejši prefix oziroma fetched
  veriga doseči znani anchor; scoped kontakt se ne promovira globalno. Gostitelj
  lahko brez zunanje transparency/gossip zadrži še neopažene posodobitve;
  zgodovinska vključitev zato ni dokaz globalne najnovejše odsotnosti preklica.
- Po member restriction/unrestriction navadni record/blob/table/reminder/cert
  write zahteva dejansko fresh signed head/access/device stanje. Ozke owner
  rotation in final historical evidence poti niso splošna izjema za stale WRITE.
- Običajna inline→child relokacija ohrani originalnega lastnika in canonical
  project ID ter obstoječe legacy graph/payment/finance blockers. Ne premakne
  poljubnih zunanjih odvisnosti ali zasebnega plačilnega prostora.
- Moderacijski snapshot je izrecno uporabniško razkritje, ne strežniško dokazana
  enakost s šifriranim plaintextom. Njegova 180-dnevna politika po rešitvi in
  30-minutni orphan staging rok sta ločena od 30-dnevne hrambe starih poslovnih
  kopij po uspešni obnovi. Nobena od teh politik ne obljublja secure erase/WAL
  ali odstranitve ključev iz že obstoječih tujih naprav.

## Zaključna verifikacija

PHP del je zaključen in se brez konkretne spremembe prizadete poti ne ponavlja.
Aggregate `build/qa/e2ee-source-upgrade/final-matrix/aggregate-165-pairs.json`
(SHA256 `3a218f95fbb5c3a0a0f0794eecbdc8d79d8d519ea95506652f5ec1670437d525`)
hrani55 PASS zbirk za vsak pogon. Ustavitve ob prvem neuspehu in pregledani
popravki testnih priprav so ohranjeni ločeno; posamezni ponovljeni prizadeti
izid nadomesti prejšnjega in se ne šteje dvakrat. Produkcijski PHP in runner
med to matriko nista bila spremenjena; source je bil znotraj vsakega teka enak.

Retained dokaz je
`build/qa/e2ee-source-upgrade/retained-invitation-recovery-continuation-evidence.json`
(SHA256 `8ee5fff33e8234959c7c24418545fa386cb47ce9561be3bbb5821749b5f32e0c`).
To je dokaz nadaljevanj istega stanja36b/38/39/40/41, ne svež celotni PASS.
Inline31 je celoten PASS. Relocation43 ima potrjene glavne podatkovne in
commit meje, recipient-only bralni in FILE zaključek še čakata. Preostanejo
že dogovorjeni končni združeni35, use3/A–B continuation in ena zaključna
Flutter zbirka/analiza; izbirni structure-successor helper ni dodatna obveznost.
Podrobne rezultate loči [izvedba](E2EE_IMPLEMENTATION.md#dokazi-in-končno-preverjanje).

Runnerjev seznam `PENDING_GATES` še zahteva vezavo ločenih dejanskih HTTP
rezultatov. Njegov izhod2 ob uspešnih PHP zbirkah zato ni testna napaka in tudi
ni končni release PASS. Ne ponavljamo celotne zelene PHP matrike samo zato,
da pozneje povežemo HTTP evidence. Drift med tekom izniči ta tek; konkreten
popravek po njem zahteva nov manifest ter prizadeto preverjanje.

Ta dokument ne zapira P0 neodvisnega pregleda, P8 varne namestitve in fizičnih
naprav, dejanskih produkcijskih backup/restore/retention dokazov ali javne
trgovinske izdaje. Potrebni libsodium in vrstni red usklajene namestitve ostaneta
izdajna predpogoja; sintetične konfiguracije niso dovoljenje za live vključitev.
