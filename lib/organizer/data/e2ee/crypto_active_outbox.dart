/// Local completion of a derived checkpoint assertion is distinct from a
/// terminal server receipt. Only the verified checkpoint supersession workflow
/// writes this marker and matching audit event. Original rows remain intact.
/// This predicate is selection/accounting only, never cryptographic authority.
String cryptoActiveOutboxPredicate([String alias = 'crypto_outbox']) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(alias)) {
    throw ArgumentError.value(alias, 'alias');
  }
  const evidence =
      "CASE WHEN json_valid(supersession.value) THEN supersession.value ELSE '{}' END";
  return """NOT (
    $alias.operation='crypto2.domain.checkpoint' AND $alias.state='blocked'
    AND NOT EXISTS(SELECT 1 FROM crypto_outbox_records claim
      WHERE claim.partition=$alias.partition AND claim.request_id=$alias.request_id)
    AND EXISTS(SELECT 1 FROM local_meta supersession
      WHERE supersession.name='crypto_checkpoint_superseded_v1:' || $alias.partition || ':' || $alias.request_id
      AND json_extract($evidence,'\$.version') IN (1,2)
      AND json_extract($evidence,'\$.oldRequestHash')=$alias.request_hash
      AND EXISTS(SELECT 1 FROM crypto_outbox_attempts audit
        WHERE audit.partition=$alias.partition AND audit.request_id=$alias.request_id
        AND audit.event='checkpoint_superseded_locally' AND audit.details=supersession.value)
      AND ((json_extract($evidence,'\$.version')=1 AND EXISTS(SELECT 1 FROM crypto_outbox replacement
        WHERE replacement.partition=$alias.partition
        AND replacement.request_id=json_extract($evidence,'\$.newRequestId')
        AND replacement.request_id!=$alias.request_id
        AND replacement.operation='crypto2.domain.checkpoint' AND replacement.state='applied'
        AND replacement.request_hash=json_extract($evidence,'\$.newRequestHash')))
      OR (json_extract($evidence,'\$.version')=2 AND EXISTS(
        SELECT 1 FROM crypto_domain_checkpoints checkpoint
        WHERE checkpoint.partition=$alias.partition
          AND checkpoint.scope_id=json_extract($evidence,'\$.scopeId')
          AND checkpoint.domain=json_extract($evidence,'\$.domain')
          AND checkpoint.head_hash=json_extract($evidence,'\$.newHeadHash')
          AND checkpoint.sequence=json_extract($evidence,'\$.replacementSequence')
          AND checkpoint.manifest_hash=json_extract($evidence,'\$.replacementManifest')
          AND checkpoint.authorization=json_extract($evidence,'\$.replacementAuthorization')))))
  )""";
}
