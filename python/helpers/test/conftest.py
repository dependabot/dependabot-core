def pytest_configure(config):
    config.addinivalue_line(
        "markers", "network: needs PyPI (deselect with -m 'not network')"
    )
