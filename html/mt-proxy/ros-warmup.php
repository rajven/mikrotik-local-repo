<?php
/**
 * ros-warmup.php — RouterOS proxy cache warmup via web server.
 *
 * Collects all unique firmware versions from the devices DB
 * (current_firmware, upgrade_firmware, last_new_version) and makes
 * requests to the upstream MikroTik server for each (file, version)
 * combination in order to pre-populate the file cache.
 *
 * File selection logic per version:
 *   - ROS 7 < 7.12.1   → NEWEST7.*
 *   - ROS 7 >= 7.12.1  → NEWESTa7.*
 *   - ROS 6 < 6.49.19  → NEWEST6.*
 *   - ROS 6 >= 6.49.19 → NEWESTa6.*
 *
 * Protection: a secret token is required in the GET parameter ?token=SECRET
 *
 * Example invocation:
 *   curl "http://localhost/routeros/ros-warmup.php?token=YOUR_SECRET_TOKEN"
 */

declare(strict_types=1);

// ============================================================
// Load DB and config
// ============================================================
require __DIR__ . '/db.php';
$CFG = require __DIR__ . '/mt_proxy_config.php';

if (!isset($_GET['token']) || $_GET['token'] !== $CFG['WARMUP_TOKEN']) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Access denied: invalid or missing token\n";
    exit;
}

// ============================================================
// HTTP headers
// ============================================================
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');

// ============================================================
// Collect unique versions from the DB
// ============================================================
function collectVersionsFromDB(): array
{
    $pdo = db();
    $stmt = $pdo->query("
        SELECT DISTINCT current_firmware AS v FROM devices WHERE current_firmware <> ''
        UNION
        SELECT DISTINCT upgrade_firmware FROM devices WHERE upgrade_firmware <> ''
        UNION
        SELECT DISTINCT last_new_version FROM devices WHERE last_new_version <> ''
    ");
    $versions = [];
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $v) {
        $v = trim((string)$v);
        if ($v !== '' && preg_match('/^\d+(\.\d+)+$/', $v)) {
            $versions[$v] = true;
        }
    }
    return array_keys($versions);
}

// ============================================================
// Determine the major version (6 or 7)
// ============================================================
function majorVersion(string $v): string
{
    $dot = strpos($v, '.');
    return $dot === false ? $v : substr($v, 0, $dot);
}

// ============================================================
// Determine the list of files that a device with the given
// version will request
// ============================================================
function filesForVersion(string $v): array
{
    $major = majorVersion($v);

    if ($major === '6') {
        if (version_compare($v, ROS6_AFILE_THRESHOLD, '>=')) {
            return [
                'NEWESTa6.stable',
                'NEWESTa6.long-term',
                'NEWESTa6.upgrade',
            ];
        }
        return [
            'NEWEST6.stable',
            'NEWEST6.long-term',
            'NEWEST6.upgrade',
        ];
    }

    if ($major === '7') {
        if (version_compare($v, ROS7_AFILE_THRESHOLD, '>=')) {
            return [
                'NEWESTa7.stable',
                'NEWESTa7.long-term',
            ];
        }
        return [
            'NEWEST7.stable',
            'NEWEST7.long-term',
        ];
    }

    return [];
}

// ============================================================
// Cache operations (identical to ros6/ros7-upgrade.php)
// ============================================================
function readCache(string $cacheFile, string $key): ?string
{
    if (!is_file($cacheFile) || !is_readable($cacheFile)) {
        return null;
    }
    $lines = @file($cacheFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
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
        $valueParts = explode('|', trim($parts[1]), 2);
        if (count($valueParts) !== 2) {
            continue;
        }
        $value = $valueParts[0];
        return $value !== '' ? $value . "\n" : null;
    }
    return null;
}

function writeCacheIfChanged(string $cacheFile, string $key, string $value): bool
{
    $dir = dirname($cacheFile);
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $value = trim($value, "\r\n\t");
    if ($value === '') {
        return false;
    }
    $fp = @fopen($cacheFile, 'c+');
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
            $existing = array_filter(explode("\n", $content), fn($line) => $line !== '');
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
                $lines[] = $line;
            } else {
                $lines[] = $line;
            }
        }
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

// ============================================================
// HTTP request to the upstream MikroTik server
// ============================================================
function fetchFromUpstream(string $file, string $version, string $userAgentPrefix, int $timeout): array
{
    $url = $CFG['upstream_base'] . $file . '?version=' . urlencode($version);
    $userAgent = $userAgentPrefix . $version;

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER    => true,
        CURLOPT_CONNECTTIMEOUT    => $CFG['connect_timeout'],
        CURLOPT_TIMEOUT           => $timeout,
        CURLOPT_USERAGENT         => $userAgent,
        CURLOPT_SSL_VERIFYPEER    => true,
        CURLOPT_SSL_VERIFYHOST    => 2,
        CURLOPT_ENCODING          => '',
        CURLOPT_HTTP_VERSION      => CURL_HTTP_VERSION_1_1,
        CURLOPT_DNS_CACHE_TIMEOUT => 300,
    ]);
    $body     = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr  = curl_error($ch);
    curl_close($ch);

    $isValid = (
        $curlErr === ''
        && $httpCode === 200
        && is_string($body)
        && preg_match('/^\s*\d+(\.\d+)+\s+\d+/', $body) === 1
    );

    return [
        'success'   => $isValid,
        'url'       => $url,
        'userAgent' => $userAgent,
        'httpCode'  => $httpCode,
        'error'     => $curlErr,
        'body'      => $isValid ? rtrim($body, "\r\n\t") . "\n" : null,
    ];
}

