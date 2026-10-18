<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Private immutable images; chunks never generate notifications or a public URL. */
class NativeIdeaAssetService extends NativeDatabase
{
    const CHUNK=262144;
    public static function available()
    {
        foreach(['gd_info','imagecreatefromstring','imagecreatetruecolor','imagepng','imagejpeg','imagerotate','imagecopyresampled','imagestring','imagecolorallocatealpha'] as $fn){if(!function_exists($fn))return false;}
        $info=gd_info();return !empty($info['JPEG Support'])&&!empty($info['PNG Support']);
    }
    public function execute($op,array $p)
    {
        $action=substr($op,12);if ($action==='download') { $action='get'; }
        if (!in_array($action,['begin','chunk','complete','get'],true)) { throw new NativeError('unsupported_operation',404); }
        $this->rate([['idea-assets-ip:'.$this->ip,1200,60]]);
        return $this->transaction(function()use($action,$p){
            $user=$this->actor()['user'];$this->fields($p,['scopeId','boardId','sha256'],match($action){'begin'=>['mime','size','width','height'],'chunk'=>['offset','data','dataBase64'],'get'=>['offset','limit'],default=>[]});
            $sid=$this->uuid($p['scopeId']);$bid=$this->uuid($p['boardId']);$sha=$p['sha256'];
            if (!is_string($sha) || !preg_match('/^[a-f0-9]{64}$/D',$sha)) { throw new NativeError('validation_error'); }
            $scope=$this->scope($sid,$user['id'],$action!=='get');
            if($action!=='get' && !self::available()){throw new NativeError('ideas_unavailable',503);}
            $row=$this->one('SELECT * FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?'.$this->lockSuffix(),[$sid,$bid,$sha]);
            $board=$this->one("SELECT payload,deleted,type FROM familyhub_records WHERE scope_id=? AND id=?",[$sid,$bid]);
            if ($board && ($board['type']!=='idea' || (int)$board['deleted'])) { throw new NativeError('asset_unavailable',404); }
            $referenced=$board && $this->references(json_decode($board['payload'],true,32,JSON_THROW_ON_ERROR),$sha);
            if ($action==='begin') {
                $a=array_intersect_key($p,array_flip(['sha256','mime','size','width','height']));(new NativeIdeaPolicy($this->container))->asset($a);
                if ($row) { if ($row['owner_account_id']!==$user['account_id'] && !$referenced) { throw new NativeError('asset_unavailable',404); }$this->matches($row,$a);return $this->wire($row); }
                $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND published=0',[$sid,$bid]);
                $quota=$this->one('SELECT COALESCE(SUM(size),0) AS bytes FROM familyhub_idea_assets WHERE owner_account_id=? AND published=0',[$user['account_id']]);if ((int)$quota['bytes']+$a['size']>67108864) { throw new NativeError('asset_staging_limit',422); }
                if ((int)$count['n']>=20) { throw new NativeError('asset_limit',422); }
                $this->change('INSERT INTO familyhub_idea_assets(scope_id,board_id,sha256,owner_account_id,mime,size,width,height,data,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$sid,$bid,$sha,$user['account_id'],$a['mime'],$a['size'],$a['width'],$a['height'],'',time(),time()]);
                return $this->wire($this->one('SELECT * FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$sid,$bid,$sha]));
            }
            if (!$row || ($row['owner_account_id']!==$user['account_id'] && (!$referenced || !(int)$row['complete']))) { throw new NativeError('asset_unavailable',404); }
            if ($action==='get') {
                if (!(int)$row['complete'] || (!$referenced && $row['owner_account_id']!==$user['account_id'])) { throw new NativeError('asset_unavailable',404); }
                $offset=$p['offset']??0;$limit=$p['limit']??self::CHUNK;
                if (!is_int($offset) || $offset<0 || $offset>(int)$row['size'] || !is_int($limit) || $limit<1 || $limit>self::CHUNK) { throw new NativeError('validation_error'); }
                $bytes=$this->bytes($row);$part=substr($bytes,$offset,$limit);$data=base64_encode($part);
                return array_replace($this->wire($row),['offset'=>$offset,'dataBase64'=>$data,'data'=>$data,'total'=>(int)$row['size'],'done'=>$offset+strlen($part)===(int)$row['size']]);
            }
            // A different member may reference a published image but may never alter its upload.
            if ($row['owner_account_id']!==$user['account_id']) { throw new NativeError('asset_unavailable',404); }
            if ($action==='chunk') {
                $offset=$p['offset']??null;$encoded=$p['dataBase64']??$p['data']??null;
                if (!is_int($offset) || $offset<0 || !is_string($encoded) || strlen($encoded)>349528) { throw new NativeError('validation_error'); }
                if (isset($p['data'],$p['dataBase64']) && $p['data']!==$p['dataBase64']) { throw new NativeError('validation_error'); }
                $bytes=base64_decode($encoded,true);if ($bytes===false || strlen($bytes)<1 || strlen($bytes)>self::CHUNK || base64_encode($bytes)!==$encoded || $offset+strlen($bytes)>(int)$row['size']) { throw new NativeError('validation_error'); }
                $existing=(int)$row['complete']?$this->bytes($row):base64_decode($row['data'],true);
                if ($offset<(int)$row['received'] || (int)$row['complete']) { if (!hash_equals(substr($existing,$offset,strlen($bytes)),$bytes)) { throw new NativeError('asset_chunk_conflict',409); }return $this->wire($row); }
                if ($offset!==(int)$row['received']) { throw new NativeError('asset_offset',409,['offset'=>(int)$row['received']]); }
                $next=$existing.$bytes;$this->change('UPDATE familyhub_idea_assets SET data=?,received=?,updated_at=? WHERE scope_id=? AND board_id=? AND sha256=?',[base64_encode($next),strlen($next),time(),$sid,$bid,$sha]);$row['received']=strlen($next);return $this->wire($row);
            }
            if ((int)$row['complete']) { $this->bytes($row);return $this->wire($row); }
            $bytes=base64_decode($row['data'],true);$this->validateBytes($bytes,$row);
            $path=$this->path($row);$dir=dirname($path);if (!is_dir($dir) && !mkdir($dir,0700,true) && !is_dir($dir)) { throw new NativeError('asset_storage_unavailable',503); }
            if (is_file($path)) { $this->validateBytes(file_get_contents($path),$row); }
            if (!is_file($path)) { $temp=tempnam($dir,'.upload-');chmod($temp,0600);if (file_put_contents($temp,$bytes)!==strlen($bytes) || !rename($temp,$path)) { @unlink($temp);throw new NativeError('asset_storage_unavailable',503); } }
            $this->change('UPDATE familyhub_idea_assets SET complete=1,data=NULL,updated_at=? WHERE scope_id=? AND board_id=? AND sha256=?',[time(),$sid,$bid,$sha]);$row['complete']=1;return $this->wire($row);
        });
    }
    private function wire($r) { return ['sha256'=>$r['sha256'],'mime'=>$r['mime'],'size'=>(int)$r['size'],'width'=>(int)$r['width'],'height'=>(int)$r['height'],'offset'=>(int)$r['received'],'complete'=>(bool)$r['complete']]; }
    private function path($r) { return DATA_DIR.'/familyhub/ideas/'.hash('sha256',$r['scope_id'].':'.$r['board_id']).'/'.$r['sha256']; }
    public function bytes($r) { $bytes=@file_get_contents($this->path($r));if ($bytes===false) { throw new NativeError('asset_storage_unavailable',503); }$this->validateBytes($bytes,$r,false);return $bytes; }
    /** Reuse the closed normalized image grammar for explicitly disclosed evidence. */
    public function validateDisclosureBytes($bytes, $descriptor)
    {
        $this->validateBytes($bytes, $descriptor, true);
    }
    private function validateBytes($bytes,$r,$decode=true)
    {
        if (!is_string($bytes) || strlen($bytes)!==(int)$r['size'] || !hash_equals($r['sha256'],hash('sha256',$bytes))) { throw new NativeError('asset_integrity',422); }
        if ($decode && !function_exists('imagecreatefromstring')) { throw new NativeError('asset_decoder_unavailable',503); }
        $image=@getimagesizefromstring($bytes);$mime=class_exists('finfo')?(new \finfo(FILEINFO_MIME_TYPE))->buffer($bytes):($image['mime']??null);
        if (!$image || $mime!==$r['mime'] || ($image['mime']??'')!==$r['mime'] || $image[0]!=(int)$r['width'] || $image[1]!=(int)$r['height']) { throw new NativeError('asset_integrity',422); }
        // Decode validates compressed content; refuse appended/polyglot bytes and metadata-bearing PNG chunks.
        if ($mime==='image/png') {
            $offset=8;$end=false;while ($offset<strlen($bytes)) { if ($offset+12>strlen($bytes)) { throw new NativeError('asset_integrity',422); }$length=unpack('N',substr($bytes,$offset,4))[1];$kind=substr($bytes,$offset+4,4);
                if (!in_array($kind,['IHDR','PLTE','IDAT','IEND','tRNS','pHYs'],true) || $length>2097152 || $offset+$length+12>strlen($bytes)) { throw new NativeError('asset_not_normalized',422); }
                $offset+=$length+12;if ($kind==='IEND') { $end=true;break; }
            }if (!$end || $offset!==strlen($bytes)) { throw new NativeError('asset_integrity',422); }
        }
        else {
            if (substr($bytes,0,2)!=="\xff\xd8" || substr($bytes,-2)!=="\xff\xd9") { throw new NativeError('asset_integrity',422); }
            $offset=2;while($offset<strlen($bytes)-2){if (ord($bytes[$offset])!==255 || $offset+4>strlen($bytes)) { throw new NativeError('asset_integrity',422); }$marker=ord($bytes[$offset+1]);
                if ($marker===0xda) { break; } // Entropy-coded bytes contain escaped marker values.
                if (($marker>=0xe1 && $marker<=0xef) || $marker===0xfe) { throw new NativeError('asset_not_normalized',422); }
                $length=unpack('n',substr($bytes,$offset+2,2))[1];if ($length<2 || $offset+$length+2>strlen($bytes)) { throw new NativeError('asset_integrity',422); }$offset+=$length+2;
            }
        }
        if ($decode && function_exists('imagecreatefromstring')) { $decoded=@imagecreatefromstring($bytes);if (!$decoded) { throw new NativeError('asset_integrity',422); }imagedestroy($decoded); }
    }
    private function matches($r,$a) { foreach (['sha256','mime','size','width','height'] as $k) { if ((string)$r[$k]!== (string)$a[$k]) { throw new NativeError('asset_metadata_conflict',409); } } }
    public function references($p,$sha) { foreach ($p['elements']??[] as $e) { if (($e['kind']??'')==='image' && ($e['asset']['sha256']??'')===$sha) { return true; } }return false; }
    public function publish($sid,$bid,$p,$account)
    {
        foreach ($p['elements'] as $e) { if ($e['kind']!=='image') { continue; }$a=$e['asset'];$r=$this->one('SELECT * FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$sid,$bid,$a['sha256']]);
            if (!$r || !(int)$r['complete'] || ($r['owner_account_id']!==$account && !(int)$r['published'])) { throw new NativeError('asset_unavailable',404); }$this->matches($r,$a);$this->bytes($r);
            $this->change('UPDATE familyhub_idea_assets SET published=1,updated_at=? WHERE scope_id=? AND board_id=? AND sha256=?',[time(),$sid,$bid,$a['sha256']]);
        }
    }
    /** Copy the exact private images when an inline project graph gains its own scope. */
    public function relocate($source,$target,$boardId,$p)
    {
        $seen=[];foreach($p['elements'] as $e){if($e['kind']!=='image' || isset($seen[$e['asset']['sha256']]))continue;$seen[$e['asset']['sha256']]=true;
            $r=$this->one('SELECT * FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$source,$boardId,$e['asset']['sha256']]);
            if(!$r || !(int)$r['complete']){throw new NativeError('asset_unavailable',404);}$this->matches($r,$e['asset']);$bytes=$this->bytes($r);$copy=$r;$copy['scope_id']=$target;$copy['published']=1;$copy['updated_at']=time();
            $path=$this->path($copy);$dir=dirname($path);if(!is_dir($dir)&&!mkdir($dir,0700,true)&&!is_dir($dir)){throw new NativeError('asset_storage_unavailable',503);}
            if(is_file($path)){$this->validateBytes(file_get_contents($path),$copy);}else{$temp=tempnam($dir,'.upload-');chmod($temp,0600);if(file_put_contents($temp,$bytes)!==strlen($bytes)||!rename($temp,$path)){@unlink($temp);throw new NativeError('asset_storage_unavailable',503);}}
            $columns=array_keys($copy);$this->change('INSERT INTO familyhub_idea_assets('.implode(',',$columns).') VALUES('.implode(',',array_fill(0,count($columns),'?')).')',array_values($copy));
        }
    }
    public function evidence($sid,$bid,$p)
    {
        $assets=[];foreach ($p['elements'] as $e) { if ($e['kind']!=='image') { continue; }$a=$e['asset'];if (isset($assets[$a['sha256']])) { continue; }
            $r=$this->one('SELECT * FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=? AND complete=1',[$sid,$bid,$a['sha256']]);if (!$r) { throw new NativeError('asset_unavailable',404); }$this->matches($r,$a);$this->bytes($r);$assets[$a['sha256']]=$a;
        }return array_values($assets);
    }
    public function retainReport($reportId,$sid,$bid,$assets) { foreach ($assets as $a) { $this->change('INSERT INTO familyhub_idea_report_assets VALUES(?,?,?,?)',[$reportId,$sid,$bid,$a['sha256']]); } }
    /** Bounded cleanup only after 7 days, preserving any board or report reference. */
    public function cleanup()
    {
        $cryptoLease=\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)?NativeCryptoMaintenanceLease::acquire():null;
        if(NativeCryptoFence::cleanupPaused($this->pdo)){return 0;}
        (new NativeScopeLifecycleService($this->container))->finishFiles();
        $removed=$this->transaction(function(){ $removed=0;foreach ($this->many('SELECT * FROM familyhub_idea_assets WHERE updated_at<? ORDER BY updated_at LIMIT 100',[time()-7*86400]) as $r) {
            $board=$this->one("SELECT payload FROM familyhub_records WHERE scope_id=? AND id=? AND type='idea' AND deleted=0",[$r['scope_id'],$r['board_id']]);
            if (($board && $this->references(json_decode($board['payload'],true,32,JSON_THROW_ON_ERROR),$r['sha256'])) || $this->one('SELECT report_id FROM familyhub_idea_report_assets WHERE scope_id=? AND board_id=? AND sha256=? LIMIT 1',[$r['scope_id'],$r['board_id'],$r['sha256']])) { $this->change('UPDATE familyhub_idea_assets SET updated_at=? WHERE scope_id=? AND board_id=? AND sha256=?',[time(),$r['scope_id'],$r['board_id'],$r['sha256']]);continue; }
            if (is_file($this->path($r)) && !unlink($this->path($r))) { continue; }
            $this->change('DELETE FROM familyhub_idea_assets WHERE scope_id=? AND board_id=? AND sha256=?',[$r['scope_id'],$r['board_id'],$r['sha256']]);$removed++;
        }return $removed; });
        return $removed+$this->cleanupUntrackedFiles();
    }
    /** Resume a bounded directory scan, including files left by an interrupted graph relocation. */
    private function cleanupUntrackedFiles()
    {
        $root=DATA_DIR.'/familyhub/ideas';if(!is_dir($root))return 0;$cursorFile=$root.'/.cleanup-cursor';$cursor=is_file($cursorFile)?json_decode(file_get_contents($cursorFile),true):null;$cursor=is_array($cursor)?$cursor:['directory'=>'','file'=>''];
        $directories=glob($root.'/*',GLOB_ONLYDIR)?:[];sort($directories,SORT_STRING);$inspected=0;$removed=0;$last=['directory'=>'','file'=>''];$finished=true;
        foreach($directories as $dir){$directory=basename($dir);if(!preg_match('/^[a-f0-9]{64}$/D',$directory)||is_link($dir)||strcmp($directory,$cursor['directory'])<0)continue;
            $files=glob($dir.'/*')?:[];$temporary=glob($dir.'/.upload-*')?:[];$files=array_merge($files,$temporary);sort($files,SORT_STRING);
            foreach($files as $file){$name=basename($file);if($directory===$cursor['directory']&&strcmp($name,$cursor['file'])<=0)continue;$last=['directory'=>$directory,'file'=>$name];$inspected++;
                if(!is_link($file)&&is_file($file)&&filemtime($file)<time()-7*86400){$known=false;if(preg_match('/^[a-f0-9]{64}$/D',$name)){foreach($this->many('SELECT scope_id,board_id FROM familyhub_idea_assets WHERE sha256=?',[$name]) as $r){if(hash('sha256',$r['scope_id'].':'.$r['board_id'])===$directory){$known=true;break;}}}elseif(!str_starts_with($name,'.upload-')){$known=true;}
                    if(!$known&&@unlink($file))$removed++;
                }
                if($inspected>=100){$finished=false;break 2;}
            }
        }
        if($finished)$last=['directory'=>'','file'=>''];$temp=tempnam($root,'.cursor-');if($temp!==false){chmod($temp,0600);file_put_contents($temp,json_encode($last,JSON_THROW_ON_ERROR));if(!rename($temp,$cursorFile))@unlink($temp);}return $removed;
    }

}
