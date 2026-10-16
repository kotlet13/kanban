# FamilyHub shared-content policy and reporting — contract 1

Current source distribution: **FamilyHub 0.15.0 / schema19**. Existing wire/contract identifiers below keep their original versions. Organization tables and private attachments are specified in the bundled `DOCUMENTS_API.md`; current distribution source is distinct from hosted deployment evidence.

Local implementation for FamilyHub 0.12.0 / additive schema16. This document
describes the new source contract; it does not confirm installation on a live
server or approval by an app store. Native API envelope remains version1;
existing record, finance, account and linked-payment contracts remain separate.

## Destination and boundary

Reports go to the administrator of the user's selected Kanboard/FamilyHub
installation. They do not go to the hosting company's cPanel account or to
TriparNA automatically. The native device bearer may submit authorized reports;
administrator review requires a Kanboard administrator web session, TLS and
CSRF protection. The reporting API does not give a native account administrator
rights, grant membership, or expose another user's personal scope.

Report preview identifies the receiving server and the single target's bounded
evidence. Submission is explicit. It must not send a complete workspace, backup,
device credentials, API keys or unrelated personal financial records. A report
does not itself delete, hide, sanction or notify its target.

## Capabilities and policy

Capabilities advertise `moderationContractVersions: [1]`,
`sharedContentPolicyVersions: [1]` and feature flags
`contentReporting` / `sharedContentPolicy`. Missing support is an upgrade-needed
state, not evidence that a report was delivered. Policy acceptance is explicit,
versioned, and bound to the server identity and authenticated account.

| Operation | Parameters | Result |
| --- | --- | --- |
| `moderation.policy` | `{}` | `contractVersion`, `serverId`, `policyVersion`, `title`, `textSl`, `textEn`, `recipient`, prohibited categories and declared report retention |
| `moderation.policyStatus` | `{}`; bearer | `serverId`, `accountId`, `policyVersion`, `accepted`, `acceptedAt` |
| `moderation.acceptPolicy` | `policyVersion: 1`; bearer | Same status, with durable acceptance |
| `moderation.reportPreview` | `scopeId`, `targetType`, `targetId`; bearer | Bound identity/target, `targetRevision`, `subject`, bounded `evidence`, `recipient`, `previewHash` |
| `moderation.report` | `requestId`, `scopeId`, `targetType`, `targetId`, `previewHash`, `reason`, `details`; bearer | `reportId`, `status: submitted`, `createdAt`, `serverId` |

Target types are `record`, `finance`, and `user`. User targets use a stable
account UUID belonging to a visible member in the selected shared scope; there
is no arbitrary global user search. Record and finance targets require current
read permission for the actual target. Finance evidence requires the existing
financial visibility checks; a report cannot bypass them.

Reasons are `harassment`, `hate`, `sexual`, `violence`, `illegal`, `spam`,
`privacy`, or `other`. Details are bounded to 2000 UTF-8 bytes. Request IDs are
UUIDs and idempotently identify a submission. Changed data under the same ID
must not create a second report or overwrite evidence. `report_preview_changed`
requires a new explicit preview; stale evidence is not silently substituted.

## Local use, private synchronization and pending work

The shared policy is required before new shared writes/uploads. No client may
accept it silently. `policy_acceptance_required` is a consent-needed state,
not a confirmed membership revocation. Downloaded content and unsent edits,
operation IDs, backups and exports must remain available. Reading and reporting
remain possible without accepting the policy. Basic local use and private
personal synchronization do not require shared-content acceptance.

A new client checks the server capability before sending shared mutations.
An older server cannot pretend to implement this contract. A new server also
enforces acceptance for older clients; client UI alone is not the enforcement
boundary. Existing operation payloads are not rewritten to add a consent flag.

## Administrator handling and lifecycle

The administrator sees a bounded list and the explicitly reported evidence,
records a review outcome and note, and can take supported scoped action. Any
record action must respect current revision and existing child/ledger rules;
membership action updates the existing access/visibility state. Explicit
administrator confirmation is required for content removal and scoped
restriction/reversal. A restriction preserves original membership, financial
grants and leadership; reversal does not reactivate an independently removed
membership. Financial
facts must not be destroyed as a shortcut for moderation. A report status change
alone is not evidence that the underlying content or membership was changed.

The web review page is
`index.php?controller=ModerationController&action=index&plugin=FamilyHub`
under Kanboard settings. It requires an active `app-admin` session. Native
bearers cannot use this administrator endpoint. Outcomes are reviewed, resolved
or dismissed, with a note and revision-checked audit. Removing a leaf record
uses a tombstone; a structural parent/root has its reported text redacted while
preserving its project/child structure. Financial records are not deleted.

Evidence is limited to id/type/revision and title/name (up to 200 UTF-8 bytes),
notes/description (up to 2000 bytes each). A user preview contains the visible
member's account ID, name, username and role. Amounts, attachments, related
entries and private linked-payment graphs are omitted.

Open reports remain for review. Evidence, report details and review notes are
redacted 180 days after resolution/dismissal; minimal IDs, hashes, category,
timestamps and audit actions remain. Cleanup processes at most 100 reports per
run, from the existing reminders worker or administrator page. No new cron,
SMTP or push configuration is required. Expired evidence is not recreated.
Account deletion removes its acceptance, reports submitted by or concerning
it, reports on its authored records and associated audits. Deleting an owned
scope also removes its reports; the deletion preview discloses these effects.
Operator backups/logs are separate.

Schema16 adds four tables (acceptance, reports, audits and scoped restrictions)
without changing prior definitions or rows. API version1 and existing operation
bodies remain unchanged. Server
operators are responsible for actually reviewing reports and configuring their
installation; publishing a reporting button alone does not prove effective
moderation or app-store compliance.
