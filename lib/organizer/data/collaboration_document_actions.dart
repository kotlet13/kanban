part of 'collaboration_repository.dart';

/// An immutable account/device/scope binding for the online document modules.
/// Metadata, verified bytes and local drafts never cross this boundary.
class SharedDocumentsContext {
  SharedDocumentsContext._(
    this._repo,
    this._session,
    this._epoch,
    this.scopeId,
    this._visible,
    this._onAccessLost,
  );
  final CollaborationRepository _repo;
  final DeviceSession _session;
  final int _epoch;
  final String scopeId;
  final bool Function()? _visible;
  final void Function()? _onAccessLost;
  int _documentGeneration = 0;
  bool _denied = false;
  bool online = true;
  bool spreadsheetsSupported = false, attachmentsSupported = false;
  final _bytes = <String, Uint8List>{};
  final _legacyUploads = <String, CryptoLegacyUploadDrain>{};
  String get partition => _session.profile.partition;
  String get _prefix => 'document_cache:$partition:$scopeId:';
  SharedScope? get scope => _repo.state.scopes
      .where(
        (s) =>
            s.id == scopeId &&
            s.canRead &&
            !s.blocked &&
            !s.deleted &&
            s.kind != SharedScopeKind.personal,
      )
      .firstOrNull;
  bool get isCurrent =>
      !_denied &&
      !_repo._closed &&
      _epoch == _repo._epoch &&
      _repo._session?.profile.partition == partition &&
      _repo._session?.profile.deviceId == _session.profile.deviceId &&
      _repo._sessionInvalidReason == null &&
      _repo.state.localAccessAllowed &&
      !_repo.state.deletionPending &&
      scope != null &&
      (_visible?.call() ?? true);
  bool get canEdit => isCurrent && scope!.canEdit;
  void check({bool write = false}) {
    _repo._checkEpoch(_epoch);
    if (!isCurrent || (write && !canEdit)) {
      throw const CollaborationException('permission_revoked');
    }
  }

