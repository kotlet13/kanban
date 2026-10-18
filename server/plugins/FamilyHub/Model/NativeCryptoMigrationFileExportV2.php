<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Logical SQL-associated file ranges. No caller supplied filesystem path. */
class NativeCryptoMigrationFileExportV2 extends NativeCryptoFileInventory
{
    public function describe($scopeId, $kind, $id)
    {
        foreach ($this->descriptors($scopeId) as $file) {
            if ($file['kind'] === $kind && $file['id'] === $id) {
                $entry = $this->inspect($file);
                $entry['stamp'] = $entry['state'] === 'present'
                    ? $this->stamp($this->pathStat($file)[1]) : null;
                return $entry;
            }
        }
        throw new NativeError('crypto_file_inventory_missing', 404);
    }
    public function page($scopeId, $after, $limit)
    {
        if (!is_int($after) || $after < 0 || !is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('invalid_cursor');
        }
        $entries = [];
        $index = 0;
        $hasMore = false;
        foreach ($this->descriptors($scopeId) as $file) {
            if ($index++ < $after) {
                continue;
            }
            if (count($entries) === $limit) {
                $hasMore = true;
                break;
            }
            $entry = $this->inspect($file);
            $entry['stamp'] = $entry['state'] === 'present'
                ? $this->stamp($this->pathStat($file)[1]) : null;
            $entries[] = $entry;
        }
        return ['files' => $entries, 'hasMore' => $hasMore, 'cursor' => $after + count($entries)];
    }

    public function chunk($scopeId, $kind, $id, $offset, $limit, $stamp)
    {
        if (!is_string($kind) || !is_string($id) || !is_string($stamp) ||
            !preg_match('/^[a-f0-9]{64}$/D', $stamp) || !is_int($offset) || $offset < 0 ||
            !is_int($limit) || $limit < 1 || $limit > 196608) {
            throw new NativeError('validation_error');
        }
        $selected = null;
        foreach ($this->descriptors($scopeId) as $file) {
            if ($file['kind'] === $kind && $file['id'] === $id) {
                $selected = $file;
                break;
            }
        }
        if (!$selected) {
            throw new NativeError('crypto_file_inventory_missing', 404);
        }
        [$path, $before] = $this->pathStat($selected);
        if (!hash_equals($stamp, $this->stamp($before)) || $offset > (int)$before['size']) {
            throw new NativeError('crypto_file_inventory_changed', 409);
        }
        $handle = @fopen($path, 'rb');
        if (!$handle) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        try {
            $opened = fstat($handle);
            if (!$opened || $this->stamp($opened) !== $stamp || fseek($handle, $offset) !== 0) {
                throw new NativeError('crypto_file_inventory_changed', 409);
            }
            $bytes = '';
            $remaining = min($limit, (int)$before['size'] - $offset);
            while (strlen($bytes) < $remaining) {
                $part = fread($handle, $remaining - strlen($bytes));
                if ($part === false || $part === '') {
                    throw new NativeError('crypto_file_inventory_changed', 409);
                }
                $bytes .= $part;
            }
            $after = fstat($handle);
            [, $named] = $this->pathStat($selected);
            if (!$after || $this->stamp($after) !== $stamp || $this->stamp($named) !== $stamp) {
                throw new NativeError('crypto_file_inventory_changed', 409);
            }
        } finally {
            fclose($handle);
        }
        return ['kind' => $kind, 'id' => $id, 'offset' => $offset,
            'nextOffset' => $offset + strlen($bytes), 'size' => (int)$before['size'],
            'stamp' => $stamp, 'dataBase64' => base64_encode($bytes)];
    }

    private function pathStat($file)
    {
        $root = realpath(DATA_DIR);
        if ($root === false || is_link(DATA_DIR)) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        $path = $root;
        foreach (explode('/', $file['path']) as $part) {
            $path .= '/'.$part;
            clearstatcache(true, $path);
            if (is_link($path)) {
                throw new NativeError('crypto_file_inventory_unavailable', 503);
            }
        }
        $stat = @stat($path);
        if (!$stat || !is_file($path) || realpath($path) !== $path) {
            throw new NativeError('crypto_file_inventory_unavailable', 503);
        }
        return [$path, $stat];
    }

    private function stamp($stat)
    {
        return hash('sha256', implode(':', array_map(static fn($key) => (string)$stat[$key],
            ['dev', 'ino', 'mode', 'size', 'mtime', 'ctime'])));
    }
}
