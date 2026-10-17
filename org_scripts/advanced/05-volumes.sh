#!/usr/bin/env bash
# Задание: заполнение тома, запись и чтение из другого контейнера.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
image alpine:3.21
docker build --pull=false --network="$BUILD_NETWORK" -t club-volume-demo:1.0 "$WORKSHOP_ROOT/advanced/volumes"
volume=org-workshop-volumes
owned_volume=0
cleanup_task() { if [[ "$owned_volume" == 1 ]]; then docker volume rm "$volume" >/dev/null; fi; }
if docker volume inspect "$volume" >/dev/null 2>&1; then
  [[ "$(docker volume inspect --format '{{index .Labels "org.inview.workshop"}}' "$volume")" == org-scripts ]] || fail "Том $volume создан вне этих скриптов."
fi
docker volume create --label org.inview.workshop=org-scripts "$volume" >/dev/null
owned_volume=1
step 'Проверяем копирование seed.txt из образа в том'
docker run --rm --mount "type=volume,src=$volume,dst=/data" club-volume-demo:1.0 > "$TASK_TMP/seed"
cmp "$WORKSHOP_ROOT/advanced/volumes/seed.txt" "$TASK_TMP/seed"
step 'Первый контейнер записывает файл и удаляется'
docker run --rm --mount "type=volume,src=$volume,dst=/data" club-volume-demo:1.0 \
  sh -c 'echo "written by container 1" > /data/result.txt'
step 'Второй контейнер читает том, подключённый только для чтения'
result=$(docker run --rm --mount "type=volume,src=$volume,dst=/data,readonly" club-volume-demo:1.0 cat /data/result.txt)
[[ "$result" == 'written by container 1' ]] || fail 'Сохранённый файл не совпал.'
docker volume inspect "$volume"
step 'Готово: файл пережил удаление контейнера. Учебный том будет удалён, образ останется'
