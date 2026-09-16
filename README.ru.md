# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Локальное зеркало репозитория MikroTik RouterOS — скачивайте пакеты из официальных репозиториев и раздавайте их устройствам в локальной сети без доступа в интернет.

## 📖 О проекте

Этот проект автоматически синхронизирует пакеты RouterOS 6 и RouterOS 7 из официальных репозиториев MikroTik (`upgrade.mikrotik.com` / `download.mikrotik.com`) в локальную директорию, которая затем раздаётся через веб-сервер.

Устройства MikroTik в локальной сети могут получать обновления из локального зеркала благодаря подмене DNS-записей официальных имён репозиториев MikroTik.

## ✨ Возможности

* 🔄 Синхронизация **RouterOS 6** (stable и LTS/fix) и **RouterOS 7** (stable и long-term)
* 🏗 Поддержка всех актуальных архитектур:
  `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
* 📥 Загрузка **Winbox** всех доступных версий (`.zip`, `.dmg`)
* 📄 Загрузка `CHANGELOG`, `packages.csv` и дополнительных файлов
* ⏩ Пропуск неизменённых версий — повторная загрузка выполняется только при изменении
* 🛠 Режим принудительной загрузки (`--force`)
* 📝 Гибкое логирование с возможностью отключения записи в файл
* 🤖 Корректная обработка `User-Agent` для ROS 7 до и после версии 7.12.1

## 📁 Структура проекта

```text
mikrotik-local-repo/
├── sync_mikrotik_repo.sh      # Основной скрипт синхронизации
├── config.sh                  # Конфигурация (пути, версии, архитектуры)
├── functions.sh               # Общие функции: логирование, доп. файлы, Winbox
├── ros6_functions.sh          # Функции загрузки RouterOS 6
├── ros7_functions.sh          # Функции загрузки RouterOS 7
└── README.md
```

## 🚀 Установка

Установите необходимые пакеты.

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

Клонируйте репозиторий:

```bash
git clone https://github.com/<username>/mikrotik-local-repo.git
cd mikrotik-local-repo
```

Скопируйте скрипты синхронизации в рабочую директорию по умолчанию:

```bash
cp sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh
```

Сделайте скрипты исполняемыми:

```bash
chmod +x *.sh
```

Установите PHP-скрипты прокси для получения версий обновлений RouterOS:

```bash
cp html/ros6-upgrade.php /путь/к/зеркалу/
cp html/ros7-upgrade.php /путь/к/зеркалу/
```

> ⚠️ Переменная `SCRIPT_DIR` в `sync_mikrotik_repo.sh` по умолчанию указывает на `/usr/local/bin`. Если скрипты размещаются в другом месте, измените эту переменную вручную.

## ⚙ Конфигурация

Отредактируйте файл **`config.sh`** в соответствии с вашей конфигурацией:

```bash
# Путь к локальному зеркалу
TARGET_DIR="/mnt/mirror/routeros"

# Версии RouterOS 6:
#   6     - стабильный релиз
#   6fix  - LTS-релиз
versions6=("6" "6fix")

# Версии RouterOS 7:
versions7=("stable" "long-term")

