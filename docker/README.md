# mikrotik-local-repo в Docker

All-in-one-контейнер: lighttpd (эндпоинты устройств + веб-админка), PHP-FPM,
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
├── bin/mt-auth-backend.sh  выбор auth-бэкенда lighttpd: htpasswd / LDAP
└── conf/
    ├── lighttpd-mirror.conf  vhost: NEWEST*/force_update/warmup/админка/защита
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
  Сменить: удалить `/data/config/.htpasswd` и перезапустить. Вместо файла
  бэкендом может быть каталог LDAP — см. следующий раздел.

## LDAP-авторизация админки (опционально)

Базовый режим — Basic Auth по файлу `/data/config/.htpasswd`. Если в сети
есть каталог (Active Directory, OpenLDAP, FreeIPA), админку можно
переключить на него переменными окружения — правка конфигов и пересборка
образа не нужны, всё включается в `.env`:

```
MT_LDAP_AUTH=1
MT_LDAP_URL=ldaps://dc01.corp.example.com:636
MT_LDAP_BASE_DN=DC=corp,DC=example,DC=com
MT_LDAP_BIND_DN=CN=svc-mikrotik,OU=service-accounts,DC=corp,DC=example,DC=com
MT_LDAP_BIND_PASSWORD=svc-account-password
MT_LDAP_FILTER=(&(sAMAccountName=?)(memberOf=CN=mikrotik-admins,OU=groups,DC=corp,DC=example,DC=com))
```

Как это работает: lighttpd в образе несёт `mod_authn_ldap` (пакет
`lighttpd-modules-ldap`), а конфиг берёт auth-бэкенд из скрипта
`bin/mt-auth-backend.sh` через `include_shell`. При `MT_LDAP_AUTH=1` скрипт
печатает LDAP-блок (`auth.backend = "ldap"`, hostname/base-dn/bind-dn/
bind-pw/filter), при 0 — прежний htpasswd; сами правила `auth.require` (только
`/mt-proxy`, оба варианта пути) не меняются. Ошибки конфигурации
(не задан `MT_LDAP_URL`/`MT_LDAP_BASE_DN`, схема не `ldap(s)://`, пароль без
bind-dn, фильтр без `?`, непечатаемые символы в значениях) роняют
`lighttpd -tt` на старте контейнера с явным сообщением — контейнер не
стартует молча с бракованным конфигом.

Семантика переменных:

| Переменная | Смысл | По умолчанию |
|---|---|---|
| `MT_LDAP_AUTH` | `1` — LDAP-бэкенд, `0`/не задана — htpasswd | `0` |
| `MT_LDAP_URL` | `ldap://host:389` или `ldaps://host:636` | — (обязательна при LDAP) |
| `MT_LDAP_BASE_DN` | база поиска пользователей | — (обязательна при LDAP) |
| `MT_LDAP_BIND_DN` | DN сервисной учётки для поиска; пусто — anonymous bind | пусто |
| `MT_LDAP_BIND_PASSWORD` | пароль сервисной учётки (только с `BIND_DN`) | пусто |
| `MT_LDAP_FILTER` | фильтр поиска, `?` = логин (lighttpd экранирует LDAP-спецсимволы); AD: `(&(sAMAccountName=?)(memberOf=CN=…))`, OpenLDAP: `(uid=?)` | `(uid=?)` |
| `MT_LDAP_STARTTLS` | `1` — `auth.backend.ldap.starttls = "enable"` для `ldap://` | `0` |
| `MT_LDAP_CA_CERT` | путь к CA-сертификату **внутри контейнера** для самоподписанного ldaps/STARTTLS (файл монтируется, например, в `/data/config/ldap-ca.pem`); уходит и в `auth.backend.ldap.ca-file` (lighttpd), и в `TLS_CACERT` `/etc/ldap/ldap.conf` (libldap/php-ldap) | пусто |
| `MT_LDAP_TLS_REQCERT` | проверка серверного сертификата каталога в `/etc/ldap/ldap.conf`: `never`/`allow`/`try`/`demand`/`hard`; `never` — типовой вариант для контроллера домена с самоподписанным сертом | пусто (дефолт libldap — `demand`) |

### `/etc/ldap/ldap.conf` (libldap)

TLS-поведение каталога на стороне libldap управляется системным
`/etc/ldap/ldap.conf`: у `mod_authn_ldap` нет своей директивы для
`TLS_REQCERT`, а `php-ldap` читает тот же файл. Entrypoint управляет им на
**каждом** старте:

- `/data/config/ldap.conf` существует → ставится как `/etc/ldap/ldap.conf`
  как есть (полный ручной контроль: `TLS_REQCERT`, `TLS_CACERT`, `BASE`,
  `URI`, …; файл на томе — переживает рестарты и обновления образа);
- иначе генерируется из env: `MT_LDAP_TLS_REQCERT` → строка `TLS_REQCERT`,
  `MT_LDAP_CA_CERT` → строка `TLS_CACERT` (остальное — закомментированные
  дефолты Debian). Заголовок файла напоминает, как его перехватить вручную.

Типовой сценарий — контроллер домена с самоподписанным сертификатом, когда
свой CA некуда положить:

