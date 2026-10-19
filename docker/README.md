# mikrotik-local-repo в Docker

All-in-one-контейнер: nginx (эндпоинты устройств + веб-админка), PHP-FPM,
bash-скрипты синхронизации, syslog-в-stdout и цикл синхронизации вместо cron.
Код живёт в образе, всё состояние — в томе `/data`.

```
docker/
├── Dockerfile
├── compose.yaml
├── .env.example
├── README.md               ← этот файл
├── bin/entrypoint.sh       генерация конфигов, сиды, симлинки, запуск
├── bin/sync-loop.sh        периодический sync_mikrotik_repo.sh
└── conf/
    ├── nginx-mirror.conf   vhost: NEWEST*/force_update/warmup/админка/защита
    ├── mt-fastcgi.conf     fastcgi-сниппет для device-эндпоинтов
    ├── php-fpm-container.conf
    └── supervisord.conf.in
```

## Быстрый старт

Каталог `docker/` кладётся в корень клонированного репозитория
(контекст сборки — сам репозиторий):

```
git clone https://github.com/rajven/mikrotik-local-repo.git
cd mikrotik-local-repo/docker
cp .env.example .env                      # заполнить WARMUP_TOKEN, ADMIN_*
docker compose up -d --build
docker compose logs -f                    # первый sync начнётся через ~90 c
```

Проверка:

```
curl -i http://localhost/routeros/NEWEST7.stable      # X-Cache: MISS → HIT
curl "http://localhost/routeros/force_update.php?new_version=7.24.5&serial=TEST&model=RB5009"
# админка: http://localhost/mt-proxy/  (admin / ADMIN_PASSWORD)
```

Далее устройства направляются на хост-зеркало как и раньше — статическими
DNS-записями `download.mikrotik.com` / `upgrade.mikrotik.com` → IP этого
хоста (для NAT-сомнительных случаем есть `network_mode: "host"` в compose).

## Что где живёт (bind-директория на хосте → `/data`)

Каталог задаётся в `.env` (или прямо в `compose.yaml`) переменной
`MIRROR_DATA_DIR` и монтируется в контейнер как `/data`:

```yaml
# compose.yaml (фрагмент)
    volumes:
      - ${MIRROR_DATA_DIR:-./data}:/data
# или захардкодить:      - /srv/mikrotik-mirror:/data
```

Относительный путь (`./data`) разрешается от каталога с compose-файлом, т.е.
`mikrotik-local-repo/docker/data`; для продакшена лучше абсолютный —
`MIRROR_DATA_DIR=/srv/mikrotik-mirror`.

| Путь в контейнере | (= `<MIRROR_DATA_DIR>/…`) | Содержимое |
|---|---|---|
| `/data/routeros` | `routeros/` | само зеркало, `*.version.cache`, winbox, `.rsc`-скрипты (с подставленным `SITE_URL`) и `.md5` для каждого из них (пересобирается на каждом старте) |
| `/data/state` | `state/` | `mt_proxy.db` (+WAL) — вся политика и инвентарь |
| `/data/config` | `config/` | `config.sh`, `mt_proxy_config.php`, `fullchain.pem`, `.htpasswd` |

Права: каталоги создаёт entrypoint от root и отдаёт `www-data` (uid **33**);
на хосте владелец будет `33:33` — это нормально, не «сломано».
Перед переносом на другой хост: `chown -R 33:33 <каталог>`.

**Резервная копия = копия каталога.** Остановить, стянуть, залить на новом
хосте, поменять `MIRROR_DATA_DIR`, запустить:

```
docker compose stop
cp -a /srv/mikrotik-mirror /backup/mikrotik-mirror.$(date +%F)   # или rsync -a
```

Для live-бекапа БД без остановки тома: `sqlite3 <каталог>/state/mt_proxy.db
".backup /backup/mt_proxy.$(date +%F).db"`, остальное (зеркало) — просто
файлы.

Возврат к именованному тому: в `compose.yaml` закомментировать bind-строку и
раскомментировать `- mirror-data:/data` (блок `volumes:` снизу уже есть).

## Конфигурация: приоритет env vs файлы

- `SITE_URL` — адрес зеркала **для устройств** (их статический DNS указывает
  на него). При каждом старте в `.rsc`-копиях зеркала:
  `http(s)://SERVER_NAME` → **весь `SITE_URL` с его схемой** (т.е. устройство
  всегда идёт ровно туда, куда настроено, даже в `install_updater.rsc` с
  https-вариантом), одиночный `SERVER_NAME` → host[:port], а `SERVER_IP` в
  `dns.rsc` → IPv4 из resolve (безуспешность — только warning, плейсхолдер
  остаётся; `ping` в образе нет, используется `getent`). Внутренний прогрев
  кэша контейнер всегда делает в себя: `http://localhost`.
