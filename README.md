# Практикум по Docker и Harbor

В репозитории собраны задания для встречи DevOps-клуба.
Вы запустите контейнер, соберёте образ приложения и сохраните его в Harbor.
Затем проверите образ на уязвимости.

## Подготовка

Установите Git, Docker с Linux-контейнерами, Docker Compose v2, Bash, curl, Python 3 и OpenSSL.
Для Windows сначала выполните [инструкцию ниже](#подготовка-windows).
На macOS можно использовать Docker Desktop или Colima.
Для Harbor выделите Docker 8 ГиБ памяти и оставьте минимум 40 ГБ свободного места.
Нужен интернет для загрузки образов и базы уязвимостей.

Если используете Colima, запустите её так:

```bash
colima start --memory 8
docker context use colima
```

На Linux и macOS скачайте материалы:

```bash
git clone git@github.com:inview-club/docker-workshop.git
cd docker-workshop
docker info
docker compose version
```

Для клонирования нужен доступ к репозиторию через SSH.
Если Docker или Compose возвращает ошибку, исправьте её до начала заданий.

## Подготовка Windows

Используйте Docker Desktop с WSL2 и Ubuntu.
Инструкция рассчитана на компьютеры с процессором Intel или AMD (x86-64).
Для Windows ARM нужен отдельный пробный запуск: Harbor использует образы `linux/amd64`.
Полный сценарий этого репозитория на Windows пока не проверен.

Схема работы:

```text
Терминал Ubuntu → команда docker → Docker Desktop → Linux-контейнеры
```

Docker Desktop запускает Docker Engine в своей Linux-среде WSL2.
Интеграция даёт терминалу Ubuntu доступ к этому Engine.
Задания выполняйте в Ubuntu. Команды PowerShell ниже нужны только для настройки Windows.

### 1. Установите WSL2 и Ubuntu

Проверьте [требования Docker Desktop к Windows и оборудованию](https://docs.docker.com/desktop/setup/install/windows-install/#system-requirements).
Включите аппаратную виртуализацию в BIOS/UEFI, если она отключена.
Для Harbor ориентируйтесь на 8 ГиБ памяти для WSL и минимум 40 ГБ свободного места.
Для этого практикума рекомендуем компьютер с 16 ГБ оперативной памяти или больше.
Часть памяти нужна самой Windows.

Если Ubuntu в WSL ещё не установлена, откройте **PowerShell от имени администратора**:

```powershell
wsl --install -d Ubuntu
```

Перезагрузите компьютер, если установка этого требует.
Откройте Ubuntu через меню «Пуск».
Дождитесь первоначальной настройки.
Создайте пользователя Linux и задайте ему пароль.
При вводе пароля символы могут не отображаться. Это обычное поведение терминала.
Если Ubuntu уже установлена, не устанавливайте её повторно.

Выполните в **PowerShell**:

```powershell
wsl --update
wsl -l -v
```

В строке `Ubuntu` в колонке `VERSION` должно быть `2`.
Если указано `1`, переведите дистрибутив в WSL2:

```powershell
wsl --set-version Ubuntu 2
wsl -l -v
```

Если дистрибутив называется иначе, используйте точное имя из `wsl -l -v`.
Например, вместо `Ubuntu` может быть указано `Ubuntu-24.04`.
Используйте это имя и в следующих командах WSL.
[Инструкция Microsoft по установке WSL](https://learn.microsoft.com/en-us/windows/wsl/install).

### 2. Настройте Docker Desktop

1. [Установите Docker Desktop для Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
2. Запустите Docker Desktop через меню «Пуск».
3. Откройте **Settings → General**.
4. Включите **Use WSL 2 based engine**. Если параметр скрыт, этот режим может быть уже включён по умолчанию.
5. Откройте **Settings → Resources → WSL Integration**.
6. Включите интеграцию для своего дистрибутива Ubuntu.
7. Примените изменения и дождитесь готовности Docker Desktop.

Если раздел **WSL Integration** отсутствует, проверьте режим контейнеров.
В меню Docker Desktop выберите **Switch to Linux containers**, если этот пункт доступен.
Для заданий нужны Linux-контейнеры.

Не устанавливайте отдельный Docker Engine внутри Ubuntu для этой схемы.
Он может конфликтовать с Docker Desktop.
Если такой Engine уже установлен, сначала устраните конфликт по [инструкции Docker](https://docs.docker.com/desktop/features/wsl/).

### 3. Проверьте ресурсы WSL

Ограничения памяти и CPU задаются в файле `%UserProfile%\.wslconfig` на стороне Windows.
По умолчанию предел памяти WSL составляет 50 % памяти компьютера.
Это общий предел для среды WSL2.

Если памяти для Harbor недостаточно, откройте файл из **PowerShell**:

```powershell
notepad "$env:USERPROFILE\.wslconfig"
```

Для компьютера с достаточным объёмом памяти можно задать:

```ini
[wsl2]
memory=8GB
processors=2
```

Не заменяйте весь существующий файл этим примером.
Сохраните остальные настройки. Измените или добавьте поля в секции `[wsl2]`.
Параметр `processors=2` позволяет сравнить два доступных CPU с одним CPU в задании cpuset.
Не задавайте больше процессоров, чем доступно компьютеру.

Чтобы применить изменения, сначала сохраните работу во всех дистрибутивах WSL.
Завершите Docker Desktop через его меню.
Следующая команда остановит все дистрибутивы WSL и работающие в них процессы:

```powershell
wsl --shutdown
```

Снова запустите Docker Desktop. Затем откройте Ubuntu.
[Описание `.wslconfig` у Microsoft](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#main-wsl-settings).

### 4. Откройте Ubuntu и установите утилиты

Выберите профиль Ubuntu в Windows Terminal.
Другой способ — выполнить в **PowerShell**:

```powershell
wsl -d Ubuntu
```

Все следующие команды выполняйте **в терминале Ubuntu**:

```bash
sudo apt update
sudo apt install -y git curl python3 openssl ca-certificates
```

Bash уже входит в Ubuntu.
При запросе `sudo` введите пароль пользователя Linux, созданного на шаге 1.
Docker Desktop оставьте запущенным во время занятия.

### 5. Скачайте репозиторий в файловую систему Ubuntu

Выполните в **Ubuntu**, если репозиторий ещё не скачан:

```bash
cd ~
git clone --config core.autocrlf=false https://github.com/inview-club/docker-workshop.git
cd ~/docker-workshop
```

Если каталог уже существует, перейдите в него без повторного клонирования.
Для доступа к закрытому репозиторию нужны права и [аутентификация GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github).

Храните материалы в `~/docker-workshop`, а не в `/mnt/c/...`.
Это каталог Linux внутри WSL. Он подходит для скриптов и подключаемых каталогов Harbor.
Параметр `core.autocrlf=false` сохраняет окончания строк LF в скриптах.
[Рекомендации Microsoft по расположению файлов](https://learn.microsoft.com/en-us/windows/wsl/filesystems#file-storage-and-performance-across-file-systems).

### 6. Проверьте окружение

Выполните из каталога репозитория **в Ubuntu**:

```bash
bash --version
git --version
curl --version
python3 --version
openssl version
docker version
docker compose version
docker info --format 'OS={{.OSType}}; cgroups={{.CgroupVersion}}; CPUs={{.NCPU}}; Memory={{.MemTotal}} bytes'
```

Проверьте результаты:

- Каждая команда завершается без ошибки.
- `docker version` показывает разделы `Client` и `Server`.
- `docker compose version` показывает установленную версию Compose.
- `docker info` показывает `OS=linux` и `cgroups=2`.
- Для сравнения cpuset желательно не менее двух CPU.
- Для Harbor значение памяти должно быть близко к 8 ГиБ, то есть 8 589 934 592 байтам.

Проверьте запуск контейнера при доступном интернете:

```bash
docker run --rm hello-world
```

При первом запуске Docker скачает образ.
Ожидается сообщение `Hello from Docker!` и код завершения 0.
Контейнер удалится после проверки. Образ останется в кэше.

Если в Ubuntu команда `docker` не найдена, проверьте **WSL Integration** на шаге 2.
Если команда найдена, но раздел `Server` недоступен, проверьте готовность Docker Desktop.
Если указано `OS=windows`, переключитесь на Linux-контейнеры.
Если указано `cgroups=1`, обновите WSL и Docker Desktop и повторите проверку.
Задание `01-cgroups.sh` требует v2.

После успешных проверок запускайте задания из корня репозитория:

```bash
cd ~/docker-workshop
bash org_scripts/basic/01-nginx.sh
```

Окна браузера можно открывать в Windows.
Во время работы соответствующего сервиса используйте `http://localhost:8080` для приложения
или `http://localhost:8081` для Harbor.
После остановки сервиса его адрес перестанет отвечать.
[Сеть Docker Desktop](https://docs.docker.com/desktop/features/networking/).

До занятия выполните [подготовку к работе без интернета](org_scripts/README.md#подготовка-к-аудитории-с-плохим-интернетом).
Проверка `hello-world` не загружает образы заданий или базу Trivy.

## Порядок заданий

1. [Запустите первый контейнер](first-container.md).
2. [Соберите приложение и запустите его с Redis](app/README.md).
3. [Подготовьте Harbor, загрузите и проверьте образ](harbor/README.md).
4. [Выполните дополнительные задания](advanced/README.md): ограничения ресурсов,
   сборка в несколько этапов, Hadolint, тома и подпись архива.

В каждом задании указан рабочий каталог. Выполняйте команды по порядку.
Перед сменой задания освободите порт 8080, если предыдущий контейнер его использует.
Harbor использует порты 8081 и 1514.

## Скрипты для проведения практики

В [org_scripts/](org_scripts/README.md) находятся отдельные скрипты базового и дополнительного треков.
Каждый скрипт выполняет одно задание и проверяет результат.
Инструкция описывает повторный запуск и подготовку к работе без интернета.

## Презентация

[Скачать презентацию Docker и Harbor](Клуб_DevOps_Docker_Harbor.pptx).

Все примеры предназначены для локального обучения.
Не используйте учебные пароли и настройки HTTP в рабочих системах.
