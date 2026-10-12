# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Deno::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
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
  let(:files) do
    [
      Dependabot::DependencyFile.new(
        name: "deno.json",
        content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0", "chalk": "npm:chalk@^5.3.0"}}'
      )
    ]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "@std/path",
      version: "1.1.4",
      previous_version: "1.0.0",
      requirements: [{
        requirement: "^1.1.4",
        file: "deno.json",
        groups: ["imports"],
        source: { type: "jsr" }
      }],
      previous_requirements: [{
        requirement: "^1.0.0",
        file: "deno.json",
        groups: ["imports"],
        source: { type: "jsr" }
      }],
      package_manager: "deno"
    )
  end

  describe "#updated_dependency_files" do
    it "updates the specifier in deno.json" do
      updated_files = updater.updated_dependency_files
      expect(updated_files.length).to eq(1)

      updated_content = updated_files.first.content
      expect(updated_content).to include("jsr:@std/path@^1.1.4")
      expect(updated_content).to include("npm:chalk@^5.3.0")
    end

    context "when the manifest contains a sub-path import for the same package" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "deno.json",
            content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0", ' \
                     '"@std/path/posix": "jsr:@std/path@^1.0.0/posix"}}'
          )
        ]
      end

      it "bumps both the bare specifier and the sub-path specifier" do
        updated_content = updater.updated_dependency_files.first.content
        expect(updated_content).to include('"jsr:@std/path@^1.1.4"')
        expect(updated_content).to include('"jsr:@std/path@^1.1.4/posix"')
      end
    end

    context "when the manifest contains a prerelease pin sharing the prefix" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "deno.json",
            content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0", ' \
                     '"@std/path-rc": "jsr:@std/path@^1.0.0-rc.1"}}'
          )
        ]
      end

      it "bumps only the bare specifier and leaves the prerelease pin untouched" do
        updated_content = updater.updated_dependency_files.first.content
        expect(updated_content).to include('"jsr:@std/path@^1.1.4"')
        expect(updated_content).to include('"jsr:@std/path@^1.0.0-rc.1"')
        expect(updated_content).not_to include("^1.1.4-rc.1")
      end
    end

    context "with a versionless specifier" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "deno.json",
            content: '{"imports": {"chalk": "npm:chalk"}}'
          )
        ]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chalk",
          version: "5.4.0",
          previous_version: nil,
          requirements: [{
            requirement: "5.4.0",
            file: "deno.json",
            groups: ["imports"],
            source: { type: "npm" }
          }],
          previous_requirements: [{
            requirement: nil,
            file: "deno.json",
            groups: ["imports"],
            source: { type: "npm" }
          }],
          package_manager: "deno"
        )
      end

      it "adds the version to the previously versionless specifier" do
        updated_content = updater.updated_dependency_files.first.content
        expect(updated_content).to eq('{"imports": {"chalk": "npm:chalk@5.4.0"}}')
      end
    end

    context "with a versionless specifier that has a sub-path and a sibling sharing the prefix" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "deno.json",
            content: '{"imports": {"chalk": "npm:chalk", ' \
                     '"chalk/utils": "npm:chalk/utils", ' \
                     '"chalk-cli": "npm:chalk-cli"}}'
          )
        ]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "chalk",
          version: "5.4.0",
          previous_version: nil,
          requirements: [{
            requirement: "5.4.0",
            file: "deno.json",
            groups: ["imports"],
            source: { type: "npm" }
          }],
          previous_requirements: [{
            requirement: nil,
            file: "deno.json",
            groups: ["imports"],
            source: { type: "npm" }
          }],
          package_manager: "deno"
        )
      end

      it "adds the version to bare and sub-path specifiers without touching siblings sharing the prefix" do
        updated_content = updater.updated_dependency_files.first.content
        expect(updated_content).to include('"chalk": "npm:chalk@5.4.0"')
        expect(updated_content).to include('"chalk/utils": "npm:chalk@5.4.0/utils"')
        expect(updated_content).to include('"chalk-cli": "npm:chalk-cli"')
      end
    end

    context "when updating a deno.jsonc file" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "deno.jsonc",
            content: <<~JSONC
              {
                // Top-level comment
                "imports": {
                  /* block comment */
                  "@std/path": "jsr:@std/path@^1.0.0" // trailing comment
                }
              }
            JSONC
          )
        ]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@std/path",
          version: "1.1.4",
          previous_version: "1.0.0",
          requirements: [{
            requirement: "^1.1.4",
            file: "deno.jsonc",
            groups: ["imports"],
            source: { type: "jsr" }
          }],
          previous_requirements: [{
            requirement: "^1.0.0",
            file: "deno.jsonc",
            groups: ["imports"],
            source: { type: "jsr" }
          }],
          package_manager: "deno"
        )
      end

      it "bumps the version while preserving comments and block comments" do
        updated_content = updater.updated_dependency_files.first.content
        expect(updated_content).to include("jsr:@std/path@^1.1.4")
        expect(updated_content).not_to include("jsr:@std/path@^1.0.0")
        expect(updated_content).to include("// Top-level comment")
        expect(updated_content).to include("/* block comment */")
        expect(updated_content).to include('"jsr:@std/path@^1.1.4" // trailing comment')
      end
    end

    context "when a deno.lock is present" do
      let(:files) do
        project_dependency_files("deno/with_lockfile")
      end

      it "emits both the manifest and the lockfile" do
        updated_files = updater.updated_dependency_files
        expect(updated_files.map(&:name)).to contain_exactly("deno.json", "deno.lock")
      end

      it "updates the lockfile to a version satisfying the new constraint" do
        lockfile = updater.updated_dependency_files.find { |f| f.name == "deno.lock" }
        lock = JSON.parse(lockfile.content)
        resolved = Gem::Version.new(lock.dig("specifiers", "jsr:@std/path@^1.1.4"))
        expect(resolved).to be >= Gem::Version.new("1.1.4")
        expect(resolved).to be < Gem::Version.new("2.0.0")
      end
    end

    context "when no deno.lock is present" do
      # files defaults to the top-level inline manifest only (no lockfile)
      it "emits only the manifest" do
        updated_files = updater.updated_dependency_files
        expect(updated_files.map(&:name)).to eq(["deno.json"])
      end
    end
  end
end
