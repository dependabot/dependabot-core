import sys
import json

from lib import parser, hasher

if __name__ == "__main__":
    args = json.loads(sys.stdin.read())

    # TODO Python 3.10 added native switch statements, so switch this if/elif
    # to that once we drop support for 3.9.
    if args["function"] == "parse_requirements":
        print(parser.parse_requirements(args["args"][0]))
    elif args["function"] == "parse_setup":
        print(parser.parse_setup(args["args"][0]))
    elif args["function"] == "parse_pep621_dependencies":
        print(parser.parse_pep621_dependencies(args["args"][0]))
    elif args["function"] == "get_dependency_hash":
        print(hasher.get_dependency_hash(*args["args"]))
    elif args["function"] == "get_pipfile_hash":
        print(hasher.get_pipfile_hash(*args["args"]))
    elif args["function"] == "get_pyproject_hash":
        print(hasher.get_pyproject_hash(*args["args"]))
