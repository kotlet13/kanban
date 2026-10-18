import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inline_deletion_codec.dart';

void main() {
  final descriptor = <String, dynamic>{
    'id': '12345678-1234-8234-a234-123456789abc',
    'domain': 'content', 'type': 'task', 'expectedRevision': 7,
    'previousRecordHash': '1' * 64, 'recordProofHash': '2' * 64,
    'batchCommitmentHash': '3' * 64,
  };
  test('inline publication opaque leaf has frozen cross-language framing', () async {
    const leaf = '940597bb2d3d8ef6ae836b0ba803fc93ffb1315d603e778dc08cc260cde51e50';
    const root = '3918098240d1809f1b212872ad956dcf5b4d7d04890bbe2f9f9c6ddd8dbf0c4f';
    expect(await CryptoInlineDeletionCodec.tombstoneLeaf(descriptor), leaf);
    expect(await CryptoInlineDeletionCodec.tombstoneRoot([descriptor]), root);
    expect(await CryptoInlineDeletionCodec.tombstoneDigestRoot([leaf]), root);
    expect(await CryptoInlineDeletionCodec.tombstoneDigestRoot([]), isNot(root));
    final changed = {...descriptor, 'recordProofHash': '4' * 64};
    expect(await CryptoInlineDeletionCodec.tombstoneRoot([changed]), isNot(root));
  });
  test('inline opaque stream rejects duplicate or reordered extra digests', () async {
    final leaf = await CryptoInlineDeletionCodec.tombstoneLeaf(descriptor);
    await expectLater(CryptoInlineDeletionCodec.tombstoneDigestRoot([leaf, leaf]), throwsFormatException);
    await expectLater(CryptoInlineDeletionCodec.tombstoneDigestRoot(['f' * 64, leaf]), throwsFormatException);
    await expectLater(CryptoInlineDeletionCodec.tombstoneRoot([descriptor, descriptor]), throwsFormatException);
  });
}
