#!/usr/bin/env python3
"""Проверка готовности локального Harbor без авторизации и изменения состояния."""
import json
import sys
import time
from urllib.error import URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

BASE = "http://localhost:8081/api/v2.0"


class LabError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Harbor:
    def __init__(self):
        # Только фиксированный loopback-адрес. Прокси и редиректы запрещены.
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def request(self, method, path):
        if method != "GET" or path != "/health":
            raise LabError("Разрешён только GET /health.")
        req = Request(BASE + path, method="GET")
        try:
            with self.opener.open(req, timeout=15) as response:
                result = json.load(response)
                if not isinstance(result, dict):
                    raise LabError("Harbor вернул неизвестный формат готовности.")
                return result
        except (URLError, TimeoutError, OSError, ValueError):
            raise LabError("Не удалось получить статус готовности Harbor.") from None

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



def main():
    if sys.argv[1:] != ["health"]:
        raise LabError("Укажите действие: health.")
    Harbor().health()


if __name__ == "__main__":
    try:
        main()
    except LabError as exc:
        print("Ошибка:", str(exc), file=sys.stderr)
        sys.exit(1)
