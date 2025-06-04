# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cargo/file_updater/lockfile_updater"

RSpec.describe Dependabot::Cargo::FileUpdater::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: dependency_files,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }]
    )
  end

  let(:dependency_files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Cargo.toml", content: manifest_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Cargo.lock", content: lockfile_body)
  end
  let(:manifest_body) { fixture("manifests", manifest_fixture_name) }
  let(:lockfile_body) { fixture("lockfiles", lockfile_fixture_name) }
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_fixture_name) { "bare_version_specified" }

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
  let(:dependency_version) { "0.1.40" }
  let(:dependency_previous_version) { "0.1.38" }
  let(:requirements) { previous_requirements }
  let(:previous_requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_lockfile_content" do
    subject(:updated_lockfile_content) { updater.updated_lockfile_content }

    it "doesn't store the files permanently" do
      expect { updated_lockfile_content }
        .not_to(change { Dir.entries(tmp_path) })
    end

    it { expect { updated_lockfile_content }.not_to output.to_stdout }

    context "when using a toolchain file that is too old" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: "[toolchain]\nchannel = \"1.67\"\n"
        )
      end
      let(:dependency_files) { [manifest, lockfile, toolchain_file] }

      it "raises a helpful error" do
        expect { updated_lockfile_content }
          .to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "when updating the lockfile fails" do
      let(:dependency_version) { "99.0.0" }
      let(:requirements) do
        [{ file: "Cargo.toml", requirement: "99", groups: [], source: nil }]
      end

      it "raises a helpful error" do
        expect { updater.updated_lockfile_content }
          .to raise_error do |error|
            expect(error)
              .to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
            expect(error.message).to include("failed to select a version")
          end
      end

      context "when an existing requirement is not sufficient" do
        let(:dependency_version) { "0.1.38" }
        let(:requirements) do
          [{ file: "Cargo.toml", requirement: "0.3.20", groups: [], source: nil }]
        end

        let(:manifest_fixture_name) { "missing_version" }
        let(:lockfile_fixture_name) { "missing_version" }

        it "raises a helpful error" do
          expect { updater.updated_lockfile_content }
            .to raise_error do |error|
              expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
              expect(error.message)
                .to include("version for the requirement `regex = \"^99.0.0\"`")
            end
        end
      end
    end

    context "when the dependency doesn't exist" do
      random_unlikely_package_name = (0...255).map { ("a".."z").to_a[rand(26)] }.join
      content = <<~CONTENT
        [package]
        name = "foo"
        version = "0.1.0"
        authors = ["me"]

        [dependencies]
        #{random_unlikely_package_name} = "99.99.99"
      CONTENT

      let(:manifest) do
        Dependabot::DependencyFile.new(name: "Cargo.toml", content: content)
      end

      it "raises a helpful error" do
        expect { updated_lockfile_content }
          .to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
            expect(error.message).to include(random_unlikely_package_name)
          end
      end
    end

    context "when the package doesn't exist at the git source" do
      content = <<~CONTENT
        [package]
        name = "foo"
        version = "0.1.0"
        authors = ["me"]
        [dependencies]
        yewtil = { git = "https://github.com/yewstack/yew" }
      CONTENT

      let(:manifest) do
        Dependabot::DependencyFile.new(name: "Cargo.toml", content: content)
      end

      it "raises a helpful error" do
        expect { updated_lockfile_content }
          .to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
          expect(error.message).to include("yewtil")
        end
      end
    end

    describe "the updated lockfile" do
      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content)
          .to include(%(name = "time"\nversion = "0.1.40"))
        expect(updated_lockfile_content).to include(
          <<~CHECKSUM
            checksum = "d825be0eb33fda1a7e68012d51e9c7f451dc1a69391e7fdc197060bb8c56667b"
          CHECKSUM
        )
        expect(updated_lockfile_content).not_to include(
          <<~CHECKSUM
            checksum = "d5d788d3aa77bc0ef3e9621256885555368b47bd495c13dd2e7413c89f845520"
          CHECKSUM
        )
      end

      context "with a binary specified" do
        let(:manifest_fixture_name) { "binary" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "time"\nversion = "0.1.40"))
        end
      end

      context "with a default-run specified" do
        let(:manifest_fixture_name) { "default_run" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "time"\nversion = "0.1.40"))
        end
      end

      context "with a target-specific dependency" do
        let(:manifest_fixture_name) { "target_dependency" }
        let(:lockfile_fixture_name) { "target_dependency" }
        let(:dependency_previous_version) { "0.1.12" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: "<= 0.1.38",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: "<= 0.1.12",
            groups: [],
            source: nil
          }]
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "time"\nversion = "0.1.40"))
        end
      end

      context "with a blank requirement" do
        let(:manifest_fixture_name) { "blank_version" }
        let(:lockfile_fixture_name) { "blank_version" }
        let(:previous_requirements) do
          [{ file: "Cargo.toml", requirement: nil, groups: [], source: nil }]
        end

        it "raises a DependencyFileNotResolvable error" do
          expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("unexpected end of input while parsing major version")
          end
        end
      end

      context "with multiple versions available of the dependency" do
        let(:manifest_fixture_name) { "multiple_versions" }
        let(:lockfile_fixture_name) { "multiple_versions" }

        let(:dependency_name) { "rand" }
        let(:dependency_version) { "0.4.2" }
        let(:dependency_previous_version) { "0.4.1" }
        let(:requirements) { previous_requirements }
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: "0.4",
            groups: [],
            source: nil
          }]
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "rand"\nversion = "0.4.2"))
        end
      end

      context "with an old format lockfile" do
        let(:manifest_fixture_name) { "old_lockfile" }
        let(:lockfile_fixture_name) { "old_lockfile" }

        it "updates the lockfile to the new version" do
          expect(updated_lockfile_content).to include(
            <<~CHECKSUM
              checksum = "d825be0eb33fda1a7e68012d51e9c7f451dc1a69391e7fdc197060bb8c56667b"
            CHECKSUM
          )
          expect(updated_lockfile_content).not_to include("[metadata]")
        end
      end

      context "with a git dependency" do
        let(:manifest_fixture_name) { "git_dependency" }
        let(:lockfile_fixture_name) { "git_dependency" }

        let(:dependency_name) { "utf8-ranges" }
        let(:dependency_version) do
          "be9b8dfcaf449453cbf83ac85260ee80323f4f77"
        end
        let(:dependency_previous_version) do
          "83141b376b93484341c68fbca3ca110ae5cd2708"
        end
        let(:requirements) { previous_requirements }
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: nil,
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: nil
            }
          }]
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include("utf8-ranges#be9b8dfcaf449453cbf83ac85260ee80323f4f77")
        end

        context "with an ssh URl" do
          let(:manifest_fixture_name) { "git_dependency_ssh" }
          let(:lockfile_fixture_name) { "git_dependency_ssh" }
          let(:requirements) { previous_requirements }
          let(:previous_requirements) do
            [{
              file: "Cargo.toml",
              requirement: nil,
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "ssh://git@github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: nil
              }
            }]
          end

          it "updates the dependency version in the lockfile" do
            expect(updated_lockfile_content)
              .to include("git+ssh://git@github.com/BurntSushi/utf8-ranges#" \
                          "be9b8dfcaf449453cbf83ac85260ee80323f4f77")
            expect(updated_lockfile_content).not_to include("git+https://")

            content = updated_lockfile_content
            expect(content.scan('name = "utf8-ranges"').count).to eq(1)
          end
        end

        context "with an updated tag" do
          let(:manifest_fixture_name) { "git_dependency_with_tag" }
          let(:lockfile_fixture_name) { "git_dependency_with_tag" }
          let(:dependency_version) do
            "83141b376b93484341c68fbca3ca110ae5cd2708"
          end
          let(:dependency_previous_version) do
            "d5094c7e9456f2965dec20de671094a98c6929c2"
          end
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: nil,
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: "1.0.0"
              }
            }]
          end
          let(:previous_requirements) do
            [{
              file: "Cargo.toml",
              requirement: nil,
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: "0.1.3"
              }
            }]
          end

          it "updates the dependency version in the lockfile" do
            expect(updated_lockfile_content)
              .to include "?tag=1.0.0#83141b376b93484341c68fbca3ca110ae5cd2708"
          end
        end
      end

      context "when there is a path dependency" do
        let(:dependency_files) { [manifest, lockfile, path_dependency_file] }
        let(:manifest_fixture_name) { "path_dependency" }
        let(:lockfile_fixture_name) { "path_dependency" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "regex",
            version: "0.2.10",
            requirements: [{
              file: "Cargo.toml",
              requirement: "=0.2.10",
              groups: [],
              source: nil
            }],
            previous_version: "0.1.38",
            previous_requirements: [{
              file: "Cargo.toml",
              requirement: "=0.1.38",
              groups: [],
              source: nil
            }],
            package_manager: "cargo"
          )
        end
        let(:path_dependency_file) do
          Dependabot::DependencyFile.new(
            name: "src/s3/Cargo.toml",
            content: fixture("manifests", "cargo-registry-s3")
          )
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "regex"\nversion = "0.2.10"))
          expect(updated_lockfile_content).to include(
            "aec3f58d903a7d2a9dc2bf0e41a746f4530e0cab6b615494e058f67a3ef947fb"
          )
          expect(updated_lockfile_content).not_to include(
            "bc2a4457b0c25dae6fee3dcd631ccded31e97d689b892c26554e096aa08dd136"
          )
        end
      end

      context "when there is a linked dependency" do
        let(:dependency_files) { [manifest, lockfile] }
        let(:manifest_fixture_name) { "linked_dependency" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "time"\nversion = "0.1.40"))
        end
      end

      context "when there is a workspace" do
        let(:dependency_files) { [manifest, lockfile, workspace_child] }
        let(:manifest_fixture_name) { "workspace_root" }
        let(:lockfile_fixture_name) { "workspace" }
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "lib/sub_crate/Cargo.toml",
            content: fixture("manifests", "workspace_child")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "log",
            version: "0.4.1",
            requirements: [{
              requirement: "=0.4.1",
              file: "lib/sub_crate/Cargo.toml",
              groups: ["dependencies"],
              source: nil
            }],
            previous_version: "0.4.0",
            previous_requirements: [{
              requirement: "=0.4.0",
              file: "lib/sub_crate/Cargo.toml",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "cargo"
          )
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "log"\nversion = "0.4.1"))
          expect(updated_lockfile_content).to include(
            "89f010e843f2b1a31dbd316b3b8d443758bc634bed37aabade59c686d644e0a2"
          )
          expect(updated_lockfile_content).not_to include(
            "b3a89a0c46ba789b8a247d4c567aed4d7c68e624672d238b45cc3ec20dc9f940"
          )
        end
      end

      context "when there's a virtual workspace" do
        let(:manifest_fixture_name) { "virtual_workspace_root" }
        let(:lockfile_fixture_name) { "virtual_workspace" }
        let(:dependency_files) do
          [manifest, lockfile, workspace_child]
        end
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "src/sub_crate/Cargo.toml",
            content: fixture("manifests", "workspace_child")
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "log",
            version: "0.4.1",
            requirements: [{
              requirement: "=0.4.1",
              file: "src/sub_crate/Cargo.toml",
              groups: ["dependencies"],
              source: nil
            }],
            previous_version: "0.4.0",
            previous_requirements: [{
              requirement: "=0.4.0",
              file: "src/sub_crate/Cargo.toml",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "cargo"
          )
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content)
            .to include(%(name = "log"\nversion = "0.4.1"))
          expect(updated_lockfile_content).to include(
            "89f010e843f2b1a31dbd316b3b8d443758bc634bed37aabade59c686d644e0a2"
          )
          expect(updated_lockfile_content).not_to include(
            "b3a89a0c46ba789b8a247d4c567aed4d7c68e624672d238b45cc3ec20dc9f940"
          )
        end
      end
    end
  end
end
