<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed observation exception for an account-global monotone counter row.
 * Never applicable to content, receipts, settings, read states or money. */
final class NativeCryptoCaptureInboxStateV3
{
    public static function observe($accountId, $typedRow)
    {
        if ($typedRow !== null) self::snapshot($accountId,$typedRow,$typedRow);
        return ['version'=>3,'accountId'=>$accountId,'state'=>$typedRow===null?'absent':'present','typedRow'=>$typedRow];
    }

    public static function prepared($accountId, $envelope)
    {
        if (!is_array($envelope) || count($envelope)!==4
            || array_diff(array_keys($envelope),['version','accountId','state','typedRow'])
            || $envelope['version']!==3 || $envelope['accountId']!==$accountId) self::fail();
        if ($envelope['state']==='absent' && $envelope['typedRow']===null) return null;
        if ($envelope['state']!=='present' || !is_array($envelope['typedRow'])) self::fail();
        $row=(object)$envelope['typedRow'];
        return self::snapshot($accountId,$row,$row);
    }

    public static function snapshot($accountId, $current, $baseline)
    {
        $now = self::values($current);
        $old = self::values($baseline);
        if ($now['account_id'] !== $accountId || $old['account_id'] !== $accountId
            || $now['sequence'] < $old['sequence']
            || $now['visibility_revision'] < $old['visibility_revision']
            || isset($old['configuration_revision'])
                && (!isset($now['configuration_revision']) || $now['configuration_revision'] < $old['configuration_revision'])) {
            throw new NativeError('crypto_capture_inbox_state_conflict',409);
        }
        return $baseline;
    }

    private static function values($typedRow)
    {
        if (!is_object($typedRow)) self::fail();
        $row = get_object_vars($typedRow);
        // Preserve signed pre-schema-22 baselines exactly; new captures retain
        // the additional monotone configuration counter without dropping it.
        $required = ['account_id','sequence','visibility_revision'];
        if (array_diff($required, array_keys($row))
            || array_diff(array_keys($row), [...$required, 'configuration_revision'])) self::fail();
        $out=[];
        foreach ($row as $key=>$cell) {
            if (is_object($cell)) $cell=get_object_vars($cell);
            if (!is_array($cell) || count($cell)!==2 || !isset($cell['type'],$cell['valueBase64'])
                || !is_string($cell['type']) || !is_string($cell['valueBase64'])) self::fail();
            $value=base64_decode($cell['valueBase64'],true);
            if ($value===false || base64_encode($value)!==$cell['valueBase64']) self::fail();
            if ($key==='account_id') {
                if (!preg_match('/^(?:text|(?:var)?char\(36\))$/iD',$cell['type'])) self::fail();
                if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$value)) self::fail();
                $out[$key]=$value;
            } else {
                if (!preg_match('/^(?:integer|bigint(?:\([0-9]+\))?(?: unsigned)?)$/iD',$cell['type'])) self::fail();
                if (!preg_match('/^(?:0|[1-9][0-9]{0,15})$/D',$value)
                    || strlen($value)>16 || strlen($value)===16 && strcmp($value,'9007199254740991')>0) self::fail();
                $out[$key]=(int)$value;
            }
        }
        return $out;
    }

    private static function fail() { throw new NativeError('crypto_capture_inbox_state_snapshot',409); }
}