  Future<void> _initialize() async {
    check();
    try {
      await _repo._negotiate(_session, _epoch);
    } on CollaborationException catch (error) {
      if (error.code != 'network') rethrow;
      online = false;
    }
    check();
    final caps = await _repo.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:$partition'],
    );
    check();
    final features = caps.isEmpty
        ? const <String, dynamic>{}
        : CollaborationRepository._map(caps.single['value'])['features'] as Map;
    spreadsheetsSupported = features['spreadsheets'] == true;
    attachmentsSupported = features['attachments'] == true;
  }

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params, {
    bool write = false,
  }) async {
    check(write: write);
    if (write &&
        const {
          'tables.create',
          'tables.save',
          'attachments.begin',
        }.contains(operation)) {
      await _repo.requireVerifiedEmailForConnectedEntry();
      check(write: true);
    }
    if (operation.startsWith('tables.') &&
        scope!.kind != SharedScopeKind.organization) {
      throw const CollaborationException('permission_revoked');
    }
    final supported = operation.startsWith('tables.')
        ? spreadsheetsSupported
        : attachmentsSupported;
    if (!supported) {
      throw const CollaborationException('documents_upgrade_required');
    }
    try {
      final body = {...params, 'scopeId': scopeId};
      CryptoLegacyUploadDrain? drain;
      if (operation == 'attachments.begin') {
        drain = await CryptoLegacyUploadDrain.begin(
          _repo.database,
          _session,
          scopeId,
          body,
          () async =>
              (await _repo._businessCryptoAccount(_session)).store.secure,
        );
        if (drain != null) _legacyUploads[body['id'] as String] = drain;
      } else if (const {
        'attachments.chunk',
        'attachments.complete',
      }.contains(operation)) {
        drain = _legacyUploads[body['id']];
      }
      final result = await _repo._callSession(
        _session,
        _epoch,
        operation,
        body,
        authorizeLegacyUploadDrain: drain == null
            ? null
            : () => drain!.authorize(operation, body),
      );
      drain?.accept(result);
      check(write: write);
      online = true;
      return result;
    } on CollaborationException catch (error) {
      if (error.code == 'network') online = false;
      if (error.code == 'table_unavailable' && params['id'] is String) {
        await evictTable(params['id'] as String);
      }
      if (const {
        'attachment_unavailable',
        'attachment_target_unavailable',
      }.contains(error.code)) {
        final target = '${params['targetType']}:${params['targetId']}';
        if (params['id'] is String) {
          await removeCache('file', '$target:${params['id']}');
        }
        _bytes.removeWhere((key, _) => key.startsWith('$target:'));
        await removeCache('attachments', target);
      }
      if (const {
        'permission_revoked',
        'access_revoked',
        'scope_deleted',
        'device_revoked',
        'auth_required',
        'session_expired',
      }.contains(error.code)) {
        _denied = true;
        _onAccessLost?.call();
        _bytes.clear();
        await _repo.database.execute(
          'DELETE FROM local_meta WHERE substr(name,1,?)=?',
          [_prefix.length, _prefix],
        );
        if (const {
          'permission_revoked',
          'access_revoked',
          'scope_deleted',
        }.contains(error.code)) {
          await _repo._blockScope(partition, scopeId, _epoch);
          await _repo.refreshLocal();
        }
      }
      rethrow;
    }
  }

  Future<Object?> cache(String kind, String id) async {
    check();
    final rows = await _repo.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['$_prefix$kind:$id'],
    );
    check();
    return rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
  }

  Future<void> putCache(
    String kind,
    String id,
    Object value,
  ) => _repo.database.transaction(() async {
    check();
    if (kind == 'file') {
      final metadata = (value as Map)['metadata'] as Map;
      final incoming = metadata['size'] as int;
      final keyPrefix = '${_prefix}file:';
      final rows = await _repo.database.rows(
        r"SELECT name,json_extract(value,'$.metadata.size') AS size,json_extract(value,'$.metadata.targetType') AS type,json_extract(value,'$.metadata.targetId') AS target,json_extract(value,'$.metadata.id') AS id,json_extract(value,'$.metadata.sha256') AS hash FROM local_meta WHERE substr(name,1,?)=? AND name<>? ORDER BY rowid",
        [keyPrefix.length, keyPrefix, '$_prefix$kind:$id'],
      );
      var total = rows.fold<int>(
        incoming,
        (sum, row) => sum + (row['size'] as int),
      );
      for (final row in rows) {
        if (total <= 64 * 1024 * 1024) break;
        await _repo.database.execute('DELETE FROM local_meta WHERE name=?', [
          row['name'],
        ]);
        _bytes.remove(
          '${row['type']}:${row['target']}:${row['id']}:${row['hash']}',
        );
        total -= row['size'] as int;
      }
    }
    await _repo.database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      ['$_prefix$kind:$id', jsonEncode(value)],
    );
    check();
  });
  Future<void> removeCache(String kind, String id) async {
    check();
    await _repo.database.execute('DELETE FROM local_meta WHERE name=?', [
      '$_prefix$kind:$id',
    ]);
    check();
  }

  Future<T> cachedRead<T>(
    Future<T> Function() remote,
    Future<T?> Function() cached,
  ) async {
    try {
      return await remote();
    } on CollaborationException catch (error) {
      if (error.code != 'network') rethrow;
      check();
      final value = await cached();
      if (value == null) rethrow;
      check();
      return value;
    }
  }

  Future<void> evictTable(String id) async {
    check();
    _documentGeneration++;
    await removeCache('table', id);
    await putCache('tableGone', id, true);
    final list = await cache('tableList', 'all');
    if (list is List) {
      await putCache(
        'tableList',
        'all',
        list.where((row) => (row as Map)['id'] != id).toList(),
      );
    }
    // Associated file bytes must not outlive a server-confirmed deleted table.
    final filePrefix = '${_prefix}file:table:$id:';
    await _repo.database.execute(
      'DELETE FROM local_meta WHERE substr(name,1,?)=?',
      [filePrefix.length, filePrefix],
    );
    await removeCache('attachments', 'table:$id');
    _bytes.removeWhere((key, _) => key.startsWith('table:$id:'));
    check();
  }

  Future<void> rememberTable(SpreadsheetDocument doc) async {
    final old = await cache('tableList', 'all');
    final rows = old is List ? List<Object?>.from(old) : <Object?>[];
    final index = rows.indexWhere((row) => (row as Map)['id'] == doc.id);
    final summary = {...doc.toJson(), 'cells': <String, String>{}};
    if (index < 0) {
      rows.add(summary);
    } else if (((rows[index] as Map)['revision'] as int) <= doc.revision) {
      rows[index] = summary;
    }
    await putCache('tableList', 'all', rows);
  }

  Future<String> requestId(String operation, Map<String, Object?> body) async {
    check();
    final digest = await Sha256().hash(utf8.encode(jsonEncode(body)));
    check();
    final suffix = digest.bytes
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join();
    final key =
        'document_request:$partition:${_session.profile.deviceId}:$scopeId:$operation:$suffix';
    return _repo.database.transaction(() async {
      check();
      final rows = await _repo.database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (rows.isNotEmpty) return rows.single['value'] as String;
      final id = newSharedId();
      await _repo.database.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?)',
        [key, id],
      );
      check();
      return id;
    });
  }

  Future<void> forgetRequest(String id) async {
    check();
    await _repo.database.execute(
      'DELETE FROM local_meta WHERE substr(name,1,?)=? AND value=?',
      [
        'document_request:$partition:${_session.profile.deviceId}:$scopeId:'
            .length,
        'document_request:$partition:${_session.profile.deviceId}:$scopeId:',
        id,
      ],
    );
    check();
  }

  SpreadsheetGateway get tables => _RemoteSpreadsheetGateway(this);
  AttachmentGateway attachments(AttachmentTarget target) {
    target.validate();
    if (target.scopeId != scopeId) {
      throw const CollaborationException('permission_revoked');
    }
    return _RemoteAttachmentGateway(this, target);
  }
}

