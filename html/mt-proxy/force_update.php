<?php
/**
 * force_update.php — проверка разрешения на обновление.
 *
 * - Новое устройство автоматически регистрируется в БД с ПУСТЫМ списком
 *   разрешённых версий (source='auto').
 * - Сохраняются IP, currentFirmware, upgradeFirmware, last_new_version.
 *
 * Логика решения:
 *   1. Устройство есть и список allowed НЕ пуст → проверка по списку устройства.
 *   2. Устройства нет (новое) или список пуст → global_versions из БД.
 *   3. global_versions пусты → файловый фолбэк (mt_proxy_rules.php).
 *   4. Файла нет/пуст → хардкод из mt_proxy_config.php.
 */
header('Content-Type: text/plain; charset=utf-8');

require __DIR__ . '/db.php';

function getParam(string $key, string $default = ''): string
{
    $source = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' ? $_POST : $_GET;
    if (!isset($source[$key])) return $default;
    $val = trim((string)$source[$key]);
    return $val !== '' ? $val : $default;
}

// Параметры от MikroTik
$newVersion      = getParam('new_version');       // Запрошенная версия для обновления
$requestedSerial = getParam('serial');
$requestedModel  = getParam('model');
$currentFirmware = getParam('currentFirmware');   // Boot firmware
$upgradeFirmware = getParam('upgradeFirmware');   // Upgrade firmware

if ($newVersion === '') {
    echo 'DISABLED';
    exit;
}

if ($requestedSerial !== '') {
    deviceRecordVisit(
        $requestedSerial,
        $requestedModel,
        $_SERVER['REMOTE_ADDR'] ?? '',
        $currentFirmware,
        $upgradeFirmware,
        $newVersion
    );
}

try {
    $isAllowed = isVersionAllowed($requestedSerial, $requestedModel, $newVersion);
} catch (Throwable $e) {
    error_log('[force_update] policy error: ' . $e->getMessage());
    $isAllowed = false;
}

echo $isAllowed ? 'ENABLED' : 'DISABLED';
