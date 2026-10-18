<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Exact byte inventory of SQL-associated private files; never returns a storage path. */
class NativeCryptoFileInventory extends NativeDatabase
{
    protected $cryptoAccess = true;

    public function collect(array $scopeIds)
    {
        $result = [];
        foreach ($scopeIds as $sid) {
            $hash = hash_init('sha256');
            $files = 0;
            $bytes = 0;
            $absent = 0;
            foreach ($this->descriptors($sid) as $file) {
                $entry = $this->inspect($file);
                hash_update($hash, NativeCryptoCodec::canonical((object)$entry)."\n");
                if ($entry['state'] === 'present') {
                    $files++;
                    $bytes += $entry['size'];
                } else {
                    $absent++;
                }
            }
            $result[$sid] = ['files' => $files,'bytes' => $bytes,'absentRetired' => $absent,'sha256' => hash_final($hash)];
        }
        return (object)$result;
    }

    public function safeDescriptors($sid)
    {
        foreach ($this->descriptors($sid) as $file) {
            yield $this->inspect($file);
        }
    }

    protected function descriptors($sid)
    {
        foreach ($this->iterate('SELECT id,size,sha256,complete,deleted FROM familyhub_attachments WHERE scope_id=? ORDER BY id', [$sid]) as $r) {
            $this->uuid($r['id']);
            $required = (int)$r['complete'] === 1 && (int)$r['deleted'] === 0;
            yield ['kind' => 'attachment','id' => $r['id'],'path' => 'familyhub/attachments/'.hash('sha256', $sid.':'.$r['id']),'required' => $required,'size' => $required ? (int)$r['size'] : null,'sha256' => $required ? $r['sha256'] : null];
        }
        foreach ($this->iterate('SELECT board_id,sha256,size,complete FROM familyhub_idea_assets WHERE scope_id=? ORDER BY board_id,sha256', [$sid]) as $r) {
            $this->uuid($r['board_id']);
            if (!preg_match('/^[a-f0-9]{64}$/D', $r['sha256'])) {
                throw new NativeError('crypto_file_inventory_invalid', 503);
            }$required = (int)$r['complete'] === 1;
            yield ['kind' => 'idea','id' => $r['board_id'].':'.$r['sha256'],'path' => 'familyhub/ideas/'.hash('sha256', $sid.':'.$r['board_id']).'/'.$r['sha256'],'required' => $required,'size' => $required ? (int)$r['size'] : null,'sha256' => $required ? $r['sha256'] : null];
        }
        // Retired scope files can survive their source row pending durable cleanup.
        foreach ($this->iterate('SELECT path_hash,path FROM familyhub_scope_deletion_files WHERE scope_id=? ORDER BY path_hash', [$sid]) as $r) {
            if (!hash_equals(hash('sha256', $r['path']), $r['path_hash']) || !preg_match('~^familyhub/(?:attachments/[a-f0-9]{64}|ideas/[a-f0-9]{64}/[a-f0-9]{64})$~D', $r['path'])) {
                throw new NativeError('crypto_file_inventory_invalid', 503);
            }
            yield ['kind' => 'retired','id' => $r['path_hash'],'path' => $r['path'],'required' => false,'size' => null,'sha256' => null];
        }
    }

    protected function inspect(array $file)
    {
        $entry = ['kind' => $file['kind'],'id' => $file['id'],'state' => 'absent','size' => 0,'sha256' => null];
        $root = realpath(DATA_DIR);
        if ($root === false || is_link(DATA_DIR)) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        $path = $root;
        foreach (explode('/', $file['path']) as $part) {
            $path .= '/'.$part;
            if (is_link($path)) {
                throw new NativeError('crypto_file_inventory_unavailable', 503);
            }
        }
        clearstatcache(true, $path);
        if (!is_file($path)) {
            if ($file['required']) {
                throw new NativeError('crypto_file_inventory_missing', 409);
            }return $entry;
        }
        if (realpath($path) !== $path) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        $before = @stat($path);
        $h = @fopen($path, 'rb');
        if (!$before || !$h) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        try {
            $opened = fstat($h);
            if (!$opened || $opened['ino'] !== $before['ino'] || $opened['dev'] !== $before['dev']) {
                throw new NativeError('crypto_file_inventory_changed', 409);
            }
            $hash = hash_init('sha256');
            $size = hash_update_stream($hash, $h);
            $digest = hash_final($hash);
            $after = fstat($h);
            if ($size === false || !$after || $size !== (int)$before['size'] || $after['size'] !== $before['size'] || $after['mtime'] !== $before['mtime'] || $after['ctime'] !== $before['ctime']) {
                throw new NativeError('crypto_file_inventory_changed', 409);
            }
        } finally {
            fclose($h);
        }
        if ($file['required'] && ($size !== $file['size'] || !hash_equals($file['sha256'], $digest))) {
            throw new NativeError('crypto_file_inventory_integrity', 409);
        }
        return array_replace($entry, ['state' => 'present','size' => $size,'sha256' => $digest]);
    }
}
