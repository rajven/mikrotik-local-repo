<?php
/**
 * Proxy for upgrade.mikrotik.com
 * Accepts requests such as:
 *   /NEWEST7.stable?version=7.19.2
 *   /NEWESTa7.long-term?version=7.19.2
 *
 * and forwards them to:
 *   https://upgrade.mikrotik.com/routeros/<file>?<query>
 *
 * If the upstream responds successfully, its response is returned as-is.
 * If the request fails, the following fallback values are used:
 *   NEWEST7.stable      => contents of the local NEWEST7.stable file
 *   NEWEST7.long-term   => contents of the local NEWEST7.stable file
 *   NEWESTa7.stable     => contents of the local NEWESTa7.stable file
 *   NEWESTa7.long-term  => contents of the local NEWESTa7.long-term file
 *
 * If the local file for stable/long-term is unavailable or empty,
 * the hardcoded value "6.49.21 1788435939" is used.
 *
 *   - always sends Content-Length;
 *   - forces HTTP/1.0 + Connection: close (more reliable for RouterOS);
 *   - no chunked encoding and no implicit line breaks.
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 5;
const TOTAL_TIMEOUT   = 10;

/**
 * Local fallback source files for stable/long-term.
 * The paths are relative to the script location.
 */

const LOCAL_STABLE_FILE     = __DIR__ . '/NEWEST7.stable';
const LOCAL_LONGTERM_FILE   = __DIR__ . '/NEWEST7.stable';
const LOCAL_STABLE_AFILE    = __DIR__ . '/NEWESTa7.stable';
const LOCAL_LONGTERM_AFILE  = __DIR__ . '/NEWESTa7.long-term';

$FALLBACKS = [
    'NEWEST7.stable'     => "7.12.1 1700221125\n",
    'NEWEST7.long-term'  => "7.12.1 1700221125\n",
    'NEWESTa7.stable'    => "7.24.2 1788429434\n",
    'NEWESTa7.long-term' => "7.23.5 1788499966\n",
];

/**
 * Returns the contents of a local fallback file, or null
 * if the file is unavailable, empty, or unreadable.
 */
function readLocalFallback(string $path): ?string
{
    if (!is_file($path) || !is_readable($path)) {
        return null;
    }
    $data = @file_get_contents($path);
    if ($data === false) {
        return null;
    }
    $data = trim($data, "\r\n \t");
    if ($data === '') {
        return null;
    }
    return $data . "\n";
}

/**
 * Selects the fallback content for the requested file.
 */
function resolveFallback(string $file, array $defaults): string
{
    switch ($file) {
        case 'NEWEST7.stable':
            $local = readLocalFallback(LOCAL_STABLE_FILE);
            if ($local !== null) {
                return $local;
            }
            break;
        case 'NEWEST7.long-term':
            $local = readLocalFallback(LOCAL_LONGTERM_FILE);
            if ($local !== null) {
                return $local;
            }
            break;

        case 'NEWESTa7.stable':
            $local = readLocalFallback(LOCAL_STABLE_AFILE);
            if ($local !== null) {
                return $local;
            }
            break;
        case 'NEWESTa7.long-term':
            $local = readLocalFallback(LOCAL_LONGTERM_AFILE);
            if ($local !== null) {
                return $local;
            }
            break;
    }

    return $defaults[$file];
}

// ---------- requested file ----------
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$file = basename($path);

if (!isset($FALLBACKS[$file])) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    header('Content-Length: 17');
    header('Connection: close');
    echo "Unknown resource\n";
    exit;
}

// ---------- upstream request ----------
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
    // Do not request compression — RouterOS does not support gzip
    CURLOPT_ENCODING       => '',
    // Explicitly use HTTP/1.1 with Connection: close (see below)
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

// ---------- build response body ----------

if ($isValid) {
    $payload = rtrim($body, "\r\n \t") . "\n";
} else {
    error_log(sprintf(
        '[mt-upgrade-proxy] upstream fail: file=%s url=%s http=%s curl_err=%s',
        $file, $url, $httpCode, $curlErr ?: '-'
    ));
    $payload = resolveFallback($file, $FALLBACKS);
}

// ---------- headers critical for RouterOS ----------
// HTTP/1.0 => chunked encoding is not possible by specification, which RouterOS prefers
header('HTTP/1.0 200 OK');
header('Content-Type: text/plain');
header('Content-Length: ' . strlen($payload));
header('Connection: close');
header('Cache-Control: no-store');

// Disable any buffering/compression at the PHP level
@ini_set('zlib.output_compression', '0');
@ini_set('output_handler', '');
while (ob_get_level() > 0) { ob_end_clean(); }

echo $payload;
