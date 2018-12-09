from setuptools import setup, find_packages

file = open("some_file", "r")
file.read()

from split_settings import __version__

setup(name='python-package',
      version=__version__,
      description='Example setup.py',
      url='httos://github.com/example/python-package',
      author='Dependabot',
      scripts=[],
      packages=find_packages(),
      setup_requires=[
          'pytest-runner',
      ],
      install_requires=[
          'raven == 5.32.0',
      ],
      tests_require=[
          'pytest==2.9.1',
          'responses==0.5.1',
      ],
      extras_require=dict(
          API=[
              'flask==0.12.2',
          ],
          socks=['PySocks>=1.5.6, !=1.5.7'],
      ),
)
