# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/nuget/file_updater"
require_relative "github_helpers"
require "json"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Nuget::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:file_updater_instance) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }],
      repo_contents_path: repo_contents_path
    )
  end
  let(:dependencies) { [dependency] }
  let(:project_name) { "dirsproj" }
  let(:directory) { "/" }
  let(:dependency_files) { nuget_project_dependency_files(project_name, directory: directory) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "nuget"
    )
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "1.1.1" }
  let(:dependency_previous_version) { "1.0.0" }
  let(:requirements) do
    [{ file: "Dir1/Dir1a/Dir1a.csproj", requirement: "1.1.1", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Dir1/Dir1a/Dir1a.csproj", requirement: "1.0.0", groups: [], source: nil }]
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:repo_contents_path) { nil }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
  end
  context "with a dirs.proj" do
    it "does not repeatedly update the same project" do
      expect(updated_files).to eq([
        "Dir1/Dir1a/Dir1a.csproj"
      ])

      expect(file_updater_instance.send(:testonly_update_tooling_calls)).to eq(
        {
          "dirs.proj": 1
        }
      )
    end
  end
end
