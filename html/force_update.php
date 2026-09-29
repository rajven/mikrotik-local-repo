<?php
// Устанавливаем заголовок, чтобы MikroTik получил чистый текст без HTML-мусора
header('Content-Type: text/plain; charset=utf-8');

/**
 * Безопасное получение GET-параметра
 */
function getParam($key, $default = '') {
    if (isset($_GET[$key])) {
        $val = trim($_GET[$key]);
        // Явная проверка на пустую строку вместо empty()
        return ($val !== '') ? $val : $default;
    }
    return $default;
}

// Предустановленный массив разрешённых версий для обновления
$allowedVersions = [
    '6.49.22',  // Пример стабильной версии ROS 6
    '7.24.4',   // Пример стабильной версии ROS 7
    '7.23.7',
];

$requestedVersion = getParam('new_version', '');

// Если версия не передана, сразу запрещаем
if ($requestedVersion === '') {
    echo 'DISABLED';
    exit;
}

// Строгая проверка наличия версии в массиве
if (in_array($requestedVersion, $allowedVersions, true)) {
    echo 'ENABLED';
} else {
    echo 'DISABLED';
}
?>
