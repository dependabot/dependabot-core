# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser/property_value_finder"

RSpec.describe Dependabot::Nuget::FileParser::PropertyValueFinder do
  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("csproj", csproj_fixture_name) }
  let(:csproj_fixture_name) { "property_version.csproj" }
  let(:finder) { described_class.new(dependency_files: files) }
  let(:files) { [file] }
  let(:property_name) { "NukeVersion" }

  describe "property_details" do
    subject(:property_details) do
      finder.property_details(property_name: property_name, callsite_file: file)
    end

    context "with a property that can be found" do
      let(:property_name) { "NukeVersion" }
      its([:value]) { is_expected.to eq("0.1.434") }
      its([:file]) { is_expected.to eq("my.csproj") }
      its([:root_property_name]) { is_expected.to eq("NukeVersion") }

      context "but which calls another property" do
        let(:csproj_fixture_name) { "property_version_indirect.csproj" }
        let(:property_name) { "IndirectNukeVersion" }
        its([:value]) { is_expected.to eq("0.1.434") }
        its([:file]) { is_expected.to eq("my.csproj") }
        its([:root_property_name]) { is_expected.to eq("NukeVersion") }

        context "leading to an infinite loop" do
          let(:property_name) { "LoopOne" }

          # For now we should manually investigate if this ever happens
          it "raises" do
            expect { property_details }.to raise_error("Circular reference!")
          end
        end
      end
    end

    context "with a property that can't be found" do
      let(:property_name) { "UnknownVersion" }
      it { is_expected.to be_nil }
    end

    context "with a property that calls a function" do
      let(:property_name) { "FunctionVersion" }
      it { is_expected.to be_nil }
    end

    context "from a directory.build.props file" do
      let(:files) { [file, build_file, imported_file] }

      let(:file) do
        Dependabot::DependencyFile.new(
          name: "nested/my.csproj",
          content: file_body
        )
      end
      let(:file_body) { fixture("csproj", "property_version.csproj") }
      let(:build_file) do
        Dependabot::DependencyFile.new(
          name: "Directory.Build.props",
          content: build_file_body
        )
      end
      let(:build_file_body) { fixture("property_files", "imports") }
      let(:imported_file) do
        Dependabot::DependencyFile.new(
          name: "build/dependencies.props",
          content: imported_file_body
        )
      end
      let(:imported_file_body) do
        fixture("property_files", "dependency.props")
      end

      let(:property_name) { "XunitPackageVersion" }

      its([:value]) { is_expected.to eq("2.3.1") }
      its([:file]) { is_expected.to eq("build/dependencies.props") }
      its([:root_property_name]) { is_expected.to eq("XunitPackageVersion") }
    end
  end
end
