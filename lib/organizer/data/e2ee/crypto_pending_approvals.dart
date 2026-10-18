import 'dart:convert';

import 'crypto_access_coordinator.dart';
import 'account_directory_v2.dart' show cryptoSha256;
import 'crypto_business_lifecycle.dart';
import 'crypto_business_leave.dart';
import 'crypto_business_router.dart';
import 'crypto_finance_account_choices.dart';
import 'crypto_json.dart';
import 'crypto_sync_repository.dart' show CryptoAuthorityPending;

/// Discovery is only a candidate list. Each approval re-reads and verifies its
/// exact source before asking for review; the component still activates once.
class CryptoPendingApprovals {
  CryptoPendingApprovals(this.context);
  final CryptoBusinessSession context;

  Future<CryptoPendingApprovalList> load() async {
    final items = <CryptoPendingApproval>[];
    final unavailable = <String>{};
    final choices = CryptoFinanceAccountChoices(context);
    try {
      for (final value in await choices.ownPending()) {
        final scope = value['scopeId'] as String;
        items.add(
          CryptoPendingApproval(scope, scope, value, false, choiceFinish: true),
        );
      }
    } catch (_) {
      unavailable.add('accountChoices');
    }
    try {
      for (final value in await CryptoBusinessLeave(context).mine()) {
        final scope = value['scopeId'] as String;
        final cached = await context.database.rows(
          'SELECT data FROM scopes WHERE partition=? AND id=?',
          [context.partition, scope],
        );
        final label = cached.isEmpty
            ? null
            : (jsonDecode(cached.single['data'] as String) as Map)['name'];
        items.add(
          CryptoPendingApproval(
            scope,
            label is String && label.isNotEmpty ? label : scope,
            value,
            false,
            ownLeave: true,
          ),
        );
      }
    } catch (_) {
      unavailable.add('ownLeave');
    }

    for (final candidate in await context.catalog()) {
      final scopeId = candidate['id'] as String;
      // Mixed legacy/V2 catalogs are supported. A missing head is not an
      // approval candidate and cannot abort discovery for unrelated scopes.
      if (candidate['headHash'] == null) continue;
      try {
        final head = await context.access.currentHead(scopeId, online: true);
        if (head.member(context.account.directory.accountId)['financeRole'] ==
            'write') {
          try {
            final response = await context.account.directory
                .call('crypto2.exports.offers', {
                  'scopeId': scopeId,
                  'variant': CryptoFinanceAccountChoices.variant,
                  'stage': 'certificates',
                  'limit': 1,
                });
            if ((response['items'] as List).isNotEmpty) {
              var ready = false;
              try {
                await choices.read(scopeId);
                ready = true;
              } catch (_) {
                /* Explicit retry below. */
              }
              if (!ready) {
                items.add(
                  CryptoPendingApproval(
                    scopeId,
                    scopeId,
                    const {},
                    false,
                    choiceMaterialize: true,
                  ),
                );
              }
            }
          } catch (_) {
            unavailable.add(scopeId);
          }
        }
        if (head.member(context.account.directory.accountId)['manageKeys'] !=
            true) {
          continue;
        }
        var name = scopeId;
        final cached = await context.database.rows(
          'SELECT data FROM scopes WHERE partition=? AND id=?',
          [context.partition, scopeId],
        );
        if (cached.isNotEmpty) {
          final value = jsonDecode(cached.single['data'] as String) as Map;
          if (value['name'] is String && (value['name'] as String).isNotEmpty) {
            name = value['name'];
          }
        }
        try {
          for (final offer in await choices.pendingOffers(scopeId)) {
            items.add(
              CryptoPendingApproval(
                scopeId,
                name,
                offer,
                false,
                choiceReview: true,
              ),
            );
          }
        } catch (_) {
          unavailable.add(scopeId);
        }
        try {
          final leave = CryptoBusinessLeave(context);
          final plans = await leave.managerPlans(scopeId);
          final known = {for (final plan in plans) plan['requestHash']};
          for (final request in await leave.pending(scopeId)) {
            if (!known.contains(request['requestHash'])) {
              final command =
                  CryptoJson.decode(
                        cryptoBase64(
                          (request['authorization'] as Map)['commandBase64'],
                        ),
                      )
                      as Map;
              final members = await context.database.rows(
                'SELECT data FROM members WHERE partition=? AND scope_id=? AND account_id=?',
                [context.partition, scopeId, command['accountId']],
              );
              final member = members.isEmpty
                  ? null
                  : jsonDecode(members.single['data'] as String) as Map;
              items.add(
                CryptoPendingApproval(
                  scopeId,
                  name,
                  {
                    ...request,
                    if (member != null)
                      'displayName':
                          member['displayName'] ?? member['username'],
                  },
                  false,
                  leaveRequest: true,
                ),
              );
            }
          }
          for (final plan in plans) {
            items.add(
              CryptoPendingApproval(
                scopeId,
                name,
                plan,
                false,
                leaveFinish: true,
              ),
            );
          }
        } catch (_) {
          unavailable.add(scopeId);
        }
        try {
          var cleanup = false;
          for (final proposal in await CryptoAccessCoordinator(
            context,
          ).pendingApprovals(scopeId, cleanup: (value) => cleanup = value)) {
            items.add(CryptoPendingApproval(scopeId, name, proposal, false));
          }
          if (cleanup) {
            items.add(
              CryptoPendingApproval(
                scopeId,
                name,
                const {},
                false,
                cleanup: true,
              ),
            );
          }
        } catch (_) {
          unavailable.add(scopeId);
        }
        try {
          for (final request in await CryptoBusinessLifecycle(
            context,
          ).pendingApprovals(scopeId)) {
            items.add(CryptoPendingApproval(scopeId, name, request, true));
          }
        } catch (_) {
          unavailable.add(scopeId);
        }
      } catch (_) {
        unavailable.add(scopeId);
      }
    }
    return CryptoPendingApprovalList(items, unavailable.length);
  }

