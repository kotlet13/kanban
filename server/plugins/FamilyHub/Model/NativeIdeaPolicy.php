<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed board language: no markup, executable paths, SVG or arbitrary URLs. */
class NativeIdeaPolicy extends NativeDatabase
{
    public function validate($p,$scopeId,$current)
    {
        if (!is_array($p) || array_is_list($p) || (strlen(json_encode($p,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR))>786432 || strlen(json_encode($p,JSON_THROW_ON_ERROR))>1048576)) { throw new NativeError('validation_error'); }
        $this->fields($p,['version','id','title','projectId','width','height','elements','revision','createdAt','updatedAt']);
        $this->uuid($p['id']);$this->text($p['title'],800);if (mb_strlen($p['title'])>200 || $p['version']!==1 || !is_int($p['revision']) || $p['revision']<0) { throw new NativeError('validation_error'); }
        $this->number($p['width'],1,16384);$this->number($p['height'],1,16384);
        $policy=new NativeRecordPolicy($this->container);$policy->date($p['createdAt']);$policy->date($p['updatedAt']);
        if ($current && json_decode($current['payload'],true,32,JSON_THROW_ON_ERROR)['createdAt']!==$p['createdAt']) { throw new NativeError('created_at_immutable'); }
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$scopeId]);$root=$scope['project_root_id']??(!empty($scope['organization_id'])?$scopeId:null);
        if ($root!==null && $p['projectId']!==$root) { throw new NativeError('parent_missing'); }
        if ($p['projectId']!==null) { $policy->parentRecord($scopeId,$p['projectId'],'project'); }
        if (!is_array($p['elements']) || !array_is_list($p['elements']) || count($p['elements'])>2000) { throw new NativeError('validation_error'); }
        $ids=[];$parents=[];$images=[];$points=0;
        foreach ($p['elements'] as $e) {
            if (!is_array($e)) { throw new NativeError('validation_error'); }
            $this->fields($e,['id','kind','x','y','width','height','rotation','color','strokeWidth','text','points','parentImageId','asset']);
            $this->uuid($e['id']);if (isset($ids[$e['id']])) { throw new NativeError('validation_error'); }$ids[$e['id']]=true;
            if (!in_array($e['kind'],['text','sticky','image','stroke','rectangle','ellipse','arrow','line'],true)) { throw new NativeError('validation_error'); }
            foreach (['x','y'] as $key) { $this->number($e[$key],-16384,32768); }
            foreach (['width','height'] as $key) { $this->number($e[$key],0,16384); }
            $this->number($e['rotation'],-2*M_PI,2*M_PI);$this->number($e['strokeWidth'],0,1000);if ($e['strokeWidth']<=0) { throw new NativeError('validation_error'); }
            if (!is_int($e['color']) || $e['color']<0 || $e['color']>4294967295) { throw new NativeError('validation_error'); }
            $this->text($e['text'],80000,true);if (mb_strlen($e['text'])>20000) { throw new NativeError('validation_error'); }
            if (!is_array($e['points']) || !array_is_list($e['points']) || count($e['points'])>10000) { throw new NativeError('validation_error'); }
            $points+=count($e['points']);if ($points>50000) { throw new NativeError('validation_error'); }
            foreach ($e['points'] as $point) { if (!is_array($point)) { throw new NativeError('validation_error'); }$this->fields($point,['x','y']);$this->number($point['x'],-16384,32768);$this->number($point['y'],-16384,32768); }
            if ($e['parentImageId']!==null) { $this->uuid($e['parentImageId']);$parents[]=$e['parentImageId']; }
            if ($e['kind']==='image') {
                if ($e['width']<=0 || $e['height']<=0 || $e['parentImageId']!==null || !is_array($e['asset'])) { throw new NativeError('validation_error'); }
                $this->asset($e['asset']);$images[$e['id']]=true;
            } elseif ($e['asset']!==null) { throw new NativeError('validation_error'); }
        }
        if (count($images)>20) { throw new NativeError('validation_error'); }
        foreach ($parents as $id) { if (!isset($images[$id])) { throw new NativeError('parent_missing'); } }
    }
    public function asset($a)
    {
        $this->fields($a,['sha256','mime','size','width','height']);
        if (!is_string($a['sha256']) || !preg_match('/^[a-f0-9]{64}$/D',$a['sha256']) || !in_array($a['mime'],['image/jpeg','image/png'],true)) { throw new NativeError('validation_error'); }
        foreach (['size'=>2097152,'width'=>4096,'height'=>4096] as $k=>$max) { if (!is_int($a[$k]) || $a[$k]<1 || $a[$k]>$max) { throw new NativeError('validation_error'); } }
    }
    private function number($n,$min,$max) { if ((!is_int($n) && !is_float($n)) || !is_finite((float)$n) || $n<$min || $n>$max) { throw new NativeError('validation_error'); } }
}
