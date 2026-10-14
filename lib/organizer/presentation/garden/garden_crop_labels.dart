import 'package:flutter/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_models.dart';

String gardenCropLabel(BuildContext context, GardenCropIllustration kind) =>
    switch (kind) {
      GardenCropIllustration.generic => context.l10n.gardenCropGeneric,
      GardenCropIllustration.carrot => context.l10n.gardenCropCarrot,
      GardenCropIllustration.tomato => context.l10n.gardenCropTomato,
      GardenCropIllustration.lettuce => context.l10n.gardenCropLettuce,
      GardenCropIllustration.cabbage => context.l10n.gardenCropCabbage,
      GardenCropIllustration.onion => context.l10n.gardenCropOnion,
      GardenCropIllustration.pepper => context.l10n.gardenCropPepper,
      GardenCropIllustration.pumpkin => context.l10n.gardenCropPumpkin,
      GardenCropIllustration.bean => context.l10n.gardenCropBean,
    };
