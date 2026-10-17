#!/usr/bin/env bash
# Задание: том, запись и чтение из разных контейнеров.
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
build_network=default
case "$offline" in
  0) ;;
  1) build_network=none ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# Проверяем кэш базовых образов.
for image_ref in alpine:3.21; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# 2. Собираем образ с /data/seed.txt.
docker build --pull=false --network="$build_network" \
  -t club-volume-demo:1.0 "$repo_root/advanced/volumes"

# 3. Проверяем владельца тома, если он остался после прежнего запуска.
owner_format='{{index .Labels "org.inview.workshop"}}'
volume_name=org-workshop-volumes
if docker volume inspect "$volume_name" >/dev/null 2>&1; then
  owner=$(docker volume inspect --format "$owner_format" "$volume_name")
  if [ "$owner" != org-scripts ]; then
    printf 'Том %s создан вне этих скриптов. Не изменяю его.\n' "$volume_name" >&2
    exit 1
  fi
fi
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap '
  if [ "$(docker volume inspect --format "$owner_format" "$volume_name" 2>/dev/null)" = org-scripts ]; then
    docker volume rm "$volume_name" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$work_dir"
' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker volume create --label org.inview.workshop=org-scripts "$volume_name"

# 4. Проверяем копирование seed.txt из образа в пустой том.
docker run --rm --mount "type=volume,src=$volume_name,dst=/data" \
  club-volume-demo:1.0 > "$work_dir/seed"
cmp "$repo_root/advanced/volumes/seed.txt" "$work_dir/seed"

# 5. Первый контейнер пишет файл и удаляется (--rm).
docker run --rm --mount "type=volume,src=$volume_name,dst=/data" club-volume-demo:1.0 \
  sh -c 'echo "written by container 1" > /data/result.txt'

# 6. Второй контейнер читает тот же том, подключённый только для чтения.
response=$(docker run --rm --mount "type=volume,src=$volume_name,dst=/data,readonly" \
  club-volume-demo:1.0 cat /data/result.txt)
printf '%s\n' "$response"
test "$response" = 'written by container 1'
docker volume inspect "$volume_name"

# 7. Удаляем только учебный том и временные файлы. Образ остаётся.
docker volume rm "$volume_name"
rm -rf -- "$work_dir"
printf 'Готово: данные пережили удаление первого контейнера.\n'
