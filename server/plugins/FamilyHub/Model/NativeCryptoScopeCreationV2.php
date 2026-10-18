<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Exact signed empty origins, distinct from a staged legacy migration. */
class NativeCryptoScopeCreationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    public function write($op, $p, $actor, $proof, $command = null, $authorKey = null)
    {
        $personal = $op === 'crypto2.scope.ensurePersonal';
        $this->fields($p, $personal ? ['id','originProof'] : ['id','kind','originProof'], $personal ? [] : ['parentScopeId','expectedParentAccessRevision','expectedParentAccessBasis']);
        $id = $this->uuid($p['id']);
        $kind = $personal ? 'personal' : $p['kind'];
        if (!in_array($kind, $personal ? ['personal'] : ['organization','household','project'], true)) {
            throw new NativeError('validation_error');
        }
        $account = $actor['user']['account_id'];
        $version = $personal ? 1 : 3;
        $parentId = $p['parentScopeId'] ?? null;
        $publicProof = $this->verifyOrigin($p['originProof'],$command,$authorKey,$id,$kind,$version,$parentId,$actor);
        if ($personal) {
            $existing = $this->one('SELECT scope_id FROM familyhub_personal_scopes WHERE account_id=?', [$account]);
            if ($existing) {
                $origin = $this->one('SELECT authorization FROM familyhub_crypto_scope_origins WHERE scope_id=? AND account_id=?', [$existing['scope_id'],$account]);
                if (!$origin) {
                    throw new NativeError('crypto_migration_required', 409, ['scopeId' => $existing['scope_id']]);
                }
                return ['scope' => (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->catalogScope($existing['scope_id'], $actor)];
            }
        }
        if ($this->one('SELECT id FROM familyhub_scopes WHERE id=?', [$id])) {
            throw new NativeError('crypto_scope_id_conflict', 409);
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $organizationId = null;
        if ($parentId !== null) {
            if ($kind !== 'project' || !isset($p['expectedParentAccessRevision'],$p['expectedParentAccessBasis'])) {
                throw new NativeError('validation_error');
            }
            $parent = $this->scope($this->uuid($parentId), $actor['user']['id'], true, true);
            if (!in_array($parent['kind'], ['organization','household'], true) || (int)$parent['access_policy_version'] !== 3) {
                throw new NativeError('access_migration_required', 409);
            }
            $head = $scopes->current($parentId);
            if (!$head) {
                throw new NativeError('crypto_migration_required', 409, ['scopeId' => $parentId]);
            }
            $scopes->manager($head, $parent, $actor);
            self::guardBusiness($this->pdo, $parentId);
            if ($p['expectedParentAccessRevision'] !== (int)$parent['effective_access_revision'] || NativeCryptoCodec::canonical($p['expectedParentAccessBasis']) !== NativeCryptoCodec::canonical($scopes->accessBasis($parent))) {
                throw new NativeError('crypto_access_changed', 409);
            }
            $organizationId = $parent['kind'] === 'organization' ? $parentId : null;
        } elseif (isset($p['expectedParentAccessRevision']) || isset($p['expectedParentAccessBasis'])) {
            throw new NativeError('validation_error');
        }
        $this->change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,organization_id,required_record_contract,access_policy_version,parent_scope_id,project_root_id) VALUES(?,?,?,?,0,?,?,?,?,?,?)', [$id,$kind,'Encrypted scope',$actor['user']['id'],time(),$organizationId,6,$version,$parentId,$kind === 'project' ? $id : null]);
        $this->change("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)", [$id,$actor['user']['id'],$account]);
        if ($personal) {
            $this->change('INSERT INTO familyhub_personal_scopes VALUES(?,?)', [$account,$id]);
        }
        $this->change('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,1,0,3)', [$id]);
        $this->change("INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')", [$id,$account]);
        $scope = $this->scope($id, $actor['user']['id']);
        $this->change("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,?,'staged')", [$id,(int)$scope['effective_access_revision']]);
        $this->change('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)', [$id,$account,json_encode($publicProof, JSON_THROW_ON_ERROR),time()]);
        (new NativeCryptoLifecycleV2($this->container))->captureBaseline($id,'new',$publicProof);
        return ['scope' => $scopes->catalogScope($id, $actor)];
    }

    private function verifyOrigin($proof, $outer, $authorKey, $scopeId, $kind, $version, $parentId, $actor)
    {
        [$body,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        $this->fields($body,['version','operation','serverId','scopeId','kind','accessPolicyVersion','parentScopeToken','requestId','accountId','deviceId','authorDirectoryHeadHash']);
        $token=$parentId === null ? null : (new NativeCryptoLifecycleV2($this->container))->parentToken($scopeId,$parentId);
        if (!$outer || $body['version']!==2 || $body['operation']!=='crypto2.scope.origin' || $body['serverId']!==$this->serverId() || $body['scopeId']!==$scopeId || $body['kind']!==$kind || $body['accessPolicyVersion']!==$version || $body['parentScopeToken']!==$token || $body['requestId']!==$outer['requestId'] || $body['accountId']!==$actor['user']['account_id'] || $body['deviceId']!==$actor['device']['id']) {
            throw new NativeError('crypto_scope_origin_invalid',403);
        }
        (new NativeCryptoScopeV2($this->container))->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);
        NativeCryptoV2Codec::verify($bytes,$signature,$authorKey,"JivieE2EE/scopeOrigin/v2\n");
        return $proof;
    }

    public static function guardBusiness($pdo, $sid)
    {
        $query = $pdo->prepare('SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?');
        $query->execute([$sid]);
        if ($query->fetchColumn() !== false) {
            $query->closeCursor();
            return;
        }
        $query->closeCursor();
        $query = $pdo->prepare("SELECT m.id FROM familyhub_crypto_scopes s JOIN familyhub_crypto_migrations_v2 m ON m.id=s.migration_id WHERE s.scope_id=? AND s.state='active' AND m.state IN ('committed','retired')");
        $query->execute([$sid]);
        $committed = $query->fetchColumn() !== false;
        $query->closeCursor();
        if (!$committed) {
            throw new NativeError('crypto_migration_required', 409);
        }
    }
}
