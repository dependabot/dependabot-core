import json
import os
import sys

import pytest

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), os.pardir, "lib")
)

from parser import parse_requirements, parse_requirements_v2  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def parse(fixture_dir):
    path = os.path.join(FIXTURES, fixture_dir)
    return json.loads(parse_requirements_v2(path))["result"]


def parse_files(path, files, requirement_files=None):
    for filename, content in files.items():
        file_path = path / filename
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content)
    return json.loads(
        parse_requirements_v2(str(path), requirement_files)
    )["result"]


def find_dep(deps, name):
    return next((d for d in deps if d["name"] == name), None)


def find_dep_in_file(deps, name, file_substring):
    return next(
        (d for d in deps
         if d["name"] == name and file_substring in d["file"]),
        None
    )


class TestParseRequirementsTxt:
    def test_legacy_result_projects_structured_declarations(self):
        path = os.path.join(FIXTURES, "requirements")
        legacy_result = json.loads(parse_requirements(path))["result"]
        structured_result = json.loads(parse_requirements_v2(path))["result"]

        assert legacy_result == structured_result["declarations"]

    def test_legacy_result_excludes_local_file_requirements(self, tmp_path):
        wheel = tmp_path / "requests-2.31.0-py3-none-any.whl"
        (tmp_path / "requirements.txt").write_text(
            f"requests @ {wheel.as_uri()}\n"
        )

        legacy_result = json.loads(parse_requirements(str(tmp_path)))["result"]
        structured_result = json.loads(
            parse_requirements_v2(str(tmp_path))
        )["result"]

        assert legacy_result == []
        requests = find_dep(structured_result["declarations"], "requests")
        assert requests["local"] is True

    def test_parses_basic_requirements(self):
        result = parse("requirements")
        deps = result["declarations"]
        requests = find_dep_in_file(deps, "requests", "requirements.txt")
        assert requests is not None
        assert requests["requirement"] == "<3.0,>=2.13.0"

    def test_parses_pinned_version(self):
        result = parse("requirements")
        deps = result["declarations"]
        urllib3 = find_dep(deps, "urllib3")
        assert urllib3 is not None
        assert urllib3["version"] == "1.26.0"
        assert urllib3["requirement"] == "==1.26.0"

    def test_parses_extras(self):
        result = parse("requirements")
        deps = result["declarations"]
        flask = find_dep(deps, "Flask")
        assert flask is not None
        assert flask["extras"] == ["async"]

    def test_strips_inline_comments(self):
        result = parse("requirements")
        deps = result["declarations"]
        boto3 = find_dep(deps, "boto3")
        assert boto3 is not None
        # boto3 has no version specifier, just a comment
        assert boto3["requirement"] is None or boto3["requirement"] == ""

    def test_file_path_is_relative(self):
        result = parse("requirements")
        deps = result["declarations"]
        for dep in deps:
            assert not os.path.isabs(dep["file"])

    def test_parses_dev_requirements(self):
        result = parse("requirements")
        deps = result["declarations"]
        black = find_dep(deps, "black")
        assert black is not None
        assert black["version"] == "22.10.0"
        assert "requirements-dev.txt" in black["file"]

    def test_parses_markers(self):
        result = parse("requirements")
        deps = result["declarations"]
        pywin32 = find_dep(deps, "pywin32")
        assert pywin32 is not None
        assert pywin32["markers"] == 'sys_platform == "win32"'

    def test_empty_directory_returns_empty(self):
        result = parse("requirements_empty")
        assert result == {
            "schema_version": 1,
            "declarations": [],
            "files": [],
            "edges": [],
            "roots": [],
            "components": [],
        }

    def test_constraint_file_deps(self):
        """Requirements with -c constraints should still parse the deps."""
        result = parse("requirements")
        deps = result["declarations"]
        # with_constraints.txt has requests
        req_files = [d["file"] for d in deps if d["name"] == "requests"]
        assert any("with_constraints" in f for f in req_files)

    def test_multiple_files_parsed(self):
        """All .txt files in the directory are parsed."""
        result = parse("requirements")
        deps = result["declarations"]
        files = {d["file"] for d in deps}
        assert any("requirements.txt" in f for f in files)
        assert any("requirements-dev.txt" in f for f in files)

    def test_flags_requirements_included_via_constraint(self):
        deps = parse("requirements")["declarations"]
        flags = {(d["file"], d["constraint"]) for d in deps}
        assert ("with_constraints.txt", False) in flags
        assert ("constraints.txt", True) in flags

    def test_returns_versioned_graph(self):
        result = parse("requirements")
        assert result["schema_version"] == 1
        assert {node["path"] for node in result["files"]} >= {
            "with_constraints.txt",
            "constraints.txt",
        }
        assert {
            (edge["from"], edge["to"], edge["type"])
            for edge in result["edges"]
        } >= {
            ("with_constraints.txt", "constraints.txt", "constraint"),
        }
        assert "with_constraints.txt" in result["roots"]

    def test_uses_pip_lines_options_and_followed_references(self, tmp_path):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": (
                    "--requirement child.txt --requirement ignored.txt\n"
                    "requests==2.31.0 \\\n"
                    "  --hash=sha256:abc \\\n"
                    "  --hash sha256:def # retained declaration comment\n"
                    "-e./local-package\n"
                    "-e git+https://example.com/repo.git#egg=flask\n"
                    "-r https://example.com/remote.txt\n"
                ),
                "child.txt": "urllib3==2.2.3\n",
                "ignored.txt": "certifi==2024.8.30\n",
                "local-package/pyproject.toml": (
                    "[project]\n"
                    "name = \"local-package\"\n"
                    "version = \"1.0.0\"\n"
                ),
            }
        )

        assert [
            (edge["from"], edge["to"], edge["remote"])
            for edge in result["edges"]
        ] == [
            ("requirements.txt", "child.txt", False),
            ("requirements.txt", "https://example.com/remote.txt", True),
        ]

        requests = find_dep(result["declarations"], "requests")
        assert requests["source"] == {"start_line": 2, "end_line": 4}
        assert requests["hashes"] == ["sha256:abc", "sha256:def"]
        flask = find_dep(result["declarations"], "flask")
        assert flask["editable"] is True
        assert flask["local"] is False

        component = next(
            component for component in result["components"]
            if "requirements.txt" in component["files"]
        )
        assert component["status"] == "partial"
        assert component["reasons"] == ["remote_reference", "local_path"]
        assert component["has_index_options"] is False
        assert component["source_spans_applicable"] is True
        assert "ignored.txt" not in component["files"]

    def test_partial_acyclic_component_preserves_constraint_roles(
        self,
        tmp_path
    ):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": (
                    "-c constraints.txt\n"
                    "-r https://example.com/remote.txt\n"
                    "requests==2.31.0\n"
                ),
                "constraints.txt": "urllib3==2.2.3\n",
            }
        )

        requests = find_dep(result["declarations"], "requests")
        urllib3 = find_dep(result["declarations"], "urllib3")
        assert requests["constraint"] is False
        assert urllib3["constraint"] is True

    def test_requirement_edge_inside_constraint_file_is_not_constraint(
        self,
        tmp_path
    ):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": (
                    "-c constraints.txt\n"
                    "-r https://example.com/remote.txt\n"
                ),
                "constraints.txt": (
                    "-r nested.txt\n"
                    "urllib3==2.2.3\n"
                ),
                "nested.txt": "certifi==2024.8.30\n",
            }
        )

        urllib3 = find_dep(result["declarations"], "urllib3")
        certifi = find_dep(result["declarations"], "certifi")
        assert urllib3["constraint"] is True
        assert certifi["constraint"] is False

    def test_records_index_options_after_other_options(self, tmp_path):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": (
                    "--trusted-host private.example.com "
                    "--index-url https://private.example.com/simple\n"
                    "requests==2.31.0\n"
                ),
            }
        )

        assert result["components"] == [
            {
                "id": "component-0",
                "files": ["requirements.txt"],
                "roots": ["requirements.txt"],
                "status": "complete",
                "reasons": [],
                "has_index_options": True,
                "source_spans_applicable": True,
            }
        ]

    def test_marks_changed_pip_decoding_as_unsafe_for_source_spans(
        self,
        tmp_path
    ):
        (tmp_path / "requirements.txt").write_bytes(
            (
                "# coding: latin-1\n"
                "# Å\n"
                "requests==2.31.0\n"
            ).encode("utf-8")
        )

        result = json.loads(parse_requirements_v2(str(tmp_path)))["result"]

        requests = find_dep(result["declarations"], "requests")
        assert requests["source"] == {"start_line": 4, "end_line": 4}
        assert result["components"][0]["source_spans_applicable"] is False

    def test_records_long_and_compact_reference_options(self, tmp_path):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": (
                    "-rchild.txt\n"
                    "--constraint=constraints.txt\n"
                ),
                "child.txt": "urllib3==2.2.3\n",
                "constraints.txt": "requests==2.31.0\n",
            }
        )

        assert result["edges"] == [
            {
                "from": "requirements.txt",
                "to": "child.txt",
                "type": "requirement",
                "remote": False,
                "source": {"start_line": 1, "end_line": 1},
            },
            {
                "from": "requirements.txt",
                "to": "constraints.txt",
                "type": "constraint",
                "remote": False,
                "source": {"start_line": 2, "end_line": 2},
            }
        ]

    def test_decodes_bom_encoded_requirement_files(self, tmp_path):
        (tmp_path / "requirements.txt").write_bytes(
            "requests==2.31.0\n".encode("utf-16")
        )

        result = json.loads(parse_requirements_v2(str(tmp_path)))["result"]

        requests = find_dep(result["declarations"], "requests")
        assert requests["source"] == {"start_line": 1, "end_line": 1}

    def test_normalizes_file_urls_for_declaration_sources(self, tmp_path):
        child = tmp_path / "child.txt"
        child.write_text("requests==2.31.0\n")
        (tmp_path / "requirements.txt").write_text(
            f"-r {child.resolve().as_uri()}\n"
        )

        result = json.loads(parse_requirements_v2(str(tmp_path)))["result"]

        requests = find_dep(result["declarations"], "requests")
        assert requests["file"] == "child.txt"
        assert requests["source"] == {"start_line": 1, "end_line": 1}

    def test_only_parses_selected_entry_files_and_their_references(
        self,
        tmp_path
    ):
        result = parse_files(
            tmp_path,
            {
                "requirements.txt": "-r constraints.txt\nrequests==2.31.0\n",
                "constraints.txt": "urllib3==2.2.3\n",
                "notes.txt": "Some release notes\n",
            },
            ["requirements.txt"]
        )

        assert {node["path"] for node in result["files"]} == {
            "requirements.txt",
            "constraints.txt",
        }
        assert {
            declaration["name"] for declaration in result["declarations"]
        } == {"requests", "urllib3"}

    def test_parses_cycles_independently_for_static_updates(self, tmp_path):
        result = parse_files(
            tmp_path,
            {
                "a.txt": "-r b.txt\nrequests==2.31.0\n",
                "b.txt": "-r a.txt\nurllib3==2.2.3\n",
            }
        )

        assert result["roots"] == []
        assert result["components"] == [
            {
                "id": "component-0",
                "files": ["a.txt", "b.txt"],
                "roots": [],
                "status": "partial",
                "reasons": ["cycle"],
                "has_index_options": False,
                "source_spans_applicable": True,
            }
        ]
        assert {
            declaration["name"] for declaration in result["declarations"]
        } == {"requests", "urllib3"}

    def test_missing_local_reference_remains_an_error(
        self,
        tmp_path,
        capsys
    ):
        (tmp_path / "requirements.txt").write_text("-r missing.txt\n")

        with pytest.raises(SystemExit):
            parse_requirements_v2(str(tmp_path))

        error = json.loads(capsys.readouterr().out)
        assert error["error"].startswith("InstallationError(")

    def test_reference_outside_fetched_files_remains_an_error(
        self,
        tmp_path,
        capsys
    ):
        (tmp_path.parent / "excluded.txt").write_text("requests==2.31.0\n")
        (tmp_path / "requirements.txt").write_text("-r ../excluded.txt\n")

        with pytest.raises(SystemExit):
            parse_requirements_v2(str(tmp_path))

        error = json.loads(capsys.readouterr().out)
        assert error["error"].startswith("InstallationError(")
        assert "outside the fetched source directory" in error["error"]
