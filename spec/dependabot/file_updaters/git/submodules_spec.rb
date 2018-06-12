# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/git/submodules"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Git::Submodules do
  it_behaves_like "a dependency file updater"

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
  let(:gitmodules) do
    Dependabot::DependencyFile.new(
      content: fixture("git", "gitmodules", ".gitmodules"),
      name: ".gitmodules"
    )
  end
  let(:submodule) do
    Dependabot::DependencyFile.new(
      content: "sha1",
      name: "manifesto",
      type: "submodule"
    )
  end

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
