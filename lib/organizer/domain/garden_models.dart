import 'dart:convert';
import 'shared_dates.dart';

/// A manually drawn rectangle on a unit canvas. It has no physical scale.
class GardenArea {
  const GardenArea({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  final String id, label;
  final double x, y, width, height;
  GardenArea copyWith({
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
  }) => GardenArea(
    id: id,
    label: label ?? this.label,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
  factory GardenArea.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'label', 'x', 'y', 'width', 'height'});
    final area = GardenArea(
      id: json['id'] as String,
      label: json['label'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
    area.validate();
    return area;
  }
  void validate() {
    _id(id);
    _text(label, 200, required: true);
    if ([x, y, width, height].any((v) => !v.isFinite) ||
        x < 0 ||
        y < 0 ||
        x > 1 ||
        y > 1 ||
        width <= 0 ||
        height <= 0 ||
        width > 1 ||
        height > 1 ||
        x + width > 1 ||
        y + height > 1) {
      throw const FormatException('Garden area outside canvas');
    }
  }
}

class Garden {
  Garden({
    required this.id,
    required this.name,
    this.notes = '',
    Iterable<GardenArea> areas = const [],
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
  }) : areas = List.unmodifiable(areas);
  final String id, name, notes;
  final List<GardenArea> areas;
  final int revision;
  final DateTime createdAt, updatedAt;
  Garden copyWith({
    String? name,
    String? notes,
    Iterable<GardenArea>? areas,
    int? revision,
    DateTime? updatedAt,
  }) => Garden(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    areas: areas ?? this.areas,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'areas': areas.map((v) => v.toJson()).toList(),
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory Garden.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'name',
      'notes',
      'areas',
      'revision',
      'createdAt',
      'updatedAt',
    });
    final garden = Garden(
      id: json['id'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String,
      revision: json['revision'] as int,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      areas: (json['areas'] as List).map(
        (v) => GardenArea.fromJson(v as Map<String, dynamic>),
      ),
    );
    garden.validate();
    return garden;
  }
  void validate() {
    _id(id);
    _text(name, 200, required: true);
    _text(notes, 20000);
    if (revision < 0 || updatedAt.isBefore(createdAt) || areas.length > 1000) {
      throw const FormatException('Invalid garden');
    }
    final ids = <String>{};
    for (final area in areas) {
      area.validate();
      if (!ids.add(area.id)) {
        throw const FormatException('Duplicate garden area');
      }
    }
  }
}

class GardenSnapshot {
  GardenSnapshot({this.revision = 0, Iterable<Garden> gardens = const []})
    : gardens = List.unmodifiable(gardens);
  final int revision;
  final List<Garden> gardens;
  static const maxBytes = 10 * 1024 * 1024;
  Set<String> get recordIds => {
    for (final g in gardens) g.id,
    for (final g in gardens)
      for (final a in g.areas) a.id,
  };
  Map<String, Object?> toJson() => {
    'version': 1,
    'revision': revision,
    'gardens': gardens.map((g) => g.toJson()).toList(),
  };
  factory GardenSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      _keys(json, {'version', 'revision', 'gardens'});
      if (json['version'] != 1) {
        throw const FormatException();
      }
      final snapshot = GardenSnapshot(
        revision: json['revision'] as int,
        gardens: (json['gardens'] as List).map(
          (v) => Garden.fromJson(v as Map<String, dynamic>),
        ),
      );
      snapshot.validate();
      return snapshot;
    } on Object {
      throw const FormatException('Unsupported garden data');
    }
  }
  void validate() {
    if (revision < 0 || gardens.length > 500) {
      throw const FormatException('Invalid garden count/revision');
    }
    final ids = <String>{};
    for (final garden in gardens) {
      garden.validate();
      for (final id in [garden.id, ...garden.areas.map((v) => v.id)]) {
        if (!ids.add(id)) {
          throw const FormatException('Duplicate garden identity');
        }
      }
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxBytes) {
      throw const FormatException('Garden data exceeds 10 MiB');
    }
  }
}

GardenSnapshot mergeGardenSnapshots(GardenSnapshot a, GardenSnapshot b) {
  if (a.recordIds.intersection(b.recordIds).isNotEmpty) {
    throw const FormatException('Garden identity collision');
  }
  return GardenSnapshot(
    revision: a.revision,
    gardens: [...a.gardens, ...b.gardens],
  )..validate();
}

void _keys(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length ||
      json.keys.toSet().difference(keys).isNotEmpty) {
    throw const FormatException('Unsupported garden field');
  }
}

void _id(String id) {
  if (!RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
  ).hasMatch(id)) {
    throw const FormatException('Invalid garden identity');
  }
}

void _text(String value, int max, {bool required = false}) {
  if (value.length > max || (required && value.trim().isEmpty)) {
    throw const FormatException('Invalid garden text');
  }
}

DateTime _date(Object? value) => readSharedDate({'date': value}, 'date');
