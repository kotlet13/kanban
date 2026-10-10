# Deljenje celotnega prostora in posameznega projekta (policy3)

Izvor FamilyHub 0.11.0/schema15; namestitev je ločen korak. Kanboardove skrbniške pravice se ne spreminjajo. Finance2 in linked-payment3 ohranita svoje metode, telesa in identitete operacij.

## Pogodba dostopa

`spaceAccessPolicyVersions:[3]`, `organizationAccessPolicyVersions:[1,2,3]`, `invitationContractVersions:[1,2,3]`; zmožnosti `spaceProjectMembership`, `scopedInvitations`, `projectSharingMigration`.

Policy3 sprejeto članstvo v household/organization daje vse skupne vsebine, finance ter obstoječe in prihodnje projektne otroke. Sprejeto članstvo v project daje samo ta projekt. `member` lahko bere, ustvarja, ureja in odstranjuje vsebino, skupne finance, povabila, članstvo ter nastavitve znotraj svojega cilja. `viewer` ostane samo branje. `owner` ostane dejanski edini lastnik; odstranjevanje lastnika je prepovedano. Sprememba lastništva/izbris računa zahtevata obstoječi preverjen postopek. Osebni prostori ter zasebni računi se ne dedujejo.

Scope wire dodaja `parentScopeId` (nullable UUID), `parentScopeKind` (nullable household/organization), `accessSource` direct/spaceMembership/leadership. `organizationId` ostane alias samo organizacijskega starša. Projekt ima en `projectRootId`; podedovani owner je v tujem projektnem otroku `member`. Pravice neposrednega in podedovanega članstva se združijo; preklic starša ne prekliče posebej sprejetega projektnega članstva.

`scopes.create` sprejme `accessPolicyVersion:3` za novi household/organization/project in `parentScopeId` za novi projekt; podeduje politiko starša. `projectPayload` je ista record3 pogodba. `scopes.members` policy3 vrne učinkovito unijo s `accessSource`, `membershipScopeId`, `accessSources` ter `inheritedFromScopeId`. Odstranitev iz otroka odstrani samo neposredno članstvo; podedovane pravice ostanejo.

## Povabila3

`invitations3.create`: `{scopeId, recipientEmail, role, requestId, language, accessScope, expiresIn?}`. `accessScope` je obvezno `space` za household/organization ali `project` za project; ciljni scope mora uporabljati policy3. `role` member/viewer, language sl/en. Vrne `{invitation,deliveryQueued:true}`; žeton fhi3_ je samo v šifrirani poštni vrsti/povezavi. Wire invitation ima `contractVersion:3`, `accessScope`, `sharedFinanceIncluded:true` in stare identifikatorje/podatke prejemnika ter roke.

`invitations3.preview:{token}`, `invitations3.pending:{}`, `invitations3.accept:{token}` ali `{invitationId}` ohranijo email2 identiteto in ločen izrecni sprejem. Registracija (`auth.registerInvitation3`) nikoli ne dodeli članstva; prijava prav tako ne. List/revoke uporabljata obstoječi `invitations.list/revoke`, ki vrneta/verificirata shranjeno verzijo. Stara create1/2 za policy3 vrneta `client_upgrade_required`.

## Izrecna nadgradnja obstoječega prostora

`scopes.accessMigrationPreview:{scopeId,targetVersion:3}` in `scopes.accessMigrationApply:{scopeId,targetVersion:3,previewHash,requestId}` sta dovoljeni dejanskemu lastniku household/organization oziroma samostojnega project prostora. Projektni otrok nadgrajuje politiko prek svojega starša. Samostojni legacy project potrebuje natanko en živ projekt record3 ter vse task/event vezane nanj; sicer `canApply:false` in `project_scope_requires_single_root`, `project_record_upgrade_required` ali `project_scope_unrelated_content`. Spremembe tega grafa spremenijo previewHash. Opuščeni targetVersion ohrani prejšnjo nadgradnjo na2 za organization.

