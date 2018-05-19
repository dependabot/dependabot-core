# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pip_compile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PipCompileFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("python", "pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("python", "requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "18.1.0" }
  let(:dependency_previous_version) { "17.4.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:dependency_previous_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the requirements.txt" do
      expect(updated_files.count).to eq(1)
      expect(updated_files.first.content).to include("attrs==18.1.0")
      expect(updated_files.first.content).
        to include("pbr==4.0.2                # via mock")
      expect(updated_files.first.content).to include("# This file is autogen")
      expect(updated_files.first.content).to_not include("--hash=sha")
    end

    context "with hashes" do
      let(:generated_fixture_name) { "pip_compile_hashes.txt" }

      it "updates the requirements.txt, keeping the hashes" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).to include("4b90b09eeeb9b88c35bc64")
        expect(updated_files.first.content).to include("# This file is autogen")
      end
    end

    context "when the requirement.in file needs to be updated" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }

      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=18.1.0",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      it "updates the requirements.txt and the requirements.in" do
        expect(updated_files.count).to eq(2)
        expect(updated_files.first.content).to include("Attrs<=18.1.0")
        expect(updated_files.last.content).to include("attrs==18.1.0")
        expect(updated_files.last.content).to_not include("# via mock")
      end
    end
  end
end
