# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Composer::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  let(:credentials) { github_credentials }
  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "exact_version" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.22.1",
      requirements: requirements,
      previous_version: "1.0.1",
      previous_requirements: previous_requirements,
      package_manager: "composer"
    )
  end
  let(:requirements) do
    [{
      file: "composer.json",
      requirement: "1.22.1",
      groups: [],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "composer.json",
      requirement: "1.0.1",
      groups: [],
      source: nil
    }]
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently or output to stdout" do
      expect { expect { updated_files }.to_not(output.to_stdout) }.
        to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      expect(updated_files.count).to eq(2)
    end

    describe "the updated composer_file" do
      let(:files) { [composer_json] }
      let(:composer_json) do
        Dependabot::DependencyFile.new(
          name: "composer.json",
          content: fixture("projects/exact_version/composer.json")
        )
      end

      context "if no files have changed" do
        let(:requirements) { previous_requirements }

        it "raises a helpful error" do
          expect { updater.updated_dependency_files }.
            to raise_error("No files have changed!")
        end
      end

      context "when the manifest has changed" do
        let(:updated_manifest_content) do
          updated_files.find { |f| f.name == "composer.json" }.content
        end

        it "includes the new requirement" do
          expect(updated_manifest_content).
            to include("\"monolog/monolog\" : \"1.22.1\"")
          expect(updated_manifest_content).
            to include("\"symfony/polyfill-mbstring\": \"1.0.1\"")
        end
      end
    end

    describe "the updated lockfile" do
      let(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "composer.lock" }.content
      end
      let(:parsed_updated_lockfile_content) { JSON.parse(updated_lockfile_content) }
      let(:updated_lockfile_entry) do
        parsed_updated_lockfile_content["packages"].find do |package|
          package["name"] == dependency.name
        end
      end

      it "updates the dependency version and plugin-api-version (to match instaled composer) in the lockfile" do
        expect(updated_lockfile_entry["version"]).to eq("1.22.1")
        expect(parsed_updated_lockfile_content["prefer-stable"]).to be(false)
        expect(parsed_updated_lockfile_content["plugin-api-version"]).to eq("2.2.0")
      end
    end

    describe "updates the lockfile using composer v1" do
      let(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "composer.lock" }.content
      end
      let(:parsed_updated_lockfile_content) { JSON.parse(updated_lockfile_content) }
      let(:updated_lockfile_entry) do
        parsed_updated_lockfile_content["packages"].find do |package|
          package["name"] == dependency.name
        end
      end
      let(:project_name) { "v1/exact_version" }

      it "updates the dependency version and plugin-api-version (to match instaled composer) in the lockfile" do
        expect(updated_lockfile_entry["version"]).to eq("1.22.1")
        expect(parsed_updated_lockfile_content["plugin-api-version"]).to eq("1.1.0")
      end
    end

    context "with a project that specifies a platform package" do
      let(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "composer.lock" }.content
      end
      let(:parsed_updated_lockfile_content) { JSON.parse(updated_lockfile_content) }
      let(:updated_lockfile_entry) do
        parsed_updated_lockfile_content["packages"].find do |package|
          package["name"] == dependency.name
        end
      end
      let(:project_name) { "platform_package" }

      it "updates the dependency and does not downgrade the composer version" do
        expect(updated_lockfile_entry["version"]).to eq("1.22.1")
        expect(parsed_updated_lockfile_content["plugin-api-version"]).to eq("2.2.0")
      end
    end
  end
end
