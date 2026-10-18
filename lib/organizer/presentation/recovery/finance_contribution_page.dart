import 'crypto_record_preview.dart';
import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../../data/e2ee/session_crypto_access.dart';

/// Public proposals travel through the authenticated pending queue. Financial
/// private keys stay exclusively with an independently authorized reader.
class FinanceContributionPage extends StatefulWidget {
  const FinanceContributionPage({
    required this.account,
    required this.scopeId,
    required this.label,
    super.key,
  });
  final AccountCryptoV2Workflow account;
  final String scopeId, label;
  @override
  State<FinanceContributionPage> createState() =>
      _FinanceContributionPageState();
}

class _FinanceContributionPageState extends State<FinanceContributionPage> {
  late final access = SessionCryptoAccess(account: widget.account);
  late final manager = ScopeCryptoManager(access);
  List<Map<String, dynamic>> _drafts = [];
  List<ScopeRecoveryPreview> _preview = [];
  ScopeRotationReview? _review;
  Map<String, dynamic>? _selected;
  bool _busy = false, _failed = false, _accepted = false, _published = false;
  void _clear() {
    for (final item in _preview) {
      item.dispose();
    }
    _preview = [];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final drafts = await manager.financeDrafts(widget.scopeId);
    if (mounted) setState(() => _drafts = drafts);
  });
  Future<void> _inspect(Map<String, dynamic> draft) => _run(() async {
    final core = draft['core'] as Map;
    ScopeRotationReview? review;
    List<ScopeRecoveryPreview> preview = [];
    if ((core['epoch'] as int) > 1) {
      final source = await access.recoveryCandidateHead(widget.scopeId);
      if (source.commitment('finance') != null) {
        review = await manager.reviewRotation(
          widget.scopeId,
          financeOnly: true,
        );
        preview = await manager.previewRotation(review);
      }
    }
    if (!mounted) {
      for (final row in preview) {
        row.dispose();
      }
      return;
    }
    _clear();
    setState(() {
      _selected = draft;
      _review = review;
      _preview = preview;
      _accepted = false;
      _published = false;
    });
  });
  Future<void> _approve() => _run(() async {
    final draft = _selected;
    if (draft == null || !_accepted) return;
    await manager.contributeFinanceDraft(
      widget.scopeId,
      draft['draftId'],
      reviewedInventory: _review,
    );
    if (mounted) setState(() => _published = true);
  });
  Future<void> _finish() => _run(() async {
    final draft = _selected;
    if (draft == null) return;
    await manager.publishFinanceGrants(widget.scopeId, draft['draftId']);
    _clear();
    if (mounted) setState(() => _selected = null);
  });
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoFinanceContributionTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(l.cryptoFinanceContributionExplanation),
                const SizedBox(height: 12),
                Text(l.cryptoMigrationLocalAvailable),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(l.cryptoFinanceContributionPending),
                if (_selected == null) ...[
                  if (_drafts.isEmpty) Text(l.cryptoFinanceNoRequests),
                  for (final draft in _drafts)
                    Card(
                      child: ListTile(
                        title: Text(l.cryptoFinanceReviewRequest),
                        subtitle: Text(l.cryptoFinanceContributionPending),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _inspect(draft),
                      ),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: Text(l.cryptoMigrationRetry),
                  ),
                ] else if (_published) ...[
                  Text(l.cryptoFinanceWaitingOwner),
                  FilledButton(
                    onPressed: _busy ? null : _finish,
                    child: Text(l.cryptoFinanceFinishContribution),
                  ),
                ] else ...[
                  Text(l.cryptoScopeRecoveryExplanation),
                  Text(
                    l.cryptoScopeRecoveryCount(
                      l.organizerFinances,
                      _review?.domains['finance']?['count'] as int? ?? 0,
                    ),
                  ),
                  for (final row in _preview)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          cryptoRecoveryPreviewSummary(
                            row.plaintext,
                            deletedLabel: l.cryptoScopeDeleted,
                            unknownLabel: l.cryptoScopeContent,
                          ),
                        ),
                      ),
                    ),
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _accepted = v == true),
                    title: Text(l.cryptoFinanceAcceptContribution),
                  ),
                  FilledButton(
                    onPressed: _busy || !_accepted ? null : _approve,
                    child: Text(l.cryptoFinanceApproveContribution),
                  ),
                ],
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l.done),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
