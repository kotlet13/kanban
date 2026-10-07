import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../l10n/l10n.dart';
import 'first_time_guide.dart';

enum SetupIntent { deviceOnly, privateDevices, household }

final gettingStartedSeenProvider =
    AsyncNotifierProvider<GettingStartedSeenController, bool>(
      GettingStartedSeenController.new,
    );

class GettingStartedSeenController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(
        'organizer_getting_started_seen_v1',
      ) ??
      false;
  Future<void> acknowledge() async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      'organizer_getting_started_seen_v1',
      true,
    )) {
      throw StateError('Setup preference save failed');
    }
    state = const AsyncData(true);
  }
}

Future<SetupIntent?> showGettingStarted(BuildContext context) =>
    showDialog<SetupIntent>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.setupTitle),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(child: GettingStartedChoices()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );

class GettingStartedChoices extends StatelessWidget {
  const GettingStartedChoices({super.key});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.setupIntro),
        const SizedBox(height: 16),
        for (final option in [
          (
            SetupIntent.deviceOnly,
            Icons.phone_iphone,
            l.setupDeviceOnly,
            l.setupDeviceOnlyDescription,
          ),
          (
            SetupIntent.privateDevices,
            Icons.devices_outlined,
            l.setupPrivateDevices,
            l.setupPrivateDevicesDescription,
          ),
          (
            SetupIntent.household,
            Icons.home_outlined,
            l.setupHousehold,
            l.setupHouseholdDescription,
          ),
        ])
          ListTile(
            key: ValueKey('setup-${option.$1.name}'),
            leading: Icon(option.$2),
            title: Text(option.$3),
            subtitle: Text(option.$4),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, option.$1),
          ),
      ],
    );
  }
}

class GettingStartedHint extends ConsumerWidget {
  const GettingStartedHint({super.key, required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(gettingStartedSeenProvider);
    final guideSeen = ref.watch(firstTimeGuideSeenProvider);
    if (seen.valueOrNull != false && guideSeen.valueOrNull != false) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.setupTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l.setupHint),
              if (guideSeen.valueOrNull == false)
                TextButton.icon(
                  onPressed: () => showFirstTimeGuide(context, ref),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(l.guideOpen),
                ),
              if (seen.valueOrNull == false)
                TextButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l.setupChoose),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
