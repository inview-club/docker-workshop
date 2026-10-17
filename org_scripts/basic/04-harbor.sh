#!/usr/bin/env bash
# Задание 4: Harbor, база Trivy, проект, push/pull и завершённый отчёт.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need python3
compose_init
build_app
helper="$WORKSHOP_ROOT/org_scripts/lib/harbor.py"
cd "$WORKSHOP_ROOT/harbor"
step 'Проверяем образы Harbor; уже скачанные образы не обновляем'
image goharbor/prepare:v2.14.0
while read -r ref; do image "$ref"; done < <(awk '$1 == "image:" {print $2}' compose.yaml)
step 'Создаём конфигурацию и ключи Harbor'
bash prepare.sh
HARBOR_COMPOSE=("${COMPOSE[@]}" -p harbor-lab -f compose.yaml)
if [[ "$OFFLINE" == 1 ]]; then
  cat > "$TASK_TMP/offline.yaml" <<'YAML'
services:
  trivy-adapter:
    environment:
      SCANNER_TRIVY_SKIP_UPDATE: "true"
      SCANNER_TRIVY_SKIP_JAVA_DB_UPDATE: "true"
      SCANNER_TRIVY_OFFLINE_SCAN: "true"
YAML
  HARBOR_COMPOSE+=(-f "$TASK_TMP/offline.yaml")
fi
step 'Запускаем Harbor и дожидаемся общего статуса healthy'
"${HARBOR_COMPOSE[@]}" up -d --pull never
"${HARBOR_COMPOSE[@]}" ps
python3 "$helper" health
step 'Готовим базу Trivy'
if [[ "$OFFLINE" == 0 ]]; then
  "${HARBOR_COMPOSE[@]}" exec -T trivy-adapter trivy image --download-db-only \
    --timeout 30m --cache-dir /home/scanner/.cache/trivy
fi
"${HARBOR_COMPOSE[@]}" exec -T trivy-adapter sh -ec \
  'test -s /home/scanner/.cache/trivy/db/trivy.db && test -s /home/scanner/.cache/trivy/db/metadata.json' \
  || fail 'База Trivy не готова. Повторите скрипт с WORKSHOP_OFFLINE=0 заранее при хорошем интернете.'
step 'Создаём приватный проект club и включаем автоматическое сканирование'
python3 "$helper" project
step 'Публикуем образ, проверяем pull и дожидаемся отчёта Trivy'
python3 "$helper" publish
step 'Готово: http://localhost:8081, проект club, образ counter:1.0 и отчёт Trivy'
printf 'Harbor и его данные оставлены для просмотра. Остановка: cd "%s/harbor" && docker compose down\n' "$WORKSHOP_ROOT"
