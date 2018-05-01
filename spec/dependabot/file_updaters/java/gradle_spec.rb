# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/file_updaters/java/gradle"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Java::Gradle do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:dependencies) { [dependency] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "co.aikar:acf-paper",
      version: "0.5.0-SNAPSHOT",
      requirements: [{
        file: "build.gradle",
        requirement: "0.6.0-SNAPSHOT",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_requirements: [{
        file: "build.gradle",
        requirement: "0.5.0-SNAPSHOT",
        groups: [],
        source: nil,
        metadata: nil
      }],
      package_manager: "gradle"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated build.gradle file" do
      subject(:updated_buildfile) do
        updated_files.find { |f| f.name == "build.gradle" }
      end

      its(:content) do
        is_expected.to include(
          "compile group: 'co.aikar', name: 'acf-paper', version: "\
          "'0.6.0-SNAPSHOT', changing: true"
        )
      end
      its(:content) { is_expected.to include "version: '4.2.0'" }
    end
  end
end
