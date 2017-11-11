import json
import re
import io
import os.path

import setuptools
import pip.req.req_file
from pip.download import PipSession
from pip.req.req_install import InstallRequirement

def parse(directory):
    # Parse the requirements.txt
    requirement_packages = []
    if os.path.isfile(directory + '/requirements.txt'):
        try:
            requirements = pip.req.req_file.parse_requirements(
                directory + '/requirements.txt',
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


    # Parse the setup.py
    setup_packages = []
    if os.path.isfile(directory + '/setup.py'):
        def setup(*args, **kwargs):
            for arg in ['install_requires', 'tests_require']:
                if not kwargs.get(arg):
                    continue
                for req in kwargs.get(arg):
                    install_req = InstallRequirement.from_line(req)
                    if install_req.original_link:
                        continue
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
        def noop(*args, **kwargs):
            pass
        def fake_open(*args, **kwargs):
            return io.StringIO("VERSION = (0, 0, 1)\n__version__ = '0.0.1'\n")
        setuptools.setup = setup
        try:
            setup_file = open(directory + '/setup.py', 'r')
            content = setup_file.read()
            content = content.replace("print(", "noop(")
            content = re.sub(r"\bopen\(", "fake_open(", content)
            content = content.replace("codec.open(", "fake_open(")
            exec(content)
        except Exception as e:
            print(json.dumps({ "error": repr(e) }))
            exit(1)

    return json.dumps({ "result": requirement_packages + setup_packages })
