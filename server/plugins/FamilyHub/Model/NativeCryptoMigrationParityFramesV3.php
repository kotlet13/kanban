<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Reconstruct the complete framed stream from server-private frozen sources.
 * All callbacks are closed internal adapters, never HTTP-supplied leaf lists.
 * The server checks ciphertext/commitment coverage, not decrypted semantics. */
final class NativeCryptoMigrationParityFramesV3
{
    public static function compute($header,callable $sources,callable $canonical,callable $artifact,array $sections)
    {
        $frames=(function()use($sources,$canonical,$artifact,$sections){
            foreach($sources() as $source){
                $binding=NativeCryptoCaptureV3::binding($source['binding']);
                $adapter=NativeCryptoMigrationBusinessParityV3::sourceAdapter($source['context']['sourceTable']);
                $primary=null;$companions=[];
                if($adapter==='canonical'){
                    $candidate=$canonical($source,true);
                    $primary=$candidate['recordProofHash'];$companions=$candidate['companionProofHashes'];
                    $hash=NativeCryptoMigrationBusinessParityV3::canonicalArtifact($candidate);
                }elseif(in_array($adapter,['sourceContext','moderationDisclosure'],true)){
                    $hash=hash('sha256',"JivieMigrationPrivateArtifact/v3\n".NativeCryptoCodec::canonical((object)['version'=>3,'adapter'=>$adapter,'binding'=>(object)$binding]));
                }elseif($adapter==='canonicalFile'){
                    $file=$artifact($source,$adapter);$hash=$file['artifactHash'];
                }else{$hash=$artifact($source,$adapter);}
                yield ['tag'=>'binding','value'=>['binding'=>$binding,'adapter'=>$adapter,'primaryRecordProofHash'=>$primary,'companionProofHashes'=>$companions,'artifactHash'=>$hash]];
            }
            foreach(['file','proofBlob'] as $tag){
                foreach($sources() as $source){
                    $adapter=NativeCryptoMigrationBusinessParityV3::sourceAdapter($source['context']['sourceTable']);
                    if($adapter==='canonicalFile'&&$tag==='file'){
                        $result=$artifact($source,$adapter);$object=$result['object'];$d=$object['blob'];
                        yield ['tag'=>'file','value'=>['bindingId'=>$source['binding']['bindingId'],'id'=>$d['id'],'kind'=>'ideaAsset','plainSize'=>$object['plainSize'],'cipherSize'=>$d['cipherSize'],'cipherSha256'=>$d['cipherSha256'],'manifestHash'=>hash('sha256',NativeCryptoCodec::base64($d['manifestBase64'],16384))]];
                        continue;
                    }
                    if($adapter!=='canonical')continue;
                    $b=$canonical($source,false);$files=[];
                    if($tag==='file')foreach($b['objects'] as $object){
                        if($object['kind']==='ideaAsset')continue;
                        $d=$object['blob'];$files[]=['bindingId'=>$b['bindingId'],'id'=>$d['id'],'kind'=>$object['kind'],'plainSize'=>$object['plainSize'],'cipherSize'=>$d['cipherSize'],'cipherSha256'=>$d['cipherSha256'],'manifestHash'=>hash('sha256',NativeCryptoCodec::base64($d['manifestBase64'],16384))];
                    }
                    if($tag==='proofBlob' && $b['witness']!==null){
                        $w=$b['witness'];$manifestHash=hash('sha256',NativeCryptoCodec::base64($w['manifestBase64'],16384));
                        foreach($w['segments'] as $segment)$files[]=['bindingId'=>$b['bindingId'],'id'=>$segment['id'],'kind'=>'typedWitness','plainSize'=>null,'cipherSize'=>$segment['size'],'cipherSha256'=>$segment['sha256'],'manifestHash'=>$manifestHash];
                    }
                    usort($files,static fn($a,$b)=>strcmp($a['kind'].'/'.$a['id'],$b['kind'].'/'.$b['id']));
                    foreach($files as $file)yield ['tag'=>$tag,'value'=>$file];
                }
            }
            ksort($sections,SORT_STRING);
            foreach($sections as $section)yield ['tag'=>'section','value'=>$section];
        })();
        return NativeCryptoMigrationBusinessParityV3::compute($header,$frames);
    }
}
