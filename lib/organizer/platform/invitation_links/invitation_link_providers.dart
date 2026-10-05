import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'invitation_link.dart';

abstract interface class InvitationLinkSource {
  Future<Uri?> initialLink();
  Stream<Uri> get links;
}

class AppInvitationLinkSource implements InvitationLinkSource {
  final _app = AppLinks();
  @override
  Future<Uri?> initialLink() => _app.getInitialLink();
  @override
  Stream<Uri> get links => _app.uriLinkStream;
}

final invitationLinkSourceProvider = Provider<InvitationLinkSource?>(
  (ref) => kIsWeb ? null : AppInvitationLinkSource(),
);
final pendingInvitationLinkProvider = StateProvider<InvitationLink?>(
  (ref) => null,
);
final invitationLinkErrorProvider = StateProvider<bool>((ref) => false);

// Link secrets remain in memory and never become router URLs or preferences.
class InvitationLinkReceiver {
  InvitationLinkReceiver({required this.onLink, required this.onInvalid});
  final void Function(InvitationLink) onLink;
  final void Function() onInvalid;
  Uri? _first;
  void receiveInitial(Uri uri) {
    if (uri == _first) return;
    receive(uri);
  }

  void receive(Uri uri) {
    _first ??= uri;
    final parsed = InvitationLink.tryParse(uri);
    if (parsed == null) {
      onInvalid();
      return;
    }
    onLink(parsed);
  }
}
