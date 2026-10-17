#!/usr/bin/env python3
"""Локальный Harbor v2.14: API, временный Docker login и проверка scan."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[2]
BASE = "http://localhost:8081/api/v2.0"
ARTIFACT = "/projects/club/repositories/counter/artifacts/1.0"
TARGET = "localhost:8081/club/counter:1.0"


class LabError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Harbor:
    def __init__(self, password=None):
        self.password = password
        # Только фиксированный loopback-адрес. Прокси и редиректы запрещены.
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def request(self, method, path, body=None, allow=(), headers=None):
        hdr = {"Content-Type": "application/json"}
        if self.password is not None:
            token = base64.b64encode(("admin:" + self.password).encode()).decode()
            hdr["Authorization"] = "Basic " + token
        hdr.update(headers or {})
        data = None if body is None else json.dumps(body).encode()
        req = Request(BASE + path, data=data, headers=hdr, method=method)
        try:
            with self.opener.open(req, timeout=15) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except HTTPError as exc:
            if exc.code in allow:
                return None
            # Не выводим ответ сервера: он может содержать конфигурацию и секреты.
            raise LabError(f"Harbor: HTTP {exc.code} при {method} {path}") from None
        except (URLError, TimeoutError, OSError):
            raise LabError(f"Harbor недоступен при {method} {path}") from None

    def health(self, timeout=600, interval=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if self.request("GET", "/health").get("status") == "healthy":
                    print("Harbor: healthy")
                    return
            except LabError:
                pass
            time.sleep(interval)
        raise LabError("Harbor не стал healthy за 10 минут. Проверьте docker compose logs в harbor/.")

    def project(self):
        path = "/projects/club"
        project = self.request("GET", path, allow=(404,))
        if project is None:
            # После неизвестного исхода повторный запуск сначала читает проект.
            self.request("POST", "/projects", {
                "project_name": "club", "storage_limit": 10 * 1024**3,
                "metadata": {"public": "false", "auto_scan": "true"},
            }, allow=(409,))
            project = self.request("GET", path)
        metadata = project.get("metadata", {})
        if metadata.get("public") != "false":
            raise LabError("Проект club уже существует и не является приватным. Не изменяю его доступы.")
        if metadata.get("auto_scan") != "true":
            self.request("PUT", path, {"metadata": {"auto_scan": "true"}})
        saved = self.request("GET", path)
        if saved.get("metadata", {}).get("auto_scan") != "true":
            raise LabError("Не удалось подтвердить auto_scan проекта club.")
        # Квота существующего проекта не меняется.
        quotas = self.request("GET", f"/quotas?reference=project&reference_id={saved['project_id']}")
        if not quotas:
            raise LabError("Не удалось прочитать квоту проекта club.")
        print("Проект club: приватный, auto_scan=true; квота (байт):", quotas[0]["hard"]["storage"])

    def scan(self, timeout=1800, interval=5):
        previous = self.request("GET", ARTIFACT + "?with_scan_overview=true").get("scan_overview") or {}
        observed_progress = not previous or any(
            s.get("scan_status") in ("Pending", "Running", "Scheduled") for s in previous.values())
        # Push уже мог запустить автоматический scan. 409 означает занятый scan.
        self.request("POST", ARTIFACT + "/scan", allow=(409,))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            artifact = self.request("GET", ARTIFACT + "?with_scan_overview=true")
            scans = list((artifact.get("scan_overview") or {}).values())
            current = artifact.get("scan_overview") or {}
            if current != previous:
                observed_progress = True
            fresh = observed_progress
            if fresh and scans and all(s.get("scan_status") == "Success" for s in scans):
                print("Сканирование завершено:", json.dumps(scans, ensure_ascii=False))
                report = self.request("GET", ARTIFACT + "/additions/vulnerabilities", headers={
                    "X-Accept-Vulnerabilities": "application/vnd.security.vulnerability.report; version=1.1",
                })
                if not isinstance(report, dict) or not report:
                    raise LabError("Harbor не вернул отчёт уязвимостей.")
                if any(not isinstance(r, dict) or not isinstance(r.get("vulnerabilities"), list)
                       for r in report.values()):
                    raise LabError("Неизвестная структура отчёта Trivy; отсутствие CVE не подтверждено.")
                vulns = [v for r in report.values() for v in r["vulnerabilities"]]
                if vulns:
                    v = vulns[0]
                    print("Пример CVE:", json.dumps({k: v.get(k) for k in
                          ("id", "package", "version", "severity", "fix_version")}, ensure_ascii=False))
                else:
                    print("Отчёт не содержит уязвимостей.")
                return
            if fresh and any(s.get("scan_status") in ("Error", "Stopped") for s in scans):
                raise LabError("Сканирование завершилось ошибкой. Проверьте журналы trivy-adapter и jobservice.")
            time.sleep(interval)
        raise LabError("Отчёт Trivy не готов за 30 минут. Запуск сканирования не означает успех.")


def password():
    value = os.environ.get("HARBOR_ADMIN_PASSWORD")
    if value:
        return value
    # Читаем только нужное поле .env. Не исполняем файл как shell-код.
    for line in (ROOT / "harbor/.env").read_text().splitlines():
        key, sep, val = line.partition("=")
        if sep and key.strip() == "HARBOR_ADMIN_PASSWORD":
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            if val:
                return val
    raise LabError("В harbor/.env нет HARBOR_ADMIN_PASSWORD. Задайте пароль текущего admin через env.")


def publish(client):
    # Отдельный Docker config: пароль Harbor не сохраняется в профиле участника.
    original = Path(os.environ.get("DOCKER_CONFIG", str(Path.home() / ".docker")))
    context = subprocess.check_output(["docker", "context", "show"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="harbor-login-") as tmp:
        config = Path(tmp)
        (config / "config.json").write_text(json.dumps({"currentContext": context}))
        if (original / "contexts").is_dir():
            shutil.copytree(original / "contexts", config / "contexts")
        command = ["docker", "--config", tmp]
        subprocess.run(command + ["login", "localhost:8081", "--username", "admin", "--password-stdin"],
                       input=client.password + "\n", text=True, check=True)
        subprocess.run(command + ["tag", "club-demo:1.0", TARGET], check=True)
        subprocess.run(command + ["push", TARGET], check=True)
        subprocess.run(command + ["pull", TARGET], check=True)
        artifact = client.request("GET", ARTIFACT)
        digests = json.loads(subprocess.check_output(command + [
            "image", "inspect", TARGET, "--format", "{{json .RepoDigests}}"], text=True)) or []
        if f"localhost:8081/club/counter@{artifact['digest']}" not in digests:
            raise LabError("Digest загруженного образа не совпал с артефактом Harbor.")
    client.scan()


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    if action == "health":
        Harbor().health()
    elif action == "project":
        Harbor(password()).project()
    elif action == "publish":
        publish(Harbor(password()))
    else:
        raise LabError("Укажите действие: health, project или publish.")


if __name__ == "__main__":
    try:
        main()
    except (LabError, subprocess.CalledProcessError, OSError, ValueError, KeyError) as exc:
        # Не выводим содержимое конфигурации или значения env.
        message = str(exc) if isinstance(exc, LabError) else type(exc).__name__
        print("Ошибка:", message, file=sys.stderr)
        sys.exit(1)
