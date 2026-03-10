# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/dependency_files_builder"
require "dependabot/shared_helpers"

RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder) do
  let(:builder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "abind",
      version: "1.0.5",
      requirements: [],
      package_manager: "npm_and_yarn"
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
  let!(:dependency_files) { project_dependency_files(project_name) }
  let(:project_name) { "npm6_and_yarn/simple" }

  def project_dependency_file(file_name)
    dependency_files.find { |f| f.name == file_name }
  end

  def dependency_file(name:, content:, directory: "/")
    Dependabot::DependencyFile.new(
      name: name,
      content: content,
      directory: directory
    )
  end

  def with_written_temporary_dependency_files
    Dependabot::SharedHelpers.in_a_temporary_directory do
      expect { builder.write_temporary_dependency_files }.not_to raise_error
      yield
    end
  end

  describe "#write_temporary_dependency_files" do
    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.glob("*")).to match_array(
          %w(package.json package-lock.json yarn.lock)
        )
      end
    end
  end

  describe "yarn berry with a private registry" do
    let(:project_name) { "yarn_berry/yarnrc_global_registry" }

    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.children(".")).to match_array(
          %w(package.json yarn.lock .yarnrc.yml)
        )
      end
    end
  end

  describe "has no lockfile or rc file" do
    let(:project_name) { "npm8/library" }

    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.children(".")).to match_array(
          %w(package.json .npmrc)
        )
        expect(File.read(".npmrc")).to be_empty
      end
    end
  end

  describe "a private registry in a .yarnrc and no yarn.lock" do
    let(:project_name) { "yarn/all_private_global_registry_no_lock" }

    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.children(".")).to match_array(
          %w(package.json .npmrc .yarnrc)
        )
        expect(File.read(".npmrc")).not_to be_empty
      end
    end
  end

  describe "a private registry in a .yarnrc with a configured Dependabot private registry and yarn.lock" do
    let(:project_name) { "yarn/all_private_global_registry" }
    let(:credentials) do
      [Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ), Dependabot::Credential.new(
        {
          "type" => "npm-registry",
          "host" => "https://npm-proxy.fury.io/",
          "username" => "dependabot",
          "password" => "password"
        }
      )]
    end

    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.children(".")).to match_array(
          %w(package.json yarn.lock .npmrc .yarnrc)
        )
      end
    end
  end

  describe "with a pnpm lockfile path that traverses outside the temporary directory" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "../../../../../pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'"
        ),
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}'
        )
      ]
    end

    it "normalizes the lockfile path and writes inside the temporary directory" do
      with_written_temporary_dependency_files do
        expect(Dir.children(".")).to match_array(%w(pnpm-lock.yaml package.json .npmrc))
        expect(File.read("pnpm-lock.yaml")).to eq("lockfileVersion: '9.0'")
      end
    end
  end

  describe "with a package.json path that traverses outside the temporary directory" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "../../../../../package.json",
          content: '{"name":"app","version":"1.0.0"}'
        )
      ]
    end

    it "normalizes package.json and writes it inside the temporary directory" do
      with_written_temporary_dependency_files do
        expect(Dir.children(".")).to match_array(%w(package.json .npmrc))
        expect(File.read("package.json")).to eq('{"name":"app","version":"1.0.0"}')
      end
    end
  end

  describe "with a yarn berry .yarnrc.yml path that traverses outside the temporary directory" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "yarn.lock",
          content: "__metadata:\n  version: 4\n"
        ),
        dependency_file(
          name: "../../../../../.yarnrc.yml",
          content: "nodeLinker: node-modules\n"
        ),
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}'
        )
      ]
    end

    it "normalizes .yarnrc.yml and writes it inside the temporary directory" do
      with_written_temporary_dependency_files do
        expect(Dir.children(".")).to match_array(%w(package.json yarn.lock .yarnrc.yml))
        expect(File.read(".yarnrc.yml")).to eq("nodeLinker: node-modules\n")
      end
    end
  end

  describe "with an absolute-style pnpm lockfile path" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "/pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'"
        ),
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}'
        )
      ]
    end

    it "writes the lockfile inside the temporary directory root" do
      with_written_temporary_dependency_files do
        expect(File.exist?("pnpm-lock.yaml")).to be(true)
        expect(File.read("pnpm-lock.yaml")).to eq("lockfileVersion: '9.0'")
      end
    end
  end

  describe "with pnpm lockfile paths that normalize to the same destination" do
    let(:base_dependency_files) do
      [
        dependency_file(
          name: "../../../../../pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'"
        ),
        dependency_file(
          name: "pnpm-lock.yaml",
          content: "lockfileVersion: '9.1'"
        ),
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}'
        )
      ]
    end
    let(:dependency_files) { base_dependency_files }

    it "writes the normalized destination deterministically" do
      with_written_temporary_dependency_files do
        expect(File.exist?("pnpm-lock.yaml")).to be(true)
        expect(File.read("pnpm-lock.yaml")).to eq("lockfileVersion: '9.1'")
      end
    end

    context "when inputs are reversed" do
      let(:dependency_files) { base_dependency_files.reverse }

      it "writes the same normalized destination deterministically" do
        with_written_temporary_dependency_files do
          expect(File.exist?("pnpm-lock.yaml")).to be(true)
          expect(File.read("pnpm-lock.yaml")).to eq("lockfileVersion: '9.1'")
        end
      end
    end
  end

  describe "with traversal paths in a non-root job directory" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "../pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'",
          directory: "/repo/packages/app"
        ),
        dependency_file(
          name: "./package.json",
          content: '{"name":"app","version":"1.0.0"}',
          directory: "/repo/packages/app"
        )
      ]
    end

    it "normalizes paths relative to the job directory" do
      with_written_temporary_dependency_files do
        expect(File.exist?("../pnpm-lock.yaml")).to be(false)
        expect(Dir.children(".")).to match_array(%w(package.json pnpm-lock.yaml .npmrc))
        expect(File.exist?("pnpm-lock.yaml")).to be(true)
        expect(File.exist?("package.json")).to be(true)
      end
    end
  end

  describe "with different source directories sharing a base" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}',
          directory: "/repo/packages/a"
        ),
        dependency_file(
          name: "pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'",
          directory: "/repo/packages/b"
        )
      ]
    end

    it "writes files relative to the active job directory" do
      with_written_temporary_dependency_files do
        expect(File.exist?("package.json")).to be(true)
        expect(File.exist?("b/pnpm-lock.yaml")).to be(true)
      end
    end
  end

  describe "with source directories that only share root" do
    let(:dependency_files) do
      [
        dependency_file(
          name: "package.json",
          content: '{"name":"app","version":"1.0.0"}',
          directory: "/repo/packages/a"
        ),
        dependency_file(
          name: "pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'",
          directory: "/other/workspaces/b"
        )
      ]
    end

    it "writes files inside the temporary directory without raising" do
      with_written_temporary_dependency_files do
        expect(File.exist?("package.json")).to be(true)
        expect(File.exist?("other/workspaces/b/pnpm-lock.yaml")).to be(true)
      end
    end
  end

  describe "with mixed source directories and varying input ordering" do
    let(:base_dependency_files) do
      [
        dependency_file(
          name: "package.json",
          content: '{"name":"app-a","version":"1.0.0"}',
          directory: "/repo/packages/a"
        ),
        dependency_file(
          name: "pnpm-lock.yaml",
          content: "lockfileVersion: '9.0'",
          directory: "/repo/packages/b"
        )
      ]
    end

    shared_examples "deterministic mixed-directory writes" do
      it "writes files to deterministic paths" do
        with_written_temporary_dependency_files do
          expect(File.read("package.json")).to include('"name":"app-a"')
          expect(File.exist?("b/pnpm-lock.yaml")).to be(true)
        end
      end
    end

    context "when package.json is first" do
      let(:dependency_files) { base_dependency_files }

      it_behaves_like "deterministic mixed-directory writes"
    end

    context "when lockfile is first" do
      let(:dependency_files) { base_dependency_files.reverse }

      it_behaves_like "deterministic mixed-directory writes"
    end
  end

  describe "#package_locks" do
    subject(:test_subject) { builder.package_locks }

    it { is_expected.to contain_exactly(project_dependency_file("package-lock.json")) }
  end

  describe "#yarn_locks" do
    subject(:test_subject) { builder.yarn_locks }

    it { is_expected.to contain_exactly(project_dependency_file("yarn.lock")) }
  end

  describe "#lockfiles" do
    subject(:test_subject) { builder.lockfiles }

    it do
      expect(test_subject).to contain_exactly(
        project_dependency_file("package-lock.json"),
        project_dependency_file("yarn.lock")
      )
    end

    context "with shrinkwraps" do
      let(:project_name) { "npm6/shrinkwrap" }

      it do
        expect(test_subject).to contain_exactly(
          project_dependency_file("package-lock.json"),
          project_dependency_file("npm-shrinkwrap.json")
        )
      end
    end
  end

  describe "#package_files" do
    subject(:test_subject) { builder.package_files }

    it { is_expected.to contain_exactly(project_dependency_file("package.json")) }
  end

  describe "#shrinkwraps" do
    subject(:test_subject) { builder.shrinkwraps }

    let(:project_name) { "npm6/shrinkwrap" }

    it { is_expected.to contain_exactly(project_dependency_file("npm-shrinkwrap.json")) }
  end
end
