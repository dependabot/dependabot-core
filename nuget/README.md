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

### Known limitations

#### Projects suppressing `NU1701`

If a project explicitly includes `NU1701` in its `<NoWarn>` property, Dependabot will likely be unable to process updates for that project. The `NU1701` warning indicates that a package's target framework may not be compatible with the project's target framework, and suppressing it allows NuGet to restore packages that would otherwise be rejected.

Dependabot cannot determine why or under what circumstances ignoring target framework compatibility is safe for a given project. As a result, the final package compatibility check will fail and Dependabot will err on the side of caution and not submit a pull request.

[core-repo]: https://github.com/dependabot/dependabot-core
