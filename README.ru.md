# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Автономное зеркало пакетов RouterOS + умный прокси обновлений + политика обновлений для каждого устройства.

## Содержание

- [О проекте](#-о-проекте) · [Возможности](#-возможности) · [Как это работает](#-как-это-работает) · [Структура проекта](#-структура-проекта)
- [Требования](#-требования) · [Установка](#-установка) · [Настройка](#-настройка) · [Синхронизация](#-синхронизация)
- [Прокси запросов версий](#-прокси-запросов-версий) · [Политика обновлений](#-политика-обновлений) · [Веб-админка](#-веб-админка)
- [Настройка устройств](#-настройка-устройств) · [Журналирование](#-журналирование) · [Диагностика](#-диагностика)
- [Замечания по безопасности](#-замечания-по-безопасности) · [Известные ограничения](#-известные-ограничения)

---

## 📖 О проекте

Автономное трёхуровневое решение для парка устройств MikroTik без доступа в Интернет (или с ограниченным доступом):

1. **Зеркало** — bash-скрипты синхронизации загружают пакеты RouterOS 6 и RouterOS 7, Winbox и вспомогательные файлы Netinstall из официальных репозиториев (`upgrade.mikrotik.com` / `download.mikrotik.com`) в каталог веб-сервера.
2. **Прокси обновлений** — PHP-обработчики перехватывают запросы RouterOS о доступных версиях (`NEWEST6.*`, `NEWESTa7.stable` и т. п.), кэшируют ответы и отдают сами файлы пакетов с этого же хоста.
3. **Политика обновлений** — каждое планируемое обновление проверяется по серийному номеру, модели устройства или глобально, а правила настраиваются через веб-интерфейс. Роутер, которыму явно не указаны разрешённые версии, обновляется до версии по умолчанию которую задал администратор.

Устройства направляют на зеркало статическими DNS-записями, поэтому RouterOS «думает», что разговаривает с MikroTik:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

## ✨ Возможности

**Зеркало**
- 🔄 RouterOS 6 (stable + LTS/`6fix`) и RouterOS 7 (stable + long-term)
- 🏗 Все поддерживаемые архитектуры: `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📦 Архивы `all_packages-*.zip` скачиваются **и распаковываются**, поэтому отдельные `.npk` доступны для ручного обновления
- 📥 Winbox всех опубликованных версий (`.zip`, `.dmg`, `.sha256`) в отдельное дерево `winbox/`
- 📄 Дополнительные файлы: `CHANGELOG`, `packages.csv`, Netinstall, ISO-образ, `.mib`, `btest.exe`, `flashfig.exe`
- ⏩ Неизменившиеся версии пропускаются — качаются только новые/обновлённые релизы; `force` перекачивает всё
- 🎯 `download_ros.sh` выгружает одну конкретную (в том числе старую) версию

**Прокси обновлений**
- 🛰 Проксирует и кэширует ответы `NEWEST6/NEWESTa6/NEWEST7/NEWESTa7` в вариантах `.stable`, `.long-term`, `.upgrade`; 
- 🔥 `ros-warmup.pl` прогревает кэш версий после каждой синхронизации, чтобы первый запрос устройства не ушёл в Интернет
- 🔀 Работа на Apache (FPM **или** mod_php, автоопределение) и Nginx; готовые конфиги в `addons/`

**Политика обновлений**
- 🚦 `force_update.php` возвращает `ENABLED` / `DISABLED` на запрашиваемую версию
- 🗂 Правила по серийному номеру, по модели (`model:RB4011`) или глобальные — с определённым приоритетом
- 👀 Устройства регистрируются автоматически при первом запросе: serial, модель, IP, текущая и устанавливаемая прошивка, время последнего визита
- 🖥 Веб-админка (Basic Auth + SQLite) с поиском, массовым редактированием и глобальным списком версий
- 🤖 Скрипты для самих роутеров: резервное копирование по расписанию (`.backup` + `/export`), обновление RouterOS и прошивки RouterBOARD, защита от цикла перезагрузок, самообновляемый установщик

## 🧭 Как это работает

```text
      Интернет: upgrade.mikrotik.com / download.mikrotik.com
                 │
                 │  только во время синхронизации: wget + curl + unzip
                 ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  Сервер-зеркало  (/var/www/html)                             │
  │                                                              │
  │  routeros/               пакеты, .npk, winbox, changelog     │
  │  routeros/*.version.cache  кэш ответов прокси-слоя           │
  │  mt-proxy/               PHP-обработчики + SQLite + админка  │
  └──────────────────────────────▲───────────────────────────────┘
                                 │  запросы версий, загрузка пакетов,
                                 │  проверка политики (ENABLED / DISABLED)
                    Роутер MikroTik (без доступа в Интернет)
                    статический DNS: download|upgrade.mikrotik.com → зеркало
                    цикл обновления запускает BackupAndUpdate.rsc
```

Цикл обновления устройства:

1. Устройство спрашивает `upgrade.mikrotik.com/routeros/NEWEST7.stable` — PHP-прокси отвечает из кэша, с upstream или из резерва.
2. Запрос `NEWESTa*` / `NEWEST6.*` с параметром `?version=X` обрабатывается так же: так RouterOS узнаёт о релизах ROS 7 ≥ 7.12.1 и о переходе с ROS 6 на ROS 7.
3. Файлы `.npk` / `all_packages` устройство качает с `/routeros/<version>/` этого же хоста.
4. Плановый скрипт `BackupAndUpdate` сообщает на `/routeros/force_update.php` серийный номер, модель и целевую версию.
5. Если сервер ответил `ENABLED`, скрипт делает резервную копию и ставит обновление; при `DISABLED` прерывается, но состояние устройства в инвентарь попадает.

## 📁 Структура проекта

```text
mikrotik-local-repo/
├── scripts/
│   ├── sync_mikrotik_repo.sh   # основной синхронизатор (цель для cron)
│   ├── download_ros.sh         # загрузка одной конкретной версии RouterOS
│   ├── config.sh               # пути, версии, архитектуры, схема URL
│   ├── functions.sh            # журналирование, доп. файлы, Winbox
│   ├── ros6_functions.sh       # логика загрузки RouterOS 6
│   ├── ros7_functions.sh       # логика загрузки RouterOS 7 (до/после 7.12.1)
│   └── ros-warmup.pl           # прогрев кэша версий прокси
├── html/
│   ├── mt-proxy/
│   │   ├── index.php           # веб-админка (устройства, правила, глобальные версии)
│   │   ├── db.php              # схема SQLite + логика принятия решений
│   │   ├── ros6-upgrade.php    # прокси NEWEST6.* / NEWESTa6.*
│   │   ├── ros7-upgrade.php    # прокси NEWEST7.* / NEWESTa7.*
│   │   ├── force_update.php    # гейт ENABLED/DISABLED
│   │   └── mt_proxy_config.php # upstream, таймауты, резервные версии
│   ├── routeros/               # стартовые *.version.cache для каталога зеркала
│   └── fullchain.pem           # CA-цепочка для HTTPS-проверк на устройствах
├── addons/
│   ├── apache/                 # vhost 00-mirror.conf + автоопределение FPM/mod_php
│   ├── nginx/                  # site.conf + сниппет mt-fastcgi.conf
│   ├── cron.d/                 # sync_ROS_repo — синхронизация по расписанию
│   └── mikrotik/               # скрипты для роутеров (.txt — исходник / .rsc — установщик)
├── CHANGELOG
└── LICENSE                     # MIT
```

## 📋 Требования

Debian / Ubuntu и пакеты:

| Компонент | Где используется |
|---|---|
| `bash`, `wget`, `curl`, `unzip`, `coreutils` | скрипты синхронизации |
| `perl` + `libwww-perl`, `liburi-perl` | `ros-warmup.pl` |
| `php-cli`, `php-curl`, `php-sqlite3` | прокси, политика, веб-админка |
| `apache2` **или** `nginx` + `php-fpm` | отдача зеркала и админки |
| `mod_rewrite`, `mod_headers`, `mod_proxy_fcgi` (Apache) | маршрутизация `/routeros/*` в FPM |

## 🚀 Установка

Во всех примерах используется стандартная раскладка Debian: скрипты в `/usr/local/bin`, корень веб-сервера `/var/www/html`, зеркало в `/var/www/html/routeros`.

### 1. Установка пакетов

**Apache**

```bash
apt install git bash wget curl unzip php php-curl php-sqlite3 \
            libwww-perl liburi-perl apache2 -y
a2enmod rewrite headers proxy_fcgi setenvif
a2enconf php8.3-fpm        # укажите свою версию PHP
```

**Nginx**

```bash
apt install git bash wget curl unzip php php-curl php-sqlite3 php-fpm \
            libwww-perl liburi-perl nginx -y
```

> В пуле PHP-FPM задайте `clear_env = no`, если собираетесь переопределять параметры через переменные окружения.

### 2. Кладём скрипты синхронизации

```bash
git clone https://github.com/rajven/mikrotik-local-repo.git
cd mikrotik-local-repo

cp scripts/*.sh scripts/ros-warmup.pl /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh \
         /usr/local/bin/download_ros.sh \
         /usr/local/bin/ros-warmup.pl
```

> ⚠️ `sync_mikrotik_repo.sh` жёстко прописал `SCRIPT_DIR="/usr/local/bin"` для `source` и вызывает `/usr/local/bin/ros-warmup.pl` по абсолютному пути. При переносе в другое место правьте обе строки. `download_ros.sh` использует `dirname "$0"` и работает из любого каталога — при условии, что весь набор скриптов лежит рядом.

### 3. Кладём веб-слой

```bash
mkdir -p /var/www/html/routeros
cp -r html/mt-proxy             /var/www/html/
cp    html/routeros/*.cache     /var/www/html/routeros/
cp    html/fullchain.pem        /var/www/html/
cp    addons/mikrotik/*.rsc     /var/www/html/routeros/   # скрипты для устройств
chown www-data:www-data -R /var/www/html
```

Скрипты для роутеров лежат в двух видах: `*.txt` — читаемый исходник, `*.rsc` — тот же скрипт, завёрнутый в `/system script add`, готовый к импорту. Наружу достаточно отдать только `.rsc`.

`fullchain.pem` — цепочка сертификатов, которую `BackupAndUpdate` импортирует в хранилище сертификатов RouterOS 6 перед HTTPS-проверкой политики. Положите туда CA-цепочку собственного сервера или используйте пример только на время тестов. Используется только, если вы работаете с сервером политики по https с оборудования на ROS6. Для ROS7 - не нужен. Если сервер политики обновлений работает по http - не нужен.

### 4. Настраиваем веб-сервер

**Apache**

```bash
cp addons/apache/conf-available/php-autodetect.conf /etc/apache2/conf-available/
cp addons/apache/sites-available/00-mirror.conf     /etc/apache2/sites-available/
a2enconf php-autodetect
a2ensite 00-mirror
a2dissite 000-default

htpasswd -c /etc/apache2/.htpasswd admin     # пароль для веб-админки
systemctl reload apache2
```

`php-autodetect.conf` выбирает `PHP_MODE_FPM`, если найдены сокет PHP-FPM и `mod_proxy_fcgi`, иначе `PHP_MODE_MODPHP`. В vhost есть маршрутизация для обоих режимов.

**Nginx**

```bash
cp addons/nginx/snippets/mt-fastcgi.conf /etc/nginx/snippets/
cp addons/nginx/site.conf               /etc/nginx/sites-available/mirror
ln -sf /etc/nginx/sites-available/mirror /etc/nginx/sites-enabled/mirror

htpasswd -c /etc/nginx/.htpasswd admin   # пароль для веб-админки
nginx -t && systemctl reload nginx
```

> 📝 В обоих конфигах захардкожены `server_name download.mikrotik.com upgrade.mikrotik.com` (в Apache закомментировано) и пути внутри `/var/www/html`. Приведите `ServerName` / `server_name`, путь к сокету FPM и корень документа к своей схеме.

Каталог `/routeros` **обязательно** должен находиться в корне сайта: устройства запрашивают `/routeros/7.24.5/routeros-7.24.5-arm64.npk`, а точки прокси матчатся как `/routeros/NEWEST…`. Отдача зеркала из подкаталога ломает и то и другое.

### 5. Синхронизация по расписанию

```bash
cp addons/cron.d/sync_ROS_repo /etc/cron.d/
chmod 644 /etc/cron.d/sync_ROS_repo
```

```cron
1 */3 * * * root /usr/local/bin/sync_mikrotik_repo.sh 2>/dev/null && chown www-data:www-data -R /var/www/html
```

Запуск каждые 3 часа от root с передачей свежих файлов пользователю веб-сервера.

### 6. Первый запуск

```bash
mkdir -p /var/www/html/routeros
/usr/local/bin/sync_mikrotik_repo.sh force
chown www-data:www-data -R /var/www/html
```

Проверяем, что прокси-слой отвечает локально:

```bash
curl -i "http://localhost/routeros/NEWEST7.stable"          # сначала X-Cache: MISS, затем HIT
curl  "http://localhost/routeros/force_update.php?new_version=7.24.5&serial=TEST&model=RB5009"
```

Второй запрос зарегистрирует в базе устройство с serial `TEST`. В свежей установке глобальный список пуст, поэтому решает уровень 5 (жёстко заданный список): `7.24.5` получит `ENABLED`, а неперечисленная версия — `DISABLED`. Чтобы забрать управление у хардкода, добавьте свои версии в **Global versions** в веб-админке.

## ⚙️ Настройка

### Скрипты синхронизации — `scripts/config.sh`

```bash
TARGET_DIR="/var/www/html/routeros"   # корень зеркала, отдаётся веб-сервером
SITE_URL="http://localhost"           # собственный базовый URL, нужен для ros-warmup.pl
WGET="/bin/wget"                      # путь к wget; иначе поиск в $PATH
LOG_OFF=0                             # 1 — полностью заглушить syslog
URL_SCHEMA="http"                     # http|https для upgrade.mikrotik.com; невалидное значение → http

versions6=("6" "6fix")                # каналы ROS 6: stable и LTS
versions7=("stable" "long-term")      # каналы ROS 7
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")

additional_files=( ...)               # Netinstall, ISO, служебные файлы, .mib, ...
WINBOX_DIR="${TARGET_DIR}/winbox"     # Winbox всегда качается по https
```

Уберите из `firmware_arch` неиспользуемые архитектуры — это самый большой выигрыш по времени и месту на диске.

### Прокси и политика — `html/mt-proxy/mt_proxy_config.php`

Файл возвращает массив конфигурации:

| Ключ | Назначение |
|---|---|
| `upstream_base` | Префикс официального репозитория (`https://upgrade.mikrotik.com/routeros/`) |
| `connect_timeout`, `total_timeout` | Таймауты обращения к upstream в секундах (2 / 3) |
| `routeros_dir` | Каталог зеркала, вычисляется из `DOCUMENT_ROOT` |
| `allowed_versions_hardcoded` | Список-последний рубеж (`6.49.23`, `7.24.5`, `7.23.8`) |
| `fallbacks` | Ответы по каждой точке, когда недоступны и upstream, и локальные маркеры |
| `v6` / `v7` | Префикс лога, файл кэша, версия по умолчанию, префикс `User-Agent`, локальные файлы-маркеры |

Именно `mt_proxy_config.php` стоит править, когда MikroTik выпускает новые релизы и вы хотите другие безопасные резервные значения. Файл правил по моделям `mt_proxy_rules.php` больше не поставляется, но `db.php` по-прежнему читает его один раз, чтобы мигрировать старые установки в SQLite.

## 🔄 Синхронизация

```bash
/usr/local/bin/sync_mikrotik_repo.sh          # только новые/изменённые версии
/usr/local/bin/sync_mikrotik_repo.sh force    # игнорировать маркеры и перекачать всё заново
/usr/local/bin/download_ros.sh 7.20.3         # одна конкретная версия в routeros/7.20.3/
/usr/local/bin/download_ros.sh 6.49.23        # ... работает и со старыми релизами
```

Аргумент версии можно передать и вторым параметром (`download_ros.sh force 7.20.3`) — на поведение это не влияет: уже скачанные файлы останутся на месте, потому что `wget` работает с `-nc`.

Что происходит за прогон:

1. Скрипт сравнивает локальные маркеры `LATEST.6` / `LATEST.6fix` и `NEWEST7.stable` / `NEWESTa7.*` с данными upstream.
2. Для каждой изменившейся версии качаются `CHANGELOG`, `packages.csv` (ROS 7), `all_packages-<arch>-<version>.zip` с последующей распаковкой, а также образы `routeros*.npk` и `wireless-*.npk` для не-x86 в ROS 7 ≥ 7.12.1.
3. Маркеры перезаписываются только после успешной загрузки, поэтому прерванный прогон повторится в следующий раз.
4. Все опубликованные сборки Winbox раскладываются по `routeros/winbox/<version>/`.
5. Кэш версий прогревается запросами к локальным точкам прокси.

Канал ROS 7 сознательно грузится дважды: `download_ros7 7.10` покрывает релизы до 7.12.1, а `download_ros7 7.12.1 a` — API `NEWESTa7.*`, появившееся в 7.12.1; они требуют разного `User-Agent` (`RouterOS <version>`).

### Прогрев кэша

В конце `sync_mikrotik_repo.sh` дважды вызывает `ros-warmup.pl`, подставляя `WARMUP_CACHE_FILE` (`ros6.version.cache` и `ros7.version.cache`) и `WARMUP_BASE` из `SITE_URL`. Скрипт читает кэш по HTTP, выбирает для каждой точки `WARMUP_KEEP` (по умолчанию 3) последних запрашиваемых версий и прогоняет каждую через локальный прокси. Уже существующие ключи вернутся из кэша; наполняются как раз те ещё не закэшированные комбинации «точка + версия», которые устройства начнут запрашивать после выхода релиза, заодно громко в syslog проверяется корректность маршрутизации PHP. Запустите вручную после смены `SITE_URL` или очистки кэша:

```bash
WARMUP_BASE=http://mirror.example.lan WARMUP_CACHE_FILE=ros7.version.cache \
WARMUP_KEEP=5 WARMUP_VERBOSE=1 /usr/local/bin/ros-warmup.pl
```

Увеличьте `WARMUP_KEEP` сразу после развёртывания чистого зеркала: при попадании в кэш прокси его не обновляет, поэтому удалить файл (или отдельную строку) по-прежнему самый надёжный способ добиться повторной проверки.

## 🛰 Прокси запросов версий

| Запрос | Обработчик |
|---|---|
| `/routeros/NEWEST6.{stable,long-term,upgrade}`, `NEWESTa6.*` | `ros6-upgrade.php` |
| `/routeros/NEWEST7.{stable,long-term,upgrade}`, `NEWESTa7.*` | `ros7-upgrade.php` |

Порядок обработки каждого запроса:

1. **Кэш** — ключ `<точка>_<запрошенная версия>` в `routeros/ros6.version.cache` / `ros7.version.cache` → `X-Cache: HIT`.
2. **Upstream** — запрос с `User-Agent: RouterOS <version>` и исходной строкой параметров; ответ валидируется по `^\d+(\.\d+)+\s+\d+` и только затем попадает в кэш → `X-Cache: MISS`.
3. **Резерв** — upstream недоступен или ответ некорректен: отдаётся локальный маркер (`LATEST.6`, `LATEST.6fix`, `NEWEST7.stable`, `NEWESTa7.long-term`), а если и его нет — значение из `mt_proxy_config.php` → `X-Cache: STALE` плюс запись в `error_log`.

Параметр `?version=` важен: MikroTik возвращает новейший релиз *относительно версии, которая сейчас на устройстве*, поэтому в кэше по одной записи на пару «канал обновлений + версия». Переход с ROS 6 на ROS 7 анонсируется через `NEWEST6.upgrade` / `NEWESTa6.upgrade`: если этот запрос не отработал, а резерв неверный, устройства либо вообще не увидят v7, либо увидят его раньше времени.

## 🚦 Политика обновлений

Гейт — `force_update.php`. Скрипт BackupAndUpdate установленный на устройстве сообщает:

```text
/routeros/force_update.php?new_version=7.24.5&model=RB4011iGS%2B&serial=XXXXYYYY&currentFirmware=7.20.3&upgradeFirmware=7.24.5
```

Каждый запрос с непустым `serial` обновляет строку устройства, его IP, версии прошивок и последнюю предложенную версию — так инвентарь наполняется сам, без всякого сканирования. Ответ — простой текст `ENABLED` или `DISABLED`. 

Приоритет правил:

| # | Правило | Поведение |
|---|---|---|
| 1 | Персональный список для `serial` | Непустой список окончательный: разрешены только перечисленные версии |
| 2 | Правило по модели `model:<MODEL>` | Непустой список окончательный |
| 3 | Таблица `global_versions` | Разрешает эти всем, кто не попал под уровни 1–2 |
| 4 | `allowed_versions_hardcoded` | В поставке: `6.49.23`, `7.24.5`, `7.23.8` |

Пустой список на любом уровне проваливает проверку на следующий, поэтому вновь зарегистрированное устройство подчиняется глобальному списку. Если расчёт политики упал с исключением — ответ `DISABLED`: безопасное поведение по умолчанию «не трогать работающий роутер».

## 🖥 Веб-админка

Откройте `http://<зеркало>/mt-proxy/` и авторизуйтесь (Basic Auth, без сессий; интерфейс доступен только через защищённый каталог).

**Devices** — устройства, добавленные автоматически (`auto`), вручную (`manual`) или импортированные из старого файла правил (`legacy`); в таблице модель, текущая и устанавливаемая прошивка, IP-адреса с историей в подсказке, комментарий, разрешённые версии и время последней видимости. Есть поиск, редактирование и удаление по строке, чекбоксы с массовым *replace* или *append* списка версий.

**Global versions** — общий для всего парка allow-список. По версии на строку (ввод через запятую тоже принимается); удаление действует сразу.


## 🔧 Настройка устройств

Статические DNS-записи на каждом роутере (или на вашем внешнем DNS) перенаправляют оба имени на зеркало:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/ip dns cache flush
```

Готовый вариант — `addons/mikrotik/dns.rsc`, только подставьте `SERVER_IP` перед импортом.

После этого ручное обновление работает как обычно (для ROS7 будет установлен режим http):

```routeros
/system package update check-for-updates
/system package update install
```

### Скрипты «резервная копия + обновление»

| Скрипт | Назначение |
|---|---|
| `BackupAndUpdate` | Ежедневный цикл: проверка зеркала, бэкап, установка RouterOS, апгрейд прошивки RouterBOARD |
| `BKPUPD-UPDATER` | Забирает с зеркала актуальный `BackupAndUpdate` и его `BackupAndUpdate.md5`, ре-импортирует только при изменившемся контрольной сумме, запускать вручную или самостоятельно сделать вызов из шедулера. По соображениям безопасности, автоматический запуск  через шедёлер не делался. |
| `install_updater.rsc` | установщик : скачать, импортировать и запустить `BKPUPD-UPDATER` |

Замените подстановку `SERVER_NAME` на имя вашего зеркала до того, как выложите скрипты (`SERVER_IP` тоже подходит; `https://` требует сертификат, которому доверяет CA-цепочка выше, — иначе используйте `-http` варианты). Апдейтеру нужны в `/routeros/` и `BackupAndUpdate.rsc`, **и** `BackupAndUpdate.md5`; файл контрольной суммы в репозитории не формируется, создавайте его после каждой правки:

```bash
cd /var/www/html/routeros
md5sum BackupAndUpdate.rsc | awk '{print $1}' > BackupAndUpdate.md5
chown www-data:www-data BackupAndUpdate.md5
```

Самый быстрый способ развёртывания — один раз импортировать `BKPUPD-UPDATER` на устройство: остальное скачается и обновится само.

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
/system script run install_updater      # после импорта addons/mikrotik/install_updater.rsc
```

Как ведёт себя `BackupAndUpdate`:

1. Регистрирует планировщик `BKPUPD-DAILY` на `05:00` и читает из его поля `comment` устойчивые счётчики неудач (`fw,os,version`).
2. На ROS 7 перед `check-for-updates` выставляет `/system package update set mode=http`, чтобы устройства принимали ответы прокси по чистому HTTP.
3. Сообщает на `force_update.php` по HTTPS модель, serial, текущую и устанавливаемую прошивку и предложенную версию, проверяя сертификат (ROS 6 при первом запуске импортирует `fullchain.pem` в хранилище сертификатов). Ответ `DISABLED` или недоступный сервер — обновление RouterOS отменяется.
4. Если обновление разрешено: сначала создаётся планировщик защиты от цикла перезагрузок, затем `system backup save` + `/export` с именем `auto-backup-<serial>-<version>-<date>` (в `flash/`, если он доступен) и удаляются старые файлы `auto-backup-*`.
5. Отдельно, если `current-firmware != upgrade-firmware`, обновляется прошивка RouterBOARD.
6. Команды, ведущие к перезагрузке (`/system package update install`, `/system reboot`), — самые последние операторы скрипта.

Защита от цикла перезагрузок: каждая попытка увеличивает счётчик в `comment` планировщика; после `maxTries` (2) подряд неудачных попыток скрипт перестаёт перезагружать это устройство. Когда с причиной разберётесь, сбросите счётчики:

```routeros
/system scheduler set BKPUPD-DAILY comment=""
```

## 📝 Журналирование

Всё уходит в syslog (`daemon`) с тегом по имени скрипта; отдельных лог-файлов, которые надо ротировать, нет.

```bash
journalctl -t sync_mikrotik_repo.sh -f   # синхронизация
journalctl -t ros-warmup -f              # прогрев кэша
tail -f /var/log/nginx/mirror-error.log  # промахи прокси, резервы, ошибки PHP
```

Чтобы полностью заглушить скрипты, поставьте в `config.sh` `LOG_OFF=1`.

Заголовок `X-Cache` — самый быстрый способ понять, какой слой ответил устройству:

```bash
curl -sI "http://localhost/routeros/NEWESTa7.stable?version=7.24.4" | grep -i x-cache
```

## 🐛 Диагностика

| Симптом | Куда смотреть |
|---|---|
| Ничего не скачивается | Доступен ли `upgrade.mikrotik.com` с сервера? Есть ли `wget`? Есть права на запсиь в `TARGET_DIR` (без этого скрипт выходит с `101`)? |
| Версия перекачивается каждый прогон | Сравните локальный маркер `LATEST.*` / `NEWEST*` с upstream — маркеры перезаписываются только после полностью успешной загрузки |
| Нет `wireless-*.npk` | Они качаются только для ROS 7 ≥ 7.12.1 на не-x86 |
| Устройство сообщает «обновлений нет» | Сброшен ли кэш DNS? отдаётся ли `/routeros` из **корня сайта**? есть ли вообще заголовок `X-Cache` (нет — сломана маршрутизация PHP)? |
| Устройство предлагает не ту версию | Кэш содержит этот ключ — посмотрите/удалите строку в `routeros/ros6.version.cache` или `ros7.version.cache` либо выполните `ros-warmup.pl` |
| Winbox не скачивается | Установлен ли `curl` и доступен ли `https://mikrotik.com/download/winbox` |
| Веб-админка отдаёт 404 | `FallbackResource` / `try_files` должны указывать на `index.php`; SQLite должна быть доступна веб-пользователю на запись (режим `WAL` требует записи в каталог) |

## 🔒 Замечания по безопасности

- Перенаправлением по DNS вы заставляете все устройства в сети доверять этому хосту, поэтому зеркало не должно быть доступно из недоверенных сегментов без контроля доступа.
- `BackupAndUpdate` / `BKPUPD-UPDATER` ставятся с полным набором policy (`reboot`, `write`, `policy`, `password`, `sensitive`, `romon`, …) и умеют перезагружать устройства. Значит, тот, кто может писать в `/routeros/BackupAndUpdate.rsc`, потенциально может получить доступ ко всем роутерам, где работает апдейтер:  ограничивайте доступ к самому серверу.
- Веб-админка защищена только Basic Auth и запретами в vhost — не выставляйте её в публичный Интернет, ограничьте по IP источника и задайте стойкий пароль.
- `mt_proxy_config.php` секретов не содержит, а вот `mt_proxy.db` — это инвентарь устройств (серийники и IP). Оба vhost его закрывают, но резервные копии держите вне корня документов.
- Предпочитайте HTTPS-варианты скриптов: `-http` передают метаданные устройства (serial, модель, прошивки) открытым текстом.
- Прокси ходит на upstream с включённой проверкой сертификата; `ros-warmup.pl` отключает проверку имени хоста только потому, что обращается к локальному зеркалу.

## ⚠️ Известные ограничения

- **Записи кэша не устаревают.** В `ros6.version.cache` / `ros7.version.cache` каждая строка хранит `значение|timestamp`, но читатели сравнивают только значение — время служит справочной информацией. Закэшированный ответ `NEWEST*` живёт, пока ключ не удалён или upstream не вернёт другое значение для той же пары «точка + версия». Чтобы сразу подхватить перевыпущенный релиз, удалите строку (или весь файл кэша).
- **Загрузка не перезаписывает существующие файлы.** `WGET_OPTS="-q -nc"` (no-clobber) действует на всех запросах, поэтому пакет, изменившийся на стороне MikroTik под тем же именем, не будет перекачан — и обратите внимание: аргумент `force` отключает только проверку «версия не менялась», но не `-nc`. По-настоящему перекачать можно только удалив `${TARGET_DIR}/<version>/`.
- **Автоматически зеркалится только новейший релиз канала.** Старые версии остаются на диске, но цикл синхронизации следит лишь за `LATEST.*` / `NEWEST*`; отдельную версию достаёт `download_ros.sh`.
- **Список архитектур статичен.** Новый тип машины нужно добавить в `firmware_arch` вручную, иначе его пакеты молча пропустятся.
- Скрипты от root и `chown www-data` в cron предполагают, что зеркало работает от root; непривилегированного режима установки нет.

## 📄 Лицензия

Распространяется по [MIT License](LICENSE). Copyright (c) 2023 Roman Dmitriev.

