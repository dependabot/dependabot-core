import sys
import json

from lib import parser, hasher

if __name__ == "__main__":
    args = json.loads(sys.stdin.read())

    match args["function"]:
        case "parse_requirements":
            print(parser.parse_requirements(args["args"][0]))
        case "parse_setup":
            print(parser.parse_setup(args["args"][0]))
        case "parse_pep621_pep735_dependencies":
            print(parser.parse_pep621_pep735_dependencies(args["args"][0]))
        case "get_dependency_hash":
            print(hasher.get_dependency_hash(*args["args"]))
        case "get_pipfile_hash":
            print(hasher.get_pipfile_hash(*args["args"]))
        case "get_pyproject_hash":
            print(hasher.get_pyproject_hash(*args["args"]))
