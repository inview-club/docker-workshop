#!/usr/bin/env bash
# Задание 1: nginx — запуск, проверка, остановка и удаление.
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
case "$offline" in
  0|1) ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# Проверяем кэш базовых образов.
for image_ref in nginx:stable; do
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
container_name=org-workshop-nginx
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

# 2. Запускаем nginx. При ручном прохождении откройте http://127.0.0.1:8080.
docker run -d --label org.inview.workshop=org-scripts --name "$container_name" \
  -p 127.0.0.1:8080:80 nginx:stable

# 3. Дожидаемся HTTP-ответа, смотрим статус, журнал и конфигурацию.
curl --noproxy '*' -fsS --retry 30 --retry-connrefused --retry-delay 2 \
  --retry-max-time 120 --connect-timeout 2 --max-time 5 http://127.0.0.1:8080
docker ps --filter "name=^/${container_name}$"
docker logs "$container_name"
docker exec "$container_name" nginx -t

# 4. Останавливаем контейнер, находим его в списке и удаляем.
docker stop "$container_name"
docker ps -a --filter "name=^/${container_name}$"
docker rm "$container_name"

# 5. Проверяем, что образ остался в кэше.
docker image inspect nginx:stable >/dev/null
printf 'Готово: контейнер удалён, образ nginx сохранён.\n'
