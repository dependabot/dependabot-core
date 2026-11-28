import json
import os
import ssl
import sys
import threading
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import MagicMock, patch
from urllib.error import URLError

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), os.pardir, "lib")
)

import hasher  # noqa: E402
import hashin as hashin_mod  # noqa: E402


class TestGetDependencyHash:
    @patch("hasher.hashin.get_package_hashes")
    def test_returns_hashes(self, mock_get):
        mock_get.return_value = {
            "hashes": [
                {"hash": "abc123", "platform": "linux"},
                {"hash": "def456", "platform": "macos"},
            ]
        }

        result = json.loads(hasher.get_dependency_hash(
            "requests", "2.28.0", "sha256"
        ))

        assert "result" in result
        assert len(result["result"]) == 2
        assert result["result"][0]["hash"] == "abc123"
        mock_get.assert_called_once()

    @patch("hasher.hashin.get_package_hashes")
    def test_custom_index_url(self, mock_get):
        mock_get.return_value = {"hashes": []}

        hasher.get_dependency_hash(
            "requests", "2.28.0", "sha256",
            index_url="https://custom.registry/simple/"
        )

        mock_get.assert_called_once_with(
            "requests",
            version="2.28.0",
            algorithm="sha256",
            index_url="https://custom.registry/simple/"
        )

    @patch("hasher.hashin.get_package_hashes")
    def test_package_not_found(self, mock_get):
        mock_get.side_effect = hashin_mod.PackageNotFoundError(
            "no-such-package"
        )

        result = json.loads(hasher.get_dependency_hash(
            "no-such-package", "1.0.0", "sha256"
        ))

        assert "error" in result

    @patch("hasher.hashin.get_package_hashes")
    def test_ssl_certificate_error(self, mock_get):
        ssl_error = ssl.SSLError(
            "CERTIFICATE_VERIFY_FAILED: unable to get local issuer"
        )
        mock_get.side_effect = URLError(ssl_error)

        result = json.loads(hasher.get_dependency_hash(
            "requests", "2.28.0", "sha256"
        ))

        assert "error" in result
        assert "CERTIFICATE_VERIFY_FAILED" in result["error"]

    @patch("hasher.hashin.get_package_hashes")
    def test_non_ssl_url_error_raises(self, mock_get):
        mock_get.side_effect = URLError("Connection refused")

        try:
            hasher.get_dependency_hash("requests", "2.28.0", "sha256")
            assert False, "Expected URLError to be raised"
        except URLError:
            pass  # expected


PACKAGE_JSON = {
    "info": {"name": "demo"},
    "releases": {
        "1.0": [{
            "url": "https://files.example.com/demo-1.0.tar.gz",
            "digests": {"sha256": "abc123"},
        }],
    },
}


@contextmanager
def package_index(json_path):
    """Serve PACKAGE_JSON at json_path only; every other path is a 404."""
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.path != json_path:
                self.send_error(404)
                return
            body = json.dumps(PACKAGE_JSON).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield "http://127.0.0.1:%d" % server.server_port, requests
    finally:
        server.shutdown()
        server.server_close()


class TestGetDependencyHashFromIndex:
    def test_index_served_under_a_path(self):
        with package_index("/api/pypi/pypi-remote/pypi/demo/json") as (
            host, requests
        ):
            result = json.loads(hasher.get_dependency_hash(
                "demo", "1.0", "sha256",
                index_url=host + "/api/pypi/pypi-remote/simple"
            ))

        assert result == {"result": [{"hash": "abc123"}]}
        assert requests == ["/api/pypi/pypi-remote/pypi/demo/json"]

    def test_index_under_a_path_with_json_at_the_host_root(self):
        with package_index("/pypi/demo/json") as (host, requests):
            result = json.loads(hasher.get_dependency_hash(
                "demo", "1.0", "sha256", index_url=host + "/mirror/simple/"
            ))

        assert result == {"result": [{"hash": "abc123"}]}
        assert requests == ["/mirror/pypi/demo/json", "/pypi/demo/json"]

    def test_index_at_the_host_root(self):
        with package_index("/pypi/demo/json") as (host, requests):
            result = json.loads(hasher.get_dependency_hash(
                "demo", "1.0", "sha256", index_url=host + "/simple"
            ))

        assert result == {"result": [{"hash": "abc123"}]}
        assert requests == ["/pypi/demo/json"]


class TestGetPipfileHash:
    @patch("builtins.open")
    @patch("hasher.plette")
    def test_returns_hash(self, mock_plette, mock_open):
        mock_pipfile = MagicMock()
        mock_pipfile.get_hash.return_value.value = "abc123hash"
        mock_plette.Pipfile.load.return_value = mock_pipfile

        result = json.loads(hasher.get_pipfile_hash("/tmp/project"))

        assert result["result"] == "abc123hash"
        mock_open.assert_called_once_with("/tmp/project/Pipfile")


class TestGetPyprojectHash:
    @patch("hasher.Factory")
    def test_returns_hash(self, mock_factory_cls):
        mock_poetry = MagicMock()
        mock_poetry.locker._get_content_hash.return_value = "xyz789hash"
        mock_factory_cls.return_value.create_poetry.return_value = mock_poetry

        result = json.loads(hasher.get_pyproject_hash("/tmp/project"))

        assert result["result"] == "xyz789hash"
        mock_factory_cls.return_value.create_poetry.assert_called_once_with(
            "/tmp/project"
        )
