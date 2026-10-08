import 'dart:convert';
import 'shared_dates.dart';

enum GardenAreaKind { bed, zone }

enum GardenPlantingStatus { planned, actual }

/// A manually drawn rectangle on a unit canvas. It has no physical scale.
class GardenArea {
  const GardenArea({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.kind = GardenAreaKind.bed,
    this.archived = false,
  });
  final String id, label;
  final double x, y, width, height;
  final GardenAreaKind kind;
  final bool archived;
  GardenArea copyWith({
    String? label,
    double? x,
    double? y,
    double? width,
    double? height,
    GardenAreaKind? kind,
    bool? archived,
  }) => GardenArea(
    id: id,
    label: label ?? this.label,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    kind: kind ?? this.kind,
    archived: archived ?? this.archived,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'kind': kind.name,
    'archived': archived,
  };
  factory GardenArea.fromJson(Map<String, dynamic> json) {
    final extended = json.containsKey('kind') || json.containsKey('archived');
    _keys(json, {
      'id',
      'label',
      'x',
      'y',
      'width',
      'height',
      if (extended) ...['kind', 'archived'],
    });
    final area = GardenArea(
      id: json['id'] as String,
      label: json['label'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      kind: extended
          ? GardenAreaKind.values.byName(json['kind'] as String)
          : GardenAreaKind.bed,
      archived: extended ? json['archived'] as bool : false,
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

/// A calendar date is stored without a timezone; it is not a delivery instant.
/// Decoded values use UTC calendar markers. Format their date fields directly
/// without converting to local time, which could change the calendar day.
class GardenPlanting {
  const GardenPlanting({
    required this.id,
    required this.areaId,
    required this.crop,
    this.variety = '',
    this.family = '',
    this.status = GardenPlantingStatus.planned,
    this.sowAt,
    this.plantAt,
    this.harvestAt,
    this.notes = '',
  });
  final String id, areaId, crop, variety, family, notes;
  final GardenPlantingStatus status;
  final DateTime? sowAt, plantAt, harvestAt;
  GardenPlanting copyWith({
    String? crop,
    String? variety,
    String? family,
    GardenPlantingStatus? status,
    String? notes,
    DateTime? sowAt,
    DateTime? plantAt,
    DateTime? harvestAt,
    bool clearSowAt = false,
    bool clearPlantAt = false,
    bool clearHarvestAt = false,
  }) => GardenPlanting(
    id: id,
    areaId: areaId,
    crop: crop ?? this.crop,
    variety: variety ?? this.variety,
    family: family ?? this.family,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    sowAt: clearSowAt ? null : sowAt ?? this.sowAt,
    plantAt: clearPlantAt ? null : plantAt ?? this.plantAt,
    harvestAt: clearHarvestAt ? null : harvestAt ?? this.harvestAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'areaId': areaId,
    'crop': crop,
    'variety': variety,
    'family': family,
    'status': status.name,
    'notes': notes,
    'sowAt': _calendarJson(sowAt),
    'plantAt': _calendarJson(plantAt),
    'harvestAt': _calendarJson(harvestAt),
  };
  factory GardenPlanting.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'areaId',
      'crop',
      'variety',
      'family',
      'status',
      'notes',
      'sowAt',
      'plantAt',
      'harvestAt',
    });
    return GardenPlanting(
      id: json['id'] as String,
      areaId: json['areaId'] as String,
      crop: json['crop'] as String,
      variety: json['variety'] as String,
      family: json['family'] as String,
      status: GardenPlantingStatus.values.byName(json['status'] as String),
      notes: json['notes'] as String,
      sowAt: _calendarDate(json['sowAt']),
      plantAt: _calendarDate(json['plantAt']),
      harvestAt: _calendarDate(json['harvestAt']),
    )..validate();
  }
  void validate() {
    _id(id);
    _id(areaId);
    _text(crop, 200, required: true);
    _text(variety, 200);
    _text(family, 200);
    _text(notes, 20000);
    final dates = [sowAt, plantAt, harvestAt].whereType<DateTime>().toList();
    for (final date in dates) {
      if (date.year < 1900 ||
          date.year > 9999 ||
          date.hour != 0 ||
          date.minute != 0 ||
          date.second != 0 ||
          date.millisecond != 0 ||
          date.microsecond != 0) {
        throw const FormatException('Invalid planting calendar date');
      }
    }
    for (var i = 1; i < dates.length; i++) {
      if (_calendarJson(dates[i])!.compareTo(_calendarJson(dates[i - 1])!) <
          0) {
        throw const FormatException('Planting dates out of order');
      }
    }
  }
}

class GardenSeason {
  GardenSeason({
    required this.year,
    this.notes = '',
    Iterable<GardenPlanting> plantings = const [],
  }) : plantings = List.unmodifiable(plantings);
  final int year;
  final String notes;
  final List<GardenPlanting> plantings;
  GardenSeason copyWith({String? notes, Iterable<GardenPlanting>? plantings}) =>
      GardenSeason(
        year: year,
        notes: notes ?? this.notes,
        plantings: plantings ?? this.plantings,
      );
  List<GardenPlanting> plantingsForArea(String areaId) =>
      List.unmodifiable(plantings.where((p) => p.areaId == areaId));
  Map<String, Object?> toJson() => {
    'year': year,
    'notes': notes,
    'plantings': plantings.map((p) => p.toJson()).toList(),
  };
  factory GardenSeason.fromJson(Map<String, dynamic> json) {
    _keys(json, {'year', 'notes', 'plantings'});
    return GardenSeason(
      year: json['year'] as int,
      notes: json['notes'] as String,
      plantings: (json['plantings'] as List).map(
        (v) => GardenPlanting.fromJson(v as Map<String, dynamic>),
      ),
    )..validate();
  }
  void validate() {
    if (year < 1900 || year > 9999 || plantings.length > 2000) {
      throw const FormatException('Invalid garden season');
    }
    _text(notes, 20000);
    final ids = <String>{};
    for (final planting in plantings) {
      planting.validate();
      if (!ids.add(planting.id)) {
        throw const FormatException('Duplicate season planting');
      }
    }
  }
}

String? _calendarJson(DateTime? date) => date == null
    ? null
    : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime? _calendarDate(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid planting calendar date');
  }
  final parts = value.split('-').map(int.parse).toList();
  final result = DateTime.utc(parts[0], parts[1], parts[2]);
  if (_calendarJson(result) != value) {
    throw const FormatException('Invalid planting calendar date');
  }
  return result;
}

