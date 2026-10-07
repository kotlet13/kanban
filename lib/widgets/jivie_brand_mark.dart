import 'package:flutter/widgets.dart';

/// Decorative app mark; the adjacent localized app name supplies its label.
class JivieBrandMark extends StatelessWidget {
  const JivieBrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      'assets/branding/jivie/icon-master.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}
