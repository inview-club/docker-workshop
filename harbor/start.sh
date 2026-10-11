#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash prepare.sh
if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
else
  compose_cmd=(docker-compose)
fi
"${compose_cmd[@]}" -p harbor-lab up -d
"${compose_cmd[@]}" -p harbor-lab ps
printf '\nПортал: http://localhost:8081\nПроверка: curl -fsS http://localhost:8081/api/v2.0/health\n'
