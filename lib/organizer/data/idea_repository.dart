import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show compute;
import 'package:cryptography/cryptography.dart';
import '../domain/idea_models.dart';
import 'idea_storage.dart';
import 'organizer_repository.dart' show newLocalId, OrganizerConflictException;

class IdeaRepository {
  IdeaRepository(
    this.storage, {
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? newLocalId {
    _subscription = storage.changes.listen((_) {
      if (!_closed) {
        unawaited(reload().catchError((Object _) {}));
      }
    });
  }
  final IdeaStorage storage;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final _changes = StreamController<IdeaSnapshot>.broadcast();
  late final StreamSubscription<void> _subscription;
  Future<void> _tail = Future.value();
  bool _closed = false;
  IdeaSnapshot? _snapshot;
  Stream<IdeaSnapshot> get changes => _changes.stream;
  IdeaSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Idea is still loading'));
  Future<T> _queue<T>(Future<T> Function() action) {
    if (_closed) {
      return Future.error(StateError('Idea repository closed'));
    }
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<IdeaSnapshot> initialize() =>
      _queue(() async => _snapshot = await storage.read());
  Future<void> reload() => _queue(() async {
    try {
      _snapshot = await storage.read();
      _changes.add(snapshot);
    } catch (e, s) {
      _snapshot = null;
      _changes.addError(e, s);
      rethrow;
    }
  });
  Future<T> _change<T>(
    FutureOr<(IdeaSnapshot, T)> Function(IdeaSnapshot) change, {
    String? expectedWorkspaceKey,
  }) {
    final generation = storage.identityGeneration;
    final workspace = expectedWorkspaceKey ?? storage.workspaceKey;
    return _queue(() async {
      if (generation != storage.identityGeneration ||
          workspace != storage.workspaceKey) {
        throw const OrganizerConflictException('Idea workspace changed');
      }
      final previous = await storage.read();
      final (candidate, result) = await change(previous);
      await storage.write(
        candidate,
        expectedRevision: previous.revision,
        expectedWorkspaceKey: workspace,
        expectedIdentityGeneration: generation,
      );
      _snapshot = await storage.read();
      _changes.add(snapshot);
      storage.database.personalChanged();
      return result;
    });
  }

  Future<String> createBoard({
    required String title,
    String? projectId,
    String? expectedWorkspaceKey,
  }) => _change((s) {
    final now = _clock().toUtc(), id = _idGenerator();
    final board = IdeaBoard(
      id: id,
      title: title.trim(),
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );
    return (
      IdeaSnapshot(revision: s.revision, boards: [...s.boards, board]),
      id,
    );
  }, expectedWorkspaceKey: expectedWorkspaceKey);
  Future<void> saveBoard(
    IdeaBoard board, {
    bool isNew = false,
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) {
    if (!isNew) {
      return updateBoard(
        board,
        base: base,
        expectedWorkspaceKey: expectedWorkspaceKey,
      );
    }
    return _change<void>((s) {
      if (s.boards.any((b) => b.id == board.id)) {
        throw const OrganizerConflictException('Idea already exists');
      }
      board.validate();
      return (
        IdeaSnapshot(revision: s.revision, boards: [...s.boards, board]),
        null,
      );
    }, expectedWorkspaceKey: expectedWorkspaceKey);
  }

  Future<void> updateBoard(
    IdeaBoard board, {
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) => _change<void>((s) async {
    await storage.validateEditorBase(base ?? board);
    final current = s.boards.where((b) => b.id == board.id).firstOrNull;
    if (current == null || current.createdAt != board.createdAt) {
      throw const OrganizerConflictException('Idea no longer exists');
    }
    var updated = board;
    if (current.revision != board.revision) {
      if (base == null) {
        throw const OrganizerConflictException(
          'Idea changed; reload before editing',
        );
      }
      updated = mergeIdeaBoards(base, board, current);
    }
    final now = _clock().toUtc();
    updated = updated.copyWith(
      revision: current.revision + 1,
      updatedAt: now.isBefore(current.updatedAt) ? current.updatedAt : now,
    );
    return (
      IdeaSnapshot(
        revision: s.revision,
        boards: s.boards.map((b) => b.id == board.id ? updated : b),
      ),
      null,
    );
  }, expectedWorkspaceKey: expectedWorkspaceKey);

  Future<void> deleteBoard(IdeaBoard board, {String? expectedWorkspaceKey}) =>
      _change<void>((s) {
        final current = s.boards.where((b) => b.id == board.id).firstOrNull;
        if (current == null ||
            current.revision != board.revision ||
            current.createdAt != board.createdAt) {
          throw const OrganizerConflictException(
            'Idea changed; reload before deleting',
          );
        }
        return (
          IdeaSnapshot(
            revision: s.revision,
            boards: s.boards.where((b) => b.id != board.id),
          ),
          null,
        );
      }, expectedWorkspaceKey: expectedWorkspaceKey);
  Future<void> saveDraft(
    IdeaBoard board, {
    IdeaBoard? base,
    String? expectedWorkspaceKey,
  }) async {
    await storage.checkWritable();
    if (expectedWorkspaceKey != null &&
        expectedWorkspaceKey != storage.workspaceKey) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    board.validate();
    if (base != null && base.id != board.id) {
      throw const FormatException('Idea draft base identity mismatch');
    }
    base?.validate();
    await storage.database.transaction(() async {
      await storage.checkWritable();
      if (workspace != storage.workspaceKey ||
          generation != storage.identityGeneration) {
        throw const OrganizerConflictException('Idea workspace changed');
      }
      await storage.database.execute(
        'INSERT INTO idea_drafts(workspace,id,payload,base) VALUES(?,?,?,?) ON CONFLICT(workspace,id) DO UPDATE SET payload=excluded.payload,base=excluded.base',
        [
          workspace,
          board.id,
          jsonEncode(board.toJson()),
          base == null ? null : jsonEncode(base.toJson()),
        ],
      );
      if (workspace != storage.workspaceKey ||
          generation != storage.identityGeneration) {
        throw const OrganizerConflictException('Idea workspace changed');
      }
      await storage.database.touchPersonal();
    });
    storage.database.personalChanged();
    if (!_closed) {
      _changes.add(
        IdeaSnapshot(
          revision: snapshot.revision,
          workspaceKey: snapshot.workspaceKey,
          canEdit: snapshot.canEdit,
          sharedScopeId: snapshot.sharedScopeId,
          boards: snapshot.boards,
        ),
      );
    }
  }

  Future<List<IdeaBoard>> listDrafts() async {
    await storage.checkDurableAccess();
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    final rows = await storage.database.rows(
      'SELECT payload FROM idea_drafts WHERE workspace=? ORDER BY id',
      [workspace],
    );
    if (workspace != storage.workspaceKey ||
        generation != storage.identityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    return List.unmodifiable(
      rows.map(
        (r) => IdeaBoard.fromJson(
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        ),
      ),
    );
  }

  Future<IdeaBoard?> readDraft(String id) async {
    await storage.checkDurableAccess();
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    final rows = await storage.database.rows(
      'SELECT payload FROM idea_drafts WHERE workspace=? AND id=?',
      [workspace, id],
    );
    if (workspace != storage.workspaceKey ||
        generation != storage.identityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    return rows.isEmpty
        ? null
        : IdeaBoard.fromJson(
            jsonDecode(rows.single['payload'] as String)
                as Map<String, dynamic>,
          );
  }

  Future<IdeaBoard?> readDraftBase(String id) async {
    await storage.checkDurableAccess();
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    final rows = await storage.database.rows(
      'SELECT base FROM idea_drafts WHERE workspace=? AND id=?',
      [workspace, id],
    );
    if (workspace != storage.workspaceKey ||
        generation != storage.identityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    return rows.isEmpty || rows.single['base'] == null
        ? null
        : IdeaBoard.fromJson(
            jsonDecode(rows.single['base'] as String) as Map<String, dynamic>,
          );
  }

  Future<void> discardDraft(String id) async {
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    await storage.database.transaction(() async {
      await storage.checkWritable();
      if (workspace != storage.workspaceKey ||
          generation != storage.identityGeneration) {
        throw const OrganizerConflictException('Idea workspace changed');
      }
      await storage.database.execute(
        'DELETE FROM idea_drafts WHERE workspace=? AND id=?',
        [workspace, id],
      );
      await storage.database.touchPersonal();
    });
    storage.database.personalChanged();
    if (!_closed) {
      _changes.add(
        IdeaSnapshot(
          revision: snapshot.revision,
          workspaceKey: snapshot.workspaceKey,
          canEdit: snapshot.canEdit,
          sharedScopeId: snapshot.sharedScopeId,
          boards: snapshot.boards,
        ),
      );
    }
  }

  Future<IdeaAsset> importImage(Uint8List bytes) async {
    await storage.checkWritable();
    final generation = storage.identityGeneration,
        workspace = storage.workspaceKey;
    if (bytes.length > 20 * 1024 * 1024 ||
        bytes.length < 8 ||
        !((bytes[0] == 0xff && bytes[1] == 0xd8) ||
            (bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4e &&
                bytes[3] == 0x47))) {
      throw const FormatException('Choose a JPEG or PNG image');
    }
    final (normalized, mime, width, height) = await compute(
      _normalizeIdeaImage,
      bytes,
    );
    final asset = IdeaAsset(
      sha256: (await Sha256().hash(
        normalized,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      mime: mime,
      size: normalized.length,
      width: width,
      height: height,
    )..validate();
    if (generation != storage.identityGeneration ||
        workspace != storage.workspaceKey) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    await storeAsset(asset, normalized);
    return asset;
  }

  Future<void> storeAsset(IdeaAsset asset, Uint8List bytes) async {
    await storage.checkWritable();
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    await verifyIdeaAsset(asset, bytes);
    if (workspace != storage.workspaceKey ||
        generation != storage.identityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    await storage.database.transaction(() async {
      await storage.checkWritable();
      if (workspace != storage.workspaceKey ||
          generation != storage.identityGeneration) {
        throw const OrganizerConflictException('Idea workspace changed');
      }
      await storage.database.execute(
        'INSERT INTO idea_assets(workspace,sha256,metadata,bytes) VALUES(?,?,?,?) ON CONFLICT(workspace,sha256) DO UPDATE SET metadata=excluded.metadata,bytes=excluded.bytes',
        [workspace, asset.sha256, jsonEncode(asset.toJson()), bytes],
      );
      await storage.database.touchPersonal();
    });
    storage.database.personalChanged();
  }

  Future<Uint8List?> readAsset(IdeaAsset asset) async {
    await storage.checkDurableAccess();
    final workspace = storage.workspaceKey,
        generation = storage.identityGeneration;
    final rows = await storage.database.rows(
      'SELECT bytes FROM idea_assets WHERE workspace=? AND sha256=?',
      [workspace, asset.sha256],
    );
    if (rows.isEmpty) return null;
    final bytes = Uint8List.fromList(rows.single['bytes'] as List<int>);
    await verifyIdeaAsset(asset, bytes);
    if (workspace != storage.workspaceKey ||
        generation != storage.identityGeneration) {
      throw const OrganizerConflictException('Idea workspace changed');
    }
    await storage.checkDurableAccess();
    return bytes;
  }

  Future<void> ensureAssets(IdeaBoard board) => storage.ensureAssets(board);

  Future<void> close() async {
    _closed = true;
    await _subscription.cancel();
    await _tail;
    await _changes.close();
  }
}

Future<void> verifyIdeaAsset(IdeaAsset asset, Uint8List bytes) async {
  asset.validate();
  final hash = (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  if (bytes.length != asset.size || hash != asset.sha256) {
    throw const FormatException('Idea image integrity check failed');
  }
  final decoder = asset.mime == 'image/png'
      ? img.PngDecoder()
      : img.JpegDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width != asset.width ||
      info.height != asset.height) {
    throw const FormatException('Idea image dimensions mismatch');
  }
  if (decoder.decode(bytes) == null) {
    throw const FormatException('Idea image cannot be decoded');
  }
  final png =
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;
  final jpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
  if ((asset.mime == 'image/png' && !png) ||
      (asset.mime == 'image/jpeg' && !jpeg)) {
    throw const FormatException('Idea image MIME mismatch');
  }
}

(Uint8List, String, int, int) _normalizeIdeaImage(Uint8List bytes) {
  final decoder = bytes[0] == 0x89 ? img.PngDecoder() : img.JpegDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 32000000) {
    throw const FormatException('Image dimensions exceed import limit');
  }
  final decoded = decoder.decode(bytes);
  if (decoded == null || decoded.width * decoded.height > 64000000) {
    throw const FormatException('Image could not be decoded');
  }
  var image = img.bakeOrientation(decoded);
  if (image.width > 4096 || image.height > 4096) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 4096 : null,
      height: image.height > image.width ? 4096 : null,
    );
  }
  image = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: image.getBytes(order: img.ChannelOrder.rgba).buffer,
    numChannels: 4,
  );
  final isPng = bytes[0] == 0x89;
  var normalized = Uint8List.fromList(
    isPng ? img.encodePng(image) : img.encodeJpg(image, quality: 85),
  );
  while (normalized.length > 2097152 &&
      (image.width > 256 || image.height > 256)) {
    image = img.copyResize(
      image,
      width: (image.width * 0.8).round().clamp(1, 4096),
      height: (image.height * 0.8).round().clamp(1, 4096),
    );
    normalized = Uint8List.fromList(
      isPng ? img.encodePng(image) : img.encodeJpg(image, quality: 85),
    );
  }
  return (
    normalized,
    isPng ? 'image/png' : 'image/jpeg',
    image.width,
    image.height,
  );
}
