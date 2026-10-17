#!/usr/bin/env bash
# Задание 3: приложение, Redis и проверка сохранения счётчика.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need curl
compose_init
build_app
image redis:7.4-alpine
cd "$WORKSHOP_ROOT/app"
app_compose() { "${COMPOSE[@]}" -p org-workshop-app -f compose.yaml "$@"; }
started=0
cleanup_task() { if [[ "$started" == 1 ]]; then app_compose down; fi; }
step 'Проверяем Compose и запускаем сервисы'
app_compose config --quiet
started=1
app_compose up -d --no-build --pull never
app_compose ps
[[ "$(wait_http http://127.0.0.1:8080/)" == *'"redis"'* ]] || fail 'Ожидался Redis.'
wait_http http://127.0.0.1:8080/
before=$(app_compose exec -T redis redis-cli GET visits | tr -d '\r')
[[ "$before" =~ ^[0-9]+$ ]] || fail 'Redis не вернул число посещений.'
step 'Пересоздаём сервисы без удаления тома'
app_compose down
app_compose up -d --no-build --pull never
[[ "$(wait_http http://127.0.0.1:8080/)" == *'"redis"'* ]] || fail 'После перезапуска нет Redis.'
after=$(app_compose exec -T redis redis-cli GET visits | tr -d '\r')
[[ "$after" =~ ^[0-9]+$ ]] || fail 'Redis не вернул число посещений.'
(( after > before )) || fail 'Счётчик не сохранился после пересоздания контейнеров.'
printf 'Готово: счётчик до %s, после %s. Том и образы сохраняются.\n' "$before" "$after"
