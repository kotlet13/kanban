<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Capture3 ciphertext/randomized commitments. Never reinterpret preview2 roots. */
final class NativeCryptoMigrationCommitmentsV3
{
    public const HEADER_FIELDS = ['version', 'serverId', 'migrationId', 'componentId',
        'componentCommitment', 'inventoryCommitment', 'scopeId', 'scopeToken', 'domain',
        'membershipHeadHash', 'managerAccountId', 'managerDirectoryHeadHash',
        'sourceRowCount', 'materializedRecordProofCount'];
    public const LEAF_FIELDS = ['version', 'migrationId', 'scopeId', 'domain', 'membershipHeadHash',
        'captureId', 'sourceInventoryRoot', 'bindingId', 'sourceCommitment', 'legacyRevision',
        'sourceKind', 'canonicalId', 'wireId', 'type', 'recordProofHash', 'materializationRole',
        'contributorAccountId', 'contributorDeviceId', 'contributorDeviceSnapshotHash',
        'archiveManifestHash', 'coldParityHash', 'witnessCipherManifestHash'];

    public static function scopeToken($serverId, $migrationId, $scopeId, $domain)
    {
        foreach ([$serverId, $migrationId, $scopeId] as $id) self::uuid($id);
        self::domain($domain);
        return hash('sha256', "JivieMigrationScope/v3\n".self::canonical([
            'version' => 3, 'serverId' => $serverId, 'migrationId' => $migrationId,
            'scopeId' => $scopeId, 'domain' => $domain,
        ]));
    }

    public static function componentCommitment($serverId,$migrationId,$componentId,$inventoryCommitment)
    {
        foreach ([$serverId,$migrationId,$componentId] as $id) self::uuid($id);
        self::digest($inventoryCommitment);
        return hash('sha256',"JivieMigrationComponent/v3\n".self::canonical([
            'version'=>3,'serverId'=>$serverId,'migrationId'=>$migrationId,
            'componentId'=>$componentId,'inventoryCommitment'=>$inventoryCommitment,
        ]));
    }

    public static function inventoryCommitment($serverId, $migrationId, $componentId, $portionCount, iterable $portions)
    {
        foreach ([$serverId, $migrationId, $componentId] as $id) self::uuid($id);
        if (!is_int($portionCount) || $portionCount < 1 || $portionCount > 1000) self::fail('context');
        $sink = hash_init('sha256');
        hash_update($sink, "JivieMigrationInventory/v3\n".self::canonical([
            'version' => 3, 'serverId' => $serverId, 'migrationId' => $migrationId,
            'componentId' => $componentId, 'portionCount' => $portionCount,
        ])."\n");
        $previous = null;
        $count = 0;
        foreach ($portions as $p) {
            self::fields($p, ['portionToken', 'captureId', 'sourceInventoryRoot']);
            self::digest($p['portionToken']); self::uuid($p['captureId']); self::digest($p['sourceInventoryRoot']);
            if (($previous !== null && strcmp($previous, $p['portionToken']) >= 0) || ++$count > $portionCount) self::fail('portions');
            $previous = $p['portionToken'];
            hash_update($sink, self::canonical($p)."\n");
        }
        if ($count !== $portionCount) self::fail('incomplete');
        return hash_final($sink);
    }

    public static function validateHeader($header)
    {
        self::fields($header, self::HEADER_FIELDS);
        foreach (['serverId', 'migrationId', 'componentId', 'scopeId', 'managerAccountId'] as $k) self::uuid($header[$k]);
        foreach (['componentCommitment', 'inventoryCommitment', 'scopeToken', 'membershipHeadHash', 'managerDirectoryHeadHash'] as $k) self::digest($header[$k]);
        self::domain($header['domain']);
        if ($header['componentCommitment'] !== self::componentCommitment($header['serverId'],$header['migrationId'],$header['componentId'],$header['inventoryCommitment']) || $header['version'] !== 3 || !is_int($header['sourceRowCount']) || $header['sourceRowCount'] < 0
            || !is_int($header['materializedRecordProofCount']) || $header['materializedRecordProofCount'] < $header['sourceRowCount']
            || $header['materializedRecordProofCount'] > 10000000
            || $header['scopeToken'] !== self::scopeToken($header['serverId'], $header['migrationId'], $header['scopeId'], $header['domain'])) self::fail('context');
    }

