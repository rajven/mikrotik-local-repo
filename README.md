# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Standalone RouterOS package mirror + smart upgrade proxy + per-device upgrade policy.

## Table of Contents

- [About](#-about) · [Features](#-features) · [How it works](#-how-it-works) · [Project structure](#-project-structure)
- [Requirements](#-requirements) · [Installation](#-installation) · [Configuration](# -configuration) · [Synchronization](#-synchronization)
- [Version-request proxy](#-version-request-proxy) · [Update policy](#-update-policy) · [Web admin](#-web-admin)
- [Device-side configuration](#-device-side-configuration) · [Logging](#-logging) · [Troubleshooting](#-troubleshooting)
- [Security notes](#-security-notes) · [Known limitations](# -known-limitations)

---

## 📖 About

A standalone, three-layer solution for MikroTik device fleets without Internet access (or with restricted access):

1. **Mirror** — Bash synchronization scripts download RouterOS 6 and RouterOS 7 packages, Winbox, and Netinstall-related files from the official repositories (`upgrade.mikrotik.com` / `download.mikrotik.com`) into the web server's document root.
2. **Upgrade proxy** — PHP handlers intercept RouterOS requests for available versions (`NEWEST6.*`, `NEWESTa7.stable`, etc.), cache responses, and serve the actual package files from the same host.
3. **Upgrade policy** — Each planned upgrade is checked against the device's serial number, model, or a global policy. Rules are managed through a web interface. If no explicitly permitted versions are configured for a router, it is upgraded to the default version specified by the administrator.

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
- 📄 Additional files: `CHANGELOG`, `packages.csv`, Netinstall, ISO images, `.mib`, `btest.exe`, `flashfig.exe`.
- ⏩ Unchanged versions are skipped — only new or updated releases are downloaded; `force` downloads everything again.
- 🎯 `download_ros.sh` downloads one specific version, including older releases.

**Upgrade proxy**

- 🛰 Proxies and caches `NEWEST6/NEWESTa6/NEWEST7/NEWESTa7` responses for the `.stable`, `.long-term`, and `.upgrade` variants.
- 🔥 `ros-warmup.pl` pre-populates the version cache after each synchronization so the first device request does not have to reach the Internet.
- 🔀 Supports Apache (FPM **or** mod_php, auto-detected) and Nginx; ready-to-use configurations are provided in `addons/`.

**Upgrade policy**

- 🚦 `force_update.php` returns `ENABLED` / `DISABLED` for the requested version.
- 🗂 Rules can be defined by serial number, by model (`model:RB4011`), or globally, with a defined priority order.
- 👀 Devices are registered automatically on their first request: serial number, model, IP address, current and target firmware versions, and last-seen time.
- 🖥 Web admin panel (Basic Auth + SQLite) with search, bulk editing, and a global version allowlist.
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
│   ├── config.sh               # Paths, versions, architectures, URL scheme
│   ├── functions.sh            # Logging, additional files, Winbox
│   ├── ros6_functions.sh       # RouterOS 6 download logic
│   ├── ros7_functions.sh       # RouterOS 7 download logic (before/after 7.12.1)
│   └── ros-warmup.pl           # Pre-populate the proxy version cache
├── html/
│   ├── mt-proxy/
│   │   ├── index.php           # Web admin panel (devices, rules, global versions)
│   │   ├── db.php              # SQLite schema + decision logic
│   │   ├── ros6-upgrade.php    # NEWEST6.* / NEWESTa6.* proxy
│   │   ├── ros7-upgrade.php    # NEWEST7.* / NEWESTa7.* proxy
│   │   ├── force_update.php    # ENABLED/DISABLED gate
│   │   └── mt_proxy_config.php # Upstream, timeouts, fallback versions
│   ├── routeros/               # Initial *.version.cache files for the mirror
│   └── fullchain.pem           # CA certificate chain for HTTPS policy checks on devices
├── addons/
│   ├── apache/                 # vhost 00-mirror.conf + FPM/mod_php auto-detection
│   ├── nginx/                  # site.conf + mt-fastcgi.conf snippet
│   ├── cron.d/                 # sync_ROS_repo — scheduled synchronization
│   └── mikrotik/               # Router scripts (.txt = source / .rsc = installer)
├── CHANGELOG
└── LICENSE                     # MIT
```

## 📋 Requirements

Debian / Ubuntu and the following packages:

| Component                                               | Used by                                |
| ------------------------------------------------------- | -------------------------------------- |
| `bash`, `wget`, `curl`, `unzip`, `coreutils`            | Synchronization scripts                |
| `perl` + `libwww-perl`, `liburi-perl`                   | `ros-warmup.pl`                        |
| `php-cli`, `php-curl`, `php-sqlite3`                    | Proxy, upgrade policy, web admin panel |
| `apache2` **or** `nginx` + `php-fpm`                    | Serving the mirror and admin panel     |
| `mod_rewrite`, `mod_headers`, `mod_proxy_fcgi` (Apache) | Routing `/routeros/*` requests to FPM  |

## 🚀 Installation

All examples use the standard Debian layout: scripts in `/usr/local/bin`, the web server document root at `/var/www/html`, and the mirror at `/var/www/html/routeros`.

### 1. Install packages

**Apache**

```
apt install git bash wget curl unzip php php-curl php-sqlite3 \
            libwww-perl liburi-perl apache2 -y
a2enmod rewrite headers proxy_fcgi setenvif
a2enconf php8.3-fpm        # Specify your PHP version
```

**Nginx**

```
apt install git bash wget curl unzip php php-curl php-sqlite3 php-fpm \
            libwww-perl liburi-perl nginx -y
```

> In the PHP-FPM pool configuration, set `clear_env = no` if you intend to override parameters using environment variables.

### 2. Install the synchronization scripts

```
git clone https://github.com/rajven/mikrotik-local-repo.git
cd mikrotik-local-repo

cp scripts/*.sh scripts/ros-warmup.pl /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh \
         /usr/local/bin/download_ros.sh \
         /usr/local/bin/ros-warmup.pl
```

> ⚠️ `sync_mikrotik_repo.sh` has `SCRIPT_DIR="/usr/local/bin"` hardcoded for `source` operations and calls `/usr/local/bin/ros-warmup.pl` using an absolute path. If you move the scripts elsewhere, update both lines. `download_ros.sh` uses `dirname "$0"` and works from any directory, provided all the scripts are located together.

### 3. Install the web layer

```
mkdir -p /var/www/html/routeros
cp -r html/mt-proxy             /var/www/html/
cp    html/routeros/*.cache     /var/www/html/routeros/
cp    html/fullchain.pem        /var/www/html/
cp    addons/mikrotik/*.rsc     /var/www/html/routeros/   # Device scripts
chown www-data:www-data -R /var/www/html
```

Router scripts are provided in two formats: `*.txt` is the readable source, while `*.rsc` is the same script wrapped in `/system script add`, ready for import. Only the `.rsc` files need to be exposed to devices.

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

The `/routeros` directory **must** be located at the website root. Devices request paths such as `/routeros/7.24.5/routeros-7.24.5-arm64.npk`, and the proxy endpoints match `/routeros/NEWEST…`. Serving the mirror from a subdirectory breaks both.

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

The second request registers a device with serial `TEST` in the database. On a fresh installation, the global version list is empty, so priority level 4 (the hardcoded list) determines the result: `7.24.5` returns `ENABLED`, while a version not on the list returns `DISABLED`. To override the hardcoded list, add your versions under **Global versions** in the web admin panel.

## ⚙️ Configuration

### Synchronization scripts — `scripts/config.sh`

```
TARGET_DIR="/var/www/html/routeros"   # Mirror root, served by the web server
SITE_URL="http://localhost"           # Base URL used by ros-warmup.pl
WGET="/bin/wget"                      # Path to wget; otherwise searched in $PATH
LOG_OFF=0                             # 1 — completely disable syslog logging
URL_SCHEMA="http"                     # http|https for upgrade.mikrotik.com; invalid values default to http

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
| `allowed_versions_hardcoded`       | Last-resort allowlist (`6.49.23`, `7.24.5`, `7.23.8`)                                 |
| `fallbacks`                        | Per-endpoint fallback responses when neither upstream nor local markers are available |
| `v6` / `v7`                        | Log prefix, cache file, default version, `User-Agent` prefix, local marker files      |

Edit `mt_proxy_config.php` when MikroTik releases new versions and you want to update the safe fallback values. The model rules file `mt_proxy_rules.php` is no longer shipped, but `db.php` still reads it once to migrate older installations into SQLite.

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
5. The version cache is warmed by sending requests to the local proxy endpoints.

The ROS 7 channel is deliberately downloaded twice: `download_ros7 7.10` handles releases before 7.12.1, while `download_ros7 7.12.1 a` handles the `NEWESTa7.*` API introduced in 7.12.1. These require different `User-Agent` values (`RouterOS <version>`).

### Cache warm-up

At the end of `sync_mikrotik_repo.sh`, `ros-warmup.pl` is called twice with different `WARMUP_CACHE_FILE` values (`ros6.version.cache` and `ros7.version.cache`) and `WARMUP_BASE` derived from `SITE_URL`. The script reads the cache over HTTP, selects the last `WARMUP_KEEP` versions requested for each endpoint (3 by default), and requests each one through the local proxy.

Existing keys are served from the cache. The script fills in combinations of endpoint and version that have not yet been cached, which devices may request after a new release becomes available. It also logs routing diagnostics to syslog, making PHP routing problems easier to detect.

Run it manually after changing `SITE_URL` or clearing the cache:

```
WARMUP_BASE=http://mirror.example.lan WARMUP_CACHE_FILE=ros7.version.cache \
WARMUP_KEEP=5 WARMUP_VERBOSE=1 /usr/local/bin/ros-warmup.pl
```

Increase `WARMUP_KEEP` immediately after deploying a fresh mirror. Cached proxy responses are not refreshed automatically, so deleting the cache file (or an individual entry) remains the most reliable way to trigger a new check.

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
/routeros/force_update.php?new_version=7.24.5&model=RB4011iGS%2B&serial=XXXXYYYY&currentFirmware=7.20.3&upgradeFirmware=7.24.5
```

Every request with a non-empty `serial` updates the device record, its IP address, firmware versions, and last offered version. This allows the inventory to populate automatically without any scanning. The response is plain text: `ENABLED` or `DISABLED`.

Rule priority:

| # | Rule                         | Behavior                                                     |
| - | ---------------------------- | ------------------------------------------------------------ |
| 1 | Per-device list for `serial` | A non-empty list is final: only listed versions are allowed  |
| 2 | Model rule `model:<MODEL>`   | A non-empty list is final                                    |
| 3 | `global_versions` table      | Allows listed versions for devices not matched by levels 1–2 |
| 4 | `allowed_versions_hardcoded` | Shipped defaults: `6.49.23`, `7.24.5`, `7.23.8`              |

An empty list at any level causes the check to fall through to the next level, so newly registered devices are governed by the global list. If policy evaluation throws an exception, the response is `DISABLED`: the safe default is to leave a working router untouched.

## 🖥 Web Admin Panel

Open `http://<mirror>/mt-proxy/` and authenticate using Basic Auth. The interface does not use sessions and is accessible only through the protected directory.

**Devices** — Devices added automatically (`auto`), manually (`manual`), or imported from an older rules file (`legacy`). The table displays the model, current and target firmware, IP addresses with history in tooltips, comments, allowed versions, and last-seen time. It supports searching, editing and deleting individual rows, and bulk replacement or appending of version lists using checkboxes.

**Global versions** — A fleet-wide version allowlist. Enter one version per line; comma-separated input is also accepted. Deletions take effect immediately.

## 🔧 Device Configuration

Static DNS records on each router (or on your external DNS server) redirect both hostnames to the mirror:

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/ip dns cache flush
```

A ready-to-use configuration is provided in `addons/mikrotik/dns.rsc`. Replace `SERVER_IP` before importing it.

After this, manual upgrades work as usual (ROS 7 will be configured to use HTTP mode):

```
/system package update check-for-updates
/system package update install
```

### Backup and upgrade scripts

| Script                | Purpose                                                                                                                                                                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BackupAndUpdate`     | Daily cycle: check the mirror, create backups, install RouterOS upgrades, and upgrade RouterBOARD firmware                                                                                                                                                                                         |
| `BKPUPD-UPDATER`      | Downloads the current `BackupAndUpdate` script and its `BackupAndUpdate.md5` file from the mirror. Reimports the script only if its checksum has changed. Run it manually or invoke it from a scheduler. Automatic scheduler-based execution is intentionally not configured for security reasons. |
| `install_updater.rsc` | Installer that downloads, imports, and runs `BKPUPD-UPDATER`                                                                                                                                                                                                                                       |

Replace `SERVER_NAME` with your mirror's hostname before publishing the scripts (`SERVER_IP` is also supported). HTTPS requires a certificate trusted by the CA chain described above; otherwise, use the `-http` variants.

The updater requires both `BackupAndUpdate.rsc` **and** `BackupAndUpdate.md5` under `/routeros/`. The checksum file is not generated automatically by the repository; regenerate it after every script change:

```
cd /var/www/html/routeros
md5sum BackupAndUpdate.rsc | awk '{print $1}' > BackupAndUpdate.md5
chown www-data:www-data BackupAndUpdate.md5
```

The quickest deployment method is to import `BKPUPD-UPDATER` on the device once. The remaining files will be downloaded and updated automatically.

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/system script run install_updater      # After importing addons/mikrotik/install_updater.rsc
```

How `BackupAndUpdate` works:

1. Registers the `BKPUPD-DAILY` scheduler at `05:00` and reads persistent failure counters (`fw,os,version`) from its `comment` field.
2. On ROS 7, sets `/system package update set mode=http` before `check-for-updates`, allowing the device to accept proxy responses over plain HTTP.
3. Sends the model, serial number, current and target firmware, and offered version to `force_update.php` over HTTPS, validating the certificate. On the first run, ROS 6 imports `fullchain.pem` into the certificate store. If the response is `DISABLED` or the server is unreachable, the RouterOS upgrade is canceled.
4. If the upgrade is allowed, first creates a scheduler to protect against reboot loops, then runs `system backup save` and `/export` using the name `auto-backup-<serial>-<version>-<date>` (under `flash/` if available) and deletes old `auto-backup-*` files.
5. Separately upgrades RouterBOARD firmware if `current-firmware != upgrade-firmware`.
6. Commands that trigger a reboot (`/system package update install`, `/system reboot`) are the final operations in the script.

**Reboot-loop protection:** Each attempt increments a counter in the scheduler's `comment` field. After `maxTries` (2) consecutive failed attempts, the script stops rebooting the device. Once the issue has been resolved, reset the counters:

```
/system scheduler set BKPUPD-DAILY comment=""
```

## 📝 Logging

Everything is sent to syslog (`daemon`) with a tag based on the script name. There are no separate log files that need rotation.

```
journalctl -t sync_mikrotik_repo.sh -f   # Synchronization
journalctl -t ros-warmup -f              # Cache warm-up
tail -f /var/log/nginx/mirror-error.log  # Proxy misses, fallbacks, PHP errors
```

To completely disable script logging, set `LOG_OFF=1` in `config.sh`.

The `X-Cache` header is the quickest way to identify which layer responded to a device:

```
curl -sI "http://localhost/routeros/NEWESTa7.stable?version=7.24.4" | grep -i x-cache
```

## 🐛 Troubleshooting

| Symptom                                   | What to check                                                                                                                                                                      |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nothing downloads                         | Is `upgrade.mikrotik.com` reachable from the server? Is `wget` installed? Does the process have write permissions to `TARGET_DIR`? Without them, the script exits with code `101`. |
| A version is downloaded on every run      | Compare the local `LATEST.*` / `NEWEST*` marker with upstream. Markers are overwritten only after a completely successful download.                                                |
| `wireless-*.npk` is missing               | These packages are downloaded only for ROS 7 versions 7.12.1 and later on non-x86 architectures.                                                                                   |
| The device reports "no updates available" | Has the DNS cache been flushed? Is `/routeros` served from the **website root**? Is an `X-Cache` header present? If not, PHP routing is broken.                                    |
| The device is offered the wrong version   | The cache contains the relevant key. Inspect or delete the entry in `routeros/ros6.version.cache` or `ros7.version.cache`, or run `ros-warmup.pl`.                                 |
| Winbox does not download                  | Is `curl` installed? Is `https://mikrotik.com/download/winbox` reachable?                                                                                                          |
| The web admin panel returns 404           | `FallbackResource` / `try_files` must point to `index.php`. SQLite must be writable by the web server user; WAL mode requires write access to the directory.                       |

## 🔒 Security Notes

- DNS redirection makes all devices on your network trust this host. Do not expose the mirror to untrusted network segments without access controls.
- `BackupAndUpdate` / `BKPUPD-UPDATER` use a full set of policies (`reboot`, `write`, `policy`, `password`, `sensitive`, `romon`, etc.) and can reboot devices. Anyone able to modify `/routeros/BackupAndUpdate.rsc` could potentially gain control over every router running the updater. Restrict access to the server itself.
- The web admin panel is protected only by Basic Auth and vhost access restrictions. Do not expose it to the public Internet; restrict access by source IP and use a strong password.
- `mt_proxy_config.php` contains no secrets, but `mt_proxy.db` contains the device inventory, including serial numbers and IP addresses. Both vhost configurations block access to it, but backups should be stored outside the document root.
- Prefer the HTTPS script variants. The `-http` variants transmit device metadata (serial number, model, and firmware versions) in plaintext.
- The proxy verifies upstream TLS certificates. `ros-warmup.pl` disables hostname verification only because it connects to the local mirror.

## ⚠️ Known Limitations

- **Cache entries do not expire.** Each line in `ros6.version.cache` / `ros7.version.cache` stores `value|timestamp`, but readers compare only the value; the timestamp is informational. A cached `NEWEST*` response remains in place until its key is deleted or upstream returns a different value for the same endpoint/version pair. To pick up a reissued release immediately, delete the relevant entry or the entire cache file.
- **Downloads do not overwrite existing files.** `WGET_OPTS="-q -nc"` (`no-clobber`) is used for all requests, so a package changed by MikroTik under the same filename will not be downloaded again. Note that `force` disables only the "version unchanged" check, not `-nc`. To truly download a file again, remove `${TARGET_DIR}/<version>/`.
- **Only the latest release in each channel is mirrored automatically.** Older versions remain on disk, but the synchronization cycle tracks only `LATEST.*` / `NEWEST*`. Use `download_ros.sh` to fetch a specific version.
- **The architecture list is static.** New hardware architectures must be added manually to `firmware_arch`; otherwise, their packages will be silently skipped.
- The scripts run as root and the cron job uses `chown www-data`. The setup assumes the mirror is managed by root; there is no unprivileged installation mode.

## 📄 License

Distributed under the MIT License. Copyright (c) 2023 Roman Dmitriev.
