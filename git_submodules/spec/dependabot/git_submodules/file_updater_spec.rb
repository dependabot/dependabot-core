# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/git_submodules/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::GitSubmodules::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "sha2",
      previous_version: "sha1",
      requirements: [{
        file: ".gitmodules",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/example/manifesto.git",
          branch: "master",
          ref: "master"
        },
        groups: []
      }],
      previous_requirements: [{
        file: ".gitmodules",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/example/manifesto.git",
          branch: "master",
          ref: "master"
        },
        groups: []
      }],
      package_manager: "submodules"
    )
  end
  let(:submodule) do
    Dependabot::DependencyFile.new(
      content: "sha1",
      name: "manifesto",
      type: "submodule"
    )
  end
  let(:gitmodules) do
    Dependabot::DependencyFile.new(
      content: fixture("gitmodules", ".gitmodules"),
      name: ".gitmodules"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: [gitmodules, submodule],
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    before do
      Dependabot::Experiments.register(:allowlist_dependency_files, true)
    end

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          ".gitmodules",
          "submodule/.git",
          ".git/modules/submodule/config",
          ".git/modules/another/config"
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

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated file" do
      subject(:updated_submodule) { updated_files.first }

      its(:name) { is_expected.to eq("manifesto") }
      its(:content) { is_expected.to eq("sha2") }
      its(:type) { is_expected.to eq("submodule") }
    end
  end
end
