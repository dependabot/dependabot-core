import json
import os
import subprocess
import sys

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
HELPERS_DIR = os.path.join(os.path.dirname(__file__), os.pardir)
RUN_PY = os.path.join(HELPERS_DIR, "run.py")
LIB_DIR = os.path.join(HELPERS_DIR, "lib")


def run_helper(function, args):
    input_json = json.dumps({"function": function, "args": args})
    result = subprocess.run(
        [sys.executable, RUN_PY],
        input=input_json,
        capture_output=True,
        text=True,
        cwd=HELPERS_DIR,
    )
    assert result.returncode == 0, (
        f"run.py failed: {result.stderr}"
    )
    return json.loads(result.stdout)


class TestRunRouting:
    def test_helper_module_starts_without_importing_setuptools(self):
        script = f"""
import builtins
import sys

real_import = builtins.__import__

def import_without_setuptools(name, *args, **kwargs):
    if name == "setuptools" or name.startswith("setuptools."):
        raise AssertionError("setuptools imported during helper startup")
    return real_import(name, *args, **kwargs)

builtins.__import__ = import_without_setuptools
sys.path.insert(0, {LIB_DIR!r})
import parser
"""
        result = subprocess.run(
            [sys.executable, "-c", script],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, result.stderr

    def test_parse_pep621_routing(self):
        fixture = os.path.join(FIXTURES, "pep621_dependencies.toml")
        result = run_helper("parse_pep621_pep735_dependencies", [fixture])

        assert "result" in result
        names = {d["name"] for d in result["result"]}
        assert "requests" in names

    def test_parse_setup_routing(self):
        fixture_dir = os.path.join(FIXTURES, "setup_py")
        result = run_helper("parse_setup", [fixture_dir])

        assert "result" in result
        names = {d["name"] for d in result["result"]}
        assert "requests" in names

    def test_parse_requirements_routing(self):
        fixture_dir = os.path.join(FIXTURES, "requirements")
        result = run_helper("parse_requirements", [fixture_dir])

        assert "result" in result
        assert isinstance(result["result"], list)
        names = {declaration["name"] for declaration in result["result"]}
        assert "requests" in names

    def test_parse_requirements_v2_routing(self):
        fixture_dir = os.path.join(FIXTURES, "requirements")
        result = run_helper("parse_requirements_v2", [fixture_dir])

        assert "result" in result
        assert result["result"]["schema_version"] == 1
        names = {
            declaration["name"]
            for declaration in result["result"]["declarations"]
        }
        assert "requests" in names
