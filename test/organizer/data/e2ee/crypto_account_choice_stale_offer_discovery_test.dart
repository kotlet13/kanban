import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_finance_account_choices.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const _scope = '11111111-1111-4111-a111-111111111111';
const _operation = '22222222-2222-4222-a222-222222222222';
const _stale = CollaborationApiException(
  'crypto_account_choices_source_set_changed',
);

class _UnusedDatabase implements CollaborationDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Discovery cannot change journals or projections');
}

class _UnusedAccess implements SessionCryptoAccess {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Discovery cannot grant authority');
}

class _Candidate implements CryptoMigrationCandidate {
  @override
  String get captureId => '33333333-3333-4333-a333-333333333333';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No migration admission exercised');
}

class _Directory implements AccountDirectoryRepository {
  _Directory(this.outcomes, {this.captured = false});
  final List<Object?> outcomes;
  final bool captured;
  final cursors = <Object?>[];
  int pages = 0, fetches = 0;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    expect(params['scopeId'], _scope);
    if (operation == 'crypto2.exports.offers') {
      cursors.add(params['afterHash']);
      pages++;
      return {
        'items': [
          {
            'authorization': {
              'commandBase64': base64Encode(
                CryptoJson.encode({
                  'offerHash': '$pages'.padLeft(64, '0'),
                  if (captured) 'capture3Context': <String, dynamic>{},
                }),
              ),
              'signatureBase64': 'opaque-discovery-seam-sentinel',
            },
          },
        ],
        'hasMore': pages < outcomes.length,
        'nextAfterHash': '$pages'.padLeft(64, '0'),
      };
    }
    expect(operation, 'crypto2.exports.delegation.forOffer');
    expect(params['includeOffer'], isTrue);
    final failure = outcomes[fetches++];
    if (failure != null) throw failure;
    return {
      'authorization': {'fixture': 'delegation'},
      'offerAuthorization': {'fixture': 'offer'},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No other directory dependencies');
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.directory);
  @override
  final AccountDirectoryRepository directory;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No account dependencies');
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

// The real discovery loop must handle a stale forOffer response before reaching
// the separately verified materializer. This seam does not accept any proof.
class _Choices extends CryptoFinanceAccountChoices {
  _Choices(_Directory directory) : super(_Runtime(directory));
  var materializations = 0;
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
    materializations++;
    return {};
  }
}

void main() {
  test(
    'stale forOffer fetch advances cursor and preserves exhaustion semantics',
    () async {
      final directory = _Directory([_stale, null]);
      final choices = _Choices(directory);
      expect(await choices.materializeAvailable(_scope), isTrue);
      expect(directory.cursors, [null, '1'.padLeft(64, '0')]);
      expect(directory.fetches, 2);
      expect(choices.materializations, 1);
      for (final code in [
        'crypto_account_choices_source_set_changed',
        'crypto_export_source_changed',
        'crypto_scope_head_changed',
        'crypto_export_issuer_changed',
      ]) {
        final exhausted = _Directory([CollaborationApiException(code)]);
        final noMaterialization = _Choices(exhausted);
        expect(await noMaterialization.materializeAvailable(_scope), isFalse);
        expect(exhausted.fetches, 1);
        expect(noMaterialization.materializations, 0);
      }
    },
  );

  test(
    'forOffer non-stale authority and integrity failures remain exact failures',
    () async {
      for (final failure in <Object>[
        const CollaborationApiException('permission_revoked'),
        const CollaborationApiException(
          'crypto_account_choices_checkpoint_changed',
        ),
        const CryptoAuthorityPending('crypto_account_choices_head_changed'),
        const CryptoDirectoryException('directory_root_changed'),
        const FormatException('crypto_signature'),
      ]) {
        final directory = _Directory([failure, null]);
        final choices = _Choices(directory);
        await expectLater(
          choices.materializeAvailable(_scope),
          throwsA(same(failure)),
        );
        expect(directory.pages, 1);
        expect(directory.fetches, 1);
        expect(choices.materializations, 0);
      }
    },
  );

  test(
    'captured certificates and migration candidates retain strict fetch failure',
    () async {
      for (final captured in [true, false]) {
        final directory = _Directory([_stale, null], captured: captured);
        final choices = _Choices(directory);
        await expectLater(
          choices.materializeAvailable(
            _scope,
            candidate: captured ? null : _Candidate(),
          ),
          throwsA(same(_stale)),
        );
        expect(directory.pages, 1);
        expect(directory.fetches, 1);
        expect(choices.materializations, 0);
      }
    },
  );
}
