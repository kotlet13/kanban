<?php
require '/var/www/app/app/common.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationCommitmentsV3 as C;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$f = json_decode(file_get_contents(__DIR__.'/fixtures/e2ee-migration-commitments-v3.json'), true, 64, JSON_THROW_ON_ERROR);
$n = 0;
$check = function ($ok) use (&$n) { if (!$ok) throw new RuntimeException('capture3 commitment vector'); $n++; };
$deny = function ($fn) use ($check) { try { $fn(); $ok = false; } catch (NativeError $e) { $ok = true; } $check($ok); };
$h = $f['header'];
$check(C::scopeToken($h['serverId'], $h['migrationId'], $h['scopeId'], $h['domain']) === $h['scopeToken']);
$i = $f['inventoryHeader'];
$check(C::inventoryCommitment($i['serverId'], $i['migrationId'], $i['componentId'], 2, $f['portions']) === $f['inventoryCommitment']);
$hashes = array_map(fn($l) => C::leafHash($h, $l), $f['leaves']); sort($hashes);
$check($hashes === $f['leafHashes']);
$check(C::domainRoot($h, $hashes) === $f['root']);
$check(C::domainRoot(array_replace($h, ['sourceRowCount' => 0, 'materializedRecordProofCount' => 0]), []) === $f['emptyRoot']);
$deny(fn() => C::domainRoot($h, array_reverse($hashes)));
$deny(fn() => C::domainRoot($h, [$hashes[0], $hashes[0]]));
$deny(fn() => C::domainRoot($h, [$hashes[0]]));
$deny(fn() => C::leafHash($h, array_replace($f['leaves'][0], ['domain' => 'finance'])));
$deny(fn() => C::leafHash($h, array_replace($f['leaves'][0], ['sourceRowHash' => str_repeat('a', 64)])));
$deny(fn() => C::validateHeader(array_replace($h, ['version' => 2])));
$deny(fn() => C::inventoryCommitment($i['serverId'], $i['migrationId'], $i['componentId'], 2, [$f['portions'][0], $f['portions'][0]]));
$check(C::componentCommitment($h['serverId'],$h['migrationId'],$h['componentId'],$h['inventoryCommitment'])===$h['componentCommitment']);
foreach (['serverId','migrationId','componentId','inventoryCommitment','componentCommitment'] as $field) {
    $deny(fn()=>C::validateHeader(array_replace($h,[$field=>str_ends_with($field,'Commitment')?str_repeat('0',64):'99999999-1111-4111-8111-111111111111'])));
}
$check(C::headerHash($h)===$f['headerHash']);
$ch=$f['contributionHeader'];
$check(C::contributionRoot($ch,$hashes)===$f['contributionRoot']);
$check(C::contributionRoot(array_replace($ch,['leafCount'=>0,'sourceRowCount'=>0]),[])===$f['emptyContributionRoot']);
$deny(fn()=>C::contributionRoot($ch,array_reverse($hashes)));
$deny(fn()=>C::contributionRoot($ch,[$hashes[0],$hashes[0]]));
$deny(fn()=>C::contributionRoot($ch,[$hashes[0]]));
$deny(fn()=>C::contributionRoot(array_replace($ch,['leafCount'=>-1]),[]));
foreach(['serverId','migrationId','captureId','scopeToken','headerHash','sourceInventoryRoot','coldParityProofHash','portionToken'] as $field){
    $changed=array_replace($ch,[$field=>str_ends_with($field,'Id')?'99999999-1111-4111-8111-111111111111':str_repeat('9',64)]);
    $check(C::contributionRoot($changed,$hashes)!==$f['contributionRoot']);
}
echo 'migration commitments3 vectors PASS '.$n.PHP_EOL;
