#!/usr/bin/env bash
#
# Скрипт перебирает каталоги, имена которых начинаются с "6." (только цифры и точки),
# для каждого выполняет запрос к upgrade.mikrotik.com и строит таблицу:
#   6.x.y = 7.a.b
#
# Использование:
#   ./map_ros6_to_ros7.sh [путь_к_каталогу_с_версиями]
#
# Если путь не указан, используется текущая директория.

set -euo pipefail

# ---------- настройки ----------
BASE_URL="https://upgrade.mikrotik.com/routeros/NEWESTa6.upgrade"
WGET_OPTS=(-q -O -)   # -q тихий режим, -O - вывод в stdout

# ---------- проверка аргументов ----------
SEARCH_DIR="${1:-.}"

if [[ ! -d "$SEARCH_DIR" ]]; then
    echo "Ошибка: каталог '$SEARCH_DIR' не существует." >&2
    exit 1
fi

# ---------- сбор версий из имён каталогов ----------
# Ищем каталоги, имя которых полностью соответствует шаблону 6.<цифры>.<цифры>
# (можно расширить, если версии бывают вида 6.49.21.1 и т.п.)
mapfile -t VERSIONS < <(
    find "$SEARCH_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | grep -E '^6\.[0-9]+\.[0-9]+$' \
        | sort -V
)

if [[ ${#VERSIONS[@]} -eq 0 ]]; then
    echo "Не найдено каталогов с версиями ROS 6.x.y в '$SEARCH_DIR'." >&2
    exit 1
fi

echo "Найдено версий ROS6: ${#VERSIONS[@]}"
echo

# ---------- вывод таблицы ----------
printf "%-12s | %-12s | %s\n" "ROS6" "ROS7" "Сырой ответ"
printf "%-12s-+-%-12s-+-%s\n" "------------" "------------" "-----------------------------"

declare -A MAPPING

for ver6 in "${VERSIONS[@]}"; do
    # Формируем URL с параметром version
    url="${BASE_URL}?version=${ver6}"

    # Выполняем запрос; если wget падает — пропускаем версию
    if ! raw=$(wget "${WGET_OPTS[@]}" "$url" 2>/dev/null); then
        printf "%-12s | %-12s | %s\n" "$ver6" "—" "ошибка запроса"
        continue
    fi

    # Первое слово ответа — версия, на которую предлагается обновиться
    ver7=$(awk '{print $1; exit}' <<< "$raw")

    # Если ответ пустой или не похож на версию (например, содержит "error"),
    # помечаем как неопределённый
    if [[ -z "$ver7" || ! "$ver7" =~ ^[0-9]+\.[0-9]+ ]]; then
        printf "%-12s | %-12s | %s\n" "$ver6" "—" "$raw"
        continue
    fi

    MAPPING["$ver6"]="$ver7"
    printf "%-12s | %-12s | %s\n" "$ver6" "$ver7" "$raw"
done

# ---------- итоговая таблица (только успешные пары) ----------
echo
echo "=== Итоговая таблица соответствий ==="
if [[ ${#MAPPING[@]} -eq 0 ]]; then
    echo "Нет успешных соответствий."
else
    printf "%-12s → %s\n" "ROS6" "ROS7"
    printf "%-12s-+-%s\n" "------------" "------------"
    for ver6 in $(printf '%s\n' "${!MAPPING[@]}" | sort -V); do
        printf "%-12s → %s\n" "$ver6" "${MAPPING[$ver6]}"
    done
fi