# Необходимые архитектуры
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")
```

## 🏃 Использование

### Обычная синхронизация

Загружает только новые или изменённые версии:

```bash
/usr/local/bin/sync_mikrotik_repo.sh
```

### Принудительная синхронизация

Игнорирует сохранённую информацию о версиях и принудительно выполняет загрузку:

```bash
/usr/local/bin/sync_mikrotik_repo.sh force
```

### Периодическая синхронизация через cron

Откройте crontab пользователя `root`:

```bash
sudo crontab -e
```

Например, запускать синхронизацию каждый день в 03:00:

```cron
0 3 * * * /usr/local/bin/sync_mikrotik_repo.sh >> /var/log/mikrotik-sync.log 2>&1
```

## 🌐 Настройка веб-сервера

Директория `$TARGET_DIR` должна быть доступна через веб-сервер.

> ⚠️ **Важно:** Каталог `/routeros` должен находиться **в корне сайта**, а не внутри другого подкаталога. Раздавайте родительскую директорию (`/mnt/mirror`), а не сам `/routeros`.

### Nginx

Пример конфигурации:

```nginx
server {
    listen 80;
    server_name download.mikrotik.com upgrade.mikrotik.com;

    root /mnt/mirror;   # БЕЗ /routeros — /routeros должен находиться в корне сайта!

    location / {
        autoindex on;
    }

    # Скрипт обновления MikroTik
    location ~ ^/ros6-upgrade.php { deny all; }
    location ~ ^/ros7-upgrade.php { deny all; }

    location ~ ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /mnt/mirror/ros6-upgrade.php;
        fastcgi_param QUERY_STRING    $query_string;
        fastcgi_param REQUEST_URI     $request_uri;

        # Отключаем chunked encoding в исходящем ответе
        chunked_transfer_encoding off;

        # Буферизуем весь ответ PHP, чтобы nginx мог вычислить Content-Length,
        # если PHP его не передал
        fastcgi_buffering on;

        # Не позволяем nginx добавлять или изменять кодировки
        gzip off;
        proxy_set_header Accept-Encoding "";
    }

    location ~ ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /mnt/mirror/ros7-upgrade.php;
        fastcgi_param QUERY_STRING    $query_string;
        fastcgi_param REQUEST_URI     $request_uri;

        # Отключаем chunked encoding в исходящем ответе
        chunked_transfer_encoding off;

        # Буферизуем весь ответ PHP, чтобы nginx мог вычислить Content-Length,
        # если PHP его не передал
        fastcgi_buffering on;

        # Не позволяем nginx добавлять или изменять кодировки
        gzip off;
        proxy_set_header Accept-Encoding "";
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

    # Запрещаем прямой доступ к PHP backend,
    # но разрешаем внутренние rewrite.
    RewriteCond %{THE_REQUEST} \s/+ros6-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros6-upgrade\.php$ - [F,L]

    RewriteCond %{THE_REQUEST} \s/+ros7-upgrade\.php(?:[?\s]) [NC]
    RewriteRule ^/ros7-upgrade\.php$ - [F,L]

    # URL обновлений RouterOS 6 -> PHP backend
    RewriteRule ^/routeros/(NEWEST6\.stable|NEWESTa6\.stable|NEWEST6\.long-term|NEWESTa6\.long-term|NEWEST6\.upgrade|NEWESTa6\.upgrade)$ /ros6-upgrade.php [L]

    # URL обновлений RouterOS 7 -> PHP backend
    RewriteRule ^/routeros/(NEWEST7\.stable|NEWESTa7\.stable|NEWEST7\.long-term|NEWESTa7\.long-term|NEWEST7\.upgrade|NEWESTa7\.upgrade)$ /ros7-upgrade.php [L]

    # Отключаем gzip для этих URL
    <IfModule mod_deflate.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" no-gzip dont-vary
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" no-gzip dont-vary
    </IfModule>

    # Убираем Accept-Encoding из входящих запросов
    <IfModule mod_headers.c>
        SetEnvIf Request_URI "^/routeros/(NEWEST6|NEWESTa6)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        SetEnvIf Request_URI "^/routeros/(NEWEST7|NEWESTa7)\.(stable|long-term|upgrade)" NO_ACCEPT_ENCODING
        RequestHeader unset Accept-Encoding env=NO_ACCEPT_ENCODING
    </IfModule>
</VirtualHost>
```

## 🔧 Настройка устройств MikroTik

На устройствах MikroTik замените DNS-записи официальных репозиториев на IP-адрес вашего локального зеркала:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Замените `192.168.0.1` на IP-адрес вашего веб-сервера.

После этого устройства будут использовать локальное зеркало для получения обновлений:

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
                                                                   DNS override
                                                                          │
                                                                 ┌────────▼─────────┐
                                                                 │  Устройства      │
                                                                 │  MikroTik        │
                                                                 └──────────────────┘
```

1. Скрипт синхронизации проверяет файлы `LATEST.*` / `NEWEST*` на наличие новых версий.
2. При обнаружении новой версии загружаются пакеты для всех настроенных архитектур.
3. Загружаются дополнительные файлы, включая `CHANGELOG`, `packages.csv`, `routeros-*.npk` и `wireless-*.npk` для ROS 7 ≥ 7.12.1.
4. Отдельно загружаются все доступные версии Winbox.
5. Устройства MikroTik используют статические DNS-записи для доступа к локальному зеркалу.

## 📝 Логирование

Логи записываются в файл, указанный переменной `LOG_FILE` в `config.sh`.

Чтобы отключить запись в файл и оставлять сообщения только в консоли, установите:

```bash
LOG_OFF=1
```

## 🐛 Устранение неполадок

| Проблема                       | Решение                                                                            |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| Пакеты не скачиваются          | Проверьте доступность `upgrade.mikrotik.com` с сервера зеркала                     |
| Устройства не видят обновления | Проверьте DNS-записи и убедитесь, что веб-сервер отдаёт `/routeros` из корня сайта |
| Не загружается Winbox          | Проверьте наличие `curl` и доступность `mikrotik.com/download/winbox`              |

## 📄 Лицензия

Распространяется под лицензией [MIT](LICENSE).
