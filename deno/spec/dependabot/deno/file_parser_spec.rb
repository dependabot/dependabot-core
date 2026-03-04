# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/file_parser"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Deno::FileParser do
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      credentials: credentials
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/repo",
      directory: "/"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  context "with a basic deno.json" do
    let(:files) do
      project_dependency_files("deno/basic")
    end

    it "parses jsr dependencies" do
      deps = parser.parse
      jsr_deps = deps.select { |d| d.requirements.first[:source][:type] == "jsr" }
      expect(jsr_deps.length).to eq(2)
      expect(jsr_deps.map(&:name)).to contain_exactly("@std/path", "@std/fs")
    end

    it "parses npm dependencies" do
      deps = parser.parse
      npm_deps = deps.select { |d| d.requirements.first[:source][:type] == "npm" }
      expect(npm_deps.length).to eq(2)
      expect(npm_deps.map(&:name)).to contain_exactly("chalk", "lodash")
    end

    it "extracts version constraints" do
      deps = parser.parse
      chalk = deps.find { |d| d.name == "chalk" }
      expect(chalk.requirements.first[:requirement]).to eq("^5.3.0")
    end

    it "sets the manifest file as the requirement source" do
      deps = parser.parse
      dep = deps.first
      expect(dep.requirements.first[:file]).to eq("deno.json")
    end
  end

  context "with scoped npm packages" do
    let(:files) do
      project_dependency_files("deno/scoped_npm")
    end

    it "parses scoped npm packages" do
      deps = parser.parse
      npm_deps = deps.select { |d| d.requirements.first[:source][:type] == "npm" }
      expect(npm_deps.map(&:name)).to contain_exactly(
        "@aws-sdk/client-polly", "@sentry/deno", "chalk"
      )
    end

    it "extracts scoped package constraints" do
      deps = parser.parse
      polly = deps.find { |d| d.name == "@aws-sdk/client-polly" }
      expect(polly.requirements.first[:requirement]).to eq("^3.600.0")
    end
  end

  context "with versionless specifiers" do
    let(:files) do
      project_dependency_files("deno/versionless")
    end

    it "parses all dependencies including versionless ones" do
      deps = parser.parse
      expect(deps.map(&:name)).to contain_exactly(
        "@std/path", "chalk", "@sentry/deno", "lodash"
      )
    end

    it "sets nil requirement for versionless specifiers" do
      deps = parser.parse
      chalk = deps.find { |d| d.name == "chalk" }
      expect(chalk.requirements.first[:requirement]).to be_nil
    end

    it "sets nil version for versionless specifiers" do
      deps = parser.parse
      chalk = deps.find { |d| d.name == "chalk" }
      expect(chalk.version).to be_nil
    end

    it "still parses versioned specifiers normally" do
      deps = parser.parse
      lodash = deps.find { |d| d.name == "lodash" }
      expect(lodash.requirements.first[:requirement]).to eq("^4.17.21")
    end
  end

  context "with subpath imports" do
    let(:files) do
      project_dependency_files("deno/subpath")
    end

    it "extracts the package name without the subpath" do
      deps = parser.parse
      expect(deps.map(&:name)).to contain_exactly("@std/path", "lodash")
    end

    it "preserves the version constraint" do
      deps = parser.parse
      path = deps.find { |d| d.name == "@std/path" }
      expect(path.requirements.first[:requirement]).to eq("^1.0.0")
    end
  end

  context "with a deno.jsonc file" do
    let(:files) do
      project_dependency_files("deno/jsonc")
    end

    it "parses JSONC with comments" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end
end
