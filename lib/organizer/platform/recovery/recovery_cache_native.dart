import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/local_vault_files.dart';

final _generatedName = RegExp(
  r'^jivie-(installation|account)-[0-9a-f]{32}\.jivie-recovery$',
);

/// Deletes only file_picker-owned secret copies in an application sandbox.
/// Desktop picker paths refer to originals and must never be removed here.
Future<void> cleanRecoveryImport(String? path) async {
  if (path == null || (!Platform.isAndroid && !Platform.isIOS)) return;
  final directory = Platform.isAndroid
      ? Directory('${(await getTemporaryDirectory()).path}/file_picker')
      : Directory.systemTemp;
  await deleteRecoveryCacheCopy(
    path: path,
    root: directory,
    androidTimestampDirectory: Platform.isAndroid,
  );
}

Future<void> cleanRecoveryExports(String name) async {
  if (!Platform.isIOS || !_generatedName.hasMatch(name)) return;
  final documents = await getApplicationDocumentsDirectory();
  await deleteRecoveryCacheCopy(
    path: '${documents.path}/$name',
    root: documents,
    generatedNameOnly: true,
  );
}

Future<void> cleanRecoveryCaches() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  final root = Platform.isAndroid
      ? Directory('${(await getTemporaryDirectory()).path}/file_picker')
      : Directory.systemTemp;
  if (await root.exists()) {
    await for (final entity in root.list(followLinks: false)) {
      if (Platform.isAndroid &&
          entity is Directory &&
          RegExp(
            r'^\d{10,17}$',
          ).hasMatch(entity.uri.pathSegments.where((s) => s.isNotEmpty).last)) {
        await for (final child in entity.list(followLinks: false)) {
          if (child is File) {
            await deleteRecoveryCacheCopy(
              path: child.path,
              root: root,
              androidTimestampDirectory: true,
            );
          }
        }
      } else if (Platform.isIOS && entity is File) {
        await deleteRecoveryCacheCopy(path: entity.path, root: root);
      }
    }
  }
  if (Platform.isIOS) {
    final documents = await getApplicationDocumentsDirectory();
    await for (final entity in documents.list(followLinks: false)) {
      if (entity is File) {
        await deleteRecoveryCacheCopy(
          path: entity.path,
          root: documents,
          generatedNameOnly: true,
        );
      }
    }
  }
}

/// Separated for filesystem regression tests. Both the original lexical path
/// and its canonical target must stay within the exact allowed layout.
Future<void> deleteRecoveryCacheCopy({
  required String path,
  required Directory root,
  bool androidTimestampDirectory = false,
  bool generatedNameOnly = false,
}) async {
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      !await root.exists()) {
    return;
  }
  final rootPath = await root.resolveSymbolicLinks();
  final lexicalRoot = root.absolute.path.replaceFirst(RegExp(r'/+$'), '');
  final lexical = file.absolute.path;
  final canonical = await file.resolveSymbolicLinks();
  if ((!lexical.startsWith('$rootPath/') &&
          !lexical.startsWith('$lexicalRoot/')) ||
      !canonical.startsWith('$rootPath/')) {
    return;
  }
  final relative = canonical.substring(rootPath.length + 1).split('/');
  if (relative.any((part) => part == '.' || part == '..' || part.isEmpty)) {
    return;
  }
  if (androidTimestampDirectory) {
    if (relative.length != 2 ||
        !RegExp(r'^\d{10,17}$').hasMatch(relative.first)) {
      return;
    }
  } else if (relative.length != 1) {
    return;
  }
  final name = relative.last;
  if (!name.toLowerCase().endsWith('.jivie-recovery') ||
      (generatedNameOnly && !_generatedName.hasMatch(name))) {
    return;
  }
  await LocalVaultFiles().delete(file);
}