- При **первом** старте entrypoint генерирует `/data/config/config.sh` и
  `mt_proxy_config.php` из `WARMUP_TOKEN` и подменяет `TARGET_DIR` на
  `/data/routeros`. Дальше env игнорируется — правятся файлы в томе (это
  штатные файлы проекта, со всеми массивами версий/архитектур).
- Чтобы применить новый env к существующему тому:
  `docker compose exec mirror rm /data/config/config.sh` и `docker compose
  up -d` (или отредактировать вручную).
- Пароль админки: `ADMIN_PASSWORD` задаётся один раз при создании
  `.htpasswd`; без него генерируется случайный и печатается в лог контейнера.
  Сменить: удалить `/data/config/.htpasswd` и перезапустить.

## Отличия/дополнения к bare-metal установке

- **Два патча на этапе сборки** (см. `Dockerfile`): путь SQLite из env
  (`MT_PROXY_DB_PATH`) и строка прогрева в `sync_mikrotik_repo.sh` →
  `wget -q -O /dev/null "http://localhost/..."` — без неё wget молча
  сохранял ответ в файл `ros-warmup.php?token=...` в текущий каталог
  (т.е. в зеркало), и вместо self-call использовал `SITE_URL`.
  Остальное — код репозитория как есть.
- **`.rsc` для устройств приготавливаются при старте контейнера**: подстановка
  `SITE_URL`/`SERVER_IP` (см. раздел «Конфигурация») и `.md5` рядом с
  **каждым** `.rsc` в зеркале (`BackupAndUpdate.md5` проверяет updater на
  устройствах, остальные — заодно).
- cron заменён на цикл с интервалом `SYNC_INTERVAL_HOURS` (по умолчанию 3 ч,
  первый прогон через `SYNC_START_DELAY` секунд).
- Логи скриптов (`logger`) перекладываются в stdout контейнера
  (`busybox syslogd -O /dev/stdout`), PHP — тоже в stderr/stdout.
- Веб-сервер один (nginx+FPM), автоопределение FPM/mod_php не нужно.

## Полезные команды

```
# одномоментный принудительный sync
docker compose exec -u www-data mirror /usr/local/bin/sync_mikrotik_repo.sh force
# закачать конкретную старую версию
docker compose exec -u www-data mirror /usr/local/bin/download_ros.sh 6.49.17
# прогрев кэша вручную (изнутри контейнера)
docker compose exec mirror sh -c '. /usr/local/bin/config.sh; wget -qO- "http://localhost/routeros/ros-warmup.php?token=${WARMUP_TOKEN}"'
# состояние
docker compose exec mirror sh -c 'supervisorctl -s unix:///run/supervisor.sock status || true'
```

## Ограничения контейнерной версии

- **Пра на томе**: entrypoint отдаёт `/data/*` пользователю `www-data` только
  для корневых каталогов (рекурсивный chown десятков гигабайт на старте —
  зло). При восстановлении из бэкапа на bind-монтировании после переноса:
  `docker compose exec mirror chown -R www-data:www-data /data`.
- **Спецсимволы**: `WARMUP_TOKEN` попадает в `sed`-подстановку — используйте
  буквы/цифры/`(  _ - )` без `|` и `&`.
- **Нет TLS**: устройства ходят по HTTP (и `mode=http` на ROS 7) — как и в
  базовом сценарии README. HTTPS — отдельный слой (reverse-proxy или
  `certbot` в контейнер позже).
- Порты: наружу торчит только 80; админка и device-эндпоинты не разделены по
  хостам — защита как в README (Basic Auth + UA-гейт + token).
- Обновление образа: `docker compose up -d --build` после
  `git pull`; конфиги в томе останутся вашими. Если репозиторий поменял
  `.rsc`-скрипты — они перетирут копию в зеркале (`install -C`), подстановка
  хоста и все md5 будут пересобраны.
- **Смена `SITE_URL` применяется на рестарте**: в образе `.rsc` лежат с
  плейсхолдером, поэтому каждый старт переустанавливает копии в зеркало
  (`install -C`) и подставляет текущий `SITE_URL`; md5 пересобираются
  автоматически. Достаточно `docker compose up -d` после правки `.env`.
  Обратная сторона: **ручные правки в `/data/routeros/*.rsc` не сохраняются**
  — кастомизацию скриптов делайте в репозитории/источнике образа.
  `dns.rsc`: `SERVER_IP` подставляется только если `SITE_URL` резолвится в
  адрес (хост в статическом DNS MikroTik не работает, нужен именно IP).
- Для very больших парков: `pm.max_children`, буферы — тюнинг на месте;
  сам проект намеренно одномашинный.
