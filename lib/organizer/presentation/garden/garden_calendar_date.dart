import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Garden dates are calendar days; formatting must not convert UTC to local.
String gardenCalendarDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(value);
