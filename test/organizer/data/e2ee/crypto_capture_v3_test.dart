import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';
import 'package:sodium/sodium.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'server/tests/fixtures/e2ee-capture-v3.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final context = CryptoCaptureSourceContext.fromJson(
    Map<String, dynamic>.from(fixture['context'] as Map),
  );
  final binding = CryptoCaptureBinding.fromJson(
    Map<String, dynamic>.from(fixture['binding'] as Map),
  );
  late Sodium sodium;
  setUpAll(() async => sodium = await SodiumInit.init());

  Future<String> root(
    Stream<CryptoCaptureBinding> bindings,
    int count, {
    String? migrationId,
  }) => CryptoCaptureV3.inventoryRoot(
    serverId: context.serverId,
    captureId: context.captureId,
    migrationId: migrationId ?? context.migrationId,
    accountId: context.accountId,
    sourceCount: count,
    bindings: bindings,
  );

  test('independent Python/PHP golden bytes and empty stream', () async {
    final raw = base64Decode(fixture['keyBase64'] as String);
    final key = sodium.secureCopy(raw);
    final salt = await CryptoCaptureV3.salt(key, context);
    try {
      expect(base64Encode(salt), fixture['saltBase64']);
      expect(await CryptoCaptureV3.bindingId(key, context), fixture['bindingId']);
      expect(
        await CryptoCaptureV3.sourceCommitment(
          context: context,
          salt: salt,
          typedRow: fixture['typedRow'] as Object,
        ),
        binding.sourceCommitment,
      );
      expect(await root(Stream.value(binding), 1), fixture['inventoryRoot']);
      expect(
        await root(const Stream.empty(), 0),
        fixture['emptyInventoryRoot'],
      );
      final wire = jsonEncode(binding.toJson());
      expect(wire, isNot(contains('CAPTURE_PRIVATE_SENTINEL')));
      expect(wire, isNot(contains(fixture['saltBase64'] as String)));
      expect(wire, isNot(contains('sourceRowHash')));
      expect(wire, isNot(contains('row:0')));
    } finally {
      key.dispose();
      raw.fillRange(0, raw.length, 0);
      salt.fillRange(0, salt.length, 0);
    }
  });

  test(
    'changed key or capture context blinds the same predictable row',
    () async {
      final key = sodium.secureCopy(Uint8List(32));
      try {
        final salt = await CryptoCaptureV3.salt(key, context);
        final other = CryptoCaptureSourceContext.fromJson({
          ...context.toJson(),
          'captureId': '77777777-7777-4777-8777-777777777777',
        });
        final otherSalt = await CryptoCaptureV3.salt(key, other);
        expect(salt, isNot(otherSalt));
        expect(
          await CryptoCaptureV3.sourceCommitment(
            context: context,
            salt: salt,
            typedRow: fixture['typedRow'] as Object,
          ),
          isNot(binding.sourceCommitment),
        );
        salt.fillRange(0, salt.length, 0);
        otherSalt.fillRange(0, otherSalt.length, 0);
      } finally {
        key.dispose();
      }
    },
  );

  test(
    'full sorted count is mandatory; witness cannot cross source/context',
    () async {
      await expectLater(root(Stream.value(binding), 2), throwsFormatException);
      await expectLater(
        root(Stream.fromIterable([binding, binding]), 2),
        throwsFormatException,
      );
      await expectLater(root(Stream.value(binding), 0), throwsFormatException);
      expect(
        await root(
          Stream.value(binding),
          1,
          migrationId: '77777777-7777-4777-8777-777777777777',
        ),
        isNot(fixture['inventoryRoot']),
      );
      final witness = {
        'version': 3,
        'context': context.toJson(),
        'typedRow': fixture['typedRow'],
        'saltBase64': fixture['saltBase64'],
      };
      await CryptoCaptureV3.verifyWitness(
        binding: binding,
        context: context,
        witness: witness,
      );
      await expectLater(
        CryptoCaptureV3.verifyWitness(
          binding: binding,
          context: context,
          witness: {
            ...witness,
            'typedRow': {'changed': true},
          },
        ),
        throwsFormatException,
      );
      await expectLater(
        CryptoCaptureV3.verifyWitness(
          binding: binding,
          context: context,
          witness: {...witness, 'version': 2},
        ),
        throwsFormatException,
      );
      expect(
        () => CryptoCaptureSourceContext.fromJson({
          ...context.toJson(),
          'version': 2,
        }),
        throwsFormatException,
      );
    },
  );
}
