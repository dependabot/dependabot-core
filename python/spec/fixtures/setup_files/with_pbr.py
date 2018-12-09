from setuptools import setup

setup(
    packages=setuptools.find_packages(),
    install_requires=['raven'],
    setup_requires=['pbr'],
    pbr=True)
