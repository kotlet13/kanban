import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../data/organizer_repository.dart';

String organizerErrorMessage(BuildContext context, Object error) {
  if (error is OrganizerConflictException) {
    return context.l10n.organizerConflict;
  }
  if (error is FormatException) return context.l10n.organizerInvalidData;
  return context.l10n.organizerSaveError;
}
