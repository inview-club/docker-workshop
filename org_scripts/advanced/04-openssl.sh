#!/usr/bin/env bash
# Задание: локальная подпись архива через OpenSSL.
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
command -v openssl >/dev/null

# Уже скачанные образы не обновляем. Offline запрещает внешнюю загрузку.
offline=${WORKSHOP_OFFLINE:-0}
build_network=default
case "$offline" in
  0) ;;
  1) build_network=none ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# 2. Если образ ещё не собран, подготавливаем его здесь же.
if ! docker image inspect club-advanced:1.0 >/dev/null 2>&1; then

# Проверяем кэш базовых образов.
for image_ref in golang:1.24.6-alpine; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done
  docker build --pull=false --network="$build_network" \
    -t club-advanced:1.0 "$repo_root/advanced/multistage"
fi

# Временные файлы удаляются при выходе из этой Bash-сессии.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap 'unset WORKSHOP_KEY_PASSWORD; rm -rf -- "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 3. Сохраняем образ и создаём зашифрованный закрытый ключ.
umask 077
cd "$work_dir"
WORKSHOP_KEY_PASSWORD=$(openssl rand -base64 32)
export WORKSHOP_KEY_PASSWORD
# Пароль не выводится и не передаётся в аргументах команды.
docker save -o image.tar club-advanced:1.0
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -aes-256-cbc \
  -pass env:WORKSHOP_KEY_PASSWORD -out signing.key
openssl pkey -in signing.key -passin env:WORKSHOP_KEY_PASSWORD -pubout -out signing.pub

# 4. Подписываем архив и проверяем подпись. Ожидается Verified OK.
openssl dgst -sha256 -sign signing.key -passin env:WORKSHOP_KEY_PASSWORD -out image.tar.sig image.tar
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig image.tar
# Загружаем только исходный архив с проверенной подписью.
docker load -i image.tar

# 5. Меняем копию. Проверка должна завершиться ошибкой.
cp image.tar tampered.tar
printf '\nchanged\n' >> tampered.tar
if openssl dgst -sha256 -verify signing.pub -signature image.tar.sig tampered.tar; then
  printf 'Ошибка: изменённый архив неожиданно прошёл проверку.\n' >&2
  exit 1
fi
# Исходный архив по-прежнему должен пройти проверку.
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig image.tar

# 6. Удаляем временные архивы, ключи и пароль. Образ Docker остаётся.
unset WORKSHOP_KEY_PASSWORD
cd "$repo_root"
rm -rf -- "$work_dir"
printf 'Готово: подпись проверена, изменение обнаружено.\n'
