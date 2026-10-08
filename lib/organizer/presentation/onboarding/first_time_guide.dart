import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/l10n.dart';

final firstTimeGuideSeenProvider =
    AsyncNotifierProvider<FirstTimeGuideSeenController, bool>(
      FirstTimeGuideSeenController.new,
    );

class FirstTimeGuideSeenController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool('jivie_guide_seen_v1') ??
      false;

  Future<void> acknowledge() async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      'jivie_guide_seen_v1',
      true,
    )) {
      throw StateError('Guide preference save failed');
    }
    state = const AsyncData(true);
  }
}

Future<void> showFirstTimeGuide(BuildContext context, WidgetRef ref) async {
  // Capture the controller while the caller is mounted; closing the dialog does
  // not opt in to a service, modify records or request a platform permission.
  final controller = ref.read(firstTimeGuideSeenProvider.notifier);
  final viewed = await showDialog<bool>(
    context: context,
    builder: (_) => const FirstTimeGuide(),
  );
  if (viewed == true) {
    try {
      await controller.acknowledge();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.organizerSaveError)),
        );
      }
    }
  }
}

class FirstTimeGuide extends StatefulWidget {
  const FirstTimeGuide({super.key});
  @override
  State<FirstTimeGuide> createState() => _FirstTimeGuideState();
}

class _FirstTimeGuideState extends State<FirstTimeGuide> {
  int _step = 0;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pages = [
      (Icons.phone_iphone, l.guideLocalTitle, l.guideLocalBody),
      (Icons.today_outlined, l.organizerToday, l.guideTodayBody),
      (Icons.event_note_outlined, l.organizerPlans, l.guidePlansBody),
      (Icons.shopping_bag_outlined, l.organizerShopping, l.guideShoppingBody),
      (Icons.menu, l.guideMenuTitle, l.guideMoreBody),
    ];
    final page = pages[_step];
    return AlertDialog(
      title: Text(l.guideTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.guideProgress(_step + 1, pages.length)),
              const SizedBox(height: 20),
              Icon(
                page.$1,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(page.$2, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(page.$3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('guide-skip'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.guideSkip),
        ),
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step--),
            child: Text(l.guideBack),
          ),
        FilledButton(
          key: const ValueKey('guide-next'),
          onPressed: () => _step == pages.length - 1
              ? Navigator.pop(context, true)
              : setState(() => _step++),
          child: Text(_step == pages.length - 1 ? l.guideDone : l.guideNext),
        ),
      ],
    );
  }
}
