# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Автономное зеркало пакетов RouterOS + «умный» прокси обновлений + политика обновлений для каждого устройства.

## 📖 Что это

Трёхуровневое решение для парка устройств MikroTik без доступа в Интернет
(или с ограниченным доступом):

1. **Зеркало** — скрипты синхронизации загружают пакеты RouterOS 6/7, Winbox
   и файлы Netinstall с `upgrade.mikrotik.com` / `download.mikrotik.com` в
   каталог, раздаваемый веб-сервером.
2. **Прокси обновлений** — PHP-обработчики отвечают на запросы RouterOS о
   доступных версиях (`NEWEST6.*`, `NEWESTa7.stable`, …), кэшируют ответы и
   держат устройства на URL пакетов зеркала.
3. **Политика обновлений** — каждое обновление фильтруется по серийному
   номеру, модели или глобально (`force_update.php` → `ENABLED`/`DISABLED`) и
   настраивается через веб-админку. Устройства сами регистрируются при первом
   обращении — без сканирования, без учёток, без требований к достижимости.

```
     Интернет: upgrade.mikrotik.com       (только во время синхронизации)
                       │
                       ▼
   Сервер-зеркало:  routeros/  +  mt-proxy/  +  SQLite/админка
                       ▲
     статический DNS:  │  запросы версий, скачивание .npk, проверка политики
   Роутеры MikroTik ───┘  download|upgrade.mikrotik.com → зеркало
```

## ✨ Возможности

- 🔄 RouterOS 6 (stable + LTS) и RouterOS 7 (stable + long-term), API до и после `7.12.1`
- 🏗 Все архитектуры: `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📦 `all_packages-*.zip` скачиваются **и распаковываются**; отдельные `.npk` на каждую версию
- ⏩ Инкрементальная синхронизация по маркерам + `force` + `download_ros.sh` для исторических версий
- 📥 Зеркало Winbox (`.zip`, `.dmg`, `.sha256`), Netinstall, ISO, `.mib`, `CHANGELOG`'и
- 🛰 Прокси запросов версий с постоянным кэшем и `X-Cache: HIT|MISS|STALE`
- 🧯 Трёхуровневая деградация: upstream → локальные маркеры → настроенные запасные значения
- 🔥 Прогрев кэша под защитой токена, по версиям прошивок зарегистрированных устройств
- 🚦 Приоритет политики: устройство → модель → глобально → legacy → встроенный allow-лист; при ошибках — `DISABLED`
- 👀 Автосоставление инвентаря: серийник, модель, имя, IP, прошивки, время последнего контакта (+ просмотр CHANGELOG)
- 🤖 Скрипты на роутерах: бэкап + обновление по расписанию, защита от циклов перезагрузок, самообновляемый установщик
- 🐳 Готовый all-in-one Docker-образ; или классическая установка на Apache/nginx без Docker

Полная документация (bare-metal установка, движок политики, детали
синхронизации, логирование, troubleshooting): [docs/](docs/).

## 🚀 Быстрый старт (Docker)

Опубликованный образ — `rajven/mikrotik-local-repo:latest` (мультиарх:
amd64 + arm64). Готовая раскладка запуска — в [`addons/docker/`](addons/docker/):

```bash
sudo mkdir -p /opt/mikrotik && cd /opt/mikrotik
# берём compose.yaml и .env.example из addons/docker/ этого репозитория
curl -o compose.yaml  https://raw.githubusercontent.com/rajven/mikrotik-local-repo/main/addons/docker/compose.yaml
curl -o .env.example  https://raw.githubusercontent.com/rajven/mikrotik-local-repo/main/addons/docker/.env.example
cp .env.example .env && chmod 600 .env
$EDITOR .env                      # SITE_URL, WARMUP_TOKEN, ADMIN_PASSWORD...
docker compose pull && docker compose up -d
docker compose logs -f            # первая синхронизация — через ~90 с
```

Проверка:

```bash
curl -i "http://localhost/routeros/NEWEST7.stable" | grep -i x-cache    # MISS, затем HIT
# админка: http://<host>/mt-proxy/  (ADMIN_USER / ADMIN_PASSWORD)
```

Направляем роутеры на зеркало (`addons/mikrotik/dns.rsc`, подставьте IP):

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Разовая установка скриптов на устройство (HTTP-бустрап; дальше скрипты
самообновляются через `BKPUPD-UPDATER`):

```routeros
/import file-name=install_updater-http.rsc    # addons/mikrotik/, SERVER_NAME подставляет контейнер
```

## ⚙️ Справочник по .env

| Переменная | Значение |
|---|---|
| `SITE_URL` | Адрес зеркала **таким, каким его видят роутеры** (`http://192.168.0.1` или `https://mirror.example.net` за TLS-прокси). При каждом старте подставляется в device-копии `.rsc` (`SERVER_NAME`, вместе со схемой), а `SERVER_IP` в `dns.rsc` получает разрешённый IPv4. Для внутренних обращений не используется — прогрев всегда ходит в `http://localhost` внутри контейнера. |
| `WARMUP_TOKEN` | Секрет эндпоинта `/routeros/ros-warmup.php`. При первом старте внедряется в `config.sh` и `mt_proxy_config.php`. Только буквы/цифры/`_ -`. |
| `ADMIN_USER` / `ADMIN_PASSWORD` | Basic Auth веб-админки (`/mt-proxy/`). Пустой пароль → случайный, один раз печатается в `docker compose logs`. Альтернатива — готовый `ADMIN_PASSWORD_HASH` (bcrypt/`$6$`). |
| `TZ` | Таймзона контейнера и PHP (отметки в логах/UI). |
| `SYNC_INTERVAL_HOURS` / `SYNC_START_DELAY` | Интервал синхронизации и задержка перед первым прогоном после старта. |
| `MIRROR_DATA_DIR` | Хост-каталог, монтируемый в `/data` (по умолчанию `./data` рядом с compose-файлом). |

