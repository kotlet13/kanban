import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/garden_rotation.dart';

String gardenFamilyLabel(BuildContext context, String family) =>
    switch (knownGardenFamily(family)) {
      'Solanaceae' => context.l10n.gardenFamilySolanaceae,
      'Fabaceae' => context.l10n.gardenFamilyFabaceae,
      'Brassicaceae' => context.l10n.gardenFamilyBrassicaceae,
      'Apiaceae' => context.l10n.gardenFamilyApiaceae,
      'Asteraceae' => context.l10n.gardenFamilyAsteraceae,
      'Cucurbitaceae' => context.l10n.gardenFamilyCucurbitaceae,
      'Amaryllidaceae' => context.l10n.gardenFamilyAmaryllidaceae,
      'Amaranthaceae' => context.l10n.gardenFamilyAmaranthaceae,
      'Poaceae' => context.l10n.gardenFamilyPoaceae,
      _ => family,
    };
