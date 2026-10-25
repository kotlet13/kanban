import 'dart:convert';
import 'dart:typed_data';

const attachmentMaxBytes = 20 * 1024 * 1024;
const attachmentChunkBytes = 256 * 1024;
const attachmentScopeMaxBytes = 256 * 1024 * 1024;

const attachmentMimeByExtension = <String, String>{
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'odt': 'application/vnd.oasis.opendocument.text',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'rtf': 'application/rtf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
};

/// Immutable server target; never inferred from the currently selected space.
class AttachmentTarget {
  const AttachmentTarget({
    required this.scopeId,
    required this.targetType,
    required this.targetId,
  });
  final String scopeId, targetType, targetId;

  void validate() {
    if (!_safeId(scopeId) ||
        !const ['scope', 'task', 'table'].contains(targetType) ||
        !_safeId(targetId)) {
      throw const FormatException('Invalid attachment target');
    }
  }

  Map<String, Object?> toJson() => {
    'scopeId': scopeId,
    'targetType': targetType,
    'targetId': targetId,
  };

  @override
  bool operator ==(Object other) =>
      other is AttachmentTarget &&
      scopeId == other.scopeId &&
      targetType == other.targetType &&
      targetId == other.targetId;
  @override
  int get hashCode => Object.hash(scopeId, targetType, targetId);
}

class AttachmentMetadata {
  const AttachmentMetadata({
    required this.id,
    required this.scopeId,
    required this.targetType,
    required this.targetId,
    required this.name,
    required this.mime,
    required this.size,
    required this.sha256,
    required this.createdAt,
    required this.complete,
    required this.offset,
  });
  final String id, scopeId, targetType, targetId, name, mime, sha256;
  final int size, createdAt, offset;
  final bool complete;

  AttachmentTarget get target => AttachmentTarget(
    scopeId: scopeId,
    targetType: targetType,
    targetId: targetId,
  );

  factory AttachmentMetadata.fromJson(Map<String, dynamic> json) =>
      AttachmentMetadata(
        id: json['id'] as String,
        scopeId: json['scopeId'] as String,
        targetType: json['targetType'] as String,
        targetId: json['targetId'] as String,
        name: json['name'] as String,
        mime: json['mime'] as String,
        size: json['size'] as int,
        sha256: json['sha256'] as String,
        createdAt: json['createdAt'] as int,
        complete: json['complete'] as bool,
        offset: json['offset'] as int,
      )..validate();

  Map<String, Object?> toJson() => {
    'id': id,
    ...target.toJson(),
    'name': name,
    'mime': mime,
    'size': size,
    'sha256': sha256,
    'createdAt': createdAt,
    'complete': complete,
    'offset': offset,
  };

  void validate() {
    target.validate();
    validateAttachmentFile(name, size, mime: mime);
    if (!_safeId(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        createdAt < 0 ||
        offset < 0 ||
        offset > size ||
        (complete && offset != size)) {
      throw const FormatException('Invalid attachment metadata');
    }
  }
}

bool _safeId(String value) =>
    value.isNotEmpty &&
    value.length <= 200 &&
    !RegExp(r'[\x00-\x20/\\]').hasMatch(value);

/// Checks user-facing names before upload and server-provided names before export.
String validateAttachmentFile(String name, int size, {String? mime}) {
  if (name.isEmpty ||
      name != name.trim() ||
      utf8.encode(name).length > 240 ||
      RegExp(r'[\x00-\x1f\x7f/\\:\u202a-\u202e\u2066-\u2069]').hasMatch(name) ||
      name.startsWith('.') ||
      name.endsWith('.') ||
      size <= 0 ||
      size > attachmentMaxBytes) {
    throw const FormatException('Invalid attachment file');
  }
  final dot = name.lastIndexOf('.');
  final extension = dot < 1 ? '' : name.substring(dot + 1).toLowerCase();
  final expected = attachmentMimeByExtension[extension];
  if (expected == null || (mime != null && mime != expected)) {
    throw const FormatException('Unsupported attachment file');
  }
  return expected;
}

/// Implementations bind all requests and cached bytes to the initiating account
/// and [target], rechecking current access after asynchronous work. Downloads
/// return verified bytes only, and upload completion verifies length and digest.
abstract interface class AttachmentGateway {
  AttachmentTarget get target;
  bool get isOnline;
  bool get isCurrent;
  Future<List<AttachmentMetadata>> list();
  Future<void> upload({
    required String name,
    required String mime,
    required Uint8List bytes,
    void Function(double)? onProgress,
  });
  Future<Uint8List> download(
    AttachmentMetadata attachment, {
    void Function(double)? onProgress,
  });
  Future<void> delete(AttachmentMetadata attachment);
  Uint8List? localBytes(AttachmentMetadata attachment);
}

/// Metadata only; cached file bytes do not authorize download or export.
abstract interface class AttachmentLocalPreview {
  Future<List<AttachmentMetadata>?> cachedList();
}
