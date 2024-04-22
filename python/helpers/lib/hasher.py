import hashin
import json
import plette
import traceback
from poetry.factory import Factory


def get_dependency_hash(dependency_name, dependency_version, algorithm):
    try:
      hashes = hashin.get_package_hashes(
          dependency_name,
          version=dependency_version,
          algorithm=algorithm
      )
      return json.dumps({"result": hashes["hashes"]})
    except hashin.PackageNotFoundError as e:
      return json.dumps({"error": repr(e), "error_class:" :
                         e.__class__.__name__, "trace:":
                         ''.join(traceback.format_stack())})


def get_pipfile_hash(directory):
    with open(directory + '/Pipfile') as f:
        pipfile = plette.Pipfile.load(f)

    return json.dumps({"result": pipfile.get_hash().value})


def get_pyproject_hash(directory):
    p = Factory().create_poetry(directory)

    return json.dumps({"result": p.locker._get_content_hash()})
