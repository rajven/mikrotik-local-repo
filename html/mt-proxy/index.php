<?php
/**
 * index.php — веб-интерфейс управления устройствами и глобальными версиями.
 */
require __DIR__ . '/db.php';
$CFG = require __DIR__ . '/mt_proxy_config.php';

$action = $_POST['action'] ?? $_GET['action'] ?? '';
$flash  = '';

/**
 * Разобрать список версий из textarea (по одной на строку, либо через запятую).
 */
function parseVersionsInput(string $raw): array
{
    $raw = str_replace(',', "\n", $raw);
    return array_values(array_unique(array_filter(
        array_map('trim', explode("\n", $raw)),
        fn($v) => $v !== ''
    )));
}

function readROSVersionFile($filename)
{
    if (is_file($filename) && is_readable($filename)) {
        $content = @file_get_contents($filename);
        if ($content !== false) {
            $content = trim($content);
            $parts = preg_split('/\s+/', $content, 2);
            if (!empty($parts[0])) { return $parts[0]; }
        }
    }
    return null;
}

function readAvailableFirmwareVersions($CFG): array
{
    $raw = [
        'ROS6 stable'    => readROSVersionFile($CFG['v6']['local_stable']),
        'ROS6 long-term' => readROSVersionFile($CFG['v6']['local_longterm']),
        'ROS7 stable'    => readROSVersionFile($CFG['v7']['local_stable_afile']),
        'ROS7 long-term' => readROSVersionFile($CFG['v7']['local_longterm_afile']),
    ];

    $result = [];
    foreach ($raw as $label => $version) {
        $hasChangelog = false;
        if ($version !== null) {
            $changelogPath = $CFG['routeros_dir'] . '/' . $version . '/CHANGELOG';
            $hasChangelog = is_file($changelogPath) && is_readable($changelogPath);
        }
        $result[] = [
            'label'         => $label,
            'version'       => $version,
            'has_changelog' => $hasChangelog,
        ];
    }
    return $result;
}


try {
    switch ($action) {
        case 'add_device':
            $serial     = trim($_POST['serial']  ?? '');
            $deviceName = trim($_POST['name']    ?? '');
            $model      = trim($_POST['model']   ?? '');
            $comment    = trim($_POST['comment'] ?? '');
            $allowed    = parseVersionsInput($_POST['allowed'] ?? '');
            if ($serial === '') {
                $flash = 'Serial is required';
            } else {
                $id = deviceAdd($serial, $model, $deviceName, $comment, $allowed);
                $flash = $id ? "Device added (ID $id)" : 'Serial already exists';
            }
            break;

        case 'update_device':
            $id = (int)($_POST['id'] ?? 0);
            $deviceName = trim($_POST['name']    ?? '');
            $model      = trim($_POST['model']   ?? '');
            $comment    = trim($_POST['comment'] ?? '');
            $allowed    = parseVersionsInput($_POST['allowed'] ?? '');
            $ips        = parseVersionsInput($_POST['ips'] ?? '');
            if ($id > 0) {
                deviceUpdate($id, $model, $deviceName, $comment, $allowed);
                deviceUpdateIps($id, $ips);
                $flash = "Device #$id updated";
            }
            break;

        case 'bulk_set_allowed':
            $ids     = array_map('intval', $_POST['ids'] ?? []);
            $ids     = array_values(array_filter($ids, fn($i) => $i > 0));
            $mode    = ($_POST['bulk_mode'] ?? 'replace') === 'append' ? 'append' : 'replace';
            $allowed = parseVersionsInput($_POST['bulk_versions'] ?? '');
            if (empty($ids)) {
                $flash = 'No devices selected';
            } else {
                $n = deviceBulkSetAllowed($ids, $allowed, $mode);
                $verb = $mode === 'append' ? 'appended to' : 'set for';
                $flash = "Allowed versions $verb $n device(s)";
            }
            break;

        case 'delete_device':
            $id = (int)($_POST['id'] ?? 0);
            if ($id > 0) {
                deviceDelete($id);
                $flash = "Device #$id deleted";
            }
            break;

        case 'add_global':
            $v = trim($_POST['version'] ?? '');
            if (globalVersionAdd($v)) {
                $flash = "Global version $v added";
            } else {
                $flash = 'Version already in global list or empty';
            }
            break;

        case 'delete_global':
            $v = $_POST['version'] ?? '';
            globalVersionDelete($v);
            $flash = "Global version removed";
            break;
    }
} catch (Throwable $e) {
    $flash = 'Error: ' . $e->getMessage();
}

