import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

Color? inboxCardColor(BuildContext context, bool? read) {
  if (read != false) return null;
  final colors = Theme.of(context).colorScheme;
  return Color.alphaBlend(
    colors.primary.withValues(alpha: .06),
    colors.surfaceContainerLow,
  );
}

TextStyle inboxTitleStyle(BuildContext context, bool? read) => TextStyle(
  fontWeight: read == false ? FontWeight.w700 : FontWeight.w400,
  color: read == true
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : Theme.of(context).colorScheme.onSurface,
);

/// The envelope shows the current state; the tooltip describes the action.
class InboxReadStatusButton extends StatelessWidget {
  const InboxReadStatusButton({
    super.key,
    required this.read,
    required this.tooltip,
    required this.onPressed,
  });

  final bool? read;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        read == null
            ? Icons.more_horiz
            : read!
            ? Icons.mark_email_read_outlined
            : Icons.mark_email_unread_outlined,
        size: 22,
        color: read == false ? colors.primary : colors.onSurfaceVariant,
        semanticLabel: read == null
            ? null
            : read!
            ? context.l10n.inboxRead
            : context.l10n.inboxUnread,
      ),
    );
  }
}
