import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_blob_window_policy.dart';

void main() {
  bool allowed({
    Duration elapsed = const Duration(seconds: 1),
    int used = 0,
    int size = 196608,
    bool foreground = true,
    bool lifecycle = true,
    bool current = true,
    bool own = true,
    bool scope = true,
    bool members = true,
    bool manifest = true,
    bool source = true,
    bool chunk = true,
  }) => permitsImmutableBlobChunk(
    elapsed: elapsed,
    usedBytes: used,
    chunkBytes: size,
    foreground: foreground,
    lifecycleMatches: lifecycle,
    identityCurrent: current,
    ownSnapshotMatches: own,
    scopePinMatches: scope,
    allMembersPinned: members,
    manifestMatches: manifest,
    sourceProofMatches: source,
    stagedChunkMatches: chunk,
  );
  test('only exact staged ciphertext fits monotonic bounded window', () {
    expect(allowed(), true);
    expect(allowed(elapsed: const Duration(seconds: 5)), false);
    expect(allowed(elapsed: const Duration(seconds: -1)), false);
    expect(allowed(used: 2 * 1024 * 1024), false);
    expect(allowed(size: 196609), false);
  });
  test(
    'background, missing member pin, changed object/chunk and revocation force fresh authority',
    () {
      for (final invalid in [
        allowed(foreground: false),
        allowed(lifecycle: false),
        allowed(current: false),
        allowed(own: false),
        allowed(scope: false),
        allowed(members: false),
        allowed(manifest: false),
        allowed(source: false),
        allowed(chunk: false),
      ])
        expect(invalid, false);
    },
  );
}
