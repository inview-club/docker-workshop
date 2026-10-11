"""Выполняется внутри официального goharbor/prepare, не на компьютере участника."""
import os
from pathlib import Path
import yaml

root = Path(os.environ["HARBOR_LAB_ROOT"])
config = yaml.safe_load(Path("/lab/harbor.yml.tmpl").read_text())
config["data_volume"] = str(root / "runtime/data")
config["log"]["local"]["location"] = str(root / "runtime/log")
config["harbor_admin_password"] = os.environ["HARBOR_ADMIN_PASSWORD"]
config["database"]["password"] = os.environ["HARBOR_DB_PASSWORD"]
Path("/input/harbor.yml").write_text(yaml.safe_dump(config, sort_keys=False))

# Официальный prepare сам создаст ключи подписи registry и конфигурацию сервисов.
# Готовые внешние TLS-сертификаты не используются.
