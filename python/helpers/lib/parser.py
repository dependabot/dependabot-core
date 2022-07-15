import glob
import io
import json
import os.path
import re

import setuptools
import pip._internal.req.req_file
from pip._internal.network.session import PipSession
from pip._internal.req.constructors import (
    install_req_from_line,
    install_req_from_parsed_requirement,
)
# Inspired by pips internal check:
# https://github.com/pypa/pip/blob/0bb3ac87f5bb149bd75cceac000844128b574385/src/pip/_internal/req/req_file.py#L35
COMMENT_RE = re.compile(r'(^|\s+)#.*$')


def parse_requirements(directory):
    # Parse the requirements.txt
    requirement_packages = []
    requirement_files = glob.glob(os.path.join(directory, '*.txt')) \
        + glob.glob(os.path.join(directory, '**', '*.txt'))

    pip_compile_files = glob.glob(os.path.join(directory, '*.in')) \
        + glob.glob(os.path.join(directory, '**', '*.in'))

    def version_from_install_req(install_req):
        if install_req.is_pinned:
            return next(iter(install_req.specifier)).version

    for reqs_file in requirement_files + pip_compile_files:
        try:
            requirements = pip._internal.req.req_file.parse_requirements(
                reqs_file,
                session=PipSession()
            )
            for parsed_req in requirements:
                install_req = install_req_from_parsed_requirement(parsed_req)
                if install.req is None:
                    continue

                pattern = r"-[cr] (.*) \(line \d+\)"
                abs_path = re.search(pattern, install_req.comes_from).group(1)
                rel_path = os.path.relpath(abs_path, directory)

                requirement_packages.append({
                    "name": install_req.req.name,
                    "version": version_from_install_req(install_req),
                    "markers": str(install_req.markers) or None,
                    "file": rel_path,
                    "requirement": str(install_req.specifier) or None,
                    "extras": sorted(list(install_req.extras))
                })
        except Exception as e:
            print(json.dumps({"error": repr(e)}))
            exit(1)

    return json.dumps({"result": requirement_packages})


def parse_setup(directory):
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
            config = setuptools.config.read_configuration(setup_cfg_path)

            for req_type in [
                "setup_requires",
                "install_requires",
                "tests_require",
            ]:
                requires = config.get("options", {}).get(req_type, [])
                parse_requirements(requires, req_type, setup_cfg)

            extras_require = config.get("options", {}).get(
                "extras_require", {}
            )
            for key, value in extras_require.items():
                parse_requirements(
                    value, "extras_require:{}".format(key), setup_cfg
                )
        except Exception as e:
            print(json.dumps({"error": repr(e)}))
            exit(1)

    return json.dumps({"result": setup_packages})
