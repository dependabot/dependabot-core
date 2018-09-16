# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_updaters/dotnet/nuget/property_value_updater"

RSpec.describe Dependabot::FileUpdaters::Dotnet::Nuget::PropertyValueUpdater do
  let(:updater) { described_class.new(project_file: project_file) }

  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "my.csproj",
      content: fixture("dotnet", "csproj", csproj_fixture_name)
    )
  end
  let(:csproj_fixture_name) { "property_version.csproj" }

  describe "#update_file_for_property_change" do
    subject(:updated_file) do
      updater.update_file_for_property_change(
        property_name: property_name,
        updated_value: updated_value
      )
    end
    let(:property_name) { "NukeVersion" }
    let(:updated_value) { "0.1.500" }

    it "updates the property" do
      expect(updated_file.content).
        to include("<NukeVersion>0.1.500</NukeVersion>")
      expect(updated_file.content).to include('Version="$(NukeVersion)" />')
    end
  end
end
