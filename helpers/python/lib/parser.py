import json

import pip.req.req_file
from pip.download import PipSession

def parse(directory):
    requirements = pip.req.req_file.parse_requirements(
        directory + '/requirements.txt',
        session=PipSession()
    )

    packages = []

    try:
        for install_req in requirements:
            if len(install_req.req.specifier) == 1:
                specifier = next(spec for spec in install_req.req.specifier)

                if specifier.operator == "==":
                    packages.append({
                        "name": install_req.name,
                        "version": specifier.version
                    })
    except Exception as e:
        print(json.dumps({ "error": repr(e) }))
        exit(1)

    return json.dumps({ "result": packages })
