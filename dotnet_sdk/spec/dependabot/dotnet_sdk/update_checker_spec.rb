# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dotnet_sdk/file_parser"
require "dependabot/dotnet_sdk/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::DotnetSdk::UpdateChecker do
  let(:dependency) { dependencies.find { |dep| dep.name == "dotnet-sdk" } }
  let(:file_parser) do
    Dependabot::DotnetSdk::FileParser.new(
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

  let(:latest_version_finder) { instance_double(Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder) }

  it_behaves_like "an update checker"

  shared_context "when the config is in root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    include_context "when the config is in root"

    before do
      allow(Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
    end

    context "when the sdk is out-of-date" do
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("8.0.301"))
      end

      it { is_expected.to be_falsey }
    end

    context "when the sdk is already up-to-date" do
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("8.0.300"))
      end

      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    include_context "when the config is in root"

    before do
      allow(Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
    end

    context "when no versions are ignored" do
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("8.0.301"))
      end

      it { is_expected.to eq(Dependabot::Version.new("8.0.301")) }
    end

    context "when the latest version is ignored" do
      let(:ignored_versions) { [">= 8.0.301"] }

      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Version.new("8.0.300"))
      end

      it { is_expected.to eq(Dependabot::Version.new("8.0.300")) }
    end
  end
end
