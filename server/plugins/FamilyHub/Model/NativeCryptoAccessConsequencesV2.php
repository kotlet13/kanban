<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Exact finite invitation consequences; no recipients, labels or mail state. */
class NativeCryptoAccessConsequencesV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const CAPACITY = 65536;

    private function token($scope, $root)
    {
        return hash('sha256', "JivieAccessPortion/v2\n".NativeCryptoCodec::canonical((object)[
            'version'=>2,'serverId'=>$this->serverId(),'scopeId'=>$scope,'rootScopeId'=>$root]));
    }

    public function collect($root, $requestId)
    {
        $this->uuid($root);
        $this->uuid($requestId);
        $leaves=[];
        $scoped=[];
        $after='';
        do {
            $scopes=$this->many('SELECT id FROM familyhub_scopes WHERE (id=? OR parent_scope_id=? OR organization_id=?) AND deleted_at IS NULL AND id>? ORDER BY id LIMIT 20',[$root,$root,$root,$after]);
            foreach ($scopes as $scope) {
                $sid=$scope['id'];
                $after=$sid;
                $token=$this->token($sid,$root);
                $scoped[$sid]=[];
                foreach (['legacy','crypto'] as $kind) {
                    $cursor='';
                    do {
                        if ($kind==='legacy') {
                            // Installed bridges continue canonically. Their
                            // original captured source remains historical.
                            $rows=$this->many("SELECT i.id FROM familyhub_invitations i WHERE i.scope_id=? AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.id>? AND NOT EXISTS (SELECT 1 FROM familyhub_crypto_invitation_routes_v3 r JOIN familyhub_crypto_invitations_v2 c ON c.id=r.invitation_id AND c.scope_id=r.scope_id AND c.token_hash=r.token_hash WHERE r.invitation_id=i.id AND r.scope_id=i.scope_id AND r.token_hash=i.token_hash) ORDER BY i.id LIMIT 50",[$sid,$cursor]);
                        } else {
                            $rows=$this->many("SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND state IN ('pending','accepted') AND id>? ORDER BY id LIMIT 50",[$sid,$cursor]);
                        }
                        foreach ($rows as $invitation) {
                            $cursor=$invitation['id'];
                            $this->uuid($cursor);
                            $entry=['version'=>2,'serverId'=>$this->serverId(),'requestId'=>$requestId,
                                'scopeToken'=>$token,'kind'=>$kind,'id'=>$cursor];
                            $digest=hash('sha256',"JivieAccessInvitationConsequenceEntry/v2\n".NativeCryptoCodec::canonical((object)$entry));
                            if (isset($leaves[$digest])) throw new NativeError('crypto_access_consequence_duplicate',409);
                            if (count($leaves)>=self::CAPACITY) throw new NativeError('crypto_access_consequence_capacity',409);
                            $leaves[$digest]=['scopeId'=>$sid,'entry'=>$entry];
                            $scoped[$sid][$digest]=['kind'=>$kind,'id'=>$cursor];
                        }
                    } while (count($rows)===50);
                }
            }
        } while (count($scopes)===20);
        ksort($leaves,SORT_STRING);
        $context=['version'=>2,'serverId'=>$this->serverId(),'scopeId'=>$root,'requestId'=>$requestId];
        $stream="JivieAccessInvitationConsequences/v2\n".NativeCryptoCodec::canonical((object)$context)."\n";
        foreach ($leaves as $digest=>$unused) $stream.=$digest."\n";
        $own=[];
        foreach ($scoped as $sid=>$entries) {
            ksort($entries,SORT_STRING);
            $header=['version'=>2,'serverId'=>$this->serverId(),'requestId'=>$requestId,'scopeToken'=>$this->token($sid,$root)];
            $bytes="JivieAccessInvitationScopeConsequences/v2\n".NativeCryptoCodec::canonical((object)$header)."\n";
            foreach ($entries as $digest=>$unused) $bytes.=$digest."\n";
            $own[$sid]=['version'=>1,'invitationCount'=>count($entries),'invitationSetHash'=>hash('sha256',$bytes)];
        }
        return ['snapshot'=>['version'=>1,'kind'=>'pendingInvitationRevocation','scopeId'=>$root,
            'invitationCount'=>count($leaves),'invitationSetHash'=>hash('sha256',$stream)],
            'leaves'=>$leaves,'scoped'=>$own,'entries'=>$scoped];
    }
}
