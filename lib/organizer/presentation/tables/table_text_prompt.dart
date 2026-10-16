import 'dart:convert';
import 'package:flutter/material.dart';
import 'tables_strings.dart';

Future<String?> tableTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  int maxBytes = 200,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TableTextPrompt(
    title: title,
    label: label,
    initial: initial,
    maxBytes: maxBytes,
  ),
);

class _TableTextPrompt extends StatefulWidget {
  const _TableTextPrompt({
    required this.title,
    required this.label,
    required this.initial,
    required this.maxBytes,
  });
  final String title, label, initial;
  final int maxBytes;
  @override
  State<_TableTextPrompt> createState() => _TableTextPromptState();
}

class _TableTextPromptState extends State<_TableTextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = TablesStrings.of(context);
    final valid =
        _controller.text.trim().isNotEmpty &&
        utf8.encode(_controller.text.trim()).length <= widget.maxBytes;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxBytes,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (valid) Navigator.pop(context, _controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: valid
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: Text(s.apply),
        ),
      ],
    );
  }
}
