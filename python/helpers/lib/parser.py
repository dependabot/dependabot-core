import glob
import io
import json
import os.path
import re
import urllib.parse
import urllib.request

import configparser

from packaging.requirements import InvalidRequirement, Requirement
# TODO: Replace 3p package `tomli` with 3.11's new stdlib `tomllib` once we
#       drop support for Python 3.10.
import tomli

# Inspired by pips internal check:
# https://github.com/pypa/pip/blob/0bb3ac87f5bb149bd75cceac000844128b574385/src/pip/_internal/req/req_file.py#L35
COMMENT_RE = re.compile(r'(^|\s+)#.*$')
REQUIREMENTS_SCHEMA_VERSION = 1


def parse_pep621_pep735_dependencies(pyproject_path):
    with open(pyproject_path, "rb") as file:
        project_toml = tomli.load(file)

    def version_from_req(specifier_set):
        if (len(specifier_set) == 1 and
                next(iter(specifier_set)).operator in {"==", "==="}):
            return next(iter(specifier_set)).version

    def original_requirement_from_entry(entry, req):
        """Extract the original requirement string.

        The packaging library normalizes specifiers
        (removes spaces, reorders operators), but we
        need the original so the file updater regex
        can match the file content.
        """
        # Strip the name (and any extras like [filecache]) from the start
        remainder = entry[len(req.name):].strip()

        # Strip extras bracket if present, e.g. [filecache]
        if remainder.startswith("["):
            close = remainder.index("]")
            remainder = remainder[close + 1:].strip()

        # Strip markers from the end, e.g. "; python_version < '3.4'"
        if req.marker:
            marker_pos = remainder.find(";")
            if marker_pos != -1:
                remainder = remainder[:marker_pos].strip()

        return remainder

    def parse_requirement(entry, pyproject_path, requirement_type=None):
        try:
            req = Requirement(entry)
        except InvalidRequirement as e:
            print(json.dumps({"error": repr(e)}))
            exit(1)
        else:
            data = {
                "name": req.name,
                "version": version_from_req(req.specifier),
                "markers": str(req.marker) or None,
                "file": pyproject_path,
                "requirement": str(req.specifier),
                "source_requirement":
                    original_requirement_from_entry(entry, req),
                "extras": sorted(list(req.extras)),
                "requirement_type": requirement_type,
            }
            return data

    def parse_toml_section_pep621_dependencies(
        pyproject_path, dependencies, requirement_type=None
    ):
        requirement_packages = []

        for dependency in dependencies:
            parsed_dependency = parse_requirement(
                dependency, pyproject_path, requirement_type
            )
            requirement_packages.append(parsed_dependency)

        return requirement_packages

    def parse_toml_section_pep735_dependencies(
        pyproject_path,
        dependency_groups,
        group_name,
        visited=None,
    ):
        requirement_packages = []
        visited = visited or set()

        if group_name in visited:
            return requirement_packages

        visited.add(group_name)
        dependencies = dependency_groups.get(group_name, [])
        for entry in dependencies:
            # Handle direct requirement
            if isinstance(entry, str):
                parsed_dependency = parse_requirement(
                    entry, pyproject_path, group_name
                )
                requirement_packages.append(parsed_dependency)
            # Handle include-group directive
            elif isinstance(entry, dict) and "include-group" in entry:
                included_group = entry["include-group"]
                requirement_packages.extend(
                    parse_toml_section_pep735_dependencies(
                        pyproject_path,
                        dependency_groups,
                        included_group,
                        visited
                    )
                )

        return requirement_packages

    dependencies = []

    if 'project' in project_toml:
        project_section = project_toml['project']

        if 'dependencies' in project_section:
            dependencies_toml = project_section['dependencies']
            runtime_dependencies = parse_toml_section_pep621_dependencies(
                pyproject_path,
                dependencies_toml,
                "dependencies"
            )
            dependencies.extend(runtime_dependencies)

        if 'optional-dependencies' in project_section:
            optional_dependencies_toml = project_section[
                'optional-dependencies'
            ]
            for group in optional_dependencies_toml:
                group_dependencies = parse_toml_section_pep621_dependencies(
                    pyproject_path,
                    optional_dependencies_toml[group],
                    group
                )
                dependencies.extend(group_dependencies)

    if 'dependency-groups' in project_toml:
        dependency_groups = project_toml['dependency-groups']
        for group_name in dependency_groups:
            group_dependencies = parse_toml_section_pep735_dependencies(
                pyproject_path, dependency_groups, group_name
            )
            dependencies.extend(group_dependencies)

    if 'build-system' in project_toml:
        build_system_section = project_toml['build-system']
        if 'requires' in build_system_section:
            build_system_dependencies = parse_toml_section_pep621_dependencies(
                pyproject_path,
                build_system_section['requires'],
                "build-system.requires"
            )
            dependencies.extend(build_system_dependencies)

    return json.dumps({"result": dependencies})


