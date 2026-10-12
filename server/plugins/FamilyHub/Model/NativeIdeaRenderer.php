<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed evidence language rasterizer; raw uploaded SVG/HTML is never emitted. */
class NativeIdeaRenderer extends NativeDatabase
{
    private function point($e,$parent,$x,$y,$scale)
    {
        $angle=$e['rotation'];$dx=$x-$e['width']/2;$dy=$y-$e['height']/2;
        $x=$e['x']+$e['width']/2+$dx*cos($angle)-$dy*sin($angle);$y=$e['y']+$e['height']/2+$dx*sin($angle)+$dy*cos($angle);
        if ($parent) { $x*=$parent['width'];$y*=$parent['height'];$dx=$x-$parent['width']/2;$dy=$y-$parent['height']/2;$angle=$parent['rotation'];
            $x=$parent['x']+$parent['width']/2+$dx*cos($angle)-$dy*sin($angle);$y=$parent['y']+$parent['height']/2+$dx*sin($angle)+$dy*cos($angle);
        }return [(int)round($x*$scale),(int)round($y*$scale)];
    }
    public function reportImage($report)
    {
        if (!function_exists('imagecreatetruecolor') || $report['snapshot']===null) { return null; }
        $snapshot=json_decode($report['snapshot'],true,32,JSON_THROW_ON_ERROR);$p=$snapshot['evidence']['board']??null;
        if (!$p || ($snapshot['subject']['type']??'')!=='idea') { return null; }
        $scale=min(1,1200/$p['width'],900/$p['height']);$w=max(1,(int)ceil($p['width']*$scale));$h=max(1,(int)ceil($p['height']*$scale));$canvas=imagecreatetruecolor($w,$h);
        $white=imagecolorallocate($canvas,255,255,255);imagefill($canvas,0,0,$white);$images=[];
        foreach ($p['elements'] as $e) { if ($e['kind']==='image') { $images[$e['id']]=$e; } }
        foreach ($p['elements'] as $e) {
            $parent=$images[$e['parentImageId']??'']??null;$c=$e['color'];$color=imagecolorallocatealpha($canvas,($c>>16)&255,($c>>8)&255,$c&255,127-(int)round((($c>>24)&255)*127/255));imagesetthickness($canvas,max(1,min(100,(int)round($e['strokeWidth']*($parent?$parent['width']:1)*$scale))));
            if ($e['kind']==='image') {
                $r=$this->one('SELECT a.* FROM familyhub_idea_assets a JOIN familyhub_idea_report_assets r ON r.scope_id=a.scope_id AND r.board_id=a.board_id AND r.sha256=a.sha256 WHERE r.report_id=? AND a.sha256=?',[$report['id'],$e['asset']['sha256']]);
                if ($r) {
                    $img=@imagecreatefromstring((new NativeIdeaAssetService($this->container))->bytes($r));
                    if ($img) {
                        $ew=max(1,(int)round($e['width']*$scale));$eh=max(1,(int)round($e['height']*$scale));$resize=min(1,1800/max($ew,$eh));$tw=max(1,(int)round($ew*$resize));$th=max(1,(int)round($eh*$resize));$tile=imagecreatetruecolor($tw,$th);imagealphablending($tile,false);imagesavealpha($tile,true);$clear=imagecolorallocatealpha($tile,0,0,0,127);imagefill($tile,0,0,$clear);imagecopyresampled($tile,$img,0,0,0,0,$tw,$th,imagesx($img),imagesy($img));imagedestroy($img);
                        if ($e['rotation']!=0) { $rotated=imagerotate($tile,-rad2deg($e['rotation']),$clear);imagedestroy($tile);$tile=$rotated; }
                        $rw=max(1,(int)round(imagesx($tile)/$resize));$rh=max(1,(int)round(imagesy($tile)/$resize));$x=(int)round(($e['x']+$e['width']/2)*$scale-$rw/2);$y=(int)round(($e['y']+$e['height']/2)*$scale-$rh/2);
                        // Only the visible intersection is resampled, bounding work to the board viewport.
                        $left=max(0,$x);$top=max(0,$y);$right=min($w,$x+$rw);$bottom=min($h,$y+$rh);
                        if ($right>$left && $bottom>$top) { $sx=(int)(($left-$x)*imagesx($tile)/$rw);$sy=(int)(($top-$y)*imagesy($tile)/$rh);$sw=max(1,(int)(($right-$left)*imagesx($tile)/$rw));$sh=max(1,(int)(($bottom-$top)*imagesy($tile)/$rh));imagecopyresampled($canvas,$tile,$left,$top,$sx,$sy,$right-$left,$bottom-$top,$sw,$sh); }imagedestroy($tile);
                    }
                }continue;
            }
            if (in_array($e['kind'],['rectangle','sticky'],true)) {
                $points=[];foreach([[0,0],[$e['width'],0],[$e['width'],$e['height']],[0,$e['height']]] as $xy){$points=array_merge($points,$this->point($e,$parent,$xy[0],$xy[1],$scale));}
                if($e['kind']==='sticky'){imagefilledpolygon($canvas,$points,$color);}else{imagepolygon($canvas,$points,$color);}
            } elseif ($e['kind']==='ellipse') { $points=[];for($n=0;$n<64;$n++){$angle=2*M_PI*$n/64;$points=array_merge($points,$this->point($e,$parent,$e['width']/2*(1+cos($angle)),$e['height']/2*(1+sin($angle)),$scale));}imagepolygon($canvas,$points,$color); }
            elseif (in_array($e['kind'],['arrow','line'],true)) { $from=$this->point($e,$parent,0,0,$scale);$to=$this->point($e,$parent,$e['width'],$e['height'],$scale);imageline($canvas,$from[0],$from[1],$to[0],$to[1],$color);if($e['kind']==='arrow'){$angle=atan2($to[1]-$from[1],$to[0]-$from[0]);foreach([-0.5,0.5] as $turn){imageline($canvas,$to[0],$to[1],(int)round($to[0]-10*cos($angle+$turn)),(int)round($to[1]-10*sin($angle+$turn)),$color);}} }
            elseif ($e['kind']==='stroke') { $previous=null;foreach($e['points'] as $point){$next=$this->point($e,$parent,$point['x'],$point['y'],$scale);if($previous){imageline($canvas,$previous[0],$previous[1],$next[0],$next[1],$color);}$previous=$next;} }
            if ($e['text']!=='') { $origin=$this->point($e,$parent,0,0,$scale);$ew=$e['width']*($parent?$parent['width']:1)*$scale;$eh=$e['height']*($parent?$parent['height']:1)*$scale;$ink=$e['kind']==='sticky'?imagecolorallocate($canvas,25,25,25):$color;$lines=explode("\n",wordwrap($e['text'],max(1,min(200,(int)($ew/7))),"\n",true));foreach(array_slice($lines,0,max(1,min(100,(int)($eh/14)))) as $n=>$line){imagestring($canvas,2,$origin[0]+3,$origin[1]+3+$n*14,$line,$ink);} }
        }
        ob_start();imagepng($canvas);$png=ob_get_clean();imagedestroy($canvas);return 'data:image/png;base64,'.base64_encode($png);
    }
}
