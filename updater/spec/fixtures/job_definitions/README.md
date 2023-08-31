### Job Definition Fixtures

These fixtures match the file format consumed by dependabot/cli.

#### Creating a fixture

We can generate these files from real projects using the CLI tool, e.g.

```sh
dependabot update bundler dependabot/dependabot-core -o test.yml
```

The resultant `test.yml` file will contain an `input` attribute which can be
extracted to use as a fixture, e.g.

```yml
input:
  # The entire input object can be extracted to a fixture file.
  job:
    package-manager: bundler
    ...
```

**Maintainers**: It is also possible to generate this file from the service,
refer to internal documentation.

