import '../platform/private_file_io.dart';
import '../data/organizer_storage.dart' show OrganizerBackupCodec;
import 'dart:typed_data';
import 'backup/backup_file_io.dart' show readBoundedBackup;
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../widgets/jivie_brand_mark.dart';
import '../state/app_preferences_provider.dart';
import 'organizer_actions.dart';
import 'jivie_public_links.dart';
import 'onboarding/first_time_guide.dart';
import 'onboarding/account_deletion_panel.dart';
import 'backup/backup_wizard.dart';
import 'backup/personal_json_export.dart';
import 'backup/backup_recovery.dart';
import 'shared/unsent_work_recovery_view.dart';
import '../platform/backup_preferences_replay.dart';
import 'organizer_widgets.dart';
import 'inbox/inbox_preferences.dart';
import 'recovery/account_crypto_wizard.dart';
import 'recovery/crypto_approvals_page.dart';
import 'recovery/preserved_installation_files_page.dart';

class OrganizerSettingsPage extends ConsumerWidget {
  const OrganizerSettingsPage({super.key, required this.actions});
  final OrganizerActions actions;

  Future<void> _import(BuildContext context) async {
    await actions.run(() async {
      Uint8List bytes;
      if (usesPrivateMobileFileIo) {
        final picked = await pickPrivateFile(
          extensions: ['json'],
          maxBytes: OrganizerBackupCodec.maxBytes,
        );
        if (picked == null || !context.mounted) return;
        bytes = picked.bytes;
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: false,
          withReadStream: true,
        );
        if (picked == null || !context.mounted) return;
        bytes = await readBoundedBackup(
          picked.files.single,
          maxBytes: OrganizerBackupCodec.maxBytes,
        );
      }
      if (!context.mounted) return;
      final json = utf8.decode(bytes);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.organizerImport),
          content: Text(context.l10n.organizerRestoreWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.organizerRestoreConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await actions.controller.importBackup(json);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.organizerRestored)));
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = ref.watch(themeModeProvider);
    final locale = ref.watch(appLocaleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.explore_outlined),
          title: Text(l.guideOpen),
          onTap: () => showFirstTimeGuide(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(l.reminderSettingsTitle),
          onTap: () => showInboxPreferences(context, ref),
        ),
        const SizedBox(height: 24),
        OrganizerHeading(
          title: l.organizerSettings,
          subtitle: l.organizerLocalDescription,
        ),
        if (ref.watch(backupPreferencesReplayProvider).hasError)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.backupSettingsRetry),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(backupPreferencesReplayProvider),
                    child: Text(l.organizerRetry),
                  ),
                ],
              ),
            ),
          ),
        OrganizerSection(
          title: l.themeMode,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ThemeMode.values)
                ChoiceChip(
                  selected: theme == mode,
                  label: Text(switch (mode) {
                    ThemeMode.system => l.systemTheme,
                    ThemeMode.light => l.lightTheme,
                    ThemeMode.dark => l.darkTheme,
                  }),
                  onSelected: (_) {
                    ref.read(themeModeProvider.notifier).state = mode;
                    actions.run(
                      () => ref.read(themeModeStoreProvider).save(mode),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        OrganizerSection(
          title: l.appLanguage,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in ['', 'sl', 'en'])
                ChoiceChip(
                  selected: (locale?.languageCode ?? '') == code,
                  label: Text(
                    code.isEmpty
                        ? l.organizerSystemLanguage
                        : code == 'sl'
                        ? 'Slovenščina'
                        : 'English',
                  ),
                  onSelected: (_) {
                    final next = code.isEmpty ? null : Locale(code);
                    ref.read(appLocaleProvider.notifier).state = next;
                    actions.run(() => ref.read(localeStoreProvider).save(next));
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        OrganizerSection(
          title: l.organizerBackup,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.backupDescription),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            showBackupWizard(context, restore: false),
                        icon: const Icon(Icons.lock_outline),
                        label: Text(l.backupCreate),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            showBackupWizard(context, restore: true),
                        icon: const Icon(Icons.restore),
                        label: Text(l.backupRestore),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ExpansionTile(
                    title: Text(l.backupLegacyJson),
                    subtitle: Text(l.organizerBackupDescription),
                    children: [
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                exportPersonalJsonForLocalRestore(context, ref),
                            icon: const Icon(
                              Icons.file_download_outlined,
                              size: 18,
                            ),
                            label: Text(l.organizerExport),
                          ),
                          TextButton.icon(
                            onPressed: () => _import(context),
                            icon: const Icon(
                              Icons.file_upload_outlined,
                              size: 18,
                            ),
                            label: Text(l.organizerImport),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(l.preservedFilesTitle),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PreservedInstallationFilesPage(),
            ),
          ),
        ),
        const BackupRecoveryPanel(),
        const UnsentWorkRecoveryButton(),
        const AccountCryptoPanel(),
        ListTile(
          leading: const Icon(Icons.approval_outlined),
          title: Text(
            Localizations.localeOf(context).languageCode == 'sl'
                ? 'Čakajoče odobritve'
                : 'Pending approvals',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CryptoApprovalsPage(),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const AccountDeletionPanel(),
        const SizedBox(height: 28),
        const JiviePublicLinks(),
        const SizedBox(height: 16),
        AboutListTile(
          icon: const Icon(Icons.info_outline),
          applicationName: l.organizerAppName,
          applicationIcon: const JivieBrandMark(size: 48),
          aboutBoxChildren: [Text(l.jivieDescription)],
          child: Text(l.jivieAbout),
        ),
      ],
    );
  }
}
