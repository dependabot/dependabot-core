from setuptools import setup, find_packages

reqs = [str(r.req) for r in parse_requirements('requirements.txt', session=PipSession()) if r.req is not None]

setup(name='python-package',
      version='0.0',
      description='Example setup.py',
      url='httos://github.com/example/python-package',
      author='Dependabot',
      scripts=[],
      packages=find_packages(),
      setup_requires=[
          'numpy==1.11.0',
          'pytest-runner',
      ],
      install_requires=reqs,
      tests_require=[
          'pytest==2.9.1',
          'responses==0.5.1',
      ]
      )
