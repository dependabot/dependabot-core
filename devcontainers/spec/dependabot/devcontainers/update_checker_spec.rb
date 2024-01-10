# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Devcontainers::UpdateChecker do
  it_behaves_like "an update checker"

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

  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:dependency_files) { project_dependency_files(project_name, directory: directory) }
  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }

  let(:dependencies) do
    file_parser.parse
  end

  let(:file_parser) do
    Dependabot::Devcontainers::FileParser.new(
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      source: nil
    )
  end

  let(:dependency) { dependencies.find { |dep| dep.name == name } }

  context "Feature that is out-of-date" do
    let(:name) { "ghcr.io/codspace/versioning/foo" }

    describe "config in root" do
      let(:project_name) { "config_in_root" }
      let(:directory) { "/" }
      subject { checker.up_to_date? }
      it { is_expected.to be_falsey }
    end

    describe "config in .devcontainer folder " do
      let(:project_name) { "config_in_dot_devcontainer_folder" }
      let(:directory) { "/.devcontainer" }
      subject { checker.up_to_date? }
      it { is_expected.to be_falsey }
    end
  end

  context "Feature that is already up-to-date" do
    let(:name) { "ghcr.io/codspace/versioning/bar" }

    describe "config in root" do
      let(:project_name) { "config_in_root" }
      let(:directory) { "/" }
      subject { checker.up_to_date? }
      it { is_expected.to be_truthy }
    end

    describe "config in .devcontainer folder " do
      let(:project_name) { "config_in_dot_devcontainer_folder" }
      let(:directory) { "/.devcontainer" }
      subject { checker.up_to_date? }
      it { is_expected.to be_truthy }
    end
  end
end
