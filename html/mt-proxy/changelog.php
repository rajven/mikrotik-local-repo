<?php
/** 
* changelog.php - returns the contents of CHANGELOG for the specified version of RouterOS. 
* Path: <routeros_dir>/<version>/CHANGELOG 
*/
header('Content-Type: text/plain; charset=utf-8');

$CFG = require __DIR__ . '/mt_proxy_config.php';

$version = trim($_GET['version'] ?? '');

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

// Limit the size so as not to transfer gigantic files
$maxSize = 2 * 1024 * 1024; // 2 MB
$size = filesize($path);
if ($size > $maxSize) {
    $content = file_get_contents($path, false, null, 0, $maxSize);
    echo $content . "\n\n... [truncated, file too large] ...\n";
} else {
    echo file_get_contents($path);
}
