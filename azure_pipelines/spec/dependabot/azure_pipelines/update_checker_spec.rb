# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/azure_pipelines/file_parser"
require "dependabot/azure_pipelines/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::AzurePipelines::UpdateChecker do
  let(:dependency) { dependencies.find { |dep| dep.name == "Gradle" } }
  let(:file_parser) do
    Dependabot::AzurePipelines::FileParser.new(
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

  let(:latest_version_finder) { instance_double(Dependabot::AzurePipelines::UpdateChecker::LatestVersionFinder) }

  it_behaves_like "an update checker"

  shared_context "with a Gradle task" do
    let(:project_name) { "jobs" }
    let(:directory) { "/" }
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    include_context "with a Gradle task"

    before do
      allow(Dependabot::AzurePipelines::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
    end

    context "when the dependency is out-of-date" do
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("3.247.1"))
      end

      it { is_expected.to be_falsey }
    end

    context "when the dependency is already up-to-date" do
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("3.0.0"))
      end

      it { is_expected.to be_truthy }
    end
  end
end
