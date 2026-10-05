import 'dart:convert';
import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/organizer_models.dart';

/// Storage is injectable; it never contacts a server or stores account secrets.
abstract interface class OrganizerStorage {
  Future<OrganizerSnapshot> read();
  Future<void> write(OrganizerSnapshot snapshot);
  Future<void> close();
}

abstract interface class ObservableOrganizerStorage {
  Stream<void> get changes;
}

class OrganizerBackupCodec {
  static const schemaVersion = 2;
  static const maxBytes = 10 * 1024 * 1024;

  static String encode(OrganizerSnapshot snapshot) {
    snapshot.validate();
    final result = jsonEncode({
      'format': 'vsakdan-personal-backup',
      'schemaVersion': schemaVersion,
      'workspace': 'personal',
      'data': snapshot.toJson(),
    });
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('Backup exceeds 10 MiB');
    }
    return result;
  }

  static OrganizerSnapshot decode(String value) {
    if (value.length > maxBytes || utf8.encode(value).length > maxBytes) {
      throw const FormatException('Backup exceeds 10 MiB');
    }
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> ||
        json['format'] != 'vsakdan-personal-backup' ||
        json['schemaVersion'] is! int ||
        !const [1, 2].contains(json['schemaVersion']) ||
        json['workspace'] != 'personal' ||
        json['data'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported personal backup format');
    }
    return OrganizerSnapshot.fromJson(json['data'] as Map<String, dynamic>);
  }
}

/// One Hive frame contains the complete transaction, including linked changes.
/// This separate personal box is never cleared by remote account logout.
class HiveOrganizerStorage implements OrganizerStorage {
  HiveOrganizerStorage._(this._box);

  final Box<String> _box;
  static const boxName = 'organizer_personal_v1';
  static const _snapshotKey = 'committed_snapshot';

  static Future<HiveOrganizerStorage> open({String? directory}) async {
    if (directory == null) {
      await Hive.initFlutter();
    }
    final box = await Hive.openBox<String>(boxName, path: directory);
    return HiveOrganizerStorage._(box);
  }

  @override
  Future<OrganizerSnapshot> read() async {
    final value = _box.get(_snapshotKey);
    // A corrupt or newer database throws; it is never replaced with empty data.
    return value == null
        ? OrganizerSnapshot()
        : OrganizerBackupCodec.decode(value);
  }

  @override
  Future<void> write(OrganizerSnapshot snapshot) async {
    await _box.put(_snapshotKey, OrganizerBackupCodec.encode(snapshot));
    await _box.flush();
  }

  @override
  Future<void> close() async {
    if (_box.isOpen) await _box.close();
  }
}
