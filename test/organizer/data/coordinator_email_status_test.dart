import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import '../support/synthetic_content_route_guard.dart';
import 'collaboration_repository_test.dart'
    show FakeServer, FakeTransport, MemorySessionStore, code;

class _Server extends FakeServer {
  final emailCalls = <String>[];
  String? fail;
  @override
  Future<Map<String, dynamic>> call(
    String op,
    Map<String, Object?> params,
    String? token,
  ) async {
    if (op == 'account.email.confirm' || op == 'account.status') {
      emailCalls.add(op);
      if (fail == op) {
        throw const CollaborationApiException('account_token_invalid');
      }
      if (op == 'account.email.confirm') return {'confirmed': true};
      return {
        'email': 'verified@example.test',
        'pendingEmail': null,
        'emailVerified': true,
        'resetAvailable': true,
      };
    }
    return super.call(op, params, token);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  for (final failure in [null, 'account.email.confirm', 'account.status']) {
    test(
      'email confirmation returns one fresh status or error: $failure',
      () async {
        final server = _Server()..fail = failure;
        final repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase.memory()),
          FakeTransport(server),
          MemorySessionStore(),
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        addTearDown(repo.close);
        await repo.initialize();
        await repo.login(
          serverUrl: 'https://synthetic.invalid',
          username: 'alice',
          password: 'synthetic',
        );
        if (failure == null) {
          final status = await repo.confirmEmailVerification('synthetic-token');
          expect(status.email, 'verified@example.test');
          expect(status.emailVerified, isTrue);
          final cached = await repo.database.rows(
            'SELECT value FROM local_meta WHERE name=?',
            ['verified_email:${repo.state.session!.partition}'],
          );
          expect(cached.single['value'], 'true');
        } else {
          await expectLater(
            repo.confirmEmailVerification('synthetic-token'),
            throwsA(code('account_token_invalid')),
          );
        }
        expect(server.emailCalls, [
          'account.email.confirm',
          if (failure != 'account.email.confirm') 'account.status',
        ]);
      },
    );
  }
}
