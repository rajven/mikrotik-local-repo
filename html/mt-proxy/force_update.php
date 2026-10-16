<?php
/**
 * force_update.php — проверка разрешения на обновление.
 */
header('Content-Type: text/plain; charset=utf-8');

require __DIR__ . '/db.php';

function getParam(string $key, string $default = ''): string
{
    if (!isset($_GET[$key])) return $default;
    $val = trim((string)$_GET[$key]);
    return $val !== '' ? $val : $default;
}

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

    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
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
