# 📦 mikrotik-local-repo

[🇬🇧English](README.md) · [🇷🇺Русский](README.ru.md)

> Локальное зеркало репозитория MikroTik RouterOS — скачивает пакеты с официальных серверов и отдаёт их устройствам в локальной сети без доступа в интернет.

## 📖 О проекте

Проект автоматически синхронизирует пакеты RouterOS 6 и RouterOS 7 с официальных репозиториев MikroTik (`upgrade.mikrotik.com` / `download.mikrotik.com`) в локальный каталог, который раздаётся веб-сервером.

Устройства MikroTik в локальной сети получают обновления с локального зеркала — для этого достаточно переопределить DNS-записи официальных хостов MikroTik.

## ✨ Возможности

- 🔄 Синхронизация **RouterOS 6** (stable и LTS/fix) и **RouterOS 7** (stable и long-term)
- 🏗 Поддержка всех актуальных архитектур:
  `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📥 Скачивание **Winbox** всех доступных версий (`.zip`, `.dmg`)
- 📄 Скачивание `CHANGELOG`, `packages.csv` и дополнительных файлов
- ⏩ Пропуск неизменившихся версий — повторно скачиваются только новые
- 🛠 Режим принудительного скачивания (`--force`)
- 📝 Гибкое логирование с возможностью отключить запись в файл
- 🤖 Корректная обработка `User-Agent` для ROS 7 до и после версии 7.12.1

## 📁 Структура проекта

```text
mikrotik-local-repo/
├── sync_mikrotik_repo.sh      # Основной скрипт синхронизации
├── config.sh                  # Конфигурация (пути, версии, архитектуры)
├── functions.sh               # Общие функции: логирование, доп. файлы, Winbox
├── ros6_functions.sh          # Функции скачивания RouterOS 6
├── ros7_functions.sh          # Функции скачивания RouterOS 7
├── ros-warmup.pl              # Прогрев кэша версий
└── README.md
```

## 🚀 Установка

Установите необходимые пакеты.

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

Клонируйте репозиторий:

```bash
git clone https://github.com/<username>/mikrotik-local-repo.git
cd mikrotik-local-repo
```

Скопируйте скрипты синхронизации в рабочий каталог по умолчанию:

```bash
cp ros-warmup.pl sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh
chmod +x /usr/local/bin/ros-warmup.pl
```

Установите прокси-скрипты для URL обновлений RouterOS:

```bash
cp html/ros6-upgrade.php /var/www/html/
cp html/ros7-upgrade.php /var/www/html/
cp html/force_update.php /var/www/html/
```

> ⚠ Переменная `SCRIPT_DIR` в `sync_mikrotik_repo.sh` по умолчанию указывает на `/usr/local/bin`. Если вы установили скрипты в другое место — измените её вручную.

## ⚙ Конфигурация

Отредактируйте **`config.sh`** под своё окружение:

```bash
# Путь к локальному зеркалу
TARGET_DIR="/mnt/mirror/routeros"

# Адрес сайта этого сервера (для прогрева кэша версий)
SITE_URL="http://localhost"

# Версии RouterOS 6:
#   6     - стабильный релиз
#   6fix  - LTS-релиз
versions6=("6" "6fix")

# Версии RouterOS 7:
versions7=("stable" "long-term")

