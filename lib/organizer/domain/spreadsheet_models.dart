/// Spreadsheet wire contract. Raw cell input is kept separately from calculation.
class SpreadsheetDocument {
  SpreadsheetDocument({
    required this.id,
    required this.scopeId,
    required this.title,
    Map<String, String> cells = const {},
    required this.revision,
    required this.updatedAt,
  }) : cells = Map.unmodifiable(cells);
  final String id, scopeId, title;
  final Map<String, String> cells;
  final int revision, updatedAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'scopeId': scopeId,
    'title': title,
    'cells': cells,
    'revision': revision,
    'updatedAt': updatedAt,
  };
  factory SpreadsheetDocument.fromJson(Map<String, dynamic> json) =>
      SpreadsheetDocument(
        id: json['id'] as String,
        scopeId: json['scopeId'] as String,
        title: json['title'] as String,
        cells: Map<String, String>.from(json['cells'] as Map? ?? {}),
        revision: json['revision'] as int,
        updatedAt: json['updatedAt'] as int,
      );
}

class SpreadsheetLease {
  const SpreadsheetLease({
    this.token,
    required this.holderName,
    required this.holderAccountId,
    required this.holderDeviceId,
    required this.expiresAt,
  });
  final String? token;
  final String holderName, holderAccountId, holderDeviceId;
  final int expiresAt;
  bool get active => expiresAt > DateTime.now().millisecondsSinceEpoch ~/ 1000;
  factory SpreadsheetLease.fromJson(Map<String, dynamic> json) =>
      SpreadsheetLease(
        token: json['token'] as String?,
        holderName: json['holderName'] as String? ?? '',
        holderAccountId: json['holderAccountId'] as String? ?? '',
        holderDeviceId: json['holderDeviceId'] as String? ?? '',
        expiresAt: json['expiresAt'] as int,
      );
}

class SpreadsheetRead {
  const SpreadsheetRead({required this.document, this.lease});
  final SpreadsheetDocument document;
  final SpreadsheetLease? lease;
}

class SpreadsheetDraft {
  SpreadsheetDraft({
    required this.tableId,
    required this.baseRevision,
    required this.title,
    required Map<String, String> cells,
    required this.updatedAt,
  }) : cells = Map.unmodifiable(cells);
  final String tableId, title;
  final int baseRevision, updatedAt;
  final Map<String, String> cells;
  Map<String, Object?> toJson() => {
    'tableId': tableId,
    'baseRevision': baseRevision,
    'title': title,
    'cells': cells,
    'updatedAt': updatedAt,
  };
  factory SpreadsheetDraft.fromJson(Map<String, dynamic> json) =>
      SpreadsheetDraft(
        tableId: json['tableId'] as String,
        baseRevision: json['baseRevision'] as int,
        title: json['title'] as String,
        cells: Map<String, String>.from(json['cells'] as Map),
        updatedAt: json['updatedAt'] as int,
      );
}

/// Bound to one server/account/device/scope. Every method must recheck that
/// identity and current permissions, including after awaiting an HTTP request.
abstract class SpreadsheetGateway {
  String get scopeId;
  bool get canEdit;
  bool get online;
  bool get isCurrent;
  Future<List<SpreadsheetDocument>> list();
  Future<SpreadsheetRead> read(String id);
  Future<SpreadsheetDocument> create(String title);
  Future<SpreadsheetLease> acquire(String id);
  Future<SpreadsheetLease> renew(String id, String token);
  Future<SpreadsheetDocument> save(
    String id,
    String token,
    int expectedRevision,
    String title,
    Map<String, String> cells,
  );
  Future<void> release(String id, String token);
  Future<void> delete(String id, String token, int expectedRevision);
  Future<SpreadsheetDraft?> loadDraft(String id);
  Future<void> storeDraft(SpreadsheetDraft draft);
  Future<void> clearDraft(String id);
}

/// Privacy boundary for an already open local draft. This carries no shared
/// read/write permission and cannot authorize a lease or publication.
abstract interface class SpreadsheetDraftIdentity {
  bool get isDraftIdentityCurrent;
}

/// Display-only snapshots already accepted locally. They carry no edit lease
/// and never replace the gateway's fresh read/write authority checks.
abstract interface class SpreadsheetLocalPreview {
  Future<List<SpreadsheetDocument>?> cachedList();
  Future<SpreadsheetRead?> cachedRead(String id);
}

/// Optional capability view for shared tables with per-record authorship.
abstract interface class SpreadsheetRecordPermissions {
  bool canEditDocument(SpreadsheetDocument document);
  bool canDeleteDocument(SpreadsheetDocument document);
}

extension SpreadsheetRecordCapabilities on SpreadsheetGateway {
  bool canEditDocument(SpreadsheetDocument document) =>
      this is SpreadsheetRecordPermissions
      ? (this as SpreadsheetRecordPermissions).canEditDocument(document)
      : canEdit;
  bool canDeleteDocument(SpreadsheetDocument document) =>
      this is SpreadsheetRecordPermissions
      ? (this as SpreadsheetRecordPermissions).canDeleteDocument(document)
      : canEdit;
}

/// Zero based address with spreadsheet-standard finite safety bounds.
class SpreadsheetAddress {
  const SpreadsheetAddress(this.row, this.column);
  static const maxRows = 100000, maxColumns = 18278;
  final int row, column;
  bool get valid =>
      row >= 0 && row < maxRows && column >= 0 && column < maxColumns;
  String get label => '${columnLabel(column)}${row + 1}';
  static String columnLabel(int column) {
    var n = column + 1, result = '';
    while (n > 0) {
      n--;
      result = String.fromCharCode(65 + n % 26) + result;
      n ~/= 26;
    }
    return result;
  }

  static SpreadsheetAddress? parse(String input) {
    final match = RegExp(
      r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})$',
    ).firstMatch(input);
    if (match == null) return null;
    var column = 0;
    for (final code in match[1]!.toUpperCase().codeUnits) {
      column = column * 26 + code - 64;
    }
    final address = SpreadsheetAddress(int.parse(match[2]!) - 1, column - 1);
    return address.valid ? address : null;
  }
}
