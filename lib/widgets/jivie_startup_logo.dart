import 'package:flutter/material.dart';

import 'jivie_brand_mark.dart';

/// Neutral local startup, before the saved workspace can be read safely.
class JivieStartupLogo extends StatelessWidget {
  const JivieStartupLogo({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Semantics(
          label: 'Jivie',
          image: true,
          child: const JivieBrandMark(size: 96),
        ),
      ),
    ),
  );
}
