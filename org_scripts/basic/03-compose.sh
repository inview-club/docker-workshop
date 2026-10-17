#!/usr/bin/env bash
# Задание 3: Compose, Redis и сохранение счётчика.
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

# Выбираем установленную команду Compose v2.
if docker compose version >/dev/null 2>&1; then
  compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version --short | grep -Eq '^v?2\.'; then
  compose=(docker-compose)
else
  printf 'Установите Docker Compose v2.\n' >&2
  exit 1
fi

# Проверяем кэш базовых образов.
for image_ref in python:3.12-slim redis:7.4-alpine; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# В offline используем ранее собранное приложение. Иначе собираем с кэшем.
if [ "$offline" != 1 ] || ! docker image inspect club-demo:1.0 >/dev/null 2>&1; then
  docker build --pull=false --network="$build_network" -t club-demo:1.0 "$repo_root/app"
fi

# 2. Работаем с отдельным учебным проектом Compose.
cd "$repo_root/app"
"${compose[@]}" -p org-workshop-app -f compose.yaml config --quiet
trap '"${compose[@]}" -p org-workshop-app -f compose.yaml down' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"${compose[@]}" -p org-workshop-app -f compose.yaml up -d --no-build --pull never
"${compose[@]}" -p org-workshop-app -f compose.yaml ps

# 3. Обращаемся к приложению и читаем счётчик в Redis.
response=$(curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/)
printf '%s\n' "$response"
[[ "$response" == *'"redis"'* ]]
curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/
before=$("${compose[@]}" -p org-workshop-app -f compose.yaml exec -T redis redis-cli GET visits | tr -d '\r')
[[ "$before" =~ ^[0-9]+$ ]]

# 4. Пересоздаём контейнеры. Не добавляйте -v: том должен сохраниться.
"${compose[@]}" -p org-workshop-app -f compose.yaml down
"${compose[@]}" -p org-workshop-app -f compose.yaml up -d --no-build --pull never
response=$(curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/)
printf '%s\n' "$response"
[[ "$response" == *'"redis"'* ]]
after=$("${compose[@]}" -p org-workshop-app -f compose.yaml exec -T redis redis-cli GET visits | tr -d '\r')
[[ "$after" =~ ^[0-9]+$ ]]
test "$after" -gt "$before"
printf 'Счётчик до: %s, после: %s.\n' "$before" "$after"

# 5. Останавливаем сервисы. Том Redis и образы остаются.
"${compose[@]}" -p org-workshop-app -f compose.yaml down
printf 'Готово: счётчик пережил пересоздание контейнеров.\n'
