## `dependabot-gradle`

Gradle support for [`dependabot-core`][core-repo].

### Dependency locking and transitive security updates

Dependabot fetches committed `gradle.lockfile` files and regenerates them with
Gradle after updating supported dependency declarations.

The `gradle_transitive_security_updates` experiment additionally discovers
dependencies declared only in those lockfiles. For security updates, Dependabot
pins the dependency to a fixed version in the affected lockfiles and runs Gradle
to verify every affected configuration, without temporary version overrides or
changes to build-file declarations. Gradle and any required private repositories
must be accessible.

Dependabot tries compatible, non-ignored security fixes in ascending order,
preserves already-safe locked versions, and rejects fixes that would change a
vulnerable dependency's version flavor (for example, Android to JRE).
Implicit `buildSrc` builds are validated independently, without committing
additional settings files.

Lockfile entries with version formats unsupported by Dependabot's comparison
logic are skipped with a warning and preserved unchanged during other updates.

If a parent dependency, strict constraint, or enforced BOM prevents resolution,
Dependabot reports that the security update is not possible. It does not add
permanent overrides or update parent dependencies automatically. Transitive
version updates and projects without committed lockfiles are not included.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell gradle
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd gradle && rspec
   ```

Gradle-specific updater operation tests run in this suite so they have access to
the Gradle implementation and fixtures.

[core-repo]: https://github.com/dependabot/dependabot-core