extension CollaborationDocumentActions on CollaborationRepository {
  Future<SharedDocumentsContext> openDocuments(
    String scopeId, {
    bool Function()? visible,
    void Function()? onAccessLost,
  }) async {
    final context = SharedDocumentsContext._(
      this,
      _requireSession(),
      _epoch,
      scopeId,
      visible,
      onAccessLost,
    );
    await context._initialize();
    return context;
  }
}

class _RemoteSpreadsheetGateway implements SpreadsheetGateway {
  _RemoteSpreadsheetGateway(this.context);
  final SharedDocumentsContext context;
  @override
  String get scopeId => context.scopeId;
  @override
  bool get canEdit => context.canEdit && context.spreadsheetsSupported;
  @override
  bool get online => context.online;
  @override
  bool get isCurrent => context.isCurrent;
  SpreadsheetDocument _document(Object? value, {String? id}) {
    final doc = SpreadsheetDocument.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    if (doc.scopeId != scopeId ||
        (id != null && doc.id != id) ||
        !isSharedUuid(doc.id) ||
        doc.revision < 1 ||
        doc.title.trim().isEmpty ||
        utf8.encode(doc.title).length > 200 ||
        doc.cells.length > 10000 ||
        utf8.encode(jsonEncode(doc.cells)).length > 512 * 1024 ||
        doc.cells.entries.any(
          (entry) =>
              SpreadsheetAddress.parse(entry.key)?.label != entry.key ||
              utf8.encode(entry.value).length > 4096,
        )) {
      throw const CollaborationException('invalid_response');
    }
    return doc;
  }

  Future<SpreadsheetDocument> _cache(SpreadsheetDocument doc) =>
      context._repo.database.transaction(() async {
        context.check();
        final old = await context.cache('table', doc.id);
        if (await context.cache('tableGone', doc.id) == true) {
          throw const CollaborationException('table_unavailable');
        }
        if (old is Map && (old['revision'] as int) > doc.revision) {
          return _document(old, id: doc.id);
        }
        await context.putCache('table', doc.id, doc.toJson());
        context.check();
        return doc;
      });
  Future<List<SpreadsheetDocument>?> _cachedList() async {
    final rows = await context.cache('tableList', 'all');
    if (rows is! List) return null;
    final result = <SpreadsheetDocument>[];
    for (final row in rows) {
      final doc = _document(row);
      if (await context.cache('tableGone', doc.id) != true) result.add(doc);
    }
    return result;
  }