Preview: `{scopeId,fromVersion,toVersion:3,canApply,blockers,projects:[{scopeId,name,financeWasEnabled,additionalReaders:[{accountId,displayName,accessSource}],additionalWriters:[...]}],revokedInvitationIds,previewHash}`. `projects` vključuje tudi sam korenski prostor. Hash pokriva članstva, finančno politiko/grante, projekte in čakajoča povabila. Apply vrne `{scope,preview}` in trajno ponovi isto telo pri izgubljenem odgovoru. Nadgradnja omogoči skupne finance ter prekliče vsa še nesprejeta stara povabila v korenu in otrocih; starih ne razširi tiho. Učinkovita politika3 se shrani tudi na otrocih; ob ločitvi zaradi potrjenega izbrisa starša ostane3. Stari target2 ne sme nadgradnje obrniti in vrne `client_upgrade_required`.

## Izločitev starega gospodinjskega inline projekta

`scopes.projectSharingPreview:{scopeId,projectId}`; `scopeId` je household policy3. `scopes.projectSharingApply:{scopeId,projectId,previewHash,requestId}`. Člani lahko opravijo izločitev.

Preview: `{scopeId,projectId,projectName,canApply,blockers:[{code,recordId?}],movedRecordIds,movedFinanceRecordIds,movedReminderIds,financeAccounts:[{id,name,currency,openingBalanceMinor,openingBalanceAt}],householdPeople:[{id,name,notes}],previewHash}`. Apply: `{scope,projectRoot,movedRecordIds,movedFinanceRecordIds,movedReminderIds}`. Novi child scope ima ID enak izvirnemu projectId; vsi domeni ID-ji/revizije izločenega grafa se ohranijo. Povezane finance so financeEntry s taskId projekta, njihovi izključno uporabljeni računi/pravila ter izključno uporabljeni profili oseb. Oseb ni tiho podvojenih. Predogled pokaže tudi prenesena začetna stanja računov in zapiske oseb. Prenos med dvema že izbranima izključnima projektnima računoma se preseli z istim ID-jem; prenos v račun zunaj grafa je blocker. Zaradi morebitnega enakega UUID-ja v splošni in finančni tabeli se obvestila/opomniki preselijo samo ob ujemanju ID-ja in vrste zapisa. Obvestila in opomniki sledijo svojemu premaknjenemu cilju.

Izločitev zavrne ponovno uporabljeni gospodinjski račun (`project_finance_account_shared`), pravilo (`project_recurrence_shared`), profil (`project_person_shared`), medobsežni prenos (`project_transfer_cross_scope`), povezano plačilo (`project_linked_payment_dependency`), ID kolizijo (`project_scope_id_collision`) ali preskromen projektni format (`project_record_upgrade_required`). Izločitev zato nikoli ne kopira preostalega gospodinjstva ali opening balance drugega projekta. Uporabnik mora ločiti skupno odvisnost pred ponovnim predogledom.

Apply je atomaren pod ključavnico gospodinjstva. Izvor dobi tombstone in evidenco selitve; novi zapis v starem obsegu vrne `record_relocated`, predhodni idempotentni odgovor pa ostane ponovljiv. Stari neizločeni projekti ostanejo dostopni. Odjemalec pred apply preveri lokalne čakalne vrste/konflikte in ob negotovem odgovoru zaklene spreminjanje izvornega obsega do ponovitve zahteve; teles ali ID-jev starih operacij ne prepisuje. Zastarel preview vrne `project_sharing_preview_changed`; neizločljiv graf `project_sharing_blocked` z blockerji.

## Lokalni dokazi

Končni sklop deljenja preverja 105 kontrol na SQLite, MySQL8.4.11 in MariaDB10.11.19. Skupaj z 16 predhodnimi sklopi (računi, sinhronizacija, policy1/2, finance, deljenje, opomniki, obvestila in izbris) je preverjenih 835 kontrol na bazo oziroma2505 skupaj. PHP lint preveri111 datotek vtičnika in testov. `build/qa/space-sharing/matrix-summary.json`, posamezni `{driver}-{suite}.log` in `php-lint.log` so lokalni dokazi. Ponovljivo orkestracijo vodi `python3 server/scripts/test-space-sharing-matrix.py`; uporablja izključno tri obstoječe izolirane razvojne vsebnike in ustvarja naključne sintetične račune. Ne resetira nosilcev. Ti dokazi niso potrdilo namestitve ali fizičnega prikaza/dostave na dveh napravah.
