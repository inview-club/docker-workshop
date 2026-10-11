# Docker Advanced: примеры для практики

Работайте из каталога `advanced/`. После команд с `cd multistage` вернитесь сюда через `cd ..` перед следующим разделом. Нужен запущенный Docker с Linux-контейнерами и Bash. На Windows используйте WSL2. Сборки и запуск скриптов создают учебные образы и контейнеры в текущем Docker context.

## 1. Namespaces и cgroups v2

```bash
bash cgroups/demo.sh
```

Скрипт запускает один контейнер с лимитами 0.5 CPU, 64 MiB памяти и 64 PID. Читает `/proc/1/ns`, `cpu.max`, `memory.max`, `pids.max`, затем создаёт двухсекундную CPU-нагрузку и показывает `cpu.stat`. Не использует privileged, host PID mode или изменение cgroups хоста.

Для обычного Docker на cgroups v2 ожидаются `50000 100000`, `67108864` и `64`. Namespace inode и счётчики нагрузки зависят от запуска. `nr_throttled` показывает число периодов, в которых исчерпана CPU-квота. На cgroups v1 скрипт завершится с объяснением. В macOS/Windows/Colima Linux-файлы читаются внутри Linux-среды Docker.

## 2. Multistage

Перед запуском убедитесь, что порт 8080 свободен. Все команды этого раздела выполняются из `multistage/`.

```bash
cd multistage
docker build -t club-advanced:1.0 .
docker run --rm -d --name club-advanced -p 127.0.0.1:8080:8080 club-advanced:1.0
curl http://127.0.0.1:8080/
docker stop club-advanced
```

Ожидаемый ответ: `Hello from multistage! UID=10001`. Для сравнения размера этапов:

```bash
docker build --target build -t club-advanced-build:1.0 .
docker image inspect club-advanced-build:1.0 club-advanced:1.0 --format '{{index .RepoTags 0}} {{.Size}}'
```

Размер указан в байтах и зависит от архитектуры и версии образов. В runtime копируется только статический бинарник. `scratch` не содержит shell, CA bundle и отладочных инструментов. Пример обслуживает HTTP и не обращается к внешним HTTPS-сервисам. Для настоящего приложения выбирайте runtime под его зависимости. Go 1.24.6 зафиксирован как учебная версия, при использовании в рабочем сервисе обновите её согласно политике проекта.

## 3. Hadolint

Hadolint вынесен в отдельный каталог `hadolint/`. Из корня advanced:

```bash
bash hadolint/lint.sh Dockerfile.good
bash hadolint/lint.sh Dockerfile.bad
```

Для хорошего примера ожидается код выхода 0. Для плохого — ненулевой код и сообщения DL3007, DL3018, DL3019, DL3025. Подробности в [hadolint/README.md](hadolint/README.md).

## 4. Volumes

Из корня материалов:

```bash
bash volumes/demo.sh
```

Скрипт собирает образ с `/data/seed.txt`, создаёт volume с уникальным именем и показывает:

1. Пустой volume получает `seed.txt` из образа при первом монтировании.
2. Первый контейнер записывает `result.txt` и удаляется.
3. Второй контейнер читает `written by container 1` из того же volume, подключённого только для чтения.

Volume остаётся после скрипта. Для удаления только созданных учебных данных скопируйте точную команду `docker volume rm ...` из его вывода. Не используйте общий `docker volume prune` для этого задания.

## 5. Локальная подпись через OpenSSL

[openssl/README.md](openssl/README.md) содержит команды экспорта образа, создания ключа, подписи, проверки и проверки изменения файла. Нужны OpenSSL и собранный образ `club-advanced:1.0`. Registry для этого упражнения не требуется.

Подписывается конкретный архив `docker save`. Это не подпись OCI-образа в registry: Docker и Harbor автоматически её не проверяют. Перед `docker load` проверяем архив вручную.

## Источники

- [Linux namespaces](https://www.man7.org/linux/man-pages/man7/namespaces.7.html)
- [Cgroups v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)
- [Multistage](https://docs.docker.com/build/building/multi-stage/)
- [Hadolint](https://github.com/hadolint/hadolint)
- [Volumes](https://docs.docker.com/engine/storage/volumes/)
- [OpenSSL: подпись и проверка](https://docs.openssl.org/3.0/man1/openssl-dgst/)
