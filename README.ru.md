📦 mikrotik-local-repo

# 📦 mikrotik-local-repo

[🇬🇧 English](README.md) · [🇷🇺 Русский](README.ru.md)

> Локальное зеркало репозитория MikroTik RouterOS — загрузка пакетов из официальных репозиториев и предоставление доступа к ним устройствам в локальной сети без подключения к Интернету.

## 📖 О проекте

Проект автоматически синхронизирует пакеты RouterOS 6 и RouterOS 7 из официальных репозиториев MikroTik (`upgrade.mikrotik.com` / `download.mikrotik.com`) в локальный каталог, доступный через веб-сервер.

Устройства MikroTik в локальной сети могут получать обновления с локального зеркала благодаря переопределению DNS-записей официальных доменов репозиториев MikroTik.

## ✨ Возможности

* 🔄 Синхронизация **RouterOS 6** (stable и LTS/fix) и **RouterOS 7** (stable и long-term)

* 🏗 Поддержка всех актуальных архитектур:
  `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`

* 📥 Загрузка **Winbox** для всех доступных версий (`.zip`, `.dmg`)

* 📄 Загрузка `CHANGELOG`, `packages.csv` и дополнительных файлов

* ⏩ Пропуск неизменившихся версий — повторно загружаются только изменившиеся версии

* 🛠 Принудительная загрузка (`--force`)

* 📝 Гибкая настройка логирования с возможностью отключения записи в файл

* 🤖 Корректная обработка `User-Agent` для ROS 7 до и после версии 7.12.1

## 📁 Структура проекта

```
mikrotik-local-repo/
├── sync_mikrotik_repo.sh      # Основной скрипт синхронизации
├── config.sh                  # Конфигурация (пути, версии, архитектуры)
├── functions.sh               # Общие функции: логирование, дополнительные файлы, Winbox
├── ros6_functions.sh          # Функции загрузки RouterOS 6
├── ros7_functions.sh          # Функции загрузки RouterOS 7
├── ros-warmup.pl              # Прогрев кэша версий
└── README.md
```

## 🚀 Установка

Установите необходимые пакеты.

### Apache

```
apt install git php php-curl wget curl apache2 libwww-perl liburi-perl -y

a2enmod rewrite
a2enmod headers
```

### Nginx

```
apt install git php php-curl wget curl nginx php-fpm libwww-perl liburi-perl -y
```

Клонируйте репозиторий:

```
git clone https://github.com/<username>/mikrotik-local-repo.git
cd mikrotik-local-repo
```

Скопируйте скрипты синхронизации в каталог, используемый по умолчанию:

```
cp ros-warmup.pl sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
chmod +x /usr/local/bin/sync_mikrotik_repo.sh
chmod +x /usr/local/bin/ros-warmup.pl
```

Установите скрипты прокси для проверки доступности обновлений RouterOS и файлы кэша:

```
mkdir -p /var/www/html/mt-proxy/
mkdir -p /var/www/html/routeros/
cp html/mt-proxy/*.php /var/www/html/mt-proxy/
cp html/routeros/*.cache /var/www/html/routeros/
chown www-data:www-data -R /var/www/html/
```

> ⚠ По умолчанию переменная `SCRIPT_DIR` в `sync_mikrotik_repo.sh` указывает на `/usr/local/bin`. Если скрипты установлены в другом месте, измените значение этой переменной вручную.

## ⚙ Конфигурация

Отредактируйте файл `**config.sh**` с учётом вашей конфигурации:

```
# Путь к локальному зеркалу
TARGET_DIR="/var/www/html/routeros"

# URL локального сайта
SITE_URL="http://localhost"

# Версии RouterOS 6:
#   6     — стабильный выпуск (stable)
#   6fix  — выпуск с долгосрочной поддержкой (LTS)
versions6=("6" "6fix")

# Версии RouterOS 7:
versions7=("stable" "long-term")

# Поддерживаемые архитектуры
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")
```

## 🏃 Использование

### Обычная синхронизация

Загружает только новые или изменившиеся версии:

```
/usr/local/bin/sync_mikrotik_repo.sh
```

### Принудительная синхронизация

Игнорирует кэш сведений о версиях и принудительно выполняет загрузку:

```
/usr/local/bin/sync_mikrotik_repo.sh force
```

### Автоматическая синхронизация через cron

Откройте crontab пользователя root:

```
sudo crontab -e
```

Например, для запуска синхронизации каждые 3 часа:

```
1 */3 * * * root /usr/local/bin/sync_mikrotik_repo.sh 2>/dev/null && chown www-data:www-data -R /var/www/html
```

## 🌐 Настройка веб-сервера

Каталог `$TARGET_DIR` должен быть доступен через веб-сервер.

> ⚠ **Важно:** каталог `/routeros` должен находиться в **корне сайта**, а не во вложенном подкаталоге. Настройте раздачу родительского каталога (`/mnt/mirror`), а не самого `/routeros`.

### Nginx

Пример конфигурации находится в `addons/nginx/`.

### Apache

Пример конфигурации находится в `addons/apache/`.

## 🔧 Настройка устройств MikroTik

На устройствах MikroTik переопределите DNS-записи официальных доменов репозиториев MikroTik, указав IP-адрес локального зеркала:

```
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Замените `192.168.0.1` на IP-адрес вашего веб-сервера.

После этого устройства будут использовать локальное зеркало для получения обновлений:

```
/system package update check-for-updates
/system package update install
```

## 🛠 Принцип работы

```
┌──────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
│  upgrade.mikrotik.com│ ──────► │ sync_mikrotik_repo  │ ──────► │ Локальный сервер │
│ download.mikrotik.com│         │  (wget/curl)        │         │  /mnt/mirror     │
└──────────────────────┘         └─────────────────────┘         └────────┬─────────┘
                                                                          │
                                                                 Переопределение DNS
                                                                          │
                                                                 ┌────────▼─────────┐
                                                                 │  Устройства      │
                                                                 │  MikroTik        │
                                                                 └──────────────────┘
```

1. Скрипт синхронизации проверяет файлы `LATEST.*` / `NEWEST*` на наличие новых версий.

2. При обнаружении новой версии загружаются пакеты для всех настроенных архитектур.

3. Загружаются дополнительные файлы, включая `CHANGELOG`, `packages.csv`, `routeros-*.npk` и `wireless-*.npk` для ROS 7 версии 7.12.1 и выше.

4. Все доступные версии Winbox загружаются отдельно.

5. Устройства MikroTik используют статические DNS-записи для доступа к локальному зеркалу.

## 📝 Логирование

Сообщения журнала записываются в системный журнал (syslog).

Чтобы отключить логирование в файл и выводить сообщения только в консоль, установите:

```
LOG_OFF=1
```

## 🐛 Решение проблем

| Проблема                       | Решение                                                                             |
| ------------------------------ | ----------------------------------------------------------------------------------- |
| Пакеты не загружаются          | Проверьте доступность `upgrade.mikrotik.com` с сервера зеркала                      |
| Устройства не видят обновления | Проверьте DNS-записи и убедитесь, что веб-сервер раздаёт `/routeros` из корня сайта |
| Не удаётся загрузить Winbox    | Проверьте, что `curl` установлен и адрес `mikrotik.com/download/winbox` доступен    |

## 📄 Лицензия

Проект распространяется по лицензии [MIT](LICENSE).
