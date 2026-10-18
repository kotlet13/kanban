import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_legacy_invitation_capsule.dart';

void main() {
  test(
    'Dart opens the exact independent PHP libsodium metadata vector',
    () async {
      final vector =
          jsonDecode(
                await File(
                  'test/organizer/data/e2ee/fixtures/legacy_invitation_capsule_v3.json',
                ).readAsString(),
              )
              as Map;
      expect(vector['synthetic'], true);
      final codec = CryptoLegacyInvitationCapsule(
        CryptoCodec(await SodiumInit.init()),
      );
      final envelope = Map<String, dynamic>.from(vector['envelope'] as Map);
      final value = await codec.openUntrustedMetadata(
        envelope: envelope,
        context: Map<String, dynamic>.from(envelope['context'] as Map),
        token: vector['token'],
      );
      expect(value, vector['metadata']);
    },
  );
  test(
    'legacy routing capsule opens with exact old token, fresh nonces, no public plaintext digest',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init()),
          codec = CryptoLegacyInvitationCapsule(
            CryptoCodec(await SodiumInit.init()),
          );
      final token = 'fhi3_${'a' * 64}',
          tokenHash = await cryptoSha256(utf8.encode('fhi3_${'a' * 64}'));
      final context = <String, dynamic>{
        'version': 3,
        'purpose': 'legacyInvitationBridge',
        'serverId': crypto.randomId(),
        'migrationId': crypto.randomId(),
        'captureId': crypto.randomId(),
        'sourceInventoryRoot': '1' * 64,
        'bridgeId': crypto.randomId(),
        'bindingId': crypto.randomId(),
        'sourceCommitment': '2' * 64,
        'scopeId': crypto.randomId(),
        'membershipHeadHash': '3' * 64,
      };
      final metadata = <String, dynamic>{
        'version': 3,
        'invitationId': crypto.randomId(),
        'scopeId': context['scopeId'],
        'recipient': {
          'kind': 'email',
          'value': 'PRIVATE_ROUTING_SENTINEL@example.invalid',
          'accountId': null,
        },
        'role': 'viewer',
        'expiresAtEpoch': 4102444800,
        'acceptedAtEpoch': null,
        'revokedAtEpoch': null,
        'legacyContractVersion': 3,
        'tokenHash': tokenHash,
      };
      final first = codec.sealMetadata(
        context: context,
        metadata: metadata,
        oldTokenHash: tokenHash,
      );
      final second = codec.sealMetadata(
        context: context,
        metadata: metadata,
        oldTokenHash: tokenHash,
      );
      expect(first['nonceBase64'], isNot(second['nonceBase64']));
      expect(first['ciphertextBase64'], isNot(second['ciphertextBase64']));
      expect(jsonEncode(first), isNot(contains('PRIVATE_ROUTING_SENTINEL')));
      expect(jsonEncode(first), isNot(contains(tokenHash)));
      expect(
        await codec.openUntrustedMetadata(
          envelope: first,
          context: context,
          token: token,
        ),
        metadata,
      );
      await expectLater(
        codec.openUntrustedMetadata(
          envelope: first,
          context: context,
          token: 'fhi3_${'b' * 64}',
        ),
        throwsFormatException,
      );
      await expectLater(
        codec.openUntrustedMetadata(
          envelope: first,
          context: {...context, 'bridgeId': crypto.randomId()},
          token: token,
        ),
        throwsFormatException,
      );
      final bytes = base64Decode(first['ciphertextBase64'] as String);
      bytes[0] ^= 1;
      await expectLater(
        codec.openUntrustedMetadata(
          envelope: {...first, 'ciphertextBase64': base64Encode(bytes)},
          context: context,
          token: token,
        ),
        throwsFormatException,
      );
      for (final forbidden in [
        'spaceName',
        'title',
        'content',
        'keyBase64',
        'tokenCipher',
        'mailState',
      ]) {
        expect(
          () => codec.sealMetadata(
            context: context,
            metadata: {...metadata, forbidden: 'PRIVATE_BUSINESS_OR_KEY'},
            oldTokenHash: tokenHash,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => codec.sealMetadata(
          context: {...context, 'tokenHash': tokenHash},
          metadata: metadata,
          oldTokenHash: tokenHash,
        ),
        throwsFormatException,
      );
      expect(
        () => codec.sealMetadata(
          context: context,
          metadata: {...metadata, 'scopeId': crypto.randomId()},
          oldTokenHash: tokenHash,
        ),
        throwsFormatException,
      );
      // Opening returns plain routing facts only, never a verified invitation,
      // a member grant, a delivery acknowledgement, or a ready key.
      expect(
        (await codec.openUntrustedMetadata(
          envelope: first,
          context: context,
          token: token,
        )).keys,
        isNot(contains('authorization')),
      );
    },
  );
}
