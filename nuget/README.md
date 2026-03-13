## `dependabot-nuget`

NuGet support for [`dependabot-core`][core-repo].

### Developing locally

Open the solution file at `helpers/lib/NuGetUpdater/NuGetUpdater.sln` in your preferred IDE.

### Running Nuget-ruby locally

1. Start a development shell

   ```
   $ bin/docker-dev-shell nuget
   ```

2. Run tests

   ```
   [dependabot-core-dev] ~ $ cd nuget && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
