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
            if (not install_req.original_link and install_req.is_pinned):
                specifier = next(iter(install_req.specifier))

                packages.append({
                    "name": install_req.name,
                    "version": specifier.version,
                    "requirement": str(specifier)
                })
    except Exception as e:
        print(json.dumps({ "error": repr(e) }))
        exit(1)

    return json.dumps({ "result": packages })
