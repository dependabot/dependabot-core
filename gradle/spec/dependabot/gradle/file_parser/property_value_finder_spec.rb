# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/gradle/file_parser/property_value_finder"

RSpec.describe Dependabot::Gradle::FileParser::PropertyValueFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "single_property_build.gradle" }

  describe "#property_details" do
    subject(:property_details) do
      finder.property_details(
        property_name: property_name,
        callsite_buildfile: callsite_buildfile
      )
    end

    context "with a single buildfile" do
      context "when the property is declared in the calling buildfile" do
        let(:buildfile_fixture_name) { "single_property_build.gradle" }
        let(:property_name) { "kotlin_version" }
        let(:callsite_buildfile) { buildfile }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:declaration_string]) do
          is_expected.to eq("ext.kotlin_version = '1.1.4-3'")
        end
        its([:file]) { is_expected.to eq("build.gradle") }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("build.gradle") }
        end

        context "and the property name has a `rootProject.` prefix" do
          let(:property_name) { "rootProject.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("build.gradle") }
        end

        context "and tricky properties" do
          let(:buildfile_fixture_name) { "properties.gradle" }

          context "and the property is declared with ext.name" do
            let(:property_name) { "kotlin_version" }
            its([:value]) { is_expected.to eq("1.2.61") }
            its([:declaration_string]) do
              is_expected.to eq("ext.kotlin_version = '1.2.61'")
            end
          end

          context "and the property is declared in an ext block" do
            let(:property_name) { "buildToolsVersion" }
            its([:value]) { is_expected.to eq("27.0.3") }
            its([:declaration_string]) do
              is_expected.to eq("buildToolsVersion = '27.0.3'")
            end
          end

          context "and the property is preceded by a comment" do
            # This is important because the declaration string must not include
            # whitespace that will be different to when the FileUpdater uses it
            # (i.e., before the comments are stripped out)
            let(:property_name) { "supportVersion" }
            its([:value]) { is_expected.to eq("27.1.1") }
            its([:declaration_string]) do
              is_expected.to eq("supportVersion = '27.1.1'")
            end
          end

          context "and the property is commented out" do
            let(:property_name) { "commentedVersion" }
            it { is_expected.to be_nil }
          end

          context "and the property is declared within a namespace" do
            let(:buildfile_fixture_name) { "properties_namespaced.gradle" }
            let(:property_name) { "versions.okhttp" }

            its([:value]) { is_expected.to eq("3.12.1") }
            its([:declaration_string]) do
              is_expected.to eq("okhttp                 : '3.12.1'")
            end
          end
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
          content: fixture("buildfiles", callsite_fixture_name)
        )
      end
      let(:callsite_fixture_name) { "basic_build.gradle" }

      its([:value]) { is_expected.to eq("1.1.4-3") }
      its([:file]) { is_expected.to eq("build.gradle") }

      context "and the property name has a `project.` prefix" do
        let(:property_name) { "project.kotlin_version" }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:file]) { is_expected.to eq("build.gradle") }
      end

      context "and the property name has a `rootProject.` prefix" do
        let(:property_name) { "rootProject.kotlin_version" }
        its([:value]) { is_expected.to eq("1.1.4-3") }
        its([:file]) { is_expected.to eq("build.gradle") }
      end

      context "with a property that only appears in the callsite buildfile" do
        let(:buildfile_fixture_name) { "basic_build.gradle" }
        let(:callsite_fixture_name) { "single_property_build.gradle" }

        context "and the property name has a `project.` prefix" do
          let(:property_name) { "project.kotlin_version" }
          its([:value]) { is_expected.to eq("1.1.4-3") }
          its([:file]) { is_expected.to eq("myapp/build.gradle") }
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
