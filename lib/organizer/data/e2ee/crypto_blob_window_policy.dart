/// A bounded optimization for immutable staged ciphertext, never plaintext,
/// records or key grants. Production elapsed time comes from a Stopwatch.
bool permitsImmutableBlobChunk({
  required Duration elapsed,
  required int usedBytes,
  required int chunkBytes,
  required bool foreground,
  required bool lifecycleMatches,
  required bool identityCurrent,
  required bool ownSnapshotMatches,
  required bool scopePinMatches,
  required bool allMembersPinned,
  required bool manifestMatches,
  required bool sourceProofMatches,
  required bool stagedChunkMatches,
}) =>
    elapsed >= Duration.zero &&
    elapsed < const Duration(seconds: 5) &&
    usedBytes >= 0 &&
    chunkBytes > 0 &&
    chunkBytes <= 196608 &&
    usedBytes + chunkBytes <= 2 * 1024 * 1024 &&
    foreground &&
    lifecycleMatches &&
    identityCurrent &&
    ownSnapshotMatches &&
    scopePinMatches &&
    allMembersPinned &&
    manifestMatches &&
    sourceProofMatches &&
    stagedChunkMatches;
