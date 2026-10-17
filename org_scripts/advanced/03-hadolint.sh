#!/usr/bin/env bash
# Задание: Hadolint, правильный Dockerfile и намеренные ошибки.
# Выполняйте команды из корня репозитория: cd ~/docker-workshop
# Для ручного прохождения откройте отдельную Bash-сессию: bash
set -euo pipefail

# 1. Проверяем рабочий каталог и инструменты.
repo_root=$(pwd -P)
if [ ! -f "$repo_root/app/Dockerfile" ] || [ ! -d "$repo_root/org_scripts" ]; then
  printf 'Перейдите в корень docker-workshop и повторите команды.\n' >&2
  exit 1
fi
docker info >/dev/null

# Уже скачанные образы не обновляем. Offline запрещает внешнюю загрузку.
offline=${WORKSHOP_OFFLINE:-0}
case "$offline" in
  0|1) ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# Проверяем кэш базовых образов.
for image_ref in ghcr.io/hadolint/hadolint:v2.15.1; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# Временные файлы удаляются при выходе из этой Bash-сессии.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 2. Правильный пример должен завершиться с кодом 0.
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 < "$repo_root/advanced/hadolint/Dockerfile.good"

# 3. Плохой пример должен вернуть код 1. Это ожидаемый результат задания.
return_code=0
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 \
  < "$repo_root/advanced/hadolint/Dockerfile.bad" > "$work_dir/lint" 2>&1 || return_code=$?
cat "$work_dir/lint"
test "$return_code" = 1
for rule in DL3007 DL3018 DL3019 DL3025; do
  grep -q "$rule" "$work_dir/lint"
done

# 4. Проверяем Dockerfile из задания multistage.
docker run --rm -i ghcr.io/hadolint/hadolint:v2.15.1 < "$repo_root/advanced/multistage/Dockerfile"
rm -rf -- "$work_dir"
printf 'Готово: хорошие примеры прошли проверку, ожидаемые ошибки найдены.\n'
