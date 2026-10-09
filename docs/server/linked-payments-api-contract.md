# Povezano osebno plačilo — FamilyHub 0.9.0 / schema13

Izvorna pogodba 9. oktobra 2026. Gostovana namestitev in mobilna izdaja imata ločene dokaze. Ta sprememba ne izvaja namestitve, objave ali spremembe različice aplikacije.

## Finančna dejstva in pravice

Canonical `financeEntry` expense ostane edini strošek organizacije oziroma njenega projekta. Finance2 payload, per-record operacije in njihove izvirne identitete/hashi ostanejo združljivi. Finance3 doda ločen payment event, omejene projekcije ter denarne premike; ne ustvarja kopij tipa expense/income.

Prva izvedba podpira enega plačnika in eno osebno plačilo celotnega stroška. Plačnik je overjeni accountId finančnega pisca vira. Sprejeto članstvo, bralna pravica ali gospodinjsko finančno pisanje sama ne dovoljujejo potrditve plačila ali povračila v organizaciji. Vsako povračilo potrdi finančni pisec vira; znesek, valuta, račun in revizija se preverijo na strežniku.

Plačilo 30 EUR pomeni: organizacijski expense totals ostanejo 30 EUR, organizacijski ledger se ob osebnem plačilu ne zmanjša, izbrani osebni račun ima premik −30 EUR. Pri pričakovanem povračilu je terjatev 30 EUR. Potrjeni nogi 10 in 20 EUR zmanjšata izbrani organizacijski račun za 10/20 EUR ter povečata osebni račun za 10/20 EUR; ne ustvarita novega stroška/prihodka. Terjatev gre 30 → 20 → 0. `expectReimbursement:false` pomeni terjatev 0 in zavrne povračila.

Household projection nastane samo ob izrecni izbiri gospodinjstva s finančno write pravico. Vsebuje že dovoljeno payment/refund dejstvo, izvorne identitete in revizije; ne vsebuje osebnega računa, naziva kartice, zasebnih opomb ali imen osebnih računov. Public source event vsebuje payerAccountId in organizacijski račun povračila. Zasebni ledgerAccountId je samo v personal projection.

## Različice in starejši odjemalci

`capabilities.features.linkedPayments` in `linkedPaymentContractVersions:[3]` oglašujeta sidecar. Canonical `financeContractVersions:[1,2]` ostane ločen; finance3 nima splošnega push API za poljubne projekcije.

Canonical finance/finance2 zahteve novega odjemalca vključijo `linkedPaymentsAware:true`. Enako velja za `sync3/4.pushTaskWithCost`. Strežnik odstrani transportni flag pred preverjanjem izvirnega request hasha. Stara čakalna operacija zato ohrani telo, opId, pogodbo in replay. Ko ima scope linked payment, projection ali refund cash, policy/pull/audit/push oziroma compound pot brez te izjave vrne `client_upgrade_required` (409). S tem starejši odjemalec ne prejme zavajajoče popolne finančne projekcije.

`SharedFinancePolicy.linkedPaymentsRequired` zahteva popoln sidecar pri izračunu računa. Odjemalec hrani dokaz zadnjega popolnega avtoriziranega prenosa skupaj z access generation, policy revision in scope sequence. Izpad omrežja ohrani upravičeno lokalno kopijo ter zadnje znano stanje. Delni/nov neuspešen prenos ne potrdi nove popolnosti.

## Metode in payloadi

Native API HTTP ovojnica ostane v1. UUID nastanejo na napravi. Datumi so UTC instanti, zneski pozitivne najmanjše enote in ena valuta EUR/USD/GBP/CHF. Nobena zahteva ne sprejme zasebnega finančnega payload-a v public scope.

| Metoda | Parametri | Izid |
| --- | --- | --- |
| `finance3.paymentCommit` | `scopeId,entryId,expectedEntryRevision,eventId,paidAt,expectReimbursement,requestId`; izbirni `personalTarget:{scopeId,accountId}`, `householdScopeId` | `{event}`; posted canonical expense potrdi celotno plačilo. Znesek/valuta iz canonical source, payer iz overjene identitete. |
| `finance3.paymentReimburse` | `scopeId,eventId,expectedRevision,legId,amountMinor,paidAt,organizationAccountId,requestId`; izbirni `organizationAccountScopeId` | `{event}` z novo nespremenljivo odobreno nogo. Privzeti account scope je source; dovoljen je tudi parent organization z ločeno finance write pravico. |
| `finance3.paymentProject` | `scopeId,eventId,expectedRevision,requestId`; izbirna ista target polja | `{event}`; source finance read, isti payer ter konkretne target write pravice. Vsebino izdela strežnik iz dovoljenega source. |
| `finance3.payments` | `scopeId` | `{events,projections,cashMovements,accessRevision,scopeSequence}` po trenutni finančni ACL. |

Event ima `eventId,sourceScopeId,sourceEntryId,sourceRevision,payerAccountId,amountMinor,currency,paidAt,expectReimbursement,revision,reimbursements`. Reimbursement leg ima `legId,amountMinor,paidAt,organizationAccountId,organizationAccountScopeId,approvedByAccountId`. Osebni/gospodinjski projection leg odstrani organizacijski račun; osebni projection doda `privateAccountId`. Projection doda `paymentRevision` in `state`. Cash movement je minimalen `id,accountId,amountMinor,currency,paidAt`; amount je predznačen.

