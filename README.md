# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Standalone RouterOS package mirror + smart upgrade proxy + per-device upgrade policy.

## 📖 What it is

A three-layer solution for fleets of MikroTik devices without Internet access
(or with restricted access):

1. **Mirror** — sync scripts download RouterOS 6/7 packages, Winbox and
   Netinstall helpers from `upgrade.mikrotik.com` / `download.mikrotik.com`
   into a web-served directory.
2. **Upgrade proxy** — PHP handlers answer RouterOS version-discovery
   requests (`NEWEST6.*`, `NEWESTa7.stable`, …), cache the answers and keep
   devices resolving package URLs to the mirror.
3. **Upgrade policy** — every planned update is gated per serial, per model
   or globally (`force_update.php` → `ENABLED`/`DISABLED`), managed through
   a web admin panel. Devices self-register on first contact — no scanning,
   no credentials, no reachability requirements.

```
     Internet: upgrade.mikrotik.com          (only during sync)
                       │
                       ▼
   Mirror server:  routeros/  +  mt-proxy/  +  SQLite/admin UI
                       ▲
        static DNS:    │  version requests, .npk downloads, policy checks
   MikroTik routers ───┘  download|upgrade.mikrotik.com → mirror
```

## ✨ Features

- 🔄 RouterOS 6 (stable + LTS) and RouterOS 7 (stable + long-term), pre- and post-`7.12.1` APIs
- 🏗 All architectures: `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📦 `all_packages-*.zip` downloaded **and unpacked**; individual `.npk` per version
- ⏩ Incremental sync (markers) + `force` + `download_ros.sh` for historical versions
- 📥 Winbox mirror (`.zip`, `.dmg`, `.sha256`), Netinstall, ISO, `.mib`, `CHANGELOG`s
- 🛰 Version-request proxy with a persistent cache and `X-Cache: HIT|MISS|STALE`
- 🧯 Three-level degradation: upstream → local markers → configured fallbacks
- 🔥 Token-protected cache warm-up driven by the firmware versions of registered devices
- 🚦 Policy precedence: device → model → global → legacy → built-in allowlist; errors fail closed
- 👀 Inventory auto-registration: serial, model, name, IPs, firmwares, last seen (+ inline CHANGELOG viewer)
- 🤖 RouterOS-side scripts: backup + update per schedule, reboot-loop protection, self-updating installer
- 🐳 All-in-one Docker image; or classic bare-metal Apache/nginx deployment

Full documentation (bare-metal installation, policy engine internals,
synchronization details, logging, troubleshooting): [docs/](docs/).

## 🚀 Quick start (Docker)

The published image is `rajven/mikrotik-local-repo:latest` (multi-arch:
amd64 + arm64). The ready-made setup lives in [`addons/docker/`](addons/docker/):

```bash
sudo mkdir -p /opt/mikrotik && cd /opt/mikrotik
# take compose.yaml and .env.example from addons/docker/ of this repo
curl -o compose.yaml  https://raw.githubusercontent.com/rajven/mikrotik-local-repo/main/addons/docker/compose.yaml
curl -o .env.example  https://raw.githubusercontent.com/rajven/mikrotik-local-repo/main/addons/docker/.env.example
cp .env.example .env && chmod 600 .env
$EDITOR .env                      # SITE_URL, WARMUP_TOKEN, ADMIN_PASSWORD...
docker compose pull && docker compose up -d
docker compose logs -f            # first sync starts after ~90 s
```

Check the installation:

```bash
curl -i "http://localhost/routeros/NEWEST7.stable" | grep -i x-cache    # MISS, then HIT
# admin panel: http://<host>/mt-proxy/  (ADMIN_USER / ADMIN_PASSWORD)
```

Point routers at the mirror (from `addons/mikrotik/dns.rsc`; replace the IP):

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Update the fleet once per device (HTTP bootstrap; the scripts then
self-update via `BKPUPD-UPDATER`):

```routeros
/import file-name=install_updater-http.rsc    # addons/mikrotik/, SERVER_NAME baked by the container
```

## ⚙️ .env reference

| Variable | Meaning |
|---|---|
| `SITE_URL` | The mirror address **as routers see it** (e.g. `http://192.168.0.1` or `https://mirror.example.net` behind a TLS proxy). Baked into the device-facing `.rsc` scripts at every start (`SERVER_NAME` placeholder, scheme included), and `SERVER_IP` in `dns.rsc` gets its resolved IPv4. Not used for internal calls — warm-up always hits `http://localhost` inside the container. |
| `WARMUP_TOKEN` | Secret for `/routeros/ros-warmup.php`. Injected into both `config.sh` and `mt_proxy_config.php` on first start. Letters/digits/`_ -` only. |
| `ADMIN_USER` / `ADMIN_PASSWORD` | Basic Auth for the web admin (`/mt-proxy/`). Empty password → random one, printed to `docker compose logs` once. `ADMIN_PASSWORD_HASH` (bcrypt/`$6$`) is an alternative. |
| `TZ` | Container and PHP timezone (affects logs/UI timestamps). |
| `SYNC_INTERVAL_HOURS` / `SYNC_START_DELAY` | How often to sync and the sleep before the first run after boot. |
| `MIRROR_DATA_DIR` | Host directory bind-mounted to `/data` (default `./data` next to the compose file). |

`WARMUP_TOKEN` / `SITE_URL` etc. are applied to the generated configs on
**first** start of a fresh `MIRROR_DATA_DIR`; afterwards the source of truth
is `/data/config/*` files. Restart after changing them.

## 💾 Where data lives

```
$MIRROR_DATA_DIR/
├── routeros/   # the package mirror + version caches + device *.rsc/*.md5
├── state/      # mt_proxy.db — inventory and policies
└── config/     # config.sh, mt_proxy_config.php, fullchain.pem, .htpasswd
```

Backup = stop + copy of this directory. On the host the files belong to
uid 33 (`www-data` in the image) — that's expected after bind mounts.

## 🔒 External HTTPS (reverse proxy)

The container serves plain HTTP (this is what RouterOS `mode=http` wants and
what the air-gapped scenario expects). To publish the admin panel and/or
device endpoints over TLS, put a reverse proxy in front — working examples:

- [`addons/docker/nginx/mirror.conf`](addons/docker/nginx/mirror.conf) — nginx fragment
- [`addons/docker/apache/site.conf`](addons/docker/apache/site.conf) — Apache fragment

Both proxy `/mt-proxy/` and `/routeros/` to the container (enable the
`8080:80` port mapping in `compose.yaml`) and **must preserve `User-Agent`**
(the container gates `.rsc`/`.txt` downloads to RouterOS user agents). Two
caveats when device traffic goes via the proxy:

- the inventory records the **proxy's** IP as the device address (PHP reads
  `REMOTE_ADDR`; there is no `X-Forwarded-For` trust yet) — let devices hit
  port 80 of the mirror directly if you care about that column;
- `SITE_URL` then must be the public HTTPS address, and devices will require
  a trusted certificate (`fullchain.pem` on ROS 6) for policy checks.

## 🛠 Building / bare metal

- Docker internals (entrypoint behaviour, image patches, supervisord layout):
  [`docker/README.md`](docker/README.md), built by [`docker/Dockerfile`](docker/Dockerfile)
  with the repo root as context.
- Classic installation (scripts + Apache/nginx, no Docker), policy engine,
  synchronization and device-script details, logging, troubleshooting:
  [docs/](docs/).

## 📄 License

Distributed under the MIT License. Copyright (c) 2023 Roman Dmitriev.
