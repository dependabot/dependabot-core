# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/php/composer"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Php::Composer do
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
  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: fixture("php", "composer_files", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: fixture("php", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

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
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

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
      subject(:updated_manifest_content) do
        updated_files.find { |f| f.name == "composer.json" }.content
      end

      context "if no files have changed" do
        let(:requirements) { previous_requirements }

        it "raises a helpful error" do
          expect { updater.updated_dependency_files }.
            to raise_error("No files have changed!")
        end
      end

      context "when the manifest has changed" do
        it "includes the new requirement" do
          expect(described_class::ManifestUpdater).
            to receive(:new).
            with(dependencies: [dependency], manifest: composer_json).
            and_call_original

          expect(updated_manifest_content).
            to include("\"monolog/monolog\" : \"1.22.1\"")
          expect(updated_manifest_content).
            to include("\"symfony/polyfill-mbstring\": \"1.0.1\"")
        end
      end
    end

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "composer.lock" }.content
      end

      it "updates the dependency version in the lockfile" do
        expect(described_class::LockfileUpdater).
          to receive(:new).
          with(
            credentials: credentials,
            dependencies: [dependency],
            dependency_files: files
          ).
          and_call_original

        expect(updated_lockfile_content).to include("\"version\": \"1.22.1\"")
        expect(updated_lockfile_content).to include("\"prefer-stable\": false")
      end
    end
  end
end
