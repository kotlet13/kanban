import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';

/// Presentation formatting only. Never converts to floating point or combines
/// currencies; the domain ledger supplies integer totals.
String sharedMoneyLabel(BuildContext context, BigInt value, String currency) {
  if (!supportedCurrencies.contains(currency)) {
    return '${value.toString()} ${context.l10n.financeMinorUnits} $currency';
  }
  final amount = value.abs();
  final hundred = BigInt.from(100);
  return '${value.isNegative ? '−' : ''}${amount ~/ hundred}.${(amount % hundred).toString().padLeft(2, '0')} $currency';
}
