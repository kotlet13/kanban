import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_legacy.dart';
import 'package:kanban/organizer/data/e2ee/crypto_capture_v3.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'server/tests/fixtures/e2ee-capture-legacy-v3.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final descriptor = CryptoLegacyReceiptDescriptor.fromJson(
    Map<String, dynamic>.from(fixture['descriptor'] as Map),
  );
  final context = CryptoCaptureSourceContext.fromJson(
    Map<String, dynamic>.from(fixture['context'] as Map),
  );
  final header = Map<String, dynamic>.from(fixture['header'] as Map);
  Future<CryptoCapturedLegacyReceipt> open({
    Map<String, dynamic>? witness,
    CryptoLegacyReceiptDescriptor? selected,
  }) => CryptoCapturedLegacyReceipt.fromWitness(
    descriptor: selected ?? descriptor,
    context: context,
    witness: witness ?? Map<String, dynamic>.from(fixture['witness'] as Map),
  );

  test(
    'Python/PHP stream golden preserves exact combined legacy receipt',
    () async {
      expect(
        await CryptoLegacyReceiptInventory.root(
          header,
          Stream.value(descriptor),
        ),
        fixture['root'],
      );
      expect(
        await CryptoLegacyReceiptInventory.root({
          ...header,
          'receiptCount': 0,
        }, const Stream.empty()),
        fixture['emptyRoot'],
      );
      final receipt = await open();
      expect(base64Encode(receipt.responseBytes), fixture['responseBase64']);
      receipt.requireOriginalRequestHash(fixture['requestHash'] as String);
      expect(receipt.outcome, 'applied');
      expect(
        jsonDecode(utf8.decode(receipt.responseBytes)),
        contains('finance'),
      );
      final public = jsonEncode({
        'header': header,
        'descriptor': descriptor.toJson(),
      });
      expect(public, isNot(contains('PRIVATE_RECEIPT')));
      expect(public, isNot(contains(fixture['requestHash'] as String)));
      expect(
        public,
        isNot(contains((fixture['witness'] as Map)['saltBase64'])),
      );
    },
  );

  test(
    'missing, duplicate and reordered inventory never proves absence',
    () async {
      await expectLater(
        CryptoLegacyReceiptInventory.root(header, const Stream.empty()),
        throwsFormatException,
      );
      await expectLater(
        CryptoLegacyReceiptInventory.root({
          ...header,
          'receiptCount': 2,
        }, Stream.fromIterable([descriptor, descriptor])),
        throwsFormatException,
      );
      final other = CryptoLegacyReceiptDescriptor(
        tuple: CryptoLegacyReceiptTuple(
          scopeId: descriptor.tuple.scopeId,
          kind: 'records',
          legacyId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        ),
        bindingId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        sourceCommitment: 'c' * 64,
      );
      await expectLater(
        CryptoLegacyReceiptInventory.root({
          ...header,
          'receiptCount': 2,
        }, Stream.fromIterable([other, descriptor])),
        throwsFormatException,
      );
      await expectLater(
        CryptoLegacyReceiptInventory.root({
          ...header,
          'domain': 'finance',
        }, Stream.value(descriptor)),
        throwsFormatException,
      );
    },
  );

  test(
    'wrong request, tuple, receipt kind or altered encrypted witness stays unresolved',
    () async {
      final receipt = await open();
      expect(
        () => receipt.requireOriginalRequestHash('f' * 64),
        throwsFormatException,
      );
      final altered =
          jsonDecode(jsonEncode(fixture['witness'])) as Map<String, dynamic>;
      (altered['typedRow']['response'] as Map)['valueBase64'] = base64Encode(
        utf8.encode('{}'),
      );
      await expectLater(open(witness: altered), throwsFormatException);
      await expectLater(
        open(
          selected: CryptoLegacyReceiptDescriptor(
            tuple: CryptoLegacyReceiptTuple(
              scopeId: descriptor.tuple.scopeId,
              kind: 'finance',
              legacyId: descriptor.tuple.legacyId,
            ),
            bindingId: descriptor.bindingId,
            sourceCommitment: descriptor.sourceCommitment,
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        open(
          selected: CryptoLegacyReceiptDescriptor(
            tuple: CryptoLegacyReceiptTuple(
              scopeId: descriptor.tuple.scopeId,
              kind: 'records',
              legacyId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
            ),
            bindingId: descriptor.bindingId,
            sourceCommitment: descriptor.sourceCommitment,
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
