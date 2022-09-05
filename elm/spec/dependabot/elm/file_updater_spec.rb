# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/elm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Elm::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
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
  let(:files) { [elm_json_file] }
  let(:elm_json_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm_jsons", elm_json_file_fixture_name),
      name: "elm.json"
    )
  end
  let(:elm_json_file_fixture_name) { "app.json" }

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
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    describe "the elm.json file" do
      subject(:updated_elm_json_file_content) do
        updated_files.find { |f| f.name == "elm.json" }.content
      end

      it "updates the right dependency" do
        expect(updated_elm_json_file_content).
          to include(%("elm/regex": "1.1.0"))
        expect(updated_elm_json_file_content).
          to include(%("elm/html": "1.0.0"))
      end
    end
  end
end
