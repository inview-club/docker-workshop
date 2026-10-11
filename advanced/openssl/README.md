# OpenSSL: локальная подпись архива образа

Нужны Docker, OpenSSL и собранный образ `club-advanced:1.0` из раздела multistage. Все команды ниже выполняются последовательно в одном терминале. Из `advanced/` создайте отдельный каталог проверки:

```bash
cd openssl
umask 077
demo_dir="demo-$(date +%Y%m%d%H%M%S)-$$"
mkdir "$demo_dir"
cd "$demo_dir"
docker save -o image.tar club-advanced:1.0
```

Создайте зашифрованный приватный RSA-ключ и открытый ключ. OpenSSL попросит придумать пароль приватного ключа, затем повторно попросит его для экспорта открытого ключа и подписи. Пароль вводите в приглашении, а не в аргументах команды:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -aes-256-cbc -out signing.key
openssl pkey -in signing.key -pubout -out signing.pub
openssl dgst -sha256 -sign signing.key -out image.tar.sig image.tar
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig image.tar
```

Ожидаемый результат последней команды: `Verified OK`, код выхода 0. После успешной проверки можно загрузить именно этот архив:

```bash
docker load -i image.tar
```

Проверьте, что изменение файла ломает подпись. Команда `cp` создаёт вторую копию архива; потребуется дополнительное место:

```bash
cp image.tar tampered.tar
printf '\nchanged\n' >> tampered.tar
openssl dgst -sha256 -verify signing.pub -signature image.tar.sig tampered.tar
```

Ожидается ошибка проверки и ненулевой код выхода. Изменённый архив не загружайте. Повторная проверка исходного `image.tar` должна по-прежнему пройти.

Подписываются байты конкретного tar-архива, включая метаданные архива. Другой экспорт того же образа может иметь другие байты и требует отдельной подписи. Это упражнение не создаёт OCI-подпись в Harbor; `docker run` и `docker load` не проверяют её автоматически. Проверяйте архив до загрузки. Подпись подтверждает происхождение относительно доверенного ключа и целостность архива, но не отсутствие уязвимостей.

Получатель получает `image.tar`, `image.tar.sig` и доверенный `signing.pub`. Отпечаток открытого ключа следует сверить по независимому доверенному каналу: если злоумышленник заменит одновременно архив, подпись и открытый ключ, простая проверка пройдёт. Приватный `signing.key` остаётся у подписанта. Каталоги `demo-*`, ключи и архивы исключены из Git.

## Документация

- [Создание ключа](https://docs.openssl.org/3.0/man1/openssl-genpkey/)
- [Экспорт открытого ключа](https://docs.openssl.org/3.0/man1/openssl-pkey/)
- [Подпись и проверка](https://docs.openssl.org/3.0/man1/openssl-dgst/)
