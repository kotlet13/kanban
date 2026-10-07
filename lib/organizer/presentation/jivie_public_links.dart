import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/l10n.dart';

enum JiviePublicPage { privacy, help, deleteAccount }

Uri jiviePublicUri(String language, JiviePublicPage page) => Uri.https(
  'jivie.app',
  '${language == 'en' ? '/en' : ''}/${switch (page) {
    JiviePublicPage.privacy => 'privacy',
    JiviePublicPage.help => 'help',
    JiviePublicPage.deleteAccount => 'delete-account',
  }}/',
);

class JiviePublicLinks extends StatelessWidget {
  const JiviePublicLinks({super.key});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final page in JiviePublicPage.values)
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(switch (page) {
              JiviePublicPage.privacy => l.jiviePrivacyLink,
              JiviePublicPage.help => l.jivieHelpLink,
              JiviePublicPage.deleteAccount => l.jivieDeletionLink,
            }),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final launched = await launchUrl(
                  jiviePublicUri(
                    Localizations.localeOf(context).languageCode,
                    page,
                  ),
                  mode: LaunchMode.externalApplication,
                );
                if (!launched && messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.jivieLinkFailed)),
                  );
                }
              } catch (_) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.jivieLinkFailed)),
                  );
                }
              }
            },
          ),
      ],
    );
  }
}
