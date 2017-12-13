import hashin
import json

def get_hash(dependency_name, dependency_version, algorithm):
    hashes = hashin.get_package_hashes(
        dependency_name,
        version=dependency_version,
        algorithm=algorithm
    )

    return json.dumps({ "result": hashes["hashes"] })
