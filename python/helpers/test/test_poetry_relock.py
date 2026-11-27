import json
import os
import shutil
import subprocess
import sys

import pytest

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "poetry")
HELPERS_DIR = os.path.join(os.path.dirname(__file__), os.pardir)
RUN_PY = os.path.join(HELPERS_DIR, "run.py")


def copy_fixture(name, tmp_path):
    directory = tmp_path / name
    shutil.copytree(os.path.join(FIXTURES, name), directory)
    return directory


def relock(directory, names):
    # Run through run.py so the exit code and error JSON are covered too.
    input_json = json.dumps({
        "function": "relock_poetry_project",
        "args": [str(directory), names],
    })
    result = subprocess.run(
        [sys.executable, RUN_PY], input=input_json,
        capture_output=True, text=True, cwd=HELPERS_DIR,
    )
    return result.returncode, json.loads(result.stdout)


def locked_version(lockfile, name):
    blocks = lockfile.split("[[package]]")
    block = next(b for b in blocks if f'name = "{name}"' in b)
    return block.split('version = "')[1].split('"')[0]


class TestRelockErrors:
    def test_rejects_packages_outside_the_project(self, tmp_path):
        directory = copy_fixture("relock", tmp_path)

        status, output = relock(directory, ["not-a-dependency"])

        assert status == 1
        assert output["error_class"] == "PackageNotInProjectError"
        assert "not-a-dependency" in output["error"]

    def test_reports_poetry_config_errors(self, tmp_path):
        directory = copy_fixture("invalid_config", tmp_path)

        status, output = relock(directory, ["requests"])

        assert status == 1
        assert output["error_class"] == "RuntimeError"
        assert "The Poetry configuration is invalid" in output["error"]


# These resolve against PyPI.
@pytest.mark.network
class TestRelock:
    def test_updates_only_the_named_package(self, tmp_path):
        directory = copy_fixture("relock", tmp_path)

        status, output = relock(directory, ["Six"])

        assert status == 0
        result = output["result"]
        assert result["versions"] == {"six": ["1.17.0"]}
        assert locked_version(result["lockfile"], "six") == "1.17.0"
        # idna allows ^3.4 and has newer releases, but stays locked.
        assert locked_version(result["lockfile"], "idna") == "3.4"
        assert (directory / "poetry.lock").read_text() == result["lockfile"]

    def test_solver_failures_have_their_own_error_class(self, tmp_path):
        directory = copy_fixture("relock", tmp_path)
        pyproject = directory / "pyproject.toml"
        pyproject.write_text(
            pyproject.read_text().replace('six = "^1.15"', 'six = ">=99"')
        )

        status, output = relock(directory, ["six"])

        assert status == 1
        assert output["error_class"] == "SolverProblemError"
        assert "version solving failed." in output["error"]

    def test_reports_every_locked_version_of_a_package(self, tmp_path):
        directory = copy_fixture("multiple_locked_versions", tmp_path)

        status, output = relock(directory, ["urllib3"])

        assert status == 0
        assert sorted(output["result"]["versions"]["urllib3"]) == [
            "1.26.20", "2.2.1"
        ]

    def test_keeps_crlf_line_endings(self, tmp_path):
        directory = copy_fixture("relock", tmp_path)
        lock = directory / "poetry.lock"
        lock.write_bytes(lock.read_bytes().replace(b"\n", b"\r\n"))

        status, output = relock(directory, ["six"])

        assert status == 0
        assert "\r\n" in output["result"]["lockfile"]
