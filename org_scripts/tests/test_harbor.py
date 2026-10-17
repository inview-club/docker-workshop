"""Проверка ожидания готовности без записи в Harbor."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("harbor", Path(__file__).resolve().parents[1] / "lib/harbor.py")
harbor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harbor)


class FakeHarbor(harbor.Harbor):
    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def request(self, method, path):
        self.calls.append((method, path))
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        return reply


class HarborTests(unittest.TestCase):
    def test_health_waits_for_overall_healthy(self):
        client = FakeHarbor([harbor.LabError("not ready"), {"status": "unhealthy"}, {"status": "healthy"}])
        client.health(timeout=1, interval=0)
        self.assertEqual(client.calls, [("GET", "/health")] * 3)

    def test_health_timeout_fails(self):
        with self.assertRaises(harbor.LabError):
            FakeHarbor([]).health(timeout=0)

    def test_mutations_and_other_endpoints_refused(self):
        client = harbor.Harbor()
        for method, path in [("POST", "/projects"), ("GET", "/projects"), ("PUT", "/health")]:
            with self.subTest(method=method, path=path), self.assertRaises(harbor.LabError):
                client.request(method, path)


if __name__ == "__main__":
    unittest.main()
