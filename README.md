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
└── README.md
```

## 🚀 Installation

Install the required packages.

### Apache

```bash
apt install git php php-curl wget curl apache2 -y

a2enmod rewrite
a2enmod headers
```

### Nginx

```bash
apt install git php php-curl wget curl nginx php-fpm -y
```

Clone the repository:

```bash
git clone https://github.com/<username>/mikrotik-local-repo.git
cd mikrotik-local-repo
```

Copy the synchronization scripts to the default working directory:

```bash
cp sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh
```

Make the scripts executable:

```bash
chmod +x *.sh
```

Install the RouterOS upgrade version proxy scripts:

```bash
cp html/ros6-upgrade.php /path/to/mirror/
cp html/ros7-upgrade.php /path/to/mirror/
```

> ⚠️ The `SCRIPT_DIR` variable in `sync_mikrotik_repo.sh` points to `/usr/local/bin` by default. If you install the scripts elsewhere, adjust this variable manually.

## ⚙ Configuration

Edit **`config.sh`** according to your environment:

```bash
# Local mirror path
TARGET_DIR="/mnt/mirror/routeros"

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

For example, run synchronization every day at 03:00:

```cron
0 3 * * * /usr/local/bin/sync_mikrotik_repo.sh >> /var/log/mikrotik-sync.log 2>&1
```

## 🌐 Web server configuration

The `$TARGET_DIR` directory must be accessible through the web server.

> ⚠️ **Important:** The `/routeros` directory must be located at the **site root**, not inside another subdirectory. Serve the parent directory (`/mnt/mirror`), not `/routeros` itself.

### Nginx

Example configuration:

```nginx
server {
    listen 80;
    server_name download.mikrotik.com upgrade.mikrotik.com;

    root /mnt/mirror;   # WITHOUT /routeros — /routeros must be at the site root!

    location / {
        autoindex on;
    }

    # MikroTik upgrade script
    location ~ ^/ros6-upgrade.php { deny all; }
    location ~ ^/ros7-upgrade.php { deny all; }

    location ~ ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /mnt/mirror/ros6-upgrade.php;
        fastcgi_param QUERY_STRING    $query_string;
        fastcgi_param REQUEST_URI     $request_uri;

        # Disable chunked encoding on the outgoing response
        chunked_transfer_encoding off;

        # Buffer the entire PHP response so nginx can calculate Content-Length
        # if PHP did not provide it
        fastcgi_buffering on;

        # Prevent nginx from adding or modifying encodings
        gzip off;
        proxy_set_header Accept-Encoding "";
    }

    location ~ ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /mnt/mirror/ros7-upgrade.php;
        fastcgi_param QUERY_STRING    $query_string;
        fastcgi_param REQUEST_URI     $request_uri;

        # Disable chunked encoding on the outgoing response
        chunked_transfer_encoding off;

        # Buffer the entire PHP response so nginx can calculate Content-Length
        # if PHP did not provide it
        fastcgi_buffering on;

        # Prevent nginx from adding or modifying encodings
        gzip off;
        proxy_set_header Accept-Encoding "";
    }
}
```

### Apache

Example configuration:

```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    RewriteEngine On

    # Block direct access to the PHP backend,
    # while allowing internal rewrites.
    RewriteCond %{THE_REQUEST} \s/+ros6-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros6-upgrade\.php$ - [F,L]

    RewriteCond %{THE_REQUEST} \s/+ros7-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros7-upgrade\.php$ - [F,L]

    # RouterOS 6 update URLs -> PHP backend
    RewriteRule ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ /ros6-upgrade.php [L]

    # RouterOS 7 update URLs -> PHP backend
    RewriteRule ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ /ros7-upgrade.php [L]

    # Disable gzip compression for these URLs
    <IfModule mod_deflate.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" no-gzip dont-vary
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" no-gzip dont-vary
    </IfModule>

    # Remove Accept-Encoding from incoming requests
    <IfModule mod_headers.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        RequestHeader unset Accept-Encoding env=NO_ACCEPT_ENCODING
    </IfModule>
</VirtualHost>
```

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

Logs are written to the file specified by the `LOG_FILE` variable in `config.sh`.

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
