<?php
require __DIR__.'/crypto2-moderation-assets-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

// A successful report has only its own minimal outcome, even after loss of the
// original scope READ. No report snapshot, roster or staging bytes are returned.
$ownerBefore = q('SELECT owner_id FROM familyhub_scopes WHERE id=?', [$newId])[0]['owner_id'];
q('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?', [$newId,$fresh['user']['accountId']]);
q('UPDATE familyhub_scopes SET owner_id=? WHERE id=?', [$outsider['user']['id'],$newId]);
deny(fn() => call('crypto2.moderation.reportPreview', ['scopeId'=>$newId,'targetType'=>'record','targetId'=>$idea['id']], $fresh), 'permission_revoked', 'removed reporter cannot inspect current old target or create a new disclosure');
ck(call('crypto2.moderation.report', $imageRequest, $fresh) === $imageReceipt, 'accepted image report lost ACK returns exact minimal own success after scope access is gone');
[$imageCommand,$imageBytes] = NativeCryptoCodec::decode($imageRequest);
$ownReceipt = call('crypto2.receipt.get', ['requestId'=>$imageCommand['requestId'],'requestHash'=>hash('sha256',$imageBytes)], $fresh);
ck($ownReceipt['response'] === $imageReceipt && $ownReceipt['authorizationRetained'] === false, 'own hash-bound report receipt reveals no selected image or original disclosure body after revocation');
$changedImage = $imageCommand;
$changedImage['payload']['reason'] = 'spam';
deny(fn() => call('crypto2.moderation.report', inner2($changedImage, "JivieE2EE/v2\n", $freshKeys), $fresh), 'idempotency_mismatch', 'removed reporter cannot substitute a new disclosure under the accepted own report ID');
ck(call('crypto2.receipt.get', ['requestId'=>$imageCommand['requestId'],'requestHash'=>hash('sha256',$imageBytes)], $outsider)['outcome'] === 'unknown', 'another account cannot retrieve the original reporter outcome by request ID');
q('UPDATE familyhub_scopes SET owner_id=? WHERE id=?', [$ownerBefore,$newId]);
q('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?', [$newId,$fresh['user']['accountId']]);
echo 'Crypto2 moderation own receipt integration: '.$checks.' checks PASS'.PHP_EOL;
