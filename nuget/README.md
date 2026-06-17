## `dependabot-nuget`

NuGet support for [`dependabot-core`][core-repo].

### Developing locally

Open the solution file at `helpers/lib/NuGetUpdater/NuGetUpdater.slnx` in your preferred IDE.

### Running Nuget-ruby locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell nuget
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd nuget && rspec
   ```

### Per-dependency prerelease opt-in

By default, Dependabot only considers stable (non-prerelease) versions when updating NuGet
dependencies. You can opt individual dependencies in to prerelease resolution using the `allow`
list in your `dependabot.yml`:

```yaml
updates:
  - package-ecosystem: "nuget"
    directory: "/"
    schedule:
      interval: "weekly"
    allow:
      - dependency-name: "MyCompany.*"
        prerelease: true
      - dependency-name: "Newtonsoft.Json"
        prerelease: true
```

Only entries with `prerelease: true` will receive prerelease updates. All other dependencies
continue to receive only stable version updates (the default behavior).

Wildcard patterns in `dependency-name` (e.g., `MyCompany.*`) are supported and match using the
same glob-style rules as other allow-list entries.

### Known limitations

#### Projects suppressing `NU1701`

If a project explicitly includes `NU1701` in its `<NoWarn>` property, Dependabot will likely be unable to process updates for that project. The `NU1701` warning indicates that a package's target framework may not be compatible with the project's target framework, and suppressing it allows NuGet to restore packages that would otherwise be rejected.

Dependabot cannot determine why or under what circumstances ignoring target framework compatibility is safe for a given project. As a result, the final package compatibility check will fail and Dependabot will err on the side of caution and not submit a pull request.

[core-repo]: https://github.com/dependabot/dependabot-core
