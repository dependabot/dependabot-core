# typed: false
# frozen_string_literal: true

require "base64"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/kotlin_toolchain/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::KotlinToolchain::FileUpdater do
  let(:wrapper) do
    Dependabot::DependencyFile.new(
      name: "kotlin",
      content: kotlin_wrapper("0.11.1")
    )
  end
  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "module.yaml",
      content: <<~YAML
        dependencies:
          - "io.ktor:ktor-server-core:3.1.0" # keep
        settings:
          kotlin:
            version: '2.2.20'
        tasks:
          testJvm:
            dependsOn: [ :plugins:prepareJvm ]
      YAML
    )
  end
  let(:dependency_files) { [wrapper, module_file] }
  let(:dependencies) { [dependency] }
  let(:credentials) { [] }
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end

  it_behaves_like "a dependency file updater"

  context "with an inline YAML dependency" do
    let(:metadata) do
      {
        kind: "yaml_value",
        path: ["dependencies", 0],
        value: "io.ktor:ktor-server-core:3.1.0",
        coordinate: "io.ktor:ktor-server-core:3.1.0"
      }
    end
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: metadata
      )
    end

    it "updates only the version and preserves quotes and comments" do
      content = updater.updated_dependency_files.find { |file| file.name == "module.yaml" }.content

      expect(content).to include('"io.ktor:ktor-server-core:3.2.0" # keep')
      expect(content).to include("dependsOn: [ :plugins:prepareJvm ]")
    end
  end

  context "with an explicit built-in version" do
    let(:metadata) do
      {
        kind: "yaml_value",
        path: %w(settings kotlin version),
        value: "2.2.20",
        version_source: "settings"
      }
    end
    let(:dependency) do
      updated_dependency(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        previous_version: "2.2.20",
        version: "2.3.0",
        metadata: metadata
      )
    end

    it "updates the scalar without changing its quote style" do
      content = updater.updated_dependency_files.find { |file| file.name == "module.yaml" }.content

      expect(content).to include("version: '2.3.0'")
    end
  end

  context "with a full-form YAML dependency" do
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          dependencies:
            - io.ktor:ktor-server-core:3.1.0:
                exported: true
        YAML
      )
    end
    let(:metadata) do
      {
        kind: "yaml_key",
        path: ["dependencies", 0, "io.ktor:ktor-server-core:3.1.0"],
        value: "io.ktor:ktor-server-core:3.1.0",
        coordinate: "io.ktor:ktor-server-core:3.1.0"
      }
    end
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: metadata
      )
    end

    it "updates the mapping key without reformatting its attributes" do
      content = updater.updated_dependency_files.find { |file| file.name == "module.yaml" }.content

      expect(content).to include("- io.ktor:ktor-server-core:3.2.0:")
      expect(content).to include("exported: true")
    end
  end

  context "with a referenced catalog version" do
    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "libs.versions.toml",
        content: <<~TOML
          [versions]
          ktor = "3.1.0" # keep

          [libraries]
          ktor-core = { module = "io.ktor:ktor-server-core", version.ref = "ktor" }
        TOML
      )
    end
    let(:dependency_files) { [wrapper, catalog] }
    let(:metadata) do
      {
        kind: "catalog_version",
        alias: "ktor-core",
        version_key: "ktor",
        value: "3.1.0"
      }
    end
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: metadata,
        file: "libs.versions.toml"
      )
    end

    it "updates the versions table and preserves the comment" do
      content = updater.updated_dependency_files.find { |file| file.name == "libs.versions.toml" }.content

      expect(content).to include('ktor = "3.2.0" # keep')
      expect(content).to include('version.ref = "ktor"')
    end
  end

  context "with an inline catalog version" do
    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "gradle/libs.versions.toml",
        content: <<~TOML
          [libraries]
          coroutines = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version = "1.10.1" } # keep
        TOML
      )
    end
    let(:dependency_files) { [wrapper, catalog] }
    let(:metadata) do
      {
        kind: "catalog_inline",
        alias: "coroutines",
        value: "1.10.1"
      }
    end
    let(:dependency) do
      updated_dependency(
        name: "org.jetbrains.kotlinx:kotlinx-coroutines-core",
        previous_version: "1.10.1",
        version: "1.10.2",
        metadata: metadata,
        file: "gradle/libs.versions.toml"
      )
    end

    it "updates the library declaration without reformatting it" do
      content = updater.updated_dependency_files.find { |file| file.name == "gradle/libs.versions.toml" }.content

      expect(content).to include('version = "1.10.2" } # keep')
    end
  end

  context "with a bare number, an alias, a merge key and an anchored coordinate" do
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          base: &base
            kotlin:
              version: &kotlin 2.2.20
          settings:
            <<: *base
            springBoot:
              version: 3.2
            ktor:
              version: *kotlin
          dependencies:
            - &okio "com.squareup.okio:okio:3.9.0"
          test-dependencies:
            - *okio
        YAML
      )
    end

    it "updates the bare number in place" do
      dependency = updated_dependency(
        name: "org.springframework.boot:spring-boot-dependencies",
        previous_version: "3.2",
        version: "3.3",
        metadata: { kind: "yaml_value", path: %w(settings springBoot version), value: "3.2" }
      )
      content = updater(dependency).updated_dependency_files.first.content

      expect(content).to include("    version: 3.3\n")
      expect(content).not_to include("3.2")
    end

    it "follows the merge key to the anchored scalar and keeps its anchor" do
      dependency = updated_dependency(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        previous_version: "2.2.20",
        version: "2.3.0",
        metadata: { kind: "yaml_value", path: %w(settings kotlin version), value: "2.2.20" }
      )
      content = updater(dependency).updated_dependency_files.first.content

      expect(content).to include("version: &kotlin 2.3.0")
      expect(content).to include("version: *kotlin")
    end

    it "follows an alias to its definition" do
      dependency = updated_dependency(
        name: "io.ktor:ktor-bom",
        previous_version: "2.2.20",
        version: "2.3.0",
        metadata: { kind: "yaml_value", path: %w(settings ktor version), value: "2.2.20" }
      )
      content = updater(dependency).updated_dependency_files.first.content

      expect(content).to include("version: &kotlin 2.3.0")
    end

    it "keeps the anchor on an updated coordinate so the alias still resolves" do
      dependency = updated_dependency(
        name: "com.squareup.okio:okio",
        previous_version: "3.9.0",
        version: "3.10.0",
        metadata: {
          kind: "yaml_value",
          path: ["dependencies", 0],
          value: "com.squareup.okio:okio:3.9.0",
          coordinate: "com.squareup.okio:okio:3.9.0"
        }
      )
      content = updater(dependency).updated_dependency_files.first.content

      expect(content).to include('- &okio "com.squareup.okio:okio:3.10.0"')
      expect(content).to include("- *okio")
      expect(Dependabot::KotlinToolchain::YamlParser.load(content, filename: "module.yaml").fetch("test-dependencies"))
        .to eq(["com.squareup.okio:okio:3.10.0"])
    end

    def updater(dependency)
      described_class.new(dependency_files: dependency_files, dependencies: [dependency], credentials: [])
    end
  end

  context "with catalog spellings TOML allows" do
    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "libs.versions.toml",
        content: <<~TOML
          [ versions ]
          kotlin = "2.0.0"
          ktor.core = "3.1.0"

          [libraries]
          stdlib = { module = "org.jetbrains.kotlin:kotlin-stdlib", version.ref = "kotlin" }
          reflect = { module = "org.jetbrains.kotlin:kotlin-reflect", version.ref = "kotlin" }
          ktor.core = { module = "io.ktor:ktor-server-core", version.ref = "ktor.core" }
          "okio.core" = "com.squareup.okio:okio:3.9.0"

          [libraries.ktor-client]
          module = "io.ktor:ktor-client-core"
          version = "3.1.0"
        TOML
      )
    end
    let(:dependency_files) { [wrapper, catalog] }
    let(:updated) { updater.updated_dependency_files.first.content }

    context "with a header that has inner whitespace" do
      let(:dependency) do
        updated_dependency(
          name: "org.jetbrains.kotlin:kotlin-stdlib",
          previous_version: "2.0.0",
          version: "2.1.0",
          metadata: { kind: "catalog_version", alias: "stdlib", version_key: "kotlin", value: "2.0.0" },
          file: "libs.versions.toml"
        )
      end

      it "still finds the key" do
        expect(updated).to include('kotlin = "2.1.0"')
      end
    end

    context "with a dotted version key" do
      let(:dependency) do
        updated_dependency(
          name: "io.ktor:ktor-server-core",
          previous_version: "3.1.0",
          version: "3.2.0",
          metadata: { kind: "catalog_version", alias: "ktor.core", version_key: "ktor.core", value: "3.1.0" },
          file: "libs.versions.toml"
        )
      end

      it "updates the nested key" do
        expect(updated).to include('ktor.core = "3.2.0"')
        expect(updated).to include('version.ref = "ktor.core"')
      end
    end

    context "with a quoted dotted alias" do
      let(:dependency) do
        updated_dependency(
          name: "com.squareup.okio:okio",
          previous_version: "3.9.0",
          version: "3.10.0",
          metadata: { kind: "catalog_inline", alias: "okio.core", value: "3.9.0" },
          file: "libs.versions.toml"
        )
      end

      it "updates the coordinate string" do
        expect(updated).to include('"okio.core" = "com.squareup.okio:okio:3.10.0"')
      end
    end

    context "with a library declared as a sub-table" do
      let(:dependency) do
        updated_dependency(
          name: "io.ktor:ktor-client-core",
          previous_version: "3.1.0",
          version: "3.2.0",
          metadata: { kind: "catalog_inline", alias: "ktor-client", value: "3.1.0" },
          file: "libs.versions.toml"
        )
      end

      it "updates the version line under the header" do
        expect(updated).to include(<<~TOML.chomp)
          [libraries.ktor-client]
          module = "io.ktor:ktor-client-core"
          version = "3.2.0"
        TOML
        expect(updated).to include('version.ref = "ktor.core"')
      end
    end

    context "with two libraries sharing a version key in one grouped update" do
      let(:dependencies) do
        %w(kotlin-stdlib kotlin-reflect).map do |artifact|
          updated_dependency(
            name: "org.jetbrains.kotlin:#{artifact}",
            previous_version: "2.0.0",
            version: "2.1.0",
            metadata: { kind: "catalog_version", alias: artifact, version_key: "kotlin", value: "2.0.0" },
            file: "libs.versions.toml"
          )
        end
      end

      it "rewrites the key once and succeeds for both" do
        expect(updated).to include('kotlin = "2.1.0"')
        expect(updated.scan("2.1.0").length).to eq(1)
      end
    end

    context "when the key holds neither the old nor the new version" do
      let(:dependency) do
        updated_dependency(
          name: "org.jetbrains.kotlin:kotlin-stdlib",
          previous_version: "1.9.0",
          version: "2.1.0",
          metadata: { kind: "catalog_version", alias: "stdlib", version_key: "kotlin", value: "1.9.0" },
          file: "libs.versions.toml"
        )
      end

      it "refuses to guess" do
        expect { updated }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          "Unable to locate versions.kotlin in libs.versions.toml"
        )
      end
    end
  end

  context "with a wrapper update" do
    let(:credentials) do
      [{
        "type" => "maven_repository",
        "url" => "https://packages.jetbrains.team/maven/p/amper/amper",
        "username" => "dependabot",
        "password" => "secret"
      }]
    end
    let(:windows_wrapper) do
      Dependabot::DependencyFile.new(
        name: "kotlin.bat",
        content: kotlin_wrapper("0.11.1", windows: true)
      )
    end
    let(:dependency_files) { [wrapper, windows_wrapper] }
    let(:dependency) do
      source = {
        type: "maven_repo",
        url: "https://packages.jetbrains.team/maven/p/amper/amper"
      }
      requirements = dependency_files.map do |file|
        {
          file: file.name,
          requirement: "0.12.0",
          groups: ["toolchain"],
          source: source,
          metadata: { kind: "wrapper" }
        }
      end
      previous_requirements = requirements.map { |requirement| requirement.merge(requirement: "0.11.1") }

      Dependabot::Dependency.new(
        name: "org.jetbrains.kotlin:kotlin-cli",
        version: "0.12.0",
        previous_version: "0.11.1",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "kotlin_toolchain",
        metadata: { wrapper: true }
      )
    end

    before do
      allow(Dependabot::RegistryClient).to receive(:get) do |url:, **|
        windows = url.end_with?(".bat")
        double(status: 200, body: kotlin_wrapper("0.12.0", windows: windows, sha: "b" * 64))
      end
    end

    it "replaces both wrappers with the official versioned artifacts" do
      updated_files = updater.updated_dependency_files

      expect(updated_files.map(&:name)).to contain_exactly("kotlin", "kotlin.bat")
      expect(updated_files.map { |file| Dependabot::KotlinToolchain::Wrapper.version_from_content(file.content) })
        .to contain_exactly("0.12.0", "0.12.0")
      expect(Dependabot::RegistryClient).to have_received(:get)
        .with(
          url: kind_of(String),
          headers: { "Authorization" => "Basic #{Base64.strict_encode64('dependabot:secret')}" }
        )
        .twice
    end
  end

  context "when the wrapper is missing" do
    it "refuses to build the updater" do
      expect do
        described_class.new(dependency_files: [module_file], dependencies: [], credentials: [])
      end.to raise_error(RuntimeError, "Kotlin Toolchain wrapper is missing")
    end
  end

  context "when no requirement changed" do
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.1.0",
        metadata: { kind: "yaml_value", path: ["dependencies", 0], value: "io.ktor:ktor-server-core:3.1.0" }
      )
    end

    it "raises because no file was touched" do
      expect { updater.updated_dependency_files }
        .to raise_error(RuntimeError, "No files changed!")
    end
  end

  context "without previous requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "io.ktor:ktor-server-core",
        version: "3.2.0",
        requirements: [{
          file: "module.yaml",
          requirement: "3.2.0",
          groups: ["dependencies"],
          source: nil,
          metadata: { kind: "yaml_value", path: ["dependencies", 0], value: "io.ktor:ktor-server-core:3.1.0" }
        }],
        package_manager: "kotlin_toolchain"
      )
    end

    it "raises because there is nothing to compare against" do
      expect { updater.updated_dependency_files }
        .to raise_error(RuntimeError, "Previous requirements are required to update io.ktor:ktor-server-core")
    end
  end

  context "without source metadata" do
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: nil
      )
    end

    it "raises and names the dependency and the file" do
      expect { updater.updated_dependency_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        "Missing source metadata for io.ktor:ktor-server-core in module.yaml"
      )
    end
  end

  context "with an unsupported declaration kind" do
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: { kind: "gradle_script", path: ["dependencies", 0], value: "io.ktor:ktor-server-core:3.1.0" }
      )
    end

    it "raises and quotes the unknown kind" do
      expect { updater.updated_dependency_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        'Unsupported Kotlin Toolchain declaration "gradle_script" in module.yaml'
      )
    end
  end

  context "with a YAML declaration that has no path" do
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: { kind: "yaml_value", value: "io.ktor:ktor-server-core:3.1.0" }
      )
    end

    it "raises" do
      expect { updater.updated_dependency_files }
        .to raise_error(Dependabot::DependencyFileNotResolvable, "Missing YAML path in module.yaml")
    end
  end

  context "with a YAML path that is absent from the file" do
    let(:dependency) do
      updated_dependency(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        previous_version: "2.2.20",
        version: "2.3.0",
        metadata: { kind: "yaml_value", path: %w(settings kotlin missing), value: "2.2.20" }
      )
    end

    it "raises and names the path" do
      expect { updater.updated_dependency_files }
        .to raise_error(
          Dependabot::DependencyFileNotResolvable,
          "Unable to locate settings.kotlin.missing in module.yaml"
        )
    end
  end

  context "with a coordinate that is absent from the declaration" do
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-client-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: {
          kind: "yaml_value",
          path: ["dependencies", 0],
          value: "io.ktor:ktor-server-core:3.1.0",
          coordinate: "io.ktor:ktor-client-core:3.1.0"
        }
      )
    end

    it "raises rather than editing the wrong coordinate" do
      expect { updater.updated_dependency_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        "Unable to update io.ktor:ktor-client-core:3.1.0 from 3.1.0"
      )
    end
  end

  context "with a multiline version scalar" do
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          settings:
            kotlin:
              version: >-
                2.2.20
        YAML
      )
    end
    let(:dependency) do
      updated_dependency(
        name: "org.jetbrains.kotlin:kotlin-stdlib",
        previous_version: "2.2.20",
        version: "2.3.0",
        metadata: { kind: "yaml_value", path: %w(settings kotlin version), value: "2.2.20" }
      )
    end

    it "refuses to rewrite it" do
      expect { updater.updated_dependency_files }.to raise_error(
        Dependabot::DependencyFileNotResolvable,
        "Multiline dependency versions are not supported in module.yaml"
      )
    end
  end

  context "with a catalog declaration" do
    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "libs.versions.toml",
        content: <<~TOML
          [versions]
          other = "1.0.0"

          [libraries]
          other-core = { module = "com.example:other", version = "1.0.0" }
        TOML
      )
    end
    let(:dependency_files) { [wrapper, catalog] }
    let(:dependency) do
      updated_dependency(
        name: "io.ktor:ktor-server-core",
        previous_version: "3.1.0",
        version: "3.2.0",
        metadata: metadata,
        file: "libs.versions.toml"
      )
    end

    context "when the version key is missing from the metadata" do
      let(:metadata) { { kind: "catalog_version", value: "3.1.0" } }

      it "raises" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileNotResolvable, "Missing version_key metadata")
      end
    end

    context "when the alias is missing from the metadata" do
      let(:metadata) { { kind: "catalog_inline", value: "3.1.0" } }

      it "raises" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileNotResolvable, "Missing alias metadata")
      end
    end

    context "when the version key is not declared in the catalog" do
      let(:metadata) { { kind: "catalog_version", version_key: "ktor", value: "3.1.0" } }

      it "raises and names the table" do
        expect { updater.updated_dependency_files }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          "Unable to locate versions.ktor in libs.versions.toml"
        )
      end
    end

    context "when the alias is not declared in the catalog" do
      let(:metadata) { { kind: "catalog_inline", alias: "ktor-core", value: "3.1.0" } }

      it "raises and names the table" do
        expect { updater.updated_dependency_files }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          "Unable to locate libraries.ktor-core in libs.versions.toml"
        )
      end
    end

    context "when the edit would produce invalid TOML" do
      let(:metadata) { { kind: "catalog_version", version_key: "other", value: "1.0.0" } }
      let(:dependency) do
        updated_dependency(
          name: "com.example:other",
          previous_version: "1.0.0",
          version: '1.1.0"',
          metadata: metadata,
          file: "libs.versions.toml"
        )
      end

      it "rejects the update instead of writing a broken file" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileNotParseable, /\Alibs\.versions\.toml: /)
      end
    end
  end

  def updated_dependency(name:, previous_version:, version:, metadata:, file: "module.yaml")
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: previous_version,
      requirements: [{
        file: file,
        requirement: version,
        groups: ["dependencies"],
        source: nil,
        metadata: metadata
      }],
      previous_requirements: [{
        file: file,
        requirement: previous_version,
        groups: ["dependencies"],
        source: nil,
        metadata: metadata
      }],
      package_manager: "kotlin_toolchain"
    )
  end
end