  @override
  Future<List<SpreadsheetDocument>> list() => context.cachedRead(() async {
    final generation = context._documentGeneration;
    final reply = await context.call('tables.list', {});
    if (context._documentGeneration != generation) {
      final current = await _cachedList();
      if (current != null) return current;
    }
    final docs = <SpreadsheetDocument>[];
    for (final value in reply['sheets'] as List) {
      var doc = _document(value);
      if (await context.cache('tableGone', doc.id) == true) continue;
      final cached = await context.cache('table', doc.id);
      if (cached is Map && (cached['revision'] as int) > doc.revision) {
        doc = _document(cached, id: doc.id);
      }
      docs.add(doc);
    }
    await context.putCache(
      'tableList',
      'all',
      docs.map((d) => {...d.toJson(), 'cells': <String, String>{}}).toList(),
    );
    return docs;
  }, _cachedList);
  @override
  Future<SpreadsheetRead> read(String id) => context.cachedRead(
    () async {
      final result = await context.call('tables.get', {'id': id});
      final doc = await _cache(_document(result['sheet'], id: id));
      final lease = result['lease'];
      return SpreadsheetRead(
        document: doc,
        lease: lease == null
            ? null
            : SpreadsheetLease.fromJson(
                Map<String, dynamic>.from(lease as Map),
              ),
      );
    },
    () async {
      final cached = await context.cache('table', id);
      return cached == null
          ? null
          : SpreadsheetRead(document: _document(cached, id: id));
    },
  );
  @override
  Future<SpreadsheetDocument> create(String title) async {
    final payload = <String, Object?>{'title': title};
    final request = await context.requestId('tables.create', payload);
    final result = await context.call('tables.create', {
      ...payload,
      'id': request,
      'requestId': request,
    }, write: true);
    final doc = _document(result['sheet'], id: request);
    final canonical = await _cache(doc);
    context._documentGeneration++;
    await context.rememberTable(canonical);
    await context.forgetRequest(request);
    return canonical;
  }

  @override
  Future<SpreadsheetLease> acquire(String id) async {
    final request = await context.requestId('tables.acquire', {'id': id});
    final reply = await context.call('tables.acquire', {
      'id': id,
      'requestId': request,
    }, write: true);
    final lease = SpreadsheetLease.fromJson(
      Map<String, dynamic>.from(reply['lease'] as Map),
    );
    if (lease.token == null) {
      throw const CollaborationException('invalid_response');
    }
    await context.forgetRequest(request);
    return lease;
  }

  @override
  Future<SpreadsheetLease> renew(String id, String token) async {
    final reply = await context.call('tables.renew', {
      'id': id,
      'token': token,
    }, write: true);
    final lease = SpreadsheetLease.fromJson(
      Map<String, dynamic>.from(reply['lease'] as Map),
    );
    if (lease.token == null) {
      throw const CollaborationException('invalid_response');
    }
    return lease;
  }

  @override
  Future<void> release(String id, String token) async {
    final reply = await context.call('tables.release', {
      'id': id,
      'token': token,
    }, write: true);
    if (reply['released'] != true) {
      throw const CollaborationException('invalid_response');
    }
  }

  @override
  Future<SpreadsheetDocument> save(
    String id,
    String token,
    int expectedRevision,
    String title,
    Map<String, String> cells,
  ) async {
    final body = <String, Object?>{
      'id': id,
      'token': token,
      'expectedRevision': expectedRevision,
      'title': title,
      'cells': cells,
    };
    final request = await context.requestId('tables.save', body);
    final result = await context.call('tables.save', {
      ...body,
      'requestId': request,
    }, write: true);
    final doc = await _cache(_document(result['sheet'], id: id));
    context._documentGeneration++;
    await context.rememberTable(doc);
    await context.forgetRequest(request);
    return doc;
  }

  @override
  Future<void> delete(String id, String token, int expectedRevision) async {
    final body = <String, Object?>{
      'id': id,
      'token': token,
      'expectedRevision': expectedRevision,
    };
    final request = await context.requestId('tables.delete', body);
    final reply = await context.call('tables.delete', {
      ...body,
      'requestId': request,
    }, write: true);
    if (reply['deleted'] != true) {
      throw const CollaborationException('invalid_response');
    }
    await context.evictTable(id);
    await clearDraft(id);
    await context.forgetRequest(request);
  }

  String _draftKey(String id) =>
      'table_draft:${context.partition}:$scopeId:$id';
  @override
  Future<SpreadsheetDraft?> loadDraft(String id) async {
    context.check();
    final rows = await context._repo.database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [_draftKey(id)],
    );
    final recovered = rows.isEmpty
        ? await CryptoMigrationIdeaDraftRecovery.tableDraft(
            context._repo.database,
            context.partition,
            scopeId,
            id,
          )
        : null;
    context.check();
    return rows.isEmpty && recovered == null
        ? null
        : SpreadsheetDraft.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(recovered ?? rows.single['value'] as String) as Map,
            ),
          );
  }

  @override
  Future<void> storeDraft(
    SpreadsheetDraft draft,
  ) => context._repo.database.transaction(() async {
    // This is a local-only write to the immutable initiating partition. A queued
    // keystroke must survive account/ACL changes; it cannot become new-account data.
    // An explicitly deleted account is a permanent boundary, including late writes.
    final deleted = await context._repo.database
        .rows('SELECT name FROM local_meta WHERE name IN (?,?)', [
          'deleted_account:${context.partition}',
          'deletion_pending:${context.partition}',
        ]);
    if (deleted.isNotEmpty) {
      throw const CollaborationException('account_deleted');
    }
    await context._repo.database.execute(
      'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
      [_draftKey(draft.tableId), jsonEncode(draft.toJson())],
    );
  });
  @override
  Future<void> clearDraft(String id) async {
    context.check();
    await context._repo.database.execute(
      'DELETE FROM local_meta WHERE name=?',
      [_draftKey(id)],
    );
    await context._repo.database.execute(
      'INSERT OR REPLACE INTO local_meta VALUES(?,?)',
      [
        'migration_table_draft_dismissed:${context.partition}:$scopeId:$id',
        '1',
      ],
    );
    context.check();
  }
}