  Future<void> approveAccess(
    CryptoPendingApproval item, {
    required Future<bool> Function(
      CryptoAccessReview review,
      Map<String, dynamic> sourceDescriptor,
    )
    review,
  }) async {
    if (item.lifecycle) throw const FormatException('crypto_approval_kind');
    await CryptoAccessCoordinator(context).approve(
      item.scopeId,
      item.value['intentHash'] as String,
      review: (value) async {
        final descriptor = await context.access.verifiedScopeDescriptor(
          item.scopeId,
          online: true,
        );
        if ((await context.access.currentHead(
              item.scopeId,
              online: true,
            )).headHash !=
            value.source.headHash) {
          throw const CryptoAuthorityPending('crypto_access_review_changed');
        }
        return review(value, descriptor);
      },
    );
  }

  Future<void> approveParent(CryptoPendingApproval item) async {
    if (!item.lifecycle) throw const FormatException('crypto_approval_kind');
    await CryptoBusinessLifecycle(context).approveParent(
      item.scopeId,
      item.value['parentActionId'] as String,
      expectedRequestHash: await cryptoSha256(CryptoJson.encode(item.value)),
    );
  }
}

class CryptoPendingApproval {
  CryptoPendingApproval(
    this.scopeId,
    this.name,
    Map<String, dynamic> value,
    this.lifecycle, {
    this.cleanup = false,
    this.ownLeave = false,
    this.leaveRequest = false,
    this.leaveFinish = false,
    this.choiceReview = false,
    this.choiceFinish = false,
    this.choiceMaterialize = false,
  }) : value = Map.unmodifiable(value);
  final String scopeId, name;
  final Map<String, dynamic> value;
  final bool lifecycle, cleanup, ownLeave, leaveRequest, leaveFinish;
  final bool choiceReview, choiceFinish, choiceMaterialize;
}

class CryptoPendingApprovalList {
  CryptoPendingApprovalList(List<CryptoPendingApproval> items, this.unavailable)
    : items = List.unmodifiable(items);
  final List<CryptoPendingApproval> items;
  final int unavailable;
}

/// Complete roster diff, including finance and key-management changes. Display
/// names are never used to select the account whose authority will change.
List<Map<String, dynamic>> cryptoApprovalRosterDiff(
  List<Map<String, dynamic>> before,
  List<Map<String, dynamic>> after,
) {
  Map<String, Map<String, dynamic>> index(List<Map<String, dynamic>> values) {
    final result = <String, Map<String, dynamic>>{};
    for (final value in values) {
      final id = value['accountId'] as String;
      if (result.containsKey(id)) {
        throw const FormatException('crypto_approval_duplicate_member');
      }
      result[id] = value;
    }
    return result;
  }

  final old = index(before), next = index(after);
  final ids = {...old.keys, ...next.keys}.toList()..sort();
  return [
    for (final id in ids)
      if (old[id] == null ||
          next[id] == null ||
          [
            'role',
            'financeRole',
            'manageKeys',
          ].any((field) => old[id]![field] != next[id]![field]))
        {'accountId': id, 'before': old[id], 'after': next[id]},
  ];
}