class Garden {
  Garden({
    required this.id,
    required this.name,
    this.notes = '',
    Iterable<GardenArea> areas = const [],
    Iterable<GardenSeason> seasons = const [],
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
  }) : areas = List.unmodifiable(areas),
       seasons = List.unmodifiable(seasons);
  final String id, name, notes;
  final List<GardenArea> areas;
  final List<GardenSeason> seasons;
  GardenSeason? seasonForYear(int year) =>
      seasons.where((s) => s.year == year).firstOrNull;
  final int revision;
  final DateTime createdAt, updatedAt;
  Garden copyWith({
    String? name,
    String? notes,
    Iterable<GardenArea>? areas,
    Iterable<GardenSeason>? seasons,
    int? revision,
    DateTime? updatedAt,
  }) => Garden(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    areas: areas ?? this.areas,
    seasons: seasons ?? this.seasons,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'version': 2,
    'id': id,
    'name': name,
    'notes': notes,
    'areas': areas.map((v) => v.toJson()).toList(),
    'seasons': seasons.map((v) => v.toJson()).toList(),
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory Garden.fromJson(Map<String, dynamic> json) {
    final extended = json.containsKey('version');
    if (extended && (json['version'] is! int || json['version'] != 2)) {
      throw const FormatException('Unsupported garden version');
    }
    _keys(json, {
      if (extended) ...['version', 'seasons'],
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
      seasons: extended
          ? (json['seasons'] as List).map(
              (v) => GardenSeason.fromJson(v as Map<String, dynamic>),
            )
          : const [],
      areas: (json['areas'] as List).map((v) {
        final payload = v as Map<String, dynamic>;
        if (extended !=
                (payload.containsKey('kind') &&
                    payload.containsKey('archived')) ||
            (!extended &&
                (payload.containsKey('kind') ||
                    payload.containsKey('archived')))) {
          throw const FormatException('Garden area version mismatch');
        }
        return GardenArea.fromJson(payload);
      }),
    );
    garden.validate();
    return garden;
  }
  void validate() {
    _id(id);
    _text(name, 200, required: true);
    _text(notes, 20000);
    if (revision < 0 ||
        updatedAt.isBefore(createdAt) ||
        areas.length > 1000 ||
        seasons.length > 500) {
      throw const FormatException('Invalid garden');
    }
    final ids = <String>{};
    for (final area in areas) {
      area.validate();
      if (!ids.add(area.id)) {
        throw const FormatException('Duplicate garden area');
      }
    }
    final years = <int>{}, plantingIds = <String>{};
    var plantingCount = 0;
    for (final season in seasons) {
      season.validate();
      if (!years.add(season.year)) {
        throw const FormatException('Duplicate garden season');
      }
      for (final planting in season.plantings) {
        if (!ids.contains(planting.areaId) ||
            !plantingIds.add(planting.id) ||
            ids.contains(planting.id) ||
            planting.id == id) {
          throw const FormatException('Invalid planting area or identity');
        }
        plantingCount++;
      }
    }
    if (plantingCount > 10000) {
      throw const FormatException('Too many garden plantings');
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
    for (final g in gardens)
      for (final s in g.seasons)
        for (final p in s.plantings) p.id,
  };
  Map<String, Object?> toJson() => {
    'version': 2,
    'revision': revision,
    'gardens': gardens.map((g) => g.toJson()).toList(),
  };
  factory GardenSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      _keys(json, {'version', 'revision', 'gardens'});
      if (json['version'] is! int || !const [1, 2].contains(json['version'])) {
        throw const FormatException();
      }
      final snapshot = GardenSnapshot(
        revision: json['revision'] as int,
        gardens: (json['gardens'] as List).map((v) {
          final payload = v as Map<String, dynamic>;
          if ((json['version'] == 1 && payload.containsKey('version')) ||
              (json['version'] == 2 && payload['version'] != 2)) {
            throw const FormatException('Garden snapshot version mismatch');
          }
          return Garden.fromJson(payload);
        }),
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
      for (final id in [
        garden.id,
        ...garden.areas.map((v) => v.id),
        for (final s in garden.seasons)
          for (final p in s.plantings) p.id,
      ]) {
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
