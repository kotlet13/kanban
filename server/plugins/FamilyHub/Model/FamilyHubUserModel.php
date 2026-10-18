<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Preserve scoped immutable evidence before the core users FK cascade. */
class FamilyHubUserModel extends \Kanboard\Model\UserModel
{
    private function tombstone($id){return NativeCryptoAccountTombstoneV2::user($this->db->getConnection(),$id);}
    public function update(array $values)
    {
        if(isset($values['id'])&&$this->tombstone($values['id'])){return false;}
        return parent::update($values);
    }
    public function isValidSession($userID,$sessionRole,$credentialsFingerprint='')
    {
        return !$this->tombstone($userID)&&parent::isValidSession($userID,$sessionRole,$credentialsFingerprint);
    }
    public function isActive($id){return !$this->tombstone($id)&&parent::isActive($id);}
    public function getById($id){return $this->tombstone($id)?[]:parent::getById($id);}
    public function getByUsername($name){$r=parent::getByUsername($name);return $r&&$this->tombstone($r['id'])?[]:$r;}
    public function getByEmail($email){$r=parent::getByEmail($email);return $r&&$this->tombstone($r['id'])?[]:$r;}
    public function getByToken($token){$r=parent::getByToken($token);return $r&&$this->tombstone($r['id'])?[]:$r;}
    public function getByExternalId($column,$id){$r=parent::getByExternalId($column,$id);return $r&&$this->tombstone($r['id'])?[]:$r;}
    public function remove($id)
    {
        if($this->tombstone($id)){return false;}
        // The helper owns a single SQL transaction including core bookkeeping;
        // the core model's nested commit/avatar-first path is not used for E2EE.
        $service=new NativeCryptoAccountDeletionV2($this->container);
        if($service->hasCryptoUser($id)){return $service->removeFromCore($id);}
        return parent::remove($id);
    }
}
