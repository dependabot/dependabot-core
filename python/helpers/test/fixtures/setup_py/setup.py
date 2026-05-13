from setuptools import setup

setup(
    name="myapp",
    version="1.0.0",
    install_requires=[
        "requests>=2.13.0",
        "urllib3==1.26.0",
    ],
    setup_requires=[
        "setuptools>=68.0",
    ],
    tests_require=[
        "pytest>=7.0",
    ],
    extras_require={
        "socks": ["PySocks>=1.5.6"],
        "dev": ["black==22.10.0"],
    },
)
