# Julia Dependency Updates

Dependabot can update dependencies in Julia packages that use the built-in package manager and manifest files.

## Supported versioning

Julia uses semantic versioning with some additional rules for pre-1.0 versions:

- `1.2.3` - Standard semver
- `0.2.3` - Updates only allow patch and minor within 0.x
- `0.0.3` - Updates only allow patch within 0.0.x

## Files updated

The following files are updated:

- `(Julia)Project.toml` - Direct dependency requirements
- `(Julia)Manifest.toml` / `(Julia)Manifest-vX.Y.toml` - Lock file with exact versions

If a `Julia*.toml` file is present it is preferred over `Project.toml` and `Manifest.toml`.
Also a `(Julia)Manifest-vX.Y.toml` file is preferred over `Manifest.toml`, where `X.Y` matches the current Julia version.

## Configuration

Enable Julia updates in your `dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "julia"
    directory: "/"
    schedule:
      interval: "weekly"
```

## Private registries

To use private Julia package registries, configure authentication:

```yaml
registries:
  julia-pkg:
    type: "julia-registry"
    url: "https://private.registry/org"
    token: ${{secrets.REGISTRY_TOKEN}}
```
