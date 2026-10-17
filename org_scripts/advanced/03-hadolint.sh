#!/usr/bin/env bash
# Задание: сравнение правильного Dockerfile и файла с намеренными ошибками.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
image ghcr.io/hadolint/hadolint:v2.15.1
step 'Проверяем правильный Dockerfile: ожидаем код 0'
bash "$WORKSHOP_ROOT/advanced/hadolint/lint.sh" Dockerfile.good
step 'Проверяем файл с ошибками: ожидаем ненулевой код'
rc=0
bash "$WORKSHOP_ROOT/advanced/hadolint/lint.sh" Dockerfile.bad > "$TASK_TMP/lint" 2>&1 || rc=$?
cat "$TASK_TMP/lint"
[[ "$rc" == 1 ]] || fail "Ожидался код Hadolint 1, получен $rc."
for rule in DL3007 DL3018 DL3019 DL3025; do
  grep -q "$rule" "$TASK_TMP/lint" || fail "В отчёте нет $rule."
done
step 'Проверяем рабочий Dockerfile из задания multistage'
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 < "$WORKSHOP_ROOT/advanced/multistage/Dockerfile"
step 'Готово: ошибки плохого примера подтверждены, хорошие примеры прошли проверку'
