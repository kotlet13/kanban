<?php
/** Synthetic loopback wrapper. No real mail is sent; redirect output privately. */
ob_start();require __DIR__.'/crypto2-migration-http-seed.php';$base=json_decode(ob_get_clean(),true,128,JSON_THROW_ON_ERROR);
$invitations=[];
foreach(['pending','accepted','revoked','expired']as$i=>$state){
    $id=seedMigrationId();$token='fhi'.($i%3+1).'_'.bin2hex(random_bytes(32));$now=time();
    seedMigrationSql('INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,recipient_email,recipient_account_id,role,token_hash,created_at,expires_at,accepted_at,accepted_by,accepted_account_id,revoked_at,invitation_contract,access_scope) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [$id,$base['scopeId'],$base['session']['user']['id'],$base['session']['user']['accountId'],'','synthetic_'.$i.'@bridge.invalid',null,'viewer',hash('sha256',$token),$now-1000,$state==='expired'?$now-1:$now+3600,$state==='accepted'?$now-500:null,null,null,$state==='revoked'?$now-500:null,3,'space']);
    if($state==='pending')seedMigrationSql('INSERT INTO familyhub_invitation_mail VALUES(?,?,?,?,?,?,?,?,?)',[$id,'SYNTHETIC_RETAINED_CIPHER','en','processing',3,$now+40,str_repeat('e',32),$now+80,null]);
    $invitations[]=['id'=>$id,'token'=>$token,'state'=>$state];
}
$base['legacyInvitations']=$invitations;echo json_encode($base,JSON_THROW_ON_ERROR).PHP_EOL;
