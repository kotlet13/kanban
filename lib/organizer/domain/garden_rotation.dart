import 'garden_models.dart';

/// These are recognized labels for comparison, not a crop-to-family inference.
/// A missing or unrecognized label provides no rotation assessment.
const gardenKnownFamilies = [
  'Solanaceae',
  'Fabaceae',
  'Brassicaceae',
  'Apiaceae',
  'Asteraceae',
  'Cucurbitaceae',
  'Amaryllidaceae',
  'Amaranthaceae',
  'Poaceae',
];

String? knownGardenFamily(String family) {
  final normalized = family.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  const aliases = {
    'solanaceae': 'Solanaceae',
    'razhudnikovke': 'Solanaceae',
    'nightshades': 'Solanaceae',
    'fabaceae': 'Fabaceae',
    'metuljnice': 'Fabaceae',
    'stročnice': 'Fabaceae',
    'legumes': 'Fabaceae',
    'brassicaceae': 'Brassicaceae',
    'križnice': 'Brassicaceae',
    'brassicas': 'Brassicaceae',
    'apiaceae': 'Apiaceae',
    'kobulnice': 'Apiaceae',
    'umbellifers': 'Apiaceae',
    'asteraceae': 'Asteraceae',
    'nebinovke': 'Asteraceae',
    'composites': 'Asteraceae',
    'cucurbitaceae': 'Cucurbitaceae',
    'bučnice': 'Cucurbitaceae',
    'bučevke': 'Cucurbitaceae',
    'bučovke': 'Cucurbitaceae',
    'cucurbits': 'Cucurbitaceae',
    'amaryllidaceae': 'Amaryllidaceae',
    'lukovke': 'Amaryllidaceae',
    'narcisovke': 'Amaryllidaceae',
    'alliums': 'Amaryllidaceae',
    'amaranthaceae': 'Amaranthaceae',
    'ščirovke': 'Amaranthaceae',
    'amaranths': 'Amaranthaceae',
    'poaceae': 'Poaceae',
    'trave': 'Poaceae',
    'grasses': 'Poaceae',
  };
  return aliases[normalized];
}

class GardenAreaSeasonHistory {
  GardenAreaSeasonHistory({
    required this.year,
    required Iterable<GardenPlanting> plantings,
  }) : plantings = List.unmodifiable(plantings);
  final int year;
  final List<GardenPlanting> plantings;
}

/// Only recorded seasons with entries for this permanent area, newest first.
List<GardenAreaSeasonHistory> gardenAreaHistory(Garden garden, String areaId) {
  final result = [
    for (final season in garden.seasons)
      if (season.plantings.any((p) => p.areaId == areaId))
        GardenAreaSeasonHistory(
          year: season.year,
          plantings: season.plantingsForArea(areaId),
        ),
  ]..sort((a, b) => b.year.compareTo(a.year));
  return List.unmodifiable(result);
}

class GardenRotationWarning {
  GardenRotationWarning({
    required this.plantingId,
    required this.areaId,
    required this.family,
    required Iterable<int> previousYears,
  }) : previousYears = List.unmodifiable(previousYears);
  final String plantingId, areaId, family;
  final List<int> previousYears;
}

/// Informational comparison of known, user-entered families on the same area.
/// Previous plans do not prove an actual planting. Empty output never means
/// that rotation is safe, complete, or suitable for any particular crop.
List<GardenRotationWarning> gardenRotationWarnings(
  Garden garden,
  int year, {
  int lookbackYears = 3,
}) {
  if (lookbackYears < 1 || lookbackYears > 100) {
    throw ArgumentError.value(lookbackYears, 'lookbackYears');
  }
  final season = garden.seasonForYear(year);
  if (season == null) return const [];
  final result = <GardenRotationWarning>[];
  for (final planting in season.plantings) {
    final family = knownGardenFamily(planting.family);
    if (family == null) continue;
    final previousYears = {
      for (final previous in garden.seasons)
        if (previous.year < year &&
            previous.year >= year - lookbackYears &&
            previous.plantings.any(
              (p) =>
                  p.areaId == planting.areaId &&
                  p.status == GardenPlantingStatus.actual &&
                  knownGardenFamily(p.family) == family,
            ))
          previous.year,
    }.toList()..sort((a, b) => b.compareTo(a));
    if (previousYears.isNotEmpty) {
      result.add(
        GardenRotationWarning(
          plantingId: planting.id,
          areaId: planting.areaId,
          family: family,
          previousYears: previousYears,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}
