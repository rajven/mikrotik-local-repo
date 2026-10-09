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

// Получаем параметры от MikroTik
$requestedVersion = getParam('new_version', '');
$requestedSerial  = getParam('serial', '');
$requestedModel   = getParam('model', '');

// Если версия не передана, сразу запрещаем
if ($requestedVersion === '') {
    echo 'DISABLED';
    exit;
}

// ============================================================
// Конфигурация правил обновления
// ============================================================

$updateRules = [
    // Уровень 1: Конкретные серийные номера (наивысший приоритет)
    'serials' => [
        // 'СЕРИЙНЫЙ_НОМЕР' => ['разрешенная_версия_1', 'разрешенная_версия_2'],
//        'ABC123DEF456' => ['7.24.5'], // Этому устройству разрешена ТОЛЬКО 7.15.3
//        'SN9876543210' => ['6.49.23'],
    ],

    // Уровень 2: Конкретные модели устройств
    'models' => [
        // 'МОДЕЛЬ' => ['разрешенная_версия_1', 'разрешенная_версия_2'],
//        'hEX lite'      => ['6.49.23'],
//        'RB4011iGS+RM'  => ['7.23.8'],
    ],

    // Уровень 3: Глобальный список разрешённых версий (фолбэк для неизвестных устройств)
    'global_versions' => [
        '6.49.23',
        '7.24.5',
        '7.23.8',
    ]
];

$isAllowed = false;
$decisionMade = false; // Флаг: было ли принято окончательное решение на основе известного идентификатора

// Шаг 1: Проверяем серийный номер
if ($requestedSerial !== '' && array_key_exists($requestedSerial, $updateRules['serials'])) {
    $decisionMade = true; // Серийник известен в базе, решение будет окончательным
    if (in_array($requestedVersion, $updateRules['serials'][$requestedSerial], true)) {
        $isAllowed = true;
    } else {
        $isAllowed = false;
    }
}

// Шаг 2: Проверяем модель (ТОЛЬКО если серийник неизвестен в базе)
if ($decisionMade === false && $requestedModel !== '' && array_key_exists($requestedModel, $updateRules['models'])) {
    $decisionMade = true; // Модель известна в базе, решение будет окончательным
    
    if (in_array($requestedVersion, $updateRules['models'][$requestedModel], true)) {
        $isAllowed = true;
    } else {
        $isAllowed = false;
    }
}

// Шаг 3: Проверяем глобальный список (ТОЛЬКО если и серийник, и модель неизвестны в базе)
if ($decisionMade === false) {
    if (in_array($requestedVersion, $updateRules['global_versions'], true)) {
        $isAllowed = true;
    } else {
        $isAllowed = false;
    }
}

// ============================================================
// Финальный вывод
// ============================================================

if ($isAllowed === true) {
    echo 'ENABLED';
} else {
    echo 'DISABLED';
}
?>
