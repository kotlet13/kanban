import 'dart:math' as math;
import 'garden_models.dart';

/// Stable calendar arithmetic, independent of DST and the stored date's zone.
DateTime gardenDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// Decorative growth follows the entered dates and chosen timeline. Missing
/// dates and future/planned records remain seedlings; harvest is explicit.
double gardenVisualGrowth(GardenPlanting planting, DateTime today) {
  if (planting.harvested) return 0;
  final start = planting.plantAt ?? planting.sowAt;
  if (planting.status != GardenPlantingStatus.actual || start == null) {
    return .12;
  }
  final days = gardenDay(today).difference(gardenDay(start)).inDays;
  return (.12 + .88 * days / planting.visualGrowthDays).clamp(.12, 1.0);
}

GardenPlanting harvestGardenPlanting(GardenPlanting planting, DateTime day) {
  final harvested = planting.copyWith(
    status: GardenPlantingStatus.actual,
    harvested: true,
    harvestAt: gardenDay(day),
  );
  harvested.validate();
  return harvested;
}

/// Edge-to-edge distance in actual meters, including diagonal gaps. Intersecting
/// beds return zero; no assumptions are made for old unmeasured sketches.
double? gardenBedGapMeters(Garden garden, GardenArea a, GardenArea b) {
  if (!garden.hasPhysicalSize) return null;
  final dx = math.max(0.0, math.max(a.x - b.x - b.width, b.x - a.x - a.width));
  final dy = math.max(
    0.0,
    math.max(a.y - b.y - b.height, b.y - a.y - a.height),
  );
  return math.sqrt(
    math.pow(dx * garden.widthMeters!, 2) +
        math.pow(dy * garden.heightMeters!, 2),
  );
}

List<GardenPlanting> gardenVisiblePlantings(
  Garden garden,
  int? year,
  String areaId,
) =>
    garden
        .seasonForYear(year ?? 0)
        ?.plantingsForArea(areaId)
        .where((p) => !p.harvested)
        .toList() ??
    const [];
