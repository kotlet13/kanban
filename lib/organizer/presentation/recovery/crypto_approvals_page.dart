import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';

import '../../data/e2ee/crypto_business_router.dart';
import '../../data/e2ee/crypto_business_leave.dart';
import '../../data/e2ee/crypto_finance_account_choices.dart';
import '../../data/e2ee/crypto_inherited_invitation_grants.dart';
import '../../data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import '../../data/e2ee/crypto_pending_approvals.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../../data/e2ee/account_directory_v2.dart'
    show VerifiedAccountDirectory;
import '../../state/collaboration_provider.dart';
import '../shared/sharing_errors.dart' show sharingErrorMessage;
import 'crypto_record_preview.dart';
import 'scope_recovery_page.dart';

String _text(BuildContext context, String sl, String en) =>
    Localizations.localeOf(context).languageCode == 'sl' ? sl : en;

/// Existing child managers can finish parent actions without parent content,
/// keys, names or a global identity pin supplied by the server.
class CryptoApprovalsPage extends ConsumerStatefulWidget {
  const CryptoApprovalsPage({super.key});
  @override
  ConsumerState<CryptoApprovalsPage> createState() =>
      _CryptoApprovalsPageState();
}

class _CryptoApprovalsPageState extends ConsumerState<CryptoApprovalsPage> {
  CryptoPendingApprovals? _service;
  CryptoPendingApprovalList? _list;
  bool _busy = false, _failed = false, _waiting = false;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
      _failure = null;
    });
    try {
      final repository = await ref.read(collaborationRepositoryProvider.future);
      final account = await repository.connectedCryptoAccount();
      final access = SessionCryptoAccess(account: account);
      final service = CryptoPendingApprovals(
        CryptoBusinessSession(account, access, repository.database),
      );
      final list = await service.load();
      if (mounted) {
        setState(() {
          _service = service;
          _list = list;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyProposedIdentity(
    String scopeId,
    String headHash,
    String accountId,
  ) async {
    final access = _service!.context.access;
    if (accountId == access.account.directory.accountId) return;
    final status = await access.account.directory.call(
      'crypto2.directory.status',
      {'scopeId': scopeId, 'headHash': headHash, 'accountId': accountId},
    );
    final directory = await access.directoryAt(
      scopeId: scopeId,
      scopeHeadHash: headHash,
      accountId: accountId,
      directoryHeadHash: status['headHash'],
      online: true,
    );
    await _verifyIdentity(directory);
  }

  Future<void> _verifyIdentity(VerifiedAccountDirectory directory) async {
    final access = _service!.context.access;
    // The normal scoped directory route has replayed the signed history and
    // pinned first-use hosting trust. Manual comparison remains optional in
    // member settings; a changed existing root propagates as a typed failure.
    await access.identities.requireVerified(
      directory.accountId,
      access.identities.fingerprint(directory),
    );
  }

  Future<void> _approve(CryptoPendingApproval item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _failure = null;
      _waiting = false;
    });
    try {
      if (item.inheritedInvitation) {
        await CryptoInheritedInvitationGrants(
          _service!.context.access,
        ).finish(item.scopeId, item.value['invitationId'] as String);
      } else if (item.choiceReview) {
        await _approveChoices(item);
      } else if (item.choiceFinish) {
        await CryptoFinanceAccountChoices(
          _service!.context,
        ).finish(item.scopeId, item.value['selectionActionId'] as String);
      } else if (item.choiceMaterialize) {
        if (!await CryptoFinanceAccountChoices(
          _service!.context,
        ).materializeAvailable(item.scopeId)) {
          throw const CryptoAuthorityPending(
            'crypto_account_choices_publication_required',
          );
        }
      } else if (item.ownLeave) {
        final confirmed = await _leaveDialog(item, cancel: true);
        if (confirmed) {
          await CryptoBusinessLeave(
            _service!.context,
          ).cancel(item.scopeId, item.value['authorization'] as Map);
        }
      } else if (item.leaveRequest) {
        await CryptoBusinessLeave(
          _service!.context,
        ).verify(item.scopeId, item.value);
        if (await _leaveDialog(item, cancel: false)) {
          await CryptoBusinessLeave(
            _service!.context,
          ).prepare(item.scopeId, item.value);
        }
      } else if (item.leaveFinish) {
        final choice = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(_text(dialog, 'Dokončaj izstop', 'Finish leave')),
            content: Text(
              _text(
                dialog,
                'Izstop se izvede šele po vseh odobritvah. Pripravo lahko prekličete; če je zgodovina že zaključena, nato izberite Dokončaj zaščito z novimi ključi. Članstvo ostane nespremenjeno.',
                'Leave applies only after every approval. You can cancel preparation; if history is already closed, next select Finish protection to create new keys. Membership remains unchanged.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, 'cancel'),
                child: Text(
                  _text(dialog, 'Prekliči pripravo', 'Cancel preparation'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(_text(dialog, 'Nazaj', 'Back')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, 'finish'),
                child: Text(_text(dialog, 'Nadaljuj', 'Resume')),
              ),
            ],
          ),
        );
        final leave = CryptoBusinessLeave(_service!.context);
        if (choice == 'finish') await leave.finish(item.scopeId, item.value);
        if (choice == 'cancel') {
          await leave.cancelPlan(item.scopeId, item.value);
        }
      } else if (item.cleanup) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ScopeRecoveryPage(
              account: _service!.context.account,
              scopeId: item.scopeId,
              label: item.name,
            ),
          ),
        );
      } else if (item.lifecycle) {
        final access = _service!.context.access;
        final directory = await access.directoryAt(
          scopeId: item.scopeId,
          scopeHeadHash: item.value['membershipHeadHash'],
          accountId: item.value['parentAccountId'],
          directoryHeadHash: item.value['parentDirectoryHeadHash'],
          online: true,
        );
        if (!mounted) return;
        await _verifyIdentity(directory);
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              _text(
                dialog,
                'Arhiviranje iz nadrejenega prostora',
                'Archive through the parent space',
              ),
            ),
            content: SingleChildScrollView(
              child: Text(
                _text(
                  dialog,
                  'Dovolim preverjenemu upravitelju nadrejenega prostora, da arhivira in znova odpre ta projekt. Dovoljenje velja za trenutno članstvo in preverjene naprave upravitelja. Ne razkrije vsebine, ključev ali drugih članov projekta. Trenutna zahteva: ${item.value['archived'] == true ? 'arhiviraj' : 'znova odpri'}.',
                  'Allow the verified parent manager to archive and reopen this project while its current membership and the manager’s verified devices remain unchanged. This does not disclose project content, keys or other members. Current request: ${item.value['archived'] == true ? 'archive' : 'reopen'}.',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(_text(dialog, 'Prekliči', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(_text(dialog, 'Dovoli', 'Allow')),
              ),
            ],
          ),
        );
        if (accepted == true) await _service!.approveParent(item);
      } else {
        await _service!.approveAccess(
          item,
          review: (review, descriptor) async {
            final names = <String, String>{};
            final rows = await _service!.context.database.rows(
              'SELECT account_id,data FROM members WHERE partition=? AND scope_id=?',
              [_service!.context.partition, item.scopeId],
            );
            for (final row in rows) {
              final value = jsonDecode(row['data'] as String) as Map;
              final label = value['displayName'] ?? value['username'];
              if (label is String && label.isNotEmpty) {
                names[row['account_id'] as String] = label;
              }
            }
            for (final member in review.members) {
              if (!mounted) return false;
              final id = member['accountId'] as String;
              await _verifyProposedIdentity(
                item.scopeId,
                review.source.headHash,
                id,
              );
            }
            if (!mounted) return false;
            String? after;
            return await showDialog<bool>(
                  context: context,
                  builder: (_) => CryptoAccessApprovalDialog(
                    scopeName: item.name,
                    memberNames: names,
                    invitationConsequences:
                        (review.proposal['future']
                                as Map)['invitationConsequences']
                            as Map?,
                    invitations: review.invitations,
                    sourceMembers: review.source.members,
                    proposedMembers: review.members,
                    sourceDescriptor: descriptor,
                    proposedDescriptor: review.descriptor,
                    historyBasis: review.history.historyBasis,
                    historyDomains: review.history.domains,
                    loadPreview: () async {
                      final rows = await ScopeCryptoManager(
                        _service!.context.access,
                      ).previewRotation(review.history, afterId: after);
                      if (rows.isNotEmpty) after = rows.last.id;
                      try {
                        if (!mounted) return <String>[];
                        return [for (final row in rows) _previewSummary(row)];
                      } finally {
                        for (final row in rows) {
                          row.dispose();
                        }
                      }
                    },
                  ),
                ) ==
                true;
          },
        );
      }
      if (mounted) await _load();
    } on CryptoAuthorityPending catch (error) {
      if (mounted) {
        setState(() {
          _waiting = error.reason == 'crypto_access_approval_required';
          _failed = !_waiting;
          _failure = _waiting ? null : error;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _failure = error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveChoices(CryptoPendingApproval item) async {
    final proof = Map<String, dynamic>.from(
      item.value['offerAuthorization'] as Map,
    );
    final body =
        jsonDecode(utf8.decode(base64Decode(proof['commandBase64'] as String)))
            as Map;
    await _verifyProposedIdentity(
      item.scopeId,
      body['targetHeadHash'] as String,
      body['accountId'] as String,
    );
    final service = CryptoFinanceAccountChoices(_service!.context);
    final review = await service.reviewOffer(item.scopeId, proof);
    if (!mounted) return;
    final writers = (review['writers'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? selected;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(
            _text(
              dialog,
              'Izbire finančnih računov',
              'Financial account choices',
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      dialog,
                      'Potrdite celoten nabor ${review['selectionCount']} izbir preverjenega izdajatelja. Imena računov in stanje niso razkriti. Izberite napravo finančnega urednika, ki bo objavila ta točen nabor.',
                      'Approve the verified issuer’s complete set of ${review['selectionCount']} choices. Account names and balances are not disclosed. Select the finance editor device that will publish this exact set.',
                    ),
                  ),
                  for (final writer in writers)
                    ListTile(
                      selected: identical(selected, writer),
                      leading: Icon(
                        identical(selected, writer)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(
                        writer['displayName'] as String? ??
                            _text(dialog, 'Finančni urednik', 'Finance editor'),
                      ),
                      subtitle: Text(
                        writer['accountId'] ==
                                    _service!
                                        .context
                                        .account
                                        .directory
                                        .accountId &&
                                writer['deviceId'] ==
                                    _service!.context.account.deviceId
                            ? _text(dialog, 'Ta naprava', 'This device')
                            : '${_text(dialog, 'Naprava', 'Device')} ${(writer['deviceId'] as String).substring(0, 8)}',
                      ),
                      onTap: () => update(() => selected = writer),
                    ),
                  ExpansionTile(
                    title: Text(
                      _text(
                        dialog,
                        'Tehnične podrobnosti',
                        'Technical details',
                      ),
                    ),
                    children: [
                      SelectableText(
                        '${review['issuerAccountId']}\n${review['selectionHash']}',
                      ),
                      for (final writer in writers)
                        SelectableText(
                          '${writer['accountId']}\n${writer['deviceId']}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(_text(dialog, 'Prekliči', 'Cancel')),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(_text(dialog, 'Odobri nabor', 'Approve selection')),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || selected == null) return;
    final action = await _service!.context.reservedRecordId(
      item.scopeId,
      'accountChoiceSelection:approve:${item.value['offerHash']}:${selected!['accountId']}:${selected!['deviceId']}',
    );
    await service.approve(
      item.scopeId,
      proof,
      actionId: action,
      recipientAccountId: selected!['accountId'] as String,
      recipientDeviceId: selected!['deviceId'] as String,
    );
  }

  Future<bool> _leaveDialog(
    CryptoPendingApproval item, {
    required bool cancel,
  }) async {
    final proof = item.value['authorization'] as Map;
    final command =
        jsonDecode(utf8.decode(base64Decode(proof['commandBase64'] as String)))
            as Map;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              cancel
                  ? _text(
                      dialog,
                      'Prekliči zahtevo za izstop',
                      'Cancel leave request',
                    )
                  : _text(
                      dialog,
                      'Zahteva člana za izstop',
                      'Member leave request',
                    ),
            ),
            content: Text(
              cancel
                  ? _text(
                      dialog,
                      'Članstvo ostane veljavno. Že podpisanega zaključka zgodovine ni mogoče razveljaviti; upravitelj bo po potrebi dokončal zaščito.',
                      'Membership remains unchanged. A signed history closure cannot be undone; a manager may need to finish protection.',
                    )
                  : _text(
                      dialog,
                      '${item.value['displayName'] ?? 'Član'} (${command['accountId']}) prosi za izstop. Priprava še ne spremeni dostopa. Nato preglejte točno spremembo članstva za vsak svoj prostor in po vseh odobritvah izberite Dokončaj izstop.',
                      '${item.value['displayName'] ?? 'Member'} (${command['accountId']}) requests to leave. Preparation does not change access. Next review the exact membership change for each of your scopes, then select Finish leave after every required approval.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(_text(dialog, 'Nazaj', 'Back')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(
                  cancel
                      ? _text(dialog, 'Prekliči zahtevo', 'Cancel request')
                      : _text(dialog, 'Pripravi pregled', 'Prepare review'),
                ),
              ),
            ],
          ),
        ) ==
        true;
  }

  String _leaveState(String state) => switch (state) {
    'pending' => _text(
      context,
      'Izstop čaka na upravitelja; zahtevo lahko prekličete.',
      'Leave awaits a manager; you can cancel the request.',
    ),
    'applied' => _text(context, 'Izstop je dokončan.', 'Leave completed.'),
    'cancelled' => _text(
      context,
      'Zahteva za izstop je preklicana.',
      'Leave request cancelled.',
    ),
    _ => _text(
      context,
      'Zahtevo je treba obnoviti po novem pregledu članstva. Najprej jo prekličite.',
      'The request needs renewal after a new membership review. Cancel it first.',
    ),
  };

  String _previewSummary(ScopeRecoveryPreview item) =>
      cryptoRecoveryPreviewSummary(
        item.plaintext,
        deletedLabel: _text(context, 'Izbrisani zapis', 'Deleted record'),
        unknownLabel: _text(context, 'Zaščiteni zapis', 'Protected record'),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_text(context, 'Čakajoče odobritve', 'Pending approvals')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _text(
            context,
            'Preglejte spremembe za svoje prostore. Posamezna odobritev pripravi zaščito; skupna sprememba se izvede šele po vseh potrebnih odobritvah.',
            'Review changes for your spaces. Each approval prepares protection; the complete change applies after every required approval.',
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_waiting)
          Text(
            _text(
              context,
              'Najprej odobrite vse potrebne spremembe, nato znova izberite Dokončaj izstop.',
              'Approve all required scope changes, then select Finish leave again.',
            ),
          ),
        if (_failed || (_list?.unavailable ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _failed && _failure != null
                  ? sharingErrorMessage(context, _failure!)
                  : _text(
                      context,
                      'Nekaterih zahtev še ni mogoče preveriti. Obstoječi podatki in pravice so ohranjeni. Preverite povezavo in poskusite znova.',
                      'Some requests cannot be verified yet. Existing data and access are preserved. Check the connection and retry.',
                    ),
            ),
          ),
        if (_list != null && _list!.items.isEmpty && _list!.unavailable == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              _text(
                context,
                'Ni čakajočih odobritev.',
                'No pending approvals.',
              ),
            ),
          ),
        for (final item in _list?.items ?? <CryptoPendingApproval>[])
          Card(
            child: ListTile(
              title: Text(item.name),
              subtitle: Text(
                item.inheritedInvitation
                    ? context.l10n.cryptoSharingFinishInheritedProjects
                    : item.choiceReview
                    ? _text(
                        context,
                        'Pregled celotnega nabora računov',
                        'Review complete account selection',
                      )
                    : item.choiceFinish
                    ? _text(
                        context,
                        'Dokončaj odobreno objavo računov',
                        'Finish approved account publication',
                      )
                    : item.choiceMaterialize
                    ? _text(
                        context,
                        'Objavi odobrene izbire računov',
                        'Publish approved account choices',
                      )
                    : item.ownLeave
                    ? _leaveState(item.value['state'] as String)
                    : item.leaveRequest
                    ? _text(
                        context,
                        'Zahteva člana za izstop',
                        'Member leave request',
                      )
                    : item.leaveFinish
                    ? _text(
                        context,
                        'Dokončaj izstop po vseh odobritvah',
                        'Finish leave after every approval',
                      )
                    : item.cleanup
                    ? _text(
                        context,
                        'Dokončaj zaščito po preklicani pripravi',
                        'Finish protection after cancelled preparation',
                      )
                    : item.lifecycle
                    ? _text(
                        context,
                        'Dovoljenje za arhiviranje iz nadrejenega prostora',
                        'Parent archive permission',
                      )
                    : _text(
                        context,
                        'Sprememba članstva ali pravil dostopa',
                        'Membership or access policy change',
                      ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  _busy ||
                      item.ownLeave &&
                          const {
                            'applied',
                            'cancelled',
                          }.contains(item.value['state'])
                  ? null
                  : () => _approve(item),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          label: Text(_text(context, 'Osveži', 'Refresh')),
        ),
      ],
    ),
  );
}

/// Review uses authenticated source membership and the exact future roster the
/// child manager will sign. Recovery history needs separate explicit consent.
class CryptoAccessApprovalDialog extends StatefulWidget {
  const CryptoAccessApprovalDialog({
    super.key,
    required this.scopeName,
    required this.sourceMembers,
    required this.proposedMembers,
    required this.sourceDescriptor,
    required this.proposedDescriptor,
    required this.historyBasis,
    required this.historyDomains,
    this.loadPreview,
    this.memberNames = const {},
    this.invitationConsequences,
    this.invitations = const [],
  });
  final String scopeName, historyBasis;
  final List<Map<String, dynamic>> sourceMembers, proposedMembers;
  final Map<String, dynamic> sourceDescriptor, proposedDescriptor;
  final Map historyDomains;
  final Map<String, String> memberNames;
  final Map? invitationConsequences;
  final List<Map<String, dynamic>> invitations;
  final Future<List<String>> Function()? loadPreview;
  @override
  State<CryptoAccessApprovalDialog> createState() =>
      _CryptoAccessApprovalDialogState();
}

class _CryptoAccessApprovalDialogState
    extends State<CryptoAccessApprovalDialog> {
  bool _acceptedHistory = false,
      _loadingPreview = false,
      _previewed = false,
      _previewFailed = false;
  List<String> _preview = [];
  int _invitationLimit = 20;

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewFailed = false;
    });
    try {
      final rows = await widget.loadPreview!();
      if (mounted) {
        setState(() {
          _preview = rows;
          _previewed = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _previewFailed = true);
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  String _role(BuildContext context, Map? member) {
    if (member == null) return _text(context, 'brez dostopa', 'no access');
    final role = switch (member['role']) {
      'owner' => _text(context, 'lastnik', 'owner'),
      'editor' => _text(context, 'urejevalec', 'editor'),
      'member' => _text(context, 'član', 'member'),
      'viewer' => _text(context, 'bralec', 'viewer'),
      _ => throw const FormatException('crypto_approval_role'),
    };
    final finance = switch (member['financeRole']) {
      'write' => _text(context, 'urejanje financ', 'finance write'),
      'read' => _text(context, 'ogled financ', 'finance read'),
      'none' => _text(context, 'brez financ', 'no finance'),
      _ => throw const FormatException('crypto_approval_finance'),
    };
    return '$role; $finance; ${member['manageKeys'] == true ? _text(context, 'upravlja zaščito', 'manages protection') : _text(context, 'ne upravlja zaščite', 'does not manage protection')}';
  }

  String _policy(BuildContext context, Object? value) => switch (value) {
    1 => _text(
      context,
      'Ločena projektna povabila',
      'Separate project invitations',
    ),
    2 => _text(
      context,
      'Projektni člani vidijo finance; vodje vse projekte',
      'Project members see finances; leaders see all projects',
    ),
    3 => _text(
      context,
      'Članstvo v prostoru vključuje vse projekte in finance',
      'Space membership includes all projects and finances',
    ),
    _ => throw const FormatException('crypto_approval_policy'),
  };
  String _kind(BuildContext context, Object? value) => switch (value) {
    'project' => _text(context, 'Projekt', 'Project'),
    'household' => _text(context, 'Gospodinjstvo', 'Household'),
    'organization' => _text(context, 'Organizacija', 'Organization'),
    'personal' => _text(context, 'Osebni prostor', 'Personal space'),
    _ => throw const FormatException('crypto_approval_scope_kind'),
  };

  @override
  Widget build(BuildContext context) {
    final recovery = widget.historyBasis == 'reviewedRecoveryBaseline';
    final previewAvailable = _previewed;
    final changes = cryptoApprovalRosterDiff(
      widget.sourceMembers,
      widget.proposedMembers,
    );
    final before = widget.sourceDescriptor, after = widget.proposedDescriptor;
    return AlertDialog(
      title: Text(widget.scopeName),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _text(
                  context,
                  'Pregled članstva in dostopa',
                  'Membership and access review',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final change in changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(
                    '${widget.memberNames[change['accountId']] ?? _text(context, 'Član', 'Member')}\n${change['accountId']}\n${_role(context, change['before'] as Map?)} → ${_role(context, change['after'] as Map?)}',
                  ),
                ),
              if (changes.isEmpty)
                Text(
                  _text(
                    context,
                    'Članstvo in vloge ostanejo enaki.',
                    'Membership and roles remain unchanged.',
                  ),
                ),
              Text(
                '${_policy(context, before['accessPolicyVersion'])} → ${_policy(context, after['accessPolicyVersion'])}',
              ),
              if (before['kind'] != after['kind'])
                Text(
                  '${_kind(context, before['kind'])} → ${_kind(context, after['kind'])}',
                ),
              if (after.containsKey('leaderAccountIds')) ...[
                Text(
                  _text(
                    context,
                    'Vodje organizacije (lastnik ostane vodja)',
                    'Organization leaders (the owner remains a leader)',
                  ),
                ),
                for (final id in {
                  ...((before['leaderAccountIds'] as List?) ?? []),
                  ...((after['leaderAccountIds'] as List?) ?? []),
                }.toList()..sort())
                  if (((before['leaderAccountIds'] as List?) ?? []).contains(
                        id,
                      ) !=
                      (after['leaderAccountIds'] as List).contains(id))
                    Text(
                      '${widget.memberNames[id] ?? _text(context, 'Član', 'Member')} · $id: ${(after['leaderAccountIds'] as List).contains(id) ? _text(context, 'postane vodja', 'becomes a leader') : _text(context, 'ne bo več vodja', 'stops being a leader')}',
                    ),
              ],
              if (before['parentScopeToken'] != after['parentScopeToken'])
                Text(
                  _text(
                    context,
                    'Spremeni se povezava z nadrejenim prostorom.',
                    'The parent space relationship changes.',
                  ),
                ),
              if (widget.invitationConsequences != null) ...[
                const SizedBox(height: 12),
                Text(
                  _text(
                    context,
                    'Preklic povabil v tem prostoru',
                    'Invitation cancellation in this space',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  _text(
                    context,
                    'Ta sprememba prekliče ${widget.invitationConsequences!['invitationCount']} še neporabljenih povabil v tem prostoru. Že porabljena povabila in zgodovinski odgovori ostanejo ohranjeni.',
                    'This change cancels ${widget.invitationConsequences!['invitationCount']} outstanding invitations in this space. Consumed invitations and historical outcomes are preserved.',
                  ),
                ),
                for (final invitation in widget.invitations.take(
                  _invitationLimit,
                ))
                  SelectableText(
                    '${_text(context, 'Povabilo', 'Invitation')} · ${invitation['id']}',
                  ),
                if (widget.invitations.length > _invitationLimit)
                  TextButton(
                    onPressed: () => setState(() => _invitationLimit += 20),
                    child: Text(
                      _text(
                        context,
                        'Preglej naslednja povabila',
                        'Review next invitations',
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(_text(context, 'Preverjena zgodovina', 'Verified history')),
              for (final entry in widget.historyDomains.entries)
                Text(
                  '${entry.key == 'finance' ? _text(context, 'Finance', 'Finances') : _text(context, 'Vsebina', 'Content')}: ${(entry.value as Map)['count']}',
                ),
              if (_previewFailed)
                Text(
                  _text(
                    context,
                    'Pregled še ni na voljo. Poskusite znova.',
                    'The preview is not available yet. Retry.',
                  ),
                ),
              if (recovery && widget.loadPreview != null) ...[
                if (_previewed && _preview.isEmpty)
                  Text(
                    _text(
                      context,
                      'V tem pregledu ni razpoložljivih zapisov.',
                      'No records are available in this preview.',
                    ),
                  ),
                for (final text in _preview)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(text),
                    ),
                  ),
                TextButton(
                  onPressed: _loadingPreview ? null : _loadPreview,
                  child: Text(
                    _text(
                      context,
                      'Preglej naslednje zapise',
                      'Review next records',
                    ),
                  ),
                ),
                if (_loadingPreview) const LinearProgressIndicator(),
              ],
              if (recovery)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _acceptedHistory,
                  onChanged: !previewAvailable
                      ? null
                      : (value) =>
                            setState(() => _acceptedHistory = value == true),
                  title: Text(
                    _text(
                      context,
                      'Pregledal sem obnovljeno začetno stanje. Razpoložljiva zgodovina je lahko starejša; to stanje izrecno sprejemam.',
                      'I reviewed the recovered starting snapshot. Available history may be older; I explicitly accept this starting state.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_text(context, 'Prekliči', 'Cancel')),
        ),
        FilledButton(
          onPressed:
              _loadingPreview ||
                  recovery && (!_acceptedHistory || !previewAvailable)
              ? null
              : () => Navigator.pop(context, true),
          child: Text(_text(context, 'Odobri spremembo', 'Approve change')),
        ),
      ],
    );
  }
}
