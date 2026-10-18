import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/device_session_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_manager.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'package:sodium/sodium.dart';

class _MemorySecure implements AccountCryptoStore {
  final rows = <String, String>{};
  @override
  Future<String?> read(String partition) async => rows[partition];
  @override
  Future<void> write(String partition, String value) async {
    rows[partition] = value;
  }
}

DeviceSession _session(String url, Map<String, dynamic> wire) {
  final user = wire['user'] as Map, device = wire['device'] as Map;
  return DeviceSession(
    AccountSession(
      serverUrl: url,
      serverId: wire['serverId'],
      accountId: user['accountId'],
      userId: user['id'],
      username: user['username'],
      displayName: user['displayName'],
      deviceId: device['id'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        device['expiresAt'] * 1000,
      ),
      allowLocalHttp: true,
    ),
    wire['token'],
  );
}

void main() {
  final path = Platform.environment['JIVIE_CRYPTO2_FINANCE_HTTP_FIXTURE'];
  test(
    'real owner without finance never receives keys, authorized reader finishes queued contribution',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final fixture = jsonDecode(await File(path!).readAsString()) as Map;
      final url = fixture['serverUrl'] as String;
      if (fixture['synthetic'] != true || Uri.parse(url).host != '127.0.0.1')
        throw StateError('Synthetic loopback required');
      final crypto = CryptoCodec(await SodiumInit.init()),
          http = HttpCollaborationTransport();
      final ownerDb = CollaborationDatabase(NativeDatabase.memory()),
          memberDb = CollaborationDatabase(NativeDatabase.memory());
      final ownerSession = _session(
        url,
        fixture['accounts']['financeOwner']['session'],
      );
      final memberSession = _session(
        url,
        fixture['accounts']['financeMember']['session'],
      );
      AccountCryptoV2Workflow make(
        DeviceSession session,
        CollaborationDatabase db,
      ) => AccountCryptoV2Workflow(
        AccountDirectoryRepository(
          reducer: AccountDirectoryV2(crypto),
          session: session,
          transport: http,
          store: CryptoIdentityStore(
            db,
            _MemorySecure(),
            session.profile.partition,
          ),
          isCurrent: () => true,
        ),
      );
      final owner = make(ownerSession, ownerDb),
          member = make(memberSession, memberDb);
      try {
        final ownerFile = await owner.prepareRecoveryFile(),
            memberFile = await member.prepareRecoveryFile();
        try {
          await owner.verifyAndInitialize(ownerFile);
          await member.verifyAndInitialize(memberFile);
        } finally {
          ownerFile.fillRange(0, ownerFile.length, 0);
          memberFile.fillRange(0, memberFile.length, 0);
        }
        final ownerDir = await owner.directory.requireFresh(),
            memberDir = await member.directory.requireFresh();
        final oa = SessionCryptoAccess(account: owner),
            ma = SessionCryptoAccess(account: member);
        // Synthetic explicit exchange uses the peer's independently held own state,
        // never a server lookup or automatically accepted first-contact root.
        final scopeId = fixture['financeScope']['id'] as String;
        final memberCard = await ma.identities.publicCard(memberDir),
            ownerCard = await oa.identities.publicCard(ownerDir);
        final substituted = jsonDecode(memberCard) as Map<String, dynamic>;
        substituted['safetyCode'] = '0' * 64;
        await expectLater(
          oa.verifyContactCard(
            scopeId,
            memberDir.accountId,
            jsonEncode(substituted),
          ),
          throwsA(isA<CryptoDirectoryException>()),
        );
        await oa.verifyContactCard(scopeId, memberDir.accountId, memberCard);
        await ma.verifyContactCard(scopeId, ownerDir.accountId, ownerCard);
        final catalog = await owner.directory.call('crypto2.scopes.catalog');
        final metadata =
            (catalog['scopes'] as List).singleWhere((s) => s['id'] == scopeId)
                as Map;
        final manager = ScopeCryptoManager(oa),
            contributor = ScopeCryptoManager(ma);
        Future<dynamic> setup() => manager.initializeEmptyScope(
          scopeId: scopeId,
          accessRevision: metadata['accessRevision'],
          members: (metadata['members'] as List).cast<Map<String, dynamic>>(),
        );
        await expectLater(setup(), throwsA(isA<CryptoAuthorityPending>()));
        expect(
          await ownerDb.rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        final drafts = await contributor.financeDrafts(scopeId);
        expect(drafts.length, 1);
        final draftId = drafts.single['draftId'] as String;
        await contributor.contributeFinanceDraft(scopeId, draftId);
        await expectLater(setup(), throwsA(isA<CryptoAuthorityPending>()));
        expect(
          await ownerDb.rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        await contributor.publishFinanceGrants(scopeId, draftId);
        final active = await setup();
        expect(active.active, true);
        expect(
          await ownerDb.rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        await ma.currentHead(scopeId, online: true);
        await ma.hydrateScopeKeys(scopeId);
        final read = await ma.getScopeKey(scopeId, 'finance', 1);
        read.release();
        final review = await manager.reviewRotation(scopeId);
        await expectLater(
          manager.confirmRotation(review, acceptedCandidateHistory: true),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        final pending = await contributor.financeDrafts(scopeId);
        final nextDraft = pending.singleWhere((d) => d['draftId'] == review.id);
        final financeReview = await contributor.reviewRotation(
          scopeId,
          financeOnly: true,
        );
        await contributor.contributeFinanceDraft(
          scopeId,
          nextDraft['draftId'],
          reviewedInventory: financeReview,
        );
        await expectLater(
          manager.confirmRotation(review, acceptedCandidateHistory: true),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        await contributor.publishFinanceGrants(scopeId, nextDraft['draftId']);
        final rotated = await manager.confirmRotation(
          review,
          acceptedCandidateHistory: true,
        );
        expect(rotated.epoch, 2);
        expect(
          rotated.commitment('finance'),
          isNot(active.commitment('finance')),
        );
        expect(
          await ownerDb.rows(
            "SELECT * FROM crypto_scope_keys WHERE domain='finance'",
          ),
          isEmpty,
        );
        await ma.currentHead(scopeId, online: true);
        await ma.hydrateScopeKeys(scopeId);
        final oldFinance = await ma.getScopeKey(scopeId, 'finance', 1),
            newFinance = await ma.getScopeKey(scopeId, 'finance', 2);
        oldFinance.release();
        newFinance.release();

        await expectLater(
          ma.writeContext(scopeId, 'finance'),
          throwsA(isA<CryptoAuthorityPending>()),
        );
        await expectLater(
          oa.getScopeKey(scopeId, 'finance', 1),
          throwsA(isA<CryptoAuthorityPending>()),
        );
      } finally {
        await ownerDb.close();
        await memberDb.close();
        http.close();
      }
    },
    skip: path == null
        ? 'Dedicated two-party finance fixture not supplied'
        : false,
  );
}
