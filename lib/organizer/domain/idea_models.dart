import 'dart:convert';
import 'shared_dates.dart';

enum IdeaElementKind {
  text,
  sticky,
  image,
  stroke,
  rectangle,
  ellipse,
  line,
  arrow,
}

class IdeaPoint {
  const IdeaPoint(this.x, this.y);
  final double x, y;
  Map<String, Object?> toJson() => {'x': x, 'y': y};
  factory IdeaPoint.fromJson(Map<String, dynamic> v) {
    ideaKeys(v, {'x', 'y'});
    return IdeaPoint((v['x'] as num).toDouble(), (v['y'] as num).toDouble());
  }
}

class IdeaAsset {
  const IdeaAsset({
    required this.sha256,
    required this.mime,
    required this.size,
    required this.width,
    required this.height,
  });
  final String sha256, mime;
  final int size, width, height;
  Map<String, Object?> toJson() => {
    'sha256': sha256,
    'mime': mime,
    'size': size,
    'width': width,
    'height': height,
  };
  factory IdeaAsset.fromJson(Map<String, dynamic> v) {
    ideaKeys(v, {'sha256', 'mime', 'size', 'width', 'height'});
    return IdeaAsset(
      sha256: v['sha256'] as String,
      mime: v['mime'] as String,
      size: v['size'] as int,
      width: v['width'] as int,
      height: v['height'] as int,
    )..validate();
  }
  void validate() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        !const ['image/jpeg', 'image/png'].contains(mime) ||
        size <= 0 ||
        size > 2097152 ||
        width < 1 ||
        height < 1 ||
        width > 4096 ||
        height > 4096) {
      throw const FormatException('Invalid idea image');
    }
  }
}

/// Root geometry uses board pixels. Attached geometry uses image-local units;
/// points are relative to the element origin, so moving a photo carries marks.
class IdeaElement {
  IdeaElement({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.color = 0xff263238,
    this.strokeWidth = 3,
    this.text = '',
    Iterable<IdeaPoint> points = const [],
    this.parentImageId,
    this.asset,
  }) : points = List.unmodifiable(points);
  final String id, text;
  final IdeaElementKind kind;
  final double x, y, width, height, rotation, strokeWidth;
  final int color;
  final List<IdeaPoint> points;
  final String? parentImageId;
  final IdeaAsset? asset;
  IdeaElement copyWith({
    IdeaElementKind? kind,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? color,
    double? strokeWidth,
    String? text,
    Iterable<IdeaPoint>? points,
    String? parentImageId,
    bool clearParentImageId = false,
    IdeaAsset? asset,
  }) => IdeaElement(
    id: id,
    kind: kind ?? this.kind,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    text: text ?? this.text,
    points: points ?? this.points,
    parentImageId: clearParentImageId
        ? null
        : parentImageId ?? this.parentImageId,
    asset: asset ?? this.asset,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'rotation': rotation,
    'color': color,
    'strokeWidth': strokeWidth,
    'text': text,
    'points': points.map((p) => p.toJson()).toList(),
    'parentImageId': parentImageId,
    'asset': asset?.toJson(),
  };
  factory IdeaElement.fromJson(Map<String, dynamic> v) {
    ideaKeys(v, {
      'id',
      'kind',
      'x',
      'y',
      'width',
      'height',
      'rotation',
      'color',
      'strokeWidth',
      'text',
      'points',
      'parentImageId',
      'asset',
    });
    return IdeaElement(
      id: v['id'] as String,
      kind: IdeaElementKind.values.byName(v['kind'] as String),
      x: (v['x'] as num).toDouble(),
      y: (v['y'] as num).toDouble(),
      width: (v['width'] as num).toDouble(),
      height: (v['height'] as num).toDouble(),
      rotation: (v['rotation'] as num).toDouble(),
      color: v['color'] as int,
      strokeWidth: (v['strokeWidth'] as num).toDouble(),
      text: v['text'] as String,
      points: (v['points'] as List).map(
        (p) => IdeaPoint.fromJson(p as Map<String, dynamic>),
      ),
      parentImageId: v['parentImageId'] as String?,
      asset: v['asset'] == null
          ? null
          : IdeaAsset.fromJson(v['asset'] as Map<String, dynamic>),
    );
  }
  void validate() {
    ideaId(id);
    if (parentImageId != null) ideaId(parentImageId!);
    if ([
          x,
          y,
          width,
          height,
          rotation,
          strokeWidth,
          ...points.expand((p) => [p.x, p.y]),
        ].any((v) => !v.isFinite || v.abs() > 32768) ||
        x < -16384 ||
        y < -16384 ||
        points.any((p) => p.x < -16384 || p.y < -16384) ||
        rotation.abs() > 6.283185307179586 ||
        width > 16384 ||
        height > 16384 ||
        width < 0 ||
        height < 0 ||
        strokeWidth <= 0 ||
        strokeWidth > 1000 ||
        color < 0 ||
        color > 0xffffffff ||
        text.length > 20000 ||
        text.contains('\u0000') ||
        points.length > 10000 ||
        (kind == IdeaElementKind.image) != (asset != null) ||
        (kind == IdeaElementKind.image &&
            (parentImageId != null || width <= 0 || height <= 0))) {
      throw const FormatException('Invalid idea element');
    }
    asset?.validate();
  }
}

