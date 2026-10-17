#!/usr/bin/env bash
# Задание 1: запуск, проверка, остановка и удаление контейнера nginx.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need curl
name=org-workshop-nginx
cleanup_task() { remove_container "$name"; }
image nginx:stable
step 'Запускаем nginx: http://127.0.0.1:8080'
run_container "$name" -d -p 127.0.0.1:8080:80 nginx:stable
wait_http http://127.0.0.1:8080
step 'Проверяем статус, журнал и конфигурацию'
docker ps --filter "name=^/${name}$"
docker logs "$name"
docker exec "$name" nginx -t
step 'Останавливаем контейнер и показываем его в списке'
docker stop "$name"
docker ps -a --filter "name=^/${name}$"
remove_container "$name"
docker image inspect nginx:stable >/dev/null
step 'Готово: контейнер удалён, образ nginx сохранён'