$search  = trim($_GET['q'] ?? '');
$devices = deviceList($search);
$globals = globalVersionsList();
$availableVersions = readAvailableFirmwareVersions($CFG);

$editId     = isset($_GET['edit']) ? (int)$_GET['edit'] : 0;
$editDevice = $editId ? deviceGet($editId) : null;

function formatIpsCell(array $ips): string
{
    if (empty($ips)) return '';
    $out = [];
    foreach (array_slice($ips, 0, 3) as $row) {
        $out[] = htmlspecialchars($row['ip_address']);
    }
    $html = implode('<br>', $out);
    if (count($ips) > 3) {
        $html .= '<br><span style="color:var(--muted)">+' . (count($ips) - 3) . ' more</span>';
    }
    return $html;
}

function formatIpsTooltip(array $ips): string
{
    if (empty($ips)) return '';
    $lines = [];
    foreach ($ips as $row) {
        $lines[] = $row['ip_address'] . '  (last: ' . $row['last_seen'] . ')';
    }
    return htmlspecialchars(implode("\n", $lines));
}

$qs = $search !== '' ? '&q=' . urlencode($search) : '';
?>
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MikroTik Update Proxy — Devices</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/inter@5.0.0/index.css">
<style>
  :root{
    --bg:#0f172a; --panel:#1e293b; --panel2:#334155;
    --text:#e2e8f0; --muted:#94a3b8; --accent:#38bdf8;
    --ok:#22c55e; --warn:#f59e0b; --err:#ef4444;
    --border:#334155;
  }
  *{box-sizing:border-box}
  body{margin:0;font-family:Inter,system-ui,sans-serif;background:var(--bg);color:var(--text);font-size:14px}
  .wrap{max-width:1440px;margin:0 auto;padding:24px}
  header{display:flex;align-items:center;justify-content:space-between;margin-bottom:24px;flex-wrap:wrap;gap:12px}
  h1{margin:0;font-size:22px;font-weight:600}
  h1 span{color:var(--accent)}
  .flash{padding:10px 14px;border-radius:8px;background:var(--panel);border:1px solid var(--border);margin-bottom:16px}
  .flash.err{border-color:var(--err)}
  .grid{display:grid;grid-template-columns:1fr;gap:20px}
  @media(min-width:1100px){.grid{grid-template-columns:2.2fr 1fr}}
  .card{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:18px}
  .card h2{margin:0 0 14px;font-size:16px;font-weight:600;display:flex;align-items:center;gap:8px}
  .card h2 .count{background:var(--panel2);color:var(--muted);font-size:12px;padding:2px 8px;border-radius:10px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th,td{text-align:left;padding:10px 8px;border-bottom:1px solid var(--border);vertical-align:top}
  th{color:var(--muted);font-weight:500;font-size:12px;text-transform:uppercase;letter-spacing:.5px}
  tr:hover td{background:rgba(56,189,248,.04)}
  tr.selected td{background:rgba(56,189,248,.09)}
  .mono{font-family:ui-monospace,Menlo,monospace;font-size:12px}
  .badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:500}
  .badge.auto{background:rgba(56,189,248,.15);color:var(--accent)}
  .badge.manual{background:rgba(34,197,94,.15);color:var(--ok)}
  .badge.legacy{background:rgba(245,158,11,.15);color:var(--warn)}
  .versions{display:flex;flex-wrap:wrap;gap:4px}
  .vtag{background:var(--panel2);padding:2px 8px;border-radius:6px;font-family:ui-monospace,monospace;font-size:11px}
  .comment{color:var(--muted);font-size:12px;font-style:italic;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .comment:empty::before{content:'—';opacity:.5}
  .device-name{color:var(--text);font-size:12px;font-weight:500;max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .device-name:empty::before{content:'—';opacity:.5}
  .ips-cell{font-family:ui-monospace,monospace;font-size:11px;line-height:1.5;min-width:110px}
.fw-cell{
  font-family:ui-monospace,Menlo,monospace;
  font-size:11px;
  line-height:1.6;
  min-width:170px;
  white-space:nowrap;
}
.fw-cell > div{
  display:flex;
  align-items:center;
  gap:4px;
  margin-bottom:2px;
}
.fw-label{
  color:var(--muted);
  font-size:10px;
  text-transform:uppercase;
  min-width:34px;
  flex-shrink:0;
}
.fw-empty{color:var(--muted);font-style:italic;font-size:11px}

.fw-boot.mismatch{
  background:rgba(239,68,68,.15);
  color:#ef4444;
  padding:2px 6px;
  border-radius:4px;
  border:1px solid rgba(239,68,68,.35);
  font-weight:600;
}
.fw-upgrade.outdated{
  background:rgba(245,158,11,.15);
  color:#f59e0b;
  padding:2px 6px;
  border-radius:4px;
  border:1px solid rgba(245,158,11,.35);
}
.fw-upgrade.current{
  background:rgba(34,197,94,.15);
  color:#22c55e;
  padding:2px 6px;
  border-radius:4px;
  border:1px solid rgba(34,197,94,.35);
}
  .fw-label{color:var(--muted);font-size:10px;text-transform:uppercase;margin-right:4px}
  .actions{display:flex;gap:6px}
  form{display:flex;flex-direction:column;gap:10px}
  label{font-size:12px;color:var(--muted);font-weight:500}
  input[type=text],textarea{
    background:var(--bg);border:1px solid var(--border);border-radius:8px;
    padding:8px 10px;color:var(--text);font-family:inherit;font-size:13px;width:100%;
  }
  textarea{min-height:80px;resize:vertical;font-family:ui-monospace,monospace}
  input:focus,textarea:focus{outline:none;border-color:var(--accent)}
  input[type=checkbox]{width:16px;height:16px;accent-color:var(--accent);cursor:pointer;margin:0}
  .btn{
    background:var(--accent);color:#0b1220;border:none;padding:8px 14px;
    border-radius:8px;font-weight:600;cursor:pointer;font-size:13px;
    transition:opacity .15s;
  }
  .btn:hover{opacity:.85}
  .btn:disabled{opacity:.4;cursor:not-allowed}
  .btn.sec{background:var(--panel2);color:var(--text)}
  .btn.danger{background:var(--err);color:#fff}
  .btn.sm{padding:4px 10px;font-size:12px}
  .search{display:flex;gap:8px;margin-bottom:14px}
  .search input{flex:1}
  .global-list{display:flex;flex-direction:column;gap:6px;margin-bottom:12px}
  .global-row{display:flex;justify-content:space-between;align-items:center;background:var(--bg);padding:6px 10px;border-radius:6px}
  .empty{text-align:center;color:var(--muted);padding:24px;font-style:italic}
  .modal-bg{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:100;padding:16px}
  .modal{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:20px;width:100%;max-width:560px;max-height:90vh;overflow:auto}
  .modal h3{margin:0 0 14px}
  .modal .row{display:flex;gap:8px;justify-content:flex-end;margin-top:10px}
  .modal .info-row{background:var(--bg);padding:8px 12px;border-radius:6px;margin-bottom:8px;font-size:12px}
  .modal .info-row .lbl{color:var(--muted);display:inline-block;width:110px}
  .time{color:var(--muted);font-size:11px}
  a{color:var(--accent);text-decoration:none}
  a:hover{text-decoration:underline}

  /* Bulk toolbar */
  .bulk-bar{
    position:sticky;top:0;z-index:50;
    display:none;align-items:center;gap:12px;flex-wrap:wrap;
    background:var(--panel2);border:1px solid var(--accent);
    border-radius:10px;padding:10px 14px;margin-bottom:14px;
    box-shadow:0 4px 16px rgba(0,0,0,.35);
  }
  .bulk-bar.visible{display:flex}
  .bulk-bar .sel-count{font-weight:600;color:var(--accent);white-space:nowrap}
  .bulk-bar textarea{min-height:38px;height:38px;font-size:12px;flex:1;min-width:180px}
  .bulk-bar .mode-group{display:flex;align-items:center;gap:10px;font-size:12px;color:var(--muted);white-space:nowrap}
  .bulk-bar .mode-group label{display:flex;align-items:center;gap:4px;cursor:pointer;color:var(--text);font-weight:500}
  .bulk-bar input[type=checkbox]{width:14px;height:14px}
  .bulk-actions{display:flex;gap:8px}
  .cb-cell{width:30px;text-align:center}
  
  /* Available versions */
  .avail-list{display:flex;flex-direction:column;gap:6px;margin-top:12px}
  .avail-row{display:flex;justify-content:space-between;align-items:center;background:var(--bg);padding:6px 10px;border-radius:6px;font-size:12px}
  .avail-label{color:var(--muted);font-size:11px}
  .avail-version{font-family:ui-monospace,monospace;font-weight:600;color:var(--accent)}

.avail-version.clickable {
    cursor: pointer;
    text-decoration: underline;
    text-decoration-style: dotted;
    text-underline-offset: 3px;
}
.avail-version.clickable:hover {
    text-decoration-style: solid;
    color: #7dd3fc;
}
.avail-version.error {
    background: rgba(239, 68, 68, 0.15);
    color: #ef4444;
    padding: 2px 8px;
    border-radius: 4px;
    border: 1px solid rgba(239, 68, 68, 0.35);
    font-weight: 600;
}
.avail-version.missing {
    color: var(--muted);
    font-style: italic;
}

</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>🛰 MikroTik <span>Update Proxy</span></h1>
    <div class="time"><?= date('Y-m-d H:i:s') ?></div>
  </header>

  <?php if ($flash): ?>
    <div class="flash"><?= htmlspecialchars($flash) ?></div>
  <?php endif; ?>

  <div class="grid">
    <!-- Devices -->
    <div class="card">
      <h2>Devices <span class="count"><?= count($devices) ?></span></h2>

      <form class="search" method="get">
        <input type="text" name="q" placeholder="Search by serial, name, model, comment or IP…" value="<?= htmlspecialchars($search) ?>">
        <button class="btn sec" type="submit">Search</button>
        <?php if ($search !== ''): ?>
          <a href="?" class="btn sec" style="text-decoration:none;display:inline-block">Clear</a>
        <?php endif; ?>
      </form>

      <?php if (empty($devices)): ?>
        <div class="empty">No devices yet. They will appear automatically when routers request updates, or you can add one manually.</div>
      <?php else: ?>

        <!-- Bulk toolbar -->
        <form class="bulk-bar" id="bulkBar" method="post"
              onsubmit="return confirmBulk(this)">
          <input type="hidden" name="action" value="bulk_set_allowed">
          <span class="sel-count" id="selCount">0 selected</span>
          <textarea name="bulk_versions" id="bulkVersions"
                    placeholder="Versions, one per line or comma-separated (empty = clear list)"></textarea>
          <span class="mode-group">
            <label><input type="radio" name="bulk_mode" value="replace" checked> Replace</label>
            <label><input type="radio" name="bulk_mode" value="append"> Append</label>
          </span>
          <span class="bulk-actions">
            <button class="btn" type="submit">Apply</button>
            <button class="btn sec" type="button" onclick="clearSelection()">Clear</button>
          </span>
          <div id="bulkIds"></div>
        </form>

        <div style="overflow-x:auto">
        <table>
          <thead>
            <tr>
              <th class="cb-cell"><input type="checkbox" id="selectAll" title="Select all" onclick="toggleAll(this)"></th>
              <th>Serial</th>
              <th>Name</th>
              <th>Model</th>
              <th>Firmware</th>
              <th>IP addresses</th>
              <th>Comment</th>
              <th>Allowed versions</th>
              <th>Src</th>
              <th>Last seen</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
          <?php foreach ($devices as $d):
            $bootFw   = $d['current_firmware'] ?? '';
            $upgFw    = $d['upgrade_firmware'] ?? '';
            $newVer   = $d['last_new_version'] ?? '';
            $mismatch = ($bootFw !== '' && $upgFw !== '' && $bootFw !== $upgFw);
            $upToDate = ($upgFw !== '' && $newVer !== '' && $upgFw === $newVer);
          ?>
            <tr data-id="<?= $d['id'] ?>">
              <td class="cb-cell">
                <input type="checkbox" class="dev-cb" value="<?= $d['id'] ?>"
                       data-serial="<?= htmlspecialchars($d['serial']) ?>"
                       onclick="onRowCheck(this)">
              </td>
              <td class="mono"><?= htmlspecialchars($d['serial']) ?></td>
              <td class="device-name" title="<?= htmlspecialchars($d['device_name']) ?>"><?= htmlspecialchars($d['device_name']) ?></td>
              <td><?= htmlspecialchars($d['model'] ?: '—') ?></td>
              <td class="fw-cell">
                <?php if ($bootFw === '' && $upgFw === ''): ?>
                  <span class="fw-empty">—</span>
                <?php else: ?>
                  <div>
                    <span class="fw-label">boot:</span>
                    <?php if ($bootFw === ''): ?>
                      <span class="fw-empty">—</span>
                    <?php elseif ($mismatch): ?>
                      <span class="fw-boot mismatch" title="Boot and upgrade firmware differ"><?= htmlspecialchars($bootFw) ?></span>
                    <?php else: ?>
                      <span class="fw-boot"><?= htmlspecialchars($bootFw) ?></span>
                    <?php endif; ?>
                  </div>
                  <div>
                    <span class="fw-label">upg:</span>
                    <?php if ($upgFw === ''): ?>
                      <span class="fw-empty">—</span>
                    <?php elseif ($upToDate): ?>
                      <span class="fw-upgrade current" title="Up to date"><?= htmlspecialchars($upgFw) ?> ✓</span>
                    <?php else: ?>
                      <span class="fw-upgrade outdated" title="Needs update to <?= htmlspecialchars($newVer) ?>"><?= htmlspecialchars($upgFw) ?></span>
                    <?php endif; ?>
                  </div>
                <?php endif; ?>
              </td>
              <td class="ips-cell" title="<?= formatIpsTooltip($d['ips']) ?>">
                <?= formatIpsCell($d['ips']) ?: '<span style="color:var(--muted);font-style:italic">—</span>' ?>
              </td>
              <td class="comment" title="<?= htmlspecialchars($d['comment']) ?>"><?= htmlspecialchars($d['comment']) ?></td>
              <td>
                <div class="versions">
                  <?php if (empty($d['allowed_arr'])): ?>
                    <span style="color:var(--muted);font-style:italic">global</span>
                  <?php else: foreach ($d['allowed_arr'] as $v): ?>
                    <span class="vtag"><?= htmlspecialchars($v) ?></span>
                  <?php endforeach; endif; ?>
                </div>
              </td>
              <td><span class="badge <?= htmlspecialchars($d['source']) ?>"><?= htmlspecialchars($d['source']) ?></span></td>
              <td class="time"><?= htmlspecialchars($d['last_seen_at']) ?></td>
              <td class="actions">
                <a href="?edit=<?= $d['id'] ?><?= $qs ?>" class="btn sm sec">Edit</a>
                <form method="post" style="display:inline" onsubmit="return confirm('Delete device?')">
                  <input type="hidden" name="action" value="delete_device">
                  <input type="hidden" name="id" value="<?= $d['id'] ?>">
                  <button class="btn sm danger" type="submit">✕</button>
                </form>
              </td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
        </div>
      <?php endif; ?>

      <h2 style="margin-top:24px">Add device manually</h2>
      <form method="post">
        <input type="hidden" name="action" value="add_device">
        <div>
          <label>Serial number *</label>
          <input type="text" name="serial" required placeholder="ABC123DEF456">
        </div>
        <div>
          <label>Device name</label>
          <input type="text" name="name" placeholder="office-gw-1">
        </div>
        <div>
          <label>Model</label>
          <input type="text" name="model" placeholder="hEX lite">
        </div>
        <div>
          <label>Comment</label>
          <input type="text" name="comment" placeholder="Office router, floor 2">
        </div>
        <div>
          <label>Allowed versions (one per line or comma-separated)</label>
          <textarea name="allowed" placeholder="7.24.5&#10;7.23.8"></textarea>
        </div>
        <button class="btn" type="submit">Add device</button>
      </form>
    </div>

    <!-- Global versions -->
    <div class="card">
      <h2>Global versions <span class="count"><?= count($globals) ?></span></h2>
      <p style="color:var(--muted);font-size:12px;margin:0 0 12px">
        Applied to devices without a specific rule.
      </p>

      <div class="global-list">
        <?php if (empty($globals)): ?>
          <div class="empty">No global versions configured</div>
        <?php else: foreach ($globals as $v): ?>
          <div class="global-row">
            <span class="mono"><?= htmlspecialchars($v) ?></span>
            <form method="post" style="display:inline" onsubmit="return confirm('Remove global version?')">
              <input type="hidden" name="action" value="delete_global">
              <input type="hidden" name="version" value="<?= htmlspecialchars($v) ?>">
              <button class="btn sm danger" type="submit">✕</button>
            </form>
          </div>
        <?php endforeach; endif; ?>
      </div>

      <form method="post">
        <input type="hidden" name="action" value="add_global">
        <label>Add version</label>
        <input type="text" name="version" placeholder="7.24.5" required>
        <button class="btn" type="submit">Add</button>
      </form>

    <?php if (!empty($availableVersions)): ?>
    <h2 style="margin-top:24px">Available firmware versions</h2>
    <p style="color:var(--muted);font-size:12px;margin:0 0 12px">
      Current versions on the proxy server. Click a version to view its CHANGELOG.
    </p>
    <div class="avail-list">
      <?php foreach ($availableVersions as $item):
          $label        = $item['label'];
          $version      = $item['version'];
          $hasChangelog = $item['has_changelog'];
      ?>
    <div class="avail-row">
      <span class="avail-label"><?= htmlspecialchars($label) ?></span>
      <?php if ($version === null): ?>
        <span class="avail-version missing" title="Version file is missing or unreadable">unknown</span>
      <?php elseif ($hasChangelog): ?>
        <a href="#" class="avail-version clickable"
           data-version="<?= htmlspecialchars($version) ?>"
           onclick="showChangelog(this); return false;"
           title="Click to view CHANGELOG"><?= htmlspecialchars($version) ?></a>
      <?php else: ?>
        <span class="avail-version error"
              title="CHANGELOG not found in <?= htmlspecialchars($version) ?>/ directory">
          <?= htmlspecialchars($version) ?>
        </span>
      <?php endif; ?>
    </div>
  <?php endforeach; ?>
</div>
        <?php endif; ?>
    </div>
  </div>
</div>

<?php if ($editDevice):
    $bootFw   = $editDevice['current_firmware'] ?? '';
    $upgFw    = $editDevice['upgrade_firmware'] ?? '';
    $newVer   = $editDevice['last_new_version'] ?? '';
    $mismatch = ($bootFw !== '' && $upgFw !== '' && $bootFw !== $upgFw);
    $upToDate = ($upgFw !== '' && $newVer !== '' && $upgFw === $newVer);
?>
<div class="modal-bg" onclick="if(event.target===this)location.href='?<?= $search!==''?'q='.urlencode($search):'' ?>'">
  <div class="modal">
    <h3>Edit device #<?= $editDevice['id'] ?></h3>

    <div class="info-row">
      <div><span class="lbl">Serial:</span> <span class="mono"><?= htmlspecialchars($editDevice['serial']) ?></span></div>
      <div style="margin-top:6px">
        <span class="lbl">Boot firmware:</span>
        <?php if ($bootFw === ''): ?>
          <span class="fw-empty">—</span>
        <?php elseif ($mismatch): ?>
          <span class="fw-boot mismatch"><?= htmlspecialchars($bootFw) ?></span>
        <?php else: ?>
          <span class="fw-boot"><?= htmlspecialchars($bootFw) ?></span>
        <?php endif; ?>
      </div>
      <div style="margin-top:4px">
        <span class="lbl">Upgrade firmware:</span>
        <?php if ($upgFw === ''): ?>
          <span class="fw-empty">—</span>
        <?php elseif ($upToDate): ?>
          <span class="fw-upgrade current"><?= htmlspecialchars($upgFw) ?> ✓</span>
        <?php else: ?>
          <span class="fw-upgrade outdated"><?= htmlspecialchars($upgFw) ?></span>
        <?php endif; ?>
      </div>
      <div style="margin-top:4px">
        <span class="lbl">Latest available:</span>
        <span class="mono"><?= htmlspecialchars($newVer ?: '—') ?></span>
      </div>
      <div style="margin-top:6px">
        <span class="lbl">IP addresses:</span>
        <?php if (empty($editDevice['ips'])): ?>
          <span style="color:var(--muted);font-style:italic">none yet</span>
        <?php else: ?>
          <div style="margin-top:4px;font-family:ui-monospace,monospace;font-size:11px;line-height:1.6">
            <?php foreach ($editDevice['ips'] as $ipRow): ?>
              <div><?= htmlspecialchars($ipRow['ip_address']) ?> <span style="color:var(--muted)">· last <?= htmlspecialchars($ipRow['last_seen']) ?></span></div>
            <?php endforeach; ?>
          </div>
        <?php endif; ?>
      </div>
    </div>

    <form method="post">
      <input type="hidden" name="action" value="update_device">
      <input type="hidden" name="id" value="<?= $editDevice['id'] ?>">
      <div>
        <label>Device name</label>
        <input type="text" name="name" value="<?= htmlspecialchars($editDevice['device_name']) ?>" placeholder="office-gw-1">
      </div>
      <div>
        <label>Model</label>
        <input type="text" name="model" value="<?= htmlspecialchars($editDevice['model']) ?>">
      </div>
      <div>
        <label>Comment</label>
        <input type="text" name="comment" value="<?= htmlspecialchars($editDevice['comment']) ?>" placeholder="Office router, floor 2">
      </div>
      <div>
        <label>Allowed versions (one per line or comma-separated)</label>
        <textarea name="allowed"><?= htmlspecialchars(implode("\n", $editDevice['allowed_arr'])) ?></textarea>
      </div>
      <div>
        <label>IP addresses (one per line)</label>
  <textarea name="ips" style="font-family:ui-monospace,monospace" placeholder="192.168.1.1&#10;10.0.0.1"><?php
$ipList = array_map(fn($row) => $row['ip_address'], $editDevice['ips']);
echo htmlspecialchars(implode("\n", $ipList));
?></textarea>
      </div>
      <div class="row">
        <a href="?<?= $search!==''?'q='.urlencode($search):'' ?>" class="btn sec">Cancel</a>
        <button class="btn" type="submit">Save</button>
      </div>
    </form>
  </div>
</div>
<?php endif; ?>

<script>

function showChangelog(el) {
    var version = el.getAttribute('data-version');
    document.getElementById('changelogVersion').textContent = version;
    document.getElementById('changelogContent').textContent = 'Loading...';
    document.getElementById('changelogModal').style.display = 'flex';

    fetch('changelog.php?version=' + encodeURIComponent(version))
        .then(function(r) {
            if (!r.ok) throw new Error('HTTP ' + r.status);
            return r.text();
        })
        .then(function(text) {
            document.getElementById('changelogContent').textContent = text;
        })
        .catch(function(err) {
            document.getElementById('changelogContent').textContent = 'Error loading CHANGELOG: ' + err.message;
        });
}

function closeChangelog() {
    document.getElementById('changelogModal').style.display = 'none';
}

// Закрытие по Escape
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeChangelog();
});

(function () {
  var bar       = document.getElementById('bulkBar');
  var idsBox    = document.getElementById('bulkIds');
  var countEl   = document.getElementById('selCount');
  var selectAll = document.getElementById('selectAll');
  if (!bar) return;

  function selectedBoxes() {
    return Array.prototype.slice.call(document.querySelectorAll('.dev-cb:checked'));
  }

  function refresh() {
    var boxes = selectedBoxes();
    idsBox.innerHTML = '';
    boxes.forEach(function (cb) {
      var inp = document.createElement('input');
      inp.type  = 'hidden';
      inp.name  = 'ids[]';
      inp.value = cb.value;
      idsBox.appendChild(inp);
    });
    countEl.textContent = boxes.length + ' selected';
    bar.classList.toggle('visible', boxes.length > 0);
    document.querySelectorAll('tr[data-id]').forEach(function (tr) {
      var cb = tr.querySelector('.dev-cb');
      tr.classList.toggle('selected', !!(cb && cb.checked));
    });
    if (selectAll) {
      var all = document.querySelectorAll('.dev-cb');
      selectAll.checked   = all.length > 0 && boxes.length === all.length;
      selectAll.indeterminate = boxes.length > 0 && boxes.length < all.length;
    }
  }

  window.onRowCheck = function () { refresh(); };

  window.toggleAll = function (master) {
    document.querySelectorAll('.dev-cb').forEach(function (cb) {
      cb.checked = master.checked;
    });
    refresh();
  };

  window.clearSelection = function () {
    document.querySelectorAll('.dev-cb').forEach(function (cb) {
      cb.checked = false;
    });
    if (selectAll) selectAll.checked = false;
    refresh();
  };

  window.confirmBulk = function (form) {
    var n    = selectedBoxes().length;
    if (n === 0) return false;
    var mode = form.querySelector('input[name=bulk_mode]:checked').value;
    var vers = document.getElementById('bulkVersions').value.trim();
    var what = vers === '' ? 'EMPTY list (devices will fall back to global)' : '"' + vers.replace(/\s+/g, ' ') + '"';
    var verb = mode === 'append' ? 'APPEND ' + what + ' to' : 'REPLACE list with ' + what + ' for';
    return confirm(verb + ' ' + n + ' selected device(s)?');
  };

  refresh();
})();
</script>

<div class="modal-bg" id="changelogModal" style="display:none"
     onclick="if(event.target===this)closeChangelog()">
  <div class="modal" style="max-width:800px;max-height:90vh">
    <h3>CHANGELOG <span id="changelogVersion" class="mono" style="color:var(--accent)"></span></h3>
    <pre id="changelogContent" style="background:var(--bg);padding:12px;border-radius:6px;
        overflow:auto;max-height:70vh;font-size:12px;line-height:1.5;white-space:pre-wrap;
        border:1px solid var(--border);color:var(--text)">Loading...</pre>
    <div class="row">
      <button class="btn sec" onclick="closeChangelog()">Close</button>
    </div>
  </div>
</div>

</body>
</html>
