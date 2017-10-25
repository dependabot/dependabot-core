# Parse the Pipfile and Pipfile.lock to get a list of dependency versions.
import json

from pipfile.api import PipfileParser

def parse(directory):
    pipfile_dict = PipfileParser(directory + "/Pipfile").parse()
    lockfile_dict = json.loads(open(directory + "/Pipfile.lock", "r").read())

    packages = []

    for key in pipfile_dict["default"].keys():
        packages.append({ "name": key, "version": lockfile_dict["default"][key]["version"].replace('=', ''), "requirement": pipfile_dict["default"][key], "group": "default" })

    for key in pipfile_dict["develop"].keys():
        packages.append({ "name": key, "version": lockfile_dict["develop"][key]["version"].replace('=', ''), "requirement": pipfile_dict["develop"][key], "group": "develop" })

    return json.dumps({ "result": packages })
