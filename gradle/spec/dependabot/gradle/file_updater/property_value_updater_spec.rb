# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/gradle/file_updater/property_value_updater"

RSpec.describe Dependabot::Gradle::FileUpdater::PropertyValueUpdater do
  let(:updater) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile, subproject_buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:subproject_buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", subproject_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "shortform_build.gradle" }
  let(:subproject_fixture_name) { "basic_build.gradle" }

  describe "update_files_for_property_change" do
    subject(:updated_files) do
      updater.update_files_for_property_change(
        callsite_buildfile: callsite_buildfile,
        property_name: property_name,
        previous_value: previous_value,
        updated_value: updated_value
      )
    end

    let(:callsite_buildfile) { buildfile }
    let(:property_name) { "kotlin_version" }
    let(:previous_value) { "1.1.4-3" }
    let(:updated_value) { "3.2.1" }

    its(:length) { is_expected.to eq(2) }

    it "updates the files correctly" do
      expect(updated_files.last).to eq(dependency_files.last)
      expect(updated_files.first.content).
        to include("ext.kotlin_version = '3.2.1'")
    end

    context "when updating from a substring to the same value" do
      let(:previous_value) { "1.1.4" }
      let(:updated_value) { "1.1.4-3" }

      it "leaves the files alone" do
        expect(updated_files.last).to eq(dependency_files.last)
        expect(updated_files.first.content).
          to include("ext.kotlin_version = '1.1.4-3'")
      end
    end
  end
end
