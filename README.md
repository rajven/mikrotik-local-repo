# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> A local MikroTik RouterOS repository mirror — download packages from the official repositories and serve them to devices on your local network without Internet access.

## 📖 About

This project automatically synchronizes RouterOS 6 and RouterOS 7 packages from the official MikroTik repositories (`upgrade.mikrotik.com` / `download.mikrotik.com`) to a local directory served by a web server.

MikroTik devices on the local network can receive updates from the local mirror by overriding the DNS records for the official MikroTik repository hostnames.

## ✨ Features

- 🔄 Synchronization of **RouterOS 6** (stable and LTS/fix) and **RouterOS 7** (stable and long-term)
- 🏗 Support for all currently supported architectures:
  `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📥 Download of **Winbox** for all available versions (`.zip`, `.dmg`)
- 📄 Download of `CHANGELOG`, `packages.csv`, and additional files
- ⏩ Skipping unchanged versions — only changed versions are downloaded again
- 🛠 Forced download mode (`--force`)
- 📝 Flexible logging with the ability to disable file logging
- 🤖 Correct `User-Agent` handling for ROS 7 before and after version 7.12.1

## 📁 Project structure

```text
mikrotik-local-repo/
├── sync_mikrotik_repo.sh      # Main synchronization script
├── config.sh                  # Configuration (paths, versions, architectures)
├── functions.sh               # Common functions: logging, additional files, Winbox
├── ros6_functions.sh          # RouterOS 6 download functions
├── ros7_functions.sh          # RouterOS 7 download functions
├── ros-warmup.pl              # warming up the version cache
└── README.md
```

## 🚀 Installation

Install the required packages.

### Apache

```bash
apt install git php php-curl wget curl apache2 libwww-perl liburi-perl -y

a2enmod rewrite
a2enmod headers
```

### Nginx

```bash
apt install git php php-curl wget curl nginx php-fpm libwww-perl liburi-perl -y
```

Clone the repository:

```bash
git clone https://github.com/<username>/mikrotik-local-repo.git
cd mikrotik-local-repo
```

Copy the synchronization scripts to the default working directory:

```bash
cp ros-warmup.pl sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh
chmod +x /usr/local/bin/ros-warmup.pl
```

Install the RouterOS upgrade version proxy scripts and cache:

```bash
mkdir -p /var/www/html/mt-proxy/
mkdir -p /var/www/html/routeros/
cp html/mt-proxy/*.php /var/www/html/mt-proxy/
cp html/routeros/*.cache /var/www/html/routeros/
chown www-data:www-data -R /var/www/html/
```

> ⚠️ The `SCRIPT_DIR` variable in `sync_mikrotik_repo.sh` points to `/usr/local/bin` by default. If you install the scripts elsewhere, adjust this variable manually.

## ⚙ Configuration

Edit **`config.sh`** according to your environment:

```bash
# Local mirror path
TARGET_DIR="/var/www/html/routeros"

# this site url
SITE_URL="http://localhost"

# RouterOS 6 versions:
#   6     - stable release
#   6fix  - LTS release
versions6=("6" "6fix")

# RouterOS 7 versions:
versions7=("stable" "long-term")

# Required architectures
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")
```

## 🏃 Usage

### Regular synchronization

Downloads only new or changed versions:

```bash
/usr/local/bin/sync_mikrotik_repo.sh
```

### Forced synchronization

Ignores the cached version information and forces downloads:

```bash
/usr/local/bin/sync_mikrotik_repo.sh force
```

### Scheduled synchronization with cron

Edit the root crontab:

```bash
sudo crontab -e
```

For example, run synchronization every 3 hours:

```cron
1 */3 * * * root /usr/local/bin/sync_mikrotik_repo.sh 2>/dev/null && chown www-data:www-data -R /var/www/html
```

## 🌐 Web server configuration

The `$TARGET_DIR` directory must be accessible through the web server.

> ⚠️ **Important:** The `/routeros` directory must be located at the **site root**, not inside another subdirectory. Serve the parent directory (`/mnt/mirror`), not `/routeros` itself.

### Nginx

Example configuration in addons/nginx/

### Apache

Example configuration in addons/apache/

## 🔧 MikroTik device configuration

On your MikroTik devices, override the DNS records for the official MikroTik repository hostnames and point them to the IP address of your local mirror:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Replace `192.168.0.1` with the IP address of your web server.

The devices will then use the local mirror for updates:

```routeros
/system package update check-for-updates
/system package update install
```

## 🛠 How it works

```text
┌──────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
│  upgrade.mikrotik.com│ ──────► │ sync_mikrotik_repo  │ ──────► │ Local server     │
│ download.mikrotik.com│         │  (wget/curl)        │         │  /mnt/mirror     │
└──────────────────────┘         └─────────────────────┘         └────────┬─────────┘
                                                                          │
                                                                   DNS override
                                                                          │
                                                                 ┌────────▼─────────┐
                                                                 │  MikroTik        │
                                                                 │  devices         │
                                                                 └──────────────────┘
```

1. The synchronization script checks `LATEST.*` / `NEWEST*` files for new versions.
2. When a new version is detected, packages for all configured architectures are downloaded.
3. Additional files are downloaded, including `CHANGELOG`, `packages.csv`, `routeros-*.npk`, and `wireless-*.npk` for ROS 7 ≥ 7.12.1.
4. All currently available Winbox versions are downloaded separately.
5. MikroTik devices use the static DNS records to access the local mirror.

## 📝 Logging

Logs are written to the syslog

To disable logging to a file and only output messages to the console, set:

```bash
LOG_OFF=1
```

## 🐛 Troubleshooting

| Problem | Solution |
|---|---|
| Packages are not downloaded | Check that `upgrade.mikrotik.com` is accessible from the mirror server |
| Devices do not see updates | Verify the DNS records and make sure the web server serves `/routeros` from the site root |
| Winbox download fails | Check that `curl` is installed and that `mikrotik.com/download/winbox` is accessible |

## 📄 License

Distributed under the [MIT License](LICENSE).
