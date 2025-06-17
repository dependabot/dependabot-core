# Gradle Native Helper

This directory contains the native helper used by Dependabot to interact with Gradle projects using the [Gradle Tooling API](https://docs.gradle.org/current/userguide/embedding.html).

## 🧩 Purpose

The helper is a standalone Kotlin/Java CLI program that:
- Extracts dependency metadata (group, name, version, configuration, etc.)
- Supports accurate dependency graph resolution using Gradle itself
- May support lockfile parsing or generation in the future
- Acts as a replacement or supplement to `file_parser.rb` and `metadata_finder.rb`

## 🏗️ Structure

- `src/main/kotlin/` — Kotlin entrypoint and core logic
- `build.gradle.kts` — Gradle build configuration
- `settings.gradle.kts` — Gradle settings file
- `build/` — Ignored directory where Gradle stores build outputs

## 🚀 Usage

The helper is invoked from the Ruby side via `SharedHelpers.run_helper_subprocess`, which passes a JSON payload via stdin:

```bash
echo '{"function": "get_dependencies", "args": { "projectDir": "." }}' | ./gradle/helpers/build/install/gradle-helper/bin/gradle-helper
````

To build locally:

```bash
cd gradle/helpers
./gradlew installDist
```

This will generate a CLI binary at:

```
build/install/gradle-helper/bin/gradle-helper
```

## 🧪 Development

To test the helper manually:

```bash
./build/install/gradle-helper/bin/gradle-helper <<< '{"function": "get_dependencies", "args": { "projectDir": "/path/to/project" }}'
```

## 📦 Integration

The Ruby side will:

* Place the project files in a temp directory
* Run this CLI tool via `SharedHelpers`
* Parse its JSON output

## 🛠️ Requirements

* Java 11+
* Gradle (automatically bootstrapped via `./gradlew`)
