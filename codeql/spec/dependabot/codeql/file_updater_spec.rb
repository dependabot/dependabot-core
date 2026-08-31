# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/codeql/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Codeql::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials
    )
  end

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  let(:files) { [qlpack_file, lockfile] }

  let(:qlpack_file) do
    Dependabot::DependencyFile.new(
      name: "qlpack.yml",
      content: <<~YAML,
        name: example/queries
        version: 1.2.3
        dependencies:
          codeql/java-all: ^0.9.1
          codeql/javascript-all: ^0.9.0
      YAML
      directory: "/"
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "codeql-pack.lock.yml",
      content: <<~YAML,
        dependencies:
          codeql/java-all:
            version: 0.9.1
          codeql/javascript-all:
            version: 0.9.0
          transitive/dep:
            version: 1.0.0
      YAML
      directory: "/"
    )
  end

  let(:dependencies) { [dependency] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "codeql/java-all",
      version: "0.10.0",
      previous_version: "0.9.1",
      requirements: [{
        requirement: "^0.10.0",
        groups: [],
        file: "qlpack.yml",
        source: { type: "codeql_pack_registry" }
      }],
      previous_requirements: [{
        requirement: "^0.9.1",
        groups: [],
        file: "qlpack.yml",
        source: { type: "codeql_pack_registry" }
      }],
      package_manager: "codeql"
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the requirement in qlpack.yml" do
      updated_manifest = updated_files.find { |f| f.name == "qlpack.yml" }

      expect(updated_manifest.content).to include("codeql/java-all: ^0.10.0")
      expect(updated_manifest.content).to include("codeql/javascript-all: ^0.9.0")
    end

    it "updates the resolved version in codeql-pack.lock.yml" do
      updated_lockfile = updated_files.find { |f| f.name == "codeql-pack.lock.yml" }

      expect(updated_lockfile.content).to include("codeql/java-all:\n    version: 0.10.0")
    end

    it "does not touch other dependencies in the lockfile" do
      updated_lockfile = updated_files.find { |f| f.name == "codeql-pack.lock.yml" }

      expect(updated_lockfile.content).to include("codeql/javascript-all:\n    version: 0.9.0")
      expect(updated_lockfile.content).to include("transitive/dep:\n    version: 1.0.0")
    end

    it "returns only the files that changed" do
      expect(updated_files.map(&:name)).to contain_exactly("qlpack.yml", "codeql-pack.lock.yml")
    end

    context "when the new version stays within the existing range" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "codeql/java-all",
          version: "0.9.5",
          previous_version: "0.9.1",
          requirements: [{
            requirement: "^0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          previous_requirements: [{
            requirement: "^0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          package_manager: "codeql"
        )
      end

      it "leaves qlpack.yml unchanged" do
        expect(updated_files.map(&:name)).not_to include("qlpack.yml")
      end

      it "still bumps the lockfile to the resolved version" do
        updated_lockfile = updated_files.find { |f| f.name == "codeql-pack.lock.yml" }

        expect(updated_lockfile.content).to include("codeql/java-all:\n    version: 0.9.5")
      end
    end

    context "when there is no lockfile" do
      let(:files) { [qlpack_file] }

      it "updates only the manifest requirement" do
        expect(updated_files.map(&:name)).to contain_exactly("qlpack.yml")
        updated_manifest = updated_files.find { |f| f.name == "qlpack.yml" }
        expect(updated_manifest.content).to include("codeql/java-all: ^0.10.0")
      end
    end

    context "when no files changed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "codeql/java-all",
          version: "0.9.1",
          previous_version: "0.9.1",
          requirements: [{
            requirement: "^0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          previous_requirements: [{
            requirement: "^0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          package_manager: "codeql"
        )
      end

      it "raises an error" do
        expect { updated_files }.to raise_error("No files changed!")
      end
    end
  end

  describe "#check_required_files" do
    context "without a qlpack.yml" do
      let(:files) { [lockfile] }

      it "raises an error" do
        expect { updater }.to raise_error("No qlpack.yml file!")
      end
    end
  end
end
