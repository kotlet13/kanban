import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_moderation.dart';

void main() {
  test(
    'review selects semantic fields without crypto keys or unknown dumps',
    () {
      final selected = CryptoBusinessModeration.selectEvidence('task', {
        'payload': {
          'title': 'Reviewed title',
          'notes': 'Reviewed text',
          'cryptoBlob': {'keyBase64': 'SECRET_DEK'},
          'cryptoPayloadBlob': {'streamKeyBase64': 'SECRET_STREAM'},
          'migrationWitness': {'raw': 'UNSELECTED_RAW'},
          'unknownPrivateExtension': 'UNSELECTED_UNKNOWN',
        },
        'authorization': {'signature': 'not disclosed'},
      });
      expect(selected, {'title': 'Reviewed title', 'notes': 'Reviewed text'});
    },
  );
  test(
    'table cells stay exact reviewed strings; nested objects are refused',
    () {
      expect(
        CryptoBusinessModeration.selectEvidence('table', {
          'title': 'Reviewed table',
          'cells': {'A1': '=SUM(A2:A3)', 'A2': '80.0'},
          'cryptoBlob': {'key': 'SECRET'},
        }),
        {
          'title': 'Reviewed table',
          'cells': {'A1': '=SUM(A2:A3)', 'A2': '80.0'},
        },
      );
      expect(
        () => CryptoBusinessModeration.selectEvidence('table', {
          'cells': {
            'A1': {'key': 'SECRET'},
          },
        }),
        throwsFormatException,
      );
    },
  );
  test('moderation operation and delivery allowlists are exact', () {
    expect(CryptoBusinessModeration.operations, {
      'moderation.reportPreview',
      'moderation.report',
    });
    expect(CryptoBusinessModeration.deliveryOperations.length, 5);
    expect(
      CryptoBusinessModeration.deliveryOperations.contains(
        'crypto2.records.batch',
      ),
      isFalse,
    );
    expect(
      CryptoBusinessModeration.deliveryOperations.contains(
        'crypto2.moderation.foo',
      ),
      isFalse,
    );
  });
}
