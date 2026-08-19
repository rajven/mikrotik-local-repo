# 📦 mikrotik-local-repo

> Локальное зеркало репозитория MikroTik RouterOS — скачивайте пакеты из официального репозитория и раздавайте их устройствам в локальной сети без доступа в интернет.

---

## 📖 О проекте

Скрипт автоматически синхронизирует пакеты RouterOS 6 и RouterOS 7 из официальных репозиториев MikroTik (`upgrade.mikrotik.com` / `download.mikrotik.com`) в локальную директорию, которая затем раздаётся через веб-сервер. Устройства MikroTik в локальной сети получают обновления из локального зеркала благодаря подмене DNS-имён.

## ✨ Возможности

- 🔄 Синхронизация **RouterOS 6** (stable, LTS/fix) и **RouterOS 7** (stable, long-term)
- 🏗️ Поддержка всех актуальных архитектур: `arm`, `arm64`, `mipsbe`, `mmips`, `ppc`, `smips`, `tile`, `x86`
- 📥 Загрузка **Winbox** (все версии: `.zip`, `.dmg`, `.sha256`)
- 📄 Скачивание `CHANGELOG`, `packages.csv` и дополнительных файлов
- ⏩ Пропуск неизменённых версий (повторная загрузка только при изменении)
- 🛠️ Режим принудительной загрузки (`--force`)
- 📝 Гибкое логирование с возможностью отключения
- 🤖 Корректная обработка `User-Agent` для ROS 7 (до и после версии 7.12.1)

## 📁 Структура проекта

```
mikrotik-local-repo/
├── sync_mikrotik_repo.sh      # Основной скрипт синхронизации
├── config.sh                  # Конфигурация (пути, версии, архитектуры)
├── functions.sh               # Общие функции: логирование, загрузка доп. файлов, Winbox
├── ros6_functions.sh          # Функции загрузки RouterOS 6
├── ros7_functions.sh          # Функции загрузки RouterOS 7
└── README.md
```

## 📋 Требования

| Компонент | Назначение |
|-----------|------------|
| `bash` ≥ 4.0 | Интерпретатор скриптов |
| `wget` | Загрузка пакетов |
| `curl` | Загрузка Winbox |
| `grep` с поддержкой `-P` (PCRE) | Парсинг ссылок Winbox |
| Веб-сервер (`nginx`, `apache`, `lighttpd`) | Раздача зеркала клиентам |

## 🚀 Установка

```bash
# Клонируем репозиторий
git clone https://github.com/ваш-аккаунт/mikrotik-local-repo.git
cd mikrotik-local-repo

# Копируем скрипты в рабочую директорию (по умолчанию /usr/local/bin)
sudo cp sync_mikrotik_repo.sh config.sh functions.sh ros6_functions.sh ros7_functions.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/sync_mikrotik_repo.sh

# Задаём права на исполнение
chmod +x *.sh
```

> ⚠️ В скрипте `sync_mikrotik_repo.sh` переменная `SCRIPT_DIR` по умолчанию указывает на `/usr/local/bin`. Если размещаете скрипты в другом месте — измените её вручную.

## ⚙️ Конфигурация

Отредактируйте файл **`config.sh`** под свои нужды:

```bash
# Путь к локальному зеркалу
TARGET_DIR="/mnt/mirror/routeros"

# Версии RouterOS 6:
#   6     - stable release
#   6fix  - LTS release
versions6=("6" "6fix")

# Версии RouterOS 7:
versions7=("stable" "long-term")

# Необходимые архитектуры
firmware_arch=("arm" "arm64" "mipsbe" "mmips" "ppc" "smips" "tile" "x86")
```

## 🏃 Использование

### Обычная синхронизация (только новые версии):

```bash
/usr/local/bin/sync_mikrotik_repo.sh
```

### Принудительная загрузка (игнорирует кэш версий):

```bash
/usr/local/bin/sync_mikrotik_repo.sh force
```

### Запуск по расписанию (cron):

