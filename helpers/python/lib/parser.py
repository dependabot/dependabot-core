from itertools import chain
import glob
import io
import json
import os.path
import re

import setuptools
import pip._internal.req.req_file
from pip._internal.download import PipSession
from pip._internal.req.req_install import InstallRequirement

def parse_requirements(directory):
    # Parse the requirements.txt
    requirement_packages = []

    requirement_files = glob.glob(os.path.join(directory, '*requirements*.txt')) \
                        + glob.glob(os.path.join(directory, 'requirements', '*.txt'))

    pip_compile_files = glob.glob(os.path.join(directory, '*requirements*.in')) \
                        + glob.glob(os.path.join(directory, 'requirements', '*.in'))

    for reqs_file in requirement_files + pip_compile_files:
        try:
            requirements = pip._internal.req.req_file.parse_requirements(
                reqs_file,
                session=PipSession()
            )
            for install_req in requirements:
                if install_req.original_link:
                    continue
                if install_req.is_pinned:
                    version = next(iter(install_req.specifier)).version
                else:
                    version = None

                pattern = r"-[cr] (.*) \(line \d+\)"
                abs_path = re.search(pattern, install_req.comes_from).group(1)
                rel_path = os.path.relpath(abs_path, directory)

                requirement_packages.append({
                    "name": install_req.req.name,
                    "version": version,
                    "file": rel_path,
                    "requirement": str(install_req.specifier) or None
                })
        except Exception as e:
            print(json.dumps({ "error": repr(e) }))
            exit(1)

    return json.dumps({ "result": requirement_packages })

def parse_setup(directory):
    # Parse the setup.py
    setup_packages = []
    if os.path.isfile(directory + '/setup.py'):
        def parse_requirement(req):
            install_req = InstallRequirement.from_line(req)
            if install_req.original_link:
                return
            if install_req.is_pinned:
                version = next(iter(install_req.specifier)).version
            else:
                version = None
            setup_packages.append({
                "name": install_req.req.name,
                "version": version,
                "file": "setup.py",
                "requirement": str(install_req.specifier) or None
            })

        def setup(*args, **kwargs):
            for arg in ['setup_requires', 'install_requires', 'tests_require']:
                if not kwargs.get(arg):
                    continue
                for req in kwargs.get(arg):
                    parse_requirement(req)
            for req in chain.from_iterable(kwargs.get('extras_require', {}).values()):
                parse_requirement(req)
        setuptools.setup = setup

        def noop(*args, **kwargs):
            pass

        def fake_parse(*args, **kwargs):
            return []

        global fake_open
        def fake_open(*args, **kwargs):
            content = ("VERSION = (0, 0, 1)\n"
                       "__version__ = '0.0.1'\n"
                       "__author__ = 'someone'\n"
                       "__title__ = 'something'\n"
                       "__description__ = 'something'\n"
                       "__author_email__ = 'something'\n"
                       "__license__ = 'something'\n"
                       "__url__ = 'something'\n")
            return io.StringIO(content)

        try:
            content = open(directory + '/setup.py', 'r').read()

            # Remove `print`, `open`, `log` and import statements
            content = re.sub(r"print\s*\(", "noop(", content)
            content = re.sub(r"log\s*(\.\w+)*\(", "noop(", content)
            content = re.sub(r"\b(\w+\.)*(open|file)\s*\(", "fake_open(", content)
            content = content.replace("parse_requirements(", "fake_parse(")
            version_re = re.compile(r"^.*import.*__version__.*$", re.MULTILINE)
            content = re.sub(version_re, "", content)

            # Set variables likely to be imported
            __version__ = '0.0.1'
            __author__ = 'someone'
            __title__ = 'something'
            __description__ = 'something'
            __author_email__ = 'something'
            __license__ = 'something'
            __url__ = 'something'

            # Exec the setup.py
            exec(content) in globals(), locals()
        except:
            pass

    return json.dumps({ "result": setup_packages })
