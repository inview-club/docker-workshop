#!/usr/bin/env bash
# Задание: экспорт, зашифрованный ключ, подпись, проверка и обнаружение изменения.
source "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"
init
need openssl
if ! docker image inspect club-advanced:1.0 >/dev/null 2>&1; then
  image golang:1.24.6-alpine
  docker build --pull=false --network="$BUILD_NETWORK" -t club-advanced:1.0 "$WORKSHOP_ROOT/advanced/multistage"
fi
umask 077
cd "$TASK_TMP"
# Случайный пароль живёт только в env этого процесса и не выводится в журнал.
WORKSHOP_KEY_PASSWORD=$(openssl rand -base64 32)
export WORKSHOP_KEY_PASSWORD
cleanup_task() { unset WORKSHOP_KEY_PASSWORD; }
docker save -o image.tar club-advanced:1.0
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -aes-256-cbc \
  -pass env:WORKSHOP_KEY_PASSWORD -out signing.key
openssl pkey -in signing.key -passin env:WORKSHOP_KEY_PASSWORD -pubout -out signing.pub
openssl dgst -sha256 -sign signing.key -passin env:WORKSHOP_KEY_PASSWORD -out image.tar.sig image.tar
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig image.tar
step 'Загружаем только архив с проверенной подписью'
docker load -i image.tar
cp image.tar tampered.tar
printf '\nchanged\n' >> tampered.tar
if openssl dgst -sha256 -verify signing.pub -signature image.tar.sig tampered.tar; then
  fail 'Изменённый архив неожиданно прошёл проверку.'
fi
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig image.tar
step 'Готово: изменение обнаружено. Временные архивы, ключ и пароль будут удалены'
