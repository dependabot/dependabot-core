# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/kotlin_toolchain/file_parser/version_catalog_parser"

RSpec.describe Dependabot::KotlinToolchain::FileParser::VersionCatalogParser do
  let(:file) { Dependabot::DependencyFile.new(name: "libs.versions.toml", content: content) }
  let(:parser) { described_class.new(file: file, profile_name: "0.12") }
  let(:dependencies) { parser.dependencies.to_h { |dependency| [dependency.name, dependency] } }

  context "with a group and name declaration" do
    let(:content) do
      <<~TOML
        [libraries]
        ktor-core = { group = "io.ktor", name = "ktor-server-core", version = "3.1.0" }
      TOML
    end

    it "builds the coordinate from the separate keys" do
      dependency = dependencies.fetch("io.ktor:ktor-server-core")

      expect(dependency.version).to eq("3.1.0")
      expect(dependency.requirements.first[:metadata]).to include(kind: "catalog_inline", alias: "ktor-core")
    end
  end

  context "with a string shorthand declaration" do
    let(:content) do
      <<~TOML
        [libraries]
        okio = "com.squareup.okio:okio:3.9.0"
      TOML
    end

    it "splits the coordinate" do
      expect(dependencies.fetch("com.squareup.okio:okio").version).to eq("3.9.0")
    end
  end

  context "with dotted aliases, quoted aliases and sub-tables" do
    let(:content) do
      <<~TOML
        [versions]
        ktor.core = "3.1.0"
        "kotlinx.io" = "0.7.0"

        [libraries]
        ktor.core = { module = "io.ktor:ktor-server-core", version.ref = "ktor.core" }
        "okio.core" = "com.squareup.okio:okio:3.9.0"
        kotlinx.io = { module = "org.jetbrains.kotlinx:kotlinx-io-core", version.ref = "kotlinx.io" }

        [libraries.ktor-client]
        module = "io.ktor:ktor-client-core"
        version = "3.1.0"
      TOML
    end

    it "sees every library the way Gradle does" do
      expect(dependencies.keys).to contain_exactly(
        "io.ktor:ktor-server-core",
        "com.squareup.okio:okio",
        "org.jetbrains.kotlinx:kotlinx-io-core",
        "io.ktor:ktor-client-core"
      )
      expect(dependencies.fetch("io.ktor:ktor-server-core").requirements.first[:metadata])
        .to include(kind: "catalog_version", alias: "ktor.core", version_key: "ktor.core")
      expect(dependencies.fetch("com.squareup.okio:okio").requirements.first[:metadata])
        .to include(kind: "catalog_inline", alias: "okio.core")
      expect(dependencies.fetch("org.jetbrains.kotlinx:kotlinx-io-core").version).to eq("0.7.0")
      expect(dependencies.fetch("io.ktor:ktor-client-core").requirements.first[:metadata])
        .to include(kind: "catalog_inline", alias: "ktor-client")
    end
  end

  context "with declarations that cannot be resolved" do
    let(:content) do
      <<~TOML
        [versions]
        ktor = { require = "3.1.0" }

        [libraries]
        too-short = "com.example:artifact"
        no-module = { version = "1.0.0" }
        no-version = { module = "com.example:artifact" }
        unknown-ref = { module = "com.example:artifact", version.ref = "missing" }
        rich-ref = { module = "io.ktor:ktor-server-core", version.ref = "ktor" }
      TOML
    end

    it "skips them instead of guessing" do
      expect(parser.dependencies).to be_empty
    end
  end

  context "without a libraries table" do
    let(:content) { "[versions]\nktor = \"3.1.0\"\n" }

    it "returns no dependencies" do
      expect(parser.dependencies).to be_empty
    end
  end

  context "with unparseable TOML" do
    let(:content) { "[libraries\nktor = \"3.1.0\"\n" }

    it "reports the file name" do
      expect { parser.dependencies }
        .to raise_error(Dependabot::DependencyFileNotParseable, /\Alibs\.versions\.toml: /)
    end
  end
end
