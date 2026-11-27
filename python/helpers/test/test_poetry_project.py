import json
import os

import pytest

from lib.poetry_project import parse_poetry_project

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures", "poetry")


def parse(name):
    return json.loads(parse_poetry_project(os.path.join(FIXTURES, name)))


def locked(result, name, version):
    return next(
        p for p in result["locked"]
        if p["name"] == name and p["version"] == version
    )


def resolved_versions(package, dependency_name):
    dependency = next(
        d for d in package["dependencies"] if d["name"] == dependency_name
    )
    return [r["version"] for r in dependency["resolved"]]


class TestMultipleLockedVersions:
    def test_reports_every_locked_version_with_its_markers(self):
        result = parse("multiple_locked_versions")["result"]

        urllib3 = [p for p in result["locked"] if p["name"] == "urllib3"]
        assert {p["version"]: p["markers"] for p in urllib3} == {
            "1.26.20": {"main": 'python_version == "3.9"'},
            "2.2.1": {"main": 'python_version >= "3.10"'},
        }
        assert all(p["groups_from_lockfile"] for p in urllib3)

    def test_links_each_version_to_the_child_it_installs_with(self):
        result = parse("multiple_locked_versions")["result"]

        old = locked(result, "requests", "2.32.5")
        new = locked(result, "requests", "2.34.2")
        assert resolved_versions(old, "urllib3") == ["1.26.20"]
        assert resolved_versions(new, "urllib3") == ["2.2.1"]

    def test_reports_each_declared_constraint(self):
        result = parse("multiple_locked_versions")["result"]

        urllib3 = [d for d in result["declared"] if d["name"] == "urllib3"]
        assert [(d["constraint"], d["markers"]) for d in urllib3] == [
            ("1.26.20", 'python_version < "3.10"'),
            ("2.2.1", 'python_version >= "3.10"'),
        ]


class TestLockWithoutGroups:
    def test_walks_declared_groups_through_the_lockfile(self):
        result = parse("lock_without_groups")["result"]

        assert result["groups_and_markers_locked"] is False
        certifi = locked(result, "certifi", "2024.2.2")
        assert certifi["groups"] == ["main"]
        assert certifi["groups_from_lockfile"] is False
        assert certifi["markers"] is None

        alabaster = next(
            p for p in result["locked"] if p["name"] == "alabaster"
        )
        assert alabaster["groups"] == ["docs"]


class TestInvalidProject:
    def test_reports_poetry_errors_and_exits_non_zero(self, capsys):
        with pytest.raises(SystemExit) as exit_info:
            parse("invalid_config")

        assert exit_info.value.code == 1
        result = json.loads(capsys.readouterr().out)
        assert "result" not in result
        assert result["error_class"] == "RuntimeError"
        assert "secondary" in result["error"]


class TestDeclaredGitReferences:
    def test_reports_which_kind_of_git_reference_was_declared(self):
        result = parse("git_refs")["result"]

        refs = {d["name"]: d["git_ref"] for d in result["declared"]}
        assert refs["fastapi"] == {
            "tag": "0.110.0", "branch": None, "rev": None
        }
        assert refs["toml"] == {"tag": None, "branch": "master", "rev": None}