```bash
sudo crontab -e
```

```cron
# Синхронизация каждый день в 03:00
0 3 * * * /usr/local/bin/sync_mikrotik_repo.sh >> /var/log/mikrotik-sync.log 2>&1
```

## 🌐 Настройка веб-сервера

Директория `$TARGET_DIR` должна быть доступна через веб-сервер.

> ⚠️ **Важно:** Каталог `/routeros` должен находиться **в корне сайта**, а не внутри подкаталога. Раздавайте родительскую директорию (`/mnt/mirror`), а не сам `/routeros`.

Пример конфигурации **Nginx**:

```nginx
server {
    listen 80;
    server_name download.mikrotik.com upgrade.mikrotik.com;

    root /mnt/mirror;   # БЕЗ /routeros — сам /routeros должен быть в корне!

    location / {
        autoindex on;
    }
}
```

Пример конфигурации **Apache**:

```apache
<VirtualHost *:80>
    ServerName download.mikrotik.com
    DocumentRoot /mnt/mirror
    <Directory /mnt/mirror>
        Options Indexes FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
```

### Создание символических ссылок

В корневой директории зеркала создайте симлинки для корректной работы устройств:

```bash
cd /mnt/mirror/routeros

touch LATEST.6fix
touch LATEST.6
ln -s LATEST.6fix NEWEST6.long-term
ln -s LATEST.6 NEWEST6.stable
```

## 🔧 Настройка устройств MikroTik

На роутерах MikroTik подмените DNS-имена официальных репозиториев на адрес вашего локального сервера:

```routeros
/ip dns static add address=192.168.0.1 name=download.mikrotik.com
/ip dns static add address=192.168.0.1 name=upgrade.mikrotik.com
```

Замените `192.168.0.1` на IP-адрес вашего веб-сервера.

После этого устройства будут получать обновления из локального зеркала:

```routeros
/system package update check-for-updates
/system package update install
```

## 🛠️ Как это работает

```
┌──────────────────────┐         ┌─────────────────────┐         ┌──────────────────┐
│  upgrade.mikrotik.com│ ──────► │ sync_mikrotik_repo  │ ──────► │  Локальный сервер │
│  download.mikrotik.com│        │  (wget/curl)        │         │  /mnt/mirror     │
└──────────────────────┘         └─────────────────────┘         └────────┬─────────┘
                                                                          │
                                                                   DNS override
                                                                          │
                                                                 ┌────────▼─────────┐
                                                                 │  Устройства       │
                                                                 │  MikroTik         │
                                                                 └──────────────────┘
```

1. Скрипт проверяет файлы `LATEST.*` / `NEWEST*.` на наличие новых версий.
2. При обнаружении новой версии скачиваются пакеты для всех указанных архитектур.
3. Скачиваются дополнительные файлы: `CHANGELOG`, `packages.csv`, `routeros-*.npk`, `wireless-*.npk` (для ROS 7 ≥ 7.12.1).
4. Отдельно загружаются все актуальные версии Winbox.
5. Устройства MikroTik через статические DNS-записи обращаются к локальному зеркалу.

## 📝 Логирование

Логи пишутся в файл, указанный в переменной `LOG_FILE` (настраивается в `config.sh`).

Для отключения записи в лог-файл (только вывод в консоль) установите:

```bash
LOG_OFF=1
```

## 🐛 Устранение неполадок

| Проблема | Решение |
|----------|---------|
| Пакеты не скачиваются | Проверьте доступность `upgrade.mikrotik.com` с сервера |
| Устройства не видят обновления | Убедитесь, что DNS-записи настроены корректно и веб-сервер отдаёт `/routeros` в корне |
| Ошибка загрузки Winbox | Проверьте наличие `curl` и доступность `mikrotik.com/download/winbox` |
| `grep -P` не работает | Установите `grep` с поддержкой PCRE или используйте `gnu grep` |

## 📄 Лицензия

Распространяется под лицензией [MIT](LICENSE).
