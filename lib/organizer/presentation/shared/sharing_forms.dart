import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/l10n.dart';
import '../planning/date_time_field.dart';

/// Presentation-only field descriptions. Validation of account and record
/// permissions remains in the collaboration controller.
class SharingField {
  const SharingField({
    required this.id,
    required this.label,
    this.initialValue = '',
    this.obscure = false,
    this.sensitive = false,
    this.readOnly = false,
    this.required = true,
    this.keyboardType,
    this.options,
    this.validator,
    this.dateTime = false,
    this.maxLines = 1,
  });
  final String id;
  final String label;
  final String initialValue;
  final bool obscure;
  final bool sensitive;
  final bool readOnly;
  final bool required;
  final TextInputType? keyboardType;
  final Map<String, String>? options;
  final String? Function(String, Map<String, String>)? validator;
  final bool dateTime;
  final int maxLines;
}

Future<void> showSharingForm(
  BuildContext context, {
  required String title,
  String? description,
  required List<SharingField> fields,
  required String submitLabel,
  required Future<void> Function(Map<String, String>) onSubmit,
  required String Function(Object) errorMessage,
  Widget Function(Widget)? wrap,
  Future<void> Function()? onDelete,
  String? deleteDescription,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final form = _SharingFormDialog(
      title: title,
      description: description,
      fields: fields,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      errorMessage: errorMessage,
      wrap: wrap,
      onDelete: onDelete,
      deleteDescription: deleteDescription,
    );
    return wrap?.call(form) ?? form;
  },
);

class _SharingFormDialog extends StatefulWidget {
  const _SharingFormDialog({
    required this.title,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
    required this.errorMessage,
    this.description,
    this.wrap,
    this.onDelete,
    this.deleteDescription,
  });
  final String title;
  final String? description;
  final List<SharingField> fields;
  final String submitLabel;
  final Future<void> Function(Map<String, String>) onSubmit;
  final String Function(Object) errorMessage;
  final Widget Function(Widget)? wrap;
  final Future<void> Function()? onDelete;
  final String? deleteDescription;
  @override
  State<_SharingFormDialog> createState() => _SharingFormDialogState();
}

class _SharingFormDialogState extends State<_SharingFormDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      field.id: TextEditingController(text: field.initialValue),
  };
  bool _busy = false;
  String? _error;
  Map<String, String> get _values => {
    for (final entry in _controllers.entries) entry.key: entry.value.text,
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !invalid.first.mounted) return;
        final fieldContext = invalid.first.context;
        final object = fieldContext.findRenderObject()!;
        final position = Scrollable.of(fieldContext).position;
        final offset = RenderAbstractViewport.of(
          object,
        ).getOffsetToReveal(object, 0).offset;
        position.animateTo(
          (offset - MediaQuery.textScalerOf(context).scale(16)).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_values);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.errorMessage(error);
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) return;
    final confirmed = await confirmSharingAction(
      context,
      title: context.l10n.organizerDeleteConfirm,
      description:
          widget.deleteDescription ?? context.l10n.organizerDeleteConfirm,
      confirmLabel: context.l10n.delete,
      wrap: widget.wrap,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        titlePadding: compact ? const EdgeInsets.fromLTRB(16, 16, 16, 8) : null,
        contentPadding: compact
            ? const EdgeInsets.fromLTRB(16, 8, 16, 12)
            : null,
        actionsPadding: compact
            ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
            : null,
        title: Text(
          widget.title,
          style: compact
              ? Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)
              : null,
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            key: const ValueKey('sharing-form-scroll'),
            padding: EdgeInsets.only(
              top: MediaQuery.textScalerOf(context).scale(12),
              bottom: 4,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.description != null) ...[
                    Text(widget.description!),
                    SizedBox(height: compact ? 12 : 20),
                  ],
                  for (final field in widget.fields)
                    Padding(
                      padding: EdgeInsets.only(bottom: compact ? 12 : 16),
                      child: field.dateTime
                          ? FormField<String>(
                              key: ValueKey('sharing-${field.id}'),
                              initialValue: field.initialValue,
                              validator: (value) =>
                                  field.required &&
                                      (value == null || value.isEmpty)
                                  ? context.l10n.sharingRequired
                                  : field.validator?.call(value ?? '', _values),
                              builder: (state) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OrganizerDateTimeField(
                                    label: field.label,
                                    value: DateTime.tryParse(
                                      _controllers[field.id]!.text,
                                    ),
                                    enabled: !_busy && !field.readOnly,
                                    wrap: widget.wrap,
                                    onChanged: (date) {
                                      final value =
                                          date?.toUtc().toIso8601String() ?? '';
                                      _controllers[field.id]!.text = value;
                                      state.didChange(value);
                                      setState(() {});
                                    },
                                  ),
                                  if (state.hasError)
                                    Text(
                                      state.errorText!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : field.options != null
                          ? DropdownButtonFormField<String>(
                              key: ValueKey('sharing-${field.id}'),
                              initialValue:
                                  field.options!.containsKey(field.initialValue)
                                  ? field.initialValue
                                  : null,
                              validator: (value) =>
                                  field.required && value == null
                                  ? context.l10n.sharingRequired
                                  : field.validator?.call(value ?? '', _values),
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              items: [
                                for (final option in field.options!.entries)
                                  DropdownMenuItem(
                                    value: option.key,
                                    child: Text(
                                      option.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _busy || field.readOnly
                                  ? null
                                  : (value) =>
                                        _controllers[field.id]!.text = value!,
                            )
                          : TextFormField(
                              key: ValueKey('sharing-${field.id}'),
                              controller: _controllers[field.id],
                              obscureText: field.obscure,
                              minLines: field.obscure || field.maxLines == 1
                                  ? 1
                                  : compact
                                  ? 2
                                  : field.maxLines,
                              maxLines: field.obscure ? 1 : field.maxLines,
                              style: compact
                                  ? Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(fontSize: 15)
                                  : null,
                              textInputAction: field.maxLines > 1
                                  ? TextInputAction.newline
                                  : field == widget.fields.last
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              enableSuggestions:
                                  !field.obscure && !field.sensitive,
                              enableIMEPersonalizedLearning:
                                  !field.obscure && !field.sensitive,
                              autocorrect: false,
                              readOnly: field.readOnly,
                              enabled: !_busy,
                              keyboardType: field.keyboardType,
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              validator: (value) {
                                if (field.required &&
                                    (value == null || value.trim().isEmpty)) {
                                  return context.l10n.sharingRequired;
                                }
                                return field.validator?.call(
                                  value ?? '',
                                  _values,
                                );
                              },
                            ),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('sharing-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmSharingAction(
  BuildContext context, {
  required String title,
  required String description,
  required String confirmLabel,
  Widget Function(Widget)? wrap,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final dialog = AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
        return wrap?.call(dialog) ?? dialog;
      },
    ) ==
    true;
