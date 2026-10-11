# Локальный Harbor

Учебный registry Harbor v2.14.0 со сканированием образов через Trivy.

## Требования

Docker с Linux-контейнерами, Bash и Docker Compose v2. Можно использовать плагин `docker compose` или отдельную команду `docker-compose` версии v2. Скрипты выбирают доступную команду автоматически. Старый Compose v1 с этой конфигурацией не проверен.

На Linux используется Docker Engine. На Windows/macOS Linux-среду предоставляет Docker Desktop, отдельную VM вручную создавать не нужно. На Windows запускайте скрипты в WSL2 и храните репозиторий в файловой системе WSL.

Выделите Docker минимум 4 GB RAM, желательно 8 GB, и оставьте минимум 40 GB свободного места. Нужен интернет для загрузки образов и базы Trivy. Стенд использует `linux/amd64`; на Apple Silicon нужна эмуляция и проверка до занятия.

## Запуск


Из корня репозитория:

```bash
cd harbor
bash start.sh
curl -fsS http://localhost:8081/api/v2.0/health
```

Если доступна только команда `docker-compose`, используйте её вместо `docker compose` во всех последующих командах этой инструкции.

Первый запуск может занять несколько минут. В ответе `/api/v2.0/health` ожидается общий статус `healthy`. Не считайте просто запущенные контейнеры признаком готовности.

`prepare.sh` запускает официальный `goharbor/prepare:v2.14.0` через Compose с `--with-trivy`. Он создаёт настройки, внутренние ключи подписи registry и данные в `harbor/runtime/`. Внешние TLS-сертификаты не требуются. Затем `compose.yaml` запускает 10 сервисов из официальных `goharbor/*` образов той же версии. [Официальный prepare](https://github.com/goharbor/harbor/blob/v2.14.0/make/prepare), [официальный шаблон Compose](https://github.com/goharbor/harbor/blob/v2.14.0/make/photon/prepare/templates/docker_compose/docker-compose.yml.jinja).

Портал: `http://localhost:8081`. Пользователь: `admin`. Для лаборатории начальный пароль задан в `.env.example`: `HarborLab12345!`. Скрипт копирует его в игнорируемый `.env`, который можно изменить перед первым запуском. Изменение переменной после инициализации БД не меняет пароль администратора. Не используйте учебные пароли в других средах.

HTTP опубликован только на `127.0.0.1`. Стенд предназначен для практики на одном компьютере. Не публикуйте его в сети и не используйте для рабочих секретов. Для общего или production registry нужен HTTPS.

### Разрешение локального HTTP registry

Если Docker возвращает `server gave HTTP response to HTTPS client`, добавьте `localhost:8081` в список `insecure-registries` настройки Docker daemon. Сохраните остальные существующие поля JSON и элементы списка.

```json
{"insecure-registries": ["localhost:8081"]}
```

В Docker Desktop это настройки Docker Engine, затем Apply & Restart. На Linux измените соответствующее поле `/etc/docker/daemon.json` и перезапустите Docker. Перезапуск затрагивает другие контейнеры, поэтому выполняйте его до практики. Конфигурация выше показывает только нужное поле, не заменяет весь существующий файл. [Настройка dockerd](https://docs.docker.com/reference/cli/dockerd/#insecure-registries).

### Проект, публикация и сканирование

1. В портале создайте приватный проект `club`.
2. В Configuration включите `Automatically scan images on push`.
3. При необходимости задайте квоту проекта и robot account с правами push/pull.
4. Из любого каталога выполните:

```bash
docker login localhost:8081
docker tag club-demo:1.0 localhost:8081/club/counter:1.0
docker push localhost:8081/club/counter:1.0
docker pull localhost:8081/club/counter:1.0
```

Откройте артефакт в `club/counter`, дождитесь завершённого scan и разберите одну CVE: пакет, установленную версию, критичность и доступное исправление. Количество CVE зависит от образа и текущей базы, оно не задано заранее. Ошибка сканирования не означает отсутствия уязвимостей. [Настройки проекта](https://goharbor.io/docs/2.14.0/working-with-projects/project-configuration/), [сканирование](https://goharbor.io/docs/2.14.0/administration/vulnerability-scanning/).

### Хранение и остановка

`runtime/data/registry` содержит blobs, `runtime/data/database` — метаданные. Конфигурация находится в `runtime/common/config`, ключи — в `runtime/data/secret`. Для сохранности стенда не удаляйте каталог `runtime` и не перемещайте его после генерации конфигурации.

```bash
docker compose down
docker compose up -d
docker pull localhost:8081/club/counter:1.0
```

У этого стенда bind mounts. Даже `down -v` не удаляет файлы `runtime/data`. Полное удаление `runtime` уничтожит образы, БД и ключи. Каталог `runtime` и `.env` исключены из Git, не загружайте их в репозиторий.

Retention задаёт правила удаления артефактов, garbage collection освобождает неиспользуемые blobs. В интерфейсе сначала используйте dry run соответствующей операции. [Garbage collection](https://goharbor.io/docs/2.14.0/administration/garbage-collection/).

## Что проверить до занятия

Проведите полный запуск на каждой используемой платформе, особенно Apple Silicon и Windows/WSL2. В среде подготовки материалов Docker daemon был недоступен: синтаксис и связи конфигурации проверены, живой запуск Harbor не подтверждён.

Если bind mount недоступен на Mac, проверьте File Sharing Docker Desktop. Если Trivy не скачивает базу, проверьте интернет и логи `docker compose logs trivy-adapter`. Если порт 8081 или syslog-порт 1514 занят, остановите другой учебный Harbor либо согласованно измените конфигурацию до запуска.
