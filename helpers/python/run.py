import sys
import json

from lib import parser
from lib import hasher

if __name__ == "__main__":
    args = json.loads(sys.stdin.read())

    if args["function"] == "parse":
        print(parser.parse(args["args"][0]))
    if args["function"] == "get_hash":
        print(hasher.get_hash(*args["args"]))
