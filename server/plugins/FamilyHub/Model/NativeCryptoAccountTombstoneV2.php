<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** An account UUID's retained public evidence is never a login identity. */
class NativeCryptoAccountTombstoneV2 extends NativeDatabase
{
    private static function lookup($pdo,$sql,$values)
    {
        try {
            $q=$pdo->prepare($sql);$q->execute($values);$row=$q->fetch(\PDO::FETCH_ASSOC);$q->closeCursor();return $row?:null;
        } catch (\PDOException $e) {
            $state=$e->errorInfo[0]??$e->getCode();$number=(int)($e->errorInfo[1]??0);
            if($state==='42S02'||$number===1146||$state==='HY000'&&$number===1&&str_contains($e->getMessage(),'no such table: familyhub_crypto_account_tombstones_v2')){return null;}
            throw new NativeError('crypto_account_tombstone_unavailable',503);
        }
    }
    public static function account($pdo,$account)
    {
        return self::lookup($pdo,'SELECT account_id FROM familyhub_crypto_account_tombstones_v2 WHERE account_id=?',[$account])!==null;
    }
    public static function user($pdo,$user)
    {
        return self::lookup($pdo,'SELECT account_id FROM familyhub_crypto_account_tombstones_v2 WHERE carrier_user_id=?',[(int)$user])!==null;
    }
    public static function operation($pdo,$operation)
    {
        return self::lookup($pdo,'SELECT account_id FROM familyhub_crypto_account_tombstones_v2 WHERE operation_id=?',[$operation])!==null;
    }
    public static function assertAccount($pdo,$account)
    {
        if(self::account($pdo,$account)){throw new NativeError('account_deleted',401);}
    }
    public static function assertUser($pdo,$user)
    {
        if(self::user($pdo,$user)){throw new NativeError('account_deleted',401);}
    }

    /** Caller holds global deletion, users and parent-before-child scope locks.
     * No signed byte is changed. Numeric references below are only the native
     * SQL routing cache; the original account UUID remains in signed history. */
    public function preserve(array $user,$operation,array $scopes)
    {
        $account=$user['account_id'];$uid=(int)$user['id'];
        self::assertAccount($this->pdo,$account);
        $this->change('INSERT INTO users(username,password,name,email,is_active,is_ldap_user,disable_login_form,role,twofactor_activated,twofactor_secret,token,api_access_token,avatar_path) VALUES(?,?,?,?,0,0,1,?,0,?,?,?,?)',[
            'deleted-'.bin2hex(random_bytes(16)),password_hash(bin2hex(random_bytes(32)),PASSWORD_BCRYPT),'Deleted account','', 'app-user','','','','',
        ]);
        $carrier=(int)$this->pdo->lastInsertId();
        $this->change('INSERT INTO familyhub_crypto_account_tombstones_v2(account_id,former_user_id,carrier_user_id,deleted_at,operation_id,authorization) VALUES(?,?,?,?,?,NULL)',[$account,$uid,$carrier,time(),$operation]);
        if($this->change('UPDATE familyhub_accounts SET user_id=? WHERE account_id=? AND user_id=?',[$carrier,$account,$uid])!==1){throw new NativeError('crypto_account_binding_changed',409);}
        foreach($scopes as $scope){
            $sid=$scope['id'];
            $head=$this->one('SELECT head_hash,access_revision FROM familyhub_crypto_scope_state WHERE scope_id=?',[$sid]);
            $this->change(($this->sqlite?'INSERT OR IGNORE':'INSERT IGNORE').' INTO familyhub_crypto_scope_deletion_blocks_v2(scope_id,account_id,head_hash,access_revision,created_at) VALUES(?,?,?,?,?)',[$sid,$account,$head['head_hash']??null,(int)$scope['access_revision'],time()]);
            $this->change('UPDATE familyhub_scopes SET owner_id=? WHERE id=? AND owner_id=?',[$carrier,$sid,$uid]);
            $this->change('UPDATE familyhub_members SET user_id=?,active=0 WHERE scope_id=? AND user_id=? AND account_id=?',[$carrier,$sid,$uid,$account]);
            $this->change('UPDATE familyhub_operations SET user_id=? WHERE scope_id=? AND user_id=?',[$carrier,$sid,$uid]);
            $this->change('UPDATE familyhub_invitations SET creator_id=? WHERE scope_id=? AND creator_id=?',[$carrier,$sid,$uid]);
            $this->change('UPDATE familyhub_invitations SET accepted_by=? WHERE scope_id=? AND accepted_by=?',[$carrier,$sid,$uid]);
        }
        // Mutable private routing/keyring copies are removed. Immutable signed
        // directory entries can embed wrappers and are deliberately retained.
        foreach(['familyhub_crypto_keyring_entries_v2','familyhub_crypto_keyring_entries','familyhub_crypto_protection_v2','familyhub_crypto_scope_observation_events_v2','familyhub_crypto_scope_observations_v2','familyhub_crypto_security_events','familyhub_crypto_reminders_v2','familyhub_account_tokens','familyhub_email_identities','familyhub_push_registrations'] as $table){
            $this->change('DELETE FROM '.$table.' WHERE account_id=?',[$account]);
        }
        $this->change('UPDATE familyhub_crypto_accounts SET keyring=? WHERE account_id=?',['',$account]);
        $this->change('UPDATE familyhub_crypto_devices SET revoked_at=COALESCE(revoked_at,?) WHERE account_id=?',[time(),$account]);
        $this->change('DELETE FROM familyhub_devices WHERE account_id=?',[$account]);
        $this->change('DELETE FROM familyhub_totp_state WHERE user_id=?',[$uid]);
        return $carrier;
    }
}
