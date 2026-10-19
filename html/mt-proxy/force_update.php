<?php
/**
 * force_update.php - check permission to update.
 */
header('Content-Type: text/plain; charset=utf-8');

require __DIR__ . '/db.php';

function getParam(string $key, string $default = ''): string
{
    if (!isset($_GET[$key])) return $default;
    $val = trim((string)$_GET[$key]);
    return $val !== '' ? $val : $default;
}

/* ----------------------------------------------------------- client IP */
/**
 * Resolve the real device address.
 *
 * Priority (only when the CONNECTION arrives from a configured trusted proxy):
 *   1. X-Forwarded-For - first valid address (original client)
 *   2. X-Real-IP
 *   3. REMOTE_ADDR
 * Otherwise: REMOTE_ADDR as-is. Every candidate must pass FILTER_VALIDATE_IP;
 * garbage/absent headers are skipped, not trusted.
 */
function resolveClientIp(array $trustedProxies): string
{
    $remote = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
    if ($remote === '' || !ipInTrustedList($remote, $trustedProxies)) {
        return $remote;
    }

    $xff = trim((string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? ''));
    if ($xff !== '') {
        foreach (explode(',', $xff) as $hop) {
            $hop = trim($hop);
            if (filter_var($hop, FILTER_VALIDATE_IP)) {
                return $hop;
            }
            // bracketed form with optional port: "[2001:db8::1]:443"
            if (preg_match('/^\[([^\]]+)\](:\d+)?$/', $hop, $m)
                && filter_var($m[1], FILTER_VALIDATE_IP)) {
                return $m[1];
            }
        }
    }

    $xri = trim((string)($_SERVER['HTTP_X_REAL_IP'] ?? ''));
    if (filter_var($xri, FILTER_VALIDATE_IP)) {
        return $xri;
    }

    return $remote;
}

function ipInTrustedList(string $ip, array $list): bool
{
    $ipBin = filter_var($ip, FILTER_VALIDATE_IP) ? inet_pton($ip) : false;
    if ($ipBin === false || $ipBin === '') {
        return false;
    }
    foreach ($list as $entry) {
        $entry = trim((string)$entry);
        if ($entry === '') {
            continue;
        }
        if (strpos($entry, '/') === false) {
            $cand = filter_var($entry, FILTER_VALIDATE_IP) ? inet_pton($entry) : false;
            if ($cand !== false && $cand !== '' && $cand === $ipBin) {
                return true;
            }
            continue;
        }
        [$net, $bits] = explode('/', $entry, 2);
        if (!filter_var($net, FILTER_VALIDATE_IP)) {
            continue;
        }
        $netBin = inet_pton($net);
        if ($netBin === false || $netBin === '' || strlen($netBin) !== strlen($ipBin)) {
            continue;
        }
        $bits = (int)$bits;
        $len  = strlen($ipBin);
        if ($bits < 0 || $bits > $len * 8) {
            continue;
        }
        $mask = str_repeat("\xff", intdiv($bits, 8));
        $rem  = $bits % 8;
        if ($rem) {
            $mask .= chr((0xff << (8 - $rem)) & 0xff);
        }
        $mask .= str_repeat("\x00", $len - strlen($mask));
        if (($ipBin & $mask) === ($netBin & $mask)) {
            return true;
        }
    }
    return false;
}

/* ----------------------------------------------------------- main */
$CFG             = require __DIR__ . '/mt_proxy_config.php';
$trustedProxies  = $CFG['trusted_proxies'] ?? [];

$newVersion      = getParam('new_version');
$requestedSerial = getParam('serial');
$requestedModel  = getParam('model');
$deviceName      = getParam('name');
$currentFirmware = getParam('currentFirmware');
$upgradeFirmware = getParam('upgradeFirmware');

if ($newVersion === '') {
    echo 'DISABLED';
    exit;
}

if ($requestedSerial !== '') {
    try {
        deviceUpsert($requestedSerial, $requestedModel, $deviceName);
    } catch (Throwable $e) {
        error_log('[force_update] db error: ' . $e->getMessage());
    }

    $ip = resolveClientIp($trustedProxies);
    if ($ip !== '') {
        try {
            deviceIpsUpsert($requestedSerial, $ip);
        } catch (Throwable $e) {
            error_log('[force_update] ips error: ' . $e->getMessage());
        }
    }

    try {
        deviceUpdateFirmwares($requestedSerial, $currentFirmware, $upgradeFirmware, $newVersion);
    } catch (Throwable $e) {
        error_log('[force_update] firmwares error: ' . $e->getMessage());
    }
}

try {
    $isAllowed = isVersionAllowed($requestedSerial, $requestedModel, $newVersion);
} catch (Throwable $e) {
    error_log('[force_update] policy error: ' . $e->getMessage());
    $isAllowed = false;
}

echo $isAllowed ? 'ENABLED' : 'DISABLED';
