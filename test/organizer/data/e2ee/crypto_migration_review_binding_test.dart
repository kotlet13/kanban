import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_migration_review_binding.dart';

void main() {
  test(
    'access review uses actual history relation and exact consent, never source head as success',
    () {
      final proposal = {
        'intentHash': 'intent',
        'affectedHash': 'affected',
        'affectedCount': 2,
      };
      final draft = {
        'proposal': proposal,
        'history': {'reviewId': 'review', 'sourceHeadHash': 'source'},
      };
      final body = {
        'scopeId': 'scope',
        'previousHeadHash': 'source',
        'accessIntentProof': {
          'commandBase64': base64Encode(
            CryptoJson.encode({
              'operation': 'crypto2.access.scopeConsent',
              'scopeId': 'scope',
              'previousHeadHash': 'source',
              ...proposal,
            }),
          ),
        },
      };
      bool matches(Map publication) => CryptoMigrationReviewBinding.matches(
        state: 'scopeAccessReview',
        scopeId: 'scope',
        intentId: 'accessReview:intent',
        draft: draft,
        publication: publication,
      );
      expect(matches({'reviewId': 'review', 'body': body}), isTrue);
      expect(matches({'reviewId': 'other', 'body': body}), isFalse);
      expect(
        matches({
          'reviewId': 'review',
          'body': {'scopeId': 'scope', 'previousHeadHash': 'source'},
        }),
        isFalse,
      );
      expect(
        matches({
          'reviewId': 'review',
          'body': {...body, 'previousHeadHash': 'fork'},
        }),
        isFalse,
      );
    },
  );
  test(
    'successor review id belongs to exact journal suffix and published immutable core',
    () {
      final draft = {
        'scopeId': 'scope',
        'previousHeadHash': 'source',
        'epoch': 2,
        'members': [
          {'accountId': 'member', 'role': 'editor'},
        ],
        'accessBasis': {'sequence': 4},
      };
      bool matches(Map body) => CryptoMigrationReviewBinding.matches(
        state: 'scopeSuccessorDraft',
        scopeId: 'scope',
        intentId: 'review:successor',
        draft: draft,
        publication: {'reviewId': 'review', 'body': body},
      );
      expect(
        CryptoMigrationReviewBinding.reviewId(
          'scopeSuccessorDraft',
          'review:successor',
          draft,
        ),
        'review',
      );
      expect(
        matches({
          ...draft,
          'keyIds': {'content': 'new key'},
        }),
        isTrue,
      );
      expect(matches({...draft, 'members': []}), isFalse);
      expect(matches({...draft, 'epoch': 3}), isFalse);
      expect(
        CryptoMigrationReviewBinding.reviewId('pending', 'unresolved', draft),
        isNull,
      );
    },
  );
}
