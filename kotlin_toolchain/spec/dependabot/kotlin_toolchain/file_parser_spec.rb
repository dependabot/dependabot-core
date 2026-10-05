# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/kotlin_toolchain"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::KotlinToolchain::FileParser do
  let(:parser) { described_class.new(dependency_files: dependency_files, source: nil) }
  let(:wrapper) do
    Dependabot::DependencyFile.new(
      name: "kotlin",
      content: kotlin_wrapper(toolchain_version)
    )
  end
  let(:toolchain_version) { "0.11.1" }
  let(:dependency_files) { [wrapper, project_file, module_file] }
  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "project.yaml",
      content: <<~YAML
        modules:
          - .
        mavenPlugins:
          - org.apache.maven.plugins:maven-checkstyle-plugin:3.6.0
      YAML
    )
  end
  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "module.yaml",
      content: <<~YAML
        product: jvm/app
        dependencies:
          - io.ktor:ktor-server-core:3.1.0
          - bom: org.springframework.boot:spring-boot-dependencies:4.0.1
          - org.postgresql:postgresql:42.7.4: runtime-only
          - com.squareup.okio:okio:3.9.0:
              exported: true
        test-dependencies@jvm:
          - org.junit.jupiter:junit-jupiter:5.12.0
        settings:
          kotlin:
            version: 2.2.20
            serialization:
              version: 1.9.0
            ksp:
              processors:
                - com.google.dagger:dagger-compiler:2.56.1
            compilerPlugins:
              - dependency: org.jetbrains.kotlinx:kover-gradle-plugin:0.9.1
          jvm:
            jdk:
              version: 21
        mavenPlugins:
          checkstyle.check:
            dependencies:
              - io.spring.nohttp:nohttp-checkstyle:0.0.11
        tasks:
          testJvm:
            dependsOn: [ :plugins:prepareJvm ]
      YAML
    )
  end

  it_behaves_like "a dependency file parser"

  it "parses wrapper, YAML declarations, processors, plugins, and explicit built-ins" do
    dependencies = parser.parse.to_h { |dependency| [dependency.name, dependency] }

    expect(dependencies.fetch("org.jetbrains.kotlin:kotlin-cli").version).to eq("0.11.1")
    expect(dependencies.fetch("io.ktor:ktor-server-core").version).to eq("3.1.0")
    expect(dependencies.fetch("org.springframework.boot:spring-boot-dependencies").version).to eq("4.0.1")
    expect(dependencies.fetch("org.postgresql:postgresql").version).to eq("42.7.4")
    expect(dependencies.fetch("com.squareup.okio:okio").version).to eq("3.9.0")
    expect(dependencies.fetch("org.junit.jupiter:junit-jupiter").requirements.first[:groups]).to include("test")
    expect(dependencies.fetch("com.google.dagger:dagger-compiler").version).to eq("2.56.1")
    expect(dependencies.fetch("org.jetbrains.kotlinx:kover-gradle-plugin").version).to eq("0.9.1")
    expect(dependencies.fetch("io.spring.nohttp:nohttp-checkstyle").version).to eq("0.0.11")
    expect(dependencies.fetch("org.apache.maven.plugins:maven-checkstyle-plugin").version).to eq("3.6.0")
    expect(dependencies.fetch("org.jetbrains.kotlin:kotlin-stdlib").version).to eq("2.2.20")
    expect(dependencies).not_to have_key("jdk")
  end

  it "does not materialize omitted built-in defaults" do
    project_file.content = "modules: [.]\n"
    module_file.content = "product: jvm/app\n"

    names = parser.parse.map(&:name)
    expect(names).to contain_exactly("org.jetbrains.kotlin:kotlin-cli")
  end

  context "with explicit built-in technology versions" do
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          product: jvm/app
          settings:
            compose:
              version: 1.10.3
              experimental:
                hotReload:
                  version: 1.2.0-rc01
            kotlin:
              version: 2.3.21
              serialization:
                version: 1.11.0
              rpc:
                version: 0.10.2
              ksp:
                version: 2.3.9
            jvm:
              test:
                junitPlatformVersion: 6.0.3
            ktor:
              version: 3.4.3
            lombok:
              version: 1.18.46
            springBoot:
              version: 4.0.6
        YAML
      )
    end

    it "maps settings versions to their published Maven artifacts" do
      dependencies = parser.parse
      versions = dependencies.to_h { |dependency| [dependency.name, dependency.version] }

      expect(versions).to include(
        "org.jetbrains.kotlin:kotlin-stdlib" => "2.3.21",
        "org.jetbrains.compose.runtime:runtime" => "1.10.3",
        "org.jetbrains.compose.hot-reload:hot-reload-runtime-api" => "1.2.0-rc01",
        "org.junit.platform:junit-platform-console-standalone" => "6.0.3",
        "org.jetbrains.kotlinx:kotlinx-serialization-core" => "1.11.0",
        "org.jetbrains.kotlinx:kotlinx-rpc-bom" => "0.10.2",
        "com.google.devtools.ksp:symbol-processing-api" => "2.3.9",
        "io.ktor:ktor-bom" => "3.4.3",
        "org.projectlombok:lombok" => "1.18.46",
        "org.springframework.boot:spring-boot-dependencies" => "4.0.6"
      )

      hot_reload = dependencies.find do |dependency|
        dependency.name == "org.jetbrains.compose.hot-reload:hot-reload-runtime-api"
      end
      expect(hot_reload&.requirements&.first&.dig(:source, :url))
        .to eq("https://packages.jetbrains.team/maven/p/amper/compose-hot-reload")
    end
  end

  context "with unquoted versions, dates and root task references" do
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          product: jvm/app
          since: 2024-01-01
          settings:
            compose:
              version: 1.9
            springBoot:
              version: 3.2
            jvm:
              test:
                junitPlatformVersion: 1.10
          tasks:
            build:
              dependsOn: :prepare
        YAML
      )
    end

    it "keeps every version exactly as written" do
      versions = parser.parse.to_h { |dependency| [dependency.name, dependency.version] }

      expect(versions).to include(
        "org.jetbrains.compose.runtime:runtime" => "1.9",
        "org.springframework.boot:spring-boot-dependencies" => "3.2",
        "org.junit.platform:junit-platform-console-standalone" => "1.10"
      )
    end
  end

  context "when a library is production in one module and test-only in another" do
    let(:dependency_files) { [wrapper, project_file, module_file, fixtures_module] }
    let(:project_file) do
      Dependabot::DependencyFile.new(name: "project.yaml", content: "modules:\n  - .\n  - fixtures\n")
    end
    let(:fixtures_module) do
      Dependabot::DependencyFile.new(
        name: "fixtures/module.yaml",
        content: "product: jvm/lib\ntest-dependencies:\n  - io.ktor:ktor-server-core:3.1.0\n"
      )
    end

    it "reports it as a production dependency" do
      dependency = parser.parse.find { |candidate| candidate.name == "io.ktor:ktor-server-core" }

      expect(dependency.requirements.map { |req| req[:groups] }).to contain_exactly(["dependencies"], ["test"])
      expect(dependency).to be_production
    end
  end

  context "with a 0.12 DataFrame setting" do
    let(:toolchain_version) { "0.12.0-dev-4188" }
    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "module.yaml",
        content: <<~YAML
          product: jvm/app
          settings:
            kotlin:
              dataframe:
                enabled: true
                version: 1.0.0-Beta5
        YAML
      )
    end

    it "parses the version introduced by the 0.12 schema" do
      dependency = parser.parse.find { |candidate| candidate.name == "org.jetbrains.kotlinx:dataframe-core" }

      expect(dependency&.version).to eq("1.0.0-Beta5")
    end
  end

  context "with a version catalog" do
    let(:dependency_files) { [wrapper, project_file, module_file, catalog] }
    let(:catalog) do
      Dependabot::DependencyFile.new(
        name: "libs.versions.toml",
        content: <<~TOML
          [versions]
          ktor = "3.1.0"

          [libraries]
          ktor-core = { module = "io.ktor:ktor-server-core", version.ref = "ktor" }
          coroutines = "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1"

          [plugins]
          kotlin = { id = "org.jetbrains.kotlin.jvm", version = "2.2.20" }
        TOML
      )
    end

    it "parses versions and libraries but not Gradle plugin entries" do
      dependencies = parser.parse.to_h { |dependency| [dependency.name, dependency] }

      expect(dependencies.fetch("io.ktor:ktor-server-core").version).to eq("3.1.0")
      expect(dependencies.fetch("org.jetbrains.kotlinx:kotlinx-coroutines-core").version).to eq("1.10.1")
      expect(dependencies).not_to have_key("plugins:org.jetbrains.kotlin.jvm")
    end
  end

  context "with a future wrapper" do
    let(:toolchain_version) { "0.13.0" }

    it "keeps parsing known fields through the safe fallback" do
      expect(parser.parse.map(&:name)).to include("io.ktor:ktor-server-core")
    end
  end

  it "reports the Kotlin Toolchain ecosystem and its package manager" do
    expect(parser.ecosystem.name).to eq("kotlin_toolchain")
    expect(parser.ecosystem.package_manager.name).to eq("kotlin-toolchain")
    expect(parser.ecosystem.package_manager.version.to_s).to eq("0.11.1")
  end

  context "without a project or module manifest" do
    let(:template) do
      Dependabot::DependencyFile.new(
        name: "base.module-template.yaml",
        content: "settings:\n  kotlin:\n    version: 2.2.20\n"
      )
    end
    let(:dependency_files) { [wrapper, template] }

    it "refuses to build the parser" do
      expect { parser }.to raise_error(
        Dependabot::DependencyFileNotFound,
        /No Kotlin Toolchain project\.yaml or module\.yaml found/
      )
    end
  end

  context "with both version catalog locations" do
    let(:catalog_content) { "[versions]\nktor = \"3.1.0\"\n" }
    let(:dependency_files) do
      [
        wrapper,
        module_file,
        Dependabot::DependencyFile.new(name: "libs.versions.toml", content: catalog_content),
        Dependabot::DependencyFile.new(name: "gradle/libs.versions.toml", content: catalog_content)
      ]
    end

    it "refuses to guess which catalog wins" do
      expect { parser }.to raise_error(
        Dependabot::DependencyFileNotParseable,
        %r{either libs\.versions\.toml or gradle/libs\.versions\.toml, not both}
      )
    end
  end

  context "with an unparseable version catalog" do
    let(:dependency_files) do
      [
        wrapper,
        module_file,
        Dependabot::DependencyFile.new(name: "libs.versions.toml", content: "[versions\nktor = \"3.1.0\"\n")
      ]
    end

    it "reports the catalog file name" do
      expect { parser.parse }
        .to raise_error(Dependabot::DependencyFileNotParseable, /\Alibs\.versions\.toml: /)
    end
  end
end
