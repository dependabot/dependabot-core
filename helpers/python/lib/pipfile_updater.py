import json
import os

def update(directory):
   os.system("cd {0} && pipenv lock --keep-outdated 2>/dev/null".format(directory))
   os.system("cd {0} && pipenv lock --keep-outdated --requirements > requirements.txt 2>/dev/null".format(directory))
   os.system("cd {0} && pipenv lock --keep-outdated --dev > requirements-dev.txt 2>/dev/null".format(directory))

   lockfile = open(directory + "/Pipfile.lock", "r").read()
   requirements = open(directory + "/requirements.txt", "r").read()
   requirements_dev = open(directory + "/requirements-dev.txt", "r").read()
   result = { "result": { "Pipfile.lock": lockfile, "requirements.txt": requirements, "requirements-dev.txt": requirements_dev } }
   return json.dumps(result)
