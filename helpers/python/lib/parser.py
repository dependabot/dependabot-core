import json
import re
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
                if (not install_req.original_link and install_req.is_pinned):
                    specifier = next(iter(install_req.specifier))

                    pattern = r"-[cr] (.*) \(line \d+\)"
                    abs_path = re.search(pattern, install_req.comes_from).group(1)
                    rel_path = os.path.relpath(abs_path, directory)

                    requirement_packages.append({
                        "name": install_req.req.name,
                        "version": specifier.version,
                        "file": rel_path,
                        "requirement": str(specifier)
                    })
        except Exception as e:
            print(json.dumps({ "error": repr(e) }))
            exit(1)


    # Parse the setup.py
    setup_packages = []
    if os.path.isfile(directory + '/setup.py'):
        def setup(*args, **kwargs):
            for arg in ['install_requires', 'tests_require']:
                for req in kwargs.get(arg):
                    install_req = InstallRequirement.from_line(req)
                    if (not install_req.original_link and install_req.is_pinned):
                        specifier = next(iter(install_req.specifier))
                        setup_packages.append({
                            "name": install_req.req.name,
                            "version": specifier.version,
                            "file": "setup.py",
                            "requirement": str(specifier)
                        })
        setuptools.setup = setup
        try:
            setup_file = open(directory + '/setup.py', 'r')
            exec(setup_file.read())
        except Exception as e:
            print(json.dumps({ "error": repr(e) }))
            exit(1)

    return json.dumps({ "result": requirement_packages + setup_packages })
