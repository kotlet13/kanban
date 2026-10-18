import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/recovery/recovery_cache_native.dart';

void main() {
  test(
    'only recovery copies in the exact Android cache layout are removed',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'jivie-recovery-cache-test-',
      );
      try {
        final root = await Directory('${temp.path}/file_picker').create();
        final timestamp = await Directory(
          '${root.path}/1792240000000',
        ).create();
        final secret = await File(
          '${timestamp.path}/chosen.jivie-recovery',
        ).writeAsString('test');
        final other = await File(
          '${timestamp.path}/document.pdf',
        ).writeAsString('test');
        final outside = await File(
          '${temp.path}/original.jivie-recovery',
        ).writeAsString('test');
        await deleteRecoveryCacheCopy(
          path: secret.path,
          root: root,
          androidTimestampDirectory: true,
        );
        await deleteRecoveryCacheCopy(
          path: other.path,
          root: root,
          androidTimestampDirectory: true,
        );
        await deleteRecoveryCacheCopy(
          path: outside.path,
          root: root,
          androidTimestampDirectory: true,
        );
        expect(await secret.exists(), false);
        expect(await other.exists(), true);
        expect(await outside.exists(), true);
        final link = await Link(
          '${timestamp.path}/linked.jivie-recovery',
        ).create(outside.path);
        await deleteRecoveryCacheCopy(
          path: link.path,
          root: root,
          androidTimestampDirectory: true,
        );
        expect(await outside.exists(), true);
        expect(await link.exists(), true);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test('iOS export cleanup accepts only our random generated basename', () async {
    final temp = await Directory.systemTemp.createTemp(
      'jivie-recovery-export-test-',
    );
    try {
      final own = await File(
        '${temp.path}/jivie-account-${List.filled(32, 'a').join()}.jivie-recovery',
      ).writeAsString('test');
      final user = await File(
        '${temp.path}/my-original.jivie-recovery',
      ).writeAsString('test');
      await deleteRecoveryCacheCopy(
        path: own.path,
        root: temp,
        generatedNameOnly: true,
      );
      await deleteRecoveryCacheCopy(
        path: user.path,
        root: temp,
        generatedNameOnly: true,
      );
      expect(await own.exists(), false);
      expect(await user.exists(), true);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
