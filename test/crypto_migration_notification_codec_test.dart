import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_notification_codec.dart';

void main() {
  test(
    'notification migration root matches independent Python vectors and binds full stream',
    () async {
      final vector =
          jsonDecode(
                File(
                  'server/tests/fixtures/e2ee-notification-migration-v3.json',
                ).readAsStringSync(),
              )
              as Map;
      final header = Map<String, dynamic>.from(vector['header'] as Map);
      final hashes = <String>[];
      for (final leaf in vector['leaves'] as List) {
        hashes.add(
          await CryptoMigrationNotificationCodec.leafDigest(leaf as Map),
        );
      }
      hashes.sort();
      expect(hashes, vector['leafDigests']);
      final context = Map<String, dynamic>.from(
        vector['selectionContext'] as Map,
      );
      expect(
        await CryptoMigrationNotificationCodec.selectionRoot(
          context,
          hashes.length,
          Stream.fromIterable(hashes),
        ),
        vector['selectionRoot'],
      );
      expect(
        await CryptoMigrationNotificationCodec.selectionRoot(
          context,
          0,
          const Stream.empty(),
        ),
        vector['emptySelectionRoot'],
      );
      for (final bad in [
        hashes.reversed.toList(),
        [hashes[0]],
        [hashes[0], hashes[0]],
      ]) {
        await expectLater(
          CryptoMigrationNotificationCodec.selectionRoot(
            context,
            hashes.length,
            Stream.fromIterable(bad),
          ),
          throwsFormatException,
        );
      }
      expect(
        await CryptoMigrationNotificationCodec.selectionRoot(
          {...context, 'sourceInventoryRoot': 'f' * 64},
          hashes.length,
          Stream.fromIterable(hashes),
        ),
        isNot(vector['selectionRoot']),
      );
      expect(
        await CryptoMigrationNotificationCodec.scopeToken(header),
        vector['scopeToken'],
      );
      expect(
        await CryptoMigrationNotificationCodec.transformRoot(
          header,
          Stream.fromIterable(hashes),
        ),
        vector['transformRoot'],
      );
      for (final bad in [
        hashes.reversed.toList(),
        [hashes[0], hashes[0]],
        [hashes[0]],
      ]) {
        await expectLater(
          CryptoMigrationNotificationCodec.transformRoot(
            header,
            Stream.fromIterable(bad),
          ),
          throwsFormatException,
        );
      }
      expect(
        await CryptoMigrationNotificationCodec.scopeToken({
          ...header,
          'accountId': '77777777-7777-4777-8777-777777777777',
        }),
        isNot(vector['scopeToken']),
      );
      expect(
        () => CryptoMigrationNotificationCodec.header({
          ...header,
          'sourceCounts': {
            'reminder': 1,
            'inbox': 0,
            'preference': 0,
            'inboxState': 0,
          },
        }),
        throwsFormatException,
      );
      await expectLater(
        CryptoMigrationNotificationCodec.leafDigest({
          ...Map.from((vector['leaves'] as List).first as Map),
          'kind': 'inbox',
        }),
        throwsFormatException,
      );
    },
  );
}
