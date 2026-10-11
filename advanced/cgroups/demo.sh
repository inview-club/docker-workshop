#!/usr/bin/env bash
set -euo pipefail
# Все чтения выполняются в Linux-контейнере, без privileged и host PID mode.
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
  '
