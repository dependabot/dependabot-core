import json
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), os.pardir, "lib")
)

from parser import parse_requirements  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def parse(fixture_dir):
    path = os.path.join(FIXTURES, fixture_dir)
    result = json.loads(parse_requirements(path))
    return result


def find_dep(deps, name):
    return next((d for d in deps if d["name"] == name), None)


def find_dep_in_file(deps, name, file_substring):
    return next(
        (d for d in deps
         if d["name"] == name and file_substring in d["file"]),
        None
    )


class TestParseRequirementsTxt:
    def test_parses_basic_requirements(self):
        result = parse("requirements")
        deps = result["result"]
        requests = find_dep_in_file(deps, "requests", "requirements.txt")
        assert requests is not None
        assert requests["requirement"] == "<3.0,>=2.13.0"

    def test_parses_pinned_version(self):
        result = parse("requirements")
        deps = result["result"]
        urllib3 = find_dep(deps, "urllib3")
        assert urllib3 is not None
        assert urllib3["version"] == "1.26.0"
        assert urllib3["requirement"] == "==1.26.0"

    def test_parses_extras(self):
        result = parse("requirements")
        deps = result["result"]
        flask = find_dep(deps, "Flask")
        assert flask is not None
        assert flask["extras"] == ["async"]

    def test_strips_inline_comments(self):
        result = parse("requirements")
        deps = result["result"]
        boto3 = find_dep(deps, "boto3")
        assert boto3 is not None
        # boto3 has no version specifier, just a comment
        assert boto3["requirement"] is None or boto3["requirement"] == ""

    def test_file_path_is_relative(self):
        result = parse("requirements")
        deps = result["result"]
        for dep in deps:
            assert not os.path.isabs(dep["file"])

    def test_parses_dev_requirements(self):
        result = parse("requirements")
        deps = result["result"]
        black = find_dep(deps, "black")
        assert black is not None
        assert black["version"] == "22.10.0"
        assert "requirements-dev.txt" in black["file"]

    def test_parses_markers(self):
        result = parse("requirements")
        deps = result["result"]
        pywin32 = find_dep(deps, "pywin32")
        assert pywin32 is not None
        assert pywin32["markers"] == 'sys_platform == "win32"'

    def test_empty_directory_returns_empty(self):
        result = parse("requirements_empty")
        deps = result["result"]
        assert deps == []

    def test_constraint_file_deps(self):
        """Requirements with -c constraints should still parse the deps."""
        result = parse("requirements")
        deps = result["result"]
        # with_constraints.txt has requests
        req_files = [d["file"] for d in deps if d["name"] == "requests"]
        assert any("with_constraints" in f for f in req_files)

    def test_multiple_files_parsed(self):
        """All .txt files in the directory are parsed."""
        result = parse("requirements")
        deps = result["result"]
        files = {d["file"] for d in deps}
        assert any("requirements.txt" in f for f in files)
        assert any("requirements-dev.txt" in f for f in files)
