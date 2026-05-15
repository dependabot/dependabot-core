# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bazel/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Bazel::FileUpdater do
  subject(:file_updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
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

  let(:dependency_files) { [module_file] }
  let(:dependencies) { [dependency] }

  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "MODULE.bazel",
      content: module_file_content
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: new_version,
      previous_version: old_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "bazel"
    )
  end

  let(:dependency_name) { "rules_cc" }
  let(:old_version) { "0.1.1" }
  let(:new_version) { "0.2.0" }
  let(:requirements) do
    [{
      file: "MODULE.bazel",
      requirement: new_version,
      groups: [],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "MODULE.bazel",
      requirement: old_version,
      groups: [],
      source: nil
    }]
  end

  let(:module_file_content) do
    <<~CONTENT
      module(name = "my-module", version = "1.0")

      bazel_dep(name = "rules_cc", version = "0.1.1")
      bazel_dep(name = "platforms", version = "0.0.11")
    CONTENT
  end

  it_behaves_like "a dependency file updater"

  describe ".updated_files_regex" do
    it "returns regex patterns for Bazel files including lockfiles" do
      expect(described_class.updated_files_regex).to contain_exactly(
        /^MODULE\.bazel$/,
        %r{^(?:.*/)?[^/]+\.MODULE\.bazel$},
        /^MODULE\.bazel\.lock$/,
        %r{^(?:.*/)?MODULE\.bazel\.lock$},
        /^WORKSPACE$/,
        %r{^(?:.*/)?WORKSPACE\.bazel$},
        %r{^(?:.*/)?BUILD$},
        %r{^(?:.*/)?BUILD\.bazel$}
      )
    end
  end

  describe "#updated_dependency_files" do
    context "with a simple MODULE.bazel file" do
      it "updates the dependency version" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("MODULE.bazel")
        expect(updated_files.first.content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')
        expect(updated_files.first.content).to include('bazel_dep(name = "platforms", version = "0.0.11")')
      end
    end

    context "with multi-line bazel_dep formatting" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(
              name = "rules_cc",
              version = "0.1.1"
          )
          bazel_dep(name = "platforms", version = "0.0.11")
        CONTENT
      end

      it "preserves formatting while updating version" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include(<<~EXPECTED.strip)
          bazel_dep(
              name = "rules_cc",
              version = "0.2.0"
          )
        EXPECTED
      end
    end

    context "with version parameter before name parameter" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(version = "0.1.1", name = "rules_cc")
          bazel_dep(name = "platforms", version = "0.0.11")
        CONTENT
      end

      it "updates the dependency version" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include('bazel_dep(version = "0.2.0", name = "rules_cc")')
      end
    end

    context "with additional parameters" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(
              name = "rules_cc",
              version = "0.1.1",
              dev_dependency = True
          )
        CONTENT
      end

      it "preserves additional parameters" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include('version = "0.2.0"')
        expect(updated_content).to include("dev_dependency = True")
      end
    end

    context "with mixed parameter orders" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(
              dev_dependency = False,
              version = "0.1.1",
              name = "rules_cc"
          )
        CONTENT
      end

      it "updates version while preserving parameter order" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include('version = "0.2.0"')
        expect(updated_content).to include("dev_dependency = False")
        lines = updated_content.lines
        dev_line_index = lines.find_index { |line| line.include?("dev_dependency") }
        version_line_index = lines.find_index { |line| line.include?('version = "0.2.0"') }
        name_line_index = lines.find_index { |line| line.include?('name = "rules_cc"') }

        expect(dev_line_index).to be < version_line_index
        expect(version_line_index).to be < name_line_index
      end
    end

    context "with comments" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          # Core dependencies
          bazel_dep(name = "rules_cc", version = "0.1.1")  # C++ rules
          # Platform definitions
          bazel_dep(name = "platforms", version = "0.0.11")
        CONTENT
      end

      it "preserves comments" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include("# Core dependencies")
        expect(updated_content).to include("# C++ rules")
        expect(updated_content).to include("# Platform definitions")
        expect(updated_content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')
      end
    end

    context "with single quotes" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = 'my-module', version = '1.0')

          bazel_dep(name = 'rules_cc', version = '0.1.1')
        CONTENT
      end

      it "updates version and converts to double quotes" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include('bazel_dep(name = \'rules_cc\', version = "0.2.0")')
      end
    end

    context "with multiple dependencies with same name pattern" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(name = "rules_cc", version = "0.1.1")
          bazel_dep(name = "rules_cc_extra", version = "1.0.0")
        CONTENT
      end

      it "only updates the exact dependency name" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')
        expect(updated_content).to include('bazel_dep(name = "rules_cc_extra", version = "1.0.0")')
      end
    end

    context "when dependency is not found" do
      let(:dependency_name) { "nonexistent_dep" }
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(name = "rules_cc", version = "0.1.1")
        CONTENT
      end

      it "returns no updated files" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(0)
      end
    end

    context "with no changes needed" do
      let(:new_version) { "0.1.1" } # Same as old version

      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(name = "rules_cc", version = "0.1.1")
        CONTENT
      end

      it "returns no updated files" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(0)
      end
    end

    context "with repo_name parameter" do
      let(:module_file_content) do
        <<~CONTENT
          module(name = "my-module", version = "1.0")

          bazel_dep(
              name = "rules_cc",
              version = "0.1.1",
              repo_name = "my_rules_cc"
          )
        CONTENT
      end

      it "preserves repo_name while updating version" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(1)
        updated_content = updated_files.first.content
        expect(updated_content).to include('version = "0.2.0"')
        expect(updated_content).to include('repo_name = "my_rules_cc"')
      end
    end

    context "with WORKSPACE file dependencies" do
      let(:dependency_files) { [workspace_file] }

      let(:workspace_file) do
        Dependabot::DependencyFile.new(
          name: "WORKSPACE",
          content: workspace_file_content
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: new_version,
          previous_version: old_version,
          requirements: workspace_requirements,
          previous_requirements: previous_workspace_requirements,
          package_manager: "bazel"
        )
      end

      let(:workspace_requirements) do
        [{
          file: "WORKSPACE",
          requirement: new_version,
          groups: [],
          source: { type: "git_repository", tag: new_version }
        }]
      end

      let(:previous_workspace_requirements) do
        [{
          file: "WORKSPACE",
          requirement: old_version,
          groups: [],
          source: { type: "git_repository", tag: old_version }
        }]
      end

      context "with git_repository dependency" do
        let(:dependency_name) { "rules_go" }
        let(:old_version) { "v0.39.0" }
        let(:new_version) { "v0.39.1" }

        let(:workspace_file_content) do
          <<~CONTENT
            git_repository(
                name = "rules_go",
                remote = "https://github.com/bazelbuild/rules_go.git",
                tag = "v0.39.0"
            )
          CONTENT
        end

        it "updates the git tag" do
          updated_files = file_updater.updated_dependency_files

          expect(updated_files.count).to eq(1)
          expect(updated_files.first.name).to eq("WORKSPACE")
          expect(updated_files.first.content).to include('tag = "v0.39.1"')
          expect(updated_files.first.content).to include('name = "rules_go"')
          expect(updated_files.first.content).to include('remote = "https://github.com/bazelbuild/rules_go.git"')
        end
      end

      context "with http_archive dependency" do
        let(:dependency_name) { "rules_cc" }
        let(:old_version) { "0.1.1" }
        let(:new_version) { "0.2.0" }

        let(:workspace_requirements) do
          [{
            file: "WORKSPACE",
            requirement: new_version,
            groups: [],
            source: { type: "http_archive", url: "https://example.com/rules_cc-0.2.0.tar.gz" }
          }]
        end

        let(:workspace_file_content) do
          <<~CONTENT
            http_archive(
                name = "rules_cc",
                url = "https://example.com/rules_cc-0.1.1.tar.gz",
                sha256 = "abc123"
            )
          CONTENT
        end

        it "updates the URL" do
          updated_files = file_updater.updated_dependency_files

          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include('url = "https://example.com/rules_cc-0.2.0.tar.gz"')
          expect(updated_files.first.content).to include('name = "rules_cc"')
          expect(updated_files.first.content).to include('sha256 = "abc123"')
        end
      end
    end

    context "with mixed MODULE.bazel and WORKSPACE files" do
      let(:dependency_files) { [module_file, workspace_file] }
      let(:dependencies) { [module_dependency, workspace_dependency] }

      let(:workspace_file) do
        Dependabot::DependencyFile.new(
          name: "WORKSPACE",
          content: <<~CONTENT
            git_repository(
                name = "rules_go",
                remote = "https://github.com/bazelbuild/rules_go.git",
                tag = "v0.39.0"
            )
          CONTENT
        )
      end

      let(:module_dependency) do
        Dependabot::Dependency.new(
          name: "rules_cc",
          version: "0.2.0",
          previous_version: "0.1.1",
          requirements: requirements,
          previous_requirements: previous_requirements,
          package_manager: "bazel"
        )
      end

      let(:workspace_dependency) do
        Dependabot::Dependency.new(
          name: "rules_go",
          version: "v0.39.1",
          previous_version: "v0.39.0",
          requirements: [{
            file: "WORKSPACE",
            requirement: "v0.39.1",
            groups: [],
            source: { type: "git_repository", tag: "v0.39.1" }
          }],
          previous_requirements: [{
            file: "WORKSPACE",
            requirement: "v0.39.0",
            groups: [],
            source: { type: "git_repository", tag: "v0.39.0" }
          }],
          package_manager: "bazel"
        )
      end

      it "updates both file types" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(2)

        module_file = updated_files.find { |f| f.name == "MODULE.bazel" }
        expect(module_file.content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')

        workspace_file = updated_files.find { |f| f.name == "WORKSPACE" }
        expect(workspace_file.content).to include('tag = "v0.39.1"')
      end
    end

    context "when no updates are needed" do
      let(:new_version) { "0.1.1" }

      it "returns no updated files" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(0)
      end
    end

    context "with non-bazel dependencies" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: new_version,
          previous_version: old_version,
          requirements: requirements,
          previous_requirements: previous_requirements,
          package_manager: "npm"
        )
      end

      it "ignores non-bazel dependencies" do
        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(0)
      end
    end
  end

  describe "lockfile generation and updating" do
    context "with a MODULE.bazel project with existing lockfile" do
      let(:dependency_files) { bazel_project_dependency_files("simple_module_with_lockfile") }

      it "updates both MODULE.bazel and MODULE.bazel.lock" do
        # Mock the BzlmodFileUpdater to return both MODULE.bazel and lockfile updates
        bzlmod_updater = instance_double(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater)
        allow(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater).to receive(:new).and_return(bzlmod_updater)

        module_file = Dependabot::DependencyFile.new(
          name: "MODULE.bazel",
          content: module_file_content.sub('version = "0.1.1"', 'version = "0.2.0"')
        )
        lockfile = Dependabot::DependencyFile.new(
          name: "MODULE.bazel.lock",
          content: updated_lockfile_content
        )

        allow(bzlmod_updater).to receive(:updated_module_files).and_return([module_file, lockfile])

        updated_files = file_updater.updated_dependency_files

        expect(updated_files.count).to eq(2)

        module_file = updated_files.find { |f| f.name == "MODULE.bazel" }
        expect(module_file.content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')

        lockfile = updated_files.find { |f| f.name == "MODULE.bazel.lock" }
        expect(lockfile).not_to be_nil
        expect(lockfile.content).to include("rules_cc@0.2.0")
      end
    end

    context "with a MODULE.bazel project without lockfile" do
      let(:dependency_files) { bazel_project_dependency_files("module_needs_lockfile") }

      it "generates new MODULE.bazel.lock" do
        # Create a file_updater with lockfile files to trigger lockfile generation
        dependency_files_with_lockfile = dependency_files + [
          Dependabot::DependencyFile.new(
            name: "MODULE.bazel.lock",
            content: "{}"
          )
        ]

        lockfile_file_updater = described_class.new(
          dependency_files: dependency_files_with_lockfile,
          dependencies: dependencies,
          credentials: credentials
        )

        # Mock the BzlmodFileUpdater to return both MODULE.bazel and lockfile updates
        bzlmod_updater = instance_double(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater)
        allow(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater).to receive(:new).and_return(bzlmod_updater)

        module_file = Dependabot::DependencyFile.new(
          name: "MODULE.bazel",
          content: module_file_content.sub('version = "0.1.1"', 'version = "0.2.0"')
        )
        lockfile = Dependabot::DependencyFile.new(
          name: "MODULE.bazel.lock",
          content: new_lockfile_content
        )

        allow(bzlmod_updater).to receive(:updated_module_files).and_return([module_file, lockfile])

        updated_files = lockfile_file_updater.updated_dependency_files

        expect(updated_files.count).to eq(2)

        module_file = updated_files.find { |f| f.name == "MODULE.bazel" }
        expect(module_file.content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')

        lockfile = updated_files.find { |f| f.name == "MODULE.bazel.lock" }
        expect(lockfile).not_to be_nil
        expect(lockfile.content).to include("rules_cc@0.2.0")
      end
    end

    context "with a WORKSPACE project" do
      let(:dependency_files) { bazel_project_dependency_files("simple_workspace") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "rules_cc",
          version: "v0.2.0",
          previous_version: "v0.1.1",
          requirements: [{
            file: "WORKSPACE",
            requirement: "v0.2.0",
            groups: [],
            source: { type: "http_archive", url: "https://github.com/bazelbuild/rules_cc/archive/v0.2.0.tar.gz" }
          }],
          previous_requirements: [{
            file: "WORKSPACE",
            requirement: "v0.1.1",
            groups: [],
            source: { type: "http_archive", url: "https://github.com/bazelbuild/rules_cc/archive/v0.1.1.tar.gz" }
          }],
          package_manager: "bazel"
        )
      end

      it "does not generate lockfile for WORKSPACE projects" do
        updated_files = file_updater.updated_dependency_files

        # Should only update WORKSPACE, not generate lockfile
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("WORKSPACE")
        expect(updated_files.none? { |f| f.name.end_with?(".lock") }).to be true
      end
    end

    context "when lockfile generation fails" do
      let(:dependency_files) { bazel_project_dependency_files("simple_module_with_lockfile") }

      it "continues with MODULE.bazel updates even if lockfile fails" do
        # Mock the BzlmodFileUpdater to return MODULE.bazel update and empty lockfile
        bzlmod_updater = instance_double(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater)
        allow(Dependabot::Bazel::FileUpdater::BzlmodFileUpdater).to receive(:new).and_return(bzlmod_updater)

        module_file = Dependabot::DependencyFile.new(
          name: "MODULE.bazel",
          content: module_file_content.sub('version = "0.1.1"', 'version = "0.2.0"')
        )
        lockfile = Dependabot::DependencyFile.new(
          name: "MODULE.bazel.lock",
          content: ""
        )

        allow(bzlmod_updater).to receive(:updated_module_files).and_return([module_file, lockfile])

        updated_files = file_updater.updated_dependency_files

        # Should still update MODULE.bazel and create an empty lockfile
        expect(updated_files.count).to eq(2)

        module_file = updated_files.find { |f| f.name == "MODULE.bazel" }
        expect(module_file.content).to include('bazel_dep(name = "rules_cc", version = "0.2.0")')

        lockfile = updated_files.find { |f| f.name == "MODULE.bazel.lock" }
        expect(lockfile.content).to eq("")
      end
    end

    def updated_lockfile_content
      # Sample updated lockfile content with new version
      <<~JSON
        {
          "lockFileVersion": 11,
          "registryFileHashes": {},
          "selectedYankedVersions": {},
          "moduleExtensions": {},
          "moduleDepGraph": {
            "<root>": {
              "name": "my-module",
              "version": "1.0",
              "repoName": "",
              "deps": {
                "rules_cc": "rules_cc@0.2.0",
                "platforms": "platforms@0.0.11",
                "abseil-cpp": "abseil-cpp@20230125.3"
              }
            }
          }
        }
      JSON
    end

    def new_lockfile_content
      # Sample new lockfile content
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
            }
          }
        }
      JSON
    end
  end

  describe "#check_required_files" do
    context "with no MODULE.bazel or WORKSPACE file" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "random.txt", content: "content")]
      end

      it "raises an error" do
        expect { file_updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileNotFound, "No MODULE.bazel or WORKSPACE file found!")
      end
    end
  end
end
