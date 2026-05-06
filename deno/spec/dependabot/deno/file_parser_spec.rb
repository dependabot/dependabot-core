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

  context "with values containing // (e.g. URLs)" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.json",
          content: <<~JSON
            {
              "imports": {
                "@std/path": "jsr:@std/path@^1.0.0",
                "legacy": "https://deno.land/x/foo/mod.ts"
              }
            }
          JSON
        )
      ]
    end

    it "parses without treating // inside string values as a comment" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end

  context "with a JSONC file containing a URL value and trailing comment" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.jsonc",
          content: <<~JSON
            {
              // Top-level comment
              "imports": {
                "@std/path": "jsr:@std/path@^1.0.0", // trailing comment
                "x": "https://example.com/lib"
              }
            }
          JSON
        )
      ]
    end

    it "strips comments without corrupting the URL value" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end

  context "with a multi-line block comment" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.jsonc",
          content: <<~JSON
            {
              /* this is a
                 multi-line
                 block comment */
              "imports": {
                "@std/path": "jsr:@std/path@^1.0.0"
              }
            }
          JSON
        )
      ]
    end

    it "strips the block comment across lines" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end

  context "with a trailing comma after the last entry" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.jsonc",
          content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0",}}'
        )
      ]
    end

    it "strips the trailing comma so JSON.parse succeeds" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end

  context "with the same package referenced via multiple subpath aliases" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.json",
          content: <<~JSON
            {
              "imports": {
                "@std/path": "jsr:@std/path@^1.0.0",
                "@std/path/posix": "jsr:@std/path@^1.0.0/posix",
                "@std/path/join": "jsr:@std/path@^1.0.0/join"
              }
            }
          JSON
        )
      ]
    end

    it "returns a single dependency" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
      expect(deps.first.requirements.first[:requirement]).to eq("^1.0.0")
    end
  end

  context "with the same package referenced under two different constraints" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.json",
          content: '{"imports": {"foo": "jsr:@scope/foo@^1.0.0", "foo2": "jsr:@scope/foo@^2.0.0"}}'
        )
      ]
    end

    it "returns one dependency with both constraints in its requirements" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@scope/foo")
      expect(deps.first.requirements.map { |r| r[:requirement] }).to contain_exactly("^1.0.0", "^2.0.0")
    end
  end

  context "with the same package name referenced via different source types" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.json",
          content: '{"imports": {"foo-jsr": "jsr:@scope/foo@^1.0.0", "foo-npm": "npm:foo@^2.0.0"}}'
        )
      ]
    end

    it "treats them as separate dependencies" do
      deps = parser.parse
      expect(deps.length).to eq(2)
      expect(deps.map { |d| d.requirements.first[:source][:type] }).to contain_exactly("jsr", "npm")
    end
  end

  context "with escaped quotes inside a string value" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "deno.jsonc",
          content: <<~'JSON'
            {
              "imports": {
                "@std/path": "jsr:@std/path@^1.0.0",
                "note": "say \"hi\" then //bye"
              }
            }
          JSON
        )
      ]
    end

    it "treats the escaped quotes as part of the string and preserves the trailing //" do
      deps = parser.parse
      expect(deps.length).to eq(1)
      expect(deps.first.name).to eq("@std/path")
    end
  end
end
