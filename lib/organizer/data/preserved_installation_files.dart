import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../platform/private_file_types.dart';
import 'portable_backup_crypto.dart';

/// Installation-wide preservation, deliberately separate from account backups.
/// An app-owned picker copy does not establish account ownership.
class PreservedInstallationFile {
  const PreservedInstallationFile(this.id, this.name, this.size);
  final String id, name;
  final int size;
}

abstract interface class PreservedInstallationFiles {
  Future<List<PreservedInstallationFile>> list({String? afterId});
  Future<Uint8List> read(String id);
}

class PreservedInstallationBundle {
  static Future<Uint8List> encrypt({
    required String name,
    required Uint8List bytes,
    required String password,
  }) async {
    validatePrivateFileName(name);
    if (bytes.length > 64 * 1024 * 1024) throw const BackupFileBound();
    return PortableBackupCrypto().encrypt({
      'format': 'jivie-preserved-installation-file',
      'version': 1,
      'name': name,
      'size': bytes.length,
      'sha256': base64Encode((await Sha256().hash(bytes)).bytes),
      'bytesBase64': base64Encode(bytes),
    }, password);
  }

  static Future<({String name, Uint8List bytes})> decrypt(
    Uint8List encrypted,
    String password,
  ) async {
    final doc = await PortableBackupCrypto().decrypt(encrypted, password);
    if (doc.length != 6 ||
        doc['format'] != 'jivie-preserved-installation-file' ||
        doc['version'] != 1 ||
        doc['name'] is! String ||
        doc['size'] is! int ||
        doc['size'] < 0 ||
        doc['size'] > 64 * 1024 * 1024 ||
        doc['sha256'] is! String ||
        doc['bytesBase64'] is! String) {
      throw const FormatException('preserved_file_invalid');
    }
    validatePrivateFileName(doc['name']);
    final bytes = base64Decode(doc['bytesBase64']);
    if (bytes.length != doc['size'] ||
        base64Encode(bytes) != doc['bytesBase64'] ||
        base64Encode((await Sha256().hash(bytes)).bytes) != doc['sha256']) {
      bytes.fillRange(0, bytes.length, 0);
      throw const FormatException('preserved_file_invalid');
    }
    return (name: doc['name'] as String, bytes: bytes);
  }
}

class BackupFileBound implements Exception {
  const BackupFileBound();
}

/// Injectable cipher seam for UI tests; production uses the same authenticated
/// password envelope independently exercised by the native recovery tests.
class PreservedInstallationFileCodec {
  const PreservedInstallationFileCodec();
  Future<Uint8List> encrypt({
    required String name,
    required Uint8List bytes,
    required String password,
  }) => PreservedInstallationBundle.encrypt(
    name: name,
    bytes: bytes,
    password: password,
  );
  Future<({String name, Uint8List bytes})> decrypt(
    Uint8List bytes,
    String password,
  ) => PreservedInstallationBundle.decrypt(bytes, password);
}
