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
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let!(:dependency_files) { [package_json, npm_lock, yarn_lock, shrinkwrap] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", "package.json")
    )
  end
  let(:manifest_fixture_name) {}
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", "package-lock.json")
    )
  end

  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("yarn_lockfiles", "yarn.lock")
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

  let(:shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: fixture("npm_lockfiles", "package-lock.json")
    )
  end

  describe "#write_temporary_dependency_files" do
    it "writes the relevant files to disk" do
      Dependabot::SharedHelpers.in_a_temporary_directory do
        builder.write_temporary_dependency_files

        expect(Dir.glob("*")).to match_array(
          %w(package.json package-lock.json yarn.lock npm-shrinkwrap.json)
        )
      end
    end
  end

  describe "#package_locks" do
    let(:subject) { builder.package_locks }
    it { is_expected.to match_array([npm_lock]) }
  end

  describe "#yarn_locks" do
    let(:subject) { builder.yarn_locks }
    it { is_expected.to match_array([yarn_lock]) }
  end

  describe "#lockfiles" do
    let(:subject) { builder.lockfiles }
    it { is_expected.to match_array([npm_lock, yarn_lock, shrinkwrap]) }
  end

  describe "#package_files" do
    let(:subject) { builder.package_files }
    it { is_expected.to match_array([package_json]) }
  end

  describe "#shrinkwraps" do
    let(:subject) { builder.shrinkwraps }
    it { is_expected.to match_array([shrinkwrap]) }
  end
end
