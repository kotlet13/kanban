<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeError extends \RuntimeException
{
    public $status;
    public $errorCode;
    public $details;

    public function __construct($code, $status = 422, array $details = [])
    {
        parent::__construct($code);
        $this->errorCode = $code;
        $this->status = $status;
        $this->details = $details;
    }
}
