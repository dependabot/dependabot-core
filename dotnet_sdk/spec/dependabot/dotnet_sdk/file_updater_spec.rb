# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dotnet_sdk/file_updater"
require "dependabot/dotnet_sdk/requirement"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::DotnetSdk::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end
  let(:directory) { "/" }
  let(:files) { project_dependency_files(project_name, directory: directory) }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  it_behaves_like "a dependency file updater"

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = ["global.json"]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          "src/global.json"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) { updater.updated_dependency_files }

    let(:project_name) { "config_in_root" }

    context "when the requirement has changed" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "dotnet-sdk",
            version: "8.0.402",
            previous_version: "8.0.300",
            requirements: [{
              requirement: "8.0.402",
              file: "global.json",
              groups: nil,
              source: nil
            }],
            previous_requirements: [{
              requirement: "8.0.300",
              file: "global.json",
              groups: nil,
              source: nil
            }],
            package_manager: "dotnet_sdk"
          )
        ]
      end

      it "updates the version in global.json when the requirement has changed" do
        expect(updated_dependency_files.size).to eq(1)

        config = updated_dependency_files.first
        expect(config.name).to eq("global.json")
        expect(config.content).to include("8.0.402")
      end
    end

    context "when the requirement has not changed" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "dotnet-sdk",
            version: "8.0.300",
            previous_version: "8.0.300",
            requirements: [{
              requirement: "8.0.300",
              file: "global.json",
              groups: nil,
              source: nil
            }],
            previous_requirements: [{
              requirement: "8.0.300",
              file: "global.json",
              groups: nil,
              source: nil
            }],
            package_manager: "dotnet_sdk"
          )
        ]
      end

      it "does not update the version in global.json when the requirement has not changed" do
        expect(updated_dependency_files.size).to eq(0)
      end
    end
  end
end
