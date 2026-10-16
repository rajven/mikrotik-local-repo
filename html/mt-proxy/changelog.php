<?php
/**
 * changelog.php — отдаёт содержимое CHANGELOG для указанной версии RouterOS.
 * Путь: <routeros_dir>/<version>/CHANGELOG
 */
header('Content-Type: text/plain; charset=utf-8');

$CFG = require __DIR__ . '/mt_proxy_config.php';

$version = trim($_GET['version'] ?? '');

// Строгая валидация: только цифры и точки, защита от path traversal
if (!preg_match('/^\d+(\.\d+)+$/', $version)) {
    http_response_code(400);
    echo "Invalid version";
    exit;
}

$path = $CFG['routeros_dir'] . '/' . $version . '/CHANGELOG';

if (!is_file($path) || !is_readable($path)) {
    http_response_code(404);
    echo "CHANGELOG not found for version " . $version;
    exit;
}

// Ограничим размер, чтобы не отдавать гигантские файлы
$maxSize = 2 * 1024 * 1024; // 2 MB
$size = filesize($path);
if ($size > $maxSize) {
    $content = file_get_contents($path, false, null, 0, $maxSize);
    echo $content . "\n\n... [truncated, file too large] ...\n";
} else {
    echo file_get_contents($path);
}
