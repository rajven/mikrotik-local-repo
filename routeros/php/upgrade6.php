<?php
/**
 * Прокси для upgrade.mikrotik.com
 * Принимает запросы вида:
 *   /NEWEST6.upgrade?version=6.49.21
 *   /NEWESTa6.upgrade?version=6.49.21
 *
 * и перенаправляет их на:
 *   https://upgrade.mikrotik.com/routeros/<файл>?<query>
 *
 * Если upstream ответил корректно — возвращаем его ответ как есть.
 * Если запрос не удался — отдаём заранее заданный fallback:
 *   NEWEST6.upgrade  → "7.12.1 1700221125"
 *   NEWESTa6.upgrade → "7.23.5 1788499966"
 *   - всегда отдаём Content-Length;
 *   - принудительно HTTP/1.0 + Connection: close (RouterOS так надёжнее);
 *   - никакого chunked, никаких неявных переводов строк.
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 5;
const TOTAL_TIMEOUT   = 10;

$FALLBACKS = [
    'NEWEST6.upgrade'  => "7.12.1 1700221125\n",
    'NEWESTa6.upgrade' => "7.23.5 1788499966\n",
];

// ---------- какой файл просят ----------
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$file = basename($path);

if (!isset($FALLBACKS[$file])) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    header('Content-Length: 21');
    header('Connection: close');
    echo "Unknown resource\n";
    exit;
}

// ---------- запрос к upstream ----------
$query = $_SERVER['QUERY_STRING'] ?? '';
$url   = UPSTREAM_BASE . $file . ($query !== '' ? '?' . $query : '');

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_CONNECTTIMEOUT => CONNECT_TIMEOUT,
    CURLOPT_TIMEOUT        => TOTAL_TIMEOUT,
    CURLOPT_USERAGENT      => 'MikroTik-Upgrade-Proxy/1.0',
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    // Не просим сжатия — RouterOS gzip не умеет
    CURLOPT_ENCODING       => '',
    // Явно HTTP/1.1, но с Connection: close (см. ниже)
    CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_1_1,
]);

$body     = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr  = curl_error($ch);
curl_close($ch);

$isValid = (
    $curlErr === ''
    && $httpCode === 200
    && is_string($body)
    && preg_match('/^\s*\d+(\.\d+)+\s+\d+/', $body) === 1
);

// ---------- формируем тело ответа ----------

if ($isValid) {
    $payload = rtrim($body, "\r\n \t") . "\n";
} else {
    error_log(sprintf(
        '[mt-upgrade-proxy] upstream fail: file=%s url=%s http=%s curl_err=%s',
        $file, $url, $httpCode, $curlErr ?: '-'
    ));
    $payload = $FALLBACKS[$file];
}

// ---------- заголовки, критичные для RouterOS ----------
// HTTP/1.0 => chunked по спецификации невозможен, RouterOS это любит
header('HTTP/1.0 200 OK');
header('Content-Type: text/plain');
header('Content-Length: ' . strlen($payload));
header('Connection: close');
header('Cache-Control: no-store');

// Отключаем любую буферизацию/сжатие на уровне PHP
@ini_set('zlib.output_compression', '0');
@ini_set('output_handler', '');
while (ob_get_level() > 0) { ob_end_clean(); }

echo $payload;
