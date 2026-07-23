# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/cargo/update_checker/file_preparer"
require "dependabot/cargo/update_checker/version_resolver"

RSpec.describe Dependabot::Cargo::UpdateChecker::VersionResolver do
  subject(:resolver) do
    described_class.new(
      dependency: dependency,
      prepared_dependency_files: dependency_files,
      original_dependency_files: unprepared_dependency_files,
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
  let(:dependency_files) do
    Dependabot::Cargo::UpdateChecker::FilePreparer.new(
      dependency_files: unprepared_dependency_files,
      dependency: dependency,
      unlock_requirement: true
    ).prepared_dependency_files
  end
  let(:unprepared_dependency_files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("manifests", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:requirements) do
    [{
      file: "Cargo.toml",
      requirement: string_req,
      groups: [],
      source: source
    }]
  end
  let(:dependency_name) { "regex" }
  let(:dependency_version) { "0.1.41" }
  let(:string_req) { "0.1.41" }
  let(:source) { nil }

  describe "latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it { is_expected.to be >= Gem::Version.new("0.2.10") }

    context "without a lockfile" do
      let(:unprepared_dependency_files) { [manifest] }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }

      context "with a template manifest file" do
        let(:manifest_fixture_name) { "template_name" }

        it { is_expected.to be >= Gem::Version.new("0.2.10") }
      end
    end

    context "with a missing dependency" do
      let(:manifest_fixture_name) { "bare_version_specified" }
      let(:lockfile_fixture_name) { "missing_dependency" }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with a binary specified" do
      let(:manifest_fixture_name) { "binary" }
      let(:lockfile_fixture_name) { "bare_version_specified" }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with a default-run specified" do
      let(:manifest_fixture_name) { "default_run" }
      let(:lockfile_fixture_name) { "bare_version_specified" }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with a target-specific dependency" do
      let(:manifest_fixture_name) { "target_dependency" }
      let(:lockfile_fixture_name) { "target_dependency" }
      let(:dependency_name) { "time" }
      let(:dependency_version) { "0.1.12" }
      let(:string_req) { "<=0.1.12" }

      it { is_expected.to be >= Gem::Version.new("0.1.41") }
    end

    context "with a linked dependency" do
      let(:manifest_fixture_name) { "linked_dependency" }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "with a missing version (for another dependency)" do
      let(:manifest_fixture_name) { "missing_version" }
      let(:lockfile_fixture_name) { "missing_version" }

      let(:dependency_name) { "time" }
      let(:dependency_version) { "0.1.38" }
      let(:string_req) { "0.1.12" }

      it "raises a helpful error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
            expect(error.message)
              .to include("version for the requirement `regex = \"^99.0.0\"`")
          end
      end

      context "without a lockfile" do
        let(:unprepared_dependency_files) { [manifest] }

        it "raises a helpful error" do
          expect { resolver.latest_resolvable_version }
            .to raise_error do |error|
              expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
              expect(error.message)
                .to include("version for the requirement `regex = \"^99.0.0\"`")
            end
        end
      end
    end

    context "with a missing rust-toolchain file" do
      let(:manifest_fixture_name) { "requires_nightly" }
      let(:lockfile_fixture_name) { "bare_version_specified" }

      it "raises a DependencyFileNotResolvable error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            # Test that the temporary path isn't included in the error message
            expect(error.message).not_to include("dependabot_20")
            expect(error.message).to include("requires a nightly version")
          end
      end
    end

    context "when using a toolchain that is too old" do
      let(:toolchain_file) do
        Dependabot::DependencyFile.new(
          name: "rust-toolchain",
          content: "[toolchain]\nchannel = \"1.67\"\n"
        )
      end
      let(:unprepared_dependency_files) { [manifest, lockfile, toolchain_file] }

      it "raises a helpful error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "when using a feature that is not enabled" do
      let(:manifest_fixture_name) { "disabled_feature" }
      let(:lockfile_fixture_name) { "bare_version_specified" }

      it "raises a DependencyFileNotResolvable error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            # Test that the temporary path isn't included in the error message
            expect(error.message).not_to include("dependabot_20")
            expect(error.message)
              .to include("feature `metabuild` is required")
          end
      end
    end

    context "when using a feature that doesn't exist on the dependency" do
      it "doesn't raise an error for singular feature mismatch" do
        error_message = "package `hashbrown` does not have that feature.\n" \
                        " package `hashbrown` does have feature `rayon`"
        error = Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: error_message,
          error_context: {}
        )

        expect { resolver.send(:handle_cargo_errors, error) }.not_to raise_error
      end

      it "doesn't raise an error for plural feature mismatch" do
        error_message = "package `example` does not have these features"
        error = Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: error_message,
          error_context: {}
        )

        expect { resolver.send(:handle_cargo_errors, error) }.not_to raise_error
      end
    end

    context "with a dependency that doesn't exist" do
      let(:unprepared_dependency_files) { [manifest] }
      let(:manifest_fixture_name) { "non_existent_package" }

      let(:dependency_name) { "no_exist_bad_time" }
      let(:dependency_version) { nil }
      let(:string_req) { "0.1.12" }

      it "raises a DependencyFileNotResolvable error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            # Test that the temporary path isn't included in the error message
            expect(error.message).not_to include("dependabot_20")
            expect(error.message)
              .to include("no matching package named `no_exist_bad_time` found")
          end
      end

      context "when it isn't the package being updated" do
        let(:dependency_name) { "regex" }
        let(:string_req) { "0.1.41" }

        it "raises a DependencyFileNotResolvable error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).not_to include("dependabot_20")
              expect(error.message)
                .to include("no matching package named `no_exist_bad_time`")
            end
        end
      end

      context "with some TOML that Cargo can't parse" do
        let(:manifest_fixture_name) { "bad_name" }
        let(:lockfile_fixture_name) { "bad_name" }

        it "raises a DependencyFileNotResolvable error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).not_to include("dependabot_20")
              expect(error.message.downcase)
                .to include("invalid character `;` in package name")
            end
        end
      end
    end

    context "with a blank requirement string" do
      let(:manifest_fixture_name) { "blank_version" }
      let(:lockfile_fixture_name) { "blank_version" }
      let(:string_req) { nil }

      it "raises a DependencyFileNotResolvable error" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).to include("unexpected end of input while parsing major version")
        end
      end
    end

    context "with an optional dependency" do
      let(:manifest_fixture_name) { "optional_dependency" }
      let(:lockfile_fixture_name) { "optional_dependency" }
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "0.1.3" }
      let(:string_req) { "0.1.3" }

      it { is_expected.to eq(Gem::Version.new("1.0.5")) }
    end

    context "with a git dependency" do
      let(:manifest_fixture_name) { "git_dependency" }
      let(:lockfile_fixture_name) { "git_dependency" }
      let(:dependency_name) { "utf8-ranges" }
      let(:dependency_version) { "83141b376b93484341c68fbca3ca110ae5cd2708" }
      let(:string_req) { nil }
      let(:source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: nil,
          ref: nil
        }
      end

      it { is_expected.to eq("be9b8dfcaf449453cbf83ac85260ee80323f4f77") }

      context "with a tag" do
        let(:manifest_fixture_name) { "git_dependency_with_tag" }
        let(:lockfile_fixture_name) { "git_dependency_with_tag" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: nil,
            ref: "0.1.3"
          }
        end

        it { is_expected.to eq(dependency_version) }
      end

      context "when it is unreachable" do
        let(:manifest_fixture_name) { "git_dependency_unreachable" }
        let(:lockfile_fixture_name) { "git_dependency_unreachable" }
        let(:git_url) do
          "https://github.com/greysteil/utf8-ranges.git/info/" \
            "refs?service=git-upload-pack"
        end
        let(:auth_header) { "Basic eC1hY2Nlc3MtdG9rZW46dG9rZW4=" }

        before do
          stub_request(:get, git_url)
            .with(headers: { "Authorization" => auth_header })
            .to_return(status: 403)
        end

        it "raises a GitDependenciesNotReachable error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
              expect(error.dependency_urls)
                .to eq(["https://github.com/greysteil/utf8-ranges"])
            end
        end

        context "when skipped by the parser due to multiple URLs)" do
          let(:unprepared_dependency_files) do
            [manifest, workspace_child, workspace_child2]
          end
          let(:manifest_fixture_name) { "workspace_root_multiple" }
          let(:workspace_child) do
            Dependabot::DependencyFile.new(
              name: "lib/sub_crate/Cargo.toml",
              content: fixture("manifests", "workspace_child_with_git")
            )
          end
          let(:workspace_child2) do
            Dependabot::DependencyFile.new(
              name: "lib/sub_crate2/Cargo.toml",
              content:
                fixture("manifests", "workspace_child_with_git_unreachable")
            )
          end

          it "raises a GitDependenciesNotReachable error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
                expect(error.dependency_urls)
                  .to eq(["https://github.com/greysteil/utf8-ranges"])
              end
          end
        end
      end

      context "with an unfetchable locked ref for an unrelated git dep" do
        let(:manifest_fixture_name) { "git_dependency" }
        let(:lockfile_fixture_name) { "git_dependency_unfetchable_ref" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: string_req,
            groups: [],
            source: source
          }]
        end
        let(:dependency_name) { "time" }
        let(:dependency_version) { "0.1.39" }
        let(:string_req) { "0.1.12" }
        let(:source) { nil }

        it "raises a GitDependencyReferenceNotFound error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency)
                .to eq("https://github.com/BurntSushi/utf8-ranges")
            end
        end
      end

      context "with an unreachable branch" do
        let(:manifest_fixture_name) { "git_dependency_with_unreachable_branch" }
        let(:lockfile_fixture_name) { "git_dependency_with_unreachable_branch" }
        let(:dependency_version) { "d5094c7e9456f2965dec20de671094a98c6929c2" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: "no_exist",
            ref: nil
          }
        end

        it "raises a GitDependencyReferenceNotFound error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency)
                .to eq("https://github.com/BurntSushi/utf8-ranges")
            end
        end
      end
    end

    context "with a feature dependency, when the feature has been removed" do
      let(:manifest_fixture_name) { "feature_removed" }
      let(:lockfile_fixture_name) { "feature_removed" }
      let(:dependency_name) { "syntect" }
      let(:dependency_version) { "1.8.1" }
      let(:string_req) { "1.8" }

      it { is_expected.to eq(Gem::Version.new("1.8.1")) }
    end

    context "with multiple versions available of the dependency" do
      let(:manifest_fixture_name) { "multiple_versions" }
      let(:lockfile_fixture_name) { "multiple_versions" }
      let(:dependency_name) { "rand" }
      let(:dependency_version) { "0.4.1" }
      let(:string_req) { "0.4" }

      it { is_expected.to be >= Gem::Version.new("0.5.1") }

      context "when the dependency isn't top-level" do
        let(:manifest_fixture_name) { "multiple_versions_subdependency" }
        let(:lockfile_fixture_name) { "multiple_versions_subdependency" }
        let(:dependency_name) { "hyper" }
        let(:dependency_version) { "0.10.13" }
        let(:requirements) { [] }

        it { is_expected.to eq(Gem::Version.new("0.10.16")) }
      end
    end

    context "when there's a virtual workspace" do
      let(:manifest_fixture_name) { "virtual_workspace_root" }
      let(:lockfile_fixture_name) { "virtual_workspace" }
      let(:unprepared_dependency_files) do
        [manifest, lockfile, workspace_child]
      end
      let(:workspace_child) do
        Dependabot::DependencyFile.new(
          name: "src/sub_crate/Cargo.toml",
          content: fixture("manifests", "workspace_child")
        )
      end

      let(:dependency_name) { "log" }
      let(:dependency_version) { "0.4.0" }
      let(:string_req) { "2.0" }
      let(:requirements) do
        [{
          requirement: "=0.4.0",
          file: "src/sub_crate/Cargo.toml",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("0.4.4") }
    end

    context "when there is a workspace" do
      let(:unprepared_dependency_files) do
        [manifest, lockfile, workspace_child]
      end
      let(:manifest_fixture_name) { "workspace_root" }
      let(:lockfile_fixture_name) { "workspace" }
      let(:workspace_child) do
        Dependabot::DependencyFile.new(
          name: "lib/sub_crate/Cargo.toml",
          content: fixture("manifests", "workspace_child")
        )
      end
      let(:dependency_name) { "log" }
      let(:dependency_version) { "0.4.0" }
      let(:string_req) { "2.0" }
      let(:requirements) do
        [{
          requirement: "=0.4.0",
          file: "lib/sub_crate/Cargo.toml",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("0.4.4") }

      context "when Dependabot has been asked to run on only a child" do
        let(:unprepared_dependency_files) { [manifest, workspace_child] }
        let(:manifest) do
          Dependabot::DependencyFile.new(
            name: "../../Cargo.toml",
            directory: "lib/sub_crate/",
            content: fixture("manifests", "workspace_root")
          )
        end
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            directory: "lib/sub_crate/",
            content: fixture("manifests", "workspace_child")
          )
        end
        let(:requirements) do
          [{
            requirement: "=0.4.0",
            file: "Cargo.toml",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "raises a DependencyFileNotResolvable error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the right details are included
              expect(error.message).to include("part of a Rust workspace")
            end
        end
      end

      context "when it is not correctly set up" do
        let(:unprepared_dependency_files) do
          [manifest, workspace_child]
        end
        let(:manifest_fixture_name) { "workspace_root" }
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "Cargo.toml",
            content: fixture("manifests", "workspace_child"),
            directory: "/lib/sub_crate"
          )
        end
        let(:manifest) do
          Dependabot::DependencyFile.new(
            name: "../../Cargo.toml",
            content: fixture("manifests", "default_run"),
            directory: "/lib/sub_crate"
          )
        end

        it "raises a DependencyFileNotResolvable error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).not_to include("dependabot_20")

              # Test that the right details are included
              expect(error.message).to include("wasn't a root")
            end
        end
      end
    end

    context "when not unlocking" do
      let(:dependency_files) { unprepared_dependency_files }

      it { is_expected.to eq(Gem::Version.new("0.1.80")) }
    end

    context "when multiple packages have a version conflict with one another" do
      let(:dependency_name) { "ructe" }
      let(:dependency_version) { "0b8acfe5eea15713bc56c156f974fa05967d0353" }
      let(:string_req) { nil }
      let(:source) { { type: "git", url: "https://github.com/kaj/ructe" } }
      let(:dependency_files) { project_dependency_files("version_conflict") }
      let(:unprepared_dependency_files) { project_dependency_files("version_conflict") }

      specify { expect(latest_resolvable_version).to be_nil }
    end

    context "with an optional dependency" do
      let(:manifest_fixture_name) { "bare_version_specified_as_optional" }
      let(:unprepared_dependency_files) { [manifest] }

      it { is_expected.to be >= Gem::Version.new("0.2.10") }
    end

    context "when attempting to resolve a subdependency of a path dependency" do
      let(:path_dependency_manifest) do
        Dependabot::DependencyFile.new(
          name: "src/s3/Cargo.toml",
          content: fixture("manifests", path_dependency_manifest_fixture_name)
        )
      end

      let(:manifest_fixture_name) { "path_dependency" }
      let(:path_dependency_manifest_fixture_name) { "cargo-registry-s3" }

      let(:unprepared_dependency_files) { [manifest, path_dependency_manifest] }

      let(:dependency_name) { "openssl" }
      let(:dependency_version) { "0.10" }
      let(:string_req) { "0.10" }

      it { is_expected.to be >= Gem::Version.new("0.10.41") }

      context "when the subdependency is optional" do
        let(:path_dependency_manifest_fixture_name) { "cargo-registry-s3-ssl-optional" }

        it { is_expected.to be_nil }
      end

      context "when the subdependency is optional but enabled by the parent" do
        let(:manifest_fixture_name) { "path_dependency_feature_enabled" }
        let(:path_dependency_manifest_fixture_name) { "cargo-registry-s3-ssl-optional" }

        it { is_expected.to be >= Gem::Version.new("0.10.41") }
      end
    end

    describe "#resolvability_error?" do
      context "with binary path errors" do
        it "detects couldn't find binary file error" do
          message = "couldn't find `src/chargebee_codegen.rs`. " \
                    "Please specify bin.path if you want to use a non-default path."
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects failed to find binary file error" do
          message = "failed to find `src/chargebee_codegen.rs` in package `my-package`"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects could not find binary file error" do
          message = "could not find `src/main.rs` for binary `my-binary`"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects cannot find binary error" do
          message = "cannot find binary `my_binary` in package `my_package`"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects binary target not found error" do
          message = "binary target `my_target` not found in manifest"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects bin.path hint message" do
          message = "error: cannot find binary file. Please specify bin.path if you want to use a non-default path."
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end
      end

      context "with existing error patterns" do
        it "detects failed to parse lock error" do
          message = "failed to parse lock file"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects workspace error" do
          message = "believes it's in a workspace"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end

        it "detects feature requirement error" do
          message = "feature `metabuild` is required"
          expect(resolver.send(:resolvability_error?, message)).to be(true)
        end
      end

      context "with non-resolvability errors" do
        context "with non-resolvability errors" do
          it "does not detect unrelated errors when original requirements are resolvable" do
            # Create a new resolver instance to avoid stubbing the subject
            non_error_resolver = described_class.new(
              dependency: dependency,
              prepared_dependency_files: dependency_files,
              original_dependency_files: unprepared_dependency_files,
              credentials: credentials
            )

            # Mock the original_requirements_resolvable? on the new instance
            allow(non_error_resolver).to receive(:original_requirements_resolvable?).and_return(true)

            message = "some other random error message"
            expect(non_error_resolver.send(:resolvability_error?, message)).to be(false)
          end
        end
      end
    end
  end

  describe "#write_manifest_files" do
    let(:manifest_fixture_name) { "bare_version_specified" }
    let(:lockfile_fixture_name) { "bare_version_specified" }
    let!(:manifest_content) { fixture("manifests", "bare_version_specified") }
    let!(:lockfile_content) { fixture("lockfiles", "bare_version_specified") }

    context "when file names have absolute paths" do
      let(:absolute_path_manifest) do
        Dependabot::DependencyFile.new(
          name: "/Cargo.toml", # Absolute path that would cause permission error
          content: manifest_content
        )
      end
      let(:absolute_path_lockfile) do
        Dependabot::DependencyFile.new(
          name: "/Cargo.lock",
          content: lockfile_content
        )
      end
      let(:unprepared_dependency_files) { [absolute_path_manifest, absolute_path_lockfile] }

      it "converts absolute paths to relative paths to avoid permission errors" do
        # Create a temporary directory to test file writing
        Dir.mktmpdir do |temp_dir|
          Dir.chdir(temp_dir) do
            # This should not raise a permission error
            expect { resolver.send(:write_manifest_files, prepared: false) }.not_to raise_error

            # Verify that the files were written with relative paths
            expect(File.exist?("Cargo.toml")).to be(true)
            expect(File.read("Cargo.toml")).to include("[package]")
          end
        end
      end
    end

    context "when file names have relative paths" do
      let(:relative_path_manifest) do
        Dependabot::DependencyFile.new(
          name: "subdir/Cargo.toml",
          content: manifest_content
        )
      end
      let(:relative_path_lockfile) do
        Dependabot::DependencyFile.new(
          name: "subdir/Cargo.lock",
          content: lockfile_content
        )
      end
      let(:unprepared_dependency_files) { [relative_path_manifest, relative_path_lockfile] }

      it "preserves relative paths and creates necessary directories" do
        Dir.mktmpdir do |temp_dir|
          Dir.chdir(temp_dir) do
            expect { resolver.send(:write_manifest_files, prepared: false) }.not_to raise_error

            # Verify that the subdirectory was created and files were written
            expect(File.exist?("subdir/Cargo.toml")).to be(true)
            expect(File.read("subdir/Cargo.toml")).to include("[package]")
            expect(Dir.exist?("subdir/src")).to be(true)
            expect(File.exist?("subdir/src/lib.rs")).to be(true)
          end
        end
      end
    end

    context "when file names are just filenames without paths" do
      let(:simple_manifest) do
        Dependabot::DependencyFile.new(
          name: "Cargo.toml",
          content: manifest_content
        )
      end
      let(:simple_lockfile) do
        Dependabot::DependencyFile.new(
          name: "Cargo.lock",
          content: lockfile_content
        )
      end
      let(:unprepared_dependency_files) { [simple_manifest, simple_lockfile] }

      it "writes files in the current directory" do
        Dir.mktmpdir do |temp_dir|
          Dir.chdir(temp_dir) do
            expect { resolver.send(:write_manifest_files, prepared: false) }.not_to raise_error

            expect(File.exist?("Cargo.toml")).to be(true)
            expect(File.read("Cargo.toml")).to include("[package]")
            expect(Dir.exist?("src")).to be(true)
            expect(File.exist?("src/lib.rs")).to be(true)
          end
        end
      end
    end
  end
end
