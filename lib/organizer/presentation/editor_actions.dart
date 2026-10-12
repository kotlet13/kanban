import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Shared CRUD controls stay in a single row, including narrow dialogs.
class EditorActionsRow extends StatelessWidget {
  const EditorActionsRow({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
    this.leadingAction,
    this.saveKey,
    this.busy = false,
    this.saveEnabled = true,
    this.cancelLabel,
  });
  final VoidCallback? onCancel, onSave, onDelete;
  final Widget? leadingAction;
  final Key? saveKey;
  final bool busy, saveEnabled;
  final String? cancelLabel;
  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('editor-actions-row'),
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (onDelete != null)
        IconButton(
          tooltip: context.l10n.delete,
          onPressed: busy ? null : onDelete,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      if (leadingAction != null)
        Flexible(child: leadingAction!)
      else
        const Spacer(),
      Flexible(
        child: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: busy ? null : onCancel,
          child: Text(
            cancelLabel ?? context.l10n.cancel,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(width: 8),
      EditorSaveButton(
        key: saveKey,
        onPressed: onSave,
        busy: busy,
        enabled: saveEnabled,
      ),
    ],
  );
}

class EditorSaveButton extends StatelessWidget {
  const EditorSaveButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.enabled = true,
  });
  final VoidCallback? onPressed;
  final bool busy, enabled;
  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: context.l10n.save,
    onPressed: busy || !enabled ? null : onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        : const Icon(Icons.save_outlined),
  );
}

class EditorHeading extends StatelessWidget {
  const EditorHeading({
    super.key,
    required this.title,
    this.style,
    this.onReport,
    this.busy = false,
  });
  final String title;
  final TextStyle? style;
  final VoidCallback? onReport;
  final bool busy;
  @override
  Widget build(BuildContext context) => onReport == null
      ? Text(title, style: style)
      : Row(
          key: const ValueKey('editor-heading-row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: style)),
            const SizedBox(width: 8),
            Flexible(
              child: TextButton(
                key: const ValueKey('editor-report'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: busy ? null : onReport,
                child: Text(
                  context.l10n.moderationReportContent,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
        );
}
