# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/elm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Elm::FileUpdater do
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "elm/regex",
      version: "1.1.0",
      requirements: [{
        file: "elm.json",
        requirement: "1.1.0",
        groups: [],
        source: nil
      }],
      previous_version: "1.0.0",
      previous_requirements: [{
        file: "elm.json",
        requirement: "1.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "elm"
    )
  end
  let(:elm_json_file_fixture_name) { "app.json" }
  let(:elm_json_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm_jsons", elm_json_file_fixture_name),
      name: "elm.json"
    )
  end
  let(:files) { [elm_json_file] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  before { FileUtils.mkdir_p(tmp_path) }

  it_behaves_like "a dependency file updater"

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "elm.json"
        ]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.not_to output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    describe "the elm.json file" do
      subject(:updated_elm_json_file_content) do
        updated_files.find { |f| f.name == "elm.json" }.content
      end

      it "updates the right dependency" do
        expect(updated_elm_json_file_content)
          .to include(%("elm/regex": "1.1.0"))
        expect(updated_elm_json_file_content)
          .to include(%("elm/html": "1.0.0"))
      end
    end
  end
end