// ============================================================
// HTML output helpers
// ============================================================
function htmlHeader(): void
{
    echo <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RouterOS Cache Warmup</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 20px; background: #0f172a; color: #e2e8f0; }
h1 { color: #38bdf8; }
.log-entry { background: #1e293b; border-left: 4px solid #334155; padding: 10px; margin: 8px 0; border-radius: 4px; font-family: ui-monospace, monospace; font-size: 13px; }
.log-entry.ok { border-left-color: #22c55e; }
.log-entry.skip { border-left-color: #38bdf8; }
.log-entry.fail { border-left-color: #ef4444; }
.log-entry.info { border-left-color: #f59e0b; }
.mono { font-family: ui-monospace, monospace; }
.url { color: #94a3b8; font-size: 11px; word-break: break-all; }
.summary { background: #334155; padding: 15px; border-radius: 8px; margin: 20px 0; }
</style>
</head>
<body>
<h1>🔥 RouterOS Cache Warmup</h1>
<p>Started at: <span class="mono">

HTML;
    echo date('Y-m-d H:i:s') . "</span></p>\n";
}

function htmlFooter(int $total, int $ok, int $skipped, int $failed): void
{
    echo <<<HTML
<div class="summary">
<h2>Summary</h2>
<p><strong>Total:</strong> $total</p>
<p><strong>Successful:</strong> <span style="color:#22c55e">$ok</span></p>
<p><strong>Skipped (cached):</strong> <span style="color:#38bdf8">$skipped</span></p>
<p><strong>Failed:</strong> <span style="color:#ef4444">$failed</span></p>
</div>
<p>Finished at: <span class="mono">
HTML;
    echo date('Y-m-d H:i:s') . "</span></p>\n";
    echo "</body>\n</html>\n";
}

function logHtml(string $type, string $message, string $details = ''): void
{
    $escaped = htmlspecialchars($message);
    $detailsHtml = $details !== '' ? '<div class="url">' . htmlspecialchars($details) . '</div>' : '';
    echo "<div class=\"log-entry $type\">$escaped$detailsHtml</div>\n";
    @ob_flush();
    @flush();
}

// ============================================================
// Main logic
// ============================================================
htmlHeader();

$versions = collectVersionsFromDB();

if (empty($versions)) {
    logHtml('info', 'No versions found in DB — nothing to warm up');
    htmlFooter(0, 0, 0, 0);
    exit;
}

// Group versions by major branch
$byMajor = [];
foreach ($versions as $v) {
    $major = majorVersion($v);
    if ($major === '6' || $major === '7') {
        $byMajor[$major][] = $v;
    } else {
        logHtml('info', "Skip unknown major version: $v");
    }
}

logHtml('info', sprintf(
    'Versions to warm up: %d total, branches: %s',
    count($versions),
    implode(', ', array_map(fn($m) => $m . '.x (' . count($byMajor[$m]) . ')', array_keys($byMajor)))
));

// ============================================================
// Warm up
// ============================================================
$total   = 0;
$ok      = 0;
$skipped = 0;
$failed  = 0;
$timeout = 5; // seconds per request

foreach ($byMajor as $major => $versionList) {
    $branch    = $CFG['v' . $major];
    $cacheFile = $branch['cache_file'];
    $userAgent = $branch['user_agent'];

    logHtml('info', "Processing ROS $major.x branch (" . count($versionList) . " versions)");

    foreach ($versionList as $v) {
        $files = filesForVersion($v);

        foreach ($files as $file) {
            $total++;
            $cacheKey = $file . '_' . $v;

            // Check if already cached
            $cached = readCache($cacheFile, $cacheKey);
            if ($cached !== null) {
                $skipped++;
                logHtml('skip', "SKIP  $file v$v (already cached)");
                continue;
            }

            // Request upstream
            $result = fetchFromUpstream($file, $v, $userAgent, $timeout);

            if ($result['success']) {
                writeCacheIfChanged($cacheFile, $cacheKey, $result['body']);
                $display = trim($result['body']);
                logHtml('ok', "OK    $file v$v → $display", $result['url'] . ' | UA: ' . $result['userAgent']);
                $ok++;
            } else {
                logHtml('fail', "FAIL  $file v$v (http={$result['httpCode']} err={$result['error']})", $result['url'] . ' | UA: ' . $result['userAgent']);
                $failed++;
            }
        }
    }
}

htmlFooter($total, $ok, $skipped, $failed);
