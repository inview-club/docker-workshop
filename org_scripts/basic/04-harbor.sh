#!/usr/bin/env bash
# Подготовка Harbor: сервисы, Trivy и загруженная база.
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
command -v python3 >/dev/null

# Уже скачанные образы не обновляем. Offline запрещает внешнюю загрузку.
offline=${WORKSHOP_OFFLINE:-0}
case "$offline" in
  0|1) ;;
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

# 2. Проверяем образы подготовки и всех сервисов Harbor.
cd "$repo_root/harbor"
# В compose.yaml перечислены образы всех сервисов; уже скачанные не обновляем.
image_refs=$(awk '$1 == "image:" {print $2}' compose.yaml)
for image_ref in goharbor/prepare:v2.14.0 $image_refs; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# 3. Подготавливаем конфигурацию и ключи: те же шаги, что в harbor/prepare.sh.
export HARBOR_LAB_ROOT="$(pwd -P)"
if [ ! -f .env ]; then
  cp .env.example .env
fi
mkdir -p runtime/input runtime/data runtime/log runtime/common/config
"${compose[@]}" --env-file .env -p harbor-lab-prepare -f prepare.compose.yaml run --rm prepare

# Временные файлы удаляются при выходе из этой Bash-сессии.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 4. В offline отключаем сетевые обновления Trivy через временный override.
compose_files=(-f compose.yaml)
if [ "$offline" = 1 ]; then
  cat > "$work_dir/offline.yaml" <<'YAML'
services:
  trivy-adapter:
    environment:
      SCANNER_TRIVY_SKIP_UPDATE: "true"
      SCANNER_TRIVY_SKIP_JAVA_DB_UPDATE: "true"
      SCANNER_TRIVY_OFFLINE_SCAN: "true"
YAML
  compose_files+=(-f "$work_dir/offline.yaml")
fi

# 5. Запускаем сервисы и дожидаемся общего статуса healthy (до 10 минут).
"${compose[@]}" -p harbor-lab "${compose_files[@]}" up -d --pull never
"${compose[@]}" -p harbor-lab "${compose_files[@]}" ps
ready=0
health_deadline=$((SECONDS + 600))
for attempt in {1..120}; do
  if [ "$SECONDS" -ge "$health_deadline" ]; then break; fi
  if curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 \
      http://localhost:8081/api/v2.0/health 2>/dev/null \
      | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("status") == "healthy" else 1)' 2>/dev/null; then
    ready=1
    break
  fi
  sleep 5
done
if [ "$ready" != 1 ]; then
  printf 'Harbor не стал healthy. Проверьте docker compose logs в harbor/.\n' >&2
  exit 1
fi

# 6. При доступном интернете скачиваем базу Trivy. В offline используем сохранённую.
if [ "$offline" = 0 ]; then
  "${compose[@]}" -p harbor-lab "${compose_files[@]}" exec -T trivy-adapter \
    trivy image --download-db-only --timeout 30m --cache-dir /home/scanner/.cache/trivy
fi
"${compose[@]}" -p harbor-lab "${compose_files[@]}" exec -T trivy-adapter sh -ec \
  'test -s /home/scanner/.cache/trivy/db/trivy.db && test -s /home/scanner/.cache/trivy/db/metadata.json' \
  || { printf 'База Trivy не готова. Загрузите её до занятия с WORKSHOP_OFFLINE=0.\n' >&2; exit 1; }

# 7. Убираем временный файл. Harbor, его данные и база Trivy остаются.
rm -rf -- "$work_dir"
printf 'Готово: Harbor с Trivy запущен, база загружена. http://localhost:8081\n'
# Проекты Harbor, авторизацию, push/pull и сканирование здесь не выполняем.
# Остановка стенда после занятия: docker compose down (из каталога harbor/).
