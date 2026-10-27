import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../domain/collaboration_models.dart';

/// Transient discovery belongs to the captured invitation session. Selecting a
/// label fills its exact username; sending still uses explicit invitation flow.
class InvitationRecipientField extends StatefulWidget {
  const InvitationRecipientField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.validator,
    required this.isCurrent,
    required this.search,
    required this.onSelected,
  });
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String? Function(String?) validator;
  final bool Function() isCurrent;
  final Future<List<InvitationRecipient>> Function(String) search;
  final void Function(InvitationRecipient?) onSelected;
  @override
  State<InvitationRecipientField> createState() =>
      _InvitationRecipientFieldState();
}

class _InvitationRecipientFieldState extends State<InvitationRecipientField> {
  Timer? _debounce;
  var _generation = 0;
  var _loading = false, _searched = false, _failed = false;
  String? _selectedUsername;
  List<InvitationRecipient> _results = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant InvitationRecipientField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
    if (!widget.enabled) {
      _debounce?.cancel();
      _generation++;
      _loading = false;
      _results = const [];
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final query = widget.controller.text.trim();
    if (query == _selectedUsername) return;
    _selectedUsername = null;
    widget.onSelected(null);
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _loading = _searched = _failed = false;
      _results = const [];
    });
    if (!widget.enabled ||
        !widget.isCurrent() ||
        query.runes.length < 2 ||
        query.runes.length > 64 ||
        query.contains('@')) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted ||
          generation != _generation ||
          !widget.enabled ||
          !widget.isCurrent()) {
        return;
      }
      setState(() => _loading = true);
      try {
        final results = await widget.search(query);
        if (!mounted ||
            generation != _generation ||
            !widget.enabled ||
            !widget.isCurrent() ||
            widget.controller.text.trim() != query) {
          return;
        }
        setState(() {
          _results = results;
          _searched = true;
          _loading = false;
        });
      } catch (_) {
        if (!mounted ||
            generation != _generation ||
            !widget.enabled ||
            !widget.isCurrent()) {
          return;
        }
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    });
  }

  void _select(InvitationRecipient recipient) {
    if (!widget.enabled || !widget.isCurrent()) return;
    _debounce?.cancel();
    _generation++;
    _selectedUsername = recipient.username;
    widget.onSelected(recipient);
    widget.controller.value = TextEditingValue(
      text: recipient.username,
      selection: TextSelection.collapsed(offset: recipient.username.length),
    );
    setState(() {
      _results = const [];
      _loading = _searched = _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('sharing-recipient'),
          controller: widget.controller,
          enabled: widget.enabled,
          validator: widget.validator,
          autocorrect: false,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: l.sharingRecipientSearchHint,
            helperMaxLines: 3,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_failed || _searched && _results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _failed
                  ? l.sharingRecipientSearchFailed
                  : l.sharingRecipientSearchEmpty,
            ),
          ),
        for (final result in _results)
          ListTile(
            key: ValueKey('recipient-${result.accountId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              result.displayName.isEmpty ? result.username : result.displayName,
            ),
            subtitle: result.displayName.isEmpty
                ? null
                : Text('@${result.username}'),
            onTap: widget.enabled ? () => _select(result) : null,
          ),
      ],
    );
  }
}
