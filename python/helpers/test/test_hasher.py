import json
import os
import ssl
import sys
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
