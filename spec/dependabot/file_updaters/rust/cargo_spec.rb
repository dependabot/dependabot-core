# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/rust/cargo"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Rust::Cargo do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
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

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Cargo.toml", content: manifest_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Cargo.lock", content: lockfile_body)
  end
  let(:manifest_body) { fixture("rust", "manifests", manifest_fixture_name) }
  let(:lockfile_body) { fixture("rust", "lockfiles", lockfile_fixture_name) }
  let(:manifest_fixture_name) { "exact_version_specified" }
  let(:lockfile_fixture_name) { "exact_version_specified" }

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
  let(:dependency_name) { "time" }
  let(:dependency_version) { "0.1.39" }
  let(:dependency_previous_version) { "0.1.38" }
  let(:requirements) { previous_requirements }
  let(:previous_requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
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

    it { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    context "without a lockfile" do
      let(:files) { [manifest] }

      context "if no files have changed" do
        it "raises a helpful error" do
          expect { updater.updated_dependency_files }.
            to raise_error("No files changed!")
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
            expect(updated_manifest_content).to include(%(time = "0.1.38"))
            expect(updated_manifest_content).to include(%(regex = "0.1.41"))
            expect(updated_manifest_content).
              to_not include(%("time" = "0.1.12"))
          end

          context "with an optional dependency" do
            let(:manifest_fixture_name) { "optional_dependency" }
            let(:lockfile_fixture_name) { "optional_dependency" }
            let(:dependency_name) { "utf8-ranges" }
            let(:dependency_version) { "1.0.0" }
            let(:dependency_previous_version) { "0.1.3" }
            let(:requirements) do
              [{
                file: "Cargo.toml",
                requirement: "1.0.0",
                groups: [],
                source: nil
              }]
            end
            let(:previous_requirements) do
              [{
                file: "Cargo.toml",
                requirement: "0.1.3",
                groups: [],
                source: nil
              }]
            end

            it "includes the new requirement" do
              expect(updated_manifest_content).to include(
                %(utf8-ranges = { version = "1.0.0", optional = true })
              )
            end
          end
        end
      end
    end

    context "when updating the lockfile fails" do
      let(:dependency_version) { "99.0.0" }
      let(:requirements) do
        [{ file: "Cargo.toml", requirement: "99", groups: [], source: nil }]
      end

      it "raises a helpful error" do
        expect { updater.updated_dependency_files }.
          to raise_error do |error|
            expect(error).
              to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
            expect(error.message).to include("no matching version")
          end
      end
    end

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "Cargo.lock" }.content
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).
          to include(%(name = "time"\nversion = "0.1.39"))
        expect(updated_lockfile_content).to include(
          "a15375f1df02096fb3317256ce2cee6a1f42fc84ea5ad5fc8c421cfe40c73098"
        )
        expect(updated_lockfile_content).to_not include(
          "d5d788d3aa77bc0ef3e9621256885555368b47bd495c13dd2e7413c89f845520"
        )
      end

      context "when there is a path dependency" do
        let(:files) { [manifest, lockfile, path_dependency_file] }
        let(:manifest_fixture_name) { "path_dependency" }
        let(:lockfile_fixture_name) { "path_dependency" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "regex",
            version: "0.2.10",
            requirements: [
              {
                file: "Cargo.toml",
                requirement: "=0.2.10",
                groups: [],
                source: nil
              }
            ],
            previous_version: "0.1.38",
            previous_requirements: [
              {
                file: "Cargo.toml",
                requirement: "=0.1.38",
                groups: [],
                source: nil
              }
            ],
            package_manager: "cargo"
          )
        end
        let(:path_dependency_file) do
          Dependabot::DependencyFile.new(
            name: "src/s3/Cargo.toml",
            content: fixture("rust", "manifests", "cargo-registry-s3")
          )
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).
            to include(%(name = "regex"\nversion = "0.2.10"))
          expect(updated_lockfile_content).to include(
            "aec3f58d903a7d2a9dc2bf0e41a746f4530e0cab6b615494e058f67a3ef947fb"
          )
          expect(updated_lockfile_content).to_not include(
            "bc2a4457b0c25dae6fee3dcd631ccded31e97d689b892c26554e096aa08dd136"
          )
        end
      end
    end
  end
end
