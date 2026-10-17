#!/usr/bin/env bash
# Общие функции. Этот файл не является отдельным заданием.
set -euo pipefail
WORKSHOP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
STATE="$WORKSHOP_ROOT/org_scripts/.state"
OFFLINE="${WORKSHOP_OFFLINE:-0}"
BUILD_NETWORK=default
TASK_TMP=''
LOCKED=0
COMPOSE=()
fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
step() { printf '\n>>> %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Установите $1 и повторите запуск."; }
cleanup_task() { :; }
finish() {
  local rc=$?
  set +e
  trap - EXIT
  cleanup_task || rc=1
  if [[ -n "$TASK_TMP" ]]; then rm -rf -- "$TASK_TMP"; fi
  if [[ "$LOCKED" == 1 ]]; then rmdir "$STATE/task.lock" || rc=1; fi
  if [[ "$rc" != 0 ]]; then printf 'Задание не завершено (код %s). Кэш образов сохранён.\n' "$rc" >&2; fi
  exit "$rc"
}
init() {
  need docker
  docker info >/dev/null 2>&1 || fail 'Запустите Docker Desktop, Colima или Docker Engine.'
  [[ "$OFFLINE" == 0 || "$OFFLINE" == 1 ]] || fail 'WORKSHOP_OFFLINE должен быть 0 или 1.'
  if [[ "$OFFLINE" == 1 ]]; then BUILD_NETWORK=none; fi
  mkdir -p "$STATE"
  mkdir "$STATE/task.lock" 2>/dev/null || fail "Другое задание уже работает. Если оно прервалось аварийно, проверьте процессы и удалите $STATE/task.lock."
  LOCKED=1
  trap finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")"
}
compose_init() {
  if docker compose version >/dev/null 2>&1; then COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1 && docker-compose version --short | grep -Eq '^v?2\.'; then COMPOSE=(docker-compose)
  else fail 'Установите Docker Compose v2.'; fi
}
image() {
  if docker image inspect "$1" >/dev/null 2>&1; then
    printf 'Используем локальный образ: %s\n' "$1"
  elif [[ "$OFFLINE" == 1 ]]; then
    fail "В кэше нет $1. Заранее выполните docker pull $1 при доступном интернете."
  else
    docker pull "$1"
  fi
}
build_app() {
  image python:3.12-slim
  if [[ "$OFFLINE" == 1 ]] && docker image inspect club-demo:1.0 >/dev/null 2>&1; then
    step 'Используем ранее собранный club-demo:1.0'
  else
    docker build --pull=false --network="$BUILD_NETWORK" -t club-demo:1.0 "$WORKSHOP_ROOT/app"
  fi
}
wait_http() {
  local url=$1 tries=${2:-60} body i
  for ((i=0; i<tries; i++)); do
    if body=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "$url" 2>/dev/null); then
      printf '%s\n' "$body"; return 0
    fi
    sleep 2
  done
  fail "Нет успешного HTTP-ответа от $url. Проверьте журналы контейнера."
}
remove_container() {
  local name=$1 owner
  if docker container inspect "$name" >/dev/null 2>&1; then
    owner=$(docker container inspect --format '{{index .Config.Labels "org.inview.workshop"}}' "$name")
    if [[ "$owner" != org-scripts ]]; then
      printf "Контейнер %s создан вне этих скриптов. Не удаляю его.\n" "$name" >&2
      return 1
    fi
    docker rm -f "$name" >/dev/null
  fi
}
run_container() {
  local name=$1; shift
  remove_container "$name" || fail "Имя $name занято чужим контейнером."
  docker run --label org.inview.workshop=org-scripts --name "$name" "$@"
}
