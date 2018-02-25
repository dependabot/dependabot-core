import json
import os

def update(directory):
   os.system("cd {0} && pipenv lock --keep-outdated".format(directory))

   lockfile = open(directory + "/Pipfile.lock", "r").read()
   return json.dumps({ "result": { "Pipfile.lock": lockfile } })
