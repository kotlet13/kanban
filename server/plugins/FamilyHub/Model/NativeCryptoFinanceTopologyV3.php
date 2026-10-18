<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Encrypted structural snapshot; tokens never disclose child scope IDs. */
class NativeCryptoFinanceTopologyV3
{
    public static function childToken($server, $parent, $child)
    {
        return hash('sha256', "JivieFinanceTopologyChild/v3\n".NativeCryptoCodec::canonical((object)[
            'version'=>3,'serverId'=>$server,'parentScopeId'=>$parent,'childScopeId'=>$child,
        ]));
    }

    public static function baseline($server, $scope, $tokens)
    {
        sort($tokens, SORT_STRING);
        if (count($tokens)>1000 || count(array_unique($tokens))!==count($tokens)) {
            throw new NativeError('crypto_finance_topology_set',409);
        }
        $body=['version'=>3,'serverId'=>$server,'scopeId'=>$scope,'generation'=>0,
            'previousRoot'=>str_repeat('0',64),'childTokens'=>$tokens,'removedTokens'=>[],'count'=>count($tokens)];
        return $body+['root'=>hash('sha256',"JivieFinanceTopology/v3\n".NativeCryptoCodec::canonical((object)$body))];
    }
}
