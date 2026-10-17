#!/usr/bin/env bash
# Задание: сборка в несколько этапов и сравнение размеров.
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
for image_ref in golang:1.24.6-alpine; do
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
container_name=org-workshop-multistage
if docker container inspect "$container_name" >/dev/null 2>&1; then
  owner=$(docker container inspect --format "$owner_format" "$container_name")
  if [ "$owner" != org-scripts ]; then
    printf 'Контейнер %s создан вне этих скриптов. Не удаляю его.\n' "$container_name" >&2
    exit 1
  fi
  docker rm -f "$container_name"
fi

# При ошибке также убираем свой контейнер. Чужой ресурс не удаляем.
trap '
  if [ "$(docker container inspect --format "$owner_format" "$container_name" 2>/dev/null)" = org-scripts ]; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 2. Читаем Dockerfile и собираем два образа. Кэш сборки сохраняется.
cat "$repo_root/advanced/multistage/Dockerfile"
docker build --pull=false --network="$build_network" --target build \
  -t club-advanced-build:1.0 "$repo_root/advanced/multistage"
docker build --pull=false --network="$build_network" \
  -t club-advanced:1.0 "$repo_root/advanced/multistage"

# 3. Запускаем итоговый образ и проверяем HTTP и UID.
docker run -d --label org.inview.workshop=org-scripts --name "$container_name" \
  -p 127.0.0.1:8080:8080 club-advanced:1.0
response=$(curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/)
printf '%s\n' "$response"
test "$response" = 'Hello from multistage! UID=10001'

# 4. Сравниваем размеры в байтах. Удаляем контейнер, оба образа остаются.
docker image inspect club-advanced-build:1.0 club-advanced:1.0 --format '{{index .RepoTags 0}} {{.Size}}'
docker rm -f "$container_name"
printf 'Готово: итоговый образ отвечает, UID равен 10001.\n'
