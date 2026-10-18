<?php
require __DIR__.'/crypto2-creation-integration.php';

$candidate = candidate2($created, $state, 2, $head['headHash'], ['content' => hash('sha256', ''), 'finance' => hash('sha256', '')]);
$candidate['membershipIntents'] = [];
for ($index = 0; $index < 101; $index++) {
    $candidate['membershipIntents'][] = ['accountId' => uid(), 'invitationId' => uid(), 'acceptanceProofHash' => hash('sha256', 'synthetic intent '.$index)];
}
$before = count(q('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=?', [$newId]));
deny(fn() => send2('crypto2.scope.headPut', $candidate, $fresh, $freshKeys), 'validation_error', '101 new membership intents are rejected at proposal validation before key grant export');
ck(count(q('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=?', [$newId])) === $before, 'oversized membership intent batch creates no candidate or key grant namespace');

echo 'Crypto2 membership intent limit integration: '.$checks.' checks PASS'.PHP_EOL;
