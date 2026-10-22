#!/bin/bash

# ========== Проверка аргументов ==========
if [ "$#" -ne 3 ]; then
    echo "Использование: $0 <путь_к_папке> <порог_в_%> <количество_файлов>"
    echo "Пример: $0 /log 80 5"
    exit 1
fi

LOG_DIR="$1"
THRESHOLD="$2"
M_FILES="$3"
BACKUP_DIR="/backup"

# ========== Валидация входных данных ==========
if [ ! -d "$LOG_DIR" ]; then
    echo "ОШИБКА: Папка '$LOG_DIR' не существует или не является директорией."
    exit 1
fi

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "ОШИБКА: Порог должен быть целым числом от 0 до 100."
    exit 1
fi

if [ "$THRESHOLD" -lt 0 ]  [ "$THRESHOLD" -gt 100 ]; then
    echo "ОШИБКА: Порог должен быть целым числом от 0 до 100."
    exit 1
fi

if ! [[ "$M_FILES" =~ ^[0-9]+$ ]]; then
    echo "ОШИБКА: Количество файлов M должно быть положительным целым числом."
    exit 1
fi

if [ "$M_FILES" -le 0 ]; then
    echo "ОШИБКА: Количество файлов M должно быть положительным целым числом."
    exit 1
fi

# ========== Подготовка папки backup ==========
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Папка $BACKUP_DIR не найдена. Создаю..."
    sudo mkdir -p "$BACKUP_DIR"  { echo "Не удалось создать $BACKUP_DIR"; exit 1; }
fi

# ========== Подсчёт размера в процентах ==========
DIR_SIZE_KB=$(du -sk "$LOG_DIR" 2>/dev/null | cut -f1)
TOTAL_SIZE_KB=$(df -k "$LOG_DIR" | tail -1 | awk '{print $2}')
USAGE_PERCENT=$(awk "BEGIN {printf \"%.10f\", ($DIR_SIZE_KB / $TOTAL_SIZE_KB) * 100}")

echo "======================================================"
echo "Анализ папки:       $LOG_DIR"
echo "Размер папки:       $DIR_SIZE_KB KB"
echo "Размер раздела:     $TOTAL_SIZE_KB KB"
echo "Занято в папке:     $USAGE_PERCENT %"
echo "Порог (N):          $THRESHOLD %"
echo "======================================================"

# ========== Сравнение с порогом ==========
IS_OVER=$(awk -v usage="$USAGE_PERCENT" -v threshold="$THRESHOLD" 'BEGIN { if (usage > threshold + 0.0001) print 1; else print 0 }')

if [ "$IS_OVER" -eq 1 ]; then
    echo ">>> Порог ПРЕВЫШЕН. Запускаю архивацию $M_FILES самых старых файлов..."

    # ========== Поиск M самых старых файлов ==========
    # ВАЖНО: \ должен быть последним символом на строке, без пробелов после
    FILE_LIST=$(find "$LOG_DIR" -type f -not -path "*/backup/*" -printf '%T@ %p\n' 2>/dev/null \
                | sort -n \
                | head -n "$M_FILES" \
                | cut -d' ' -f2-)

    if [ -z "$FILE_LIST" ]; then
        echo "В папке нет файлов для архивации. Выход."
        exit 0
    fi

    echo "Файлы, отобранные для архивации:"
    echo "$FILE_LIST"

    # ========== Создание архива ==========
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"

    echo "$FILE_LIST" | sudo tar -czf "$ARCHIVE_NAME" -T -

    if [ $? -eq 0 ]; then
        echo ">>> Архив успешно создан: $ARCHIVE_NAME"
        echo ">>> Размер архива: $(du -h "$ARCHIVE_NAME" | cut -f1)"
    else
        echo "ОШИБКА при создании архива!"
        exit 1
    fi
else
    echo ">>> Размер папки в пределах нормы. Архивация не требуется."
fi
