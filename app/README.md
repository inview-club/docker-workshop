# Учебное приложение Docker Workshop

HTTP-счётчик на Flask. При отдельном запуске хранит значение в памяти процесса. В Compose использует Redis и сохраняет счётчик в named volume.

Нужен Docker с Linux-контейнерами. Для второго варианта нужен Docker Compose v2. Все команды ниже выполняются из каталога `app/`.

## Сборка и запуск образа

```bash
docker build -t club-demo:1.0 .
docker run --rm club-demo:1.0 id
docker run -d --name counter-demo -p 127.0.0.1:8080:8080 club-demo:1.0
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/
docker logs counter-demo
```

`/health` возвращает `{"status":"ok"}`, `/` возвращает число посещений и `backend: memory`. Процесс работает с UID 10001. При перезапуске процесса счётчик в памяти сбрасывается.

`EXPOSE 8080` в Dockerfile описывает порт. Для подключения с компьютера нужен параметр `-p`: первый порт относится к компьютеру, второй к контейнеру. Публикация ограничена адресом `127.0.0.1`. Если запускать без `-d`, `Ctrl+C` остановит приложение.

Перед запуском Compose остановите и удалите отдельный контейнер, чтобы освободить порт 8080:

```bash
docker stop counter-demo
docker rm counter-demo
```

## Приложение и Redis через Compose

```bash
docker compose config
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/
docker compose exec redis redis-cli GET visits
docker compose down
docker compose up -d
curl http://127.0.0.1:8080/
```

Ответ содержит `backend: redis`. Redis сохраняет данные в AOF в volume `redis-data`, поэтому счётчик сохраняется после обычного `down` и пересоздания контейнеров. `docker compose down -v` удаляет volume и данные счётчика.

Compose ждёт успешной проверки Redis при старте приложения. При последующей недоступности Redis приложение возвращает HTTP 503. `/health` проверяет только HTTP-приложение, доступность Redis проверяйте запросом `/`.

В примере используется учебный сервер Flask. Для production нужен WSGI-сервер.
