#!/bin/bash

# ========== Настройки ==========
SCRIPT="./log_archiver.sh"      # путь до тестируемого скрипта
TEST_DIR="/log"                 # тестовая папка
BACKUP_DIR="/backup"            # папка для архивов
LOG_FILE="./test_results.log"   # файл с логами

# Счётчики
PASSED=0
FAILED=0

# ========== Вспомогательные функции ==========

# Проверка, что log_archiver.sh существует
if [ ! -f "$SCRIPT" ]; then
    echo -e "ОШИБКА: $SCRIPT не найден в текущей директории!"
    echo "Убедись, что ты находишься в ~/acos_lab1 и файл script1.sh там лежит."
    exit 1
fi

# Очистка тестовой среды перед каждым тестом
cleanup_env() {
    sudo rm -rf "$TEST_DIR"
    sudo rm -rf "$BACKUP_DIR"
    sudo mkdir -p "$TEST_DIR"
    sudo mkdir -p "$BACKUP_DIR"
    # Даём права на запись текущему пользователю
    sudo chown -R "$(whoami)":"$(whoami)" "$TEST_DIR" "$BACKUP_DIR"
}

# Печать заголовка теста
print_test_header() {
    echo ""
    echo -e "====================================================="
    echo -e " ТЕСТ: $1"
    echo -e "====================================================="
}

# Отметка о результате
mark_pass() {
    echo -e "[PASS] $1"
    PASSED=$((PASSED + 1))
    echo "[PASS] $1" >> "$LOG_FILE"
}

mark_fail() {
    echo -e "[FAIL] $1"
    FAILED=$((FAILED + 1))
    echo "[FAIL] $1" >> "$LOG_FILE"
}

