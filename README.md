# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Standalone RouterOS package mirror + smart upgrade proxy + per-device upgrade policy.

## Table of Contents

- [About](#-about) · [Features](#-features) · [How It Works](#-how-it-works) · [Project Structure](#-project-structure)
- [Requirements](#-requirements) · [Installation](#-installation) · [Configuration](#-configuration) · [Synchronization](#-synchronization)
- [Version Request Proxy](#-version-request-proxy) · [Upgrade Policy](#-upgrade-policy) · [Web Admin Panel](#-web-admin-panel)
- [Device Configuration](#-device-configuration) · [Logging](#-logging) · [Troubleshooting](#-troubleshooting)
- [Security Notes](#-security-notes) · [Known Limitations](#-known-limitations)

---

## 📖 About

A standalone, three-layer solution for MikroTik device fleets without Internet access (or with restricted access):

1. **Mirror** — Bash synchronization scripts download RouterOS 6 and RouterOS 7 packages, Winbox, and Netinstall-related files from the official repositories (`upgrade.mikrotik.com` / `download.mikrotik.com`) into the web server's document root.
2. **Upgrade proxy** — PHP handlers intercept RouterOS requests for available versions (`NEWEST6.*`, `NEWESTa7.stable`, etc.), cache responses, and serve the actual package files from the same host.
3. **Upgrade policy** — Each planned upgrade is checked against the device's serial number, model, or a global policy. Rules are managed through a web interface. When no rule matches, the built-in allowlist from `mt_proxy_config.php` decides, so a router is never upgraded to an unvetted version.

Devices are directed to the mirror using static DNS records, so RouterOS thinks it is communicating with MikroTik:

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

## ✨ Features

**Mirror**

- 🔄 RouterOS 6 (stable + LTS/`6fix`) and RouterOS 7 (stable + long-term).
- 🏗 All supported architectures: `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`.
- 📦 `all_packages-*.zip` archives are **downloaded and extracted**, making individual `.npk` files available for manual upgrades.
- 📥 Winbox for all published versions (`.zip`, `.dmg`, `.sha256`) in a separate `winbox/` directory tree.
- 📄 Additional files: `CHANGELOG`, `packages.csv`, Netinstall, ISO images, The Dude installer, `.mib`, `btest.exe`, `flashfig.exe`.
- ⏩ Unchanged versions are skipped — only new or updated releases are downloaded; `force` downloads everything again.
- 🎯 `download_ros.sh` downloads one specific version, including older releases.

**Upgrade proxy**

- 🛰 Proxies and caches `NEWEST6/NEWESTa6/NEWEST7/NEWESTa7` responses for the `.stable`, `.long-term`, and `.upgrade` variants.
- 🔥 `ros-warmup.php` pre-populates the version cache after each synchronization, using the firmware versions of the devices actually registered in the database, so the first device request does not have to reach the Internet. The endpoint is protected by a secret token.
- 🔀 Supports Apache (FPM **or** mod_php, auto-detected) and Nginx; ready-to-use configurations are provided in `addons/`.

**Upgrade policy**

- 🚦 `force_update.php` returns `ENABLED` / `DISABLED` for the requested version.
- 🗂 Rules can be defined by serial number, by model (`model:RB4011`), or globally, with a defined priority order.
- 👀 Devices are registered automatically on their first request: serial number, model, device name, IP address, current and target firmware versions, and last-seen time.
- 🖥 Web admin panel (Basic Auth + SQLite) with search, bulk editing, a global version allowlist, and a CHANGELOG viewer for the mirrored versions.
- 🤖 Scripts for the routers themselves: scheduled backups (`.backup` + `/export`), RouterOS and RouterBOARD firmware upgrades, reboot-loop protection, and a self-updating installer.

## 🧭 How It Works

```
     Internet: upgrade.mikrotik.com / download.mikrotik.com
                │
                │  Only during synchronization: wget + curl + unzip
                ▼
 ┌──────────────────────────────────────────────────────────────┐
 │  Mirror server  (/var/www/html)                              │
 │                                                              │
 │  routeros/                 packages, .npk, Winbox, changelog │
 │  routeros/*.version.cache  proxy-layer response cache        │
 │  mt-proxy/                 PHP handlers + SQLite + admin UI  │
 └──────────────────────────────▲───────────────────────────────┘
                                 │  version requests, package downloads,
                                 │  policy checks (ENABLED / DISABLED)
                    MikroTik router (without Internet access)
                    Static DNS: download|upgrade.mikrotik.com → mirror
                    The upgrade cycle is started by BackupAndUpdate.rsc
```

Device upgrade workflow:

1. The device requests `upgrade.mikrotik.com/routeros/NEWEST7.stable` — the PHP proxy responds from the cache, the upstream server, or a fallback value.
2. Requests for `NEWESTa*` / `NEWEST6.*` with the `?version=X` parameter are handled in the same way. This allows RouterOS to discover ROS 7 releases starting from 7.12.1 and to detect upgrades from ROS 6 to ROS 7.
3. The device downloads `.npk` / `all_packages` files from `/routeros/<version>/` on the same host.
4. The scheduled `BackupAndUpdate` script sends the serial number, model, and target version to `/routeros/force_update.php`.
5. If the server responds with `ENABLED`, the script creates a backup and installs the upgrade. If it responds with `DISABLED`, the script aborts, but the device's state is still recorded in the inventory.

## 📁 Project Structure

```
mikrotik-local-repo/
├── scripts/
│   ├── sync_mikrotik_repo.sh   # Main synchronization script (cron target)
│   ├── download_ros.sh         # Download a specific RouterOS version
│   ├── config.sh               # Paths, versions, architectures, URL scheme, warm-up token
│   ├── functions.sh            # Logging, additional files, Winbox
│   ├── ros6_functions.sh       # RouterOS 6 download logic
│   └── ros7_functions.sh       # RouterOS 7 download logic (before/after 7.12.1)
├── html/
│   ├── mt-proxy/
│   │   ├── index.php           # Web admin panel (devices, rules, global versions, CHANGELOG)
│   │   ├── db.php              # SQLite schema + decision logic
│   │   ├── changelog.php       # Serves the CHANGELOG of a mirrored version to the admin UI
│   │   ├── ros6-upgrade.php    # NEWEST6.* / NEWESTa6.* proxy
│   │   ├── ros7-upgrade.php    # NEWEST7.* / NEWESTa7.* proxy
│   │   ├── force_update.php    # ENABLED/DISABLED gate
│   │   ├── ros-warmup.php      # Token-protected version-cache warm-up
│   │   └── mt_proxy_config.php # Upstream, timeouts, fallback versions, token
│   ├── routeros/               # Initial *.version.cache files for the mirror
│   └── fullchain.pem           # CA certificate chain for HTTPS policy checks on devices
├── addons/
│   ├── apache/                 # vhost 00-mirror.conf + FPM/mod_php auto-detection
│   ├── nginx/                  # site.conf + mt-fastcgi.conf + mikrotik_ua.conf (UA allow-map)
│   ├── cron.d/                 # sync_ROS_repo — scheduled synchronization
│   └── mikrotik/               # Router scripts (.txt = source / .rsc = installer)
├── docker/                   # all-in-one container image (see "Alternative: Docker")
├── CHANGELOG
└── LICENSE                     # MIT
```

## 📋 Requirements

Debian / Ubuntu and the following packages:

| Component                                               | Used by                                |
| ------------------------------------------------------- | -------------------------------------- |
| `bash`, `wget`, `curl`, `unzip`, `coreutils`            | Synchronization scripts                |
| `php-curl`, `php-sqlite3`                               | Proxy, upgrade policy, web admin panel |
| `apache2` **or** `nginx` + `php-fpm`                    | Serving the mirror and admin panel     |
| `mod_rewrite`, `mod_headers`, `mod_proxy_fcgi` (Apache) | Routing `/routeros/*` requests to FPM  |

## 🚀 Installation

All examples use the standard Debian layout: scripts in `/usr/local/bin`, the web server document root at `/var/www/html`, and the mirror at `/var/www/html/routeros`.

### 1. Install packages

**Apache**

```
apt install git bash wget curl unzip php php-curl php-sqlite3 php-fpm apache2 -y
a2enmod rewrite headers proxy_fcgi setenvif
a2enconf php8.3-fpm        # Specify your PHP version
```

**Nginx**

```
apt install git bash wget curl unzip php php-curl php-sqlite3 php-fpm nginx -y
```

> In the PHP-FPM pool configuration, set `clear_env = no` if you intend to override parameters using environment variables.

### 2. Install the synchronization scripts

```
git clone https://github.com/rajven/mikrotik-local-repo.git
cd mikrotik-local-repo

cp scripts/*.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh \
         /usr/local/bin/download_ros.sh
```

### 3. Install the web layer

```
mkdir -p /var/www/html/routeros
cp -r html/mt-proxy             /var/www/html/
cp    html/routeros/*.cache     /var/www/html/routeros/
cp    html/fullchain.pem        /var/www/html/
cp    addons/mikrotik/*.rsc     /var/www/html/routeros/   # Device scripts
chown www-data:www-data -R /var/www/html
```

Router scripts are provided in two formats: `*.txt` is the readable source, while `*.rsc` is the same script wrapped in `/system script add`, ready for import. Only the `.rsc` files need to be exposed to devices. Both provided web server configurations deliberately serve `*.rsc` and `*.txt` from `/routeros/` **only to RouterOS fetch clients** (User-Agent `Mikrotik/6.x…Fetch`, `Mikrotik/7.x…Fetch` or `RouterOS 7.x…`); a download attempt with `curl` or a browser returns 403.

`fullchain.pem` is the certificate chain that `BackupAndUpdate` imports into the RouterOS 6 certificate store before performing an HTTPS policy check. Place your own server's CA chain there, or use the example only for testing. This file is needed only if ROS 6 devices access the policy server over HTTPS. It is not required for ROS 7 or when the policy server uses HTTP.

### 4. Configure the web server

**Apache**

```
cp addons/apache/conf-available/php-autodetect.conf /etc/apache2/conf-available/
cp addons/apache/sites-available/00-mirror.conf     /etc/apache2/sites-available/
a2enconf php-autodetect
a2ensite 00-mirror
a2dissite 000-default

htpasswd -c /etc/apache2/.htpasswd admin     # Web admin password
systemctl reload apache2
```

`php-autodetect.conf` selects `PHP_MODE_FPM` if a PHP-FPM socket is found and `mod_proxy_fcgi` is enabled; otherwise, it selects `PHP_MODE_MODPHP`. The vhost includes routing for both modes.

**Nginx**

```
cp addons/nginx/conf.d/mikrotik_ua.conf /etc/nginx/conf.d
cp addons/nginx/snippets/mt-fastcgi.conf /etc/nginx/snippets/
cp addons/nginx/site.conf               /etc/nginx/sites-available/mirror
ln -sf /etc/nginx/sites-available/mirror /etc/nginx/sites-enabled/mirror

htpasswd -c /etc/nginx/.htpasswd admin   # Web admin password
nginx -t && systemctl reload nginx
```

> 📝 Both configurations have `server_name download.mikrotik.com upgrade.mikrotik.com` hardcoded (commented out in Apache), along with paths under `/var/www/html`. Adjust `ServerName` / `server_name`, the FPM socket path, and the document root to match your setup.

The `/routeros` directory **must** be located at the website root. Devices request paths such as `/routeros/7.24.5/routeros-arm64-7.24.5.npk`, and the proxy endpoints match `/routeros/NEWEST…`. Serving the mirror from a subdirectory breaks both.

### 5. Schedule synchronization

```
cp addons/cron.d/sync_ROS_repo /etc/cron.d/
chmod 644 /etc/cron.d/sync_ROS_repo
```

```
1 */3 * * * root /usr/local/bin/sync_mikrotik_repo.sh 2>/dev/null && chown www-data:www-data -R /var/www/html
```

This runs every three hours as root and assigns the updated files to the web server user.

### 6. First run

```
mkdir -p /var/www/html/routeros
/usr/local/bin/sync_mikrotik_repo.sh force
chown www-data:www-data -R /var/www/html
```

Check that the proxy responds locally:

```
curl -i "http://localhost/routeros/NEWEST7.stable"          # First X-Cache: MISS, then HIT
curl  "http://localhost/routeros/force_update.php?new_version=7.24.5&serial=TEST&model=RB5009"
```

The second request registers a device with serial `TEST` in the database. On a fresh installation, the global version list is empty, so priority level 5 (the hardcoded allowlist) determines the result: `7.24.5` returns `ENABLED`, while a version not on the list returns `DISABLED`. To override the hardcoded list, add your versions under **Global versions** in the web admin panel.

### Alternative: Docker

The `docker/` directory ships a ready all-in-one image (nginx + PHP-FPM,
sync loop included — no web-server or cron setup):

```
git clone https://github.com/rajven/mikrotik-local-repo.git
cd mikrotik-local-repo/docker
cp .env.example .env      # fill in SITE_URL, WARMUP_TOKEN, ADMIN_PASSWORD
docker compose up -d --build
docker compose logs -f    # first sync starts after ~90 s
```

All state (mirror, SQLite, configs) lives in the host directory
`MIRROR_DATA_DIR` (from `.env`, `./data` by default) bind-mounted at `/data`.
On every start the container embeds `SITE_URL` into the device-facing `.rsc`
copies, resolves `SERVER_IP` for `dns.rsc`, regenerates every `.md5` and
propagates `TZ` to PHP-FPM. Device-side setup (static DNS, scripts) is
identical to the steps above. Details: [`docker/README.md`](docker/README.md).

## ⚙️ Configuration

### Synchronization scripts — `scripts/config.sh`

```
TARGET_DIR="/var/www/html/routeros"   # Mirror root, served by the web server
SITE_URL="http://localhost"           # Base URL used to call the ros-warmup.php endpoint
WARMUP_TOKEN="CHANGE_ME"              # Secret token for the cache warm-up endpoint
WGET="/bin/wget"                      # Path to wget; otherwise searched in $PATH
LOG_OFF=0                             # 1 — completely disable syslog logging
URL_SCHEMA="https"                    # http|https for upgrade.mikrotik.com; invalid values default to http

versions6=("6" "6fix")                # ROS 6 channels: stable and LTS
versions7=("stable" "long-term")      # ROS 7 channels
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

additional_files=( ...)               # Netinstall, ISO, utility files, .mib, etc.
WINBOX_DIR="${TARGET_DIR}/winbox"     # Winbox is always downloaded over HTTPS
```

Remove unused architectures from `firmware_arch` for the biggest improvement in synchronization time and disk usage.

### Proxy and policy — `html/mt-proxy/mt_proxy_config.php`

This file returns a configuration array:

| Key                                | Purpose                                                                               |
| ---------------------------------- | ------------------------------------------------------------------------------------- |
| `upstream_base`                    | Official repository URL prefix (`https://upgrade.mikrotik.com/routeros/`)             |
| `connect_timeout`, `total_timeout` | Upstream request timeouts in seconds (2 / 3)                                          |
| `routeros_dir`                     | Mirror directory, derived from `DOCUMENT_ROOT`                                        |
| `WARMUP_TOKEN`                     | Secret token for `ros-warmup.php`; must match `WARMUP_TOKEN` in `scripts/config.sh`   |
| `allowed_versions_hardcoded`       | Last-resort allowlist (`6.49.23`, `7.24.5`, `7.23.8`)                                 |
| `fallbacks`                        | Per-endpoint fallback responses when neither upstream nor local markers are available |
| `v6` / `v7`                        | Log prefix, cache file, default version, `User-Agent` prefix, local marker files      |

Edit `mt_proxy_config.php` when MikroTik releases new versions and you want to update the safe fallback values. The model rules file `mt_proxy_rules.php` is no longer shipped: the web admin panel stores rules in SQLite instead. An old `mt_proxy_rules.php` left in `mt-proxy/` is still honored as priority level 4 and is imported once into the database during the first connection.

## 🔄 Synchronization

```
/usr/local/bin/sync_mikrotik_repo.sh          # Only new/changed versions
/usr/local/bin/sync_mikrotik_repo.sh force    # Ignore markers and download everything again
/usr/local/bin/download_ros.sh 7.20.3         # One specific version in routeros/7.20.3/
/usr/local/bin/download_ros.sh 6.49.23        # Also works with older releases
```

The version argument can also be supplied as the second parameter (`download_ros.sh force 7.20.3`). This does not affect behavior: already downloaded files remain untouched because `wget` uses `-nc`.

What happens during a synchronization run:

1. The script compares local markers (`LATEST.6` / `LATEST.6fix` and `NEWEST7.stable` / `NEWESTa7.*`) with the upstream data.
2. For each changed version, it downloads `CHANGELOG`, `packages.csv` (ROS 7), `all_packages-<arch>-<version>.zip` and extracts the archives. It also downloads `routeros*.npk` and, for non-x86 architectures on ROS 7 versions 7.12.1 and later, `wireless-*.npk` images.
3. Markers are overwritten only after successful downloads, so an interrupted run will be retried during the next synchronization.
4. All published Winbox builds are organized under `routeros/winbox/<version>/`.
5. The script finishes by calling the local warm-up endpoint: `wget ${SITE_URL}/routeros/ros-warmup.php?token=${WARMUP_TOKEN}`. The endpoint collects all unique firmware versions from the devices database (`current_firmware`, `upgrade_firmware`, `last_new_version`), fetches the answers for the appropriate upstream markers of each version (`NEWEST6.*` for ROS 6 ≥ 6.49.19 uses `NEWESTa6.*`; ROS 7 ≥ 7.12.1 uses `NEWESTa7.*` instead of `NEWEST7.*`), and writes them into the cache files. Already-cached keys are skipped; the run ends with an HTML report (OK/SKIP/FAIL per request) and requires no Internet access from the devices.

The ROS 7 channel is deliberately downloaded twice: `download_ros7 7.10` handles releases before 7.12.1, while `download_ros7 7.12.1 a` handles the `NEWESTa7.*` API introduced in 7.12.1. These require different `User-Agent` values (`RouterOS <version>`).

The warm-up can also be triggered manually, for example after changing `SITE_URL` or clearing the cache (both tokens must match):

```
curl "http://localhost/routeros/ros-warmup.php?token=YOUR_SECRET_TOKEN"
```

## 🛰 Version Request Proxy

| Request                                                      | Handler            |
| ------------------------------------------------------------ | ------------------ |
| `/routeros/NEWEST6.{stable,long-term,upgrade}`, `NEWESTa6.*` | `ros6-upgrade.php` |
| `/routeros/NEWEST7.{stable,long-term,upgrade}`, `NEWESTa7.*` | `ros7-upgrade.php` |

Each request is processed in the following order:

1. **Cache** — The key `<endpoint>_<requested version>` in `routeros/ros6.version.cache` / `ros7.version.cache` is checked. A hit returns `X-Cache: HIT`.
2. **Upstream** — A request is sent with `User-Agent: RouterOS <version>` and the original query string. The response is validated against `^\d+(\.\d+)+\s+\d+` before being cached. A successful upstream response returns `X-Cache: MISS`.
3. **Fallback** — If upstream is unavailable or its response is invalid, the proxy returns a local marker (`LATEST.6`, `LATEST.6fix`, `NEWEST7.stable`, `NEWESTa7.long-term`). If the marker is also missing, it uses the value configured in `mt_proxy_config.php`. The response includes `X-Cache: STALE`, and the event is recorded in `error_log`.

The `?version=` parameter is important: MikroTik returns the newest release relative to the version currently installed on the device. Therefore, the cache stores a separate entry for each update channel and version pair.

The transition from ROS 6 to ROS 7 is announced through `NEWEST6.upgrade` / `NEWESTa6.upgrade`. If these requests fail and the fallback value is incorrect, devices may either fail to discover ROS 7 or be offered it prematurely.

## 🚦 Upgrade Policy

The policy gate is `force_update.php`. The `BackupAndUpdate` script installed on the device sends a request such as:

```
/routeros/force_update.php?new_version=7.24.5&model=RB4011iGS%2B&serial=XXXXYYYY&name=HQ%20router&currentFirmware=7.20.3&upgradeFirmware=7.24.5
```

Every request with a non-empty `serial` updates the device record, its IP address (taken from the connection), firmware versions, device name, and last offered version. This allows the inventory to populate automatically without any scanning. Model and device name are percent-encoded by the script, so names containing `&`, `+`, spaces, etc. are transmitted correctly. The response is plain text: `ENABLED` or `DISABLED`.

Rule priority:

| # | Rule                         | Behavior                                                     |
| - | ---------------------------- | ------------------------------------------------------------ |
| 1 | Per-device list for `serial` | A non-empty list is final: only listed versions are allowed  |
| 2 | Model rule `model:<MODEL>`   | A non-empty list is final                                    |
| 3 | `global_versions` table      | Allows listed versions for devices not matched by levels 1–2 |
| 4 | Legacy `mt_proxy_rules.php`  | Global list from an old rules file, if still present         |
| 5 | `allowed_versions_hardcoded` | Shipped defaults: `6.49.23`, `7.24.5`, `7.23.8`              |

An empty list at any level causes the check to fall through to the next level, so newly registered devices are governed by the global list. If policy evaluation throws an exception, the response is `DISABLED`: the safe default is to leave a working router untouched.

## 🖥 Web Admin Panel

Open `http://<mirror>/mt-proxy/` and authenticate using Basic Auth. The interface does not use sessions and is accessible only through the protected directory.

**Devices** — Devices added automatically (`auto`), manually (`manual`), or imported from an older rules file (`legacy`). The table displays the model, current and target firmware, IP addresses with history in tooltips, comments, allowed versions, and last-seen time. It supports searching (including by IP address), editing and deleting individual rows — IP addresses can also be edited in the device form — and bulk replacement or appending of version lists using checkboxes.

**Global versions** — A fleet-wide version allowlist. Enter one version per line; comma-separated input is also accepted. Deletions take effect immediately.

**Current versions** — The panel shows the firmware versions currently offered by the proxy (read from the local marker files). Clicking a version opens its `CHANGELOG` (served by `changelog.php` from the mirrored `<version>/CHANGELOG`), so you can review a release before adding it to the allowlist.

## 🔧 Device Configuration

Static DNS records on each router (or on your external DNS server) redirect both hostnames to the mirror:

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/ip dns cache flush
```

A ready-to-use configuration is provided in `addons/mikrotik/dns.rsc`. Replace `SERVER_IP` before importing it.

After this, manual upgrades work as usual. On ROS 7 the update client uses HTTPS by default, so set `/system package update set mode=http` to let the device accept the mirror's plain-HTTP answers (the `BackupAndUpdate` script does this automatically):

```
/system package update check-for-updates
/system package update install
```

### Backup and upgrade scripts

| Script                   | Purpose                                                                                                                                                                                                                                            |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BackupAndUpdate`        | Daily cycle: check the mirror, create backups, install RouterOS upgrades, and upgrade RouterBOARD firmware. Works on ROS 6 and ROS 7 over HTTP or HTTPS                                                                                           |
| `BKPUPD-UPDATER`         | Downloads the current `BackupAndUpdate` script and its `BackupAndUpdate.md5` file from the mirror. Reimports the script only if its checksum has changed. Run it manually or invoke it from a scheduler. Automatic scheduler-based execution is intentionally not configured for security reasons. |
| `install_updater.rsc`    | Installer that downloads, imports, and runs `BKPUPD-UPDATER` over HTTPS (certificate not validated during bootstrap)                                                                                                                               |
| `install_updater-http.rsc`| The same installer using plain HTTP — for initial deployment before TLS is configured                                                                                                                                                              |

Replace `SERVER_NAME` with your mirror's hostname before publishing the scripts. Both device scripts default to `http://SERVER_NAME`. To switch the policy check and script updates to TLS, change the server URL in the scripts to `https://…`: the fetch helper then validates the certificate, and ROS 6 devices automatically download `fullchain.pem` and import it into the certificate store on the first run. ROS 7 uses the system trust store, so the CA must be covered by it or imported manually.

The updater requires both `BackupAndUpdate.rsc` **and** `BackupAndUpdate.md5` under `/routeros/`. The checksum file is not generated automatically by the repository; regenerate it after every script change:

```
cd /var/www/html/routeros
md5sum BackupAndUpdate.rsc | awk '{print $1}' > BackupAndUpdate.md5
chown www-data:www-data BackupAndUpdate.md5
```

The quickest deployment method is to import `BKPUPD-UPDATER` on the device once (via `install_updater.rsc` or `install_updater-http.rsc`). The remaining files will be downloaded and updated automatically.

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/system script run install_updater      # After importing addons/mikrotik/install_updater.rsc
```

How `BackupAndUpdate` works:

1. Registers the `BKPUPD-DAILY` scheduler at `05:00` and reads persistent failure counters (`fw,os,osver`) from its `comment` field. Each device first waits a deterministic 0–599 s delay derived from its serial number, so a fleet does not update all at once.
2. On ROS 7, sets `/system package update set mode=http` before `check-for-updates`, allowing the device to accept proxy responses over plain HTTP.
3. Sends the model, serial number, device name, current and target firmware, and offered version to `force_update.php` (HTTP by default; HTTPS with certificate validation if configured — see above). If the response is `DISABLED` or the server is unreachable, the RouterOS upgrade is canceled. The device state is reported on every run, even when no update is pending.
4. If the upgrade is allowed, first creates a scheduler to protect against reboot loops, then runs `system backup save` and `/export` using the name `auto-backup-<serial>-<version>-<date>` (under `flash/` if available) and deletes old `auto-backup-*` files.
5. Separately upgrades RouterBOARD firmware if `current-firmware != upgrade-firmware`.
6. Commands that trigger a reboot (`/system package update install`, `/system reboot`) are the final operations in the script.

**Reboot-loop protection:** Each attempt increments a counter in the scheduler's `comment` field. After `maxTries` (2) consecutive failed attempts, the script stops rebooting the device. Once the issue has been resolved, reset the counters:

```
/system scheduler set BKPUPD-DAILY comment=""
```

## 📝 Logging

Everything is sent to syslog (`daemon`) with a tag based on the script name. There are no separate log files that need rotation. The PHP endpoints and the warm-up report go to the web server error log.

```
journalctl -t sync_mikrotik_repo.sh -f   # Synchronization
tail -f /var/log/nginx/mirror-error.log  # Proxy misses, fallbacks, PHP errors
```

To completely disable script logging, set `LOG_OFF=1` in `config.sh`.

The `X-Cache` header is the quickest way to identify which layer responded to a device:

```
curl -sI "http://localhost/routeros/NEWESTa7.stable?version=7.24.4" | grep -i x-cache
```

## 🐛 Troubleshooting

| Symptom                                   | What to check                                                                                                                                                                      |
| ----------------------------------------- | -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Nothing downloads                         | Is `upgrade.mikrotik.com` reachable from the server? Is `wget` installed (missing wget exits with code `100`)? Does the process have write permissions to `TARGET_DIR` (exits `101`)? |
| A version is downloaded on every run      | Compare the local `LATEST.*` / `NEWEST*` marker with upstream. Markers are overwritten only after a completely successful download.                                                |
| `wireless-*.npk` is missing               | These packages are downloaded only for ROS 7 versions 7.12.1 and later on non-x86 architectures.                                                                                   |
| The device reports "no updates available" | Has the DNS cache been flushed? Is `/routeros` served from the **website root**? Is an `X-Cache` header present? If not, PHP routing is broken.                                    |
| The device is offered the wrong version   | The cache contains the relevant key. Inspect or delete the entry in `routeros/ros6.version.cache` or `ros7.version.cache`, or re-run `ros-warmup.php?token=…`.                       |
| The warm-up does nothing                  | `ros-warmup.php` returns 403 unless the token in the query matches `WARMUP_TOKEN` in `mt_proxy_config.php`; keep it in sync with `scripts/config.sh`. With an empty device database there is also nothing to warm up. |
| `403` when downloading a `.rsc` script    | Expected for browsers and `curl`: `/routeros/*.rsc` is served only to RouterOS User-Agents (`Mikrotik/x.y…Fetch`, `RouterOS 7.x…`).                                                |
| Winbox does not download                  | Is `curl` installed? Is `https://mikrotik.com/download/winbox` reachable?                                                                                                          |
| The web admin panel returns 404           | `FallbackResource` / `try_files` must point to `index.php`. SQLite must be writable by the web server user; WAL mode requires write access to the directory.                       |

## 🔒 Security Notes

- DNS redirection makes all devices on your network trust this host. Do not expose the mirror to untrusted network segments without access controls.
- The cache warm-up endpoint is protected only by a shared secret. Change `WARMUP_TOKEN` from `CHANGE_ME` in **both** `scripts/config.sh` and `html/mt-proxy/mt_proxy_config.php`, otherwise anyone who can reach the URL can trigger upstream requests with arbitrary version parameters.
- `BackupAndUpdate` / `BKPUPD-UPDATER` are imported with a full set of RouterOS policies (`ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon`) and can reboot devices. Anyone able to modify `/routeros/BackupAndUpdate.rsc` could potentially gain control over every router running the updater. Restrict access to the server itself; the vhost configuration limits `.rsc`/`.txt` downloads to RouterOS User-Agents, but an attacker on the mirror host is still a risk.
- The web admin panel is protected only by Basic Auth and vhost access restrictions. Do not expose it to the public Internet; restrict access by source IP and use a strong password.
- `mt_proxy_config.php` now contains a secret (`WARMUP_TOKEN`), and `mt_proxy.db` contains the device inventory, including serial numbers and IP addresses. Both vhost configurations block direct access to the database; store backups outside the document root and protect the PHP config files from source disclosure.
- Over plain HTTP the policy check transmits device metadata (serial, model, firmware) in clear text. Use HTTPS (and the CA bundle) if the devices' network path is not fully trusted.

## ⚠️ Known Limitations

- **Cache entries do not expire.** Each line in `ros6.version.cache` / `ros7.version.cache` stores `value|timestamp`, but readers compare only the value; the timestamp is informational. A cached `NEWEST*` response remains in place until its key is deleted or upstream returns a different value for the same endpoint/version pair. To pick up a reissued release immediately, delete the relevant entry or the entire cache file.
- **Downloads do not overwrite existing files.** `WGET_OPTS="-q -nc"` (`no-clobber`) is used for all requests, so a package changed by MikroTik under the same filename will not be downloaded again. Note that `force` disables only the "version unchanged" check, not `-nc`. To truly download a file again, remove `${TARGET_DIR}/<version>/`.
- **Only the latest release in each channel is mirrored automatically.** Older versions remain on disk, but the synchronization cycle tracks only `LATEST.*` / `NEWEST*`. Use `download_ros.sh` to fetch a specific version.
- **The architecture list is static.** New hardware architectures must be added manually to `firmware_arch`; otherwise, their packages will be silently skipped.
- The scripts run as root and the cron job uses `chown www-data`. The setup assumes the mirror is managed by root; there is no unprivileged installation mode.

## 📄 License

Distributed under the MIT License. Copyright (c) 2023 Roman Dmitriev.
