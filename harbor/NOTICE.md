# Основа конфигурации

`compose.yaml` получен из официального шаблона Harbor **v2.14.0**:
[goharbor/harbor: docker-compose.yml.jinja](https://github.com/goharbor/harbor/blob/v2.14.0/make/photon/prepare/templates/docker_compose/docker-compose.yml.jinja).

Исходный проект: Copyright The Harbor Authors, лицензия Apache-2.0. Текст лицензии включён в `LICENSE.harbor`.

Изменения для локального воркшопа: относительные пути в `runtime`, привязка HTTP к `127.0.0.1:8081`, явная платформа `linux/amd64`, имя проекта `harbor-lab`, удаление фиксированных `container_name`. Конфигурацию компонентов создаёт официальный образ `goharbor/prepare` той же версии.

`harbor.yml.tmpl` — сокращённая учебная конфигурация на основе официального [harbor.yml.tmpl](https://github.com/goharbor/harbor/blob/v2.14.0/make/harbor.yml.tmpl). Логи и число рабочих задач уменьшены для локального занятия.
