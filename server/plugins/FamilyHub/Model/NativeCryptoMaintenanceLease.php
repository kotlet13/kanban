<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Same-host worker/fence interlock, always acquired BEFORE a database transaction. */
class NativeCryptoMaintenanceLease
{
    private $handle;
    private function __construct($handle)
    {
        $this->handle = $handle;
    }
    public static function acquire($exclusive = false)
    {
        // Legacy installations with no crypto schema do not need a new filesystem dependency.
        $root = DATA_DIR.'/familyhub/crypto';
        if (is_link(DATA_DIR.'/familyhub') || is_link($root)) {
            throw new NativeError('crypto_storage_unavailable', 503);
        }
        if (!is_dir($root) && !@mkdir($root, 0700, true) && !is_dir($root)) {
            throw new NativeError('crypto_storage_unavailable', 503);
        }
        $path = $root.'/migration.lock';
        if (is_link($path)) {
            throw new NativeError('crypto_storage_unavailable', 503);
        }$h = @fopen($path, 'c');
        if (!$h) {
            throw new NativeError('crypto_storage_unavailable', 503);
        }@chmod($path, 0600);
        if (!flock($h, ($exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB)) {
            fclose($h);
            throw new NativeError('crypto_workers_busy', 409);
        }return new self($h);
    }
    public function __destruct()
    {
        if (is_resource($this->handle)) {
            flock($this->handle, LOCK_UN);
            fclose($this->handle);
        }
    }
}
