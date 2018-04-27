import json
import os

def update(directory):
   os.system("cd {0} && eval \"$(pyenv init -)\" && PIPENV_YES=true pipenv lock --keep-outdated >/dev/null 2>&1".format(directory))
   os.system("cd {0} && eval \"$(pyenv init -)\" && PIPENV_YES=true pipenv lock --keep-outdated --requirements > requirements.txt >/dev/null 2>&1".format(directory))
   os.system("cd {0} && eval \"$(pyenv init -)\" && PIPENV_YES=true pipenv lock --keep-outdated --dev > requirements-dev.txt >/dev/null 2>&1".format(directory))

   lockfile = open(directory + "/Pipfile.lock", "r").read()
   requirements = open(directory + "/requirements.txt", "r").read()
   requirements_dev = open(directory + "/requirements-dev.txt", "r").read()
   result = { "result": { "Pipfile.lock": lockfile, "requirements.txt": requirements, "requirements-dev.txt": requirements_dev } }
   return json.dumps(result)
