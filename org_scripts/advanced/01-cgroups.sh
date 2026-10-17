#!/usr/bin/env bash
# Задание: namespaces и ограничения cgroups v2.
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

# Уже скачанные образы не обновляем. Offline запрещает внешнюю загрузку.
offline=${WORKSHOP_OFFLINE:-0}
case "$offline" in
  0|1) ;;
  *) printf 'WORKSHOP_OFFLINE должен быть 0 или 1.\n' >&2; exit 1 ;;
esac

# Проверяем кэш базовых образов.
for image_ref in python:3.12-slim; do
  if ! docker image inspect "$image_ref" >/dev/null 2>&1; then
    if [ "$offline" = 1 ]; then
      printf 'В кэше нет %s. Загрузите образ до занятия.\n' "$image_ref" >&2
      exit 1
    fi
    docker pull "$image_ref"
  fi
done

# Временные файлы удаляются при выходе из этой Bash-сессии.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-workshop.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 2. Запускаем контейнер с лимитами ресурсов и читаем настройки Linux.
# Контейнер удалится сам (--rm). Изменения cgroups хоста не требуются.
docker run --rm --cpus=0.5 --memory=64m --memory-swap=64m --pids-limit=64 \
  python:3.12-slim sh -ec '
    test -f /sys/fs/cgroup/cgroup.controllers || {
      echo "Этот пример требует cgroups v2." >&2; exit 1;
    }
    echo "=== Namespace процесса PID 1 ==="
    ls -l /proc/1/ns
    echo "=== CPU quota / period (microseconds) ==="
    cat /sys/fs/cgroup/cpu.max
    echo "=== Memory limit (bytes) ==="
    cat /sys/fs/cgroup/memory.max
    echo "=== PIDs limit ==="
    cat /sys/fs/cgroup/pids.max
    echo "=== Нагрузка CPU в течение двух секунд ==="
    python -c "import time; end=time.monotonic()+2; n=0
while time.monotonic()<end: n+=1
print(n)"
    echo "=== Учёт CPU и throttling ==="
    cat /sys/fs/cgroup/cpu.stat
  ' | tee "$work_dir/result"

# 3. Проверяем квоту CPU, 64 МиБ памяти и лимит 64 PID.
grep -qx '50000 100000' "$work_dir/result"
grep -qx 67108864 "$work_dir/result"
grep -qx 64 "$work_dir/result"
rm -rf -- "$work_dir"
printf 'Готово: ограничения проверены, образ сохранён.\n'
