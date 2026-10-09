# Prostori, vodstvo in vrt — FamilyHub 0.8.0 / schema12

Izvorna pogodba 9. oktobra 2026; HTTP ovojnica Native API ostane v1. Lokalni izvor in testi niso dokaz gostovane namestitve. Ta sprememba ne zviša različice mobilne aplikacije in ne izvaja produkcijskega preklopa. Namestitvene dokaze še vedno vodi `CPANEL_SETUP.md`.

## Različice in odkrivanje

`capabilities` oglašuje `organizationAccessPolicyVersions:[1,2]`, record1/2/3/4, finance1/2 in dodatne zmožnosti `organizationLeadership`, `projectFinanceMembership`, `accessMigrationPreview`, `stableScopePublication`, `scopeAccessChanges`, `scopeMetadata`, `householdGardenSync`. Privzeto izključen Native API, podprte baze, TLS in osebna identiteta ostanejo enaki.

Schema12 additivno dodaja `access_policy_version=1`, `access_revision=0`, `address=NULL`, `metadata_revision=0` in lastni tabeli `familyhub_organization_leaders`, `familyhub_scope_revocations`. Ponavljanje selitve ohrani vse vrstice. **Sama DDL selitev ne spremeni obstoječih dovoljenj.** MySQL/MariaDB DDL ni povrnitev transakcije; pred namestitvijo je potrebna preverjena celotna kopija baze, datotek in konfiguracije. Ne znižuj različice sheme ali briši tabel kot nadomestila za obnovo.

## Pravila dostopa

Pri policy1 ostanejo ločena članstva in finančni grant-i. Pri policy2:

- Sprejeti projektni član, tudi viewer, bere vso projektno vsebino in vse projektne finance. Neprejeta/nepotrjena povabila ne dajejo pravic. Članstvo enega projekta ne odpre organizacije ali sorodnih projektov.
- Aktivni lastnik organizacije je privzeto vodja. Izrecno določeni drugi vodje morajo imeti aktivno, z accountId povezano organizacijsko članstvo. Vodje berejo vse obstoječe/prihodnje projekte in njihove finance. Če nimajo neposrednega projektnega članstva, dobijo učinkovito vlogo `viewer`.
- Splošne finance organizacije samodejno berejo vodje; ohranijo se že obstoječi izrecni finančni grant-i drugih članov. Običajno organizacijsko članstvo ne odpre splošnih financ.
- Urejanje projektnih zapisov določa neposredna projektna vloga, urejanje financ pa izrecni `write` grant skupaj z vlogo. Vodstvo ne dodeli urejanja. Upravljanje članstva, vodij in migracije ostane lastnikovo.
- Novi policy2 org/projekti imajo vključene finance in lastnikov write grant. Migracija po predogledu omogoči tudi prej izključene finance; ohrani obstoječe grant-e in manjkajoč lastnikov grant doda kot write. `finance.enable` z `enabled:false` za policy2 vrne `managed_by_organization_policy` (409).
- `finance.grant:none` projektnega člana ne odstrani iz dogovorjene projektne bralne matrike. Odstranitev člana/vodje upošteva alternativne neposredne oziroma vodstvene pravice. Arhiviranje ustavi zapisovanje, branje ostane po isti matriki.

`scopeWire` dodatno vsebuje `address`, `metadataRevision`, `accessPolicyVersion`, `accessRevision`, `organizationLeader` in `accessSource` (`direct` ali `leadership`). Za otroški projekt sta različica in revizija dostopa izpeljani iz organizacije. `scopes.members` organizacijskim članom doda `organizationLeader`. Finančna politika doda `managedByOrganizationPolicy` in `readAccessFromMembership`; njena bralna revizija vključuje organizacijsko revizijo dostopa.

