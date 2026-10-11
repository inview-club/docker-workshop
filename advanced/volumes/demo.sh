#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Уникальное имя: не используем и не удаляем чужие volumes.
volume="club-volume-$(date +%Y%m%d%H%M%S)-$$"
image="club-volume-demo:1.0"
docker build -t "$image" .
docker volume create "$volume" >/dev/null
printf 'Учебный volume: %s\n' "$volume"
# Пустой volume получает seed.txt из /data образа при первом монтировании.
docker run --rm --mount "type=volume,src=$volume,dst=/data" "$image"
# Первый контейнер записывает данные и затем удаляется (--rm).
docker run --rm --mount "type=volume,src=$volume,dst=/data" "$image" \
  sh -c 'echo "written by container 1" > /data/result.txt'
# Второй контейнер читает сохранённый файл, подключив volume только для чтения.
docker run --rm --mount "type=volume,src=$volume,dst=/data,readonly" "$image" \
  cat /data/result.txt
docker volume inspect "$volume"
printf '\nVolume оставлен для проверки. Когда закончите: docker volume rm %s\n' "$volume"
