# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/crystal_shards/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::CrystalShards::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end

  let(:dependency_files) { [shard_yml] }

  let(:shard_yml) do
    Dependabot::DependencyFile.new(
      name: "shard.yml",
      content: <<~YAML
        name: my_shard
        version: 1.0.0

        dependencies:
          kemal:
            github: kemalcr/kemal
            version: ~> 1.0.0
      YAML
    )
  end

  let(:dependencies) { [dependency] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "kemal",
      version: "1.1.0",
      previous_version: "1.0.0",
      requirements: [{
        file: "shard.yml",
        requirement: "~> 1.1.0",
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/kemalcr/kemal"
        }
      }],
      previous_requirements: [{
        file: "shard.yml",
        requirement: "~> 1.0.0",
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/kemalcr/kemal"
        }
      }],
      package_manager: "crystal_shards"
    )
  end

  let(:credentials) { [] }

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "when version requirement changes" do
      it "returns updated shard.yml" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("shard.yml")
        expect(updated_files.first.content).to include("~> 1.1.0")
      end
    end

    context "when no changes are needed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "kemal",
          version: "1.0.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "shard.yml",
            requirement: "~> 1.0.0",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/kemalcr/kemal"
            }
          }],
          previous_requirements: [{
            file: "shard.yml",
            requirement: "~> 1.0.0",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/kemalcr/kemal"
            }
          }],
          package_manager: "crystal_shards"
        )
      end

      it "raises error when no files changed" do
        expect { updated_files }.to raise_error("No files changed!")
      end
    end

    context "when updating git tag reference" do
      let(:shard_yml) do
        Dependabot::DependencyFile.new(
          name: "shard.yml",
          content: <<~YAML
            name: my_shard
            version: 1.0.0

            dependencies:
              kemal:
                github: kemalcr/kemal
                tag: v1.0.0
          YAML
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "kemal",
          version: "1.1.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "shard.yml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/kemalcr/kemal",
              ref: "v1.1.0"
            }
          }],
          previous_requirements: [{
            file: "shard.yml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/kemalcr/kemal",
              ref: "v1.0.0"
            }
          }],
          package_manager: "crystal_shards"
        )
      end

      it "updates the tag reference" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.content).to include("v1.1.0")
      end
    end
  end

  describe "#check_required_files" do
    context "when shard.yml is present" do
      it "passes the required files check" do
        # When shard.yml is present, check_required_files passes and we get updated files
        expect(updater.updated_dependency_files).to be_an(Array)
      end
    end

    context "when shard.yml is missing" do
      let(:dependency_files) { [] }

      it "raises an error" do
        expect { updater.updated_dependency_files }.to raise_error("No shard.yml")
      end
    end
  end
end
