"""Проверки повторного запуска, готовности и ошибок без Docker daemon."""
import importlib.util
from pathlib import Path
import unittest
import json
import os
import subprocess
import tempfile
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("harbor", Path(__file__).resolve().parents[1] / "lib/harbor.py")
harbor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harbor)


class FakeHarbor(harbor.Harbor):
    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def request(self, method, path, body=None, **kwargs):
        self.calls.append((method, path, body))
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        return reply


def project(auto="true", public="false"):
    return {"project_id": 7, "metadata": {"auto_scan": auto, "public": public}}


def scan(status, end="old"):
    return {"scan_overview": {"report": {"scan_status": status, "end_time": end}}}


class HarborTests(unittest.TestCase):
    def test_existing_project_is_not_recreated_or_reconfigured(self):
        client = FakeHarbor([project(), project(), [{"hard": {"storage": 123}}]])
        client.project()
        self.assertTrue(all(c[0] == "GET" for c in client.calls))

    def test_creation_and_independent_readback(self):
        client = FakeHarbor([None, None, project(), project(), [{"hard": {"storage": 10 * 1024**3}}]])
        client.project()
        creation = [c for c in client.calls if c[0] == "POST"]
        self.assertEqual(len(creation), 1)
        self.assertEqual(creation[0][2]["metadata"], {"public": "false", "auto_scan": "true"})

    def test_existing_quota_preserved_when_enabling_scan(self):
        client = FakeHarbor([project("false"), None, project(), [{"hard": {"storage": 123}}]])
        client.project()
        updates = [c for c in client.calls if c[0] == "PUT"]
        self.assertEqual(updates[0][2], {"metadata": {"auto_scan": "true"}})

    def test_public_project_is_not_changed(self):
        client = FakeHarbor([project(public="true")])
        with self.assertRaises(harbor.LabError):
            client.project()
        self.assertEqual(len(client.calls), 1)

    def test_unconfirmed_configuration_fails(self):
        client = FakeHarbor([project("false"), None, project("false")])
        with self.assertRaises(harbor.LabError):
            client.project()

    def test_health_waits_for_overall_healthy(self):
        client = FakeHarbor([harbor.LabError("not ready"), {"status": "unhealthy"}, {"status": "healthy"}])
        client.health(timeout=1, interval=0)
        self.assertEqual(len(client.calls), 3)

    def test_health_timeout_fails(self):
        with self.assertRaises(harbor.LabError):
            FakeHarbor([]).health(timeout=0)

    def test_scan_waits_past_stale_success(self):
        client = FakeHarbor([scan("Success"), None, scan("Success"), scan("Running"),
                             scan("Success", "new"), {"report": {"vulnerabilities": []}}])
        client.scan(timeout=1, interval=0)
        self.assertEqual(len(client.calls), 6)

    def test_scan_error_is_not_reported_as_zero_vulnerabilities(self):
        client = FakeHarbor([scan("Pending"), None, scan("Error")])
        with self.assertRaises(harbor.LabError):
            client.scan(timeout=1, interval=0)

    def test_stale_error_is_not_new_scan_failure(self):
        client = FakeHarbor([scan("Error"), None, scan("Error"), scan("Running"),
                             scan("Success", "new"), {"report": {"vulnerabilities": []}}])
        client.scan(timeout=1, interval=0)
        self.assertEqual(len(client.calls), 6)

    def test_missing_report_is_not_zero_vulnerabilities(self):
        client = FakeHarbor([scan("Running"), None, scan("Success", "new"), {}])
        with self.assertRaises(harbor.LabError):
            client.scan(timeout=1, interval=0)

    def test_scan_timeout_fails(self):
        with self.assertRaises(harbor.LabError):
            FakeHarbor([scan("Pending"), None]).scan(timeout=0)


class PublishTests(unittest.TestCase):
    def run_publish(self, fail_login=False):
        with tempfile.TemporaryDirectory() as original:
            (Path(original) / "contexts").mkdir()
            (Path(original) / "contexts" / "marker").write_text("context metadata")
            client = Mock(password="synthetic-test-password")
            client.request.return_value = {"digest": "sha256:abc"}
            configs = []

            def output(command, **kwargs):
                if command[1:] == ["context", "show"]:
                    return "colima\n"
                return json.dumps(["localhost:8081/club/counter@sha256:abc"])

            def run(command, **kwargs):
                self.assertNotIn(client.password, command)
                config = Path(command[command.index("--config") + 1])
                configs.append(config)
                self.assertEqual(json.loads((config / "config.json").read_text()), {"currentContext": "colima"})
                self.assertTrue((config / "contexts/marker").exists())
                if "login" in command:
                    self.assertEqual(kwargs["input"], client.password + "\n")
                    if fail_login:
                        raise subprocess.CalledProcessError(1, command)

            with patch.dict(os.environ, {"DOCKER_CONFIG": original}), \
                 patch.object(harbor.subprocess, "check_output", side_effect=output), \
                 patch.object(harbor.subprocess, "run", side_effect=run):
                if fail_login:
                    with self.assertRaises(subprocess.CalledProcessError):
                        harbor.publish(client)
                    client.scan.assert_not_called()
                else:
                    harbor.publish(client)
                    client.scan.assert_called_once()
            self.assertTrue(configs)
            self.assertTrue(all(not p.exists() for p in configs))
            self.assertTrue((Path(original) / "contexts/marker").exists())

    def test_login_profile_deleted_after_success(self):
        self.run_publish()

    def test_login_profile_deleted_after_error(self):
        self.run_publish(fail_login=True)


if __name__ == "__main__":
    unittest.main()