# Требуемые архитектуры
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")
```

## 🏃 Использование

### Обычная синхронизация

Скачиваются только новые или изменившиеся версии:

```bash
/usr/local/bin/sync_mikrotik_repo.sh
```

### Принудительная синхронизация

Игнорирует кэш информации о версиях и скачивает всё заново:

```bash
/usr/local/bin/sync_mikrotik_repo.sh force
```

### Синхронизация по расписанию (cron)

Откройте crontab root:

```bash
sudo crontab -e
```

Например, запуск синхронизации каждые 3 часа

```cron
1 */3 * * * root /usr/local/bin/sync_mikrotik_repo.sh 2>/dev/null && chown www-data:www-data -R /var/www/html
```

## 🌐 Настройка веб-сервера

Каталог `$TARGET_DIR` должен быть доступен через веб-сервер.

> ⚠ **Важно:** каталог `/routeros` должен находиться в **корне сайта**, а не внутри другого подкаталога. Раздавайте родительский каталог (`/mnt/mirror`), а не сам `/routeros`.

### Nginx

Пример конфигурации:

```nginx
server {
    listen 80;
    server_name download.mikrotik.com upgrade.mikrotik.com;

    root /var/www/html;   # БЕЗ /routeros — /routeros должен быть в корне сайта!

    location / {
        autoindex on;
    }

    # Скрипты обновления MikroTik
    location = /ros6-upgrade.php { return 404; }
    location = /ros7-upgrade.php { return 404; }
    location = /force_update.php { return 404; }

    location ~ ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ {
            include fastcgi_params;
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME /mnt/md0/mirror/ros6-upgrade.php;
            fastcgi_param SCRIPT_NAME     /ros6-upgrade.php;
            fastcgi_param DOCUMENT_ROOT   /mnt/md0/mirror;
            fastcgi_param REQUEST_URI  $request_uri;
            fastcgi_param QUERY_STRING $query_string;
            fastcgi_connect_timeout 2s;
            fastcgi_send_timeout    3s;
            fastcgi_read_timeout    3s;
            fastcgi_buffer_size     16k;
            fastcgi_buffers         8 16k;
            fastcgi_busy_buffers_size 32k;
            fastcgi_buffering on;
            gzip off;
        }

    location ~ ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ {
            include fastcgi_params;
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME /mnt/md0/mirror/ros7-upgrade.php;
            fastcgi_param SCRIPT_NAME     /ros7-upgrade.php;
            fastcgi_param DOCUMENT_ROOT   /mnt/md0/mirror;
            fastcgi_param REQUEST_URI  $request_uri;
            fastcgi_param QUERY_STRING $query_string;
            fastcgi_connect_timeout 2s;
            fastcgi_send_timeout    3s;
            fastcgi_read_timeout    3s;
            fastcgi_buffer_size     16k;
            fastcgi_buffers         8 16k;
            fastcgi_busy_buffers_size 32k;
            fastcgi_buffering on;
            gzip off;
        }

    location = /routeros/force_update.php {
            include fastcgi_params;
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME /mnt/md0/mirror/force_update.php;
            fastcgi_param QUERY_STRING    $query_string;
            fastcgi_param REQUEST_URI     $request_uri;
            fastcgi_connect_timeout 2s;
            fastcgi_send_timeout    3s;
            fastcgi_read_timeout    3s;
            fastcgi_buffer_size     16k;
            fastcgi_buffers         8 16k;
            fastcgi_busy_buffers_size 32k;
            fastcgi_buffering on;
            gzip off;
        }
}
```

### Apache

Пример конфигурации:

```apache
<VirtualHost *:80>
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    RewriteEngine On

    # Блокируем прямой доступ к PHP-бэкенду, разрешая только внутренние rewrite.
    RewriteCond %{THE_REQUEST} \s/+ros6-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros6-upgrade\.php$ - [F,L]
    RewriteCond %{THE_REQUEST} \s/+ros7-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros7-upgrade\.php$ - [F,L]
    RewriteCond %{THE_REQUEST} \s/+force_update\.php(?:[?\s]) [NC]
    RewriteRule ^/force_update\.php$ - [F,L]

    # URL обновления RouterOS 6 -> PHP-бэкенд
    RewriteRule ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ /ros6-upgrade.php [L]

    # URL обновления RouterOS 7 -> PHP-бэкенд
    RewriteRule ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ /ros7-upgrade.php [L]

    # Обновление включено?
    RewriteRule ^/routeros/force_update.php /force_update.php [L]

    # Отключаем gzip-сжатие для этих URL
    <IfModule mod_deflate.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" no-gzip dont-vary
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" no-gzip dont-vary
        SetEnvIf Request_URI "^/routeros/force_update.php" no-gzip dont-vary
    </IfModule>

    # Удаляем Accept-Encoding из входящих запросов
    <IfModule mod_headers.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        SetEnvIf Request_URI "^/routeros/force_update.php" NO_ACCEPT_ENCODING
        RequestHeader unset Accept-Encoding env=NO_ACCEPT_ENCODING
    </IfModule>

</VirtualHost>
```

## 🔧 Настройка устройств MikroTik

На устройствах MikroTik переопределите DNS-записи официальных хостов MikroTik, направив их на IP-адрес локального зеркала:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Замените `192.168.0.1` на IP-адрес вашего веб-сервера.

После этого устройства будут использовать локальное зеркало для обновлений:

```routeros
/system package update check-for-updates
/system package update install
```

## 🛠 Как это работает

```text
┌──────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
│  upgrade.mikrotik.com│ ──────► │ sync_mikrotik_repo  │ ──────► │ Локальный сервер │
│ download.mikrotik.com│         │  (wget/curl)        │         │  /mnt/mirror     │
└──────────────────────┘         └─────────────────────┘         └────────┬─────────┘
                                                                          │
                                                                   Подмена DNS
                                                                          │
                                                                 ┌────────▼─────────┐
                                                                 │  Устройства      │
                                                                 │  MikroTik        │
                                                                 └──────────────────┘
```

1. Скрипт синхронизации проверяет файлы `LATEST.*` / `NEWEST*` на наличие новых версий.
2. При обнаружении новой версии скачиваются пакеты для всех настроенных архитектур.
3. Скачиваются дополнительные файлы, включая `CHANGELOG`, `packages.csv`, `routeros-*.npk` и `wireless-*.npk` для ROS 7 ≥ 7.12.1.
4. Отдельно скачиваются все доступные версии Winbox.
5. Устройства MikroTik используют статические DNS-записи для доступа к локальному зеркалу.

## 📝 Логирование

Логи пишутся в syslog.

Чтобы отключить запись в файл и оставить вывод сообщений только в консоль, установите:

```bash
LOG_OFF=1
```

## 🐛 Решение проблем

| Проблема | Решение |
|---|---|
| Пакеты не скачиваются | Проверьте, что `upgrade.mikrotik.com` доступен с сервера-зеркала |
| Устройства не видят обновлений | Проверьте DNS-записи и убедитесь, что веб-сервер отдаёт `/routeros` из корня сайта |
| Winbox не скачивается | Проверьте, что установлен `curl` и что `mikrotik.com/download/winbox` доступен |

## 📄 Лицензия

Распространяется под [лицензией MIT](LICENSE).
