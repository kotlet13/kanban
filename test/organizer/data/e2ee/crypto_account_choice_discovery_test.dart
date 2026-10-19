import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _operation = '22222222-2222-4222-a222-222222222222';

class _UnusedDatabase implements CollaborationDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Discovery must not change a journal or projection');
}

class _UnusedAccess implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Discovery must not bypass materialize authority');
}

class _Candidate implements CryptoMigrationCandidate {
  @override
  String get captureId => '33333333-3333-4333-a333-333333333333';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No migration admission exercised by discovery');
}

Map<String, dynamic> _certificate({bool captured = false}) => {
  'commandBase64': base64Encode(
    CryptoJson.encode({
      'offerHash': 'a' * 64,
      if (captured) 'capture3Context': <String, dynamic>{},
    }),
  ),
  'signatureBase64': 'not-used-at-the-discovery-seam',
};

class _Directory implements AccountDirectoryRepository {
  _Directory(this.certificates);
  final List<Map<String, dynamic>> certificates;
  final requests = <Map<String, dynamic>>[];
  var pages = 0;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    expect(params['scopeId'], _scope);
    requests.add({'operation': operation, ...params});
    if (operation == 'crypto2.exports.offers') {
      final index = pages++;
      return {
        'items': [
          {'authorization': certificates[index]},
        ],
        'hasMore': pages < certificates.length,
        'nextAfterHash': '$pages'.padLeft(64, '0'),
      };
    }
    expect(operation, 'crypto2.exports.delegation.forOffer');
    return {
      'authorization': {'fixture': 'delegation'},
      'offerAuthorization': {'fixture': 'offer'},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected directory dependency');
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final AccountDirectoryRepository directory;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account dependency');
}

class _Runtime extends CryptoBusinessSession {
  _Runtime(_Directory directory)
    : super(_Account(directory), _UnusedAccess(), _UnusedDatabase());
  @override
  Future<String> reservedRecordId(String scope, String namespace) async {
    expect(scope, _scope);
    expect(namespace, startsWith('accountChoiceSelection:materialize:'));
    return _operation;
  }
}

/// Exercise the real discovery loop while controlling the independently
/// tested materialize verifier's result. This seam grants no authority.
class _Choices extends CryptoFinanceAccountChoices {
  _Choices(_Directory directory, this.outcomes) : super(_Runtime(directory));
  final List<Object?> outcomes;
  var attempts = 0;
  @override
  Future<Map<String, dynamic>> materialize(
    String scope, {
    required Map<String, dynamic> offerAuthorization,
    required Map<String, dynamic> delegationAuthorization,
    required Map<String, dynamic> certificateAuthorization,
    required String operationId,
    CryptoMigrationCandidate? candidate,
  }) async {
    expect(scope, _scope);
    expect(operationId, _operation);
    expect(offerAuthorization, {'fixture': 'offer'});
    expect(delegationAuthorization, {'fixture': 'delegation'});
    final outcome = outcomes[attempts++];
    if (outcome != null) throw outcome;
    return {'fixture': 'verified-current-projection'};
  }
}

void main() {
  const stale = CryptoAuthorityPending('crypto_account_choices_head_changed');
  test(
    'ordinary stale certificate advances to the next verified candidate',
    () async {
      final directory = _Directory([_certificate(), _certificate()]);
      final choices = _Choices(directory, [stale, null]);
      expect(await choices.materializeAvailable(_scope), isTrue);
      expect(choices.attempts, 2);
      expect(directory.pages, 2);
      final pages = directory.requests
          .where((r) => r['stage'] == 'certificates')
          .toList();
      expect(pages.first.containsKey('afterHash'), isFalse);
      expect(pages.last['afterHash'], '1'.padLeft(64, '0'));
    },
  );

  test(
    'exhausted ordinary stale certificates return no materialization for fresh derivation',
    () async {
      final directory = _Directory([_certificate(), _certificate()]);
      final choices = _Choices(directory, [stale, stale]);
      expect(await choices.materializeAvailable(_scope), isFalse);
      expect(choices.attempts, 2);
      expect(directory.pages, 2);
    },
  );

  test('unrelated pending authority stops discovery', () async {
    final directory = _Directory([_certificate(), _certificate()]);
    final pending = const CryptoAuthorityPending(
      'scoped_export_recipient_changed',
    );
    final choices = _Choices(directory, [pending, null]);
    await expectLater(
      choices.materializeAvailable(_scope),
      throwsA(same(pending)),
    );
    expect(choices.attempts, 1);
    expect(directory.pages, 1);
  });

  test('captured certificate retains strict head-change failure', () async {
    final directory = _Directory([
      _certificate(captured: true),
      _certificate(),
    ]);
    final choices = _Choices(directory, [stale, null]);
    await expectLater(
      choices.materializeAvailable(_scope),
      throwsA(same(stale)),
    );
    expect(choices.attempts, 1);
  });

  test('migration candidate retains strict head-change failure', () async {
    final directory = _Directory([_certificate(), _certificate()]);
    final choices = _Choices(directory, [stale, null]);
    final candidate = _Candidate();
    await expectLater(
      choices.materializeAvailable(_scope, candidate: candidate),
      throwsA(same(stale)),
    );
    expect(choices.attempts, 1);
    expect(directory.requests.first['captureId'], candidate.captureId);
  });
}
