# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pipfile"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Python::Pipfile do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [pipfile, lockfile],
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      content: pipfile_body,
      name: "Pipfile"
    )
  end
  let(:pipfile_body) do
    fixture("python", "pipfiles", "version_not_specified")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: lockfile_body,
      name: "Pipfile.lock"
    )
  end
  let(:lockfile_body) do
    fixture("python", "lockfiles", "version_not_specified.lock")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.18.4",
      previous_version: "2.18.0",
      package_manager: "pipfile",
      requirements: [
        { requirement: "*", file: "Pipfile", source: nil, groups: ["default"] }
      ],
      previous_requirements: [
        { requirement: "*", file: "Pipfile", source: nil, groups: ["default"] }
      ]
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated Pipfile" do
      subject(:updated_pipfile) do
        updated_files.find { |f| f.name == "Pipfile" }
      end

      its(:content) { is_expected.to eq(pipfile_body) }
    end

    describe "the updated Pipfile.lock" do
      let(:updated_lockfile) do
        updated_files.find { |f| f.name == "Pipfile.lock" }
      end

      let(:json_lockfile) { JSON.parse(updated_lockfile.content) }

      it "updates only what it needs to" do
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        expect(json_lockfile["_meta"]["hash"]).
          to eq(JSON.parse(lockfile_body)["_meta"]["hash"])
        expect(
          json_lockfile["_meta"]["host-environment-markers"]["python_version"]
        ).to eq("2.7")
      end
    end
  end
end
