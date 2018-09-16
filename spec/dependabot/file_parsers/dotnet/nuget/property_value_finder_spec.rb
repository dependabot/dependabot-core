# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/dotnet/nuget/property_value_finder"

RSpec.describe Dependabot::FileParsers::Dotnet::Nuget::PropertyValueFinder do
  let(:file) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: file_body)
  end
  let(:file_body) { fixture("dotnet", "csproj", "property_version.csproj") }
  let(:finder) { described_class.new(project_file: file) }
  let(:property_name) { "NukeVersion" }

  describe "property_details" do
    subject(:property_details) do
      finder.property_details(property_name: property_name)
    end

    context "with a property that can be found" do
      let(:property_name) { "NukeVersion" }
      its([:value]) { is_expected.to eq("0.1.434") }
    end

    context "with a property that can't be found" do
      let(:property_name) { "UnknownVersion" }
      it { is_expected.to be_nil }
    end
  end
end
