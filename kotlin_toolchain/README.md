## `dependabot-kotlin_toolchain`

Native JetBrains Kotlin Toolchain support for [`dependabot-core`][core-repo].

The ecosystem reads the project-local `kotlin`/`kotlin.bat` wrapper version and
updates:

- Maven dependencies in `project.yaml`, `module.yaml`, and module templates;
- `libs.versions.toml` or `gradle/libs.versions.toml`;
- explicit built-in technology versions under `settings`;
- the Kotlin Toolchain wrapper itself.

Use `package-ecosystem: "kotlin-toolchain"` in Dependabot configuration. The
ecosystem does not require a Gradle build file.

The wrapper version selects the manifest compatibility profile. Known 0.11 and
0.12 schema features are handled explicitly; later versions use a conservative
forward-compatible profile that keeps updating known declarations and follows
nested module templates.

### Running locally

1. Start a development shell:

   ```console
   bin/docker-dev-shell kotlin_toolchain
   ```

2. Run tests:

   ```console
   cd kotlin_toolchain
   rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