def _parse_requirements_result(directory, requirement_files=None):
    try:
        return RequirementsFileParser(
            directory,
            requirement_files=requirement_files
        ).parse()
    except Exception as e:
        print(json.dumps({"error": repr(e)}))
        exit(1)


def parse_requirements(directory, requirement_files=None):
    result = _parse_requirements_result(directory, requirement_files)
    return json.dumps({
        "result": [
            declaration
            for declaration in result["declarations"]
            if not declaration["local"]
        ]
    })


def parse_requirements_v2(directory, requirement_files=None):
    result = _parse_requirements_result(directory, requirement_files)
    return json.dumps({"result": result})


class TrackingLineIterator:
    def __init__(self, content):
        self._lines = iter(enumerate(content.splitlines(), start=1))
        self.last_line_number = None

    def __iter__(self):
        return self

    def __next__(self):
        line = next(self._lines)
        self.last_line_number = line[0]
        return line


class RequirementsFileParser:
    def __init__(self, directory, requirement_files=None):
        import pip._internal.req.req_file as req_file
        from pip._internal.exceptions import InstallationError
        from pip._internal.network.session import PipSession
        from pip._internal.req.constructors import (
            install_req_from_parsed_requirement,
        )

        self.directory = os.path.abspath(directory)
        self.requirement_files = requirement_files
        self.req_file = req_file
        self.installation_error = InstallationError
        self.install_req_from_parsed_requirement = (
            install_req_from_parsed_requirement
        )
        self.session = PipSession()
        self.line_parser = self.req_file.get_line_parser(None)
        self.pip_parser = self.req_file.RequirementsFileParser(
            self.session,
            self.line_parser
        )
        self.direct_requirements = {}
        self.edges = []
        self.has_index_options = set()
        self.has_local_path = set()
        self.source_spans = {}

    def parse(self):
        original_directory = os.getcwd()
        os.chdir(self.directory)
        try:
            files = self._parse_local_files()
            components = self._components(files)
            declarations = self._declarations(components)
            component_ids = {
                filename: component["id"]
                for component in components
                for filename in component["files"]
            }

            return {
                "schema_version": REQUIREMENTS_SCHEMA_VERSION,
                "declarations": declarations,
                "files": [
                    {
                        "path": filename,
                        "component_id": component_ids[filename],
                    }
                    for filename in sorted(files)
                ],
                "edges": self.edges,
                "roots": sorted({
                    root
                    for component in components
                    for root in component["roots"]
                }),
                "components": components,
            }
        finally:
            os.chdir(original_directory)

    def _parse_local_files(self):
        if self.requirement_files is None:
            files = {
                self._relative_path(path)
                for suffix in ("*.txt", "*.in")
                for path in glob.glob(
                    os.path.join(self.directory, "**", suffix),
                    recursive=True
                )
            }
        else:
            files = {
                self._relative_local_path(
                    os.path.join(self.directory, filename)
                )
                for filename in self.requirement_files
            }
        pending = sorted(files)
        parsed = set()

        while pending:
            filename = pending.pop(0)
            if filename in parsed:
                continue

            parsed.add(filename)
            absolute_path = os.path.join(self.directory, filename)
            self.source_spans[filename] = self._physical_line_spans(
                absolute_path
            )
            direct_requirements = []

            for line in self.pip_parser._parse_file(absolute_path, False):
                if self._has_index_options(line):
                    self.has_index_options.add(filename)

                parsed_requirement = self.req_file.handle_line(
                    line,
                    session=self.session
                )
                if parsed_requirement is not None:
                    direct_requirements.append(parsed_requirement)
                    if self._is_local_path(parsed_requirement):
                        self.has_local_path.add(filename)
                    continue

                edge = self._edge_from_line(filename, line)
                if edge is None:
                    continue

                self.edges.append(edge)
                if edge["remote"]:
                    continue

                target = edge["to"]
                target_path = os.path.join(self.directory, target)
                if not os.path.isfile(target_path):
                    raise self.installation_error(
                        "Could not open requirements file: "
                        f"[Errno 2] No such file or directory: '{target_path}'"
                    )

                if target not in files:
                    files.add(target)
                    pending.append(target)

            self.direct_requirements[filename] = direct_requirements

        return files

    @staticmethod
    def _has_index_options(line):
        return bool(
            getattr(line.opts, "index_url", None) or
            getattr(line.opts, "extra_index_urls", None) or
            getattr(line.opts, "no_index", False)
        )

    def _edge_from_line(self, filename, line):
        if line.requirement is not None:
            return None

        if line.opts.requirements:
            target = line.opts.requirements[0]
            edge_type = "requirement"
        elif line.opts.constraints:
            target = line.opts.constraints[0]
            edge_type = "constraint"
        else:
            return None

        resolved_target, remote = self._resolve_reference(filename, target)
        return {
            "from": filename,
            "to": resolved_target,
            "type": edge_type,
            "remote": remote,
            "source": self._source_span(filename, line.lineno),
        }

    def _resolve_reference(self, filename, target):
        parsed = urllib.parse.urlparse(target)
        if parsed.scheme and parsed.scheme != "file":
            return target, True

        target_path = self._file_url_path(target)

        if not os.path.isabs(target_path):
            target_path = os.path.join(
                os.path.dirname(os.path.join(self.directory, filename)),
                target_path
            )

        return self._relative_local_path(target_path), False

    def _components(self, files):
        local_edges = [edge for edge in self.edges if not edge["remote"]]
        neighbours = {filename: set() for filename in files}
        for edge in local_edges:
            neighbours[edge["from"]].add(edge["to"])
            neighbours[edge["to"]].add(edge["from"])

        components = []
        remaining = set(files)
        while remaining:
            first = min(remaining, key=self._file_sort_key)
            component_files = set()
            pending = [first]
            while pending:
                filename = pending.pop()
                if filename in component_files:
                    continue

                component_files.add(filename)
                pending.extend(neighbours[filename] - component_files)

            remaining -= component_files
            components.append(
                self._component(
                    f"component-{len(components)}",
                    component_files,
                    local_edges
                )
            )

        return components

    def _component(self, component_id, files, local_edges):
        component_edges = [
            edge for edge in local_edges
            if edge["from"] in files and edge["to"] in files
        ]
        incoming = {filename: 0 for filename in files}
        for edge in component_edges:
            incoming[edge["to"]] += 1

        roots = {
            filename for filename, count in incoming.items()
            if count == 0
        }
        roots |= {
            edge["to"]
            for edge in component_edges
            if edge["type"] == "constraint"
            and edge["from"] in roots
            and edge["from"].endswith(".in")
            and edge["to"] == f"{edge['from'][:-3]}.txt"
        }

        reasons = []
        if any(edge["remote"] and edge["from"] in files
               for edge in self.edges):
            reasons.append("remote_reference")
        if self._has_cycle(files, component_edges):
            reasons.append("cycle")
        if self.has_local_path.intersection(files):
            reasons.append("local_path")

        return {
            "id": component_id,
            "files": sorted(files),
            "roots": sorted(roots, key=self._file_sort_key),
            "status": "partial" if reasons else "complete",
            "reasons": reasons,
            "has_index_options": bool(
                self.has_index_options.intersection(files)
            ),
        }

    def _has_cycle(self, files, edges):
        children = {filename: [] for filename in files}
        for edge in edges:
            children[edge["from"]].append(edge["to"])

        visiting = set()
        visited = set()

        def visit(filename):
            if filename in visiting:
                return True
            if filename in visited:
                return False

            visiting.add(filename)
            if any(visit(child) for child in children[filename]):
                return True
            visiting.remove(filename)
            visited.add(filename)
            return False

        return any(visit(filename) for filename in files)

    def _declarations(self, components):
        declarations = {}
        for component in components:
            for requirement, constraint in self._component_requirements(
                component
            ):
                declaration = self._declaration(
                    requirement,
                    constraint=constraint
                )
                if declaration is None:
                    continue

                source = declaration["source"]
                key = (
                    declaration["file"],
                    source["start_line"],
                    source["end_line"],
                )
                previous = declarations.get(key)
                if previous is None:
                    declarations[key] = declaration
                elif previous["constraint"] and not declaration["constraint"]:
                    declarations[key] = declaration

        return list(declarations.values())

    def _component_requirements(self, component):
        if component["status"] == "complete":
            return (
                (requirement, None)
                for root in component["roots"]
                for requirement in self.req_file.parse_requirements(
                    os.path.join(self.directory, root),
                    session=self.session
                )
            )

        if component["roots"] and "cycle" not in component["reasons"]:
            return self._partial_component_requirements(component)

        return (
            (requirement, None)
            for filename in component["files"]
            for requirement in self.direct_requirements[filename]
        )

    def _partial_component_requirements(self, component):
        component_files = set(component["files"])
        edges = {
            filename: [
                edge for edge in self.edges
                if not edge["remote"] and
                edge["from"] == filename and
                edge["to"] in component_files
            ]
            for filename in component_files
        }
        pending = [(root, False) for root in component["roots"]]
        visited = set()

        while pending:
            filename, constraint = pending.pop(0)
            state = (filename, constraint)
            if state in visited:
                continue

            visited.add(state)
            for requirement in self.direct_requirements[filename]:
                yield requirement, constraint

            for edge in edges[filename]:
                # pip derives the child's role from this edge, not its parent.
                pending.append((edge["to"], edge["type"] == "constraint"))

    def _declaration(self, parsed_requirement, constraint=None):
        install_req = self.install_req_from_parsed_requirement(
            parsed_requirement
        )
        if install_req.req is None:
            return None

        filename, line_number = self._requirement_source(parsed_requirement)
        return {
            "name": install_req.req.name,
            "version": self._version_from_install_req(install_req),
            "markers": str(install_req.markers) or None,
            "file": filename,
            "requirement": str(install_req.specifier) or None,
            "source_requirement": parsed_requirement.requirement,
            "extras": sorted(list(install_req.extras)),
            "constraint": (
                parsed_requirement.constraint
                if constraint is None
                else constraint
            ),
            "editable": parsed_requirement.is_editable,
            "local": install_req.link is not None and install_req.link.is_file,
            "hashes": self._hashes(parsed_requirement),
            "source": self._source_span(filename, line_number),
        }

    def _is_local_path(self, parsed_requirement):
        install_req = self.install_req_from_parsed_requirement(
            parsed_requirement
        )
        return install_req.link is not None and install_req.link.is_file

    def _requirement_source(self, parsed_requirement):
        match = re.fullmatch(
            r"line (?P<line>\d+) of (?P<filename>.*)",
            parsed_requirement.line_source or ""
        )
        if match is None:
            raise ValueError(
                "pip requirement did not include a source location"
            )

        return (
            self._relative_local_path(
                self._file_url_path(match.group("filename"))
            ),
            int(match.group("line"))
        )

    def _source_span(self, filename, start_line):
        end_line = self.source_spans[filename].get(start_line)
        if end_line is None:
            raise ValueError(
                f"pip requirement source line {start_line} was not found "
                f"in {filename}"
            )

        return {
            "start_line": start_line,
            "end_line": end_line,
        }

    def _physical_line_spans(self, filename):
        with open(filename, "rb") as file:
            content = self.req_file._decode_req_file(
                file.read(),
                filename
            )

        lines = TrackingLineIterator(content)
        spans = {}
        for start_line, _ in self.req_file.join_lines(lines):
            spans[start_line] = lines.last_line_number
        return spans

    def _relative_path(self, path):
        return os.path.relpath(path, self.directory)

    @staticmethod
    def _file_url_path(path):
        parsed = urllib.parse.urlparse(path)
        if parsed.scheme == "file":
            return urllib.request.url2pathname(parsed.path)

        return path

    def _relative_local_path(self, path):
        absolute_path = os.path.abspath(path)
        common_path = os.path.commonpath([self.directory, absolute_path])
        if common_path != self.directory:
            raise self.installation_error(
                "Requirements file is outside the fetched source directory: "
                f"'{absolute_path}'"
            )

        return self._relative_path(absolute_path)

    @staticmethod
    def _file_sort_key(filename):
        return (0 if filename.endswith(".txt") else 1, filename)

    @staticmethod
    def _version_from_install_req(install_req):
        if install_req.is_pinned:
            return next(iter(install_req.specifier)).version

    @staticmethod
    def _hashes(parsed_requirement):
        hashes = (parsed_requirement.options or {}).get("hashes", {})
        return [
            f"{algorithm}:{digest}"
            for algorithm in sorted(hashes)
            for digest in hashes[algorithm]
        ]


