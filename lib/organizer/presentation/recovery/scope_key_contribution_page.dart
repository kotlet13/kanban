import 'crypto_record_preview.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../../data/e2ee/scope_key_contributions.dart';
import '../../data/e2ee/session_crypto_access.dart';

/// The authenticated queue carries public proposals. Each recipient creates
/// only the domain keys it is entitled to hold, then confirms the final roster.
class ScopeKeyContributionPage extends StatefulWidget {
  const ScopeKeyContributionPage({
    required this.account,
    required this.scopeId,
    required this.label,
    super.key,
  });
  final AccountCryptoV2Workflow account;
  final String scopeId, label;
  @override
  State<ScopeKeyContributionPage> createState() =>
      _ScopeKeyContributionPageState();
}

class _ScopeKeyContributionPageState extends State<ScopeKeyContributionPage> {
  late final manager = ScopeCryptoManager(
    SessionCryptoAccess(account: widget.account),
  );
  late final service = ScopeKeyContributions(manager);
  List<Map<String, dynamic>> _drafts = [];
  bool _busy = false, _failed = false, _accepted = false;
  ScopeRotationReview? _review;
  List<ScopeRecoveryPreview> _preview = [];
  final _names = <String, String>{};
  @override
  void dispose() {
    for (final row in _preview) {
      row.dispose();
    }
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _refresh() async {
    final cached = await widget.account.store.database.rows(
      'SELECT account_id,data FROM members WHERE partition=? AND scope_id=?',
      [widget.account.store.partition, widget.scopeId],
    );
    for (final row in cached) {
      final m = jsonDecode(row['data'] as String) as Map;
      _names[row['account_id'] as String] =
          (m['displayName'] ?? m['username'] ?? '') as String;
    }
    final list = await service.list(widget.scopeId);
    final verified = <Map<String, dynamic>>[];
    for (final row in list) {
      verified.add(await service.get(widget.scopeId, row['draftId']));
    }
    if (mounted) setState(() => _drafts = verified);
  }

  Future<void> _load() => _run(_refresh);
  Future<void> _offer(Map<String, dynamic> draft, String domain) =>
      _run(() async {
        ScopeRotationReview? review;
        if (domain == 'finance' && (draft['core']['epoch'] as int) > 1) {
          review =
              _review ??
              await manager.reviewRotation(widget.scopeId, financeOnly: true);
          if (!_accepted) {
            final preview = await manager.previewRotation(review);
            if (!mounted) {
              for (final row in preview) {
                row.dispose();
              }
              return;
            }
            for (final row in _preview) {
              row.dispose();
            }
            setState(() {
              _review = review;
              _preview = preview;
            });
            return;
          }
        }
        await service.offer(
          widget.scopeId,
          draft['draftId'],
          domain,
          financeReview: review,
        );
        await _refresh();
      });
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, own = widget.account.directory.accountId;
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoKeyContributionTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(l.cryptoKeyContributionExplanation),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(l.cryptoKeyContributionPending),
                if (_drafts.isEmpty && !_busy)
                  Text(l.cryptoKeyContributionEmpty),
                if (_review != null) ...[
                  Text(l.cryptoScopeRecoveryExplanation),
                  for (final domain in _review!.domains.keys)
                    Text(
                      l.cryptoScopeRecoveryCount(
                        domain == 'finance'
                            ? l.organizerFinances
                            : l.cryptoScopeContent,
                        _review!.domains[domain]['count'] as int,
                      ),
                    ),
                  for (final row in _preview)
                    SelectableText(
                      cryptoRecoveryPreviewSummary(
                        row.plaintext,
                        deletedLabel: l.cryptoScopeDeleted,
                        unknownLabel: l.cryptoScopeContent,
                      ),
                    ),
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _accepted = v == true),
                    title: Text(l.cryptoFinanceAcceptContribution),
                  ),
                ],
                for (final draft in _drafts)
                  Builder(
                    builder: (context) {
                      final members = (draft['core']['members'] as List)
                          .where((m) => m['accountId'] == own)
                          .toList();
                      if (members.length != 1) return const SizedBox.shrink();
                      final member = members.single as Map;
                      final domains = (draft['requestedDomains'] as List).where(
                        (d) => d == 'content'
                            ? member['role'] == 'owner'
                            : member['financeRole'] != 'none',
                      );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(l.cryptoKeyContributionPending),
                              for (final m in draft['core']['members'] as List)
                                ListTile(
                                  title: Text(
                                    _names[m['accountId']]?.isNotEmpty == true
                                        ? _names[m['accountId']]!
                                        : l.cryptoScopeMember,
                                  ),
                                  subtitle: Text(
                                    m['role'] == 'owner'
                                        ? l.cryptoScopeOwner
                                        : m['role'] == 'viewer'
                                        ? l.cryptoScopeViewer
                                        : l.cryptoScopeMember,
                                  ),
                                ),
                              for (final domain in domains) ...[
                                Text(
                                  domain == 'finance'
                                      ? l.organizerFinances
                                      : l.cryptoScopeContent,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _offer(draft, domain),
                                  child: Text(l.cryptoKeyContributionOffer),
                                ),
                                OutlinedButton(
                                  onPressed: _busy || draft['finalCore'] == null
                                      ? null
                                      : () => _run(() async {
                                          await service.sign(
                                            widget.scopeId,
                                            draft['draftId'],
                                            domain,
                                          );
                                          await _refresh();
                                        }),
                                  child: Text(l.cryptoKeyContributionSign),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                          if (domain == 'content') {
                                            await service.publishContent(
                                              widget.scopeId,
                                              draft['draftId'],
                                            );
                                          } else {
                                            await service.publishFinance(
                                              widget.scopeId,
                                              draft['draftId'],
                                            );
                                          }
                                          await _refresh();
                                        }),
                                  child: Text(l.cryptoKeyContributionPublish),
                                ),
                              ],
                              if (member['role'] == 'owner')
                                FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() async {
                                          await service.acceptOwnership(
                                            widget.scopeId,
                                            draft['draftId'],
                                          );
                                          await _refresh();
                                        }),
                                  child: Text(
                                    l.cryptoKeyContributionAcceptOwner,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: Text(l.cryptoMigrationRetry),
                ),
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