Commit source preveri finance2 pogodbo, posted expense, revizijo in obstoječi payer/paidAt. Če paidAt še ni določen, ga skupaj z occurredAt in payer identity atomarno dopolni v canonical expense. Finance2 zahteva paidAt==occurredAt; source revision in audit napredujeta. Currency in amount se ne spreminjata. Personal target mora biti ownerjev personal scope ter obstoječ, ne arhiviran račun v isti valuti. Household mora imeti writer grant.

EventId ni mogoče ponovno uporabiti za drug source; legId ni mogoče uporabiti za drug premik. Vsota odobrenih nog ne preseže payment amount, noga ni pred prvotnim paidAt, največ 500 nog/event. Po povezavi se zavrne source delete ali sprememba monetary/account/payer/payment/link polj. Varno urejanje title/notes/category/plannedAt je dovoljeno in posodobi sourceRevision ter payment revision. Task-only due-date sprememba ne prepiše že plačanih finančnih datumov.

Snapshot je omejen na 524288 JSON bajtov. Presežek vrne `linked_payments_too_large` (413), brez delne uspešne projekcije. Prva izvedba ne oglašuje paginiranega ali neomejenega sidecar prenosa. Odjemalec ne sme neuspešnega prenosa razglasiti za popoln balans.

## Atomska hramba, replay in delo brez povezave

Schema13 additivno ustvari `familyhub_payment_events`, `familyhub_payment_projections` in `familyhub_payment_cash`. Finance3 zahteve imajo isti globalni mutex kot account deletion ter običajne actor/source/parent scope locks. Source + izbrani server targets se zapišejo v eni transakciji. Že znana revokacija ali spremenjen grant se preveri pred replay; private receipt ne obide current target ACL.

Reimbursement in varna source sprememba posodobita že izrecno povezane server projections ter običajni finance sequence relevantnih prostorov. Normalen odjemalski sync zato znova prebere sidecar, tudi če finance2 nima novega expense recorda. Povračilo ustvari finančno obvestilo prek obstoječega inbox/mail/push mehanizma za upravičene naročnike; nespremenljivi legId prepreči podvajanje ob replay. Klik odpre canonical expense v izvornem prostoru in ponovno preveri pravice. Izpeljano trusted pisanje target projekcije ne razkrije njenega zasebnega accountId source writerju.

All-local source/event/projekcije/intenti se zapišejo v eni SQLite transakciji. Mixed source-server/local-target tok hrani exact request pred HTTP in šele po potrjenem canonical eventu objavi avtorizirane lokalne projekcije. Izgubljeni ACK ponovi isti requestId/eventId/legId. Local source z oddaljenim targetom ostane lokalno uporaben in čaka `waiting_source_publication`; ne objavi vira samodejno. Po izrecni objavi je potreben identity-aware nadaljevalni most. Target na drugem strežniku je v tej izvedbi izrecno zavrnjen.

Prenosna backup4 vključuje dogodke, projekcije, cash rows in intente. Obnova remote source-bound dela ostane v šifrirani karanteni; ne aktivira pravic ali pošiljanja pod drugo identiteto. Stare backup1–3 ne odstranijo novega lokalnega sidecar-a. Payload/references in collisions se preverijo pred atomarno obnovo. Pozna revizija 1/replay ne prepiše že znane revizije 2 z odobrenim povračilom; nasprotujoča ista revizija je napaka.

## Izbris računa: policy3

Če linked financial facts vplivajo na izbris, je potreben odjemalec deletion policy3 in svež predogled. `linkedFinancialFacts` vsebuje natančne per-scope event/refund counts ter reason `retained_shared_financial_fact`: dogodki se ohranijo, če uporabnik prenese/ohrani source, in izbrišejo, če izrecno izbriše njegov source. Impact doda `privatePaymentProjectionsDeleted`, `sharedPaymentReceiptsRetained`. Nov `financeEntry/preserveStructure` resolution zahteva izrecno odločitev za ohranitev shared canonical expense.

Ohranjen shared source zadrži amount/date/refund history in potrebne opaque historical actor UUID reference. Uporabniško ime/opombe/naziv se zamenjajo z removed-member/shared presentation, canonical payer se odstrani; zasebna projection/card povezava in osebni scope se odstranita. To ni trditev popolne anonimizacije ali izbrisa že prenesenih kopij.

Izrecen source delete odstrani njegov payment event sidecar. Že dovoljeni downstream cash receipt ostane označen `sourceRemoved`, brez trditve aktivnega source oziroma aktivne terjatve. Izbris private scope odstrani njegove projekcije in cash rows. Povrnitev pravic/obnovljena kopija ni dokaz prvotnega članstva.

## Preverjanje

`server/tests/linked-payments-integration.php` uporablja nove sintetične dejanske HTTP fixtures na SQLite/MySQL/MariaDB. Pokriva plačilo 30 EUR in povračili 10/20 EUR, replay, stale revisions, allow/deny, zasebno kartico, parent org račun, no-reimbursement, zahtevo za nadgradnjo starega odjemalca, original finance2 hash, bounded failure, linked task due-date ter account deletion retained/deleted source. Spletni obrazec dodatno preveri policy3 predogled, pogojne counts, zasebnost, POST/CSRF, ponovno overitev ter receipt replay po izbrisu bearerja. Ločeni Dart domain/coordinator/loopback testi dokazujejo odjemalsko pretvorbo in lokalno obnovljivost. Končne rezultate dokumentira izvedbeni dokaz; seznam testov sam ni dokaz dokončanega UI ali gostovane namestitve.
