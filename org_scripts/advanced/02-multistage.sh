#!/usr/bin/env bash
# Задание: сборка в несколько этапов, HTTP и сравнение размеров.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need curl
image golang:1.24.6-alpine
name=org-workshop-multistage
cleanup_task() { remove_container "$name"; }
cat "$WORKSHOP_ROOT/advanced/multistage/Dockerfile"
docker build --pull=false --network="$BUILD_NETWORK" --target build -t club-advanced-build:1.0 "$WORKSHOP_ROOT/advanced/multistage"
docker build --pull=false --network="$BUILD_NETWORK" -t club-advanced:1.0 "$WORKSHOP_ROOT/advanced/multistage"
run_container "$name" -d -p 127.0.0.1:8080:8080 club-advanced:1.0
[[ "$(wait_http http://127.0.0.1:8080/)" == 'Hello from multistage! UID=10001' ]] || fail 'Неверный ответ приложения.'
docker image inspect club-advanced-build:1.0 club-advanced:1.0 --format '{{index .RepoTags 0}} {{.Size}}'
step 'Готово: HTTP и UID проверены. Размеры выше указаны в байтах'
