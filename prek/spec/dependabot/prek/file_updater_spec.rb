# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/prek/file_updater"
require "dependabot/prek/version"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Prek::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/pre-commit/pre-commit-hooks",
      version: "v6.0.0",
      previous_version: "v4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "prek.toml",
        source: {
          type: "git",
          url: "https://github.com/pre-commit/pre-commit-hooks",
          ref: "v6.0.0",
          branch: nil
        }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "prek.toml",
        source: {
          type: "git",
          url: "https://github.com/pre-commit/pre-commit-hooks",
          ref: "v4.4.0",
          branch: nil
        }
      }],
      package_manager: "prek"
    )
  end
  let(:config_file_body) { fixture("prek_configs", "basic.toml") }
  let(:config_file) do
    Dependabot::DependencyFile.new(
      content: config_file_body,
      name: "prek.toml"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [config_file] }
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  it_behaves_like "a dependency file updater"

  it "is registered as the file updater for the prek package manager" do
    expect(Dependabot::FileUpdaters.for_package_manager("prek")).to eq(described_class)
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      expect(updated_files).to all(be_a(Dependabot::DependencyFile))
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated config file" do
      subject(:updated_config_file) do
        updated_files.find { |f| f.name == "prek.toml" }
      end

      its(:content) do
        is_expected.to include 'rev = "v6.0.0"'
        is_expected.not_to include 'rev = "v4.4.0"'
      end

      it "leaves other repos untouched" do
        expect(updated_config_file.content).to include 'rev = "23.12.1"'
      end
    end

    context "when only a different repo is updated" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/psf/black",
          version: "24.0.0",
          previous_version: "23.12.1",
          requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/psf/black", ref: "24.0.0", branch: nil
            }
          }],
          previous_requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/psf/black", ref: "23.12.1", branch: nil
            }
          }],
          package_manager: "prek"
        )
      end

      it "updates only the matching repo's rev" do
        content = updated_files.find { |f| f.name == "prek.toml" }.content
        expect(content).to include 'rev = "24.0.0"'
        expect(content).to include 'rev = "v4.4.0"'
      end
    end

    context "with repos defined as an inline-table array" do
      let(:config_file_body) { fixture("prek_configs", "inline_repos.toml") }

      it "updates the rev inside the matching inline table" do
        content = updated_files.find { |f| f.name == "prek.toml" }.content
        expect(content).to include 'rev = "v6.0.0"'
        expect(content).not_to include 'rev = "v4.4.0"'
      end

      it "leaves other inline-table repos untouched" do
        content = updated_files.find { |f| f.name == "prek.toml" }.content
        expect(content).to include 'rev = "23.12.1"'
      end
    end

    context "with a frozen SHA pin and version comment" do
      let(:config_file_body) { fixture("prek_configs", "frozen.toml") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/pre-commit/pre-commit-hooks",
          version: "10864545ddc58bd96330029b6bff16da3d072237",
          previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
          requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "10864545ddc58bd96330029b6bff16da3d072237", branch: nil
            },
            metadata: { comment_version: "v4.4.0", new_comment_version: "v6.0.0" }
          }],
          previous_requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e", branch: nil
            },
            metadata: { comment: "# frozen: v4.4.0" }
          }],
          package_manager: "prek"
        )
      end

      it "rewrites both the SHA and the frozen version comment" do
        content = updated_files.find { |f| f.name == "prek.toml" }.content
        expect(content).to include('rev = "10864545ddc58bd96330029b6bff16da3d072237"')
        expect(content).to include("# frozen: v6.0.0")
        expect(content).not_to include("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
        expect(content).not_to include("v4.4.0")
      end
    end

    context "when the dependency's old ref is a prefix of the on-file rev" do
      # The on-file rev is "v4.4.0"; the recorded previous ref is the prefix
      # "v4.4". A prefix must NOT partially rewrite the longer on-file value.
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/pre-commit/pre-commit-hooks",
          version: "v6.0.0",
          previous_version: "v4.4",
          requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v6.0.0", branch: nil
            }
          }],
          previous_requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v4.4", branch: nil
            }
          }],
          package_manager: "prek"
        )
      end

      it "does not corrupt the longer rev value" do
        expect { updated_files }.to raise_error(/No files changed/)
      end
    end
  end
end
