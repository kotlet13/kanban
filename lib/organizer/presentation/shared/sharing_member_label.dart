import 'package:flutter/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';

String sharingMemberLabel(BuildContext context, SharedMember member) =>
    member.labelUnavailable
    ? context.l10n.sharingMemberNameUnavailable(member.accountId)
    : member.displayName.isEmpty
    ? member.username
    : member.displayName;
