import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/preserved_installation_files.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/preserved_installation_files_page.dart';

class _Files implements PreservedInstallationFiles {
  final reads = <String>[];
  @override
  Future<List<PreservedInstallationFile>> list({String? afterId}) async =>
      const [PreservedInstallationFile('a', 'other-profile.pdf', 17)];
  @override
  Future<Uint8List> read(String id) async {
    reads.add(id);
    return Uint8List.fromList(utf8.encode('PRIVATE_FILE_DATA'));
  }
}

class _Io extends BackupFileIo {
  Uint8List? saved;
  @override
  Future<BackupSaveStatus> save(
    Uint8List bytes, {
    required String title,
    required String name,
  }) async {
    saved = Uint8List.fromList(bytes);
    return BackupSaveStatus.cancelled;
  }

  @override
  Future<PickedBackupFile?> pick({required int maxBytes}) async => saved == null
      ? null
      : PickedBackupFile('preserved.vsakdan', Uint8List.fromList(saved!));
}

class _Codec extends PreservedInstallationFileCodec {
  int exports = 0, imports = 0;
  @override
  Future<Uint8List> encrypt({
    required String name,
    required Uint8List bytes,
    required String password,
  }) async {
    expect(name, 'other-profile.pdf');
    expect(utf8.decode(bytes), 'PRIVATE_FILE_DATA');
    expect(password, 'installation-file-password');
    exports++;
    return Uint8List.fromList([91, 92, 93]);
  }

  @override
  Future<({String name, Uint8List bytes})> decrypt(
    Uint8List bytes,
    String password,
  ) async {
    expect(bytes, [91, 92, 93]);
    imports++;
    return (
      name: 'other-profile.pdf',
      bytes: Uint8List.fromList(utf8.encode('PRIVATE_FILE_DATA')),
    );
  }
}

void main() {
  testWidgets(
    'installation file export requires selection+scope review; cancelled save/import installs nothing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = _Files(), io = _Io();
      final codec = _Codec();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preservedInstallationFilesProvider.overrideWithValue(
              Future.value(files),
            ),
            backupFileIoProvider.overrideWithValue(io),
            preservedInstallationFileCodecProvider.overrideWithValue(codec),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const PreservedInstallationFilesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(files.reads, isEmpty);
      await tester.scrollUntilVisible(
        find.text('other-profile.pdf'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('other-profile.pdf'));
      await tester.pumpAndSettle();
      expect(files.reads, isEmpty);
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'installation-file-password',
      );
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(files.reads, ['a']);
      expect(io.saved, [91, 92, 93]);
      expect(codec.exports, 1);
      await tester.scrollUntilVisible(
        find.text('Open an encrypted preserved file'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open an encrypted preserved file'));
      await tester.pumpAndSettle();
      expect(files.reads, [
        'a',
      ]); // Read-only import; no archive or app data install API.
      expect(codec.imports, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
