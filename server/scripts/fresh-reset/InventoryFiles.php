<?php
/** Read-only inventory of precisely the two FamilyHub business-file namespaces.
 * Never walks backups, core Kanboard files, cache, keys, or crypto/migration.lock. */
final class FamilyHubFreshResetFiles
{
    public static function inspect(string $dataDir,int $maxFiles=100000,int $maxBytes=10737418240,int $maxEntries=200000): array {
        if(!str_starts_with($dataDir,'/')||preg_match('~/(?:\.|\.\.)(?:/|$)~',$dataDir))throw new RuntimeException('unsafe_data_root');
        $walk='';foreach(explode('/',trim($dataDir,'/')) as $part){$walk.='/'.$part;if(is_link($walk))throw new RuntimeException('symlink_data_root');}
        $root=realpath($dataDir);if($root===false||!is_dir($root))throw new RuntimeException('missing_data_root');
        $base=$root.'/familyhub';if(is_link($base))throw new RuntimeException('symlink_familyhub');
        if(file_exists($base)&&!is_dir($base))throw new RuntimeException('invalid_familyhub');
        if(is_dir($base)){foreach(scandir($base) as $n)if(!in_array($n,['.','..','attachments','ideas','crypto'],true))throw new RuntimeException('unclassified_familyhub_path');}
        $out=[];$count=0;$bytes=0;$entries=0;
        foreach(['attachments','ideas'] as $namespace){$dir=$base.'/'.$namespace;if(is_link($dir))throw new RuntimeException('symlink_business_root');
            if(!file_exists($dir)){$out[$namespace]=['state'=>'absent'];continue;}
            if(!is_dir($dir))throw new RuntimeException('invalid_business_root');
            $out[$namespace]=['state'=>'directory','mode'=>fileperms($dir)&0777];
            $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST);
            foreach($iterator as $entry){if(++$entries>$maxEntries)throw new RuntimeException('excess_business_entries');$path=$entry->getPathname();$relative=substr($path,strlen($base)+1);if($entry->isLink())throw new RuntimeException('symlink_business_entry');
                if($entry->isDir()){$out[$relative]=['state'=>'directory','mode'=>$entry->getPerms()&0777];continue;}
                if(!$entry->isFile()||++$count>$maxFiles)throw new RuntimeException('unsupported_or_excess_files');
                $before=lstat($path);if($before['size']>$maxBytes-$bytes)throw new RuntimeException('excess_business_bytes');$h=fopen($path,'rb');if(!$h)throw new RuntimeException('unreadable_business_file');
                try{$opened=fstat($h);if($before['ino']!==$opened['ino']||$before['dev']!==$opened['dev'])throw new RuntimeException('file_changed');$hash=hash_init('sha256');$size=hash_update_stream($hash,$h);$after=fstat($h);if($size!==$before['size']||$after['size']!==$before['size']||$after['mtime']!==$before['mtime']||$after['ctime']!==$before['ctime'])throw new RuntimeException('file_changed');$digest=hash_final($hash);}finally{fclose($h);}
                $bytes+=$size;if($bytes>$maxBytes)throw new RuntimeException('excess_business_bytes');
                $out[$relative]=['state'=>'file','mode'=>$before['mode']&0777,'size'=>$size,'sha256'=>$digest];
            }
        }
        ksort($out);return ['version'=>1,'entries'=>$out,'files'=>$count,'bytes'=>$bytes,'manifestHash'=>hash('sha256',serialize($out))];
    }
}
