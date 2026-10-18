<?php
namespace Kanboard\Plugin\FamilyHub\Auth;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAccountTombstoneV2;
class FamilyHubDatabaseAuth extends \Kanboard\Auth\DatabaseAuth
{
    public function authenticate()
    {
        if(!parent::authenticate()){return false;}
        if(NativeCryptoAccountTombstoneV2::user($this->db->getConnection(),$this->userInfo['id'])){$this->userInfo=[];return false;}
        return true;
    }
}
