# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/cake/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Cake::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end
  let(:dependencies) { [dependency, other_dependency] }
  let(:dependency_files) { [cake_file] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:cake_file) do
    Dependabot::DependencyFile.new(
      content: cake_file_body,
      name: "build.cake"
    )
  end
  let(:cake_file_body) { fixture("cake_files", "multiple_directives") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Cake.Addin",
      version: "1.3.56",
      previous_version: "1.2.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "build.cake",
        source: nil
      }],
      previous_requirements: [{
        requirement: "1.2.0",
        groups: [],
        file: "build.cake",
        source: nil,
        metadata: { directive: { type: "addin", scheme: "nuget", url: nil } }
      }],
      package_manager: "cake"
    )
  end
  let(:other_dependency) do
    Dependabot::Dependency.new(
      name: "Cake.Tool",
      version: "2.0.2",
      previous_version: "2.0.1",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "build.cake",
        source: nil
      }],
      previous_requirements: [{
        requirement: "2.0.1",
        groups: [],
        file: "build.cake",
        source: nil,
        metadata: { directive: { type: "addin", scheme: "nuget", url: nil } }
      }],
      package_manager: "cake"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated cake_file" do
      subject(:updated_cake_file) do
        updated_files.find { |f| f.name == "build.cake" }
      end

      # rubocop:disable Layout/LineLength
      its(:content) { is_expected.to include "#module nuget:?package=Cake.Module&version=0.1.0\n" }
      its(:content) { is_expected.to include "#addin nuget:?package=Cake.Addin&version=1.3.56\n" }
      its(:content) { is_expected.to include "#tool nuget:?package=Cake.Tool&version=2.0.2\n" }
      # rubocop:enable Layout/LineLength
    end
  end
end
