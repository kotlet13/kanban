import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';

Future<String?> showCryptoPublicCardDialog(
  BuildContext context, {
  String? explanation,
}) => showDialog<String>(
  context: context,
  builder: (_) => _CryptoPublicCardDialog(explanation: explanation),
);

class _CryptoPublicCardDialog extends StatefulWidget {
  const _CryptoPublicCardDialog({this.explanation});

  final String? explanation;

  @override
  State<_CryptoPublicCardDialog> createState() => _CryptoPublicCardDialogState();
}

class _CryptoPublicCardDialogState extends State<_CryptoPublicCardDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.cryptoCompareContact),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.explanation ?? context.l10n.cryptoVerifyContactExplanation),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 6,
            autocorrect: false,
            enableSuggestions: false,
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: context.l10n.cryptoPastePublicCard,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text),
        child: Text(context.l10n.cryptoCompareContact),
      ),
    ],
  );
}
