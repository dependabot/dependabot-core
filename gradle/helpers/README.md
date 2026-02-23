# Gradle Native Helper

This directory contains a native helper used by Dependabot to interact with Gradle projects via the [Gradle Tooling API](https://docs.gradle.org/current/userguide/embedding.html).

## 🧩 Purpose

The helper is a standalone Kotlin CLI tool that:

- Uses the Gradle Tooling API to extract dependency metadata
- Supports accurate dependency graph resolution using the project's actual Gradle setup
- Detects and reports configuration issues in the target project
- Can evolve to support native commands for various metadata operations
- Provides native command-line interfaces for Dependabot Ruby to consume in a standardized way

## ✅ Current Functionality

- Lists all dependencies of a given Gradle project using the `IdeaProject` model

## 🏗️ Project Structure

```

gradle/helpers/
├── build.gradle.kts               # Gradle build configuration (Kotlin DSL)
├── settings.gradle.kts            # Gradle settings
├── src/
│   └── main/
│       └── kotlin/
│           └── dependabot/
│               └── gradle/
│                   ├── GradleHelper.kt   # Tooling API logic
│                   └── Main.kt           # JSON stdin/stdout entrypoint
└── spec/fixtures/projects/        # Example Gradle projects for testing

````

## 🚀 Usage

The helper accepts JSON over stdin and returns JSON on stdout. For example:

```bash
echo '{"function":"list_dependencies","args":{"projectDir":"/path/to/project"}}' \
  | java -jar build/libs/gradle-helper.jar
````

To build the CLI:

```bash
./gradlew shadowJar
```

The resulting JAR will be located at:

```
build/libs/gradle-helper.jar
```

## 🧪 Development & Testing

To test the helper locally with a sample project:

```bash
echo '{"function":"list_dependencies","args":{"projectDir":"spec/fixtures/projects/sample-gradle-project"}}' \
  | java -jar build/libs/gradle-helper.jar
```

You can add additional test projects under `spec/fixtures/projects/` to expand test coverage.

## 📦 Integration

On the Ruby side, Dependabot will:

* Extract the target project to a temporary directory
* Invoke this helper via `SharedHelpers.run_helper_subprocess`
* Deserialize and consume the resulting JSON

## 🔮 Roadmap

Planned extensions include:

* Native support for resolving versions and upgrade paths
* Lockfile inspection or generation
* Handling metadata specific to configurations, scopes, exclusions
* Multi-project and included builds support
* Gradle plugin and settings analysis

## 🛠️ Requirements

* Java 11+
* Gradle (automatically bootstrapped via `./gradlew` or inherited from the target project)

```
