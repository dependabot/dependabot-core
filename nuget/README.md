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

Run the reusable C# test suite in the NuGet development container:

```
$ bin/test nuget ./script/run-csharp-tests
```

### Known limitations

#### C# file-based apps

C# file-based app support is gated by the `nuget_update_file_based_apps` experiment
(disabled by default). Package directives are read from the leading directive
block, not from strings, comments, or source files under a C# project directory.
Versionless `#:package` references participate in NuGet discovery. When Central
Package Management is enabled, updates change the version in
`Directory.Packages.props` (or its imported version properties) and preserve the
versionless directive.

#### Projects suppressing `NU1701`

If a project explicitly includes `NU1701` in its `<NoWarn>` property, Dependabot will likely be unable to process updates for that project. The `NU1701` warning indicates that a package's target framework may not be compatible with the project's target framework, and suppressing it allows NuGet to restore packages that would otherwise be rejected.

Dependabot cannot determine why or under what circumstances ignoring target framework compatibility is safe for a given project. As a result, the final package compatibility check will fail and Dependabot will err on the side of caution and not submit a pull request.

[core-repo]: https://github.com/dependabot/dependabot-core
