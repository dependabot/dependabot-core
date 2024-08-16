# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cargo/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Cargo::FileUpdater do
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:previous_requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:requirements) { previous_requirements }
  let(:dependency_previous_version) { "0.1.38" }
  let(:dependency_version) { "0.1.40" }
  let(:dependency_name) { "time" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "cargo"
    )
  end
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_body) { fixture("lockfiles", lockfile_fixture_name) }
  let(:manifest_body) { fixture("manifests", manifest_fixture_name) }
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Cargo.lock", content: lockfile_body)
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Cargo.toml", content: manifest_body)
  end
  let(:files) { [manifest, lockfile] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
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
    subject(:updated_files_regex) { described_class.updated_files_regex(allowlist_enabled) }

    let(:allowlist_enabled) { false } # default value

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "Cargo.toml",
          "Cargo.lock",
          "some_project/Cargo.toml",
          "some_project/Cargo.lock",
          "some_project/subdir/Cargo.toml",
          "some_project/subdir/Cargo.lock"
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

    context "without a lockfile" do
      let(:files) { [manifest] }

      context "when no files have changed" do
        it "raises a helpful error" do
          expect { updater.updated_dependency_files }
            .to raise_error("No files changed!")
        end
      end

      context "when the manifest has changed" do
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: "0.1.38",
            groups: [],
            source: nil
          }]
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated manifest" do
          subject(:updated_manifest_content) do
            updated_files.find { |f| f.name == "Cargo.toml" }.content
          end

          it "includes the new requirement" do
            expect(described_class::ManifestUpdater)
              .to receive(:new)
              .with(dependencies: [dependency], manifest: manifest)
              .and_call_original

            expect(updated_manifest_content).to include(%(time = "0.1.38"))
            expect(updated_manifest_content).to include(%(regex = "0.1.41"))
          end
        end
      end
    end

    context "with a lockfile" do
      describe "the updated lockfile" do
        subject(:updated_lockfile_content) do
          updated_files.find { |f| f.name == "Cargo.lock" }.content
        end

        it "updates the dependency version in the lockfile" do
          expect(described_class::LockfileUpdater)
            .to receive(:new)
            .with(
              credentials: credentials,
              dependencies: [dependency],
              dependency_files: files
            )
            .and_call_original

          expect(updated_lockfile_content)
            .to include(%(name = "time"\nversion = "0.1.40"))
          expect(updated_lockfile_content).to include(
            "d825be0eb33fda1a7e68012d51e9c7f451dc1a69391e7fdc197060bb8c56667b"
          )
          expect(updated_lockfile_content).not_to include(
            "d5d788d3aa77bc0ef3e9621256885555368b47bd495c13dd2e7413c89f845520"
          )
        end
      end
    end
  end
end
