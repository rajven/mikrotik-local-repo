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
| `/data/routeros` | `routeros/` | само зеркало, `*.version.cache`, winbox, `.rsc`-скрипты и `BackupAndUpdate.md5` (пересобирается на каждом старте) |
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

- При **первом** старте entrypoint генерирует `/data/config/config.sh` и
  `mt_proxy_config.php` из переменных (`SITE_URL`, `WARMUP_TOKEN`) и
  подменяет `TARGET_DIR` на `/data/routeros`. Дальше env игнорируется —
  правятся файлы в томе (это штатные файлы проекта, со всеми массивами
  версий/архитектур).
- Чтобы применить новый env к существующему тому:
  `docker compose exec mirror rm /data/config/config.sh` и `docker compose
  up -d` (или отредактировать вручную).
- Пароль админки: `ADMIN_PASSWORD` задаётся один раз при создании
  `.htpasswd`; без него генерируется случайный и печатается в лог контейнера.
  Сменить: удалить `/data/config/.htpasswd` и перезапустить.

## Отличия/дополнения к bare-metal установке

- **Крошечный патч на этапе сборки**: в `db.php` путь к SQLite
  читается из env (`MT_PROXY_DB_PATH`), чтобы БД и WAL попадали в том.
  Больше код репозитория не меняется (см. `Dockerfile`).
- `BackupAndUpdate.md5` генерируется автоматически на каждом старте
  контейнера (в bare-metal это по-прежнему ручная команда).
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
# прогрев кэша вручную
docker compose exec mirror sh -c '. /data/config/config.sh; wget -qO- "$SITE_URL/routeros/ros-warmup.php?token=${WARMUP_TOKEN}"'
# состояние
docker compose exec mirror sh -c 'supervisorctl -s unix:///run/supervisor.sock status || true'
```

## Ограничения контейнерной версии

- **Права на томе**: entrypoint отдаёт `/data/*` пользователю `www-data` только
  для корневых каталогов (рекурсивный chown десятков гигабайт на старте —
  зло). При восстановлении из бэкапа на bind-монтировании после переноса:
  `docker compose exec mirror chown -R www-data:www-data /data`.
- **Спецсимволы**: `WARMUP_TOKEN` попадает в `sed`-подстановку — используйте
  буквы/цифры/`(  _ - )` без `|` и `&`.
- Обновление образа: `docker compose up -d --build` после
  `git pull`; конфиги в томе останутся вашими. Если репозиторий поменял
  `.rsc`-скрипты — они перетирут копию в зеркале (`install -C`) и md5 будет
  пересобрана.
