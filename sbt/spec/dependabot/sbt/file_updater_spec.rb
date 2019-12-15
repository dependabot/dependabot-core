# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/sbt/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Sbt::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:dependencies) { [dependency] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.sbt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.mutabilitydetector:MutabilityDetector",
      version: "0.10.2",
      requirements: [{
        file: "build.sbt",
        requirement: "0.10.2",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_requirements: [{
        file: "build.sbt",
        requirement: "0.9.4-SNAPSHOT",
        groups: [],
        source: nil,
        metadata: {
          cross_scala_versions: []
        }
      }],
      package_manager: "sbt"
    )
  end

  describe "the updated build.sbt file" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    subject(:updated_buildfile) do
      updated_files.find { |f| f.name == "build.sbt" }
    end

    its(:content) do
      is_expected.to include(
        "libraryDependencies += \"org.mutabilitydetector\" % "\
        "\"MutabilityDetector\" % \"0.10.2\" % \"test\""
      )
    end
    its(:content) do
      is_expected.to include(
        "libraryDependencies += \"junit\" % \"junit-dep\" % \"4.11\" % \"test\""
      )
    end
  end

  describe "cross build scala versions" do
    let(:buildfile_fixture_name) { "cross_scala_version_build.sbt" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.scalatest:scalatest_2.11",
        version: "2.2.5",
        requirements: [{
          file: "build.sbt",
          requirement: "2.2.6",
          groups: [],
          source: nil,
          metadata: nil
        }],
        previous_requirements: [{
          file: "build.sbt",
          requirement: "2.2.5",
          groups: [],
          source: nil,
          metadata: {
            cross_scala_versions: ["2.11"]
          }
        }],
        package_manager: "sbt"
      )
    end

    subject(:updated_files) { updater.updated_dependency_files }

    subject(:updated_buildfile) do
      updated_files.find { |f| f.name == "build.sbt" }
    end

    its(:content) do
      is_expected.to include(
        "libraryDependencies += \"org.scalatest\" %% \"scalatest\" % "\
          "\"2.2.6\" % \"test\""
      )
    end
  end
end
