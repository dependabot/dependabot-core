import setuptools

def _main():
    setuptools.setup(name='python-package',
          version='0.0',
          description='Example setup.py',
          url='httos://github.com/example/python-package',
          author='Dependabot',
          scripts=[],
          packages=setuptools.find_packages(),
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
          ),
    )

if __name__ == "__main__":
    _main()
