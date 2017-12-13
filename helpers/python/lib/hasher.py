import hashin
import json

def get_hash(dependency_name, dependency_version):
    hashes = hashin.get_package_hashes(
        dependency_name,
        version=dependency_version
    )

    return json.dumps({ "result": hashes["hashes"] })
