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

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let!(:dependency_files) { project_dependency_files(project_name) }
  let(:project_name) { "npm6_and_yarn/simple" }

  before do
    Dependabot::Experiments.register(:yarn_berry, true)
  end

  def project_dependency_file(file_name)
    dependency_files.find { |f| f.name == file_name }
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "abind",
      version: "1.0.5",
      requirements: [],
      package_manager: "npm_and_yarn"
    )
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
        expect(File.empty?(".npmrc"))
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
        expect(File.empty?(".npmrc"))
      end
    end
  end

  describe "a private registry in a .yarnrc with a configured Dependabot private registry and yarn.lock" do
    let(:project_name) { "yarn/all_private_global_registry" }
    let(:credentials) do
      [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }, {
        "type" => "npm-registry",
        "host" => "https://npm-proxy.fury.io/",
        "username" => "dependabot",
        "password" => "password"
      }]
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

  describe "#package_locks" do
    let(:subject) { builder.package_locks }
    it { is_expected.to match_array([project_dependency_file("package-lock.json")]) }
  end

  describe "#yarn_locks" do
    let(:subject) { builder.yarn_locks }
    it { is_expected.to match_array([project_dependency_file("yarn.lock")]) }
  end

  describe "#lockfiles" do
    let(:subject) { builder.lockfiles }
    it do
      is_expected.to match_array(
        [
          project_dependency_file("package-lock.json"),
          project_dependency_file("yarn.lock")
        ]
      )
    end

    context "with shrinkwraps" do
      let(:project_name) { "npm6/shrinkwrap" }

      it do
        is_expected.to match_array(
          [
            project_dependency_file("package-lock.json"),
            project_dependency_file("npm-shrinkwrap.json")
          ]
        )
      end
    end
  end

  describe "#package_files" do
    let(:subject) { builder.package_files }
    it { is_expected.to match_array([project_dependency_file("package.json")]) }
  end

  describe "#shrinkwraps" do
    let(:project_name) { "npm6/shrinkwrap" }
    let(:subject) { builder.shrinkwraps }
    it { is_expected.to match_array([project_dependency_file("npm-shrinkwrap.json")]) }
  end
end
