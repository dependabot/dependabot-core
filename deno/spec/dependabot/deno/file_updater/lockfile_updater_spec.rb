# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/file_updater/lockfile_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Deno::FileUpdater::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: files,
      credentials: credentials
    )
  end
  let(:credentials) { [] }
  let(:files) { project_dependency_files("deno/with_lockfile") }
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

  describe "#updated_lockfile_content" do
    it "returns lockfile content with a version satisfying the new constraint" do
      content = updater.updated_lockfile_content
      lock = JSON.parse(content)

      # Specifier key reflects the bumped constraint; resolved value must satisfy ^1.1.4.
      resolved = Gem::Version.new(lock.fetch("specifiers").fetch("jsr:@std/path@^1.1.4"))
      expect(resolved).to be >= Gem::Version.new("1.1.4")
      expect(resolved).to be < Gem::Version.new("2.0.0")

      # Old pinned 1.0.0 entry is gone.
      expect(lock.fetch("jsr")).not_to have_key("@std/path@1.0.0")
    end

    it "preserves the v4 lockfile format" do
      content = updater.updated_lockfile_content
      lock = JSON.parse(content)
      expect(lock["version"]).to eq("4")
    end
  end

  context "with an npm dependency" do
    let(:files) { project_dependency_files("deno/with_lockfile_npm") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "chalk",
        version: "5.4.0",
        previous_version: "5.3.0",
        requirements: [{
          requirement: "^5.4.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "npm" }
        }],
        previous_requirements: [{
          requirement: "^5.3.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "npm" }
        }],
        package_manager: "deno"
      )
    end

    it "updates the npm block in the lockfile" do
      content = updater.updated_lockfile_content
      lock = JSON.parse(content)
      resolved = Gem::Version.new(lock.fetch("specifiers").fetch("npm:chalk@^5.4.0"))
      expect(resolved).to be >= Gem::Version.new("5.4.0")
      expect(resolved).to be < Gem::Version.new("6.0.0")
      expect(lock.fetch("npm")).not_to have_key("chalk@5.3.0")
    end
  end

  context "with a deno.jsonc manifest" do
    let(:files) { project_dependency_files("deno/with_lockfile_jsonc") }
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

    it "regenerates the lockfile from a JSONC manifest" do
      content = updater.updated_lockfile_content
      lock = JSON.parse(content)
      resolved = Gem::Version.new(lock.dig("specifiers", "jsr:@std/path@^1.1.4"))
      expect(resolved).to be >= Gem::Version.new("1.1.4")
      expect(resolved).to be < Gem::Version.new("2.0.0")
    end
  end

  context "with multiple dependencies in the lockfile" do
    let(:files) { project_dependency_files("deno/with_lockfile_multi") }
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

    it "bumps the targeted dep while keeping untouched deps resolvable" do
      content = updater.updated_lockfile_content
      lock = JSON.parse(content)

      path_keys = lock["jsr"].keys.grep(%r{^@std/path@})
      expect(path_keys.length).to eq(1)
      path_version = Gem::Version.new(path_keys.first.split("@").last)
      expect(path_version).to be >= Gem::Version.new("1.1.4")
      expect(path_version).to be < Gem::Version.new("2.0.0")

      expect(lock["jsr"].keys).to include(match(%r{^@std/assert@}))
    end
  end

  context "when deno install does not change the lockfile" do
    before do
      # Stub run_deno_command to leave the lockfile untouched in the tmpdir.
      allow(Dependabot::Deno::Helpers).to receive(:run_deno_command).and_return("")
    end

    it "raises DependencyFileNotResolvable with a diagnostic message" do
      expect do
        updater.updated_lockfile_content
      end.to raise_error(Dependabot::DependencyFileNotResolvable, /did not change/)
    end
  end

  context "when deno install exits non-zero" do
    before do
      allow(Dependabot::Deno::Helpers).to receive(:run_deno_command)
        .and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "error: Unable to parse config file",
            error_context: { command: "deno install" }
          )
        )
    end

    it "wraps the helper error as DependencyFileNotResolvable" do
      expect do
        updater.updated_lockfile_content
      end.to raise_error(Dependabot::DependencyFileNotResolvable, /Unable to parse config file/)
    end
  end
end
