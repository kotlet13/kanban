import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;
import 'email_invitation_repository_test.dart' show EmailServer;

class _PausedPreview extends EmailServer {
  String? pauseOperation;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, Object?> params,
    String? bearer,
  ) async {
    if (operation == pauseOperation) {
      pauseOperation = null;
      started.complete();
      await release.future;
    }
    return super.call(operation, params, bearer);
  }
}

void main() {
  for (final mode in [
    'capabilities',
    'invitations2.preview',
    'mismatched_checkpoint',
  ]) {
    test(
      'late preview preserves accepted checkpoint and deferral: $mode',
      () async {
        final server = _PausedPreview();
        server.scopeId = newSharedId();
        server.scopes[server.scopeId!] = {
          'id': server.scopeId,
          'kind': 'household',
          'name': 'Synthetic',
        };
        final store = MemoryPendingInvitationStore();
        final repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase.memory()),
          FakeTransport(server),
          MemorySessionStore(),
          invitationStore: store,
        );
        addTearDown(repo.close);
        await repo.initialize();
        const origin = 'https://synthetic.invalid/';
        await repo.rememberInvitation(serverUrl: origin, token: server.token);
        server.pauseOperation = mode == 'capabilities'
            ? mode
            : 'invitations2.preview';
        final preview = repo.previewEmailInvitation(
          serverUrl: origin,
          token: server.token,
        );
        // Register the failure listener before releasing the controlled response.
        final outcome = mode == 'mismatched_checkpoint'
            ? expectLater(
                preview,
                throwsA(
                  isA<CollaborationException>().having(
                    (e) => e.code,
                    'code',
                    'invitation_identity_mismatch',
                  ),
                ),
              )
            : null;
        await server.started.future;
        final checkpoint = PendingInvitation(
          serverUrl: origin,
          token: server.token,
          serverId: server.serverId,
          accountPartition: 'synthetic-accepted-account',
          invitationId: mode == 'mismatched_checkpoint'
              ? newSharedId()
              : server.invitationId,
          autoOpen: false,
        );
        // A newer local acceptance checkpoint arrives while preview is in flight.
        // This is a storage interleaving test, not a server acceptance test.
        await store.serialized(() => store.write(checkpoint));
        server.release.complete();
        if (outcome != null) {
          await outcome;
        } else {
          await preview;
        }
        expect(store.value!.accountPartition, checkpoint.accountPartition);
        expect(store.value!.invitationId, checkpoint.invitationId);
        expect(store.value!.serverId, checkpoint.serverId);
        expect(store.value!.autoOpen, false);
        expect(server.acceptCalls, 0);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
