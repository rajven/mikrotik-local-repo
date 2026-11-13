<?php
/**
 * mt_cache.php - version-cache helpers shared by ros6-upgrade.php,
 * ros7-upgrade.php and ros-warmup.php.
 *
 * Cache file format: one entry per line, "key=value|timestamp", where the key
 * is "<endpoint>_<requested-version>" and the timestamp is the unix time the
 * answer was last (re)validated against upstream. Both helpers lock the file
 * with flock, so concurrent PHP-FPM workers and the warm-up run cannot
 * interleave their writes.
 */

/**
 * Returns ['value' => "...\n", 'ts' => <unix>] or null when there is no
 * usable entry. The timestamp is what makes re-validation possible.
 */
function readCacheEntry(string $cacheFile, string $key): ?array
{
    if (!is_file($cacheFile) || !is_readable($cacheFile)) return null;
    $lines = @file($cacheFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) return null;
    foreach ($lines as $line) {
        $parts = explode('=', $line, 2);
        if (count($parts) !== 2) continue;
        if (trim($parts[0]) !== $key) continue;
        $valueParts = explode('|', trim($parts[1]), 2);
        if (count($valueParts) !== 2) continue;
        $value = $valueParts[0];
        if ($value === '') return null;
        return ['value' => $value . "\n", 'ts' => (int) $valueParts[1]];
    }
    return null;
}

function writeCacheIfChanged(string $cacheFile, string $key, string $value): bool
{
    $dir = dirname($cacheFile);
    if (!is_dir($dir)) @mkdir($dir, 0755, true);
    $value = trim($value, "\r\n\t ");
    if ($value === '') return false;

    $fp = @fopen($cacheFile, 'c+');
    if (!$fp) return false;
    if (!flock($fp, LOCK_EX)) { fclose($fp); return false; }
    try {
        rewind($fp);
        $content = stream_get_contents($fp);
        $existing = [];
        if ($content !== false && $content !== '') {
            $existing = array_filter(explode("\n", $content), fn($l) => $l !== '');
        }
        $lines = []; $found = false; $currentValue = null;
        foreach ($existing as $line) {
            $parts = explode('=', $line, 2);
            if (count($parts) === 2 && trim($parts[0]) === $key) {
                $found = true;
                $vp = explode('|', trim($parts[1]), 2);
                if (count($vp) === 2) $currentValue = $vp[0];
                $lines[] = $line;
            } else {
                $lines[] = $line;
            }
        }
        // Refresh the timestamp even when the answer did not change, otherwise
        // an unchanged release would be re-validated on every single request.
        $changed = !$found || $currentValue !== $value;
        $newLine = $key . '=' . $value . '|' . time();
        if ($found) {
            foreach ($lines as $i => $line) {
                $parts = explode('=', $line, 2);
                if (count($parts) === 2 && trim($parts[0]) === $key) { $lines[$i] = $newLine; break; }
            }
        } else {
            $lines[] = $newLine;
        }
        ftruncate($fp, 0); rewind($fp);
        fwrite($fp, implode("\n", $lines) . "\n");
        fflush($fp);
        return $changed;
    } finally {
        flock($fp, LOCK_UN); fclose($fp);
    }
}