def parse_setup(directory):
    global setuptools
    import setuptools
    from pip._internal.req.constructors import install_req_from_line

    def version_from_install_req(install_req):
        if install_req.is_pinned:
            return next(iter(install_req.specifier)).version

    def parse_requirement(req, req_type, filename):
        install_req = install_req_from_line(req)
        if install_req.original_link:
            return

        setup_packages.append(
            {
                "name": install_req.req.name,
                "version": version_from_install_req(install_req),
                "markers": str(install_req.markers) or None,
                "file": filename,
                "requirement": str(install_req.specifier) or None,
                "requirement_type": req_type,
                "extras": sorted(list(install_req.extras)),
            }
        )

    def parse_requirements(requires, req_type, filename):
        for req in requires:
            req = COMMENT_RE.sub('', req)
            req = req.strip()
            parse_requirement(req, req_type, filename)

    # Parse the setup.py and setup.cfg
    setup_py = "setup.py"
    setup_py_path = os.path.join(directory, setup_py)
    setup_cfg = "setup.cfg"
    setup_cfg_path = os.path.join(directory, setup_cfg)
    setup_packages = []

    if os.path.isfile(setup_py_path):

        def setup(*args, **kwargs):
            for arg in ["setup_requires", "install_requires", "tests_require"]:
                requires = kwargs.get(arg, [])
                parse_requirements(requires, arg, setup_py)
            extras_require_dict = kwargs.get("extras_require", {})
            for key, value in extras_require_dict.items():
                parse_requirements(
                    value, "extras_require:{}".format(key), setup_py
                )

        setuptools.setup = setup

        def noop(*args, **kwargs):
            pass

        def fake_parse(*args, **kwargs):
            return []

        global fake_open

        def fake_open(*args, **kwargs):
            content = (
                "VERSION = ('0', '0', '1+dependabot')\n"
                "__version__ = '0.0.1+dependabot'\n"
                "__author__ = 'someone'\n"
                "__title__ = 'something'\n"
                "__description__ = 'something'\n"
                "__author_email__ = 'something'\n"
                "__license__ = 'something'\n"
                "__url__ = 'something'\n"
            )
            return io.StringIO(content)

        content = open(setup_py_path, "r").read()

        # Remove `print`, `open`, `log` and import statements
        content = re.sub(r"print\s*\(", "noop(", content)
        content = re.sub(r"log\s*(\.\w+)*\(", "noop(", content)
        content = re.sub(r"\b(\w+\.)*(open|file)\s*\(", "fake_open(", content)
        content = content.replace("parse_requirements(", "fake_parse(")
        version_re = re.compile(r"^.*import.*__version__.*$", re.MULTILINE)
        content = re.sub(version_re, "", content)

        # Set variables likely to be imported
        __version__ = "0.0.1+dependabot"
        __author__ = "someone"
        __title__ = "something"
        __description__ = "something"
        __author_email__ = "something"
        __license__ = "something"
        __url__ = "something"

        # Run as main (since setup.py is a script)
        __name__ = "__main__"

        # Exec the setup.py
        exec(content) in globals(), locals()

    if os.path.isfile(setup_cfg_path):
        try:
            config = configparser.ConfigParser()
            config.read(setup_cfg_path)

            for req_type in [
                "setup_requires",
                "install_requires",
                "tests_require",
            ]:
                requires = config.get(
                    'options',
                    req_type, fallback='').splitlines()
                requires = [req for req in requires if req.strip()]
                parse_requirements(requires, req_type, setup_cfg)

            if config.has_section('options.extras_require'):
                extras_require = config._sections['options.extras_require']
                for key, value in extras_require.items():
                    requires = value.splitlines()
                    requires = [req for req in requires if req.strip()]
                    parse_requirements(
                        requires,
                        f"extras_require:{key}",
                        setup_cfg
                    )

        except Exception as e:
            print(json.dumps({"error": repr(e)}))
            exit(1)

    return json.dumps({"result": setup_packages})
