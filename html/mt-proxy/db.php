<?php
/**
 * db.php — инициализация SQLite и вспомогательные функции
 */

define('DB_PATH', __DIR__ . '/mt_proxy.db');

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO('sqlite:' . DB_PATH);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $pdo->exec('PRAGMA journal_mode = WAL');
        $pdo->exec('PRAGMA busy_timeout = 1000');   // ждать блокировку до 1с вместо мгновенной ошибки
        $pdo->exec('PRAGMA synchronous = NORMAL');  // безопасно в WAL, коммиты в разы быстрее
        $pdo->exec('PRAGMA foreign_keys = ON');

        $pdo->exec("
            CREATE TABLE IF NOT EXISTS devices (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                serial          TEXT NOT NULL,
                model           TEXT NOT NULL DEFAULT '',
                comment         TEXT NOT NULL DEFAULT '',
                allowed         TEXT NOT NULL DEFAULT '[]',
                source          TEXT NOT NULL DEFAULT 'auto',
                current_firmware TEXT NOT NULL DEFAULT '',
                upgrade_firmware TEXT NOT NULL DEFAULT '',
                last_new_version TEXT NOT NULL DEFAULT '',
                created_at      TEXT NOT NULL DEFAULT (datetime('now')),
                last_seen_at    TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(serial)
            );
            CREATE INDEX IF NOT EXISTS idx_devices_serial ON devices(serial);
            CREATE INDEX IF NOT EXISTS idx_devices_model  ON devices(model);
        ");

        // Таблица IP-адресов устройств (IP может быть несколько, IP может быть не уникальным)
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS device_ips (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                serial      TEXT NOT NULL,
                ip_address  TEXT NOT NULL,
                first_seen  TEXT NOT NULL DEFAULT (datetime('now')),
                last_seen   TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(serial, ip_address)
            );
            CREATE INDEX IF NOT EXISTS idx_device_ips_serial ON device_ips(serial);
            CREATE INDEX IF NOT EXISTS idx_device_ips_ip     ON device_ips(ip_address);
        ");

        $pdo->exec("
            CREATE TABLE IF NOT EXISTS global_versions (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                version TEXT NOT NULL UNIQUE
            );
        ");

        // Служебная таблица (флаги миграций и т.п.)
        $pdo->exec("
            CREATE TABLE IF NOT EXISTS meta (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL DEFAULT ''
            );
        ");

        // Миграции для существующих БД
        $stmt = $pdo->query("PRAGMA table_info(devices)");
        $cols = array_column($stmt->fetchAll(), 'name');

        if (!in_array('comment', $cols, true)) {
            $pdo->exec("ALTER TABLE devices ADD COLUMN comment TEXT NOT NULL DEFAULT ''");
        }
        if (in_array('current_version', $cols, true)) {
            try {
                $pdo->exec("ALTER TABLE devices RENAME COLUMN current_version TO current_firmware");
            } catch (Throwable $e) {
                if (!in_array('current_firmware', $cols, true)) {
                    $pdo->exec("ALTER TABLE devices ADD COLUMN current_firmware TEXT NOT NULL DEFAULT ''");
                    $pdo->exec("UPDATE devices SET current_firmware = current_version");
                }
            }
        } elseif (!in_array('current_firmware', $cols, true)) {
            $pdo->exec("ALTER TABLE devices ADD COLUMN current_firmware TEXT NOT NULL DEFAULT ''");
        }
        if (!in_array('upgrade_firmware', $cols, true)) {
            $pdo->exec("ALTER TABLE devices ADD COLUMN upgrade_firmware TEXT NOT NULL DEFAULT ''");
        }
        if (!in_array('last_new_version', $cols, true)) {
            $pdo->exec("ALTER TABLE devices ADD COLUMN last_new_version TEXT NOT NULL DEFAULT ''");
        }

        // Одноразовая миграция из старого mt_proxy_rules.php.
        // Выполняется РОВНО ОДИН РАЗ (флаг в meta), чтобы намеренно
        // очищенные global_versions не заполнялись снова из файла.
        $stmt = $pdo->query("SELECT value FROM meta WHERE key = 'legacy_migrated'");
        if (!$stmt->fetch()) {
            migrateFromLegacy($pdo);
            $pdo->exec("INSERT OR REPLACE INTO meta(key, value) VALUES('legacy_migrated', '1')");
        }
    }
    return $pdo;
}

function migrateFromLegacy(PDO $pdo): void
{
    $legacyFile = __DIR__ . '/mt_proxy_rules.php';
    if (!is_file($legacyFile)) return;
    $rules = @require $legacyFile;
    if (!is_array($rules)) return;

    if (!empty($rules['global_versions']) && is_array($rules['global_versions'])) {
        $stmt = $pdo->prepare("INSERT OR IGNORE INTO global_versions(version) VALUES(?)");
        foreach ($rules['global_versions'] as $v) {
            $v = trim((string)$v);
            if ($v !== '') $stmt->execute([$v]);
        }
    }

    if (!empty($rules['serials']) && is_array($rules['serials'])) {
        $stmt = $pdo->prepare(
            "INSERT INTO devices(serial, model, comment, allowed, source) VALUES(?, '', '', ?, 'legacy')"
        );
        foreach ($rules['serials'] as $serial => $versions) {
            $serial = trim((string)$serial);
            if ($serial === '') continue;
            $stmt->execute([$serial, json_encode(array_values($versions))]);
        }
    }

    if (!empty($rules['models']) && is_array($rules['models'])) {
        $stmt = $pdo->prepare(
            "INSERT OR IGNORE INTO devices(serial, model, comment, allowed, source) VALUES(?, ?, '', ?, 'legacy')"
        );
        foreach ($rules['models'] as $model => $versions) {
            $model = trim((string)$model);
            if ($model === '') continue;
            $stmt->execute(['model:' . $model, $model, json_encode(array_values($versions))]);
        }
    }
}

/* ---------- CRUD ---------- */

/**
 * Зарегистрировать устройство (если его ещё нет — создать с ПУСТЫМ списком
 * разрешённых версий и source='auto'). Обновить last_seen_at и model.
 */
function deviceUpsert(string $serial, string $model): array
{
    $pdo = db();
    $now = gmdate('Y-m-d H:i:s');

    $stmt = $pdo->prepare(
        "INSERT INTO devices(serial, model, allowed, source, last_seen_at)
         VALUES(?, ?, '[]', 'auto', ?)
         ON CONFLICT(serial) DO UPDATE SET
            model = CASE WHEN excluded.model <> '' THEN excluded.model ELSE devices.model END,
            last_seen_at = excluded.last_seen_at"
    );
    $stmt->execute([$serial, $model, $now]);

    $stmt = $pdo->prepare("SELECT * FROM devices WHERE serial = ?");
    $stmt->execute([$serial]);
    return $stmt->fetch();
}

/**
 * Обновить информацию о прошивках устройства.
 * @param string $serial          Серийный номер
 * @param string $currentFirmware Boot firmware (текущая загрузочная прошивка)
 * @param string $upgradeFirmware Upgrade firmware (рабочая прошивка)
 * @param string $newVersion      Запрошенная версия для обновления
 */
function deviceUpdateFirmwares(string $serial, string $currentFirmware, string $upgradeFirmware, string $newVersion): void
{
    if ($serial === '') return;
    $pdo = db();
    $now = gmdate('Y-m-d H:i:s');
    $stmt = $pdo->prepare(
        "UPDATE devices 
         SET current_firmware = ?, upgrade_firmware = ?, last_new_version = ?, last_seen_at = ?
         WHERE serial = ?"
    );
    $stmt->execute([$currentFirmware, $upgradeFirmware, $newVersion, $now, $serial]);
}

/* ---------- IP-адреса устройств ---------- */

function deviceIpsUpsert(string $serial, string $ip): void
{
    if ($serial === '' || $ip === '') return;
    $pdo = db();
    $now = gmdate('Y-m-d H:i:s');
    $stmt = $pdo->prepare(
        "INSERT INTO device_ips(serial, ip_address, first_seen, last_seen)
         VALUES(?, ?, ?, ?)
         ON CONFLICT(serial, ip_address) DO UPDATE SET last_seen = excluded.last_seen"
    );
    $stmt->execute([$serial, $ip, $now, $now]);
}

function deviceIpsList(string $serial): array
{
    if ($serial === '') return [];
    $pdo = db();
    $stmt = $pdo->prepare(
        "SELECT ip_address, first_seen, last_seen FROM device_ips
         WHERE serial = ? ORDER BY last_seen DESC"
    );
    $stmt->execute([$serial]);
    return $stmt->fetchAll();
}

function deviceSerialsByIp(string $ip): array
{
    if ($ip === '') return [];
    $pdo = db();
    $stmt = $pdo->prepare("SELECT DISTINCT serial FROM device_ips WHERE ip_address = ?");
    $stmt->execute([$ip]);
    return array_column($stmt->fetchAll(), 'serial');
}

function deviceIpsForSerials(array $serials): array
{
    if (empty($serials)) return [];
    $pdo = db();
    $placeholders = implode(',', array_fill(0, count($serials), '?'));
    $stmt = $pdo->prepare(
        "SELECT serial, ip_address, last_seen FROM device_ips
         WHERE serial IN ($placeholders)
         ORDER BY last_seen DESC"
    );
    $stmt->execute(array_values($serials));
    $result = [];
    foreach ($stmt->fetchAll() as $row) {
        $result[$row['serial']][] = $row;
    }
    return $result;
}

/* ---------- Devices list/get/update/delete ---------- */

function deviceList(string $search = ''): array
{
    $pdo = db();

    $searchByIp = false;
    $ipSerials  = [];
    if ($search !== '' && preg_match('/^\d{1,3}(\.\d{1,3}){0,3}/', $search)) {
        $searchByIp = true;
        $ipSerials  = deviceSerialsByIp($search);
    }

    if ($search !== '') {
        if ($searchByIp && !empty($ipSerials)) {
            $placeholders = implode(',', array_fill(0, count($ipSerials), '?'));
            $stmt = $pdo->prepare(
                "SELECT * FROM devices
                 WHERE serial IN ($placeholders)
                    OR serial LIKE :s OR model LIKE :s OR comment LIKE :s
                 ORDER BY last_seen_at DESC, id DESC"
            );
            $stmt->execute(array_merge(array_values($ipSerials), ['%' . $search . '%', '%' . $search . '%', '%' . $search . '%']));
        } else {
            $stmt = $pdo->prepare(
                "SELECT * FROM devices
                 WHERE serial LIKE :s OR model LIKE :s OR comment LIKE :s
                 ORDER BY last_seen_at DESC, id DESC"
            );
            $stmt->execute([':s' => '%' . $search . '%']);
        }
    } else {
        $stmt = $pdo->query("SELECT * FROM devices ORDER BY last_seen_at DESC, id DESC");
    }

    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) {
        $r['allowed_arr'] = json_decode($r['allowed'], true) ?: [];
    }

    $serials = array_column($rows, 'serial');
    $ipsMap  = deviceIpsForSerials($serials);
    foreach ($rows as &$r) {
        $r['ips'] = $ipsMap[$r['serial']] ?? [];
    }

    return $rows;
}

