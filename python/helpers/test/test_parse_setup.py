import json
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), os.pardir, "lib")
)

from parser import parse_setup  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def parse(fixture_dir):
    path = os.path.join(FIXTURES, fixture_dir)
    result = json.loads(parse_setup(path))
    return result


def find_dep(deps, name):
    return next((d for d in deps if d["name"] == name), None)


# ---------------------------------------------------------------------------
# setup.py parsing
# ---------------------------------------------------------------------------
class TestSetupPy:
    def test_parses_install_requires(self):
        result = parse("setup_py")
        deps = result["result"]
        requests = find_dep(deps, "requests")
        assert requests is not None
        assert requests["requirement"] == ">=2.13.0"
        assert requests["requirement_type"] == "install_requires"
        assert requests["file"] == "setup.py"

    def test_parses_pinned_version(self):
        result = parse("setup_py")
        deps = result["result"]
        urllib3 = find_dep(deps, "urllib3")
        assert urllib3 is not None
        assert urllib3["version"] == "1.26.0"

    def test_parses_setup_requires(self):
        result = parse("setup_py")
        deps = result["result"]
        setuptools = find_dep(deps, "setuptools")
        assert setuptools is not None
        assert setuptools["requirement_type"] == "setup_requires"

    def test_parses_tests_require(self):
        result = parse("setup_py")
        deps = result["result"]
        pytest = find_dep(deps, "pytest")
        assert pytest is not None
        assert pytest["requirement_type"] == "tests_require"

    def test_parses_extras_require(self):
        result = parse("setup_py")
        deps = result["result"]
        pysocks = find_dep(deps, "PySocks")
        assert pysocks is not None
        assert pysocks["requirement_type"] == "extras_require:socks"

    def test_parses_multiple_extras_groups(self):
        result = parse("setup_py")
        deps = result["result"]
        extras = [d for d in deps if d["requirement_type"].startswith(
            "extras_require:"
        )]
        groups = {d["requirement_type"] for d in extras}
        assert "extras_require:socks" in groups
        assert "extras_require:dev" in groups

    def test_strips_comments(self):
        result = parse("setup_py_comments")
        deps = result["result"]
        requests = find_dep(deps, "requests")
        assert requests is not None
        assert requests["requirement"] == ">=2.13.0"


# ---------------------------------------------------------------------------
# setup.cfg parsing
# ---------------------------------------------------------------------------
class TestSetupCfg:
    def test_parses_install_requires(self):
        result = parse("setup_cfg")
        deps = result["result"]
        requests = find_dep(deps, "requests")
        assert requests is not None
        assert requests["requirement"] == ">=2.13.0"
        assert requests["requirement_type"] == "install_requires"
        assert requests["file"] == "setup.cfg"

    def test_parses_pinned_version(self):
        result = parse("setup_cfg")
        deps = result["result"]
        urllib3 = find_dep(deps, "urllib3")
        assert urllib3 is not None
        assert urllib3["version"] == "1.26.0"

    def test_parses_setup_requires(self):
        result = parse("setup_cfg")
        deps = result["result"]
        setuptools = find_dep(deps, "setuptools")
        assert setuptools is not None
        assert setuptools["requirement_type"] == "setup_requires"

    def test_parses_tests_require(self):
        result = parse("setup_cfg")
        deps = result["result"]
        pytest = find_dep(deps, "pytest")
        assert pytest is not None
        assert pytest["requirement_type"] == "tests_require"

    def test_parses_extras_require(self):
        result = parse("setup_cfg")
        deps = result["result"]
        pysocks = find_dep(deps, "PySocks")
        assert pysocks is not None
        assert pysocks["requirement_type"] == "extras_require:socks"

    def test_empty_directory_returns_empty(self):
        result = parse("requirements_empty")
        deps = result["result"]
        assert deps == []
