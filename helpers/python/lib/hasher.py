import hashin
import json
import pipfile
from poetry.poetry import Poetry

def get_dependency_hash(dependency_name, dependency_version, algorithm):
    hashes = hashin.get_package_hashes(
        dependency_name,
        version=dependency_version,
        algorithm=algorithm
    )

    return json.dumps({ "result": hashes["hashes"] })

def get_pipfile_hash(directory):
    p = pipfile.load(directory + '/Pipfile')

    return json.dumps({ "result": p.hash })

def get_pyproject_hash(directory):
    p = Poetry.create(directory)

    return json.dumps({ "result": p.locker._get_content_hash() })
