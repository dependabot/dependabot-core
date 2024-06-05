# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Devcontainers::UpdateChecker do
  let(:dependency) { dependencies.find { |dep| dep.name == name } }
  let(:file_parser) do
    Dependabot::Devcontainers::FileParser.new(
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      source: nil
    )
  end
  let(:dependencies) do
    file_parser.parse
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:dependency_files) { project_dependency_files(project_name, directory: directory) }
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

  it_behaves_like "an update checker"

  shared_context "when the config is in root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    context "when feature is out-of-date" do
      let(:name) { "ghcr.io/codspace/versioning/foo" }

      context "when the config is in root" do
        include_context "when the config is in root"

        it { is_expected.to be_falsey }
      end

      context "when the config is in .devcontainer folder" do
        let(:project_name) { "config_in_dot_devcontainer_folder" }
        let(:directory) { "/.devcontainer" }

        it { is_expected.to be_falsey }
      end
    end

    context "when feature is already up-to-date" do
      let(:name) { "ghcr.io/codspace/versioning/bar" }

      context "when the config is in root" do
        include_context "when the config is in root"

        it { is_expected.to be_truthy }
      end

      context "when the config is in .devcontainer folder" do
        let(:project_name) { "config_in_dot_devcontainer_folder" }
        let(:directory) { "/.devcontainer" }

        it { is_expected.to be_truthy }
      end
    end
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version.to_s }

    let(:name) { "ghcr.io/codspace/versioning/foo" }
    let(:current_version) { "1.1.0" }

    include_context "when the config is in root"

    context "when all later versions are being ignored" do
      let(:ignored_versions) { ["> #{current_version}"] }

      it { is_expected.to eq(current_version) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "raises an error" do
          expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when some later versions are not ignored" do
      let(:ignored_versions) { [">= 2.1.0"] }

      it { is_expected.to eq("2.0.0") }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it { is_expected.to eq("2.0.0") }
      end
    end
  end
end