class _RemoteAttachmentGateway implements AttachmentGateway {
  _RemoteAttachmentGateway(this.context, this.target);
  final SharedDocumentsContext context;
  @override
  final AttachmentTarget target;
  String get _targetKey => '${target.targetType}:${target.targetId}';
  @override
  bool get isOnline => context.online;
  @override
  bool get isCurrent => context.isCurrent;
  AttachmentMetadata _metadata(Object? value, {String? id}) {
    final metadata = AttachmentMetadata.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    metadata.validate();
    if (metadata.target != target || (id != null && metadata.id != id)) {
      throw const CollaborationException('invalid_response');
    }
    return metadata;
  }

  Map<String, Object?> get _params => target.toJson();
  @override
  Future<List<AttachmentMetadata>> list() => context.cachedRead(
    () async {
      final reply = await context.call('attachments.list', _params);
      final entries = (reply['attachments'] as List)
          .map((v) => _metadata(v))
          .toList();
      if (entries.any((entry) => !entry.complete)) {
        throw const CollaborationException('invalid_response');
      }
      await context.putCache(
        'attachments',
        _targetKey,
        entries.map((e) => e.toJson()).toList(),
      );
      return entries;
    },
    () async {
      final rows = await context.cache('attachments', _targetKey);
      return rows == null
          ? null
          : await _ready((rows as List).map((r) => _metadata(r)).toList());
    },
  );
  Future<List<AttachmentMetadata>> _ready(
    List<AttachmentMetadata> entries,
  ) async {
    if (context.online) return entries;
    for (final entry in entries) {
      final stored = await context.cache('file', '$_targetKey:${entry.id}');
      if (stored is! Map) continue;
      try {
        final metadata = _metadata(stored['metadata'], id: entry.id);
        if (metadata.sha256 != entry.sha256 || metadata.size != entry.size) {
          throw const CollaborationException('invalid_response');
        }
        final bytes = base64Decode(stored['data'] as String);
        await _verify(entry, bytes);
        context._bytes['$_targetKey:${entry.id}:${entry.sha256}'] = bytes;
      } on FormatException {
        await context.removeCache('file', '$_targetKey:${entry.id}');
      } on CollaborationException catch (error) {
        if (error.code != 'invalid_response') rethrow;
        await context.removeCache('file', '$_targetKey:${entry.id}');
      }
    }
    return entries;
  }

  @override
  Uint8List? localBytes(AttachmentMetadata attachment) {
    context.check();
    if (attachment.target != target) return null;
    final bytes =
        context._bytes['$_targetKey:${attachment.id}:${attachment.sha256}'];
    return bytes?.asUnmodifiableView();
  }

  Future<void> _verify(AttachmentMetadata metadata, Uint8List bytes) async {
    if (bytes.length != metadata.size) {
      throw const CollaborationException('invalid_response');
    }
    final digest = await Sha256().hash(bytes);
    final hash = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (hash != metadata.sha256) {
      throw const CollaborationException('invalid_response');
    }
    context.check();
  }

