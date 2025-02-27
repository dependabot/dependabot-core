from pathlib import Path

from setuptools import find_packages, setup

from unidown import static_data

# get long description
with Path('README.rst').open(mode='r', encoding='UTF-8') as reader:
    long_description = reader.read()

setup(
      name=static_data.NAME,
      version=static_data.VERSION,
      description='Example setup.py',
      url='httos://github.com/example/python-package',
      author='Dependabot',
      scripts=[],
      packages=find_packages(),
      setup_requires=[
          'numpy==1.11.0',
          'pytest-runner',
      ],
      install_requires=[
          'requests[security] == 2.12.*',
          'scipy==0.18.1',
          'scikit-learn==0.18.1',
      ],
      tests_require=[
          'pytest==2.9.1',
          'responses==0.5.1',
      ],
      extras_require=dict(
          API=[
              'flask==0.12.2',
          ],
      ),
)
