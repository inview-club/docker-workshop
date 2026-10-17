#!/usr/bin/env bash
# Задание 2: сборка, пользователь, HTTP и повторная сборка с кэшем.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need curl
name=org-workshop-counter
cleanup_task() { remove_container "$name"; }
step 'Изучаем Dockerfile и собираем приложение'
cat "$WORKSHOP_ROOT/app/Dockerfile"
build_app
[[ "$(docker run --rm club-demo:1.0 id -u)" == 10001 ]] || fail 'Ожидался UID 10001.'
run_container "$name" -d -p 127.0.0.1:8080:8080 club-demo:1.0
[[ "$(wait_http http://127.0.0.1:8080/health)" == *'"ok"'* ]] || fail 'Неверный ответ /health.'
[[ "$(wait_http http://127.0.0.1:8080/)" == *'"memory"'* ]] || fail 'Ожидался счётчик в памяти.'
docker history club-demo:1.0
step 'Меняем только временную копию app.py и проверяем повторную сборку'
cp "$WORKSHOP_ROOT/app/"{Dockerfile,requirements.txt,app.py} "$TASK_TMP/"
printf '\n# Изменение для проверки кэша сборки.\n' >> "$TASK_TMP/app.py"
docker build --pull=false --network="$BUILD_NETWORK" -t club-demo:cache-demo "$TASK_TMP"
step 'Готово: изучите CACHED/Using cache в выводе. Оба образа сохранены'
