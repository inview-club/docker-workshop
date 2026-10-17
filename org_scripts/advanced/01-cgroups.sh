#!/usr/bin/env bash
# Задание: namespaces и ограничения cgroups v2.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
image python:3.12-slim
bash "$WORKSHOP_ROOT/advanced/cgroups/demo.sh" | tee "$TASK_TMP/result"
grep -qx '50000 100000' "$TASK_TMP/result" || fail 'Не найдена ожидаемая квота CPU.'
grep -qx 67108864 "$TASK_TMP/result" || fail 'Не найден лимит памяти 64 МиБ.'
grep -qx 64 "$TASK_TMP/result" || fail 'Не найден лимит 64 PID.'
step 'Готово: ограничения проверены, контейнер удалён, образ сохранён'
