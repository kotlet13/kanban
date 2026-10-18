<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Privacy3 cold-business commitment. Callers reconstruct the entire frozen
 * source stream and validate each closed adapter; this codec never decrypts. */
final class NativeCryptoMigrationBusinessParityV3
{
    public const ADAPTERS = ['canonical','canonicalFile','structure','notification','invitation','immutableReceipt','auditHistory','moderationDisclosure','sourceContext'];
    public const SECTIONS = ['audit','invitations','notifications','receipts','structure'];

    public static function sourceAdapter($table)
    {
        return match ($table) {
            'familyhub_scopes','familyhub_records','familyhub_finance_records','familyhub_tables','familyhub_attachments',
            'familyhub_payment_events','familyhub_payment_projections','familyhub_payment_cash' => 'canonical',
            'familyhub_idea_assets' => 'canonicalFile',
            'familyhub_members','familyhub_organization_leaders','familyhub_scope_revocations','familyhub_finance_policy',
            'familyhub_finance_grants','familyhub_personal_scopes','familyhub_record_relocations' => 'structure',
            'familyhub_reminders','familyhub_inbox','familyhub_inbox_preferences','familyhub_inbox_state',
            'familyhub_deliveries','familyhub_push_jobs' => 'notification',
            'familyhub_invitations','familyhub_invitation_mail' => 'invitation',
            'familyhub_operations','familyhub_finance_operations','familyhub_document_requests' => 'immutableReceipt',
            'familyhub_finance_audit' => 'auditHistory',
            'familyhub_moderation_reports','familyhub_idea_report_assets' => 'moderationDisclosure',
            'familyhub_attachment_chunks' => 'sourceContext',
            default => throw new NativeError('crypto_business_parity_adapter_pending',409),
        };
    }

    /** Caller first verifies exact signed stage/source/ciphertext dependencies. */
    public static function canonicalArtifact($signedSourceBinding)
    {
        self::fields($signedSourceBinding,['bindingId','scopeId','sourceKind','canonicalId','wireId','domain',
            'type','legacyRevision','recordProofHash','companionProofHashes','witness','objects']);
        return hash('sha256',"JivieMigrationCanonicalArtifact/v3\n".self::canonical($signedSourceBinding));
    }

    /** Caller first verifies the exact signed physical file begin and bytes. */
    public static function canonicalFileArtifact($signedBegin)
    {
        self::fields($signedBegin,['commandBase64','signatureBase64']);
        [$command]=NativeCryptoCodec::decode($signedBegin);
        self::fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        $p=$command['payload'];
        self::fields($p,['captureVersion','migrationId','captureId','sourceInventoryRoot','bindingId','scopeId','domain','epoch','membershipHeadHash','accessRevision','id','purpose','size','sha256','manifestBase64']);
        if($command['version']!==2||$command['operation']!=='crypto2.migration.blob.begin'||$command['signer']!=='device'||$p['captureVersion']!==3||$p['purpose']!=='ideaAsset'||$p['domain']!=='content')self::fail('file');
        return hash('sha256',"JivieMigrationCanonicalArtifact/v3\n".self::canonical($signedBegin));
    }

