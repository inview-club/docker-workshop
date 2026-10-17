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

# Cgroups v1: контроллеры могут иметь отдельные иерархии.
# Квота CPU задаётся парой cpu.cfs_quota_us / cpu.cfs_period_us,
# память — memory.limit_in_bytes; CPU-набор — cpuset.cpus.
# Cgroups v2: единая иерархия; аналоги — cpu.max, memory.max и cpuset.cpus.
# cpuset.cpus.effective показывает фактически доступные CPU с учётом родительских ограничений.
# Версия определяется Linux-хостом Docker (в Colima это VM), а не образом контейнера.
# Этот сценарий выполняется на v2. Для живого сравнения с v1 нужна подготовленная среда v1.

# 2. Узнаём CPU, доступные процессу без дополнительного ограничения cpuset.
# Не предполагаем, что CPU 0 доступен: выбираем первый CPU из реального списка.
allowed_cpus=$(docker run --rm --pull=never python:3.12-slim python -c \
  'import os; print(",".join(map(str, sorted(os.sched_getaffinity(0)))))')
cpu_id=${allowed_cpus%%,*}
[[ "$cpu_id" =~ ^[0-9]+$ ]]
printf 'CPU без дополнительного cpuset: %s\n' "$allowed_cpus"
printf 'Для задания разрешаем только CPU %s.\n' "$cpu_id"
if [ "$allowed_cpus" = "$cpu_id" ]; then
  printf 'Доступен один CPU: сокращения списка не будет, но настройку cpuset проверим.\n'
fi

# 3. Запускаем контейнер с cpuset и квотой CPU; читаем реальные ограничения.
# --cpus=0.5 ограничивает время CPU, --cpuset-cpus выбирает разрешённый CPU.
# В Colima это виртуальный CPU VM. Флаг не выделяет физическое ядро Mac эксклюзивно.
# Контейнер удалится сам (--rm). Привилегированный режим и изменение хоста не нужны.
docker run --rm --pull=never -i --cpuset-cpus "$cpu_id" \
  --cpus=0.5 --memory=64m --memory-swap=64m --pids-limit=64 \
  python:3.12-slim python - "$cpu_id" <<'PYTHON' | tee "$work_dir/result"
import os
from pathlib import Path
import subprocess
import sys
import time

cgroup = Path("/sys/fs/cgroup")
if not (cgroup / "cgroup.controllers").is_file():
    raise SystemExit("Этот пример требует cgroups v2.")

expected_cpu = int(sys.argv[1])
affinity = sorted(os.sched_getaffinity(0))
print("=== Проверяем cpuset ===", flush=True)
print("CPU affinity:", affinity, flush=True)
print("cpuset.cpus:", repr((cgroup / "cpuset.cpus").read_text().strip()), flush=True)
print("cpuset.cpus.effective:", (cgroup / "cpuset.cpus.effective").read_text().strip(), flush=True)
for line in Path("/proc/self/status").read_text().splitlines():
    if line.startswith("Cpus_allowed_list:"):
        print(line, flush=True)
if affinity != [expected_cpu]:
    raise SystemExit("Фактический набор CPU не совпал с заданным cpuset.")
print(f"Cpuset проверен: CPU {expected_cpu}", flush=True)

print("=== CPU quota / period (microseconds) ===", flush=True)
print((cgroup / "cpu.max").read_text().strip(), flush=True)
print("=== Memory limit (bytes) ===", flush=True)
print((cgroup / "memory.max").read_text().strip(), flush=True)
print("=== PIDs limit ===", flush=True)
print((cgroup / "pids.max").read_text().strip(), flush=True)

# 4. Создаём дочерний процесс и сравниваем ссылки /proc/PID/ns у двух живых процессов.
# Разные PID не означают разные namespaces: потомок наследует их от родителя.
# Это не сравнение с хостом. Например, user/time namespaces могут быть общими с хостом.
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
try:
    parent_pid = os.getpid()
    print(f"=== Namespaces: родитель PID {parent_pid}, потомок PID {child.pid} ===", flush=True)
    print("Тип | родитель | потомок | совпадает", flush=True)
    for entry in sorted(Path(f"/proc/{parent_pid}/ns").iterdir()):
        parent_ns = os.readlink(entry)
        child_ns = os.readlink(f"/proc/{child.pid}/ns/{entry.name}")
        same = parent_ns == child_ns
        print(f"{entry.name} | {parent_ns} | {child_ns} | {same}", flush=True)
        if not same:
            raise SystemExit(f"Namespace {entry.name} неожиданно отличается.")
    print("Namespaces родителя и потомка совпадают.", flush=True)
finally:
    child.terminate()
    child.wait(timeout=5)

# 5. Создаём двухсекундную нагрузку и читаем статистику ограничения CPU.
print("=== Нагрузка CPU в течение двух секунд ===", flush=True)
end = time.monotonic() + 2
iterations = 0
while time.monotonic() < end:
    iterations += 1
print("Итераций:", iterations, flush=True)
print("=== Учёт CPU и throttling ===", flush=True)
print((cgroup / "cpu.stat").read_text(), flush=True)
PYTHON

# 6. Проверяем квоту CPU, 64 МиБ памяти, лимит 64 PID и результаты демонстрации.
grep -qx '50000 100000' "$work_dir/result"
grep -qx 67108864 "$work_dir/result"
grep -qx 64 "$work_dir/result"
grep -qx "Cpuset проверен: CPU $cpu_id" "$work_dir/result"
grep -qx 'Namespaces родителя и потомка совпадают.' "$work_dir/result"
rm -rf -- "$work_dir"
printf 'Готово: cpuset, cgroups и наследование namespaces проверены. Образ сохранён.\n'
