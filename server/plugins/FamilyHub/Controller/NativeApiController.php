<?php
namespace Kanboard\Plugin\FamilyHub\Controller;

use Kanboard\Controller\BaseController;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Model\NativeService;

/** Public dispatcher only. Every protected operation validates its own bearer. */
class NativeApiController extends BaseController
{
    public function handle()
    {
        // This bearer-only dispatcher never changes Kanboard's web session.
        // Avoid its deferred SELECT/write shutdown transaction racing native
        // SQLite writes and appending a fatal error after a valid JSON response.
        if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
        $this->response->withHeader('Cache-Control', 'no-store')->withHeader('Vary', 'Origin')
            ->withHeader('X-Content-Type-Options', 'nosniff');
        try {
            $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
            $allowed = defined('FAMILYHUB_CORS_ORIGINS') && is_array(FAMILYHUB_CORS_ORIGINS) ? FAMILYHUB_CORS_ORIGINS : [];
            if ($origin !== '') {
                if (!in_array($origin, $allowed, true) || !$this->validOrigin($origin)) {
                    throw new NativeError('origin_not_allowed', 403);
                }
                $this->response->withHeader('Access-Control-Allow-Origin', $origin)
                    ->withHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
                    ->withHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
            }
            if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
                if ($origin === '' || ($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] ?? '') !== 'POST') {
                    throw new NativeError('origin_not_allowed', 403);
                }
                $this->response->withStatusCode(204)->withBody('')->send();
                return;
            }
            if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
                throw new NativeError('method_not_allowed', 405);
            }
            if (!self::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT === true)) {
                throw new NativeError('https_required', 403);
            }
            if (strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0])) !== 'application/json') {
                throw new NativeError('json_required', 415);
            }
            // Bounded read, regardless of whether Content-Length was provided.
            $stream = fopen('php://input', 'rb');
            $body = stream_get_contents($stream, 1048577);
            fclose($stream);
            if (strlen($body) > 1048576) {
                throw new NativeError('request_too_large', 413);
            }
            $shape = json_decode($body, false, 32, JSON_THROW_ON_ERROR);
            if (!($shape instanceof \stdClass) || !(($shape->params ?? null) instanceof \stdClass)) {
                throw new NativeError('invalid_request');
            }
            $envelope = json_decode($body, true, 32, JSON_THROW_ON_ERROR);
            if (!is_array($envelope) || ($envelope['v'] ?? null) !== 1 || !is_string($envelope['op'] ?? null) || !is_array($envelope['params'] ?? null)) {
                throw new NativeError('invalid_request');
            }
            $service = new NativeService($this->container);
            $data = $service->dispatch($envelope['op'], $envelope['params'], $_SERVER['HTTP_AUTHORIZATION'] ?? '', $_SERVER['REMOTE_ADDR'] ?? 'unknown');
            $this->response->json(['v' => 1, 'data' => $data]);
        } catch (NativeError $error) {
            if ($error->errorCode === 'rate_limited') {
                $this->response->withHeader('Retry-After', (string)($error->details['retryAfter'] ?? 60));
            }
            $this->response->json(['v' => 1, 'error' => ['code' => $error->errorCode, 'message' => $error->errorCode, 'details' => (object)$error->details]], $error->status);
        } catch (\JsonException $error) {
            $this->response->json(['v' => 1, 'error' => ['code' => 'invalid_json', 'message' => 'invalid_json']], 422);
        } catch (\Throwable $error) {
            // No user payload, token, database exception or stack trace in logs/HTTP.
            $this->response->json(['v' => 1, 'error' => ['code' => 'server_error', 'message' => 'server_error']], 500);
        }
    }

    public static function secureTransport(array $server)
    {
        if (isset($server['HTTPS']) && $server['HTTPS'] !== '' && strtolower((string)$server['HTTPS']) !== 'off') { return true; }
        $trusted = defined('FAMILYHUB_TRUSTED_PROXY_IPS') && is_array(FAMILYHUB_TRUSTED_PROXY_IPS) ? FAMILYHUB_TRUSTED_PROXY_IPS : [];
        return in_array($server['REMOTE_ADDR'] ?? '', $trusted, true) && ($server['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    }

    private function validOrigin($origin)
    {
        $parts = parse_url($origin);
        if (!$parts || isset($parts['user']) || isset($parts['pass']) || isset($parts['path']) || isset($parts['query']) || isset($parts['fragment']) || !isset($parts['host'])) {
            return false;
        }
        return ($parts['scheme'] ?? '') === 'https' ||
            ((defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT === true) &&
             ($parts['scheme'] ?? '') === 'http' && in_array($parts['host'], ['127.0.0.1', 'localhost', '::1'], true));
    }
}
