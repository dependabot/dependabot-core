# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/nuget/file_updater/property_value_updater"

RSpec.describe Dependabot::Nuget::FileUpdater::PropertyValueUpdater do
  let(:updater) { described_class.new(dependency_files: files) }
  let(:files) { [project_file] }

  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "my.csproj",
      content: fixture("csproj", csproj_fixture_name)
    )
  end
  let(:csproj_fixture_name) { "property_version.csproj" }

  describe "#update_files_for_property_change" do
    subject(:updated_files) do
      updater.update_files_for_property_change(
        property_name: property_name,
        updated_value: updated_value,
        callsite_file: project_file
      )
    end
    let(:property_name) { "NukeVersion" }
    let(:updated_value) { "0.1.500" }

    it "updates the property" do
      expect(updated_files.first.content).
        to include("<NukeVersion>0.1.500</NukeVersion>")
      expect(updated_files.first.content).
        to include('Version="$(NukeVersion)" />')
    end

    context "when the property is inherited" do
      let(:files) { [project_file, build_file, imported_file] }

      let(:project_file) do
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

      it "updates the property" do
        expect(updated_files.count).to eq(3)

        changed_files = updated_files - files
        expect(changed_files.count).to eq(1)

        changed_file = changed_files.first

        expect(changed_file.name).to eq("build/dependencies.props")
        expect(changed_file.content).
          to include("<XunitPackageVersion>0.1.500</XunitPackageVersion>")
      end
    end
  end
end
