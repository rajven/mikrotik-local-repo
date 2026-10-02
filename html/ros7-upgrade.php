<?php
/**
 * Proxy for upgrade.mikrotik.com
 * Accepts requests such as:
 *   /routeros/NEWEST7.stable?version=7.19.2
 *   /routeros/NEWESTa7.long-term?version=7.19.2
 *
 * Cache key format: "filename_version" (e.g., "NEWESTa7.long-term_7.20.4")
 * This allows caching different upstream responses for different client versions.
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 2;
const TOTAL_TIMEOUT   = 3;

const CACHE_FILE = __DIR__ . '/routeros/version.cache';

const LOCAL_STABLE_FILE     = __DIR__ . '/NEWEST7.stable';
const LOCAL_LONGTERM_FILE   = __DIR__ . '/NEWEST7.stable';
const LOCAL_STABLE_AFILE    = __DIR__ . '/NEWESTa7.stable';
const LOCAL_LONGTERM_AFILE  = __DIR__ . '/NEWESTa7.long-term';

$FALLBACKS = [
    'NEWEST7.stable'     => "7.12.1 1700221125\n",
    'NEWEST7.long-term'  => "7.12.1 1700221125\n",
    'NEWESTa7.stable'    => "7.24.5 1790691687\n",
    'NEWESTa7.long-term' => "7.23.7 1789561155\n",
];

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

function readCache(string $key): ?string
{
    if (!is_file(CACHE_FILE) || !is_readable(CACHE_FILE)) {
        return null;
    }
    $lines = @file(CACHE_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return null;
    }
    foreach ($lines as $line) {
        $parts = explode('=', $line, 2);
        if (count($parts) === 2 && trim($parts[0]) === $key) {
            $value = trim($parts[1]);
            return $value !== '' ? $value . "\n" : null;
        }
    }
    return null;
}

function writeCache(string $key, string $value): void
{
    $dir = dirname(CACHE_FILE);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    
    $value = trim($value, "\r\n \t");
    if ($value === '') {
        return;
    }
    
    $fp = @fopen(CACHE_FILE, 'c+');
    if (!$fp) {
        return;
    }
    
    if (!flock($fp, LOCK_EX)) {
        fclose($fp);
        return;
    }
    
    try {
        $existing = [];
        rewind($fp);
        $content = stream_get_contents($fp);
        if ($content !== false && $content !== '') {
            $existing = array_filter(
                explode("\n", $content),
                fn($line) => $line !== ''
            );
        }
        
        $lines = [];
        $found = false;
        foreach ($existing as $line) {
            $parts = explode('=', $line, 2);
            if (count($parts) === 2 && trim($parts[0]) === $key) {
                $lines[] = $key . '=' . $value;
                $found = true;
            } else {
                $lines[] = $line;
            }
        }
        if (!$found) {
            $lines[] = $key . '=' . $value;
        }
        
        ftruncate($fp, 0);
        rewind($fp);
        fwrite($fp, implode("\n", $lines) . "\n");
        fflush($fp);
        
    } finally {
        flock($fp, LOCK_UN);
        fclose($fp);
    }
}

function resolveFallback(string $cacheKey, string $file, array $defaults): string
{
    // Try cache first (by composite key: file + version)
    $cached = readCache($cacheKey);
    if ($cached !== null) {
        return $cached;
    }
    
    // Try local files
    switch ($file) {
        case 'NEWEST7.stable':
            $local = readLocalFallback(LOCAL_STABLE_FILE);
            if ($local !== null) return $local;
            break;
        case 'NEWEST7.long-term':
            $local = readLocalFallback(LOCAL_LONGTERM_FILE);
            if ($local !== null) return $local;
            break;
        case 'NEWESTa7.stable':
            $local = readLocalFallback(LOCAL_STABLE_AFILE);
            if ($local !== null) return $local;
            break;
        case 'NEWESTa7.long-term':
            $local = readLocalFallback(LOCAL_LONGTERM_AFILE);
            if ($local !== null) return $local;
            break;
    }
    
    // Final fallback: hardcoded values
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

// ---------- extract version for User-Agent and cache key ----------
$version = $_GET['version'] ?? '7.0';
if (!preg_match('/^\d+(\.\d+)*$/', $version)) {
    $version = '7.0';
}

$cacheKey = $file . '_' . $version;

// ---------- upstream request ----------
$query = $_SERVER['QUERY_STRING'] ?? '';
$url   = UPSTREAM_BASE . $file . ($query !== '' ? '?' . $query : '');

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CONNECTTIMEOUT => CONNECT_TIMEOUT,
    CURLOPT_TIMEOUT        => TOTAL_TIMEOUT,
    CURLOPT_USERAGENT      => 'RouterOS ' . $version,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_ENCODING       => '',
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
    writeCache($cacheKey, $payload);
} else {
    error_log(sprintf(
        '[mt-upgrade-proxy-v7] upstream fail: file=%s version=%s url=%s http=%s curl_err=%s',
        $file, $version, $url, $httpCode, $curlErr ?: '-'
    ));
    $payload = resolveFallback($cacheKey, $file, $FALLBACKS);
}

// ---------- headers ----------
header('HTTP/1.0 200 OK');
header('Content-Type: text/plain');
header('Content-Length: ' . strlen($payload));
header('Connection: close');
header('Cache-Control: no-store');

@ini_set('zlib.output_compression', '0');
@ini_set('output_handler', '');
while (ob_get_level() > 0) { ob_end_clean(); }

echo $payload;