    public static function compute($header, iterable $frames)
    {
        self::fields($header, ['version','serverId','migrationId','captureId','componentId','componentCommitment','accountId','sourceInventoryRoot','sourceCount','archiveManifestHash']);
        foreach (['serverId','migrationId','captureId','componentId','accountId'] as $k) self::uuid($header[$k]);
        foreach (['componentCommitment','sourceInventoryRoot','archiveManifestHash'] as $k) self::digest($header[$k]);
        if ($header['version'] !== 3 || !self::count($header['sourceCount']) || $header['sourceCount'] > 10000000) self::fail('context');
        $sink = hash_init('sha256'); hash_update($sink, "JivieMigrationBusinessParity/v3\n");
        $add = static function($tag,$value) use ($sink) {
            $bytes = self::canonical(['tag'=>$tag,'value'=>$value]);
            if (strlen($bytes) > 196608) self::fail('frame');
            hash_update($sink,$bytes."\n");
        };
        $add('header',$header);
        $inventory = hash_init('sha256');
        $inventoryHeader = ['version'=>3];
        foreach (['serverId','captureId','migrationId','accountId','sourceCount'] as $k) $inventoryHeader[$k]=$header[$k];
        hash_update($inventory,"JivieCaptureInventory/v3\n".self::canonical($inventoryHeader)."\n");
        $phase=0; $sourceRows=0; $primary=0; $companions=0; $contexts=0; $userFiles=0; $userBytes=0; $proofBlobs=0;
        $previous=null; $sections=[]; $adapterCounts=array_fill_keys(self::ADAPTERS,0);
        foreach ($frames as $frame) {
            self::fields($frame,['tag','value']); $tag=$frame['tag']; $v=$frame['value'];
            if (!is_array($v)) self::fail('shape');
            if ($tag === 'binding') {
                self::fields($v,['binding','adapter','primaryRecordProofHash','companionProofHashes','artifactHash']);
                NativeCryptoCaptureV3::binding($v['binding']);
                $adapter=$v['adapter']; $hashes=$v['companionProofHashes'];
                if (!in_array($adapter,self::ADAPTERS,true) || !is_array($hashes) || !array_is_list($hashes) || count($hashes)>31) self::fail('adapter_pending');
                self::digest($v['artifactHash']);
                if ($adapter === 'canonical') self::digest($v['primaryRecordProofHash']);
                elseif ($v['primaryRecordProofHash'] !== null || $hashes) self::fail('adapter_pending');
                $last=null;
                foreach ($hashes as $h) {
                    self::digest($h);
                    if ($h === $v['primaryRecordProofHash'] || $last !== null && strcmp($last,$h)>=0) self::fail('companions');
                    $last=$h;
                }
                $sourceRows++; $adapterCounts[$adapter]++;
                if ($adapter === 'canonical') { $primary++; $companions+=count($hashes); }
                if (in_array($adapter,['immutableReceipt','moderationDisclosure','sourceContext'],true)) $contexts++;
                if ($sourceRows > $header['sourceCount']) self::fail('coverage');
                hash_update($inventory,self::canonical($v['binding'])."\n");
                $nextPhase=1; $key=$v['binding']['bindingId'];
            } elseif ($tag === 'file' || $tag === 'proofBlob') {
                self::fields($v,['bindingId','id','kind','plainSize','cipherSize','cipherSha256','manifestHash']);
                self::uuid($v['bindingId']); self::uuid($v['id']); self::digest($v['cipherSha256']); self::digest($v['manifestHash']);
                if (($tag === 'file' ? !self::count($v['plainSize']) || $v['plainSize']>20971520 : $v['plainSize'] !== null) || !self::count($v['cipherSize']) || $v['cipherSize']<1 || $v['cipherSize']>69206016 ||
                    ($tag === 'file' ? !in_array($v['kind'],['attachment','ideaAsset'],true) : $v['kind'] !== 'typedWitness')) self::fail('file');
                if ($tag === 'file') { $userFiles++; $userBytes+=$v['plainSize']; } else { $proofBlobs++; }
                $nextPhase=$tag === 'file'?2:3; $key=$v['bindingId'].'/'.$v['kind'].'/'.$v['id'];
            } elseif ($tag === 'section') {
                self::fields($v,['kind','count','root']); self::digest($v['root']);
                if (!in_array($v['kind'],self::SECTIONS,true) || !self::count($v['count']) || isset($sections[$v['kind']])) self::fail('section');
                $sections[$v['kind']]=true; $nextPhase=4; $key=$v['kind'];
            } else self::fail('adapter_pending');
            if ($nextPhase<$phase || $nextPhase===$phase && $previous !== null && strcmp($previous,$key)>=0) self::fail('order');
            $phase=$nextPhase; $previous=$key; $add($tag,$v);
        }
        if ($sourceRows !== $header['sourceCount'] || !hash_equals($header['sourceInventoryRoot'],hash_final($inventory)) || count($sections)!==count(self::SECTIONS)) self::fail('coverage');
        $footer=['version'=>3,'sourceRowCount'=>$sourceRows,'primaryRecordProofCount'=>$primary,'companionProofCount'=>$companions,'archiveContextRowCount'=>$contexts,
            'userFileCount'=>$userFiles,'userFileBytes'=>$userBytes,'witnessBlobCount'=>$proofBlobs,'adapterCounts'=>$adapterCounts];
        $add('footer',$footer); return $footer+['hash'=>hash_final($sink)];
    }
    private static function canonical($v) { return NativeCryptoCodec::canonical((object)$v); }
    private static function fields($v,$keys) { if (!is_array($v) || count($v)!==count($keys) || array_diff(array_keys($v),$keys)) self::fail('shape'); }
    private static function count($v) { return is_int($v) && $v>=0 && $v<=9007199254740991; }
    private static function uuid($v) { if (!is_string($v) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$v)) self::fail('context'); }
    private static function digest($v) { if (!is_string($v) || !preg_match('/^[a-f0-9]{64}$/D',$v)) self::fail('digest'); }
    private static function fail($why) { throw new NativeError('crypto_business_parity_'.$why,409); }
}
