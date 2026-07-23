# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_updater/lockfile_updater"

RSpec.describe Dependabot::Bazel::FileUpdater::LockfileUpdater do
  let(:lockfile_updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:dependency_name) { "rules_cc" }
  let(:old_version) { "0.1.1" }
  let(:new_version) { "0.2.0" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: new_version,
      previous_version: old_version,
      requirements: [{
        file: "MODULE.bazel",
        requirement: new_version,
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "MODULE.bazel",
        requirement: old_version,
        groups: [],
        source: nil
      }],
      package_manager: "bazel"
    )
  end

  let(:dependencies) { [dependency] }

  describe "#updated_lockfile" do
    context "with a bzlmod project that has existing lockfile" do
      let(:dependency_files) { bazel_project_dependency_files("simple_module_with_lockfile") }

      it "returns an updated lockfile" do
        # Mock the Bazel command execution since we can't run it in tests
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_return(
          updated_lockfile_content
        )

        updated_lockfile = lockfile_updater.updated_lockfile
        expect(updated_lockfile).not_to be_nil
        expect(updated_lockfile.name).to eq("MODULE.bazel.lock")
        expect(updated_lockfile.content).to include("rules_cc@0.2.0")
      end

      it "returns nil when lockfile content doesn't change" do
        original_lockfile = dependency_files.find { |f| f.name == "MODULE.bazel.lock" }
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_return(
          original_lockfile.content
        )

        updated_lockfile = lockfile_updater.updated_lockfile
        expect(updated_lockfile).to be_nil
      end
    end

    context "with a bzlmod project that needs a new lockfile" do
      let(:dependency_files) { bazel_project_dependency_files("module_needs_lockfile") }

      it "generates a new lockfile" do
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_return(
          new_lockfile_content
        )

        updated_lockfile = lockfile_updater.updated_lockfile
        expect(updated_lockfile).not_to be_nil
        expect(updated_lockfile.name).to eq("MODULE.bazel.lock")
        expect(updated_lockfile.content).to include("rules_cc@0.2.0")
      end
    end

    context "with a WORKSPACE-based project" do
      let(:dependency_files) { bazel_project_dependency_files("simple_workspace") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: new_version,
          previous_version: old_version,
          requirements: [{
            file: "WORKSPACE",
            requirement: new_version,
            groups: [],
            source: nil
          }],
          package_manager: "bazel"
        )
      end

      it "returns nil for workspace dependencies (no lockfile update needed)" do
        updated_lockfile = lockfile_updater.updated_lockfile
        expect(updated_lockfile).to be_nil
      end
    end

    context "when Bazel command fails" do
      let(:dependency_files) { bazel_project_dependency_files("simple_module_with_lockfile") }

      it "handles Bazel not found error" do
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "bazel: command not found",
            error_context: {}
          )
        )

        expect { lockfile_updater.updated_lockfile }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /Bazel binary not available/)
      end

      it "handles network errors gracefully" do
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "network timeout error",
            error_context: {}
          )
        )

        expect { lockfile_updater.updated_lockfile }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /Network error/)
      end

      it "raises error for other errors" do
        allow(lockfile_updater).to receive(:generate_lockfile_content).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "some other error",
            error_context: {}
          )
        )

        expect { lockfile_updater.updated_lockfile }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /Error generating lockfile/)
      end
    end
  end

  describe "#determine_bazel_version" do
    context "when .bazelversion file exists with valid content" do
      let(:dependency_files) { bazel_project_dependency_files("with_bazelversion") }

      it "returns the version from .bazelversion file" do
        expect(lockfile_updater.determine_bazel_version).to eq("6.4.0")
      end
    end

    context "when .bazelversion file does not exist" do
      let(:dependency_files) { bazel_project_dependency_files("simple_module_with_lockfile") }

      it "returns DEFAULT_BAZEL_VERSION" do
        expect(lockfile_updater.determine_bazel_version)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end

    context "when .bazelversion file exists but is empty" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "",
          directory: "/"
        )
        files
      end

      it "returns DEFAULT_BAZEL_VERSION" do
        expect(lockfile_updater.determine_bazel_version)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end

    context "when .bazelversion file exists with whitespace only" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "  \n  ",
          directory: "/"
        )
        files
      end

      it "returns DEFAULT_BAZEL_VERSION" do
        expect(lockfile_updater.determine_bazel_version)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end

    context "when .bazelversion file exists with a BuildBuddy multi-line wrapper" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "buildbuddy-io/5.0.321\n9.1.0\n",
          directory: "/"
        )
        files
      end

      it "returns the actual Bazel version ignoring the BuildBuddy wrapper line" do
        expect(lockfile_updater.determine_bazel_version).to eq("9.1.0")
      end
    end

    context "when .bazelversion contains only a BuildBuddy wrapper entry" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "buildbuddy-io/5.0.321\n",
          directory: "/"
        )
        files
      end

      it "falls back to DEFAULT_BAZEL_VERSION rather than the wrapper's version" do
        expect(lockfile_updater.determine_bazel_version)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end

    context "when only a nested .bazelversion exists (e.g. from a local_path_override module)" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: "third_party/mod/.bazelversion",
          content: "5.3.0\n",
          directory: "/"
        )
        files
      end

      it "ignores the nested module's pin and falls back to DEFAULT_BAZEL_VERSION" do
        expect(lockfile_updater.determine_bazel_version)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end
  end

  describe "the temporary .bazelversion written for Bazelisk" do
    def bazelversion_written_for_bazel
      content = nil
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
        content = File.read(".bazelversion").strip
      end

      lockfile_updater.updated_lockfile
      content
    end

    context "with a BuildBuddy multi-line wrapper .bazelversion" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "buildbuddy-io/5.0.321\n9.1.0\n",
          directory: "/"
        )
        files
      end

      it "strips the wrapper line so Bazelisk runs Bazel directly" do
        expect(bazelversion_written_for_bazel).to eq("9.1.0")
      end
    end

    context "with a Bazelisk fork target .bazelversion" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "myorg/8.0.0\n",
          directory: "/"
        )
        files
      end

      it "preserves the fork target so Bazelisk fetches the fork, not upstream Bazel" do
        expect(bazelversion_written_for_bazel).to eq("myorg/8.0.0")
      end
    end

    context "with a wrapper-only .bazelversion" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: ".bazelversion",
          content: "buildbuddy-io/5.0.321\n",
          directory: "/"
        )
        files
      end

      it "writes the default Bazel version" do
        expect(bazelversion_written_for_bazel)
          .to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
      end
    end

    context "with only a nested .bazelversion from a local_path_override module" do
      let(:dependency_files) do
        files = bazel_project_dependency_files("simple_module_with_lockfile")
        files << Dependabot::DependencyFile.new(
          name: "third_party/mod/.bazelversion",
          content: "5.3.0\n",
          directory: "/"
        )
        files
      end

      it "writes the default root .bazelversion and keeps the nested module's own pin" do
        root_content = nil
        nested_content = nil
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do
          root_content = File.read(".bazelversion").strip
          nested_content = File.read("third_party/mod/.bazelversion").strip
        end

        lockfile_updater.updated_lockfile

        expect(root_content).to eq(Dependabot::Bazel::DEFAULT_BAZEL_VERSION)
        expect(nested_content).to eq("5.3.0")
      end
    end
  end

  def updated_lockfile_content
    content = original_lockfile_content.dup
    content.gsub!(/"rules_cc@0\.1\.1"/, '"rules_cc@0.2.0"')
    content.gsub!("rules_cc/0.1.1/MODULE.bazel", "rules_cc/0.2.0/MODULE.bazel")
    content
  end

  def new_lockfile_content
    <<~JSON
      {
        "lockFileVersion": 11,
        "registryFileHashes": {},
        "selectedYankedVersions": {},
        "moduleExtensions": {},
        "moduleDepGraph": {
          "<root>": {
            "name": "test-module",
            "version": "1.0",
            "repoName": "",
            "deps": {
              "rules_cc": "rules_cc@0.2.0",
              "platforms": "platforms@0.0.11"
            }
          },
          "rules_cc@0.2.0": {
            "name": "rules_cc",
            "version": "0.2.0",
            "repoName": "rules_cc",
            "deps": {}
          },
          "platforms@0.0.11": {
            "name": "platforms",
            "version": "0.0.11",
            "repoName": "platforms",
            "deps": {}
          }
        }
      }
    JSON
  end

  def original_lockfile_content
    dependency_files.find { |f| f.name == "MODULE.bazel.lock" }.content
  end
end
