import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../data/e2ee/crypto_sync_repository.dart';
import '../../data/collaboration_transport.dart';
import '../../data/e2ee/crypto_json.dart';

/// Explicit generation review; imported caches never enable its acceptance.
class CryptoMigrationGenerationPage extends StatefulWidget {
  const CryptoMigrationGenerationPage({
    required this.coordinator,
    required this.scopeId,
    required this.migrationId,
    super.key,
  });
  final CryptoMigrationCoordinator coordinator;
  final String scopeId, migrationId;
  @override
  State<CryptoMigrationGenerationPage> createState() => _GenerationState();
}

class _GenerationState extends State<CryptoMigrationGenerationPage> {
  Map<String, dynamic>? _state;
  bool _busy = false;
  String? _error;
  String? _rejectedCommitRequest;
  bool get sl => Localizations.localeOf(context).languageCode == 'sl';
  get api => widget.coordinator.generation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CryptoAuthorityPending
              ? error.reason
              : 'incomplete',
        );
      }
    } finally {
      final generation = _state?['generationId'];
      if (generation is String && _state?['context']?['mode'] == 'continue') {
        try {
          final rejected = await api.rejectedCommitRequest(generation);
          if (mounted) setState(() => _rejectedCommitRequest = rejected);
        } catch (_) {
          if (mounted) setState(() => _rejectedCommitRequest = null);
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    final value = await api.forMigration(widget.migrationId);
    if (mounted) setState(() => _state = value);
  });
  Future<void> _prepare({bool renew = false}) => _run(() async {
    Map<String, dynamic> value;
    try {
      value = await _prepareAttempt(false, renew: renew);
    } on CollaborationApiException catch (error) {
      if (error.code != 'crypto_migration_generation_publication_boundary') {
        rethrow;
      }
      value = await _prepareAttempt(true, renew: renew);
    }
    if (mounted) setState(() => _state = value);
  });

  Future<Map<String, dynamic>> _prepareAttempt(
    bool published, {
    bool renew = false,
  }) async {
    final account = widget.coordinator.account,
        db = widget.coordinator.account.store.database;
    final name =
        'migration_generation_request:${account.store.partition}:${widget.migrationId}:$published';
    final saved = await db.rows('SELECT value FROM local_meta WHERE name=?', [
      name,
    ]);
    final id = saved.isEmpty || renew
        ? account.directory.reducer.crypto.randomId()
        : saved.single['value'] as String;
    if (saved.isEmpty) {
      await db.execute('INSERT INTO local_meta VALUES(?,?)', [name, id]);
    } else if (renew) {
      final history =
          'migration_generation_request_history:${account.store.partition}:$id';
      await db.execute('INSERT INTO local_meta VALUES(?,?)', [history, id]);
      await db.execute('UPDATE local_meta SET value=? WHERE name=?', [
        id,
        name,
      ]);
    }
    try {
      return await api.prepare(
        migrationId: widget.migrationId,
        generationId: id,
        afterPublication: published,
      );
    } on CryptoAuthorityPending catch (error) {
      if (error.reason != 'crypto_command_receipt_pending') rethrow;
      // commandResult masks rejected commands as pending. Only the exact
      // conclusive receipt of this immutable attempt permits choosing the
      // already supported continuation mode; all other failures propagate.
      final rows = await db.rows(
        'SELECT o.* FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key=?',
        [account.store.partition, 'generationPrepare:$id'],
      );
      if (rows.length != 1 || rows.single['state'] != 'rejected') rethrow;
      final row = rows.single,
          receipt = jsonDecode(row['response'] as String) as Map,
          signed = jsonDecode(row['signed_body'] as String) as Map,
          command =
              CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
      if (row['operation'] != 'crypto2.migration.generation.prepare' ||
          command['operation'] != row['operation'] ||
          command['payload']['migrationId'] != widget.migrationId ||
          command['payload']['generationId'] != id ||
          command['payload']['mode'] !=
              (published ? 'continue' : 'supersede') ||
          receipt['status'] != 409 ||
          receipt['requestId'] != row['request_id'] ||
          receipt['requestHash'] != row['request_hash'] ||
          base64Encode(CryptoJson.encode(receipt['authorization'])) !=
              base64Encode(CryptoJson.encode(signed)) ||
          receipt['response'] is! Map ||
          receipt['response']['errorCode'] !=
              'crypto_migration_generation_publication_boundary') {
        rethrow;
      }
      throw const CollaborationApiException(
        'crypto_migration_generation_publication_boundary',
      );
    }
  }

  Future<void> _draft(Map target) => _run(() async {
    final sid = target['scopeId'];
    String? after;
    Map? selected;
    do {
      final page = await widget.coordinator.account.directory.call(
        'crypto2.scopes.catalog',
        {'limit': 50, if (after != null) 'afterId': after},
      );
      for (final row in page['scopes'] as List) {
        if (row['id'] == sid) selected = row as Map;
      }
      if (selected != null || page['hasMore'] != true) break;
      final next = page['nextAfterId'];
      if (next is! String || next == after) {
        throw const FormatException('crypto_catalog_cursor');
      }
      after = next;
    } while (true);
    if (selected == null ||
        selected['accessRevision'] != target['accessRevision']) {
      throw const CryptoAuthorityPending('crypto_migration_generation_changed');
    }
    await api.draft(
      generationId: _state!['generationId'],
      scopeId: sid,
      accessRevision: target['accessRevision'],
      members: (selected['members'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
    );
    final value = await api.status(_state!['generationId']);
    if (mounted) setState(() => _state = value);
  });
  Future<bool> _review(Map<String, dynamic> exact) async {
    if (!mounted) return false;
    var accepted = false;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(
                sl ? 'Preglejte nadaljevanje' : 'Review continuation',
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        exact['mode'] == 'supersede'
                            ? (sl
                                  ? 'Pripravljeni bodo novi ključi. Vsi spodnji člani in njihove vloge morajo ostati pravilni. Stari poskus in dokazi ostanejo ohranjeni.'
                                  : 'Fresh keys will be used. Check every member and role below. The previous attempt and evidence are retained.')
                            : (sl
                                  ? 'Ohranijo se isti ključi in že potrjeni podatki. Potrditev dovoljuje samo zaključek istega preverjenega poskusa.'
                                  : 'The same keys and already approved data are retained. Approval only permits finishing this same verified attempt.'),
                      ),
                      for (final target in exact['reviewTargets'] as List)
                        ExpansionTile(
                          title: Text(
                            '${sl ? 'Prostor' : 'Space'} · ${(target['scopeId'] as String).substring(0, 8)}',
                          ),
                          children: [
                            for (final member in target['members'] as List)
                              ListTile(
                                title: Text(
                                  member['role'] == 'owner'
                                      ? (sl ? 'Lastnik' : 'Owner')
                                      : member['role'] == 'viewer'
                                      ? (sl ? 'Bralec' : 'Reader')
                                      : (sl ? 'Član' : 'Member'),
                                ),
                                subtitle: Text(
                                  '${member['accountId']}\n${sl ? 'Finance' : 'Finance'}: ${member['financeRole']}${member['manageKeys'] == true ? (sl ? ' · upravlja ključe' : ' · manages keys') : ''}',
                                ),
                              ),
                          ],
                        ),
                      CheckboxListTile(
                        value: accepted,
                        onChanged: (v) => update(() => accepted = v == true),
                        title: Text(
                          sl
                              ? 'Potrjujem ta točen pregled'
                              : 'I approve this exact review',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(sl ? 'Prekliči' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: accepted
                      ? () => Navigator.pop(dialog, true)
                      : null,
                  child: Text(sl ? 'Potrdi' : 'Approve'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final value = _state, mode = value?['mode'], state = value?['state'];
    return Scaffold(
      appBar: AppBar(
        title: Text(sl ? 'Nadaljevanje priprave' : 'Resume preparation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sl
                  ? 'Ta korak je namenjen prekinjenemu poskusu po menjavi naprave. Ne izbriše stare vsebine ali dokazov in ne potrdi obnovljene vsebine samodejno.'
                  : 'Use this step for an interrupted attempt after changing devices. It preserves old data and evidence and never approves recovered content automatically.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                sl
                    ? 'Nadaljevanje še ni popolno. Potrebni so prvotni podpisani dokazi in potrditve vseh sodelujočih. Če podpis manjka, ostane prvotni poskus ohranjen in samo za branje.'
                    : 'Continuation is incomplete. Original signed evidence and all contributors’ approvals are required. Missing signatures leave the original attempt preserved and read only.',
              ),
            if (value == null)
              OutlinedButton(
                onPressed: _busy ? null : _prepare,
                child: Text(
                  sl ? 'Pripravi nadaljevanje' : 'Prepare continuation',
                ),
              ),
            if (value != null) ...[
              Text(
                mode == 'supersede'
                    ? (sl
                          ? 'Nov pripravljalni poskus'
                          : 'Fresh preparatory attempt')
                    : (sl
                          ? 'Nadaljevanje istega poskusa'
                          : 'Continue the same attempt'),
              ),
              if (state != 'superseded')
                TextButton(
                  onPressed: _busy ? null : () => _prepare(renew: true),
                  child: Text(
                    sl
                        ? 'Po spremembi pravic začni nov izrecen pregled'
                        : 'Start a fresh explicit review after sharing changes',
                  ),
                ),
              if (state == 'drafting') ...[
                for (final target in value['targets'] as List)
                  if (mode == 'supersede' && target['canDraft'] == true)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _draft(target as Map),
                      child: Text(
                        '${sl ? 'Pripravi ključe prostora' : 'Prepare space keys'} · ${(target['scopeId'] as String).substring(0, 8)}',
                      ),
                    ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final next = await api.seal(value['generationId']);
                          if (mounted) setState(() => _state = next);
                        }),
                  child: Text(
                    sl
                        ? 'Zakleni pregled vseh priprav'
                        : 'Freeze complete review',
                  ),
                ),
              ],
              if (state == 'review') ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final next = await api.approve(
                            value['generationId'],
                            review: _review,
                          );
                          if (mounted) setState(() => _state = next);
                        }),
                  child: Text(sl ? 'Preglej in podpiši' : 'Review and sign'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          if (mode == 'supersede') {
                            await api.finish(
                              value['generationId'],
                              value['contextHash'],
                            );
                            await widget.coordinator.adoptGenerationSuccessor(
                              scopeId: widget.scopeId,
                              generationId: value['generationId'],
                            );
                          } else {
                            await api.resumeAcceptedCommit(
                              value['generationId'],
                            );
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        }),
                  child: Text(
                    sl
                        ? 'Zaključi po vseh potrditvah'
                        : 'Finish after all approvals',
                  ),
                ),
              ],
              if (state == 'review' &&
                  mode == 'continue' &&
                  _rejectedCommitRequest != null)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final request = _rejectedCommitRequest!;
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: Text(
                                sl ? 'Ponovi zaključek' : 'Retry finalization',
                              ),
                              content: Text(
                                sl
                                    ? 'Ponovno poskusite zaključiti že odobreno nadgradnjo. Podatki in obnovitvena datoteka ostanejo isti.'
                                    : 'Retry finishing the upgrade you already approved. Your data and recovery file stay the same.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: Text(sl ? 'Prekliči' : 'Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: Text(
                                    sl
                                        ? 'Ponovi zaključek'
                                        : 'Retry finalization',
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (accepted != true || !mounted) return;
                          await _run(() async {
                            await api.retryRejectedCommit(
                              value['generationId'],
                              rejectedRequestId: request,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          });
                        },
                  child: Text(sl ? 'Ponovi zaključek' : 'Retry finalization'),
                ),
              if (state == 'superseded')
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.coordinator.adoptGenerationSuccessor(
                            scopeId: widget.scopeId,
                            generationId: value['generationId'],
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        }),
                  child: Text(
                    sl ? 'Nadaljuj novi poskus' : 'Continue the new attempt',
                  ),
                ),
            ],
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: Text(sl ? 'Osveži potrditve' : 'Refresh approvals'),
            ),
          ],
        ),
      ),
    );
  }
}
