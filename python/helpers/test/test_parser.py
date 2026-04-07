import json
import os
import sys

# Add the helpers lib directory to the Python path so we can import parser
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), os.pardir, "lib")
)

from parser import parse_pep621_pep735_dependencies  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def parse(fixture_name):
    path = os.path.join(FIXTURES, fixture_name)
    result = json.loads(parse_pep621_pep735_dependencies(path))
    return result["result"]


def find_dep(deps, name):
    return next((d for d in deps if d["name"] == name), None)


# ---------------------------------------------------------------------------
# PEP 621 project.dependencies
# ---------------------------------------------------------------------------
class TestPep621Dependencies:
    def test_parses_runtime_dependencies(self):
        deps = parse("pep621_dependencies.toml")
        requests = find_dep(deps, "requests")
        assert requests is not None
        # packaging normalises specifier order alphabetically by operator
        assert requests["requirement"] == "<3.0,>=2.13.0"
        assert requests["requirement_type"] == "dependencies"

    def test_parses_exact_version(self):
        deps = parse("pep621_dependencies.toml")
        urllib3 = find_dep(deps, "urllib3")
        assert urllib3 is not None
        assert urllib3["version"] == "1.26.0"
        assert urllib3["requirement"] == "==1.26.0"

    def test_parses_optional_dependencies(self):
        deps = parse("pep621_dependencies.toml")
        pysocks = find_dep(deps, "PySocks")
        assert pysocks is not None
        assert pysocks["requirement_type"] == "socks"

    def test_optional_dependency_specifiers(self):
        deps = parse("pep621_dependencies.toml")
        pysocks = find_dep(deps, "PySocks")
        # packaging normalises specifiers: sorted, no spaces
        assert "!=" in pysocks["requirement"]
        assert ">=" in pysocks["requirement"]

    def test_parses_multiple_optional_groups(self):
        deps = parse("pep621_dependencies.toml")
        group_types = {d["requirement_type"] for d in deps}
        assert "socks" in group_types
        assert "tests" in group_types

    def test_parses_build_system_requires(self):
        deps = parse("pep621_dependencies.toml")
        setuptools = find_dep(deps, "setuptools")
        assert setuptools is not None
        assert setuptools["requirement_type"] == "build-system.requires"
        assert setuptools["requirement"] == ">=68.0"


# ---------------------------------------------------------------------------
# PEP 621 extras
# ---------------------------------------------------------------------------
class TestPep621Extras:
    def test_parses_extras(self):
        deps = parse("pep621_extras.toml")
        cc = find_dep(deps, "cachecontrol")
        assert cc is not None
        assert cc["extras"] == ["filecache"]

    def test_extras_requirement(self):
        deps = parse("pep621_extras.toml")
        cc = find_dep(deps, "cachecontrol")
        assert cc["requirement"] == ">=0.14.0"


# ---------------------------------------------------------------------------
# PEP 735 dependency-groups
# ---------------------------------------------------------------------------
class TestPep735DependencyGroups:
    def test_parses_dependency_group(self):
        deps = parse("pep735_dependency_groups.toml")
        pytest_dep = find_dep(deps, "pytest")
        assert pytest_dep is not None
        assert pytest_dep["requirement_type"] == "dev"
        assert pytest_dep["version"] == "7.1.3"

    def test_include_group_resolves(self):
        deps = parse("pep735_dependency_groups.toml")
        # "lint" group includes "dev" via include-group, plus flake8
        lint_deps = [d for d in deps if d["requirement_type"] == "lint"]
        lint_names = {d["name"] for d in lint_deps}
        assert "flake8" in lint_names
        # include-group pulls dev deps into lint but they keep their
        # original group name, so they appear under "dev" requirement_type
        all_names = {d["name"] for d in deps}
        assert "pytest" in all_names
        assert "black" in all_names

    def test_include_group_lists_all_resolved_deps(self):
        deps = parse("pep735_dependency_groups.toml")
        # pytest appears twice: once from direct "dev" processing and
        # once from "lint" including "dev" (both with requirement_type="dev"
        # because included deps keep their original group name)
        pytests = [d for d in deps if d["name"] == "pytest"]
        assert len(pytests) == 2
        assert all(d["requirement_type"] == "dev" for d in pytests)


# ---------------------------------------------------------------------------
# Markers
# ---------------------------------------------------------------------------
class TestMarkers:
    def test_parses_markers(self):
        deps = parse("pep621_markers.toml")
        requests = find_dep(deps, "requests")
        assert requests is not None
        assert requests["markers"] == 'python_version >= "3.8"'

    def test_requirement_with_markers(self):
        deps = parse("pep621_markers.toml")
        requests = find_dep(deps, "requests")
        assert requests["requirement"] == ">=2.13.0"


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------
class TestEdgeCases:
    def test_no_dependencies(self):
        deps = parse("no_dependencies.toml")
        assert deps == []

    def test_only_build_system(self):
        deps = parse("pep621_only_build_system.toml")
        assert len(deps) == 2
        names = {d["name"] for d in deps}
        assert "setuptools" in names
        assert "wheel" in names
        assert all(
            d["requirement_type"] == "build-system.requires" for d in deps
        )

    def test_empty_dependency_lists(self):
        deps = parse("pep621_empty_deps.toml")
        assert deps == []

    def test_multiple_extras_on_single_dep(self):
        deps = parse("pep621_multiple_extras.toml")
        boto3 = find_dep(deps, "boto3")
        assert boto3 is not None
        assert boto3["extras"] == ["crt", "s3"]
        assert boto3["requirement"] == ">=1.28.0"

    def test_arbitrary_equality_operator(self):
        deps = parse("pep621_arbitrary_equality.toml")
        numpy = find_dep(deps, "numpy")
        assert numpy is not None
        assert numpy["version"] == "1.24.0rc1"
        assert numpy["requirement"] == "===1.24.0rc1"

    def test_no_version_specifier(self):
        deps = parse("pep621_no_version.toml")
        requests = find_dep(deps, "requests")
        assert requests is not None
        assert requests["version"] is None
        assert requests["requirement"] == ""

    def test_cyclic_include_group_does_not_loop(self):
        deps = parse("pep735_cycle.toml")
        names = [d["name"] for d in deps]
        # Both groups should be processed without infinite recursion
        assert "requests" in names
        assert "flask" in names