class IdeaBoard {
  IdeaBoard({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.width = 1600,
    this.height = 1200,
    Iterable<IdeaElement> elements = const [],
    this.revision = 0,
  }) : elements = List.unmodifiable(elements);
  final String id, title;
  final String? projectId;
  final double width, height;
  final List<IdeaElement> elements;
  final int revision;
  final DateTime createdAt, updatedAt;
  Iterable<IdeaAsset> get assets =>
      elements.where((e) => e.asset != null).map((e) => e.asset!);
  IdeaBoard copyWith({
    String? id,
    String? title,
    String? projectId,
    bool clearProjectId = false,
    double? width,
    double? height,
    Iterable<IdeaElement>? elements,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => IdeaBoard(
    id: id ?? this.id,
    title: title ?? this.title,
    projectId: clearProjectId ? null : projectId ?? this.projectId,
    width: width ?? this.width,
    height: height ?? this.height,
    elements: elements ?? this.elements,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'title': title,
    'projectId': projectId,
    'width': width,
    'height': height,
    'elements': elements.map((e) => e.toJson()).toList(),
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory IdeaBoard.fromJson(Map<String, dynamic> v) {
    ideaKeys(v, {
      'version',
      'id',
      'title',
      'projectId',
      'width',
      'height',
      'elements',
      'revision',
      'createdAt',
      'updatedAt',
    });
    if (v['version'] != 1) {
      throw const FormatException('Unsupported idea board');
    }
    return IdeaBoard(
      id: v['id'] as String,
      title: v['title'] as String,
      projectId: v['projectId'] as String?,
      width: (v['width'] as num).toDouble(),
      height: (v['height'] as num).toDouble(),
      elements: (v['elements'] as List).map(
        (e) => IdeaElement.fromJson(e as Map<String, dynamic>),
      ),
      revision: v['revision'] as int,
      createdAt: readSharedDate(v, 'createdAt'),
      updatedAt: readSharedDate(v, 'updatedAt'),
    )..validate();
  }
  void validate() {
    ideaId(id);
    if (projectId != null) ideaId(projectId!);
    if (title.trim().isEmpty ||
        title.length > 200 ||
        title.contains('\u0000') ||
        !width.isFinite ||
        !height.isFinite ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        revision < 0 ||
        updatedAt.isBefore(createdAt) ||
        elements.length > 2000 ||
        assets.length > 20) {
      throw const FormatException('Invalid idea board');
    }
    final ids = <String>{};
    final images = <String>{
      for (final e in elements)
        if (e.kind == IdeaElementKind.image) e.id,
    };
    var count = 0;
    for (final e in elements) {
      e.validate();
      count += e.points.length;
      if (!ids.add(e.id) ||
          (e.parentImageId != null && !images.contains(e.parentImageId))) {
        throw const FormatException('Invalid idea element identity or parent');
      }
    }
    if (count > 50000 ||
        utf8.encode(jsonEncode(toJson())).length > 786432 ||
        ideaEscapedJsonBytes(toJson()) > 1048576) {
      throw const FormatException('Idea board too large');
    }
  }
}

class IdeaSnapshot {
  IdeaSnapshot({
    this.revision = 0,
    this.workspaceKey = 'local',
    this.canEdit = true,
    this.sharedScopeId,
    Iterable<IdeaBoard> boards = const [],
  }) : boards = List.unmodifiable(boards);
  final int revision;
  final String workspaceKey;
  final bool canEdit;
  final String? sharedScopeId;
  final List<IdeaBoard> boards;
  Map<String, Object?> toJson() => {
    'version': 1,
    'revision': revision,
    'boards': boards.map((b) => b.toJson()).toList(),
  };
  factory IdeaSnapshot.fromJson(Map<String, dynamic> v) {
    ideaKeys(v, {'version', 'revision', 'boards'});
    if (v['version'] != 1) throw const FormatException('Unsupported ideas');
    return IdeaSnapshot(
      revision: v['revision'] as int,
      boards: (v['boards'] as List).map(
        (b) => IdeaBoard.fromJson(b as Map<String, dynamic>),
      ),
    )..validate();
  }
  void validate() {
    final ids = <String>{};
    if (revision < 0 || boards.length > 1000) {
      throw const FormatException('Invalid ideas');
    }
    for (final b in boards) {
      b.validate();
      if (!ids.add(b.id)) throw const FormatException('Duplicate idea');
    }
  }
}

class IdeaMergeConflict implements Exception {
  const IdeaMergeConflict(this.elementIds);
  final List<String> elementIds;
  @override
  String toString() => 'IdeaMergeConflict(${elementIds.join(', ')})';
}

/// Three-way element merge; a conflict leaves both durable versions intact.
IdeaBoard mergeIdeaBoards(IdeaBoard base, IdeaBoard local, IdeaBoard remote) {
  if (base.id != local.id || base.id != remote.id) {
    throw const FormatException('Idea identity changed');
  }
  final conflicts = <String>[];
  T pick<T>(String key, T a, T b, T c) {
    final x = jsonEncode(a), y = jsonEncode(b), z = jsonEncode(c);
    if (y == x) return c;
    if (z == x || y == z) return b;
    conflicts.add(key);
    return b;
  }

  final a = {for (final e in base.elements) e.id: e},
      b = {for (final e in local.elements) e.id: e},
      c = {for (final e in remote.elements) e.id: e};
  final elements = <IdeaElement>[];
  for (final id in {...a.keys, ...c.keys, ...b.keys}) {
    final value = pick(id, a[id]?.toJson(), b[id]?.toJson(), c[id]?.toJson());
    if (value != null) {
      elements.add(IdeaElement.fromJson(Map<String, dynamic>.from(value)));
    }
  }
  final result = local.copyWith(
    title: pick('title', base.title, local.title, remote.title),
    projectId: pick(
      'projectId',
      base.projectId,
      local.projectId,
      remote.projectId,
    ),
    clearProjectId:
        pick('projectId', base.projectId, local.projectId, remote.projectId) ==
        null,
    width: pick('width', base.width, local.width, remote.width),
    height: pick('height', base.height, local.height, remote.height),
    elements: elements,
    revision: remote.revision,
    createdAt: remote.createdAt,
    updatedAt: local.updatedAt.isAfter(remote.updatedAt)
        ? local.updatedAt
        : remote.updatedAt,
  );
  if (conflicts.isNotEmpty) {
    throw IdeaMergeConflict(List.unmodifiable(conflicts.toSet()));
  }
  final images = result.elements
      .where((e) => e.kind == IdeaElementKind.image)
      .map((e) => e.id)
      .toSet();
  final dangling = result.elements
      .where(
        (e) => e.parentImageId != null && !images.contains(e.parentImageId),
      )
      .map((e) => e.id)
      .toList();
  if (dangling.isNotEmpty) throw IdeaMergeConflict(dangling);
  result.validate();
  return result;
}

void ideaKeys(Map<String, dynamic> v, Set<String> keys) {
  if (v.length != keys.length || !keys.containsAll(v.keys)) {
    throw const FormatException('Unsupported idea field');
  }
}

void ideaId(String id) {
  if (!RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  ).hasMatch(id)) {
    throw const FormatException('Invalid idea identity');
  }
}

/// PHP default JSON encoding escapes Unicode and forward slashes. Bounding
/// that representation keeps previews and pull envelopes below transport caps.
int ideaEscapedJsonBytes(Object? value) => jsonEncode(value).runes.fold(
  0,
  (bytes, rune) =>
      bytes +
      (rune == 47
          ? 2
          : rune > 0xffff
          ? 12
          : rune > 127
          ? 6
          : 1),
);
