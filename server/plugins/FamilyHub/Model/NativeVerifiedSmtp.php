<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Fail closed when Swift's initial EHLO fallback would skip requested STARTTLS. */
class NativeVerifiedSmtp extends \Swift_SmtpTransport
{
    private $deadline;
    public function __construct($host, $port, $encryption)
    {
        parent::__construct($host, $port, $encryption); $this->deadline = microtime(true) + 40;
    }

    public function executeCommand($command, $codes = [], &$failures = null)
    {
        if (microtime(true) > $this->deadline || ($this->getEncryption() === 'tls' && str_starts_with(strtoupper($command), 'HELO '))) {
            throw new \Swift_TransportException('Verified SMTP transport unavailable');
        }
        return parent::executeCommand($command, $codes, $failures);
    }
}
