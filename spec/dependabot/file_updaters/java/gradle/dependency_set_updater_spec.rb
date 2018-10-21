# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java/gradle/dependency_set_updater"

RSpec.describe Dependabot::FileUpdaters::Java::Gradle::DependencySetUpdater do
  let(:updater) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile, irrelevant_file] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:irrelevant_file) do
    Dependabot::DependencyFile.new(
      name: "nested/build.gradle",
      content: fixture("java", "buildfiles", "basic_build.gradle")
    )
  end

  let(:buildfile_fixture_name) { "dependency_set.gradle" }

  describe "update_files_for_dep_set_change" do
    subject(:updated_files) do
      updater.update_files_for_dep_set_change(
        buildfile: callsite_buildfile,
        dependency_set: dependency_set,
        previous_requirement: previous_requirement,
        updated_requirement: updated_requirement
      )
    end

    let(:callsite_buildfile) { buildfile }
    let(:dependency_set) { { group: "com.google.protobuf", version: "3.6.1" } }
    let(:previous_requirement) { "3.6.1" }
    let(:updated_requirement) { "4.0.0" }

    its(:length) { is_expected.to eq(2) }

    it "updates the files correctly" do
      expect(updated_files.last).to eq(dependency_files.last)
      expect(updated_files.first.content).
        to include(
          "dependencySet(group: 'com.google.protobuf', version: '4.0.0') {"
        )
    end
  end
end