Переменные применяются к генерируемым конфигам при **первом** старте свежего
`MIRROR_DATA_DIR`; дальше источник истины — файлы `/data/config/*`. После их
правки — перезапуск.

## 💾 Где лежат данные

```
$MIRROR_DATA_DIR/
├── routeros/   # зеркало пакетов + кэши версий + device-скрипты *.rsc/*.md5
├── state/      # mt_proxy.db — инвентарь и политика
└── config/     # config.sh, mt_proxy_config.php, fullchain.pem, .htpasswd
```

Резервная копия = остановить и скопировать каталог. На хосте файлы
принадлежат uid 33 (`www-data` из образа) — после bind-монтирования это
нормально.

## 🔒 Внешний HTTPS (reverse proxy)

Контейнер раздаёт обычный HTTP (так хочет RouterOS `mode=http` и так
устроена air-gapped-эксплуатация). Чтобы вывести админку и/или device-эндпоинты
по TLS, поставьте спереди reverse-proxy — готовые примеры:

- [`addons/docker/nginx/mirror.conf`](addons/docker/nginx/mirror.conf) — фрагмент для nginx
- [`addons/docker/apache/site.conf`](addons/docker/apache/site.conf) — фрагмент для Apache

Оба проксируют `/mt-proxy/` и `/routeros/` на контейнер (включите маппинг
`8080:80` в `compose.yaml`) и **обязаны сохранять `User-Agent`** (контейнер
отдаёт `.rsc`/`.txt` только User-Agent'ам RouterOS). Два момента, если
трафик устройств идёт через прокси:

- в инвентаре адресом устройства станет **адрес прокси** (PHP читает
  `REMOTE_ADDR`, доверия к `X-Forwarded-For` пока нет) — если нужна эта
  колонка, пускайте устройства напрямую на 80-й порт зеркала;
- `SITE_URL` тогда должен быть публичным HTTPS-адресом, и для проверок
  политики устройствам понадобится доверенный сертификат (`fullchain.pem`
  на ROS 6).

## 🛠 Сборка / bare-metal

- Внутренности Docker-образа (entrypoint, патчи, supervisord-раскладка):
  [`docker/README.md`](docker/README.md); собирается [`docker/Dockerfile`](docker/Dockerfile)
  с контекстом в корне репозитория.
- Классическая установка (скрипты + Apache/nginx, без Docker), движок
  политики, синхронизация и device-скрипты, логирование, troubleshooting:
  [docs/](docs/).

## 📄 Лицензия

Распространяется по MIT License. Copyright (c) 2023 Roman Dmitriev.
