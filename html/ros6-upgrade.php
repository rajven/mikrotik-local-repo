<?php
/**
 * Proxy for upgrade.mikrotik.com (RouterOS v6 branch)
 * Accepts requests such as:
 *   /routeros/NEWEST6.upgrade?version=6.49.21
 *   /routeros/NEWESTa6.upgrade?version=6.49.21
 *
 * Cache key:   "<file>_<version>"   (e.g. "NEWEST6.upgrade_6.49.21")
 * Cache line:  "<file>_<version>=<value>|<timestamp>"
 *
 * Policy:
 *   - Если в кэше есть запись для (file, version) — отдаём её, upstream не трогаем.
 *   - Иначе — идём в upstream, при валидном ответе сохраняем (если значения
 *     ещё нет или оно изменилось) и отдаём.
 *   - Если upstream недоступен — local-fallback файл, затем хардкод.
 */

const UPSTREAM_BASE   = 'https://upgrade.mikrotik.com/routeros/';
const CONNECT_TIMEOUT = 2;
const TOTAL_TIMEOUT   = 3;

const CACHE_FILE = __DIR__ . '/routeros/ros6.version.cache';

const LOCAL_STABLE_FILE   = __DIR__ . '/LATEST.6';
const LOCAL_LONGTERM_FILE = __DIR__ . '/LATEST.6fix';

$FALLBACKS = [
    'NEWEST6.stable'     => "6.49.23 1791389116\n",
    'NEWESTa6.stable'    => "6.49.23 1791389116\n",
    'NEWEST6.long-term'  => "6.49.23 1791389116\n",
    'NEWESTa6.long-term' => "6.49.23 1791389116\n",
    'NEWEST6.upgrade'    => "7.12.1 1700221125\n",
    'NEWESTa6.upgrade'   => "7.23.8 1791452776\n",
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
 * TTL больше нет — запись живёт, пока её не заменит успешный upstream.
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
 * Атомарная запись в кэш.
 *
 * Пишет только если:
 *   - записи для ключа ещё нет, ИЛИ
 *   - существующее значение отличается от нового.
 *
 * Чтение и запись — под одним flock(LOCK_EX), поэтому при гонке
 * нескольких параллельных запросов фактическая запись произойдёт
 * только один раз.
 *
 * @return bool true — записали, false — не потребовалось
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

        $lines        = [];
        $found        = false;
        $currentValue = null;

        foreach ($existing as $line) {
            $parts = explode('=', $line, 2);
            if (count($parts) === 2 && trim($parts[0]) === $key) {
                $found = true;
                $vp = explode('|', trim($parts[1]), 2);
                if (count($vp) === 2) {
                    $currentValue = $vp[0];
                }
                $lines[] = $line; // перезапишем ниже, если нужно
            } else {
                $lines[] = $line;
            }
        }

        // Уже есть точно такое же значение — ничего не пишем.
        if ($found && $currentValue === $value) {
            return false;
        }

        $newLine = $key . '=' . $value . '|' . time();

        if ($found) {
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
    header('Content-Length: 17');
    header('Connection: close');
    echo "Unknown resource\n";
    exit;
}

$version = $_GET['version'] ?? '6.0';
if (!preg_match('/^\d+(\.\d+)*$/', $version)) {
    $version = '6.0';
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

/* ---------- 3. Ответ ---------- */
if ($isValid) {
    $payload = rtrim($body, "\r\n \t") . "\n";

    // Быстрая проверка без лока: вдруг кто-то уже записал, пока мы ходили
    // в upstream. Отсекает большинство гонок без взятия flock.
    $again = readCache($cacheKey);
    if ($again === null) {
        // Никто не записал — пишем под локом, но с повторной проверкой
        // «а вдруг записали прямо сейчас». Идемпотентно.
        writeCacheIfChanged($cacheKey, $payload);
    }

    serve($payload, 'MISS');
}

/* ---------- 4. Upstream упал — fallback ---------- */
error_log(sprintf(
    '[mt-upgrade-proxy-v6] upstream fail: file=%s version=%s url=%s http=%s curl_err=%s',
    $file, $version, $url, $httpCode, $curlErr ?: '-'
));

$payload = resolveFallback($file, $FALLBACKS);
serve($payload, 'STALE');