Centralni `NativeOrganizationAccess` ter `NativeFinanceAccess` se uporabljata za sync, finance pull/audit, inbox/open/group, opomnike ter mail/push ob pošiljanju. Backend nima ločenega izvoza ali priponkovnega API za te nove zapise: odjemalčev lokalni izvoz in njegova priponkovna hramba imata ločena merila. Skupna organizacijska vloga ne razkrije osebnih finančnih prostorov ali gospodinjstev.

## Končni podpisi metod

| Metoda | Parametri | Izid |
| --- | --- | --- |
| `scopes.create` | Obstoječi `id,kind,name,requestId`; izbirni `organizationId,accessPolicyVersion,address,projectPayload` | `{scope,projectRoot?}`; client UUID ostane enak, isti requestId/body vrne isti izid. `accessPolicyVersion` velja samo za novo organizacijo; izpustitev ohrani policy1. `projectPayload` velja samo za organizacijski projekt in je njegov izvirni record3 payload; title mora ustrezati name. |
| `scopes.updateMetadata` | `scopeId,name,address,expectedRevision,requestId` | `{scope}` za lastnika gospodinjstva/organizacije. `metadata_conflict` (409) vsebuje trenutno dovoljeno scope projekcijo. Projekt se preimenuje prek obstoječega urejanja korenskega projekta. |
| `scopes.setLeader` | `scopeId,accountId,enabled,requestId` | `{members,accessRevision}` za lastnika policy2 organizacije; vodstva lastnika ni mogoče izključiti. |
| `scopes.accessMigrationPreview` | `scopeId` | `{scopeId,fromVersion,toVersion:2,projects,previewHash}` za lastnika organizacije. |
| `scopes.accessMigrationApply` | `scopeId,previewHash,requestId` | `{scope,preview}`; stale hash vrne `access_preview_changed` (409), isti requestId/body ponovi izvirni izid. |
| `scopes.list` | Obstoječe izbire ter izbirni `includeAccessChanges:true` | Običajni scopes ter dodatni `revokedScopeIds`, samo ob izrecni izbiri. |

Projekt v predogledu vsebuje `scopeId,name,financeWasEnabled,additionalReaders`; bralec `accountId,displayName,accessSource` (`projectMembership` ali `leadership`). Predogled vključuje tudi prej izključene finančne module, saj preklop vpliva tudi nanje. Za policy2 ponovni pregled ne opisuje nove širitve.

Ob sprejemu povabila organizacijskega projekta `invitation.projectFinanceIncluded` in `preview.scope.projectFinanceIncluded` jasno pomenita branje vseh projektnih financ, tudi pozneje dodanih. Osebni finančni račun plačnika ni del povabila.

## Atomska uskladitev in potrjen preklic

Zaklepni vrstni red je uporabnik → organizacija → projekt. Vsak `scope()` za organizacijski projekt zaklene najprej organizacijo; to velja tudi za povabila, projektne finance/grant-e in generic sync. Predogled, hash preverjanje in preklop tečejo v isti transakciji pod zaklepom organizacije. Sprememba otroškega članstva ali finančne politike zato ne more zdrsniti med preverjanjem in preklopom. Izbris računa zaklepa organizacije pred njihovimi otroki.

Dnevnik potrjenega preklica nastane samo po izrecni odstranitvi člana/vodje oziroma izgubi izpeljanega dostopa zaradi potrjene odstranitve organizacijske povezave. Vpisani so samo prej vidni obsegi, po upoštevanju alternativnih pravic. Ponovno sprejeto članstvo ali vodstvo počisti ustrezne oznake. `scopes.list` dodatno preveri trenutno učinkovito pravico in obstoj prostora, preden vrne oznako. S tem ne razkriva ID-jev projektov, ki jih uporabnik nikoli ni videl.

**Odsotnost prostora v seznamu ni dokaz preklica.** Manjkajoči prostor vrne `scope_unavailable` (409), ne `permission_revoked`. Izginula/prazno obnovljena baza brez dnevnika ne ustvari preklica. Nepopoln odgovor, potek seje in nedosegljivost ostanejo odjemalčevo usklajevanje; lokalne kopije se ohranijo. Backend ne more zagotoviti brezpovezavnega branja, kopije/obnove in priponk: dokazujejo jih ločeni odjemalčevi preizkusi.

