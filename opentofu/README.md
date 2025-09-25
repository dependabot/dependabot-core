## `dependabot-opentofu`

OpenTofu support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell opentofu
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd opentofu && rspec
   ```

### Configuration

To enable OpenTofu support, add to your `dependabot.yml`:

```yaml
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "opentofu"
    directory: "/"
    schedule:
      interval: "weekly"
```

[core-repo]: https://github.com/dependabot/dependabot-core
