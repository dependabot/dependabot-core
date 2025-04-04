from setuptools import setup, find_packages

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
      install_requires=[
          'boto3==1.3.1',
          'flake8==2.5.4',
          'gocardless_pro==0.2.3',
          'numpy==1.11.0',
          'pandas==0.19.2',
          'pep8==1.7.0',
          'psycopg2==2.6.1',
          'raven==5.32.0',
          'requests==2.12.4',
          'scipy==0.18.1',
          'scikit-learn==0.18.1',
      ]
      )
