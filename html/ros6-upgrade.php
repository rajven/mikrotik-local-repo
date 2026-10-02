<?php
/**
 * Proxy for upgrade.mikrotik.com (RouterOS v6 branch)
 * Accepts requests such as:
 *   /routeros/NEWEST6.upgrade?version=6.49.21
 *   /routeros/NEWESTa6.upgrade?version=6.49.21
 *
 * Cache key format: "filename_version" (e.g., "NEWEST6.upgrade_6.49.21")
 * Cache value format: "version timestamp|cache_timestamp"
 *
 * Optimization:
 *   - If cache is fresh (TTL not expired) → return it immediately, no upstream request
 *   - If cache is stale or missing → try upstream
 *   - Write to cache ONLY if upstream response differs from cached one
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 2;
const TOTAL_TIMEOUT   = 3;
const CACHE_TTL       = 10800; // 3 hours in seconds

const CACHE_FILE = __DIR__ . '/routeros/ros6.version.cache';

const LOCAL_STABLE_FILE    = __DIR__ . '/LATEST.6';
const LOCAL_LONGTERM_FILE  = __DIR__ . '/LATEST.6fix';

$FALLBACKS = [
    'NEWEST6.stable'     => "6.49.22 1789563951\n",
    'NEWESTa6.stable'    => "6.49.22 1789563951\n",
    'NEWEST6.long-term'  => "6.49.22 1789563951\n",
    'NEWESTa6.long-term' => "6.49.22 1789563951\n",
    'NEWEST6.upgrade'    => "7.12.1 1700221125\n",
    'NEWESTa6.upgrade'   => "7.23.7 1789561155\n",
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

/**
 * Reads cache entry.
 * @param string $key
 * @param bool $checkTTL If true, returns null when entry is older than CACHE_TTL
 * @return array|null Returns ['value' => string, 'timestamp' => int] or null
 */
function readCacheEntry(string $key, bool $checkTTL = true): ?array
{
    if (!is_file(CACHE_FILE) || !is_readable(CACHE_FILE)) {
        return null;
    }
    $lines = @file(CACHE_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return null;
    }
    
    $now = time();
    foreach ($lines as $line) {
        $parts = explode('=', $line, 2);
        if (count($parts) === 2 && trim($parts[0]) === $key) {
            // Format: "value|cache_timestamp"
            $valueParts = explode('|', trim($parts[1]), 2);
            if (count($valueParts) === 2) {
                $value = $valueParts[0];
                $cacheTime = (int)$valueParts[1];
                
                if ($checkTTL && ($now - $cacheTime) > CACHE_TTL) {
                    return null; // Stale cache
                }
                
                return $value !== '' 
                    ? ['value' => $value . "\n", 'timestamp' => $cacheTime]
                    : null;
            }
        }
    }
    return null;
}

/**
 * Reads only the cached value (convenience wrapper).
 */
function readCache(string $key, bool $checkTTL = true): ?string
{
    $entry = readCacheEntry($key, $checkTTL);
    return $entry !== null ? $entry['value'] : null;
}

/**
 * Atomic write to cache with timestamp.
 */
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
        
        $newValue = $value . '|' . time();
        
        $lines = [];
        $found = false;
        foreach ($existing as $line) {
            $parts = explode('=', $line, 2);
            if (count($parts) === 2 && trim($parts[0]) === $key) {
                $lines[] = $key . '=' . $newValue;
                $found = true;
            } else {
                $lines[] = $line;
            }
        }
        if (!$found) {
            $lines[] = $key . '=' . $newValue;
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
    // 1. Try stale cache (ignore TTL) — better old data than nothing
    $staleCached = readCache($cacheKey, false);
    if ($staleCached !== null) {
        return $staleCached;
    }
    
    // 2. Try local files
    switch ($file) {
        case 'NEWEST6.stable':
        case 'NEWESTa6.stable':
            $local = readLocalFallback(LOCAL_STABLE_FILE);
            if ($local !== null) return $local;
            break;

        case 'NEWEST6.long-term':
        case 'NEWESTa6.long-term':
            $local = readLocalFallback(LOCAL_LONGTERM_FILE);
            if ($local !== null) return $local;
            break;
    }
    
    // 3. Hardcoded defaults
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

// ---------- extract version ----------
$version = $_GET['version'] ?? '6.0';
if (!preg_match('/^\d+(\.\d+)*$/', $version)) {
    $version = '6.0';
}

$cacheKey = $file . '_' . $version;

// ---------- FAST PATH: check fresh cache ----------
$freshCache = readCache($cacheKey, true); // with TTL check
if ($freshCache !== null) {
    $payload = $freshCache;
    
    // Skip upstream entirely — just serve fresh cache
    header('HTTP/1.0 200 OK');
    header('Content-Type: text/plain');
    header('Content-Length: ' . strlen($payload));
    header('Connection: close');
    header('Cache-Control: no-store');
    header('X-Cache: HIT');
    
    @ini_set('zlib.output_compression', '0');
    @ini_set('output_handler', '');
    while (ob_get_level() > 0) { ob_end_clean(); }
    
    echo $payload;
    exit;
}

// ---------- SLOW PATH: cache is stale or missing, go upstream ----------
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
    $newPayload = rtrim($body, "\r\n \t") . "\n";
    
    // Read stale cache (ignore TTL) to compare values
    $staleCached = readCache($cacheKey, false);
    
    // Write to cache ONLY if data changed
    if ($newPayload !== $staleCached) {
        writeCache($cacheKey, $newPayload);
    }
    
    $payload = $newPayload;
    $cacheStatus = 'MISS';
} else {
    error_log(sprintf(
        '[mt-upgrade-proxy-v6] upstream fail: file=%s version=%s url=%s http=%s curl_err=%s',
        $file, $version, $url, $httpCode, $curlErr ?: '-'
    ));
    
    // Use stale cache or fallback chain
    $payload = resolveFallback($cacheKey, $file, $FALLBACKS);
    $cacheStatus = 'STALE';
}

// ---------- headers ----------
header('HTTP/1.0 200 OK');
header('Content-Type: text/plain');
header('Content-Length: ' . strlen($payload));
header('Connection: close');
header('Cache-Control: no-store');
header('X-Cache: ' . $cacheStatus);

@ini_set('zlib.output_compression', '0');
@ini_set('output_handler', '');
while (ob_get_level() > 0) { ob_end_clean(); }

echo $payload;