```
MT_LDAP_TLS_REQCERT=never
```

Штатные значения: `never` (без проверки), `allow` (проверять, но при ошибке
продолжить), `try`/`demand`/`hard` (проверять; отличаются поведением без
сертификата сервера). `never` отключает защиту от MITM на пути к каталогу —
entrypoint печатает об этом WARNING в лог; для продакшена предпочтительнее
`MT_LDAP_CA_CERT` со своим CA и дефолтная проверка. Недопустимое значение
`MT_LDAP_TLS_REQCERT` останавливает старт контейнера с явной ошибкой.

Смена бэкенда применяется на рестарте контейнера: `docker compose up -d`
после правки `.env`. Пароль сервисной учётки передаётся через env
(как и `ADMIN_PASSWORD`) — в лог он не печатается; файл `.htpasswd` при
включённом LDAP продолжит создаваться и остаётся рабочим фолбэком, если
переменные убрать. Пустой пароль при бинде lighttpd отвергает
принудительно (`allow-empty-pw = "disable"`); группа-членство фильтром
`memberOf` — штатный способ дать доступ только нужной группе; поиск идёт
под сервисной учёткой, а не под логином пользователя. Недоступный каталог
не даёт ни обхода авторизации, ни падения веб-сервера: lighttpd закрывает
запрос (fail-closed; в логе `ldap_sasl_bind_s(): Can't contact LDAP server`).
`php-ldap` в образе установлен на будущее (если авторизация LDAP
понадобится и в коде панели), сейчас LDAP использует lighttpd.

Проверка на живом каталоге: открыть `/mt-proxy/` и войти доменным логином
из группы; в логе контейнера при старте появится строка
`Admin UI auth backend: LDAP (...)`. Если каталог недоступен — lighttpd
вернёт 401 на Basic Auth (fail-closed), а в логе будет ошибка ldap;
проверьте досягаемость `MT_LDAP_URL` из контейнера и CA-сертификат. При
ошибках TLS-хендшейка (самоподписанный серт контроллера) в логе будет
`TLS: certificate verify failed` — либо задайте `MT_LDAP_CA_CERT`, либо,
если CA недоступен, `MT_LDAP_TLS_REQCERT=never`.

## Отличия/дополнения к bare-metal установке

- **Два патча на этапе сборки** (см. `Dockerfile`): путь SQLite из env
  (`MT_PROXY_DB_PATH`) и строка `WARMUP_URL="${SITE_URL}/..."` →
  `WARMUP_URL="http://localhost/..."`, то есть self-call вместо `SITE_URL`
  (это адрес для устройств, поверх него может стоять реверс-прокси). Сам
  вызов прогрева уже передаёт wget `-O /dev/null`: без него wget сохранял
  HTML-отчёт в файл `ros-warmup.php?token=...` внутри зеркала.
  Остальное — код репозитория как есть.
- **`.rsc` для устройств приготавливаются при старте контейнера**: подстановка
  `SITE_URL`/`SERVER_IP` (см. раздел «Конфигурация») и `.md5` рядом с
  **каждым** `.rsc` в зеркале (`BackupAndUpdate.md5` проверяет updater на
  устройствах, остальные — заодно).
- cron заменён на цикл с интервалом `SYNC_INTERVAL_HOURS` (по умолчанию 3 ч,
  первый прогон через `SYNC_START_DELAY` секунд).
- Логи скриптов (`logger`) перекладываются в stdout контейнера
  (`busybox syslogd -O /dev/stdout`), PHP — тоже в stderr/stdout.
  Логи самого lighttpd (errorlog и accesslog) идут через тот же syslog
  (`server.errorlog-use-syslog` / `accesslog.use-syslog`), поэтому в
  `docker logs` они с syslog-префиксом `<29>Nov 19 … lighttpd[…]: …`.
  Это осознанно: lighttpd открывает лог-файлы уже ПОСЛЕ сброса привилегий
  до `www-data`, а повторное открытие `/dev/stderr` (файл, который держит
  supervisord) без прав роняло сервер в рестарт-цикл
  (`opening errorlog '/dev/stderr' failed: Permission denied`). Сокет
  `/dev/log` открывается один раз и переживает сброс; доступ `/healthz`
  в accesslog по-прежнему не пишется.
- supervisord сам остаётся root (`user = root` в `[supervisord]` — lighttpd
  биндит :80 и сбрасывает привилегии самостоятельно, это штатный режим, а не
  недосмотр), а его XML-RPC-сокет (`supervisorctl`) защищён парой
  логин/пароль, которую entrypoint генерирует случайно на каждый старт и
  вписывает в рендеренный `/etc/supervisor/supervisord.conf` — секрет не
  запечён в образ; `supervisorctl status/restart …` работает без изменений,
  так как читает тот же файл.
- Синхронизация защищена общим локом (`SYNC_LOCK_FILE`): накладывающиеся
  прогоны cron'а, контейнерного цикла и ручного `download_ros.sh` не
  дерутся за маркеры и распаковку. Повторный прогон, пока идёт первый,
  завершается с сообщением `Another synchronisation is already running`.
- Веб-сервер один (lighttpd+FPM), автоопределение FPM/mod_php не нужно.

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
