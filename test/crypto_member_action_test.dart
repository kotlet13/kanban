import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_member_action.dart';

void main() {
  final original = <String, Object?>{
    'version': 2,
    'operation': 'removeMember',
    'serverId': 'server',
    'accountId': 'owner',
    'deviceId': 'approved-device',
    'scopeId': 'scope',
    'requestId': 'request-one',
    'reviewId': 'review-one',
    'sourceHeadHash': 'authenticated-old-head',
    'targetAccountId': 'exact-member',
    'membersHash': 'reviewed-future-roster',
    'authorDirectoryHeadHash': 'author-prefix',
  };
  test(
    'valid old signed member action cannot be relabeled as another review',
    () {
      CryptoMemberAction.requireBinding(original, Map.from(original));
      for (final replacement in {
        'requestId': 'different-request',
        'reviewId': 'unrelated-review',
        'sourceHeadHash': 'different-head',
        'targetAccountId': 'another-member',
        'membersHash': 'roster-that-keeps-removed-member',
        'scopeId': 'other-scope',
        'serverId': 'other-server',
        'accountId': 'another-owner',
      }.entries) {
        expect(
          () => CryptoMemberAction.requireBinding(original, {
            ...original,
            replacement.key: replacement.value,
          }),
          throwsFormatException,
          reason: replacement.key,
        );
      }
      expect(
        () => CryptoMemberAction.requireBinding({
          ...original,
          'extra': true,
        }, original),
        throwsFormatException,
      );
    },
  );
  test(
    'secure review approval anchor cannot substitute or import approval flags',
    () {
      final anchor = <String, Object?>{
        'version': 2,
        'actionProofHash': 'exact-proof',
        'requestId': 'request-one',
        'reviewId': 'review-one',
        'acceptedCandidateHistory': false,
      };
      Map<String, dynamic> check(Map value) => CryptoMemberAction.anchor(
        value,
        actionProofHash: 'exact-proof',
        requestId: 'request-one',
        reviewId: 'review-one',
      );
      expect(check(anchor)['acceptedCandidateHistory'], isFalse);
      for (final replacement in {
        'actionProofHash': 'unrelated-proof',
        'requestId': 'other-request',
        'reviewId': 'other-review',
        'version': 1,
        'acceptedCandidateHistory': 'true',
      }.entries) {
        expect(
          () => check({...anchor, replacement.key: replacement.value}),
          throwsFormatException,
          reason: replacement.key,
        );
      }
      expect(
        () => check({...anchor, 'restoredTrusted': true}),
        throwsFormatException,
      );
    },
  );
}
