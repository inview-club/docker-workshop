#!/usr/bin/env bash
# Задание 2: Dockerfile, UID, HTTP и кэш повторной сборки.
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
command -v curl >/dev/null

# Уже скачанные образы не обновляем. Offline запрещает внешнюю загрузку.
offline=${WORKSHOP_OFFLINE:-0}
build_network=default
case "$offline" in
  0) ;;
  1) build_network=none ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# Проверяем кэш базовых образов.
for image_ref in python:3.12-slim; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# При повторном запуске удаляем только свой прежний учебный контейнер.
owner_format='{{index .Config.Labels "org.inview.workshop"}}'
container_name=org-workshop-counter
if docker container inspect "$container_name" >/dev/null 2>&1; then
  owner=$(docker container inspect --format "$owner_format" "$container_name")
  if [ "$owner" != org-scripts ]; then
    printf 'Контейнер %s создан вне этих скриптов. Не удаляю его.\n' "$container_name" >&2
    exit 1
  fi
  docker rm -f "$container_name"
fi

# При ошибке также убираем свой контейнер. Чужой ресурс не удаляем.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap '
  if [ "$(docker container inspect --format "$owner_format" "$container_name" 2>/dev/null)" = org-scripts ]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$work_dir"
' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 2. Читаем Dockerfile, собираем образ и проверяем пользователя.
cat "$repo_root/app/Dockerfile"

# В offline используем ранее собранное приложение. Иначе собираем с кэшем.
if [ "$offline" != 1 ] || ! docker image inspect club-demo:1.0 >/dev/null 2>&1; then
  docker build --pull=false --network="$build_network" -t club-demo:1.0 "$repo_root/app"
fi
test "$(docker run --rm club-demo:1.0 id -u)" = 10001

# 3. Запускаем приложение и проверяем ответы.
docker run -d --label org.inview.workshop=org-scripts --name "$container_name" \
  -p 127.0.0.1:8080:8080 club-demo:1.0
response=$(curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/health)
printf '%s\n' "$response"
[[ "$response" == *'"ok"'* ]]
response=$(curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/)
printf '%s\n' "$response"
[[ "$response" == *'"memory"'* ]]
docker history club-demo:1.0

# 4. Меняем только временную копию исходника. Оригинал остаётся прежним.
cp "$repo_root/app/Dockerfile" "$repo_root/app/requirements.txt" "$repo_root/app/app.py" "$work_dir/"
printf '\n# Изменение для проверки кэша сборки.\n' >> "$work_dir/app.py"
docker build --pull=false --network="$build_network" -t club-demo:cache-demo "$work_dir"
# Изучите CACHED/Using cache в выводе сборки.

# 5. Освобождаем порт и удаляем временные файлы. Образы остаются.
docker rm -f "$container_name"
rm -rf -- "$work_dir"
printf 'Готово: HTTP и UID проверены, оба образа сохранены.\n'
