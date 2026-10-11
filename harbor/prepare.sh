#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export HARBOR_LAB_ROOT="$(pwd -P)"
docker info >/dev/null
if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
  compose_cmd=(docker-compose)
else
  printf 'Не найден Docker Compose: установите docker compose или docker-compose.\n' >&2
  exit 1
fi
if [[ ! -f .env ]]; then
  cp .env.example .env
fi
# Сохранённые данные и ключи остаются в runtime между запусками.
mkdir -p runtime/input runtime/data runtime/log runtime/common/config
"${compose_cmd[@]}" --env-file .env -p harbor-lab-prepare -f prepare.compose.yaml run --rm prepare
printf '\nКонфигурация готова. Запуск: %s up -d\n' "${compose_cmd[*]}"
