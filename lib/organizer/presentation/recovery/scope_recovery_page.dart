import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/scope_crypto_manager.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../platform/recovery/recovery_file_io.dart';

class ScopeRecoveryPage extends ConsumerStatefulWidget {
  const ScopeRecoveryPage({
    required this.account,
    required this.scopeId,
    required this.label,
    super.key,
  });
  final AccountCryptoV2Workflow account;
  final String scopeId, label;
  @override
  ConsumerState<ScopeRecoveryPage> createState() => _ScopeRecoveryPageState();
}

class _ScopeRecoveryPageState extends ConsumerState<ScopeRecoveryPage> {
  late final manager = ScopeCryptoManager(
    SessionCryptoAccess(account: widget.account),
  );
  ScopeRotationReview? _review;
  List<Map<String, dynamic>>? _members;
  final _names = <String, String>{};
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() => _run(() async {
    final rows = await widget.account.store.database.rows(
      'SELECT account_id,data FROM members WHERE partition=? AND scope_id=?',
      [widget.account.store.partition, widget.scopeId],
    );
    for (final row in rows) {
      final value = jsonDecode(row['data'] as String) as Map;
      _names[row['account_id'] as String] =
          (value['displayName'] ?? value['username'] ?? '') as String;
    }
    final reviews = await manager.pendingRotationReviews(widget.scopeId);
    if (reviews.isNotEmpty) {
      final review = reviews.first,
          proposed = await manager.proposedMembers(reviews.first);
      final preview = await manager.previewRotation(review);
      if (!mounted) {
        for (final row in preview) {
          row.dispose();
        }
        return;
      }
      setState(() {
        _review = review;
        _members = proposed;
        _preview = preview;
      });
    }
  });
  Future<void> _editMembers() => _run(() async {
    final head = await manager.access.recoveryCandidateHead(widget.scopeId);
    if (mounted) {
      setState(
        () => _members = [
          for (final m in head.members) Map<String, dynamic>.from(m),
        ],
      );
    }
  });
  Future<void> _cancel() => _run(() async {
    final review = _review;
    if (review == null) return;
    await manager.cancelRotation(review);
    _clearPreview();
    if (mounted) {
      setState(() {
        _review = null;
        _members = null;
        _accepted = false;
      });
    }
  });
  List<ScopeRecoveryPreview> _preview = [];
  bool _busy = false, _failed = false, _accepted = false, _complete = false;
  void _clearPreview() {
    for (final item in _preview) {
      item.dispose();
    }
    _preview = [];
  }

