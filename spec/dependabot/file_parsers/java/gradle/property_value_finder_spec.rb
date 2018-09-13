# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/gradle/property_value_finder"

RSpec.describe Dependabot::FileParsers::Java::Gradle::PropertyValueFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "single_property_build.gradle" }

  describe "#property_value" do
    subject(:property_value) do
      finder.property_value(
        property_name: property_name,
        callsite_buildfile: callsite_buildfile
      )
    end

    context "with a single buildfile" do
      context "when the property is declared in the calling buildfile" do
        let(:buildfile_fixture_name) { "single_property_build.gradle" }
        let(:property_name) { "kotlin_version" }
        let(:callsite_buildfile) { buildfile }
        it { is_expected.to eq("1.1.4-3") }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          it { is_expected.to eq("1.1.4-3") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlin_version" }
          it { is_expected.to eq("1.1.4-3") }
        end
      end
    end

    context "with multiple buildfiles" do
      let(:dependency_files) { [buildfile, callsite_buildfile] }
      let(:buildfile_fixture_name) { "single_property_build.gradle" }
      let(:property_name) { "kotlin_version" }
      let(:callsite_buildfile) do
        Dependabot::DependencyFile.new(
          name: "myapp/build.gradle",
          content: fixture("java", "buildfiles", callsite_fixture_name)
        )
      end
      let(:callsite_fixture_name) { "basic_build.gradle" }

      it { is_expected.to eq("1.1.4-3") }

      context "and the property name has a `project.` prefix" do
        let(:property_name) { "project.kotlin_version" }
        it { is_expected.to eq("1.1.4-3") }
      end

      context "and the property name has a `rootProject.` prefix" do
        let(:property_name) { "rootProject.kotlin_version" }
        it { is_expected.to eq("1.1.4-3") }
      end

      context "with a property that only appears in the callsite buildfile" do
        let(:buildfile_fixture_name) { "basic_build.gradle" }
        let(:callsite_fixture_name) { "single_property_build.gradle" }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          it { is_expected.to eq("1.1.4-3") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlin_version" }
          # We wouldn't normally expect this to be `nil` - it's more likely to
          # be another version specified in the root project file.
          it { is_expected.to be_nil }
        end
      end
    end
  end
end
