---
applyTo: "updater/**"
---

# Updater & Native Helpers

## Container Path Mapping

The `updater/` directory on the host is mounted as `dependabot-updater/` inside containers. Always use `dependabot-updater` when referencing paths in container commands.

## Running Updater Tests

```bash
# Quick one-off test run:
bin/test --workdir updater {ecosystem} rspec spec/path/to/spec.rb

# Interactive development:
bin/docker-dev-shell {ecosystem}
# Then inside the container:
cd dependabot-updater && rspec spec
```

## Native Helpers

- Located in `{ecosystem}/helpers/`
- Run exclusively within containers — they will not work on the host
- Rebuild after changes: `{ecosystem}/helpers/build`
- Changes are **not** automatically reflected in the container — you must rebuild

## Debugging

All debugging commands must be run inside the dev container. Start one first:

```bash
bin/docker-dev-shell {ecosystem}
```

Then use `bin/dry-run.rb` to test against real repositories:

```bash
# Enable helper debug output
DEBUG_HELPERS=true bin/dry-run.rb {ecosystem} {repo}

# Debug a specific native helper function
DEBUG_FUNCTION=function_name bin/dry-run.rb {ecosystem} {repo}

# Profile performance
bin/dry-run.rb {ecosystem} {repo} --profile
```