# ============================================================
# ТЕСТ 1: Несуществующая папка
# ============================================================
test_nonexistent_dir() {
    print_test_header "1. Несуществующая папка"
    cleanup_env

    sudo rm -rf /log

    OUTPUT=$(sudo "$SCRIPT" /log 80 3 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"

    if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qi "не существует"; then
        mark_pass "Скрипт корректно отказался работать с несуществующей папкой"
    else
        mark_fail "Скрипт не выдал ошибку при несуществующей папке"
    fi
}

# ============================================================
# ТЕСТ 2: Некорректный порог (150%)
# ============================================================
test_bad_threshold() {
    print_test_header "2. Порог 150%"
    cleanup_env
    sudo echo "test" > "$TEST_DIR/file.txt"

    # Запускаем и сохраняем вывод и код возврата
    OUTPUT=$(sudo "$SCRIPT" /log 150 3 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"
    echo "Код возврата: $EXIT_CODE"

    # Проверяем, что код возврата не 0 и что в выводе есть слово "Порог" или "ОШИБКА"
    if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qiE "порог|ошибка"; then
        mark_pass "Скрипт отклонил порог 150%"
    else
        mark_fail "Скрипт не отклонил порог 150% (exit=$EXIT_CODE)"
    fi
}

# ============================================================
# ТЕСТ 3: Некорректное количество файлов (0)
# ============================================================
test_bad_mfiles() {
    print_test_header "3. Kоличество файлов = 0"
    cleanup_env
    sudo echo "test" > "$TEST_DIR/file.txt"

    OUTPUT=$(sudo "$SCRIPT" /log 50 0 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"

    if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qi "положительным"; then
        mark_pass "Скрипт отклонил M=0"
    else
        mark_fail "Скрипт не отклонил M=0"
    fi
}

# ============================================================
# ТЕСТ 4: Размер ниже порога — архивации НЕ должно быть
# ============================================================
test_below_threshold() {
    print_test_header "4. Размер ниже порога"
    cleanup_env

    sudo echo "test" > "$TEST_DIR/file.txt"

    OUTPUT=$(sudo "$SCRIPT" /log 99 5 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"
ARCHIVE_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    if [ $EXIT_CODE -eq 0 ] && [ "$ARCHIVE_COUNT" -eq 0 ] && echo "$OUTPUT" | grep -qi "не требуется"; then
        mark_pass "При размере ниже порога архив не создан"
    else
        mark_fail "Скрипт создал архив при размере ниже порога или упал (exit=$EXIT_CODE)"
    fi
}

# ============================================================
# ТЕСТ 5: Превышение порога — архив создаётся
# ============================================================
test_archivation_created() {
    print_test_header "5. Превышение порога, архив создаётся"
    cleanup_env

    # Создаём файлы через dd (по 1 МБ), чтобы процент был точно больше нуля
    for i in 1 2 3 4 5; do
        sudo dd if=/dev/zero of="$TEST_DIR/file_$i.txt" bs=1M count=1 status=none
    done

    OUTPUT=$(sudo "$SCRIPT" /log 0 3 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"

    ARCHIVE_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    if [ $EXIT_CODE -eq 0 ] && [ "$ARCHIVE_COUNT" -ge 1 ]; then
        mark_pass "Архив создан при превышении порога"
    else
        mark_fail "Архив НЕ создан (exit=$EXIT_CODE, архивов=$ARCHIVE_COUNT)"
    fi
}

# ============================================================
# ТЕСТ 6: Фильтрация самых старых файлов
# ============================================================
test_oldest_filter() {
    print_test_header "6. Фильтрация самых старых файлов"
    cleanup_env

    # Самый старый (1 МБ)
    sudo dd if=/dev/zero of="$TEST_DIR/oldest.txt" bs=1M count=1 status=none
    sudo touch -d "10 days ago" "$TEST_DIR/oldest.txt"

    # Средний (1 МБ)
    sudo dd if=/dev/zero of="$TEST_DIR/medium.txt" bs=1M count=1 status=none
    sudo touch -d "5 days ago" "$TEST_DIR/medium.txt"

    # Новый (1 МБ)
    sudo dd if=/dev/zero of="$TEST_DIR/newest.txt" bs=1M count=1 status=none
    sudo touch "$TEST_DIR/newest.txt"

    # Просим 2 самых старых
    OUTPUT=$(sudo "$SCRIPT" /log 0 2 2>&1)
    echo "Вывод скрипта: $OUTPUT"

    ARCHIVE=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

    if [ -z "$ARCHIVE" ]; then
        mark_fail "Архив не создан — нечего проверять"
        return
    fi

    CONTENT=$(tar -tzf "$ARCHIVE" 2>/dev/null)

    echo "Содержимое архива:"
    echo "$CONTENT"

    HAS_OLDEST=0; HAS_MEDIUM=0; HAS_NEWEST=0
    echo "$CONTENT" | grep -q "oldest.txt" && HAS_OLDEST=1
    echo "$CONTENT" | grep -q "medium.txt" && HAS_MEDIUM=1
    echo "$CONTENT" | grep -q "newest.txt" && HAS_NEWEST=1

    if [ $HAS_OLDEST -eq 1 ] && [ $HAS_MEDIUM -eq 1 ] && [ $HAS_NEWEST -eq 0 ]; then
        mark_pass "В архив попали самые старые файлы (oldest + medium), новый не попал"
    else
        mark_fail "Фильтрация неверная: oldest=$HAS_OLDEST, medium=$HAS_MEDIUM, newest=$HAS_NEWEST"
    fi
}

# ============================================================
# ТЕСТ 7: Архив сохраняется в /backup
# ============================================================
test_archive_location() {
    print_test_header "7. Архив лежит в /backup"
    cleanup_env

    sudo dd if=/dev/zero of="$TEST_DIR/bigfile1.txt" bs=1M count=1 status=none
    sudo dd if=/dev/zero of="$TEST_DIR/bigfile2.txt" bs=1M count=1 status=none
    sudo dd if=/dev/zero of="$TEST_DIR/bigfile3.txt" bs=1M count=1 status=none

    sudo "$SCRIPT" /log 0 2 > /dev/null 2>&1

    if ls -1 /backup/*.tar.gz >/dev/null 2>&1; then
        mark_pass "Архив найден в /backup"
    else
        mark_fail "Архива в /backup нет"
    fi
}

# ============================================================
# ТЕСТ 8: M больше, чем файлов
# ============================================================
test_m_greater_than_files() {
    print_test_header "8. Edge case — M больше, чем файлов"
    cleanup_env


    sudo dd if=/dev/zero of="$TEST_DIR/f1.txt" bs=1M count=1 status=none
    sudo dd if=/dev/zero of="$TEST_DIR/f2.txt" bs=1M count=1 status=none
    
    OUTPUT=$(sudo "$SCRIPT" /log 0 10 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"

    ARCHIVE_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    if [ $EXIT_CODE -eq 0 ] && [ "$ARCHIVE_COUNT" -eq 1 ]; then
        mark_pass "Скрипт не упал, заархивировал имеющиеся файлы"
    else
        mark_fail "Скрипт упал или не создал архив (exit=$EXIT_CODE)"
    fi
}

# ============================================================
# ТЕСТ 9: Пустая папка
# ============================================================
test_empty_dir() {
    print_test_header "9. Пустая папка /log"
    cleanup_env

    OUTPUT=$(sudo "$SCRIPT" /log 0 3 2>&1)
    EXIT_CODE=$?

    echo "Вывод скрипта: $OUTPUT"

    if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -qiE "нет файлов|не требуется|в норме"; then
        mark_pass "Скрипт корректно обработал пустую папку"
    else
        if [ $EXIT_CODE -eq 0 ]; then
            mark_pass "Скрипт завершился без ошибок на пустой папке"
        else
            mark_fail "Скрипт упал на пустой папке (exit=$EXIT_CODE)"
        fi
    fi
}

# ============================================================
# ТЕСТ 10: /backup внутри /log — защита от рекурсии
# ============================================================
test_backup_inside_log() {
    print_test_header "10. /backup внутри /log (защита от рекурсии)"
    cleanup_env

    sudo mkdir -p "$TEST_DIR/backup"
    sudo echo "fake archive content" > "$TEST_DIR/backup/old_archive.tar.gz"
    sudo echo "real log" > "$TEST_DIR/real.log"

    OUTPUT=$(sudo "$SCRIPT" /log 0 5 2>&1)
    echo "Вывод скрипта: $OUTPUT"

    ARCHIVE=$(ls -1 /backup/*.tar.gz 2>/dev/null | head -1)

    if [ -z "$ARCHIVE" ]; then
        mark_pass "Скрипт не упал при вложенном /backup"
        return
    fi

    CONTENT=$(tar -tzf "$ARCHIVE" 2>/dev/null)
    echo "Содержимое архива: $CONTENT"

    if echo "$CONTENT" | grep -q "old_archive.tar.gz"; then
        mark_fail "Скрипт заархивировал сам старый архив (рекурсия!)"
    else
        mark_pass "Скрипт корректно исключил папку backup из поиска"
    fi
}

# ============================================================
# ЗАПУСК ВСЕХ ТЕСТОВ
# ============================================================

echo "======================================================"
echo " ЗАПУСК ТЕСТОВ ДЛЯ log_archiver.sh"
echo "======================================================"

> "$LOG_FILE"

test_nonexistent_dir
test_bad_threshold
test_bad_mfiles
test_below_threshold
test_archivation_created
test_oldest_filter
test_archive_location
test_m_greater_than_files
test_empty_dir
test_backup_inside_log

# ========== Итог ==========
echo ""
echo "======================================================"
TOTAL=$((PASSED + FAILED))
echo -e " ИТОГО: $PASSED прошло из $TOTAL, $FAILED провалено"
echo "======================================================"

if [ $FAILED -eq 0 ]; then
    echo -e "ВСЕ ТЕСТЫ ПРОШЛИ УСПЕШНО!"
    exit 0
else
    echo -e "ЕСТЬ ПРОВАЛЕННЫЕ ТЕСТЫ"
    echo "Полный лог: $LOG_FILE"
    exit 1
fi