function deviceGet(int $id): ?array
{
    $pdo = db();
    $stmt = $pdo->prepare("SELECT * FROM devices WHERE id = ?");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if (!$row) return null;
    $row['allowed_arr'] = json_decode($row['allowed'], true) ?: [];
    $row['ips'] = deviceIpsList($row['serial']);
    return $row;
}

function deviceUpdate(int $id, string $model, string $comment, array $allowed): bool
{
    $pdo = db();
    $stmt = $pdo->prepare(
        "UPDATE devices SET model = ?, comment = ?, allowed = ? WHERE id = ?"
    );
    return $stmt->execute([$model, $comment, json_encode(array_values($allowed)), $id]);
}

/**
 * Массовое обновление списка разрешённых версий для нескольких устройств.
 * @param array  $ids     Список ID устройств
 * @param array  $allowed Список версий
 * @param string $mode    'replace' — заменить список, 'append' — добавить к существующему
 * @return int  Количество обновлённых устройств
 */
function deviceBulkSetAllowed(array $ids, array $allowed, string $mode = 'replace'): int
{
    if (empty($ids)) return 0;
    $pdo = db();
    $allowed = array_values(array_unique($allowed));
    $updated = 0;

    $pdo->beginTransaction();
    try {
        if ($mode === 'append') {
            $sel = $pdo->prepare("SELECT id, allowed FROM devices WHERE id = ?");
            $upd = $pdo->prepare("UPDATE devices SET allowed = ? WHERE id = ?");
            foreach ($ids as $id) {
                $sel->execute([$id]);
                $row = $sel->fetch();
                if (!$row) continue;
                $existing = json_decode($row['allowed'], true) ?: [];
                $merged   = array_values(array_unique(array_merge($existing, $allowed)));
                $upd->execute([json_encode($merged), $id]);
                $updated++;
            }
        } else {
            $upd = $pdo->prepare("UPDATE devices SET allowed = ? WHERE id = ?");
            $json = json_encode($allowed);
            foreach ($ids as $id) {
                $upd->execute([$json, $id]);
                $updated += $upd->rowCount();
            }
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
    return $updated;
}

function deviceDelete(int $id): bool
{
    $pdo = db();
    $row = deviceGet($id);
    if (!$row) return false;
    $pdo->prepare("DELETE FROM device_ips WHERE serial = ?")->execute([$row['serial']]);
    return $pdo->prepare("DELETE FROM devices WHERE id = ?")->execute([$id]);
}

function deviceAdd(string $serial, string $model, string $comment, array $allowed): ?int
{
    $pdo = db();
    $stmt = $pdo->prepare(
        "INSERT INTO devices(serial, model, comment, allowed, source) VALUES(?, ?, ?, ?, 'manual')"
    );
    try {
        $stmt->execute([$serial, $model, $comment, json_encode(array_values($allowed))]);
        return (int)$pdo->lastInsertId();
    } catch (Throwable $e) {
        return null;
    }
}

/* ---------- Global versions ---------- */

function globalVersionsList(): array
{
    $pdo = db();
    $stmt = $pdo->query("SELECT version FROM global_versions ORDER BY version DESC");
    return array_column($stmt->fetchAll(), 'version');
}

function globalVersionAdd(string $v): bool
{
    $v = trim($v);
    if ($v === '') return false;
    $pdo = db();
    return $pdo->prepare("INSERT OR IGNORE INTO global_versions(version) VALUES(?)")->execute([$v]);
}

function globalVersionDelete(string $v): bool
{
    $pdo = db();
    return $pdo->prepare("DELETE FROM global_versions WHERE version = ?")->execute([trim($v)]);
}

/* ---------- Fallback-цепочки ---------- */

/**
 * Файловый фолбэк: global_versions из legacy mt_proxy_rules.php.
 * Пустой массив, если файла нет или список пуст.
 */
function legacyFileGlobalVersions(): array
{
    static $cached = null;
    if ($cached !== null) return $cached;
    $cached = [];
    $file = __DIR__ . '/mt_proxy_rules.php';
    if (is_file($file) && is_readable($file)) {
        $rules = @require $file;
        if (is_array($rules) && !empty($rules['global_versions']) && is_array($rules['global_versions'])) {
            $cached = array_values(array_filter(
                array_map(fn($v) => trim((string)$v), $rules['global_versions']),
                fn($v) => $v !== ''
            ));
        }
    }
    return $cached;
}

/**
 * Хардкод-фолбэк: allowed_versions_hardcoded из mt_proxy_config.php.
 */
function hardcodedAllowedVersions(): array
{
    static $cached = null;
    if ($cached !== null) return $cached;
    $cached = [];
    $file = __DIR__ . '/mt_proxy_config.php';
    if (is_file($file)) {
        $cfg = @require $file;
        if (is_array($cfg) && !empty($cfg['allowed_versions_hardcoded']) && is_array($cfg['allowed_versions_hardcoded'])) {
            $cached = array_values(array_filter(
                array_map(fn($v) => trim((string)$v), $cfg['allowed_versions_hardcoded']),
                fn($v) => $v !== ''
            ));
        }
    }
    return $cached;
}

/**
 * Разрешено ли обновление до $version.
 *
 * Порядок принятия решения:
 *  1. Устройство найдено по serial И его список allowed НЕ пуст → решение окончательное.
 *  2. Модельное правило ('model:XXX') существует И НЕ пусто → решение окончательное.
 *  3. Устройства нет (новое) ИЛИ есть, но список пуст:
 *     3a. global_versions из БД (если не пусты) → проверка по ним.
 *     3b. Файловый фолбэк: mt_proxy_rules.php['global_versions'] (если не пуст).
 *     3c. Хардкод: mt_proxy_config.php['allowed_versions_hardcoded'].
 */
function isVersionAllowed(string $serial, string $model, string $version): bool
{
    $pdo = db();

    // 1. Персональный список устройства (по serial)
    if ($serial !== '') {
        $stmt = $pdo->prepare("SELECT allowed FROM devices WHERE serial = ?");
        $stmt->execute([$serial]);
        $row = $stmt->fetch();
        if ($row) {
            $list = json_decode($row['allowed'], true) ?: [];
            if (!empty($list)) {
                return in_array($version, $list, true);
            }
            // Список пуст → проваливаемся к глобальным правилам
        }
    }

    // 2. Модельное правило (устройство с serial = 'model:XXX')
    if ($model !== '') {
        $stmt = $pdo->prepare("SELECT allowed FROM devices WHERE serial = ?");
        $stmt->execute(['model:' . $model]);
        $row = $stmt->fetch();
        if ($row) {
            $list = json_decode($row['allowed'], true) ?: [];
            if (!empty($list)) {
                return in_array($version, $list, true);
            }
        }
    }

    // 3a. Глобальные версии из БД
    $globals = globalVersionsList();
    if (!empty($globals)) {
        return in_array($version, $globals, true);
    }

    // 3b. Файловый фолбэк (legacy mt_proxy_rules.php)
    $fileGlobals = legacyFileGlobalVersions();
    if (!empty($fileGlobals)) {
        return in_array($version, $fileGlobals, true);
    }

    // 3c. Хардкод из mt_proxy_config.php
    $hardcoded = hardcodedAllowedVersions();
    return in_array($version, $hardcoded, true);
}

function deviceRecordVisit(string $serial, string $model, string $ip,
                           string $currentFw, string $upgradeFw, string $newVersion): void
{
    if ($serial === '') return;
    $pdo = db();
    $now = gmdate('Y-m-d H:i:s');
    try {
        $pdo->exec('BEGIN IMMEDIATE');

        // 1. Регистрация/обновление устройства
        $stmt = $pdo->prepare(
            "INSERT INTO devices(serial, model, source, last_seen_at)
             VALUES(?, ?, 'auto', ?)
             ON CONFLICT(serial) DO UPDATE SET
                model = CASE WHEN excluded.model <> '' THEN excluded.model ELSE devices.model END,
                last_seen_at = excluded.last_seen_at"
        );
        $stmt->execute([$serial, $model, $now]);

        // 2. IP
        if ($ip !== '') {
            $stmt = $pdo->prepare(
                "INSERT INTO device_ips(serial, ip_address, first_seen, last_seen)
                 VALUES(?, ?, ?, ?)
                 ON CONFLICT(serial, ip_address) DO UPDATE SET last_seen = excluded.last_seen"
            );
            $stmt->execute([$serial, $ip, $now, $now]);
        }

        // 3. Прошивки — только если что-то реально изменилось
        if ($currentFw !== '' || $upgradeFw !== '' || $newVersion !== '') {
            $stmt = $pdo->prepare(
                "SELECT current_firmware, upgrade_firmware, last_new_version FROM devices WHERE serial = ?"
            );
            $stmt->execute([$serial]);
            $row = $stmt->fetch();
            if ($row && ($row['current_firmware'] !== $currentFw
                      || $row['upgrade_firmware'] !== $upgradeFw
                      || $row['last_new_version'] !== $newVersion)) {
                $stmt = $pdo->prepare(
                    "UPDATE devices SET current_firmware = ?, upgrade_firmware = ?, last_new_version = ?
                     WHERE serial = ?"
                );
                $stmt->execute([$currentFw, $upgradeFw, $newVersion, $serial]);
            }
        }

        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('[force_update] recordVisit error: ' . $e->getMessage());
    }
}
