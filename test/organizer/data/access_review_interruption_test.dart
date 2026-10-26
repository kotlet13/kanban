import 'dart:async';
import 'dart:convert';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'access_review_coordinator_test.dart' as fixture;

void main() {
  test(
    'account departure during access review cannot apply late result',
    () async {
      final f = await fixture.setup();
      await f.block(f.parent);
      final before = await f.repo.database.rows(
        'SELECT data,blocked FROM scopes ORDER BY id',
      );
      final entered = Completer<void>(), release = Completer<void>();
      f.transport.gate = () async {
        entered.complete();
        await release.future;
      };
      final check = f.repo.checkAllAccess();
      final failed = expectLater(check, throwsA(isA<CollaborationException>()));
      await entered.future;
      await f.repo.signOut();
      release.complete();
      await failed;
      expect(
        await f.repo.database.rows(
          'SELECT data,blocked FROM scopes ORDER BY id',
        ),
        before,
      );
      expect(f.repo.state.session, isNull);
    },
  );
  test(
    'restoring access preserves saved draft, exact queued payload and blocked operation',
    () async {
      final f = await fixture.setup();
      await f.block(f.parent);
      final id = newSharedId(), op = newSharedId();
      final payload = jsonEncode(
        LocalTask(
          id: id,
          title: 'Retained draft',
          notes: 'do not discard',
          projectId: null,
          dueAt: null,
          isCompleted: false,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ).toJson(),
      );
      final request = jsonEncode({
        'requestId': op,
        'type': 'task',
        'id': id,
        'payload': jsonDecode(payload),
      });
      await f.repo.database.execute(
        'INSERT INTO records(partition,scope_id,id,type,local_revision,server_revision,payload,deleted,remote) VALUES(?,?,?,?,?,?,?,?,?)',
        [f.p, f.parent, id, 'task', 1, 0, payload, 0, null],
      );
      await f.repo.database.execute(
        'INSERT INTO outbox(op_id,partition,scope_id,record_id,request,state) VALUES(?,?,?,?,?,?)',
        [op, f.p, f.parent, id, request, 'blocked'],
      );
      final before = await f.repo.database.rows('SELECT * FROM outbox');
      final r = await f.repo.checkAllAccess();
      expect(r.restored, 1);
      expect(await f.repo.database.rows('SELECT * FROM outbox'), before);
      expect(
        (await f.repo.database.rows('SELECT payload FROM records WHERE id=?', [
          id,
        ])).single['payload'],
        payload,
      );
      expect(
        f.repo.state.scopes.singleWhere((s) => s.id == f.parent).blocked,
        false,
      );
    },
  );
}