    public static function leafHash($header, $leaf)
    {
        self::validateHeader($header); self::fields($leaf, self::LEAF_FIELDS);
        foreach (['captureId', 'bindingId', 'canonicalId', 'contributorAccountId', 'contributorDeviceId'] as $k) self::uuid($leaf[$k]);
        foreach (['sourceInventoryRoot', 'sourceCommitment', 'recordProofHash', 'contributorDeviceSnapshotHash', 'archiveManifestHash', 'coldParityHash'] as $k) self::digest($leaf[$k]);
        foreach (['migrationId', 'scopeId', 'domain', 'membershipHeadHash'] as $k) if ($leaf[$k] !== $header[$k]) self::fail('leaf');
        if ($leaf['version'] !== 3 || !in_array($leaf['materializationRole'], ['primary', 'taskDerivationIntent', 'taskDerivationResolution', 'financeAccountChoice'], true)
            || !is_int($leaf['legacyRevision']) || $leaf['legacyRevision'] < 0) self::fail('leaf');
        NativeCryptoRecordAddressV2::wireId($leaf['wireId']);
        if (!is_string($leaf['type']) || !is_string($leaf['sourceKind'])
            || NativeCryptoRecordAddressV2::derive($header['serverId'], $leaf['scopeId'], $leaf['domain'], $leaf['sourceKind'], $leaf['canonicalId']) !== $leaf['wireId']) self::fail('leaf');
        // Mapping/type validation is closed even if an attacker supplies a
        // self-consistent hash for an invented source namespace.
        $identity = ['sourceKind' => $leaf['sourceKind'], 'canonicalId' => $leaf['canonicalId']];
        NativeCryptoRecordAddressV2::verify(['serverId' => $header['serverId'], 'scopeId' => $leaf['scopeId'],
            'domain' => $leaf['domain'], 'type' => $leaf['type'], 'id' => $leaf['wireId'], 'metadata' => ['identity' => $identity]]);
        if (($leaf['legacyRevision'] === 0 && $leaf['type'] !== 'scopeMetadata')
            || ($leaf['materializationRole'] === 'taskDerivationIntent' && $leaf['type'] !== 'taskDerivationIntent')
            || ($leaf['materializationRole'] === 'financeAccountChoice' && $leaf['type'] !== 'financeAccountChoice')
            || ($leaf['materializationRole'] === 'taskDerivationResolution' && $leaf['type'] !== 'taskDerivationResolution')) self::fail('leaf');
        if ($leaf['type'] === 'scopeMetadata') {
            if ($leaf['witnessCipherManifestHash'] !== null || $leaf['contributorAccountId'] !== $header['managerAccountId']) self::fail('leaf');
        } else self::digest($leaf['witnessCipherManifestHash']);
        return hash('sha256', "JivieMigrationLeaf/v3\n".self::canonical($leaf));
    }

    public static function domainRoot($header, iterable $hashes)
    {
        self::validateHeader($header);
        $sink = hash_init('sha256');
        hash_update($sink, "JivieMigrationDomain/v3\n".self::canonical($header)."\n");
        $previous = null; $count = 0;
        foreach ($hashes as $hash) {
            self::digest($hash);
            if (($previous !== null && strcmp($previous, $hash) >= 0) || ++$count > $header['materializedRecordProofCount']) self::fail('order');
            $previous = $hash; hash_update($sink, $hash."\n");
        }
        if ($count !== $header['materializedRecordProofCount']) self::fail('incomplete');
        return hash_final($sink);
    }
    public const CONTRIBUTION_FIELDS = ['version','serverId','migrationId','scopeToken','domain','headerHash',
        'portionToken','captureId','sourceInventoryRoot','coldParityProofHash','leafCount','sourceRowCount','authorDirectoryHeadHash'];

    public static function headerHash($header)
    {
        self::validateHeader($header);
        return hash('sha256', "JivieMigrationDomainHeader/v3\n".self::canonical($header));
    }

    /** Exact selected portion's opaque leaf contribution, including required
     * empties. Selection/READ/signature and own-log inclusion are independent
     * caller obligations; this codec grants none of those authorities. */
    public static function contributionRoot($header, iterable $hashes)
    {
        self::fields($header,self::CONTRIBUTION_FIELDS);
        foreach (['serverId','migrationId','captureId'] as $key) self::uuid($header[$key]);
        foreach (['scopeToken','headerHash','portionToken','sourceInventoryRoot','coldParityProofHash','authorDirectoryHeadHash'] as $key) self::digest($header[$key]);
        self::domain($header['domain']);
        if ($header['version'] !== 3 || !is_int($header['leafCount']) || !is_int($header['sourceRowCount'])
            || $header['sourceRowCount'] < 0 || $header['leafCount'] < $header['sourceRowCount'] || $header['leafCount'] > 10000000) self::fail('contribution');
        $sink=hash_init('sha256');
        hash_update($sink,"JivieMigrationContribution/v3\n".self::canonical($header)."\n");
        $previous=null;$count=0;
        foreach ($hashes as $hash) {
            self::digest($hash);
            if ($previous !== null && strcmp($previous,$hash)>=0 || ++$count>$header['leafCount']) self::fail('contribution');
            $previous=$hash;hash_update($sink,$hash."\n");
        }
        if ($count!==$header['leafCount']) self::fail('incomplete');
        return hash_final($sink);
    }

    private static function canonical($v) { return NativeCryptoCodec::canonical((object)$v); }
    private static function fields($v, $fields) {
        if (!is_array($v) || count($v) !== count($fields) || array_diff(array_keys($v), $fields)) self::fail('shape');
    }
    private static function uuid($v) {
        if (!is_string($v) || !preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/D', $v)) self::fail('context');
    }
    private static function digest($v) { if (!is_string($v) || !preg_match('/^[0-9a-f]{64}$/D', $v)) self::fail('digest'); }
    private static function domain($v) { if (!in_array($v, ['content', 'finance'], true)) self::fail('context'); }
    private static function fail($why) { throw new NativeError('crypto_capture_commitment_'.$why, 409); }
}
