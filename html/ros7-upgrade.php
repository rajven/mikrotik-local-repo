<?php
/**
 * Proxy for upgrade.mikrotik.com
 *
 * Cache key:   "<file>_<version>"   (e.g. "NEWESTa7.stable_7.24.4")
 * Cache line:  "<file>_<version>=<value>|<timestamp>"
 *
 * Policy:
 *   - Если в кэше есть запись для (file, version) — отдаём её, upstream не трогаем.
 *   - Иначе — идём в upstream, при валидном ответе сохраняем и отдаём.
 *   - Если upstream недоступен — local-fallback файл, затем хардкод.
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 2;
const TOTAL_TIMEOUT   = 3;

const CACHE_FILE = __DIR__ . '/routeros/ros7.version.cache';

const LOCAL_STABLE_FILE    = __DIR__ . '/NEWEST7.stable';
const LOCAL_LONGTERM_FILE  = __DIR__ . '/NEWEST7.stable';
const LOCAL_STABLE_AFILE   = __DIR__ . '/NEWESTa7.stable';
const LOCAL_LONGTERM_AFILE = __DIR__ . '/NEWESTa7.long-term';

$FALLBACKS = [
    'NEWEST7.stable'     => "7.12.1 1700221125\n",
    'NEWEST7.long-term'  => "7.12.1 1700221125\n",
    'NEWESTa7.stable'    => "7.24.5 1790691687\n",
    'NEWESTa7.long-term' => "7.23.8 1791452776\n",
];

/* ---------------- helpers ---------------- */

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
    return $data === '' ? null : $data . "\n";
}

/**
 * Возвращает значение из кэша для ключа или null.
 */
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
        if (count($parts) !== 2) {
            continue;
        }
        if (trim($parts[0]) !== $key) {
            continue;
        }
        // Формат значения: "value|timestamp"
        $valueParts = explode('|', trim($parts[1]), 2);
        if (count($valueParts) !== 2) {
            continue;
        }
        $value = $valueParts[0];
        return $value !== '' ? $value . "\n" : null;
    }
    return null;
}

/**
 * Атомарно пишет значение в кэш, только если:
 *   - записи для ключа ещё нет, ИЛИ
 *   - существующее значение отличается.
 *
 * Чтение и запись — под одним flock(LOCK_EX), поэтому между
 * проверкой и записью никто не вклинится.
 *
 * @return bool true — записали, false — не потребовалось (уже есть такое же)
 */
function writeCacheIfChanged(string $key, string $value): bool
{
    $dir = dirname(CACHE_FILE);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }

    $value = trim($value, "\r\n \t");
    if ($value === '') {
        return false;
    }

    $fp = @fopen(CACHE_FILE, 'c+');
    if (!$fp) {
        return false;
    }
    if (!flock($fp, LOCK_EX)) {
        fclose($fp);
        return false;
    }

    try {
        rewind($fp);
        $content = stream_get_contents($fp);
        $existing = [];
        if ($content !== false && $content !== '') {
            $existing = array_filter(
                explode("\n", $content),
                fn($line) => $line !== ''
            );
        }

        // Ищем ключ и заодно проверяем текущее значение.
        $lines        = [];
        $found        = false;
        $currentValue = null;

        foreach ($existing as $line) {
            $parts = explode('=', $line, 2);
            if (count($parts) === 2 && trim($parts[0]) === $key) {
                $found = true;
                // value|timestamp
                $vp = explode('|', trim($parts[1]), 2);
                if (count($vp) === 2) {
                    $currentValue = $vp[0];
                }
                // Пока оставляем как есть — перезапишем ниже, если нужно.
                $lines[] = $line;
            } else {
                $lines[] = $line;
            }
        }

        // Уже есть точно такое же значение — ничего не пишем.
        if ($found && $currentValue === $value) {
            return false;
        }

        // Готовим новую строку.
        $newLine = $key . '=' . $value . '|' . time();

        if ($found) {
            // Заменяем существующую строку.
            foreach ($lines as $i => $line) {
                $parts = explode('=', $line, 2);
                if (count($parts) === 2 && trim($parts[0]) === $key) {
                    $lines[$i] = $newLine;
                    break;
                }
            }
        } else {
            $lines[] = $newLine;
        }

        ftruncate($fp, 0);
        rewind($fp);
        fwrite($fp, implode("\n", $lines) . "\n");
        fflush($fp);

        return true;
    } finally {
        flock($fp, LOCK_UN);
        fclose($fp);
    }
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
    while (ob_get_level() > 0) {
        ob_end_clean();
    }

    echo $payload;
    exit;
}

/* ---------------- маршрутизация ---------------- */

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$file = basename($path);

if (!isset($FALLBACKS[$file])) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Unknown resource\n";
    exit;
}

$version = $_GET['version'] ?? '7.0';
if (!preg_match('/^\d+(\.\d+)*$/', $version)) {
    $version = '7.0';
}

$cacheKey = $file . '_' . $version;

/* ---------- 1. Кэш: если есть — отдаём и выходим ---------- */
$cached = readCache($cacheKey);
if ($cached !== null) {
    serve($cached, 'HIT');
}

/* ---------- 2. Идём в upstream ---------- */
$query = $_SERVER['QUERY_STRING'] ?? '';
$url   = UPSTREAM_BASE . $file . ($query !== '' ? '?' . $query : '');

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER    => true,
    CURLOPT_CONNECTTIMEOUT    => CONNECT_TIMEOUT,
    CURLOPT_TIMEOUT           => TOTAL_TIMEOUT,
    CURLOPT_USERAGENT         => 'RouterOS ' . $version,
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
    $payload = rtrim($body, "\r\n \t") . "\n";
    $again = readCache($cacheKey);
    if ($again === null) {
        writeCacheIfChanged($cacheKey, $payload);
    }
    serve($payload, 'MISS');
}

/* ---------- 3. Upstream упал — fallback ---------- */
error_log(sprintf(
    '[mt-upgrade-proxy] upstream fail: file=%s version=%s url=%s http=%s curl_err=%s',
    $file, $version, $url, $httpCode, $curlErr ?: '-'
));

$payload = resolveFallback($file, $FALLBACKS);
serve($payload, 'STALE');
