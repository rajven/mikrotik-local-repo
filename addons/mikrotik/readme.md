# MikroTik Auto Backup & Update System

[🇬🇧nglish](readme.md) · [🇷🇺усский](readme.ru.md)

An automated solution for MikroTik RouterOS that performs configuration backups, system updates, and firmware upgrades, featuring an intelligent local proxy server with caching and fallback mechanisms.

## 📋 Features

- ✅ **Daily Automated Backups** – Creates both binary backups and `.rsc` configuration exports.
- ✅ **Automatic RouterOS Update Checks** – Monitors the configured update channel (e.g., `stable`).
- ✅ **RouterBOARD Firmware Upgrades** – Automatically upgrades firmware when a new version is detected.
- ✅ **Intelligent Local Proxy** – Caches upstream responses, provides instant fallbacks during network issues, and prevents RouterOS update timeouts.
- ✅ **ROS6 & ROS7 Compatibility** – Adapts behavior based on the detected major RouterOS version.
- ✅ **Smart Backup Naming** – Uses the device's Serial Number and current Date for unique, traceable filenames.
- ✅ **Automatic Cleanup** – Removes outdated backup files before creating new ones.
- ✅ **Reboot Scheduler** – Ensures the update script resumes and completes successfully after a device reboot.
- ✅ **Optional Server Policy Check** – Centralized control to allow or block specific update versions.

## 🔧 How It Works

The script executes in a strict, sequential order:

1. **Step 1** – Creates a daily scheduler (05:00) to trigger itself.
2. **Step 2** – Checks for RouterOS package updates (forces `mode=http` on ROS7).
3. **Step 3** – Checks for RouterBOARD firmware updates.
4. **Step 3.5** – *(Optional)* Queries the external server for update authorization.
5. **Step 4** – Creates backups, installs the RouterOS update, and schedules a post-reboot continuation.
6. **Step 5** – Upgrades the RouterBOARD firmware (executed after the Step 4 reboot).
7. **Step 6** – Cleans up the reboot scheduler and finishes.

The script is provided in two formats:
* `upgrade-mikrotik-inline.rsc` – For direct copy-paste into the terminal (may lag on devices with weak CPUs).
* `upgrade-mikrotik.txt` – For manual creation via Winbox or WebFig.

## ⚙️ MikroTik Configuration

Before using the script, edit the variables at the top of the file to match your environment:

```routeros
:local scriptName "BackupAndUpdate"
:local dailySchedulerName "BKPUPD-DAILY"
:local rebootSchedulerName "BKPUPD-REBOOT"
:local updateChannel "stable"          # Update channel: stable, testing, development, or long-term
:local backupName "auto-backup"        # Backup filename prefix
:local backupPassword ""               # Encryption password (leave empty for no encryption)
:local Httpmode "http"                 # http or https (required for ROS7 update checks)

# URL for centralized update policy check
:local policyCheckUrl "http://YOUR_SERVER_NAME/routeros/force_update.php"
```

> **Note on using the Local Proxy:** To utilize the caching proxy, ensure your MikroTik devices resolve `upgrade.mikrotik.com` to your local server's IP address (via DNS static entries or firewall NAT), or configure the update server URL directly in RouterOS if supported by your version.

---

## 🖥 Server-Side Component: The Upgrade Proxy

The core of this system is a pair of lightweight PHP proxy scripts (`ros7-upgrade.php` and `ros6-upgrade.php`) hosted on your web server. They intercept update requests from MikroTik devices and handle them intelligently.

### How the Proxy Algorithm Works

1. **Intercepts Request:** Receives requests like `/NEWEST7.stable?version=7.19.2`.
2. **Spoofs User-Agent:** Forwards the request to `upgrade.mikrotik.com` using `User-Agent: RouterOS <version>` to bypass CDN/WAF bot protection.
3. **Strict Timeouts:** Uses aggressive timeouts (`CONNECT_TIMEOUT=2s`, `TOTAL_TIMEOUT=3s`). If the upstream is slow, it fails fast to prevent the MikroTik device from dropping the connection.
4. **Fallback Chain:** If the upstream request fails, it instantly returns a valid response from:
   - **Tier 1:** Local cache (`/routeros/version.cache`) from the last successful fetch.
   - **Tier 2:** Local static files (e.g., `NEWEST7.stable`, `LATEST.6`).
   - **Tier 3:** Hardcoded default values.

### Installation on the Server

1. Place `ros7-upgrade.php` and `ros6-upgrade.php` in your web directory (e.g., `/var/www/html/`).
2. Create the cache directory and set permissions:
   ```bash
   mkdir -p /var/www/html/routeros
   chown www-data:www-data /var/www/html/routeros
   chmod 755 /var/www/html/routeros
   ```
3. Ensure PHP has permission to make outbound network requests (e.g., on RHEL/CentOS: `setsebool -P httpd_can_network_connect on`).
4. needed php-curl

### Policy Check (`force_update.php`)

If you want strict, centralized control over *which* versions are allowed to install, you can add the `force_update.php` script. 

The MikroTik script will send a GET request:
`GET http://YOUR_SERVER_NAME/routeros/force_update.php?new_version=7.15.1`

The PHP script checks the version against an `$allowedVersions` array and returns either `ENABLED` or `DISABLED`. If the response is anything other than `ENABLED`, the MikroTik script aborts the update.

---

## 📁 Backup Location

The script automatically detects the storage medium:
- If a `flash` directory exists → Backups are saved to `/flash/auto-backup-<SERIAL>-<YYYY-MM-DD>.backup` and `.rsc`.
- Otherwise → Backups are saved to the root directory `/`.

Old backups matching the `auto-backup-` prefix are automatically deleted before new ones are created to save space.

## 🔄 Update Logic

### RouterOS Update
The update proceeds **only if**:
1. `/system package update check-for-updates` returns `"New version is available"`.
2. *(If configured)* The external policy server returns `"ENABLED"`.

Once confirmed, the script:
1. Creates the reboot scheduler (`BKPUPD-REBOOT`) to run on `startup` with a 3-minute delay.
2. Executes `/system backup save` and `/export`.
3. Executes `/system package update install`.
4. The device reboots.

### RouterBOARD Firmware Update
After the RouterOS update reboot, the `BKPUPD-REBOOT` scheduler triggers the script again. It then:
1. Checks if `current-firmware` differs from `upgrade-firmware`.
2. If yes, executes `/system routerboard upgrade`.
3. Reboots the device a second time to apply the firmware.
4. Cleans up the `BKPUPD- it removes the `BKPUPD-REBOOT` scheduler, leaving the system clean.

## 📝 Logs

All actions are logged to the system log with the `BackupAndUpdate` tag. You can filter them in Winbox or CLI:
```routeros
/log print where message~"BackupAndUpdate"
```

## 🐛 Known Limitations

- A hardcoded `15s` delay is used after `check-for-updates` to allow the router to fetch data (increase this if your internet connection is very slow).
- Backup file creation has a `60s` timeout watchdog.
- The `force_update.php` checks for **exact** version string matches (no wildcards).
- The proxy cache key is `filename_version` (e.g., `NEWEST7.stable_7.19.2`), ensuring different client versions can be cached independently if the upstream responds differently.
