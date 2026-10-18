<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** One final SQL boundary for the existing project-sharing conversion. */
class NativeCryptoProjectRelocationCommitV2 extends NativeDatabase
{
    protected $cryptoAccess=true;

    public function commit($p,$actor,$proof,$command,$key)
    {
        $this->fields($p,['actionId','planHash','publications','accountEventProof']);
        if(!$this->transactionActive()||$command['operation']!=='crypto2.projectRelocation.commit'){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        $stage=new NativeCryptoProjectRelocationStageV2($this->container,$this->bearer,$this->ip);
        $prepared=$stage->prepareInstall($p['actionId'],$p['planHash'],$actor,$command,$key);
        $row=$prepared['plan'];$plan=$prepared['body'];
        // All these preparations are read-only. No partial source tombstone,
        // target catalogue entry, notification move or audit row can precede
        // complete source CAS and all closed-purpose commitments.
        $audit=new NativeCryptoProjectRelocationAuditV2($this->container,$this->bearer,$this->ip);
        $auditPlan=$audit->prepareInstall($prepared,$actor,$command,$key);
        $prepared['blobIds']=array_values(array_unique(array_merge($prepared['blobIds'],$auditPlan['blobIds'])));
        $notifications=new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip);
        $notificationPlan=$notifications->prepareInstall($prepared,$actor,$command,$key);
        $this->change("UPDATE familyhub_crypto_project_relocations_v2 SET state='committing' WHERE action_id=?",[$row['action_id']]);
        $row['state']='committing';
        $api=new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip);
        $api->installTarget($row['action_id'],$row['plan_hash'],$actor);
        $stage->installBlobs($prepared,$actor);
        $records=(new NativeCryptoStorageV2($this->container,$this->bearer,$this->ip))
            ->installProjectRelocation($prepared,$actor,$command,$key);
        $audit->install($auditPlan);
        $notifications->install($notificationPlan);
        $publication=(new NativeCryptoProjectRelocationPublicationV2($this->container,$this->bearer,$this->ip))
            ->publish($row,$plan,$p['publications'],$prepared['leaves'],$prepared['batchDigests'],$auditPlan,$notificationPlan,$actor,$command,$key,$p['accountEventProof']);
        $this->change("UPDATE familyhub_crypto_project_relocations_v2 SET state='committed' WHERE action_id=?",[$row['action_id']]);
        // Private preparatory receipts/source correspondence remain immutable
        // through final exact-ACK recovery. They are not scoped read evidence.
        return ['moved'=>true,'actionId'=>$row['action_id'],'planHash'=>$row['plan_hash'],
            'targetScopeId'=>$plan['targetScopeId'],'projectId'=>$plan['projectId'],
            'publicationRoot'=>$publication['publicationRoot'],'eventHeadHash'=>$publication['eventHeadHash'],
            'eventCommandHash'=>$publication['eventCommandHash'],'records'=>$records];
    }
}
