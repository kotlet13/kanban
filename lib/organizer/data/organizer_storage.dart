import 'dart:convert';
import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/organizer_models.dart';
import '../domain/garden_models.dart';

/// Storage is injectable; it never contacts a server or stores account secrets.
abstract interface class OrganizerStorage {
  Future<OrganizerSnapshot> read();
  Future<void> write(OrganizerSnapshot snapshot);
  Future<void> close();
}

abstract interface class ObservableOrganizerStorage {
  Stream<void> get changes;
}

/// SQLite implements a combined atomic JSON import. Other legacy storages must
/// explicitly reject a document containing gardens instead of discarding them.
abstract interface class PersonalJsonBackupStorage {
  Future<String> exportPersonalJsonBackup();
  Future<void> importPersonalJsonBackup(String json);
}

class PersonalJsonBackup {
  const PersonalJsonBackup(this.personal, this.gardens);
  final OrganizerSnapshot personal;
  final GardenSnapshot? gardens;
}

class OrganizerBackupCodec {
  static const schemaVersion = 2;
  static const maxBytes = 10 * 1024 * 1024;

  static String encode(OrganizerSnapshot snapshot, {GardenSnapshot? gardens}) {
    snapshot.validate();
    gardens?.validate();
    final result = jsonEncode({
      'format': 'vsakdan-personal-backup',
      'schemaVersion': gardens == null ? schemaVersion : 3,
      'workspace': 'personal',
      'data': snapshot.toJson(),
      if (gardens != null) 'gardens': gardens.toJson(),
    });
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('Backup exceeds 10 MiB');
    }
    return result;
  }

  static OrganizerSnapshot decode(String value) =>
      decodeDocument(value).personal;

  static PersonalJsonBackup decodeDocument(String value) {
    if (value.length > maxBytes || utf8.encode(value).length > maxBytes) {
      throw const FormatException('Backup exceeds 10 MiB');
    }
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> ||
        json['format'] != 'vsakdan-personal-backup' ||
        json['schemaVersion'] is! int ||
        !const [1, 2, 3].contains(json['schemaVersion']) ||
        json['workspace'] != 'personal' ||
        json['data'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported personal backup format');
    }
    if (json['schemaVersion'] == 3 &&
        json['gardens'] is! Map<String, dynamic>) {
      throw const FormatException('Missing garden backup data');
    }
    final keys = {
      'format',
      'schemaVersion',
      'workspace',
      'data',
      if (json['schemaVersion'] == 3) 'gardens',
    };
    if (json.length != keys.length ||
        json.keys.toSet().difference(keys).isNotEmpty) {
      throw const FormatException('Unsupported personal backup fields');
    }
    return PersonalJsonBackup(
      OrganizerSnapshot.fromJson(json['data'] as Map<String, dynamic>),
      json['schemaVersion'] == 3
          ? GardenSnapshot.fromJson(json['gardens'] as Map<String, dynamic>)
          : null,
    );
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
    if (value == null) return OrganizerSnapshot();
    final document = OrganizerBackupCodec.decodeDocument(value);
    if (document.gardens != null) {
      throw const FormatException(
        'Legacy Hive storage cannot hold garden data',
      );
    }
    return document.personal;
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
