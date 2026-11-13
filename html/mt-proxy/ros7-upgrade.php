<?php
/**
 * Proxy for upgrade.mikrotik.com ROS 7 branch
 */
$CFG = require __DIR__ . '/mt_proxy_config.php';
$V7  = $CFG['v7'];
define('UPSTREAM_BASE',   $CFG['upstream_base']);
define('CONNECT_TIMEOUT', $CFG['connect_timeout']);
define('TOTAL_TIMEOUT',   $CFG['total_timeout']);
define('CACHE_FILE', $V7['cache_file']);
define('CACHE_REVALIDATE', (int) ($CFG['cache_revalidate'] ?? 21600));
define('LOG_PREFIX', $V7['log_prefix']);
define('DEFAULT_VERSION', $V7['default_version']);
define('USER_AGENT_PREFIX', $V7['user_agent']);
define('LOCAL_STABLE_FILE',         $V7['local_stable']);
define('LOCAL_LONGTERM_FILE',       $V7['local_longterm']);
define('LOCAL_STABLE_AFILE',        $V7['local_stable_afile']);
define('LOCAL_LONGTERM_AFILE',      $V7['local_longterm_afile']);
$FALLBACKS = $CFG['fallbacks'];

require __DIR__ . '/mt_cache.php';

/* ---------------- helpers ---------------- */
function readLocalFallback(string $path): ?string
{
    if (!is_file($path) || !is_readable($path)) return null;
    $data = @file_get_contents($path);
    if ($data === false) return null;
    $data = trim($data, "\r\n\t ");
    return $data === '' ? null : $data . "\n";
}

function resolveFallback(string $file, array $defaults): string
{
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
    return $defaults[$file];
}

function serve(string $payload, string $cacheStatus): void
{
    header('HTTP/1.0 200 OK');
    header('Content-Type: text/plain');
    header('Content-Length: ' . strlen($payload));
    header('Connection: close');
    header('Cache-Control: no-store');
    header('X-Cache: ' . $cacheStatus);
    @ini_set('zlib.output_compression', '0');
    @ini_set('output_handler', '');
    while (ob_get_level() > 0) ob_end_clean();
    echo $payload;
    exit;
}

/* ---------------- routing ---------------- */
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$file = basename($path);

if (!isset($FALLBACKS[$file])) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    header('Connection: close');
    echo "Unknown resource\n";
    exit;
}

$version = $_GET['version'] ?? DEFAULT_VERSION;
if (!preg_match('/^\d+(\.\d+)*$/', $version)) {
    $version = DEFAULT_VERSION;
}

$cacheKey = $file . '_' . $version;

/* ---------- 1. Cache ---------- */
/* $stale keeps an expired answer as the last resort: better than a generic
   fallback value when upstream is unreachable. */
$stale = null;
$entry = readCacheEntry(CACHE_FILE, $cacheKey);
if ($entry !== null) {
    if (CACHE_REVALIDATE <= 0 || (time() - $entry['ts']) < CACHE_REVALIDATE) {
        serve($entry['value'], 'HIT');
    }
    $stale = $entry['value'];
}

/* ---------- 2. Upstream ---------- */
$query = $_SERVER['QUERY_STRING'] ?? '';
$url   = UPSTREAM_BASE . $file . ($query !== '' ? '?' . $query : '');
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER    => true,
    CURLOPT_CONNECTTIMEOUT    => CONNECT_TIMEOUT,
    CURLOPT_TIMEOUT           => TOTAL_TIMEOUT,
    CURLOPT_USERAGENT         => USER_AGENT_PREFIX . $version,
    CURLOPT_SSL_VERIFYPEER    => true,
    CURLOPT_SSL_VERIFYHOST    => 2,
    CURLOPT_ENCODING          => '',
    CURLOPT_HTTP_VERSION      => CURL_HTTP_VERSION_1_1,
    CURLOPT_DNS_CACHE_TIMEOUT => 300,
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

if ($isValid) {
    $payload = rtrim($body, "\r\n\t ") . "\n";
    writeCacheIfChanged(CACHE_FILE, $cacheKey, $payload);
    serve($payload, 'MISS');
}

/* ---------- 3. Upstream failed - fallback ---------- */
error_log(sprintf(
    '%s upstream fail: file=%s version=%s url=%s http=%s curl_err=%s',
    LOG_PREFIX, $file, $version, $url, $httpCode, $curlErr ?: '-'
));
if ($stale !== null) serve($stale, 'STALE');
$payload = resolveFallback($file, $FALLBACKS);
serve($payload, 'STALE');