  @override
  void dispose() {
    _clearPreview();
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

  Future<void> _reviewLocal() => _run(() async {
    final review = await manager.reviewRotation(widget.scopeId),
        preview = await manager.previewRotation(review);
    if (!mounted) {
      for (final row in preview) row.dispose();
      return;
    }
    _clearPreview();
    setState(() {
      _review = review;
      _preview = preview;
      _accepted = false;
    });
  });
  Future<void> _reviewFile() => _run(() async {
    final file = await ref.read(recoveryFileIoProvider).pick();
    if (file == null) return;
    try {
      final review = await manager.reviewRotation(
        widget.scopeId,
        recoveryFile: file,
      );
      final preview = await manager.previewRotation(review);
      if (!mounted) {
        for (final item in preview) {
          item.dispose();
        }
        return;
      }
      _clearPreview();
      setState(() {
        _review = review;
        _preview = preview;
        _accepted = false;
      });
    } finally {
      file.fillRange(0, file.length, 0);
    }
  });
  Future<void> _nextPage() => _run(() async {
    final review = _review;
    if (review == null || _preview.isEmpty) return;
    final next = await manager.previewRotation(
      review,
      afterId: _preview.last.id,
    );
    if (!mounted) {
      for (final item in next) {
        item.dispose();
      }
      return;
    }
    _clearPreview();
    setState(() => _preview = next);
  });
  Future<void> _confirm() => _run(() async {
    final review = _review;
    if (review == null || !_accepted) return;
    await manager.confirmRotation(
      review,
      acceptedCandidateHistory: true,
      members: _members,
    );
    _clearPreview();
    if (mounted) setState(() => _complete = true);
  });
  String _previewSummary(ScopeRecoveryPreview item) {
    if(item.plaintext==null)return context.l10n.cryptoScopeDeleted;
    try {
      final decoded=jsonDecode(utf8.decode(item.plaintext!));
      final value=decoded is Map && decoded['payload'] is Map?decoded['payload']:decoded;
      if(value is Map) {
        final parts=<String>[];
        for(final key in ['title','name','description','notes']) {
          if(value[key] is String && (value[key] as String).isNotEmpty) {
            final text=value[key] as String;parts.add(text.length>1000?'${text.substring(0,1000)}…':text);
          }
        }
        if(parts.isNotEmpty)return parts.join('\n');
      }
    }catch(_){/* Original evidence is retained; previews never expose protocol. */}
    return context.l10n.cryptoScopeRecoveryCount(context.l10n.cryptoScopeContent,1);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, review = _review;
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoScopeRecoveryTitle)),
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
                Text(l.cryptoScopeRecoveryExplanation),
                const SizedBox(height: 12),
                Text(l.cryptoMigrationLocalAvailable),
                if (_busy) const LinearProgressIndicator(),
                if (_failed) Text(l.cryptoScopeRecoveryPending),
                if (_complete)
                  Text(l.cryptoScopeRecoveryComplete)
                else if (review == null) ...[
                  OutlinedButton(
                    onPressed: _busy ? null : _reviewLocal,
                    child: Text(l.cryptoScopeReviewLocal),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _reviewFile,
                    child: Text(l.cryptoScopeRecoveryImport),
                  ),
                ] else ...[
                  for (final domain in review.domains.keys)
                    Text(
                      l.cryptoScopeRecoveryCount(
                        domain == 'finance'
                            ? l.organizerFinances
                            : l.cryptoScopeContent,
                        review.domains[domain]['count'] as int,
                      ),
                    ),
                  for (final item in _preview)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _previewSummary(item),
                        ),
                      ),
                    ),
                  if (_preview.isNotEmpty)
                    TextButton(
                      onPressed: _busy ? null : _nextPage,
                      child: Text(l.cryptoScopeNextPreview),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : _editMembers,
                    child: Text(l.cryptoScopeManageMembers),
                  ),
                  if (_members != null) ...[
                    Text(l.cryptoScopeTransferExplanation),
                    for (final member in _members!)
                      ListTile(
                        title: Text(
                          _names[member['accountId']]?.isNotEmpty == true
                              ? _names[member['accountId']]!
                              : l.cryptoScopeMember,
                        ),
                        subtitle: Text(
                          (member['accountId'] as String).substring(0, 8),
                        ),
                        trailing: DropdownButton<String>(
                          value: member['role'],
                          items: [
                            DropdownMenuItem(
                              value: 'owner',
                              child: Text(l.cryptoScopeOwner),
                            ),
                            DropdownMenuItem(
                              value: 'member',
                              child: Text(l.cryptoScopeMember),
                            ),
                            DropdownMenuItem(
                              value: 'viewer',
                              child: Text(l.cryptoScopeViewer),
                            ),
                            DropdownMenuItem(
                              value: 'remove',
                              child: Text(l.cryptoScopeRemoveMember),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == 'remove') {
                                    _members!.remove(member);
                                  } else {
                                    if (value == 'owner')
                                      for (final other in _members!) {
                                        if (other['role'] == 'owner') {
                                          other['role'] = 'member';
                                          other['manageKeys'] = false;
                                        }
                                      }
                                    member['role'] = value;
                                    member['manageKeys'] = value == 'owner';
                                  }
                                  _accepted = false;
                                }),
                        ),
                      ),
                  ],
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _accepted = v == true),
                    title: Text(l.cryptoScopeAcceptCandidate),
                  ),
                  FilledButton(
                    onPressed: _busy || !_accepted ? null : _confirm,
                    child: Text(l.cryptoScopeConfirmRecovery),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(l.cryptoScopeCancelPreparation),
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