  @override
  Future<Uint8List> download(
    AttachmentMetadata attachment, {
    void Function(double)? onProgress,
  }) async {
    attachment.validate();
    if (attachment.target != target || !attachment.complete) {
      throw const CollaborationException('permission_revoked');
    }
    context.check();
    // A cached file never bypasses a fresh online permission check.
    try {
      final builder = BytesBuilder(copy: false);
      while (builder.length < attachment.size) {
        final offset = builder.length;
        final reply = await context.call('attachments.get', {
          ..._params,
          'id': attachment.id,
          'offset': offset,
          'limit': attachmentChunkBytes,
        });
        final metadata = _metadata(reply['attachment'], id: attachment.id);
        if (metadata.sha256 != attachment.sha256 ||
            metadata.size != attachment.size ||
            reply['offset'] != offset ||
            reply['total'] != attachment.size) {
          throw const CollaborationException('invalid_response');
        }
        final chunk = base64Decode(reply['dataBase64'] as String);
        if (chunk.isEmpty ||
            chunk.length > attachmentChunkBytes ||
            builder.length + chunk.length > attachment.size) {
          throw const CollaborationException('invalid_response');
        }
        builder.add(chunk);
        onProgress?.call(builder.length / attachment.size);
      }
      final result = builder.takeBytes();
      await _verify(attachment, result);
      await context.putCache('file', '$_targetKey:${attachment.id}', {
        'metadata': attachment.toJson(),
        'data': base64Encode(result),
      });
      context._bytes['$_targetKey:${attachment.id}:${attachment.sha256}'] =
          Uint8List.fromList(result);
      return result;
    } on CollaborationException catch (error) {
      if (error.code != 'network') rethrow;
      context.check();
      final cached = await context.cache(
        'file',
        '$_targetKey:${attachment.id}',
      );
      if (cached == null) rethrow;
      final data = cached as Map;
      final metadata = _metadata(data['metadata'], id: attachment.id);
      if (metadata.sha256 != attachment.sha256) rethrow;
      final result = base64Decode(data['data'] as String);
      await _verify(attachment, result);
      context._bytes['$_targetKey:${attachment.id}:${attachment.sha256}'] =
          Uint8List.fromList(result);
      return result;
    }
  }

  @override
  Future<void> upload({
    required String name,
    required String mime,
    required Uint8List bytes,
    void Function(double)? onProgress,
  }) async {
    validateAttachmentFile(name, bytes.length, mime: mime);
    context.check(write: true);
    final digest = await Sha256().hash(bytes);
    context.check(write: true);
    final hash = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final body = <String, Object?>{
      ..._params,
      'name': name,
      'mime': mime,
      'size': bytes.length,
      'sha256': hash,
    };
    final request = await context.requestId('attachments.begin', body);
    final begin = await context.call('attachments.begin', {
      ...body,
      'id': request,
      'requestId': request,
    }, write: true);
    var metadata = _metadata(begin['attachment'], id: request);
    if (metadata.sha256 != hash || metadata.size != bytes.length) {
      throw const CollaborationException('invalid_response');
    }
    for (
      var offset = metadata.offset;
      !metadata.complete && offset < bytes.length;
    ) {
      final end = (offset + attachmentChunkBytes).clamp(0, bytes.length);
      final reply = await context.call('attachments.chunk', {
        ..._params,
        'id': metadata.id,
        'offset': offset,
        'dataBase64': base64Encode(bytes.sublist(offset, end)),
      }, write: true);
      metadata = _metadata(reply['attachment'], id: request);
      if (metadata.offset != end ||
          metadata.sha256 != hash ||
          metadata.size != bytes.length) {
        throw const CollaborationException('invalid_response');
      }
      offset = end;
      onProgress?.call(offset / bytes.length);
    }
    final completeReceipt = await context.requestId('attachments.complete', {
      'id': request,
    });
    if (!metadata.complete) {
      final complete = await context.call('attachments.complete', {
        ..._params,
        'id': request,
        'requestId': completeReceipt,
      }, write: true);
      metadata = _metadata(complete['attachment'], id: request);
    }
    if (!metadata.complete ||
        metadata.offset != bytes.length ||
        metadata.sha256 != hash) {
      throw const CollaborationException('invalid_response');
    }
    await context.putCache('file', '$_targetKey:${metadata.id}', {
      'metadata': metadata.toJson(),
      'data': base64Encode(bytes),
    });
    await context.forgetRequest(request);
    await context.forgetRequest(completeReceipt);
    context._bytes['$_targetKey:${metadata.id}:${metadata.sha256}'] =
        Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(AttachmentMetadata attachment) async {
    if (attachment.target != target) {
      throw const CollaborationException('permission_revoked');
    }
    final body = <String, Object?>{..._params, 'id': attachment.id};
    final request = await context.requestId('attachments.delete', body);
    final reply = await context.call('attachments.delete', {
      ...body,
      'requestId': request,
    }, write: true);
    if (reply['deleted'] != true) {
      throw const CollaborationException('invalid_response');
    }
    await context.removeCache('file', '$_targetKey:${attachment.id}');
    context._bytes.remove('$_targetKey:${attachment.id}:${attachment.sha256}');
    await context.forgetRequest(request);
  }
}