Vodje se zaradi vidnosti ne naročijo na vsa projektna obvestila. Izpeljan prejemnik se doda šele, ko ima izrecno shranjeno nastavitev konkretnega projekta/kategorije; ob dostavi se pravice ponovno preverijo. Neposredni člani ohranijo dosedanje privzete nastavitve. Odstranitev člana/računa počisti vodstvene vnose; izbris računa ne pusti veljavnega starega accountId.

## Vrt in transport4

`sync4.push/pull` uporablja isti per-record envelope in trajne opId-je kot predhodniki. Tip `garden` je dovoljen samo v gospodinjstvu z `operationContractVersion:4`. Payload je **natančen Garden.toJson format2**, tudi `version,id,name,notes,areas,seasons,revision,createdAt,updatedAt`.

`payload.id` mora biti enak `operation.recordId`; canonical **envelope revision** je avtoritativna za sočasno urejanje. Payload revision je ločena lokalna metainformacija in ob prenosu ne sme prepisati canonical envelope revizije. Ostanejo trajni ID-ji gred/zasaditev, letne sezone in koledarski datumi brez pretvorbe časovnega pasu. Veljajo obstoječe lokalne meje (1000 območij, 500 sezon, 2000 zasaditev/sezono, 10000 skupaj) ter največ 524288 UTF-8 bajtov/dokument. Zahteva je največ 1 MiB; stran ciljano 512 KiB, vendar en prvi dokument z ovojnico lahko preseže cilj strani, da ni razreza ali zastoja. Odjemalčev HTTP odgovor je omejen na 2 MiB.

Starejši odjemalec za obseg z garden recordom dobi `client_upgrade_required`, tudi po tombstonu. Transport4 pa sprejme stare record1/2/3 operacije z izvirnim `operationContractVersion`; hash, telo in opId ostanejo izvirni. `sync4.pushTaskWithCost` je atomski most obstoječega `sync3.pushTaskWithCost` z istim originalnim hashom, finance2 delom in preverjanjem pravic. Prisotnost vrta ne prepreči običajnih opravil/stroškov. Vrt trenutno ne ustvarja generičnih shopping obvestil.

Noben obstoječi lokalni vrt se samodejno ne objavi: odjemalec potrebuje izrecno povezavo z gospodinjstvom in predogled posledice deljenja. Zunanji format kopije in karantena obnovljenega strežniškega dela imata ločena pravila.

## Preverjanje in preostale meje

`server/tests/spaces-integration.php` izvaja dejanski HTTP na ločenih sintetičnih SQLite, MySQL 8.4 in MariaDB 10.11 okoljih: policy1/2, allow/deny branje in ločeno pisanje, lastnika/vodjo/sprejetega/nepotrjenega člana, obstoječe/prihodnje projekte, stale child grant/member preview, replay, alternativne pravice, pozitiven preklic/manjkajoči prostor, zavrnjeni inbox ter garden CRUD/replay/conflict/tombstone, metadata in izvirno objavo korenskega projekta. Širši sklop ohranja native/finance/organization/collaboration/reminder/account-deletion regresije. Rezultate končnega zagona glavni agent zabeleži posebej; seznam testov sam ni dokaz uspeha.

FamilyHub 0.9.0/schema13 dodaja povezana osebna plačila, izrecne gospodinjske projekcije in delna povračila v ločeni [finance3 pogodbi](linked-payments-api-contract.md). Canonical finance2 strošek ostane eno dejstvo; sidecar loči osebno denarno breme, terjatev in poravnavo ter varuje zasebni račun plačnika. Izvorna izvedba in njeni preizkusi ne pomenijo nadgradnje gostovane namestitve ali mobilne izdaje.
